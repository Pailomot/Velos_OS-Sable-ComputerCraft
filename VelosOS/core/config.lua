-- ============================================================
--  VelosOS  |  core/config.lua
-- ============================================================

local config = {}

local CONFIG_PATH = "data/config.cfg"
local _data = {}

local PROFILES = {
  { id = "terrestre", label = "Terrestre",   icon = "[T]" },
  { id = "aereo",     label = "Aereo",       icon = "[A]" },
  { id = "espacial",  label = "Espacial",    icon = "[E]" },
  { id = "nautico",   label = "Nautico",     icon = "[N]" },
}

function config.load()
  _data = {}
  if fs.exists(CONFIG_PATH) then
    local f = fs.open(CONFIG_PATH, "r")
    if f then
      local raw = f.readAll()
      f.close()
      local parsed = textutils.unserialise(raw)
      if parsed then _data = parsed end
    end
  end
end

function config.save()
  if not fs.exists("data") then fs.makeDir("data") end
  local f = fs.open(CONFIG_PATH, "w")
  if f then
    f.write(textutils.serialise(_data))
    f.close()
  end
end

function config.get(key, default)
  local v = _data[key]
  if v == nil then return default end
  return v
end

function config.set(key, value)
  _data[key] = value
  config.save()
end

function config.getProfiles()
  return PROFILES
end

function config.firstTimeSetup(renderTarget)
  local t = renderTarget.term
  t.setBackgroundColor(colors.black)
  t.clear()
  t.setCursorPos(1, 1)

  local function cprint(color, text)
    t.setTextColor(color)
    t.setCursorPos(1, ({t.getCursorPos()})[2])
    print(text)
  end

  cprint(colors.yellow, " ============================")
  cprint(colors.yellow, "   CONFIGURACION INICIAL     ")
  cprint(colors.yellow, " ============================")
  cprint(colors.white,  "")
  cprint(colors.white,  " Elige el perfil del vehiculo:")
  cprint(colors.white,  "")

  for i, p in ipairs(PROFILES) do
    t.setTextColor(colors.cyan)
    print("  [" .. i .. "] " .. p.icon .. " " .. p.label)
  end

  cprint(colors.white, "")
  cprint(colors.lightGray, " Escribe el numero y Enter:")
  t.setTextColor(colors.white)

  local choice = tonumber(read())
  while not choice or not PROFILES[choice] do
    cprint(colors.red, " Opcion invalida. Intenta de nuevo:")
    t.setTextColor(colors.white)
    choice = tonumber(read())
  end

  config.set("vehicle_profile", PROFILES[choice].id)
  config.set("vehicle_label",   PROFILES[choice].label)

  cprint(colors.lime, "")
  cprint(colors.lime, " Perfil guardado: " .. PROFILES[choice].label)
  cprint(colors.lightGray, " Puedes cambiarlo desde el menu.")
  sleep(1.5)
end

return config
