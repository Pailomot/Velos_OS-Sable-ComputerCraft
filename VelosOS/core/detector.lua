-- ============================================================
--  VelosOS  |  core/detector.lua
-- ============================================================

local detector = {}

local _active = {}

-- Tipos de fluidos (tanks)
-- Create puede exponer el tank con cualquiera de estos tipos
-- segun version del mod y como este conectado
local FLUID_TYPES = {
  "fluid_storage",
  "fluidStorage",
  "create:fluid_tank",
  "createFluidTank",
  "forge:fluid_handler",
}

-- Tipos de inventario solido (cofres, barriles, vaults, etc)
local INVENTORY_TYPES = {
  "inventory",
  "minecraft:chest",
  "minecraft:barrel",
  "create:vault",
  "create:chest",
  "ironchest:iron_chest",
  "ironchest:gold_chest",
  "ironchest:diamond_chest",
  "sophisticatedbackpacks:backpack",
}

local KNOWN_TYPES = {
  -- Display
  ["monitor"]              = "monitor",
  ["create_source"]        = "display_link",
  ["create_target"]        = "display_target",
  -- Perifericos Advanced Peripherals
  ["playerDetector"]       = "radar",
  ["chatBox"]              = "comms",
  ["environmentDetector"]  = "environment",
  -- Armamento
  ["cbc_cannon_mount"]     = "cannon",
  -- Energia
  ["energy_storage"]       = "energy",
  ["forge:energy_storage"] = "energy",
  -- Speaker
  ["speaker"]              = "speaker",
  -- Modem
  ["modem"]                = "modem",
  -- Create Scroller
  ["create_scroller"]                  = "scroller",
  -- Create Radar
  ["create_radar:radar_bearing"]       = "cr_bearing",
  ["create_radar:monitor"]             = "cr_monitor",
  ["create_radar:auto_yaw_controller"] = "cr_yaw",
  ["create_radar:auto_pitch_controller"] = "cr_pitch",
  ["create_radar:plane_radar"]         = "cr_plane",
  ["create_radar:fire_controller"]     = "cr_fire",
}

-- Agrega todos los tipos de fluido y de inventario a KNOWN_TYPES
for _, t in ipairs(FLUID_TYPES)     do KNOWN_TYPES[t] = "tank"      end
for _, t in ipairs(INVENTORY_TYPES) do KNOWN_TYPES[t] = "inventory" end

-- ============================================================
--  Registro de un periferico
-- ============================================================
local function _registerPeripheral(name)
  local ptypes = peripheral.getType(name)
  if not ptypes then return end

  -- Normalizar siempre a tabla para manejar ambos casos
  if type(ptypes) == "string" then ptypes = { ptypes } end

  local matched = nil
  local matchedRaw = nil
  for _, t in ipairs(ptypes) do
    if KNOWN_TYPES[t] then
      matched    = KNOWN_TYPES[t]
      matchedRaw = t
      break
    end
  end

  if matched then
    local p = peripheral.wrap(name)
    if p then
      _active[name] = {
        osType   = matched,
        rawType  = matchedRaw,
        allTypes = ptypes,      -- guardamos todos los tipos para diagnostico
        label    = matched .. " [" .. name .. "]",
        periph   = p,
        online   = true,
      }
    end
  end
end

-- ============================================================
--  API publica
-- ============================================================
function detector.scan()
  _active = {}
  for _, name in ipairs(peripheral.getNames()) do
    _registerPeripheral(name)
  end
  return _active
end

function detector.onAttach(name)
  _registerPeripheral(name)
  renderer.refreshExtras()
  return _active[name]
end

function detector.onDetach(name)
  local was = _active[name]
  _active[name] = nil
  renderer.refreshExtras()
  return was
end

function detector.getByType(osType)
  local result = {}
  for name, entry in pairs(_active) do
    if entry.osType == osType then
      result[name] = entry
    end
  end
  return result
end

function detector.hasType(osType)
  for _, entry in pairs(_active) do
    if entry.osType == osType then return true end
  end
  return false
end

function detector.getAll()
  return _active
end

function detector.getSummary()
  local lines = {}
  if not next(_active) then
    table.insert(lines, "  Sin perifericos opcionales")
    return lines
  end
  for _, entry in pairs(_active) do
    table.insert(lines, "  [+] " .. entry.label)
  end
  table.sort(lines)
  return lines
end

-- ============================================================
--  Diagnostico: lista TODOS los perifericos con sus tipos
--  reales aunque no sean reconocidos por el OS.
--  Util para detectar tanks con nombres de tipo inesperados.
-- ============================================================
function detector.diagnose(renderTarget)
  local t    = renderTarget.term
  local w    = renderTarget.w
  local useC = renderTarget.color

  t.setBackgroundColor(colors.black)
  t.setTextColor(colors.white)
  t.clear()
  t.setCursorPos(1,1)

  if useC then t.setTextColor(colors.yellow) end
  print(("= DIAGNOSTICO PERIFERICOS ="):sub(1,w))
  print(string.rep("-", w))

  -- Listar TODOS los nombres incluyendo red wired
  local names = peripheral.getNames()
  if #names == 0 then
    if useC then t.setTextColor(colors.gray) end
    print("  Sin perifericos conectados.")
  end

  for _, name in ipairs(names) do
    local ptypes = peripheral.getType(name)
    if type(ptypes) == "string" then ptypes = { ptypes } end

    local entry   = _active[name]
    local osLabel = entry and ("[" .. entry.osType .. "]") or "[desconocido]"

    if useC then
      t.setTextColor(entry and colors.lime or colors.orange)
    end
    -- Mostrar nombre completo del periferico
    print((" " .. name .. "  " .. osLabel):sub(1,w))

    if useC then t.setTextColor(colors.lightGray) end
    for _, tp in ipairs(ptypes or {}) do
      print(("   tipo: " .. tp):sub(1,w))
    end
  end

  if useC then t.setTextColor(colors.gray) end
  print(string.rep("-", w))
  -- Mostrar nombre del monitor principal detectado
  local mainMon = renderer.getMainMonitorName()
  if mainMon then
    print((" Monitor principal: " .. mainMon):sub(1,w))
  end
  print(" Presiona cualquier tecla...")
  t.setTextColor(colors.white)

  while true do
    local ev = os.pullEvent()
    if ev == "key" or ev == "mouse_click" or ev == "monitor_touch" then break end
  end

  t.setBackgroundColor(colors.black)
  t.clear()
end

return detector
