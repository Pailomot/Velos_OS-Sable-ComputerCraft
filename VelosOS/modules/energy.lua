-- ============================================================
--  VelosOS  |  modules/energy.lua
--  Monitoreo de energia FE via energy_storage
--  Misma logica de media movil que tanks.lua
-- ============================================================

local energy = {}

local RATE_SAMPLES = 6
local MIN_DT       = 0.4
local _history     = {}   -- { periph_name -> { energy, time, samples, ... } }

-- ============================================================
--  Init
-- ============================================================
function energy.init()
  -- Nada que configurar, lee directamente del detector
end

-- ============================================================
--  Media movil de tasa de consumo (igual que tanks)
-- ============================================================
local function updateRate(name, amount, now)
  local h = _history[name]
  if not h then
    _history[name] = { amount=amount, time=now, samples={} }
    return nil, nil, false
  end

  local dt = now - h.time
  if dt < MIN_DT then
    return h.lastRate, h.lastTimeLeft, h.lastCharging or false
  end

  local delta       = h.amount - amount   -- positivo = consumiendo
  local instantRate = delta / dt

  local samples = h.samples
  table.insert(samples, instantRate)
  if #samples > RATE_SAMPLES then table.remove(samples, 1) end

  local rate = 0
  if #samples >= 3 then
    local sorted = {}
    for _, v in ipairs(samples) do table.insert(sorted, v) end
    table.sort(sorted)
    local sum, count = 0, 0
    for i = 2, #sorted - 1 do sum = sum + sorted[i]; count = count + 1 end
    rate = count > 0 and (sum / count) or sorted[math.ceil(#sorted/2)]
  else
    local sum = 0
    for _, v in ipairs(samples) do sum = sum + v end
    rate = #samples > 0 and (sum / #samples) or 0
  end

  local timeLeft, charging = nil, false
  if rate < -10 then
    charging = true; rate = nil
  elseif rate < 1 then
    rate = 0
  else
    timeLeft = amount / rate
  end

  _history[name] = {
    amount=amount, time=now, samples=samples,
    lastRate=rate, lastTimeLeft=timeLeft, lastCharging=charging,
  }
  return rate, timeLeft, charging
end

-- ============================================================
--  Leer un storage
-- ============================================================
local function readStorage(name, periph)
  local ok1, energy_amt = pcall(function() return periph.getEnergy()         end)
  local ok2, energy_cap = pcall(function() return periph.getEnergyCapacity() end)

  local amount   = ok1 and energy_amt or 0
  local capacity = ok2 and energy_cap or 1
  if capacity <= 0 then capacity = 1 end

  local pct  = math.min(1.0, amount / capacity)
  local now  = os.epoch("utc") / 1000
  local rate, timeLeft, charging = updateRate(name, amount, now)

  local alert = "ok"
  if amount == 0     then alert = "empty"
  elseif pct < 0.05  then alert = "critical"
  elseif pct < 0.20  then alert = "low"
  end

  return {
    name     = name,
    amount   = amount,
    capacity = capacity,
    pct      = pct,
    rate     = rate,
    timeLeft = timeLeft,
    charging = charging,
    alert    = alert,
  }
end

-- ============================================================
--  Render de un storage (4 lineas)
-- ============================================================
local function renderStorage(t, x, y, w, data)
  local useC = t.color

  -- Titulo
  local tag = "[FE]"
  local title = renderer.truncate(data.name, w - #tag - 1)
  renderer.write(t, x, y,
    title .. string.rep(" ", w - #title - #tag) .. tag,
    useC and colors.white or nil)

  -- Barra
  local pctStr = string.format("%3d%%", math.floor(data.pct * 100))
  local barW   = w - #pctStr - 1
  renderer.write(t, x, y+1,
    renderer.progressBar(data.pct, barW) .. " " .. pctStr,
    useC and renderer.alertColor(data.pct, true) or nil)

  -- Cantidad
  local function fmtFE(n)
    if n >= 1000000 then return string.format("%.1fM", n/1000000)
    elseif n >= 1000 then return string.format("%.1fk", n/1000)
    else return tostring(math.floor(n)) end
  end
  renderer.write(t, x, y+2,
    renderer.truncate(fmtFE(data.amount) .. " / " .. fmtFE(data.capacity) .. " FE", w),
    useC and colors.lightGray or nil)

  -- Tasa / tiempo
  local statusStr, fg
  if data.alert == "empty" then
    statusStr = "SIN ENERGIA"
    fg = useC and colors.red or nil
  elseif data.charging then
    statusStr = "Cargando..."
    fg = useC and colors.cyan or nil
  elseif data.rate == nil then
    statusStr = "Calculando..."
    fg = useC and colors.lightGray or nil
  elseif data.rate == 0 then
    statusStr = "En espera"
    fg = useC and colors.lightGray or nil
  else
    local timeStr = data.timeLeft and renderer.formatTime(data.timeLeft) or "--:--"
    statusStr = string.format("%.0f FE/s  |  %s rest.", data.rate, timeStr)
    fg = useC and (
      data.alert == "critical" and colors.red   or
      data.alert == "low"      and colors.orange or
      colors.lightGray) or nil
  end
  renderer.write(t, x, y+3, renderer.truncate(statusStr, w), fg)
end

-- ============================================================
--  Render de todos los storages
-- ============================================================
function energy.renderAll(t, x, y, w, h)
  local storages = detector.getByType("energy")
  if not next(storages) then
    renderer.write(t, x, y,
      renderer.truncate("Sin almacen de energia", w),
      t.color and colors.lightGray or nil)
    return
  end

  local rowH = 5
  local row  = 0
  for name, entry in pairs(storages) do
    if (row * rowH) + 4 > h then break end
    if row > 0 then
      renderer.write(t, x, y + (row * rowH) - 1,
        string.rep("-", w), t.color and colors.gray or nil)
    end
    local data = readStorage(name, entry.periph)
    renderStorage(t, x, y + (row * rowH), w, data)
    row = row + 1
  end
end

function energy.heightNeeded()
  local count = 0
  for _ in pairs(detector.getByType("energy")) do count = count + 1 end
  return math.max(5, count * 5)
end

-- Para alertas del speaker
function energy.getLowestPct()
  local lowest = 1.0
  for name, entry in pairs(detector.getByType("energy")) do
    local ok1, amt = pcall(function() return entry.periph.getEnergy()         end)
    local ok2, cap = pcall(function() return entry.periph.getEnergyCapacity() end)
    if ok1 and ok2 and cap > 0 then
      local pct = amt / cap
      if pct < lowest then lowest = pct end
    end
  end
  return lowest
end

return energy
