-- ============================================================
--  VelosOS  |  modules/cannon_ui.lua
--  Interfaz de artilleria:
--    - Pagina en HUD principal
--    - Monitor dedicado si hay uno secundario disponible
-- ============================================================

local cannon_ui = {}

-- Monitor dedicado para artilleria (si hay mas de uno conectado)
local _dedicatedMonitor = nil

-- Indice del track seleccionado en la lista del radar
local _selectedTrack = 1

-- Cache de tracks para no re-leer en cada frame
local _trackCache    = {}
local _trackTimer    = 0
local TRACK_REFRESH  = 1.0   -- segundos entre lecturas del radar

-- ============================================================
--  Monitor dedicado
-- ============================================================

-- Busca un monitor que no sea el principal del HUD
function cannon_ui.findDedicatedMonitor(mainRenderTarget)
  local all = { peripheral.find("monitor") }
  for _, mon in ipairs(all) do
    -- Comparar con el monitor principal
    if mon ~= mainRenderTarget.term then
      mon.setTextScale(0.5)
      mon.setBackgroundColor(colors.black)
      mon.clear()
      local w, h = mon.getSize()
      _dedicatedMonitor = {
        term  = mon,
        w     = w,
        h     = h,
        color = mon.isColour and mon.isColour() or false,
      }
      return _dedicatedMonitor
    end
  end
  _dedicatedMonitor = nil
  return nil
end

function cannon_ui.getDedicatedMonitor()
  return _dedicatedMonitor
end

-- ============================================================
--  Helpers de escritura (sin parpadeo)
-- ============================================================
-- wLine es alias de renderer.writeLine para comodidad
local function wLine(t, x, y, text, w, fg, bg)
  renderer.writeLine(t, x, y, text, w, fg, bg)
end

local function hline(t, y, char, fg)
  char = char or "-"
  if fg then t.term.setTextColor(fg) end
  t.term.setCursorPos(1, y)
  t.term.write(string.rep(char, t.w))
end

-- ============================================================
--  Cache de tracks
-- ============================================================
local function refreshTracks()
  local now = os.epoch("utc") / 1000
  if now - _trackTimer >= TRACK_REFRESH then
    _trackCache  = cannon.getTracks()
    _trackTimer  = now
    -- Clamp seleccion
    if _selectedTrack > #_trackCache then
      _selectedTrack = math.max(1, #_trackCache)
    end
  end
  return _trackCache
end

-- ============================================================
--  Colores de alerta segun modo y estado
-- ============================================================
local function stateColor(useC)
  if not useC then return nil end
  local s = cannon.getState()
  if s == "assembled" then return colors.lime   end
  if s == "firing"    then return colors.red    end
  if s == "assembling" then return colors.yellow end
  return colors.orange
end

local function modeColor(useC, mode)
  if not useC then return nil end
  if mode == "manual" then return colors.cyan   end
  if mode == "radar"  then return colors.yellow end
  if mode == "coords" then return colors.lime   end
  return colors.white
end

-- ============================================================
--  Formatear distancia legible
-- ============================================================
local function fmtDist(d)
  if d >= 1000 then return string.format("%.1fkm", d/1000) end
  return string.format("%.0fm", d)
end

-- ============================================================
--  Dibujar lista de tracks (para HUD y monitor)
-- ============================================================
local function drawTrackList(t, x, y, w, h, tracks, selected)
  local useC  = t.color
  local count = math.min(#tracks, h)

  if count == 0 then
    wLine(t, x, y, " Sin objetivos detectados", w,
      useC and colors.lightGray or nil)
    return
  end

  for i = 1, count do
    local tr   = tracks[i]
    local isSel = (i == selected)
    local fg, bg

    if isSel then
      fg = useC and colors.black or nil
      bg = useC and colors.white or nil
    else
      -- Color por tipo de entidad
      if tr.rawType and tr.rawType:find("player") then
        fg = useC and colors.yellow or nil
      elseif tr.rawType and tr.rawType:find("sable") then
        fg = useC and colors.orange or nil
      else
        fg = useC and colors.lightGray or nil
      end
      bg = useC and colors.black or nil
    end

    local dist    = fmtDist(tr.dist)
    local label   = tr.label
    local suffix  = " " .. dist
    local maxLbl  = w - x - #suffix
    if #label > maxLbl then label = label:sub(1, maxLbl-1) .. ">" end

    local pad = w - x + 1 - #label - #suffix
    wLine(t, x, y + i - 1,
      " " .. label .. string.rep(" ", math.max(0, pad-1)) .. suffix,
      w, fg, bg)
  end

  -- Limpiar lineas sobrantes
  for i = count + 1, h do
    wLine(t, x, y + i - 1, "", w)
  end
end

-- ============================================================
--  PAGINA DE ARTILLERIA en el HUD principal
--  Se llama desde hud.lua igual que drawMovimiento etc.
-- ============================================================
function cannon_ui.drawPage(t, x, y, w, h)
  local useC   = t.color
  local col    = useC and colors.cyan      or nil
  local dim    = useC and colors.lightGray or nil
  local norm   = useC and colors.white     or nil
  local tracks = refreshTracks()
  local mode   = cannon.getAimMode()
  local line   = y

  -- Estado del cañon
  local stateStr = cannon.getState():upper()
  if not cannon.hasCBC() then stateStr = "SIN CBC" end
  local assembled = cannon.isAssembled()

  wLine(t, x, line, "-- ARTILLERIA --", w, col) line=line+1
  wLine(t, x, line,
    string.format(" Estado: %-12s  Hw: %s",
      stateStr, cannon.hasCBC() and "CBC" or "Radar"),
    w, useC and stateColor(useC) or nil) line=line+1

  -- Angulos actuales
  local yaw   = cannon.getYaw()
  local pitch = cannon.getPitch()
  wLine(t, x, line,
    string.format(" Yaw: %7.1f   Pitch: %+6.1f", yaw, pitch),
    w, norm) line=line+1

  -- Modo de apuntado + paso
  local stepStr = cannon.isFineMode() and "FINO" or "GRUESO"
  wLine(t, x, line,
    string.format(" Modo: %-8s  Paso: %s", mode:upper(), stepStr),
    w, useC and modeColor(useC, mode) or nil) line=line+1

  -- Cargado (solo con CBC)
  if cannon.hasCBC() then
    local loaded = cannon.isLoaded()
    local loadStr = loaded == nil and "?" or (loaded and "SI" or "NO")
    local loadFg  = useC and (loaded and colors.lime or colors.red) or nil
    wLine(t, x, line, " Cargado: " .. loadStr, w, loadFg) line=line+1
  end

  line=line+1

  -- Objetivo actual
  local target = cannon.getTarget()
  wLine(t, x, line, "-- OBJETIVO --", w, col) line=line+1
  if target then
    wLine(t, x, line,
      string.format(" %s  (%s)", target.label, fmtDist(target.dist)),
      w, useC and colors.yellow or nil) line=line+1
    wLine(t, x, line,
      string.format(" X:%.0f  Y:%.0f  Z:%.0f",
        target.x, target.y, target.z),
      w, dim) line=line+1
    if cannon.isAiming() then
      wLine(t, x, line, " Apuntando...", w, useC and colors.yellow or nil)
    else
      wLine(t, x, line, " Listo", w, useC and colors.lime or nil)
    end
    line=line+1
  else
    wLine(t, x, line, " Sin objetivo", w, dim) line=line+2
  end

  -- Lista de tracks si hay espacio
  local remaining = h - (line - y)
  if remaining >= 3 and #tracks > 0 then
    line=line+1
    wLine(t, x, line, "-- RADAR --", w, col) line=line+1
    drawTrackList(t, x, line, w, remaining - 2, tracks, _selectedTrack)
  end
end

function cannon_ui.heightPage()
  -- Altura minima para mostrar la pagina
  return 10
end

-- ============================================================
--  MONITOR DEDICADO — interfaz completa
-- ============================================================
function cannon_ui.drawMonitor()
  local dm = _dedicatedMonitor
  if not dm then return end

  local t    = dm
  local w    = dm.w
  local h    = dm.h
  local useC = dm.color
  local tracks = refreshTracks()
  local mode   = cannon.getAimMode()
  local target = cannon.getTarget()
  local yaw    = cannon.getYaw()
  local pitch  = cannon.getPitch()

  -- Header
  local stateStr = cannon.getState():upper()
  local hdr = " ARTILLERIA  [" .. stateStr .. "]"
  local now = textutils.formatTime(os.time(), true)
  local gap = math.max(1, w - #hdr - #now - 1)
  wLine(t, 1, 1, hdr .. string.rep(" ", gap) .. now .. " ", w,
    useC and colors.black  or nil,
    useC and colors.red    or nil)

  hline(t, 2, "=", useC and colors.red or nil)

  -- Columnas: izquierda = datos cañon, derecha = lista tracks
  local leftW  = math.floor(w * 0.5)
  local rightW = w - leftW - 1
  local startY = 3

  -- Divisor vertical
  if useC then dm.term.setTextColor(colors.gray) end
  for row = startY, h - 1 do
    dm.term.setCursorPos(leftW + 1, row)
    dm.term.write("|")
  end

  -- Columna izquierda: estado y angulos
  local col  = useC and colors.cyan      or nil
  local dim  = useC and colors.lightGray or nil
  local norm = useC and colors.white     or nil
  local line = startY

  wLine(t, 1, line, "-- ANGULOS --", leftW, col) line=line+1
  wLine(t, 1, line, string.format(" Yaw:   %7.2f", yaw),   leftW, norm) line=line+1
  wLine(t, 1, line, string.format(" Pitch: %+7.2f", pitch), leftW, norm) line=line+1
  local aimStr = cannon.isAiming() and "Apuntando..." or "En posicion"
  wLine(t, 1, line, " " .. aimStr, leftW,
    useC and (cannon.isAiming() and colors.yellow or colors.lime) or nil)
  line=line+2

  -- Hardware
  wLine(t, 1, line, "-- HARDWARE --", leftW, col) line=line+1
  wLine(t, 1, line,
    " CBC:   " .. (cannon.hasCBC() and "SI" or "NO"), leftW,
    useC and (cannon.hasCBC() and colors.lime or colors.gray) or nil) line=line+1
  wLine(t, 1, line,
    " Radar: " .. (cannon.hasRadar() and "SI" or "NO"), leftW,
    useC and (cannon.hasRadar() and colors.lime or colors.gray) or nil) line=line+1
  wLine(t, 1, line,
    " Fire:  " .. (cannon.hasFireController() and "SI" or "NO"), leftW,
    useC and (cannon.hasFireController() and colors.lime or colors.gray) or nil)
  line=line+2

  -- Modo y cargado
  wLine(t, 1, line, "-- ESTADO --", leftW, col) line=line+1
  wLine(t, 1, line,
    string.format(" Modo:  %s", mode:upper()), leftW,
    useC and modeColor(useC, mode) or nil) line=line+1

  if cannon.hasCBC() then
    local loaded  = cannon.isLoaded()
    local loadStr = loaded == nil and "?" or (loaded and "LISTO" or "CARGANDO")
    wLine(t, 1, line,
      " Carga: " .. loadStr, leftW,
      useC and (loaded and colors.lime or colors.orange) or nil) line=line+1
  end

  -- Objetivo
  line=line+1
  wLine(t, 1, line, "-- OBJETIVO --", leftW, col) line=line+1
  if target then
    wLine(t, 1, line,
      renderer.truncate(" " .. target.label, leftW),
      leftW, useC and colors.yellow or nil) line=line+1
    wLine(t, 1, line,
      string.format(" Dist: %s", fmtDist(target.dist)),
      leftW, dim) line=line+1
    wLine(t, 1, line,
      string.format(" X:%.0f Y:%.0f", target.x, target.y),
      leftW, dim) line=line+1
    wLine(t, 1, line,
      string.format(" Z:%.0f", target.z),
      leftW, dim)
  else
    wLine(t, 1, line, " Sin objetivo", leftW, dim)
  end

  -- Columna derecha: lista de tracks
  local listH = h - startY - 2
  wLine(t, leftW+2, startY, "-- RADAR --", rightW, col)
  if #tracks == 0 then
    wLine(t, leftW+2, startY+1, " Sin senales", rightW, dim)
  else
    drawTrackList(t, leftW+2, startY+1, w, listH, tracks, _selectedTrack)
  end

  -- Footer con controles
  hline(t, h, "=", useC and colors.red or nil)
  local k    = cannon.getKeys()
  local kYL  = k.yawLeft  and keys.getName(k.yawLeft)  or "?"
  local kYR  = k.yawRight and keys.getName(k.yawRight) or "?"
  local kPU  = k.pitchUp  and keys.getName(k.pitchUp)  or "?"
  local kPD  = k.pitchDown and keys.getName(k.pitchDown) or "?"
  local kF   = k.fire     and keys.getName(k.fire)     or "?"
  local ctrl = string.format(" [%s/%s]Yaw [%s/%s]Pitch [%s]FUEGO",
    kYL, kYR, kPU, kPD, kF)
  wLine(t, 1, h, ctrl, w,
    useC and colors.black or nil,
    useC and colors.gray  or nil)
end

-- ============================================================
--  Navegacion en lista de tracks (desde hud event loop)
-- ============================================================
function cannon_ui.selectNextTrack()
  local tracks = _trackCache
  if #tracks == 0 then return end
  _selectedTrack = (_selectedTrack % #tracks) + 1
  cannon.setTarget(tracks[_selectedTrack])
end

function cannon_ui.selectPrevTrack()
  local tracks = _trackCache
  if #tracks == 0 then return end
  _selectedTrack = ((_selectedTrack - 2) % #tracks) + 1
  cannon.setTarget(tracks[_selectedTrack])
end

function cannon_ui.confirmTarget()
  local tracks = _trackCache
  if tracks[_selectedTrack] then
    cannon.setTarget(tracks[_selectedTrack])
    cannon.cycleAimMode()   -- activa modo radar al confirmar
    if cannon.getAimMode() ~= "radar" then
      -- asegurar que quede en radar
      while cannon.getAimMode() ~= "radar" do
        cannon.cycleAimMode()
      end
    end
  end
end

return cannon_ui
