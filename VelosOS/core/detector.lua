-- ============================================================
--  VelosOS  |  core/detector.lua
--  Escanea perifericos opcionales y los registra.
--  Se vuelve a llamar en eventos peripheral / peripheral_detach
-- ============================================================

-- Tabla de perifericos activos: { id -> { type, label, periph } }
local _active = {}

-- Tipos conocidos y su etiqueta para el OS
local KNOWN_TYPES = {
  ["fluid_storage"]        = "tank",
  ["monitor"]              = "monitor",
  ["create_source"]        = "display_link",
  ["create_target"]        = "display_target",
  ["playerDetector"]       = "radar",
  ["chatBox"]              = "comms",
  ["environmentDetector"]  = "environment",
  ["cbc_cannon_mount"]     = "cannon",
  ["energy_storage"]       = "energy",
}

-- ============================================================
--  Escaneo completo
-- ============================================================
function scan()
  _active = {}
  local names = peripheral.getNames()
  for _, name in ipairs(names) do
    _registerPeripheral(name)
  end
  return _active
end

-- Registra un periferico por su nombre de lado/red
function _registerPeripheral(name)
  local ptype = peripheral.getType(name)
  if not ptype then return end

  -- peripheral.getType puede devolver multiples tipos en CC:T moderno
  -- revisamos todos
  local matched = nil
  if type(ptype) == "table" then
    for _, t in ipairs(ptype) do
      if KNOWN_TYPES[t] then matched = KNOWN_TYPES[t]; break end
    end
  else
    matched = KNOWN_TYPES[ptype]
  end

  if matched then
    local p = peripheral.wrap(name)
    if p then
      _active[name] = {
        osType  = matched,
        rawType = ptype,
        label   = matched .. " [" .. name .. "]",
        periph  = p,
        online  = true,
      }
    end
  end
end

-- ============================================================
--  Eventos de conexion/desconexion (llamar desde el event loop)
-- ============================================================
function onAttach(name)
  _registerPeripheral(name)
  -- Actualizar Display Links en el renderer
  renderer.refreshExtras()
  return _active[name]  -- nil si no es tipo conocido
end

function onDetach(name)
  local was = _active[name]
  _active[name] = nil
  renderer.refreshExtras()
  return was  -- devuelve el entry que se elimino (para mostrar notif)
end

-- ============================================================
--  Consultas
-- ============================================================

-- Devuelve todos los perifericos de un osType dado
function getByType(osType)
  local result = {}
  for name, entry in pairs(_active) do
    if entry.osType == osType then
      result[name] = entry
    end
  end
  return result
end

-- Devuelve true si hay al menos uno del tipo dado
function hasType(osType)
  for _, entry in pairs(_active) do
    if entry.osType == osType then return true end
  end
  return false
end

-- Devuelve tabla completa para debug/menu
function getAll()
  return _active
end

-- Lista legible para pantalla de estado
function getSummary()
  local lines = {}
  if next(_active) == nil then
    table.insert(lines, "  Sin perifericos opcionales")
    return lines
  end
  for name, entry in pairs(_active) do
    table.insert(lines, "  [+] " .. entry.label)
  end
  table.sort(lines)
  return lines
end
