-- ============================================================
--  VelosOS  |  modules/tanks.lua
--  Maneja fluid_storage perifericos.
--  Cada tank se clasifica como "fuel" o "cargo" y se guarda
--  en config. Calcula tasa de consumo y tiempo restante.
-- ============================================================

local TANKS_CFG_KEY = "tank_types"   -- clave en config.lua

-- Historial de lecturas para calcular tasa de consumo
--   _history[tankName] = { amount, time }
local _history = {}

-- Cache de la clasificacion guardada
local _types = {}   -- tankName -> "fuel" | "cargo"

-- ============================================================
--  Inicializacion
-- ============================================================
function init()
  local saved = config.get(TANKS_CFG_KEY, {})
  _types = saved
end

-- ============================================================
--  Clasificacion interactiva de un tank nuevo
-- ============================================================
function classifyTank(tankName, renderTarget)
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
  print(" Clasificado como: " .. (tankType == "fuel" and "Combustible" or "Carga"))
  sleep(1)

  return tankType
end

-- ============================================================
--  Lectura y calculo de un tank
-- ============================================================

--  Devuelve tabla con todos los datos calculados del tank:
--  {
--    name        : nombre del periferico
--    tankType    : "fuel" | "cargo" | "unknown"
--    fluid       : string (nombre del fluido o "Vacio")
--    amount      : number (mB actuales)
--    capacity    : number (mB maximos)
--    pct         : number (0.0 a 1.0)
--    rate        : number|nil  (mB/s, solo fuel, nil si no hay datos aun)
--    timeLeft    : number|nil  (segundos restantes, nil si tasa <= 0)
--    charging    : boolean     (tasa negativa = recargando)
--    alert       : "ok"|"low"|"critical"|"empty"
--  }
function readTank(tankName, periph)
  local tankType = _types[tankName] or "unknown"

  -- fluid_storage devuelve tabla de tanks internos
  local ok, tanks = pcall(function() return periph.tanks() end)
  if not ok or not tanks or #tanks == 0 then
    return {
      name = tankName, tankType = tankType,
      fluid = "Error", amount = 0, capacity = 1, pct = 0,
      alert = "empty",
    }
  end

  -- Usamos el primer slot con fluido, o el primero si todos vacios
  local slot = tanks[1]
  for _, s in ipairs(tanks) do
    if s.amount and s.amount > 0 then slot = s; break end
  end

  local amount   = slot.amount   or 0
  local capacity = slot.capacity or 1
  local fluid    = slot.name     or "Vacio"
  -- Quitar prefijo "minecraft:" o mod: del nombre
  fluid = fluid:match(":(.+)$") or fluid
  -- Capitalizar primera letra
  fluid = fluid:sub(1,1):upper() .. fluid:sub(2)

  local pct = amount / capacity

  -- Calcular tasa solo para fuel
  local rate, timeLeft, charging = nil, nil, false
  if tankType == "fuel" then
    local now  = os.epoch("utc") / 1000   -- segundos reales
    local prev = _history[tankName]

    if prev then
      local dt = now - prev.time
      if dt > 0.5 then   -- esperar al menos 0.5s para evitar ruido
        local delta = prev.amount - amount   -- positivo = consumiendo
        rate = delta / dt

        if rate < 0 then
          charging = true
          timeLeft = nil
        elseif rate < 0.001 then
          rate = 0
          timeLeft = nil   -- motor apagado
        else
          timeLeft = amount / rate
        end

        _history[tankName] = { amount = amount, time = now }
      end
    else
      -- Primera lectura, solo guardamos
      _history[tankName] = { amount = amount, time = now }
    end
  end

  -- Nivel de alerta
  local alert = "ok"
  if amount == 0 then
    alert = "empty"
  elseif pct < 0.05 then
    alert = "critical"
  elseif pct < 0.20 then
    alert = "low"
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
--  Render de un tank en pantalla
--  Dibuja en 4 lineas a partir de (x, y) con ancho 'w'
-- ============================================================
function renderTank(t, x, y, w, data)
  local useColor = t.color
  local term = t.term

  -- Linea 1: titulo + tipo
  local typeTag = (data.tankType == "fuel") and "[COMB]" or
                  (data.tankType == "cargo") and "[CARGA]" or "[?]"
  local title = renderer.truncate(data.fluid, w - #typeTag - 1)
  renderer.write(t, x, y,
    title .. string.rep(" ", w - #title - #typeTag) .. typeTag,
    useColor and colors.white or nil,
    useColor and colors.black or nil)

  -- Linea 2: barra de progreso + porcentaje
  local pctStr = string.format("%3d%%", math.floor(data.pct * 100))
  local barW   = w - #pctStr - 1
  local bar    = renderer.progressBar(data.pct, barW, nil, nil, false)
  local barColor = useColor and renderer.alertColor(data.pct, true) or nil
  renderer.write(t, x, y+1, bar .. " " .. pctStr, barColor)

  -- Linea 3: cantidad
  local amtStr = renderer.formatNum(data.amount) .. "/" ..
                 renderer.formatNum(data.capacity) .. " mB"
  renderer.write(t, x, y+2, renderer.truncate(amtStr, w),
    useColor and colors.lightGray or nil)

  -- Linea 4: tasa / tiempo restante / estado
  local statusStr = ""
  if data.tankType == "fuel" then
    if data.alert == "empty" then
      statusStr = "!!! SIN COMBUSTIBLE !!!"
    elseif data.charging then
      statusStr = "Cargando..."
    elseif data.rate == nil then
      statusStr = "Esperando datos..."
    elseif data.rate == 0 then
      statusStr = "Motor apagado"
    else
      local rateStr = string.format("%.1f mB/s", data.rate)
      local timeStr = data.timeLeft and renderer.formatTime(data.timeLeft) or "--:--"
      statusStr = rateStr .. "  |  " .. timeStr .. " rest."
    end
    local alertFg = useColor and (
      data.alert == "empty"    and colors.red    or
      data.alert == "critical" and colors.red    or
      data.alert == "low"      and colors.orange or
      colors.lightGray) or nil
    renderer.write(t, x, y+3, renderer.truncate(statusStr, w), alertFg)
  else
    -- Cargo: solo estado simple
    renderer.write(t, x, y+3,
      renderer.truncate("Nivel: " .. string.format("%.1f%%", data.pct*100), w),
      useColor and colors.lightGray or nil)
  end
end

-- ============================================================
--  Render de todos los tanks detectados
--  Dibuja en el area (x, y, w, h) del renderTarget
-- ============================================================
function renderAll(renderTarget, x, y, w, h)
  local tanks = detector.getByType("tank")
  if not next(tanks) then
    renderer.write(renderTarget, x, y,
      renderer.truncate("Sin tanks detectados", w),
      renderTarget.color and colors.lightGray or nil)
    return
  end

  local rowH = 5   -- 4 lineas de datos + 1 separador
  local row  = 0
  for tankName, entry in pairs(tanks) do
    if (row * rowH) + 4 > h then break end   -- no cabe mas

    -- Clasificar si es desconocido (primer arranque con este tank)
    if _types[tankName] == nil then
      classifyTank(tankName, renderTarget)
    end

    local data = readTank(tankName, entry.periph)
    renderTank(renderTarget, x, y + (row * rowH), w, data)

    -- Separador entre tanks
    if row > 0 then
      renderer.write(renderTarget, x, y + (row * rowH) - 1,
        string.rep("-", w), renderTarget.color and colors.gray or nil)
    end

    row = row + 1
  end
end

-- Suma total de combustible (mB) de todos los tanks tipo fuel
function getTotalFuel()
  local total, cap = 0, 0
  local tanks = detector.getByType("tank")
  for tankName, entry in pairs(tanks) do
    if (_types[tankName] or "unknown") == "fuel" then
      local ok, t = pcall(function() return entry.periph.tanks() end)
      if ok and t and t[1] then
        total = total + (t[1].amount   or 0)
        cap   = cap   + (t[1].capacity or 0)
      end
    end
  end
  return total, cap
end
