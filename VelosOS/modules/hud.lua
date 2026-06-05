-- ============================================================
--  VelosOS  |  modules/hud.lua
-- ============================================================

local hud  = {}
local menu = require("modules.menu")

local REFRESH_HZ  = 0.25
local NOTIFY_TIME = 4
local _notifs = {}

-- ============================================================
--  Helpers de fisica
-- ============================================================
local function speed(v)
  return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
end

local function quatToEuler(q)
  local ok, p, y, r = pcall(function() return q:toEuler() end)
  if ok then return math.deg(p), math.deg(y), math.deg(r) end
  return 0, 0, 0
end

-- Tabla de cardinales: abreviado y completo
-- Se elige segun el espacio disponible en la linea
local CARDINALS_SHORT = {
  "N","NNE","NE","ENE","E","ESE","SE","SSE",
  "S","SSO","SO","OSO","O","ONO","NO","NNO"
}
local CARDINALS_LONG = {
  "Norte","Norte-Noreste","Noreste","Este-Noreste",
  "Este","Este-Sureste","Sureste","Sur-Sureste",
  "Sur","Sur-Suroeste","Suroeste","Oeste-Suroeste",
  "Oeste","Oeste-Noroeste","Noroeste","Nor-Noroeste"
}

local function yawToCardinal(yaw, lineWidth)
  yaw = yaw % 360
  if yaw < 0 then yaw = yaw + 360 end
  local idx = math.floor((yaw + 11.25) / 22.5) % 16 + 1
  -- Si la linea tiene espacio suficiente, nombre completo
  -- "Nor-Noroeste" es el mas largo (12 chars) + prefijo " Rumbo: " (8) = 20
  if lineWidth and lineWidth >= 22 then
    return CARDINALS_LONG[idx]
  end
  return CARDINALS_SHORT[idx]
end

local function horizonBar(pitch, roll, width)
  local center = math.floor(width / 2)
  local offset = math.max(-(center-2), math.min(center-2, math.floor(roll/10)))
  local pos = center + offset
  local bar = string.rep("-", width)
  bar = bar:sub(1, pos-1) .. "|" .. bar:sub(pos+1)
  return string.format("%+.0f", pitch) .. " [" .. bar .. "]"
end

-- ============================================================
--  Escritura sin parpadeo
--  Rellena con espacios hasta 'w' para borrar residuos
--  sin hacer clear() en la pantalla completa
-- ============================================================
local function writeLine(t, x, y, text, w, fg, bg)
  -- Rellenar o truncar hasta exactamente w - x + 1 caracteres
  local available = w - x + 1
  if #text > available then
    text = string.sub(text, 1, available - 1) .. ">"
  else
    text = text .. string.rep(" ", available - #text)
  end
  if fg then t.term.setTextColor(fg) end
  if bg then t.term.setBackgroundColor(bg) end
  t.term.setCursorPos(x, y)
  t.term.write(text)
  -- Resetear bg para no contaminar lineas siguientes
  t.term.setBackgroundColor(colors.black)
end

-- ============================================================
--  Notificaciones
-- ============================================================
local function pushNotif(text, color)
  local expires = os.epoch("utc")/1000 + NOTIFY_TIME
  table.insert(_notifs, { text=text, color=color or colors.yellow, expires=expires })
  while #_notifs > 3 do table.remove(_notifs, 1) end
end

local function pruneNotifs()
  local now = os.epoch("utc") / 1000
  local i = 1
  while i <= #_notifs do
    if _notifs[i].expires < now then table.remove(_notifs, i)
    else i = i + 1 end
  end
end

-- ============================================================
--  Layout
-- ============================================================
local function drawHeader(t, profile)
  local now   = textutils.formatTime(os.time(), true)
  local title = " VELOS OS  [" .. (profile or "?"):upper() .. "]"
  local right = now .. " "
  local mid   = string.rep(" ", t.w - #title - #right)
  writeLine(t, 1, 1, title..mid..right, t.w,
    t.color and colors.black  or nil,
    t.color and colors.yellow or nil)
end

local function drawFooter(t)
  local hint = " [Q]Salir [M]Widgets [P]Perfil [D]Diag"
  writeLine(t, 1, t.h, hint, t.w,
    t.color and colors.black or nil,
    t.color and colors.gray  or nil)
end

local function drawNotifs(t)
  pruneNotifs()
  local startY = t.h - #_notifs - 1
  for i, n in ipairs(_notifs) do
    writeLine(t, 1, startY + i - 1, " " .. n.text, t.w,
      t.color and n.color     or nil,
      t.color and colors.gray or nil)
  end
end

-- ============================================================
--  Bloque de datos de Sable (sin clear, sobreescribe)
-- ============================================================
local function drawSableBlock(t, x, y, w, profile)
  local pose = sublevel.getLogicalPose()
  local vel  = sublevel.getVelocity()

  local px, py, pz = pose.position.x, pose.position.y, pose.position.z
  local pitch, yaw, roll = quatToEuler(pose.orientation)
  local spd_total = speed(vel)
  local spd_horiz = math.sqrt(vel.x*vel.x + vel.z*vel.z)
  local spd_vert  = vel.y

  local posVec   = vector.new(px, py, pz)
  local pressure = aero.getAirPressure(posVec)
  local gravity  = aero.getGravity()
  local drag     = aero.getUniversalDrag()

  local useC = t.color
  local col  = useC and colors.cyan      or nil
  local dim  = useC and colors.lightGray or nil
  local norm = useC and colors.white     or nil

  local line = y

  writeLine(t, x, line, "-- VELOCIDAD --",                                    w, col)  line=line+1
  writeLine(t, x, line, string.format(" Total:  %6.2f m/s", spd_total),       w, norm) line=line+1
  writeLine(t, x, line, string.format(" Horiz:  %6.2f m/s", spd_horiz),       w, dim)  line=line+1
  writeLine(t, x, line, string.format(" Vert:   %+6.2f m/s", spd_vert),       w, dim)  line=line+1

  if profile ~= "terrestre" then
    line=line+1
    writeLine(t, x, line, "-- ORIENTACION --",                                w, col)  line=line+1
    writeLine(t, x, line, horizonBar(pitch, roll, w - 6),                     w, norm) line=line+1
    -- Rumbo: nombre largo si hay espacio, corto si no
    local cardinal = yawToCardinal(yaw, w)
    writeLine(t, x, line, string.format(" Rumbo: %5.1f  %s", yaw, cardinal),  w, dim)  line=line+1
    writeLine(t, x, line, string.format(" Pitch: %+5.1f  Roll: %+5.1f", pitch, roll), w, dim) line=line+1
  end

  line=line+1
  writeLine(t, x, line, "-- POSICION --",                                     w, col)  line=line+1
  writeLine(t, x, line, string.format(" X: %-9.1f  Y: %-9.1f", px, py),      w, norm) line=line+1
  writeLine(t, x, line, string.format(" Z: %-9.1f", pz),                      w, norm) line=line+1

  line=line+1
  writeLine(t, x, line, "-- ATMOSFERA --",                                    w, col)  line=line+1
  writeLine(t, x, line, string.format(" Presion: %.1f kPa", pressure),        w, dim)  line=line+1
  writeLine(t, x, line, string.format(" Grav: %.2f  Drag: %.3f", math.abs(gravity.y), drag), w, dim) line=line+1

  return line - y
end

-- ============================================================
--  Divisor vertical (sobreescribe sin clear)
-- ============================================================
local function drawDivider(t, col_x, fromY, toY)
  local fg = t.color and colors.gray or nil
  for row = fromY, toY do
    if fg then t.term.setTextColor(fg) end
    t.term.setCursorPos(col_x, row)
    t.term.write("|")
  end
end

-- ============================================================
--  Display Links secundarios
--  Solo espejo de datos del vehiculo (Sable).
--  El Display Link no puede leer tanks de Create directamente.
-- ============================================================
local function renderDisplayLinks(profile)
  for _, dl in ipairs(renderer.getExtras()) do
    local dt = dl.term
    local w  = dl.w

    local function dlLine(y, text)
      if #text > w then text = text:sub(1, w-1) .. ">" end
      text = text .. string.rep(" ", w - #text)
      dt.setCursorPos(1, y)
      dt.write(text)
    end

    local vel  = sublevel.getVelocity()
    local pose = sublevel.getLogicalPose()
    local spd  = speed(vel)
    local spd_h = math.sqrt(vel.x*vel.x + vel.z*vel.z)

    dlLine(1, "VELOS OS | " .. profile:upper())
    dlLine(2, string.format("Vel:  %.1f m/s", spd))
    dlLine(3, string.format("Hor:  %.1f m/s", spd_h))
    dlLine(4, string.format("Alt:  %.1f m",   pose.position.y))
    dlLine(5, string.format("X:%.0f  Z:%.0f", pose.position.x, pose.position.z))
    -- Lineas extra vacias para limpiar residuos
    for extraY = 6, dl.h do dlLine(extraY, "") end
  end
end

-- ============================================================
--  Loop principal
-- ============================================================
function hud.run(renderTarget)
  local t       = renderTarget
  local profile = config.get("vehicle_profile", "terrestre")

  tanks.init()
  menu.init()

  -- Limpiar UNA sola vez al arrancar
  t.term.setBackgroundColor(colors.black)
  t.term.setTextColor(colors.white)
  t.term.clear()
  t.term.setCursorBlink(false)

  local timerId = os.startTimer(REFRESH_HZ)
  local running = true

  local function draw()
    if not sublevel.isInPlotGrid() then
      writeLine(t, 1, 1, "Sub-Level perdido!  ", t.w, t.color and colors.red    or nil)
      writeLine(t, 1, 2, "Reintentando...     ", t.w, t.color and colors.yellow or nil)
      return
    end

    -- Header y footer siempre se sobreescriben
    drawHeader(t, profile)
    drawFooter(t)

    local contentY = 2
    local contentH = t.h - 2

    if t.w >= 70 then
      local leftW  = math.floor(t.w * 0.55)
      local rightW = t.w - leftW - 1
      drawSableBlock(t, 1, contentY, leftW, profile)
      drawDivider(t, leftW+1, contentY, contentY + contentH - 1)
      tanks.renderAll(t, leftW+2, contentY, rightW, contentH)

    elseif t.w >= 40 then
      local topH = math.floor(contentH * 0.6)
      local used = drawSableBlock(t, 1, contentY, t.w, profile)
      local sepY = contentY + math.min(used, topH)
      writeLine(t, 1, sepY, string.rep("-", t.w), t.w, t.color and colors.gray or nil)
      tanks.renderAll(t, 1, sepY+1, t.w, contentH - (sepY - contentY) - 1)
    else
      drawSableBlock(t, 1, contentY, t.w, profile)
    end

    drawNotifs(t)
    renderDisplayLinks(profile)
  end

  while running do
    local ev, p1 = os.pullEvent()

    if ev == "timer" and p1 == timerId then
      draw()
      timerId = os.startTimer(REFRESH_HZ)

    elseif ev == "key" then
      if p1 == keys.q then
        running = false
      elseif p1 == keys.m then
        menu.open(t)
        menu.init()
        t.term.setBackgroundColor(colors.black)
        t.term.clear()
        pushNotif("Widgets actualizados", colors.lime)
      elseif p1 == keys.p then
        config.firstTimeSetup(t)
        profile = config.get("vehicle_profile", "terrestre")
        t.term.setBackgroundColor(colors.black)
        t.term.clear()
        pushNotif("Perfil: " .. profile, colors.lime)
      elseif p1 == keys.d then
        detector.diagnose(t)
        t.term.setBackgroundColor(colors.black)
        t.term.clear()
      elseif p1 == keys.t then
        config.set("tank_types", {})
        tanks.init()
        pushNotif("Tanks reclasificados", colors.yellow)
      end

    elseif ev == "peripheral" then
      local entry = detector.onAttach(p1)
      if entry then
        pushNotif("+ " .. entry.label, colors.lime)
        if entry.osType == "tank" then tanks.init() end
      end

    elseif ev == "peripheral_detach" then
      local was = detector.onDetach(p1)
      if was then
        pushNotif("- " .. was.label, colors.orange)
      end
    end
  end

  t.term.setBackgroundColor(colors.black)
  t.term.setTextColor(colors.white)
  t.term.clear()
  t.term.setCursorPos(1,1)
  print("VelosOS cerrado.")
end

return hud
