-- ============================================================
--  VelosOS  |  modules/modem.lua
--  Comunicacion por rednet entre vehiculos y con
--  computadoras remotas (ej. tank remoto).
--
--  PROTOCOLO:
--    Canal de escucha: "velosOS"
--    Mensajes son tablas serializadas con { type, data, sender }
--
--  TIPOS DE MENSAJE:
--    "tank_data"    : datos de un tank remoto
--    "ping"         : solicitud de estado
--    "pong"         : respuesta a ping con nombre del vehiculo
--    "alert"        : alerta critica de otro vehiculo
-- ============================================================

local modem_mod = {}

local PROTOCOL   = "velosOS"
local _modem     = nil
local _modemSide = nil
local _open      = false

-- Datos remotos recibidos
-- { sender -> { type, data, time } }
local _remoteTanks   = {}   -- tanks recibidos de otras computadoras
local _knownVehicles = {}   -- vehiculos que respondieron ping
local _alerts        = {}   -- alertas recibidas

-- ============================================================
--  Init — abrir rednet
-- ============================================================
function modem_mod.init()
  local entries = detector.getByType("modem")
  for name, e in pairs(entries) do
    _modem     = e.periph
    _modemSide = name
    break
  end

  if not _modem then return false end

  -- Abrir rednet en el lado del modem
  local ok = pcall(function()
    rednet.open(_modemSide)
  end)
  _open = ok
  return ok
end

function modem_mod.isOpen()
  return _open
end

-- ============================================================
--  Enviar mensaje a todos (broadcast) o a un ID especifico
-- ============================================================
local function send(msg, targetId)
  if not _open then return false end
  local payload = textutils.serialise({
    type   = msg.type,
    data   = msg.data,
    sender = os.getComputerLabel() or tostring(os.getComputerID()),
  })
  local ok
  if targetId then
    ok = pcall(function() rednet.send(targetId, payload, PROTOCOL) end)
  else
    ok = pcall(function() rednet.broadcast(payload, PROTOCOL) end)
  end
  return ok
end

-- ============================================================
--  Procesar mensaje recibido
--  Llamar desde el event loop con ev=="rednet_message"
-- ============================================================
function modem_mod.onMessage(senderId, rawMsg)
  local ok, msg = pcall(function() return textutils.unserialise(rawMsg) end)
  if not ok or type(msg) ~= "table" then return end

  local now = os.epoch("utc") / 1000

  if msg.type == "tank_data" and msg.data then
    -- Tank remoto: guardar datos indexados por sender
    _remoteTanks[msg.sender] = {
      tanks  = msg.data,
      time   = now,
      sender = msg.sender,
      id     = senderId,
    }

  elseif msg.type == "ping" then
    -- Responder con nuestro nombre
    local name = sublevel.getName() or
                 os.getComputerLabel() or
                 "Vehiculo-" .. os.getComputerID()
    send({ type="pong", data={ name=name } }, senderId)

  elseif msg.type == "pong" and msg.data then
    _knownVehicles[msg.sender] = {
      name = msg.data.name,
      id   = senderId,
      time = now,
    }

  elseif msg.type == "alert" and msg.data then
    table.insert(_alerts, {
      sender  = msg.sender,
      text    = msg.data.text or "Alerta",
      time    = now,
    })
    -- Mantener solo las ultimas 5 alertas
    while #_alerts > 5 do table.remove(_alerts, 1) end
    -- Notificar al speaker si hay misil
    if msg.data.text and msg.data.text:find("MISIL") then
      pcall(function() speaker.missilWarning() end)
    end
  end
end

-- ============================================================
--  Limpiar datos viejos (llamar periodicamente)
-- ============================================================
function modem_mod.cleanup()
  local now     = os.epoch("utc") / 1000
  local TIMEOUT = 10   -- segundos sin datos = considerado offline

  for sender, entry in pairs(_remoteTanks) do
    if now - entry.time > TIMEOUT then
      _remoteTanks[sender] = nil
    end
  end
  for sender, entry in pairs(_knownVehicles) do
    if now - entry.time > 30 then
      _knownVehicles[sender] = nil
    end
  end
end

-- ============================================================
--  Transmitir nuestros datos de tanks a la red
--  (para que una computadora remota junto al tank
--   pueda enviarlos de vuelta al vehiculo)
-- ============================================================
function modem_mod.broadcastStatus()
  if not _open then return end
  local name = sublevel.getName() or "?"
  send({
    type = "pong",
    data = { name = name },
  })
end

-- ============================================================
--  Enviar alerta a toda la red
-- ============================================================
function modem_mod.broadcastAlert(text)
  if not _open then return end
  send({ type="alert", data={ text=text } })
end

-- ============================================================
--  Ping a todos los vehiculos en la red
-- ============================================================
function modem_mod.ping()
  if not _open then return end
  send({ type="ping", data={} })
end

-- ============================================================
--  Getters
-- ============================================================
function modem_mod.getRemoteTanks()
  return _remoteTanks
end

function modem_mod.getKnownVehicles()
  return _knownVehicles
end

function modem_mod.getAlerts()
  return _alerts
end

-- ============================================================
--  Render en HUD — tanks remotos + vehiculos conocidos
-- ============================================================
function modem_mod.renderAll(t, x, y, w, h)
  local useC  = t.color
  local col   = useC and colors.cyan      or nil
  local dim   = useC and colors.lightGray or nil
  local norm  = useC and colors.white     or nil
  local line  = y

  if not _open then
    writeLine(t, x, line, "-- RED --", w, col)         line=line+1
    writeLine(t, x, line, " Modem sin inicializar", w, dim)
    return
  end

  -- Vehiculos conocidos en red
  writeLine(t, x, line, "-- RED VELOSNET --", w, col) line=line+1
  local vCount = 0
  for _, v in pairs(_knownVehicles) do
    if line - y >= h then break end
    writeLine(t, x, line,
      string.format(" [V] %s (ID:%d)", v.name, v.id), w, norm)
    line = line + 1; vCount = vCount + 1
  end
  if vCount == 0 then
    writeLine(t, x, line, " Sin vehiculos en red", w, dim) line=line+1
  end

  if line - y >= h then return end
  line = line + 1

  -- Tanks remotos
  writeLine(t, x, line, "-- TANKS REMOTOS --", w, col) line=line+1
  local now = os.epoch("utc") / 1000
  local tCount = 0
  for sender, entry in pairs(_remoteTanks) do
    if line - y >= h then break end
    local age    = math.floor(now - entry.time)
    local status = age > 5 and " [!]" or ""
    writeLine(t, x, line,
      string.format(" [T] %s%s", sender, status), w,
      useC and (age > 5 and colors.orange or colors.lime) or nil)
    line = line + 1

    -- Mostrar cada tank recibido
    if entry.tanks then
      for _, tk in ipairs(entry.tanks) do
        if line - y >= h then break end
        local pctStr = string.format("%3d%%", math.floor((tk.pct or 0) * 100))
        local barW   = w - #pctStr - 3
        local bar    = renderer.progressBar(tk.pct or 0, barW)
        writeLine(t, x, line,
          "  " .. bar .. " " .. pctStr, w,
          useC and renderer.alertColor(tk.pct or 0, true) or nil)
        line = line + 1
      end
    end
    tCount = tCount + 1
  end
  if tCount == 0 then
    writeLine(t, x, line, " Sin tanks remotos", w, dim)
    line = line + 1
  end

  -- Alertas recibidas
  if #_alerts > 0 and (line - y) < h then
    line = line + 1
    writeLine(t, x, line, "-- ALERTAS RED --", w, col) line=line+1
    for i = #_alerts, math.max(1, #_alerts - 2), -1 do
      if line - y >= h then break end
      local a = _alerts[i]
      writeLine(t, x, line,
        string.format(" %s: %s", a.sender, a.text), w,
        useC and colors.orange or nil)
      line = line + 1
    end
  end
end

function modem_mod.heightNeeded()
  local base = 6
  local vCount = 0; for _ in pairs(_knownVehicles) do vCount = vCount + 1 end
  local tCount = 0; for _ in pairs(_remoteTanks)   do tCount = tCount + 1 end
  return base + vCount + (tCount * 3)
end

return modem_mod
