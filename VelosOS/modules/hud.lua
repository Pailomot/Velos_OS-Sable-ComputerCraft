-- ============================================================
--  VelosOS  |  modules/hud.lua
--  Loop principal del HUD. Lee datos de Sable, dibuja el
--  layout adaptativo y despacha modulos opcionales.
-- ============================================================

local REFRESH_HZ  = 0.25   -- segundos entre updates del HUD
local NOTIFY_TIME = 4      -- segundos que dura una notificacion

-- Cola de notificaciones { text, color, expires }
local _notifs = {}

-- ============================================================
--  Helpers de fisica
-- ============================================================

-- Magnitud de un vector de velocidad
local function speed(v)
  return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
end

-- Convierte quaternion a pitch/yaw/roll en grados
-- Usa la API quaternion de CC: Advanced Math (bundled con Sable)
local function quatToEuler(q)
  local ok, p, y, r = pcall(function()
    return q:toEuler()
  end)
  if ok then
    -- toEuler devuelve radianes, convertir a grados
    return math.deg(p), math.deg(y), math.deg(r)
  end
  return 0, 0, 0
end

-- Heading en texto (16 puntos cardinales)
local CARDINALS = {"N","NNE","NE","ENE","E","ESE","SE","SSE",
                   "S","SSO","SO","OSO","O","ONO","NO","NNO"}
local function yawToCardinal(yaw)
  -- Normalizar 0-360
  yaw = yaw % 360
  if yaw < 0 then yaw = yaw + 360 end
  local idx = math.floor((yaw + 11.25) / 22.5) % 16 + 1
  return CARDINALS[idx]
end

-- Barra de horizonte artificial (pitch + roll) en ASCII
local function horizonBar(pitch, roll, width)
  -- Indicador simple: muestra inclinacion lateral con el simbolo
  local center = math.floor(width / 2)
  local rollOffset = math.floor(roll / 10)  -- cada 10 grados = 1 char
  rollOffset = math.max(-(center-2), math.min(center-2, rollOffset))

  local bar = string.rep("-", width)
  local pos = center + rollOffset
  -- Reemplazar caracter central con indicador
  bar = bar:sub(1, pos-1) .. "|" .. bar:sub(pos+1)

  -- Prefijo de pitch
  local pitchStr = string.format("%+.0f", pitch)
  return pitchStr .. " [" .. bar .. "]"
end

-- ============================================================
--  Notificaciones
-- ============================================================
local function pushNotif(text, color)
  local expires = os.epoch("utc")/1000 + NOTIFY_TIME
  table.insert(_notifs, { text = text, color = color or colors.yellow, expires = expires })
  -- Mantener solo las ultimas 3
  while #_notifs > 3 do table.remove(_notifs, 1) end
end

local function pruneNotifs()
  local now = os.epoch("utc") / 1000
  local i = 1
  while i <= #_notifs do
    if _notifs[i].expires < now then
      table.remove(_notifs, i)
    else
      i = i + 1
    end
  end
end

-- ============================================================
--  Layout principal
--  El HUD se divide en zonas segun el tamano de la pantalla:
--
--  PEQUENA (< 40 cols): una columna, datos minimos
--  MEDIANA (40-70):     dos columnas
--  GRANDE  (> 70):      dos columnas + panel lateral de tanks
-- ============================================================

local function drawHeader(t, profile)
  local now = textutils.formatTime(os.time(), true)
  local title = " VELOS OS  [" .. (profile or "?"):upper() .. "]"
  local right = now .. " "
  local mid   = string.rep(" ", t.w - #title - #right)
  renderer.write(t, 1, 1, title .. mid .. right,
    t.color and colors.black  or nil,
    t.color and colors.yellow or nil)
end

local function drawFooter(t)
  local hint = " [Q]Salir  [P]Perfil  [T]Tanks "
  renderer.write(t, 1, t.h,
    renderer.truncate(hint .. string.rep(" ", t.w), t.w),
    t.color and colors.black   or nil,
    t.color and colors.gray    or nil)
end

local function drawNotifs(t, startY)
  pruneNotifs()
  for i, n in ipairs(_notifs) do
    renderer.write(t, 1, startY + i - 1,
      renderer.truncate(" " .. n.text .. string.rep(" ", t.w), t.w),
      t.color and n.color    or nil,
      t.color and colors.gray or nil)
  end
end

-- ============================================================
--  Dibuja el bloque de datos de Sable
--  Retorna la cantidad de lineas usadas
-- ============================================================
local function drawSableBlock(t, x, y, w, profile)
  local pose = sublevel.getLogicalPose()
  local vel  = sublevel.getVelocity()
  local lvel = sublevel.getLinearVelocity()
  local avel = sublevel.getAngularVelocity()
  local mass = sublevel.getMass()
  local com  = sublevel.getCenterOfMass()

  -- Posicion y orientacion
  local px = pose.position.x
  local py = pose.position.y
  local pz = pose.position.z
  local pitch, yaw, roll = quatToEuler(pose.orientation)

  -- Velocidades
  local spd_total = speed(vel)
  local spd_horiz = math.sqrt(vel.x*vel.x + vel.z*vel.z)
  local spd_vert  = vel.y

  -- Atmosfera
  local posVec   = vector.new(px, py, pz)
  local pressure = aero.getAirPressure(posVec)
  local gravity  = aero.getGravity()
  local drag     = aero.getUniversalDrag()
  local gMag     = math.abs(gravity.y)

  local useC = t.color
  local col  = t.color and colors.cyan or nil
  local dim  = t.color and colors.lightGray or nil
  local norm = t.color and colors.white or nil

  local line = y

  -- Seccion VELOCIDAD
  renderer.write(t, x, line, renderer.truncate("-- VELOCIDAD --", w), col)
  line = line + 1
  renderer.write(t, x, line,
    renderer.truncate(string.format(" Total:  %6.2f m/s", spd_total), w), norm)
  line = line + 1
  renderer.write(t, x, line,
    renderer.truncate(string.format(" Horiz:  %6.2f m/s", spd_horiz), w), dim)
  line = line + 1
  renderer.write(t, x, line,
    renderer.truncate(string.format(" Vert:   %+6.2f m/s", spd_vert), w), dim)
  line = line + 1

  -- Seccion ORIENTACION (solo perfiles que la usan)
  if profile ~= "terrestre" then
    line = line + 1
    renderer.write(t, x, line, renderer.truncate("-- ORIENTACION --", w), col)
    line = line + 1
    local horizon = horizonBar(pitch, roll, w - 6)
    renderer.write(t, x, line, renderer.truncate(horizon, w), norm)
    line = line + 1
    renderer.write(t, x, line,
      renderer.truncate(string.format(" Yaw:  %5.1f  %s", yaw, yawToCardinal(yaw)), w), dim)
    line = line + 1
    renderer.write(t, x, line,
      renderer.truncate(string.format(" Pitch:%+5.1f  Roll:%+5.1f", pitch, roll), w), dim)
    line = line + 1
  end

  -- Seccion POSICION
  line = line + 1
  renderer.write(t, x, line, renderer.truncate("-- POSICION --", w), col)
  line = line + 1
  renderer.write(t, x, line,
    renderer.truncate(string.format(" X:%-8.1f  Y:%-8.1f", px, py), w), norm)
  line = line + 1
  renderer.write(t, x, line,
    renderer.truncate(string.format(" Z:%-8.1f", pz), w), norm)
  line = line + 1

  -- Seccion ATMOSFERA
  line = line + 1
  renderer.write(t, x, line, renderer.truncate("-- ATMOSFERA --", w), col)
  line = line + 1
  renderer.write(t, x, line,
    renderer.truncate(string.format(" Presion: %.1f kPa", pressure), w), dim)
  line = line + 1
  renderer.write(t, x, line,
    renderer.truncate(string.format(" Gravedad:%.2f  Drag:%.3f", gMag, drag), w), dim)
  line = line + 1

  return line - y   -- lineas usadas
end

-- ============================================================
--  Render en Display Links secundarios
-- ============================================================
local function renderDisplayLinks(profile)
  local extras = renderer.getExtras()
  for _, dl in ipairs(extras) do
    local dt = dl.term
    dt.clear()
    dt.setCursorPos(1, 1)

    if dl.mode == "mirror" then
      -- Espejo simplificado: datos clave en texto plano
      local vel  = sublevel.getVelocity()
      local pose = sublevel.getLogicalPose()
      local spd  = speed(vel)

      dt.write("VELOS OS | " .. profile:upper())
      dt.setCursorPos(1, 2)
      dt.write(string.format("Vel: %.1f m/s", spd))
      dt.setCursorPos(1, 3)
      dt.write(string.format("Alt: %.1f m", pose.position.y))
      dt.setCursorPos(1, 4)
      dt.write(string.format("X:%.0f Z:%.0f", pose.position.x, pose.position.z))

      -- Combustible total si hay tanks
      if detector.hasType("tank") then
        local fuel, cap = tanks.getTotalFuel()
        local pct = cap > 0 and (fuel/cap*100) or 0
        dt.setCursorPos(1, 5)
        dt.write(string.format("Comb: %.0f%% (%d mB)", pct, fuel))
      end
    end
  end
end

-- ============================================================
--  Loop principal
-- ============================================================
function run(renderTarget)
  local t       = renderTarget
  local profile = config.get("vehicle_profile", "terrestre")

  tanks.init()

  -- Timer de refresco
  local timerId = os.startTimer(REFRESH_HZ)

  local running = true
  local function draw()
    if not sublevel.isInPlotGrid() then
      t.term.setBackgroundColor(colors.black)
      t.term.clear()
      renderer.write(t, 1, 1, "Sub-Level perdido!", t.color and colors.red or nil)
      renderer.write(t, 1, 2, "Reintentando...", t.color and colors.yellow or nil)
      return
    end

    t.term.setBackgroundColor(colors.black)
    t.term.clear()
    t.term.setCursorBlink(false)

    drawHeader(t, profile)
    drawFooter(t)

    local contentH = t.h - 2   -- lineas entre header y footer
    local contentY = 2

    if t.w >= 70 then
      -- Layout grande: Sable izquierda, Tanks derecha
      local leftW  = math.floor(t.w * 0.55)
      local rightW = t.w - leftW - 1
      drawSableBlock(t, 1, contentY, leftW, profile)

      -- Divisor vertical
      for row = contentY, contentY + contentH - 1 do
        renderer.write(t, leftW + 1, row, "|", t.color and colors.gray or nil)
      end

      tanks.renderAll(t, leftW + 2, contentY, rightW, contentH)

    elseif t.w >= 40 then
      -- Layout mediano: Sable arriba, tanks abajo
      local topH    = math.floor(contentH * 0.6)
      local bottomH = contentH - topH - 1
      local used    = drawSableBlock(t, 1, contentY, t.w, profile)

      -- Separador
      local sepY = contentY + math.min(used, topH)
      renderer.hline(t, sepY, "-", t.color and colors.gray or nil)

      tanks.renderAll(t, 1, sepY + 1, t.w, bottomH)
    else
      -- Layout pequeno: solo Sable, sin tanks (no caben)
      drawSableBlock(t, 1, contentY, t.w, profile)
    end

    -- Notificaciones sobre el footer
    drawNotifs(t, t.h - #_notifs - 1)

    -- Display Links
    renderDisplayLinks(profile)
  end

  -- ============================================================
  --  Event loop
  -- ============================================================
  while running do
    local ev, p1, p2 = os.pullEvent()

    if ev == "timer" and p1 == timerId then
      draw()
      timerId = os.startTimer(REFRESH_HZ)

    elseif ev == "key" then
      if p1 == keys.q then
        running = false

      elseif p1 == keys.p then
        -- Cambiar perfil
        config.firstTimeSetup(t)
        profile = config.get("vehicle_profile", "terrestre")
        pushNotif("Perfil cambiado: " .. profile, colors.lime)

      elseif p1 == keys.t then
        -- Re-clasificar tanks (borrar config de tanks)
        config.set("tank_types", {})
        tanks.init()
        pushNotif("Clasificacion de tanks reiniciada", colors.yellow)
      end

    elseif ev == "peripheral" then
      -- Nuevo periferico conectado
      local entry = detector.onAttach(p1)
      if entry then
        pushNotif("+ " .. entry.label, colors.lime)
        if entry.osType == "tank" then
          tanks.init()
        end
      end

    elseif ev == "peripheral_detach" then
      local was = detector.onDetach(p1)
      if was then
        pushNotif("- " .. was.label .. " desconectado", colors.orange)
      end

    elseif ev == "monitor_touch" then
      -- Touch en monitor: por ahora solo loguea (para future tabs)
      -- p1=side, p2=x, p3=y
    end
  end

  -- Salida limpia
  t.term.setBackgroundColor(colors.black)
  t.term.setTextColor(colors.white)
  t.term.clear()
  t.term.setCursorPos(1,1)
  print("VelosOS cerrado.")
end
