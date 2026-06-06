-- ============================================================
--  VelosOS  |  modules/hud.lua
-- ============================================================

local hud       = {}
local menu      = require("modules.menu")
local cannon    = require("modules.cannon")
local cannon_ui = require("modules.cannon_ui")
local REFRESH_HZ  = 0.25
local NOTIFY_TIME = 4
local _notifs     = {}
local _currentPage = 1   -- pagina actual (paginacion automatica)

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
  if lineWidth and lineWidth >= 22 then return CARDINALS_LONG[idx] end
  return CARDINALS_SHORT[idx]
end

local function horizonBar(pitch, roll, width)
  local center = math.floor(width / 2)
  local offset = math.max(-(center-2), math.min(center-2, math.floor(roll/10)))
  local pos    = center + offset
  local bar    = string.rep("-", width)
  bar = bar:sub(1, pos-1) .. "|" .. bar:sub(pos+1)
  return string.format("%+.0f", pitch) .. " [" .. bar .. "]"
end

-- ============================================================
--  Escritura sin parpadeo — alias de renderer para comodidad
-- ============================================================
local function writeLine(t, x, y, text, w, fg, bg)
  renderer.writeLine(t, x, y, text, w, fg, bg)
end

local _lastPageDrawn = 0

local function clearLines(t, fromY, toY)
  renderer.clearLines(t, fromY, toY)
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
--  Header y footer
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

-- Footer adaptativo: muestra indicador de pagina si hay paginacion activa
local function drawFooter(t, pageInfo)
  local useC = t.color
  local w    = t.w
  local hint

  if pageInfo and pageInfo.total > 1 then
    -- Con paginacion activa
    local pagLabel = string.format("< %d/%d >", pageInfo.current, pageInfo.total)
    local pagName  = pageInfo.name

    if w >= 50 then
      local left  = " [<][>]Pag [M]Menu [Q]Sal"
      local right = "  " .. pagName .. "  " .. pagLabel .. " "
      local gap   = math.max(1, w - #left - #right)
      hint = left .. string.rep(" ", gap) .. right
    elseif w >= 30 then
      -- Compacto: solo paginacion y salir
      local left  = " [<][>] [M] [Q]"
      local right = " " .. pagLabel .. " "
      local gap   = math.max(1, w - #left - #right)
      hint = left .. string.rep(" ", gap) .. right
    else
      -- Minimo: solo indicador de pagina
      hint = " " .. pagLabel
    end
  else
    -- Sin paginacion
    if w >= 42 then
      hint = " [Q]Salir [M]Widgets [P]Perfil [D]Diag"
    elseif w >= 28 then
      hint = " [Q]Sal [M]Widget [P]Perf"
    else
      hint = " [Q] [M] [P] [D]"
    end
  end

  writeLine(t, 1, t.h, hint, w,
    useC and colors.black or nil,
    useC and colors.gray  or nil)
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
--  Paginas tematicas — cada una retorna lineas usadas
-- ============================================================

-- PAGINA 1: Movimiento (Velocidad + Orientacion)
local function drawMovimiento(t, x, y, w, profile)
  local vel  = sublevel.getVelocity()
  local pose = sublevel.getLogicalPose()

  local pitch, yaw, roll = quatToEuler(pose.orientation)
  local spd_total = speed(vel)
  local spd_horiz = math.sqrt(vel.x*vel.x + vel.z*vel.z)
  local spd_vert  = vel.y

  local useC = t.color
  local col  = useC and colors.cyan      or nil
  local dim  = useC and colors.lightGray or nil
  local norm = useC and colors.white     or nil
  local line = y

  if menu.isActive("velocidad") then
    writeLine(t, x, line, "-- VELOCIDAD --",                                  w, col)  line=line+1
    writeLine(t, x, line, string.format(" Total:  %6.2f m/s", spd_total),     w, norm) line=line+1
    writeLine(t, x, line, string.format(" Horiz:  %6.2f m/s", spd_horiz),     w, dim)  line=line+1
    writeLine(t, x, line, string.format(" Vert:   %+6.2f m/s", spd_vert),     w, dim)  line=line+1
    line=line+1
  end

  if menu.isActive("orientacion") and profile ~= "terrestre" then
    writeLine(t, x, line, "-- ORIENTACION --",                                w, col)  line=line+1
    writeLine(t, x, line, horizonBar(pitch, roll, w - 6),                     w, norm) line=line+1
    local cardinal = yawToCardinal(yaw, w)
    writeLine(t, x, line, string.format(" Rumbo: %5.1f  %s", yaw, cardinal),  w, dim)  line=line+1
    writeLine(t, x, line, string.format(" Pitch: %+5.1f  Roll: %+5.1f", pitch, roll), w, dim) line=line+1
    line=line+1
  end

  return line - y
end

-- Altura que necesita la pagina Movimiento
local function heightMovimiento(profile)
  local h = 0
  if menu.isActive("velocidad")                               then h = h + 5 end
  if menu.isActive("orientacion") and profile ~= "terrestre"  then h = h + 5 end
  return h
end

-- PAGINA 2: Navegacion (Posicion + Atmosfera)
local function drawNavegacion(t, x, y, w)
  local pose   = sublevel.getLogicalPose()
  local px, py, pz = pose.position.x, pose.position.y, pose.position.z
  local posVec = vector.new(px, py, pz)
  local pressure = aero.getAirPressure(posVec)
  local gravity  = aero.getGravity()
  local drag     = aero.getUniversalDrag()

  local useC = t.color
  local col  = useC and colors.cyan      or nil
  local dim  = useC and colors.lightGray or nil
  local norm = useC and colors.white     or nil
  local line = y

  if menu.isActive("posicion") then
    writeLine(t, x, line, "-- POSICION --",                                       w, col)  line=line+1
    writeLine(t, x, line, string.format(" X: %-9.1f  Y: %-9.1f", px, py),        w, norm) line=line+1
    writeLine(t, x, line, string.format(" Z: %-9.1f", pz),                        w, norm) line=line+1
    line=line+1
  end

  if menu.isActive("atmosfera") then
    writeLine(t, x, line, "-- ATMOSFERA --",                                      w, col)  line=line+1
    writeLine(t, x, line, string.format(" Presion: %.1f kPa", pressure),          w, dim)  line=line+1
    writeLine(t, x, line, string.format(" Grav: %.2f  Drag: %.3f",
      math.abs(gravity.y), drag),                                                  w, dim)  line=line+1
    line=line+1
  end

  return line - y
end

local function heightNavegacion()
  local h = 0
  if menu.isActive("posicion")  then h = h + 4 end
  if menu.isActive("atmosfera") then h = h + 4 end
  return h
end

-- PAGINA 3: Sistemas (Tanks + Energia)
local function drawSistemas(t, x, y, w, h)
  local line      = y
  local remaining = h

  if menu.isActive("tanks") and detector.hasType("tank") then
    local th = math.min(remaining, 10)
    tanks.renderAll(t, x, line, w, th)
    line      = line + th
    remaining = remaining - th
    if remaining > 1 then
      writeLine(t, x, line, string.rep("-", w), w,
        t.color and colors.gray or nil)
      line = line + 1; remaining = remaining - 1
    end
  end

  if menu.isActive("energia") and detector.hasType("energy") and remaining > 4 then
    energy.renderAll(t, x, line, w, remaining)
  end

  if not menu.isActive("tanks") and not menu.isActive("energia") then
    writeLine(t, x, y, "Sistemas: sin widgets activos", w,
      t.color and colors.lightGray or nil)
  end
end

local function heightSistemas()
  local h = 0
  if menu.isActive("tanks") then
    local count = 0
    for _ in pairs(detector.getByType("tank")) do count = count + 1 end
    h = h + math.max(5, count * 5)
  end
  if menu.isActive("energia") and detector.hasType("energy") then
    h = h + energy.heightNeeded()
  end
  return math.max(h, 1)
end

-- PAGINA 4: Entorno
local function drawEntorno(t, x, y, w, h)
  environment.draw(t, x, y, w)
end

local function heightEntorno()
  if not menu.isActive("entorno") then return 0 end
  return environment.heightNeeded()
end

-- ============================================================
--  Motor de paginacion
--  Construye la lista de paginas activas y decide si paginar
-- ============================================================
local PAGES_DEF = {
  { id = "movimiento",   name = "Movimiento"  },
  { id = "navegacion",   name = "Navegacion"  },
  { id = "sistemas",     name = "Sistemas"    },
  { id = "entorno",      name = "Entorno"     },
  { id = "inventario",   name = "Inventario"  },
  { id = "red",          name = "Red"         },
  { id = "display_ext",  name = "Display Ext" },
  { id = "artilleria",   name = "Artilleria"  },
}

local function buildPages(profile, contentH, t, contentY, w)
  local heights = {
    movimiento  = heightMovimiento(profile),
    navegacion  = heightNavegacion(),
    sistemas    = heightSistemas(),
    entorno     = heightEntorno(),
    inventario  = (menu.isActive("inventario") and detector.hasType("inventory"))
                  and inventory.heightNeeded() or 0,
    red         = (menu.isActive("red") and detector.hasType("modem"))
                  and modem_mod.heightNeeded() or 0,
    display_ext = (menu.isActive("display_ext") and detector.hasType("display_target"))
                  and display_target.heightNeeded() or 0,
    artilleria  = (menu.isActive("cannon") and cannon.hasAnyCannon())
                  and cannon_ui.heightPage() or 0,
  }

  -- Filtrar paginas con contenido
  local active = {}
  for _, p in ipairs(PAGES_DEF) do
    if heights[p.id] > 0 then
      table.insert(active, { id=p.id, name=p.name, height=heights[p.id] })
    end
  end

  if #active == 0 then return nil end

  -- Calcular altura total si mostramos todo junto
  local totalH = 0
  for _, p in ipairs(active) do totalH = totalH + p.height end

  -- Si todo cabe: modo sin paginacion (devuelve paginas pero con total=1 especial)
  if totalH <= contentH then
    return { paginate=false, pages=active }
  end

  -- Si no cabe: modo paginacion
  return { paginate=true, pages=active }
end

-- ============================================================
--  Render principal segun modo
-- ============================================================
local function drawContent(t, profile, contentY, contentH, pageIndex)
  local w = t.w

  -- Pantalla ancha: dos columnas (sin paginacion)
  if w >= 70 then
    local leftW  = math.floor(w * 0.55)
    local rightW = w - leftW - 1

    -- Columna izquierda: movimiento + navegacion
    local line = contentY
    line = line + drawMovimiento(t, 1, line, leftW, profile)
    drawNavegacion(t, 1, line, leftW)

    -- Divisor
    local useC = t.color
    for row = contentY, contentY + contentH - 1 do
      if useC then t.term.setTextColor(colors.gray) end
      t.term.setCursorPos(leftW+1, row)
      t.term.write("|")
    end

    -- Columna derecha: sistemas
    drawSistemas(t, leftW+2, contentY, rightW, contentH)

    return nil   -- sin paginacion en pantalla ancha
  end

  -- Pantalla normal: calcular paginacion
  local layout = buildPages(profile, contentH, t, contentY, w)
  if not layout then return nil end

  if not layout.paginate then
    -- Todo cabe, dibujar seguido
    local line = contentY
    line = line + drawMovimiento(t, 1, line, w, profile)
    line = line + drawNavegacion(t, 1, line, w)
    drawSistemas(t, 1, line, w, contentH - (line - contentY))
    -- Limpiar area sobrante
    local used = line - contentY + heightSistemas()
    if used < contentH then
      clearLines(t, contentY + used, contentY + contentH - 1)
    end
    return nil   -- sin indicador de pagina
  end

  -- Paginacion activa
  local totalPages = #layout.pages
  if pageIndex > totalPages then pageIndex = totalPages end
  if pageIndex < 1          then pageIndex = 1          end

  local page = layout.pages[pageIndex]

  -- Solo limpiar el area de contenido cuando cambia la pagina,
  -- no en cada frame (evita parpadeo)
  if pageIndex ~= _lastPageDrawn then
    clearLines(t, contentY, contentY + contentH - 1)
    _lastPageDrawn = pageIndex
  end

  if page.id == "movimiento" then
    drawMovimiento(t, 1, contentY, w, profile)
  elseif page.id == "navegacion" then
    drawNavegacion(t, 1, contentY, w)
  elseif page.id == "sistemas" then
    drawSistemas(t, 1, contentY, w, contentH)
  elseif page.id == "entorno" then
    drawEntorno(t, 1, contentY, w, contentH)
  elseif page.id == "inventario" then
    inventory.renderAll(t, 1, contentY, w, contentH)
  elseif page.id == "red" then
    modem_mod.renderAll(t, 1, contentY, w, contentH)
  elseif page.id == "display_ext" then
    display_target.renderAll(t, 1, contentY, w, contentH)
  elseif page.id == "artilleria" then
    cannon_ui.drawPage(t, 1, contentY, w, contentH)
  end

  return {
    current = pageIndex,
    total   = totalPages,
    name    = page.name,
  }
end

-- ============================================================
--  Display Links secundarios
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
  speaker.init()
  environment.init()
  energy.init()
  chatbox.init()
  inventory.init()
  modem_mod.init()
  display_target.init()

  -- Inicializar cañon si hay hardware disponible
  local cannonAvail = cannon.init()
  if cannonAvail then
    -- Preguntar si quiere activar artilleria (solo si no esta ya configurado)
    if config.get("cannon_asked") == nil then
      t.term.setBackgroundColor(colors.black)
      t.term.clear()
      t.term.setCursorPos(1,1)
      if t.color then t.term.setTextColor(colors.yellow) end
      print(" ============================")
      print("   HARDWARE DE ARTILLERIA   ")
      print("   DETECTADO                ")
      print(" ============================")
      if t.color then t.term.setTextColor(colors.white) end
      print("")
      print(" " .. cannon.getHardwareSummary())
      print("")
      print(" Activar modulo de artilleria?")
      print("")
      if t.color then t.term.setTextColor(colors.cyan) end
      print("  [1] Si, activar")
      print("  [2] No por ahora")
      if t.color then t.term.setTextColor(colors.white) end
      print("")
      local choice = tonumber(read())
      config.set("cannon_asked", true)
      if choice == 1 then
        -- Activar widget en menu
        local widgets = config.get("widgets", {})
        widgets["cannon"] = true
        config.set("widgets", widgets)
        menu.init()
        -- Configurar teclas si no estan
        if not config.get("cannon_keys") then
          cannon.setupKeys(t)
        end
      end
      t.term.setBackgroundColor(colors.black)
      t.term.clear()
    elseif not config.get("cannon_keys") then
      cannon.setupKeys(t)
      t.term.setBackgroundColor(colors.black)
      t.term.clear()
    end
  end

  -- Buscar monitor dedicado para artilleria
  cannon_ui.setMainMonitor(renderer.getMainMonitorName())
  cannon_ui.findDedicatedMonitor(t)

  t.term.setBackgroundColor(colors.black)
  t.term.setTextColor(colors.white)
  t.term.clear()
  t.term.setCursorBlink(false)

  local timerId    = os.startTimer(REFRESH_HZ)
  local running    = true
  local lastPageInfo = nil   -- para saber si hay paginacion activa

  local contentY = 2
  local function getContentH() return t.h - 2 end

  local function draw()
    if not sublevel.isInPlotGrid() then
      writeLine(t, 1, 1, "Sub-Level perdido!  ", t.w, t.color and colors.red    or nil)
      writeLine(t, 1, 2, "Reintentando...     ", t.w, t.color and colors.yellow or nil)
      return
    end

    local pageInfo = drawContent(t, profile, contentY, getContentH(), _currentPage)
    lastPageInfo   = pageInfo
    if not pageInfo then _currentPage = 1 end

    cannon.updateAutoAim()

    -- Tick de alertas de audio y chat
    pcall(function() speaker.checkAlerts() end)

    -- Alerta de energia baja
    if detector.hasType("energy") then
      local pct = energy.getLowestPct()
      if pct < 0.05 then
        pcall(function() speaker.energyLow()      end)
        pcall(function() chatbox.energyLow(pct)   end)
      end
    end

    -- Alerta de combustible via chatbox (speaker ya lo hace en checkAlerts)
    if detector.hasType("tank") then
      local fuel, cap = tanks.getTotalFuel()
      if cap > 0 and (fuel/cap) < 0.05 then
        pcall(function() chatbox.fuelCritical(fuel/cap) end)
      end
    end

    drawHeader(t, profile)
    drawFooter(t, pageInfo)
    drawNotifs(t)
    renderDisplayLinks(profile)

    -- Render en monitor dedicado de artilleria
    cannon_ui.drawMonitor()
  end

  local function nextPage()
    if lastPageInfo and lastPageInfo.total > 1 then
      _currentPage   = (_currentPage % lastPageInfo.total) + 1
      _lastPageDrawn = -1   -- forzar limpieza en el siguiente frame
    end
  end

  local function prevPage()
    if lastPageInfo and lastPageInfo.total > 1 then
      _currentPage   = ((_currentPage - 2) % lastPageInfo.total) + 1
      _lastPageDrawn = -1
    end
  end

  -- ============================================================
  --  Event loop
  -- ============================================================
  while running do
    local ev, p1, p2, p3 = os.pullEvent()

    if ev == "timer" and p1 == timerId then
      draw()
      timerId = os.startTimer(REFRESH_HZ)

    elseif ev == "key" then
      if p1 == keys.q then
        running = false
      elseif p1 == keys.right or p1 == keys.period then
        nextPage()
      elseif p1 == keys.left or p1 == keys.comma then
        prevPage()
      -- Navegacion de tracks en pagina artilleria
      elseif lastPageInfo and lastPageInfo.name == "Artilleria" then
        if p1 == keys.up then
          cannon_ui.selectPrevTrack()
        elseif p1 == keys.down then
          cannon_ui.selectNextTrack()
        elseif p1 == keys.enter then
          cannon_ui.confirmTarget()
        else
          -- Teclas del cañon (yaw, pitch, fire, etc)
          cannon.handleKey(p1)
        end
      else
        -- Teclas del cañon funcionan en cualquier pagina
        cannon.handleKey(p1)
      end

      -- Teclas de sistema (siempre activas)
      if p1 == keys.m then
        menu.open(t)
        menu.init()
        t.term.setBackgroundColor(colors.black)
        t.term.clear()
        _currentPage   = 1
        _lastPageDrawn = -1
        pushNotif("Widgets actualizados", colors.lime)
      elseif p1 == keys.p then
        config.firstTimeSetup(t)
        profile = config.get("vehicle_profile", "terrestre")
        t.term.setBackgroundColor(colors.black)
        t.term.clear()
        _currentPage   = 1
        _lastPageDrawn = -1
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

    elseif ev == "mouse_click" then
      -- p1=boton (1=izq, 2=der, 3=medio), p2=x, p3=y
      if p1 == 1 then nextPage()
      elseif p1 == 2 then prevPage()
      end

    elseif ev == "monitor_touch" then
      -- p1=lado, p2=x, p3=y
      -- Click en mitad izquierda = atras, mitad derecha = adelante
      if p3 and p2 then
        if p2 <= math.floor(t.w / 2) then prevPage()
        else nextPage()
        end
      end

    elseif ev == "create_scroll" then
      -- Scroller Pane: p1=lado, p2=direccion (1=adelante, -1=atras)
      if p2 and p2 > 0 then nextPage()
      elseif p2 and p2 < 0 then prevPage()
      end

    elseif ev == "peripheral" then
      local entry = detector.onAttach(p1)
      if entry then
        pushNotif("+ " .. entry.label, colors.lime)
        if entry.osType == "tank"      then tanks.init()          end
        if entry.osType == "modem"     then modem_mod.init()      end
        if entry.osType == "inventory" then inventory.init()      end
        if entry.osType == "display_target" then display_target.init() end
        if entry.osType == "cannon" or (entry.osType and entry.osType:find("^cr_")) then
          cannon.init()
          cannon_ui.findDedicatedMonitor(t)
        end
        if entry.osType == "monitor" then
          cannon_ui.findDedicatedMonitor(t)
        end
      end

    elseif ev == "peripheral_detach" then
      local was = detector.onDetach(p1)
      if was then
        pushNotif("- " .. was.label, colors.orange)
        if was.osType == "cannon" or (was.osType and was.osType:find("^cr_")) then
          cannon.init()
        end
      end

    elseif ev == "rednet_message" then
      -- p1=senderID, p2=message, p3=protocol
      if p3 == "velosOS" then
        modem_mod.onMessage(p1, p2)
        modem_mod.cleanup()
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
