-- ============================================================
--  VelosOS  |  modules/display_target.lua
--  Recibe texto desde un create_target (CC:C Bridge)
--  El create_target es la pantalla receptora del Display Link.
--  Un source externo puede escribir en el target y el OS
--  lo muestra en el HUD como panel de informacion externo.
-- ============================================================

local display_target = {}

local _targets  = {}   -- { name -> { periph, lines, time } }
local CACHE_TTL = 1.0

-- ============================================================
--  Init
-- ============================================================
function display_target.init()
  local entries = detector.getByType("display_target")
  _targets = {}
  for name, e in pairs(entries) do
    _targets[name] = { periph=e.periph, lines={}, time=0 }
  end
  return next(_targets) ~= nil
end

function display_target.isAvailable()
  return next(_targets) ~= nil
end

-- ============================================================
--  Leer contenido actual de un target
--  create_target expone getText() que devuelve el contenido
--  actual de la pantalla como string con saltos de linea
-- ============================================================
local function readTarget(name, entry)
  local now = os.epoch("utc") / 1000
  if now - entry.time < CACHE_TTL then return entry.lines end

  local ok, raw = pcall(function() return entry.periph.getText() end)
  if not ok or not raw then
    entry.lines = { "(sin datos)" }
    entry.time  = now
    return entry.lines
  end

  -- Dividir por saltos de linea
  local lines = {}
  for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end
  if #lines == 0 then lines = { "(vacio)" } end

  entry.lines = lines
  entry.time  = now
  return lines
end

-- ============================================================
--  Render de un target (altura variable)
-- ============================================================
local function renderOne(t, x, y, w, name, entry, maxLines)
  local useC = t.color
  local col  = useC and colors.cyan      or nil
  local dim  = useC and colors.lightGray or nil
  local line = y

  writeLine(t, x, line,
    "-- DISPLAY [" .. name .. "] --", w, col)
  line = line + 1

  local lines   = readTarget(name, entry)
  local toShow  = math.min(#lines, maxLines - 1)

  for i = 1, toShow do
    writeLine(t, x, line, " " .. (lines[i] or ""), w, dim)
    line = line + 1
  end

  if #lines > toShow then
    writeLine(t, x, line,
      " +" .. (#lines - toShow) .. " lineas mas...", w,
      useC and colors.gray or nil)
    line = line + 1
  end

  return line - y
end

-- ============================================================
--  Render de todos los targets
-- ============================================================
function display_target.renderAll(t, x, y, w, h)
  if not next(_targets) then
    writeLine(t, x, y, "Sin display targets", w,
      t.color and colors.lightGray or nil)
    return
  end

  local line      = y
  local remaining = h
  local count     = 0

  for name, entry in pairs(_targets) do
    if remaining < 3 then break end

    if count > 0 then
      writeLine(t, x, line, string.rep("-", w), w,
        t.color and colors.gray or nil)
      line      = line + 1
      remaining = remaining - 1
    end

    -- Dar espacio proporcional a cada target
    local allCount = 0
    for _ in pairs(_targets) do allCount = allCount + 1 end
    local slot = math.max(4, math.floor(remaining / math.max(1, allCount - count)))

    local used = renderOne(t, x, line, w, name, entry, slot)
    line      = line + used
    remaining = remaining - used
    count     = count + 1
  end
end

function display_target.heightNeeded()
  local count = 0
  for _ in pairs(_targets) do count = count + 1 end
  return math.max(4, count * 5)
end

return display_target
