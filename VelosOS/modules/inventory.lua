-- ============================================================
--  VelosOS  |  modules/inventory.lua
--  Muestra el contenido de cofres, barriles y vaults
--  conectados al vehiculo como perifericos
-- ============================================================

local inventory = {}

-- Cache por inventario para no leer cada frame
local _cache     = {}   -- { periph_name -> { items, time } }
local CACHE_TTL  = 2.0

-- ============================================================
--  Init
-- ============================================================
function inventory.init()
  -- Nada que configurar, lee del detector
end

-- ============================================================
--  Leer items de un inventario con cache
-- ============================================================
local function readItems(name, periph)
  local now = os.epoch("utc") / 1000
  local cached = _cache[name]
  if cached and (now - cached.time) < CACHE_TTL then
    return cached.items, cached.size, cached.used
  end

  local items = {}
  local size  = 0
  local used  = 0

  -- Tamano del inventario
  local ok1, s = pcall(function() return periph.size() end)
  if ok1 then size = s end

  -- Lista de items
  local ok2, list = pcall(function() return periph.list() end)
  if ok2 and list then
    for slot, item in pairs(list) do
      -- Limpiar nombre del namespace
      local name_clean = item.name:match(":(.+)$") or item.name
      name_clean = name_clean:gsub("_", " ")
      name_clean = name_clean:sub(1,1):upper() .. name_clean:sub(2)
      table.insert(items, {
        slot  = slot,
        name  = name_clean,
        raw   = item.name,
        count = item.count,
      })
      used = used + 1
    end
    -- Ordenar por slot
    table.sort(items, function(a, b) return a.slot < b.slot end)
  end

  _cache[name] = { items=items, size=size, used=used, time=now }
  return items, size, used
end

-- ============================================================
--  Etiqueta del tipo de contenedor
-- ============================================================
local function containerLabel(rawType)
  if rawType:find("barrel")  then return "Barril" end
  if rawType:find("chest")   then return "Cofre"  end
  if rawType:find("vault")   then return "Vault"  end
  return "Inv."
end

-- ============================================================
--  Render de un inventario (altura variable)
--  Retorna lineas usadas
-- ============================================================
local function renderOne(t, x, y, w, name, entry, maxLines)
  local useC  = t.color
  local col   = useC and colors.cyan      or nil
  local dim   = useC and colors.lightGray or nil
  local norm  = useC and colors.white     or nil

  local items, size, used = readItems(name, entry.periph)
  local label = containerLabel(entry.rawType or "")
  local line  = y

  -- Titulo: tipo + ocupacion
  local pct     = size > 0 and (used / size) or 0
  local pctStr  = string.format("%d/%d", used, size)
  local title   = "-- " .. label .. " [" .. name .. "] --"
  renderer.writeLine(t, x, line, title, w, col)
  line = line + 1

  -- Barra de ocupacion
  local barW  = w - #pctStr - 1
  local bar   = renderer.progressBar(pct, barW)
  renderer.writeLine(t, x, line, bar .. " " .. pctStr, w,
    useC and renderer.alertColor(1 - pct, true) or nil)
  line = line + 1

  -- Lista de items (hasta maxLines - 2 lineas de header)
  local remaining = maxLines - 2
  if #items == 0 then
    renderer.writeLine(t, x, line, " (vacio)", w, dim)
    line = line + 1
  else
    for _, item in ipairs(items) do
      if remaining <= 0 then
        renderer.writeLine(t, x, line, " +" .. (#items - (line - y - 2)) .. " mas...", w, dim)
        line = line + 1
        break
      end
      local countStr = "x" .. item.count
      local nameW    = w - #countStr - 2
      local nameStr  = item.name
      if #nameStr > nameW then nameStr = nameStr:sub(1, nameW-1) .. ">" end
      renderer.writeLine(t, x, line,
        " " .. nameStr .. string.rep(" ", nameW - #nameStr) .. countStr,
        w, norm)
      line      = line + 1
      remaining = remaining - 1
    end
  end

  return line - y
end

-- ============================================================
--  Render de todos los inventarios
-- ============================================================
function inventory.renderAll(t, x, y, w, h)
  local all = detector.getByType("inventory")
  if not next(all) then
    renderer.writeLine(t, x, y, "Sin inventarios detectados", w,
      t.color and colors.lightGray or nil)
    return
  end

  local line      = y
  local remaining = h
  local count     = 0

  for name, entry in pairs(all) do
    if remaining < 3 then break end

    -- Separador entre inventarios
    if count > 0 then
      renderer.writeLine(t, x, line, string.rep("-", w), w,
        t.color and colors.gray or nil)
      line      = line + 1
      remaining = remaining - 1
    end

    -- Dar como maximo la mitad del espacio restante a cada uno
    -- para que quepan varios si los hay
    local allNames = {}
    for n in pairs(all) do table.insert(allNames, n) end
    local slot = math.max(4, math.floor(remaining / math.max(1, #allNames - count)))

    local used = renderOne(t, x, line, w, name, entry, slot)
    line      = line + used
    remaining = remaining - used
    count     = count + 1
  end
end

function inventory.heightNeeded()
  local count = 0
  for _ in pairs(detector.getByType("inventory")) do count = count + 1 end
  -- 4 lineas minimas por inventario (header + barra + 2 items) + separadores
  return math.max(4, count * 6)
end

return inventory
