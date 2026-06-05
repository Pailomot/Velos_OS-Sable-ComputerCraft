-- ============================================================
--  VelosOS  |  modules/tanks.lua
-- ============================================================

local tanks = {}

local TANKS_CFG_KEY  = "tank_types"
local RATE_SAMPLES   = 8      -- cuantas lecturas para la media movil
local MIN_DT         = 0.4    -- segundos minimos entre lecturas

local _history = {}   -- { amount, time, samples = {{delta,dt},...} }
local _types   = {}

-- ============================================================
--  Init
-- ============================================================
function tanks.init()
  _types = config.get(TANKS_CFG_KEY, {})
end

-- ============================================================
--  Clasificacion interactiva
-- ============================================================
function tanks.classifyTank(tankName, renderTarget)
  local t = renderTarget.term
  t.setBackgroundColor(colors.black)
  t.clear()
  t.setCursorPos(1, 1)

  t.setTextColor(colors.yellow)
  print(" ============================")
  print("   NUEVO TANK DETECTADO      ")
  print(" ============================")
  t.setTextColor(colors.white)
  print("")
  print(" Tank: " .. tankName)
  print("")
  print(" Que tipo de fluido maneja?")
  print("")
  t.setTextColor(colors.cyan)
  print("  [1] Combustible")
  print("      (mide consumo y tiempo)")
  print("")
  print("  [2] Carga")
  print("      (solo nivel y fluido)")
  t.setTextColor(colors.lightGray)
  print("")
  print(" Escribe 1 o 2 y Enter:")
  t.setTextColor(colors.white)

  local choice = tonumber(read())
  while choice ~= 1 and choice ~= 2 do
    t.setTextColor(colors.red)
    print(" Opcion invalida:")
    t.setTextColor(colors.white)
    choice = tonumber(read())
  end

  local tankType = (choice == 1) and "fuel" or "cargo"
  _types[tankName] = tankType
  config.set(TANKS_CFG_KEY, _types)

  t.setTextColor(colors.lime)
  print("")
  print(" Clasificado como: " ..
    (tankType == "fuel" and "Combustible" or "Carga"))
  sleep(1)
  return tankType
end

-- ============================================================
--  Leer capacidad total del tank
--  Create expone capacidad de formas distintas segun version:
--    1. slot.capacity  (por slot, hay que sumar todos)
--    2. periph.tankCapacity()  (total directo)
--  Probamos las dos y nos quedamos con la mayor.
-- ============================================================
local function readCapacity(periph, slots)
  local fromSlots = 0
  for _, s in ipairs(slots) do
    fromSlots = fromSlots + (s.capacity or 0)
  end

  local fromApi = 0
  local ok, cap = pcall(function() return periph.tankCapacity() end)
  if ok and type(cap) == "number" then fromApi = cap end

  -- Nos quedamos con el valor mas alto y mas de 0
  local result = math.max(fromSlots, fromApi)
  if result <= 0 then result = 1 end
  return result
end

-- ============================================================
--  Leer cantidad total de fluido (suma todos los slots)
-- ============================================================
local function readAmount(slots)
  local total = 0
  local name  = "Vacio"
  for _, s in ipairs(slots) do
    local amt = s.amount or 0
    total = total + amt
    if amt > 0 and s.name then name = s.name end
  end
  -- Limpiar prefijo de namespace
  name = name:match(":(.+)$") or name
  name = name:gsub("_", " ")
  name = name:sub(1,1):upper() .. name:sub(2)
  return total, name
end

-- ============================================================
--  Media movil de tasa de consumo
--  Guarda las ultimas RATE_SAMPLES deltas y promedia
-- ============================================================
local function updateRate(tankName, amount, now)
  local h = _history[tankName]
  if not h then
    _history[tankName] = { amount=amount, time=now, samples={} }
    return nil, nil, false
  end

  local dt = now - h.time
  if dt < MIN_DT then
    -- Todavia no paso suficiente tiempo, devolver ultimo calculo
    return h.lastRate, h.lastTimeLeft, h.lastCharging or false
  end

  local delta = h.amount - amount   -- positivo = consumiendo
  local instantRate = delta / dt

  -- Agregar muestra al historial circular
  local samples = h.samples
  table.insert(samples, instantRate)
  if #samples > RATE_SAMPLES then table.remove(samples, 1) end

  -- Calcular media descartando outliers extremos si hay suficientes muestras
  local rate = 0
  if #samples >= 3 then
    -- Ordenar copia y descartar el maximo y minimo
    local sorted = {}
    for _, v in ipairs(samples) do table.insert(sorted, v) end
    table.sort(sorted)
    local sum, count = 0, 0
    for i = 2, #sorted - 1 do   -- descartar primero y ultimo
      sum   = sum   + sorted[i]
      count = count + 1
    end
    rate = count > 0 and (sum / count) or sorted[math.ceil(#sorted/2)]
  else
    -- Con pocas muestras simplemente promediamos todo
    local sum = 0
    for _, v in ipairs(samples) do sum = sum + v end
    rate = sum / #samples
  end

  local timeLeft, charging = nil, false

  if rate < -0.5 then
    -- Recargando significativamente
    charging = true
    rate     = nil
  elseif rate < 0.5 then
    -- Variacion minima, consideramos motor apagado o idle
    rate     = 0
    timeLeft = nil
  else
    timeLeft = amount / rate
  end

  -- Actualizar historial
  _history[tankName] = {
    amount      = amount,
    time        = now,
    samples     = samples,
    lastRate     = rate,
    lastTimeLeft = timeLeft,
    lastCharging = charging,
  }

  return rate, timeLeft, charging
end

-- ============================================================
--  Lectura completa de un tank
-- ============================================================
function tanks.readTank(tankName, periph)
  local tankType = _types[tankName] or "unknown"

  local ok, slots = pcall(function() return periph.tanks() end)
  if not ok or not slots or #slots == 0 then
    return {
      name=tankName, tankType=tankType,
      fluid="Error", amount=0, capacity=1, pct=0,
      alert="empty",
    }
  end

  local amount, fluid = readAmount(slots)
  local capacity      = readCapacity(periph, slots)
  local pct           = math.min(1.0, amount / capacity)  -- clamp por seguridad

  local rate, timeLeft, charging = nil, nil, false
  if tankType == "fuel" then
    local now = os.epoch("utc") / 1000
    rate, timeLeft, charging = updateRate(tankName, amount, now)
  end

  local alert = "ok"
  if amount == 0     then alert = "empty"
  elseif pct < 0.05  then alert = "critical"
  elseif pct < 0.20  then alert = "low"
  end

  return {
    name      = tankName,
    tankType  = tankType,
    fluid     = fluid,
    amount    = amount,
    capacity  = capacity,
    pct       = pct,
    rate      = rate,
    timeLeft  = timeLeft,
    charging  = charging,
    alert     = alert,
  }
end

-- ============================================================
--  Render de un tank (4 lineas)
-- ============================================================
function tanks.renderTank(t, x, y, w, data)
  local useColor = t.color

  -- Linea 1: nombre del fluido + etiqueta de tipo
  local typeTag = (data.tankType == "fuel")  and "[COMB]"  or
                  (data.tankType == "cargo") and "[CARGA]" or "[?]"
  local title = data.fluid
  local gap   = w - #title - #typeTag
  if gap < 1 then
    title = title:sub(1, w - #typeTag - 2) .. ">"
    gap   = 1
  end
  renderer.write(t, x, y,
    title .. string.rep(" ", gap) .. typeTag,
    useColor and colors.white or nil)

  -- Linea 2: barra de progreso + porcentaje
  local pctStr = string.format("%3d%%", math.min(999, math.floor(data.pct * 100)))
  local barW   = w - #pctStr - 1
  local bar    = renderer.progressBar(data.pct, barW)
  renderer.write(t, x, y+1, bar .. " " .. pctStr,
    useColor and renderer.alertColor(data.pct, true) or nil)

  -- Linea 3: cantidad / capacidad
  local amtStr = renderer.formatNum(data.amount) .. " / " ..
                 renderer.formatNum(data.capacity) .. " mB"
  renderer.write(t, x, y+2,
    renderer.truncate(amtStr, w),
    useColor and colors.lightGray or nil)

  -- Linea 4: estado (solo para combustible)
  if data.tankType == "fuel" then
    local statusStr, alertFg

    if data.alert == "empty" then
      statusStr = "!!! SIN COMBUSTIBLE !!!"
      alertFg   = useColor and colors.red or nil
    elseif data.charging then
      statusStr = "Cargando..."
      alertFg   = useColor and colors.cyan or nil
    elseif data.rate == nil then
      statusStr = "Calculando..."
      alertFg   = useColor and colors.lightGray or nil
    elseif data.rate == 0 then
      statusStr = "Motor apagado / idle"
      alertFg   = useColor and colors.lightGray or nil
    else
      local timeStr = data.timeLeft and
                      renderer.formatTime(data.timeLeft) or "--:--"
      statusStr = string.format("%.1f mB/s  |  %s rest.", data.rate, timeStr)
      alertFg   = useColor and (
        data.alert == "critical" and colors.red    or
        data.alert == "low"      and colors.orange or
        colors.lightGray) or nil
    end

    renderer.write(t, x, y+3,
      renderer.truncate(statusStr, w), alertFg)
  else
    -- Para carga solo mostramos nivel
    renderer.write(t, x, y+3,
      renderer.truncate(string.format("Nivel: %.1f%%", data.pct*100), w),
      useColor and colors.lightGray or nil)
  end
end

-- ============================================================
--  Render de todos los tanks
-- ============================================================
function tanks.renderAll(renderTarget, x, y, w, h)
  local allTanks = detector.getByType("tank")
  if not next(allTanks) then
    renderer.write(renderTarget, x, y,
      renderer.truncate("Sin tanks detectados", w),
      renderTarget.color and colors.lightGray or nil)
    return
  end

  local rowH = 5
  local row  = 0
  for tankName, entry in pairs(allTanks) do
    if (row * rowH) + 4 > h then break end
    if _types[tankName] == nil then
      tanks.classifyTank(tankName, renderTarget)
    end
    if row > 0 then
      renderer.write(renderTarget, x, y + (row * rowH) - 1,
        string.rep("-", w),
        renderTarget.color and colors.gray or nil)
    end
    local data = tanks.readTank(tankName, entry.periph)
    tanks.renderTank(renderTarget, x, y + (row * rowH), w, data)
    row = row + 1
  end
end

-- ============================================================
--  Total de combustible para Display Link / header
-- ============================================================
function tanks.getTotalFuel()
  local total, cap = 0, 0
  for tankName, entry in pairs(detector.getByType("tank")) do
    if (_types[tankName] or "unknown") == "fuel" then
      local ok, slots = pcall(function() return entry.periph.tanks() end)
      if ok and slots then
        local amt, _ = readAmount(slots)
        local c      = readCapacity(entry.periph, slots)
        total = total + amt
        cap   = cap   + c
      end
    end
  end
  return total, cap
end

return tanks
