-- ============================================================
--  VelosOS  |  modules/menu.lua
--  Menu de widgets: activa/desactiva lo que se ve en el HUD
--  Navegacion: flechas + Enter  |  click en monitor
-- ============================================================

local menu = {}

local WIDGETS_CFG_KEY = "widgets"

-- Definicion de todos los widgets disponibles
-- id        : clave en config
-- label     : texto en el menu
-- default   : activo por defecto?
-- requires  : osType del detector que debe estar presente (nil = siempre disponible)
local WIDGET_DEFS = {
  { id = "velocidad",   label = "Velocidad",          default = true,  requires = nil         },
  { id = "orientacion", label = "Orientacion",         default = true,  requires = nil         },
  { id = "posicion",    label = "Posicion",            default = true,  requires = nil         },
  { id = "atmosfera",   label = "Atmosfera",           default = true,  requires = nil         },
  { id = "tanks",       label = "Tanks (combustible)", default = true,  requires = "tank"      },
  { id = "radar",       label = "Radar de entidades",  default = false, requires = "radar"     },
  { id = "entorno",     label = "Clima / Entorno",     default = false, requires = "environment"},
  { id = "energia",     label = "Energia",             default = false, requires = "energy"    },
  { id = "cannon",      label = "Artilleria",          default = false, requires = "cannon"    },
  { id = "comms",       label = "Comunicaciones",      default = false, requires = "comms"     },
}

-- Cache local del estado de widgets
local _state = {}

-- ============================================================
--  Init y persistencia
-- ============================================================
function menu.init()
  local saved = config.get(WIDGETS_CFG_KEY, {})
  _state = {}
  for _, def in ipairs(WIDGET_DEFS) do
    if saved[def.id] ~= nil then
      _state[def.id] = saved[def.id]
    else
      _state[def.id] = def.default
    end
  end
end

function menu.save()
  config.set(WIDGETS_CFG_KEY, _state)
end

-- Consulta si un widget esta activo
function menu.isActive(id)
  return _state[id] == true
end

-- ============================================================
--  Disponibilidad segun perifericos conectados
-- ============================================================
local function isAvailable(def)
  if def.requires == nil then return true end
  return detector.hasType(def.requires)
end

-- ============================================================
--  Render del menu
-- ============================================================
local TITLE      = "  WIDGETS DEL HUD  "
local CHECK_ON   = "[v]"
local CHECK_OFF  = "[ ]"
local CHECK_NA   = "[~]"   -- no disponible (falta periferico)

local function drawMenu(t, selected)
  local useC = t.color
  local w    = t.w

  -- Fondo negro limpio (solo al entrar al menu, no en cada frame)
  -- Se llama clear() una vez desde menu.open()

  -- Titulo
  local titleLine = string.rep("=", w)
  if useC then t.term.setTextColor(colors.yellow) end
  t.term.setCursorPos(1, 1)
  t.term.write(titleLine)

  local titlePad = math.floor((w - #TITLE) / 2)
  t.term.setCursorPos(1, 2)
  t.term.write(string.rep(" ", titlePad) .. TITLE ..
    string.rep(" ", w - titlePad - #TITLE))

  t.term.setCursorPos(1, 3)
  t.term.write(titleLine)

  -- Lista de widgets
  for i, def in ipairs(WIDGET_DEFS) do
    local row     = i + 3
    local avail   = isAvailable(def)
    local active  = _state[def.id]
    local isSel   = (i == selected)

    local check
    local fg, bg

    if not avail then
      check = CHECK_NA
      fg    = useC and colors.gray or nil
      bg    = useC and colors.black or nil
    elseif active then
      check = CHECK_ON
      fg    = useC and colors.lime or nil
      bg    = useC and colors.black or nil
    else
      check = CHECK_OFF
      fg    = useC and colors.lightGray or nil
      bg    = useC and colors.black or nil
    end

    -- Resaltar fila seleccionada
    if isSel then
      fg = useC and colors.black  or nil
      bg = useC and colors.white  or nil
      if not avail then
        bg = useC and colors.gray or nil
      end
    end

    local suffix = ""
    if not avail then
      local req = def.requires or ""
      suffix = "  <necesita " .. req .. ">"
    end

    local line = " " .. check .. " " .. def.label .. suffix
    -- Rellenar hasta ancho completo
    line = line .. string.rep(" ", math.max(0, w - #line))
    line = line:sub(1, w)

    if fg then t.term.setTextColor(fg) end
    if bg then t.term.setBackgroundColor(bg) end
    t.term.setCursorPos(1, row)
    t.term.write(line)
    t.term.setBackgroundColor(colors.black)
  end

  -- Separador
  local sepRow = #WIDGET_DEFS + 4
  if useC then
    t.term.setTextColor(colors.gray)
    t.term.setBackgroundColor(colors.black)
  end
  t.term.setCursorPos(1, sepRow)
  t.term.write(string.rep("-", w))

  -- Instrucciones
  local instrRow = sepRow + 1
  local instr1 = " Arriba/Abajo: mover    Enter: toggle"
  local instr2 = " Q / Esc: volver al HUD"
  if useC then t.term.setTextColor(colors.lightGray) end
  t.term.setCursorPos(1, instrRow)
  t.term.write((instr1 .. string.rep(" ", w)):sub(1, w))
  if instrRow + 1 <= t.h then
    t.term.setCursorPos(1, instrRow + 1)
    t.term.write((instr2 .. string.rep(" ", w)):sub(1, w))
  end
end

-- ============================================================
--  Toggle de un widget por indice
-- ============================================================
local function toggleWidget(idx)
  local def = WIDGET_DEFS[idx]
  if not def then return end
  if not isAvailable(def) then return end  -- no se puede activar sin periferico
  _state[def.id] = not _state[def.id]
  menu.save()
end

-- ============================================================
--  Detectar click en una fila del menu
--  Retorna el indice del widget clickeado o nil
-- ============================================================
local function rowToWidget(y)
  -- Widgets empiezan en fila 4 (1-indexed)
  local idx = y - 3
  if idx >= 1 and idx <= #WIDGET_DEFS then
    return idx
  end
  return nil
end

-- ============================================================
--  Abrir el menu (bloquea hasta que el usuario cierra)
-- ============================================================
function menu.open(renderTarget)
  local t        = renderTarget
  local selected = 1

  -- Limpiar pantalla al entrar
  t.term.setBackgroundColor(colors.black)
  t.term.setTextColor(colors.white)
  t.term.clear()
  t.term.setCursorBlink(false)

  drawMenu(t, selected)

  local inMenu = true
  while inMenu do
    local ev, p1, p2, p3 = os.pullEvent()

    if ev == "key" then
      if p1 == keys.up then
        selected = math.max(1, selected - 1)
        drawMenu(t, selected)

      elseif p1 == keys.down then
        selected = math.min(#WIDGET_DEFS, selected + 1)
        drawMenu(t, selected)

      elseif p1 == keys.enter or p1 == keys.space then
        toggleWidget(selected)
        drawMenu(t, selected)

      elseif p1 == keys.q or p1 == keys.escape then
        inMenu = false
      end

    elseif ev == "monitor_touch" then
      -- p1=side, p2=x, p3=y
      local idx = rowToWidget(p3)
      if idx then
        selected = idx
        toggleWidget(idx)
        drawMenu(t, selected)
      end

    elseif ev == "mouse_click" then
      -- p1=button, p2=x, p3=y  (click en Advanced Computer)
      local idx = rowToWidget(p3)
      if idx then
        selected = idx
        toggleWidget(idx)
        drawMenu(t, selected)
      end
    end
  end

  -- Limpiar al salir para que el HUD redibuje limpio
  t.term.setBackgroundColor(colors.black)
  t.term.setTextColor(colors.white)
  t.term.clear()
end

return menu