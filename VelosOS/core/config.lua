-- ============================================================
--  VelosOS  |  core/config.lua
--  Guarda y carga la configuracion del vehiculo en disco
-- ============================================================

local CONFIG_PATH = "data/config.cfg"
local _data = {}

-- Profiles disponibles con etiquetas de datos relevantes
local PROFILES = {
  { id = "terrestre", label = "Terrestre",   icon = "[T]" },
  { id = "aereo",     label = "Aereo",       icon = "[A]" },
  { id = "espacial",  label = "Espacial",    icon = "[E]" },
  { id = "nautico",   label = "Nautico",     icon = "[N]" },
}

function load()
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

function save()
  -- Asegurar que la carpeta exista
  if not fs.exists("data") then fs.makeDir("data") end
  local f = fs.open(CONFIG_PATH, "w")
  if f then
    f.write(textutils.serialise(_data))
    f.close()
  end
end

function get(key, default)
  local v = _data[key]
  if v == nil then return default end
  return v
end

function set(key, value)
  _data[key] = value
  save()
end

-- Devuelve lista de perfiles para el menu
function getProfiles()
  return PROFILES
end

-- ============================================================
--  Primer arranque: setup interactivo en la terminal
-- ============================================================
function firstTimeSetup(renderTarget)
  local t = renderTarget.term
  t.setBackgroundColor(colors.black)
  t.clear()
  t.setCursorPos(1, 1)

  -- Helper local para escribir con color
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

  set("vehicle_profile", PROFILES[choice].id)
  set("vehicle_label",   PROFILES[choice].label)

  cprint(colors.lime, "")
  cprint(colors.lime, " Perfil guardado: " .. PROFILES[choice].label)
  cprint(colors.lightGray, " Puedes cambiarlo desde el menu.")
  sleep(1.5)
end
