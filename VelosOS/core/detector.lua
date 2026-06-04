-- ============================================================
--  VelosOS  |  core/detector.lua
-- ============================================================

local detector = {}

local _active = {}

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

local function _registerPeripheral(name)
  local ptype = peripheral.getType(name)
  if not ptype then return end

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

return detector
