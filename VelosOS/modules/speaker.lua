-- ============================================================
--  VelosOS  |  modules/speaker.lua
--  Alertas de audio via Speaker de CC:Tweaked
--  Prioridades: CRITICO > ALERTA > INFO
--  No spamea: cada alerta tiene cooldown individual
-- ============================================================

local spk = {}

local _speaker   = nil
local _cooldowns = {}   -- { alertId -> lastPlayed (epoch s) }

-- Cooldowns en segundos por tipo de alerta
local COOLDOWN = {
  missile   = 3,
  fuel_crit = 8,
  fuel_low  = 20,
  energy_low= 20,
  offline   = 5,
  fired     = 1,
  info      = 5,
}

-- ============================================================
--  Init
-- ============================================================
function spk.init()
  local entries = detector.getByType("speaker")
  for _, e in pairs(entries) do
    _speaker = e.periph
    break
  end
  return _speaker ~= nil
end

function spk.isAvailable()
  return _speaker ~= nil
end

-- ============================================================
--  Cooldown helper
-- ============================================================
local function canPlay(alertId)
  local cd  = COOLDOWN[alertId] or 5
  local now = os.epoch("utc") / 1000
  local last = _cooldowns[alertId] or 0
  if now - last >= cd then
    _cooldowns[alertId] = now
    return true
  end
  return false
end

-- ============================================================
--  Reproducir nota musical como alerta
--  instrument: "harp","bass","bell","flute","chime","guitar"
--  notes: lista de { pitch(0-24), duration(s) }
-- ============================================================
local function playNotes(instrument, notes)
  if not _speaker then return end
  for _, n in ipairs(notes) do
    pcall(function()
      _speaker.playNote(instrument, 1.0, n[1])
    end)
    if n[2] and n[2] > 0 then sleep(n[2]) end
  end
end

-- ============================================================
--  Alertas predefinidas
-- ============================================================

-- Misil entrante — sonido urgente (3 beeps agudos rapidos)
function spk.missilWarning()
  if not canPlay("missile") then return end
  playNotes("bell", {
    {24, 0.08}, {24, 0.08}, {24, 0.08},
    {20, 0.08}, {20, 0.08}, {20, 0.08},
    {24, 0.0},
  })
end

-- Combustible critico (<5%) — tono grave largo
function spk.fuelCritical()
  if not canPlay("fuel_crit") then return end
  playNotes("bass", {
    {5, 0.2}, {5, 0.2}, {5, 0.0},
  })
end

-- Combustible bajo (<20%) — dos notas medias
function spk.fuelLow()
  if not canPlay("fuel_low") then return end
  playNotes("harp", {
    {12, 0.15}, {10, 0.0},
  })
end

-- Energia baja
function spk.energyLow()
  if not canPlay("energy_low") then return end
  playNotes("guitar", {
    {10, 0.15}, {8, 0.0},
  })
end

-- Periferico desconectado
function spk.peripheralOffline()
  if not canPlay("offline") then return end
  playNotes("harp", {
    {15, 0.1}, {10, 0.1}, {5, 0.0},
  })
end

-- Canon disparado
function spk.fired()
  if not canPlay("fired") then return end
  playNotes("bass", {
    {2, 0.05}, {0, 0.0},
  })
end

-- Info general (confirmacion)
function spk.info()
  if not canPlay("info") then return end
  playNotes("harp", {
    {12, 0.08}, {16, 0.0},
  })
end

-- ============================================================
--  Tick de alertas automaticas
--  Llamar desde el loop principal en cada refresh
-- ============================================================
function spk.checkAlerts()
  if not _speaker then return end

  -- Alerta de combustible
  if detector.hasType("tank") then
    local fuel, cap = tanks.getTotalFuel()
    if cap > 0 then
      local pct = fuel / cap
      if pct < 0.05 then
        spk.fuelCritical()
      elseif pct < 0.20 then
        spk.fuelLow()
      end
    end
  end

  -- Alerta de misil (se llama desde cannon cuando detecta)
  -- No se revisa aqui para evitar doble lectura del radar
end

return spk
