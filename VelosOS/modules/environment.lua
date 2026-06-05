-- ============================================================
--  VelosOS  |  modules/environment.lua
--  Datos de entorno via environmentDetector (Adv. Peripherals)
--  y complementos de aero API de Sable
-- ============================================================

local environment = {}

local _periph = nil

-- Cache para no leer cada frame (el envDet es lento)
local _cache     = {}
local _cacheTime = 0
local CACHE_TTL  = 2.0   -- segundos entre lecturas

-- ============================================================
--  Init
-- ============================================================
function environment.init()
  local entries = detector.getByType("environment")
  for _, e in pairs(entries) do
    _periph = e.periph
    break
  end
  return _periph ~= nil
end

function environment.isAvailable()
  return _periph ~= nil
end

-- ============================================================
--  Lectura con cache
-- ============================================================
local function read()
  local now = os.epoch("utc") / 1000
  if now - _cacheTime < CACHE_TTL and next(_cache) then
    return _cache
  end

  local data = {}

  if _periph then
    -- Clima
    local ok1, isRain  = pcall(function() return _periph.isRaining()      end)
    local ok2, isThund = pcall(function() return _periph.isThundering()   end)
    local ok3, biome   = pcall(function() return _periph.getBiome()       end)
    local ok4, light   = pcall(function() return _periph.getLightLevel()  end)
    local ok5, temp    = pcall(function() return _periph.getTemperature()  end)
    local ok6, humid   = pcall(function() return _periph.getHumidity()    end)

    data.isRaining    = ok1 and isRain  or false
    data.isThundering = ok2 and isThund or false
    data.biome        = ok3 and biome   or "Desconocido"
    data.light        = ok4 and light   or 0
    data.temperature  = ok5 and temp    or nil
    data.humidity     = ok6 and humid   or nil

    -- Limpiar nombre del bioma (quitar namespace)
    if data.biome then
      data.biome = data.biome:match(":(.+)$") or data.biome
      data.biome = data.biome:gsub("_", " ")
      data.biome = data.biome:sub(1,1):upper() .. data.biome:sub(2)
    end
  end

  -- Hora del mundo (siempre disponible via os.time())
  local worldTime = os.time()
  data.timeStr    = textutils.formatTime(worldTime, false)  -- 12h
  data.timeStr24  = textutils.formatTime(worldTime, true)   -- 24h
  data.isDaytime  = worldTime >= 6 and worldTime < 18

  -- Datos de atmosfera de Sable (ya disponibles sin periferico)
  local pose    = sublevel.getLogicalPose()
  local posVec  = vector.new(pose.position.x, pose.position.y, pose.position.z)
  local ok7, pressure = pcall(function() return aero.getAirPressure(posVec) end)
  local ok8, gravity  = pcall(function() return aero.getGravity() end)
  local ok9, drag     = pcall(function() return aero.getUniversalDrag() end)

  data.pressure = ok7 and pressure or 0
  data.gravity  = ok8 and math.abs(gravity.y) or 9.8
  data.drag     = ok9 and drag or 0

  _cache     = data
  _cacheTime = now
  return data
end

-- ============================================================
--  Render en HUD
--  Retorna lineas usadas
-- ============================================================
function environment.draw(t, x, y, w)
  local data = read()
  local useC = t.color
  local col  = useC and colors.cyan      or nil
  local dim  = useC and colors.lightGray or nil
  local norm = useC and colors.white     or nil
  local line = y

  local function wl(text, fg)
    local available = w - x + 1
    text = text .. string.rep(" ", math.max(0, available - #text))
    text = text:sub(1, available)
    if fg then t.term.setTextColor(fg) end
    t.term.setBackgroundColor(colors.black)
    t.term.setCursorPos(x, line)
    t.term.write(text)
    line = line + 1
  end

  wl("-- ENTORNO --", col)

  -- Hora
  local dayIcon = data.isDaytime and "Sol" or "Luna"
  wl(string.format(" Hora:  %s  (%s)", data.timeStr24, dayIcon), norm)

  -- Bioma
  if _periph then
    wl(string.format(" Bioma: %s", data.biome or "?"), dim)

    -- Clima
    local climaStr, climaFg
    if data.isThundering then
      climaStr = "Tormenta electrica"
      climaFg  = useC and colors.red or nil
    elseif data.isRaining then
      climaStr = "Lloviendo"
      climaFg  = useC and colors.lightBlue or nil
    else
      climaStr = "Despejado"
      climaFg  = useC and colors.lime or nil
    end
    wl(" Clima: " .. climaStr, climaFg)

    -- Luz
    local lightFg = useC and (data.light < 4 and colors.orange or colors.lightGray) or nil
    wl(string.format(" Luz:   %d/15", data.light), lightFg)

    -- Temperatura y humedad si estan disponibles
    if data.temperature then
      wl(string.format(" Temp:  %.1f", data.temperature), dim)
    end
  end

  line = line + 1
  wl("-- ATMOSFERA --", col)
  wl(string.format(" Presion: %.1f kPa", data.pressure), dim)
  wl(string.format(" Gravedad: %.2f  Drag: %.3f", data.gravity, data.drag), dim)

  return line - y
end

function environment.heightNeeded()
  local base = 10   -- hora + bioma + clima + luz + separador + atmosfera (3)
  if not _periph then base = 6 end
  return base
end

-- Getter para otras partes del OS (ej. alertas de tormenta)
function environment.getData()
  return read()
end

return environment
