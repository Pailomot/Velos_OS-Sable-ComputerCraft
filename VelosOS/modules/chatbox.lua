-- ============================================================
--  VelosOS  |  modules/chatbox.lua
--  Envia mensajes al chat del servidor via chatBox
--  Solo para alertas criticas, no spam
-- ============================================================

local chatbox = {}

local _periph    = nil
local _cooldowns = {}
local _name      = "VelosOS"   -- nombre que aparece en el chat

local COOLDOWN = {
  missile  = 10,
  fuel     = 30,
  energy   = 30,
  offline  = 15,
  custom   = 5,
}

-- ============================================================
--  Init
-- ============================================================
function chatbox.init()
  local entries = detector.getByType("comms")
  for _, e in pairs(entries) do
    _periph = e.periph
    break
  end
  -- Leer nombre del vehiculo de config
  _name = config.get("vehicle_name", sublevel.getName() or "VelosOS")
  return _periph ~= nil
end

function chatbox.isAvailable()
  return _periph ~= nil
end

-- ============================================================
--  Cooldown
-- ============================================================
local function canSend(id)
  local cd  = COOLDOWN[id] or 5
  local now = os.epoch("utc") / 1000
  if (now - (_cooldowns[id] or 0)) >= cd then
    _cooldowns[id] = now
    return true
  end
  return false
end

-- ============================================================
--  Enviar mensaje
-- ============================================================
local function send(text, brackets)
  if not _periph then return false end
  brackets = brackets or "&7[" .. _name .. "]&r"
  local ok, err = pcall(function()
    _periph.sendMessage(text, brackets)
  end)
  return ok
end

-- ============================================================
--  Mensajes predefinidos
-- ============================================================
function chatbox.missilWarning(dist)
  if not canSend("missile") then return end
  send(string.format(
    "&c⚠ MISIL ENTRANTE a %.0fm del vehiculo!", dist))
end

function chatbox.fuelCritical(pct)
  if not canSend("fuel") then return end
  send(string.format(
    "&6⚠ Combustible critico: %.0f%%", pct * 100))
end

function chatbox.energyLow(pct)
  if not canSend("energy") then return end
  send(string.format(
    "&e⚠ Energia baja: %.0f%%", pct * 100))
end

function chatbox.peripheralOffline(label)
  if not canSend("offline") then return end
  send("&7Periferico desconectado: " .. label)
end

function chatbox.custom(text)
  if not canSend("custom") then return end
  send(text)
end

return chatbox
