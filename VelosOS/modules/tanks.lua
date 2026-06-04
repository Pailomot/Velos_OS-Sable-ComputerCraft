-- ============================================================
--  VelosOS  |  modules/tanks.lua
-- ============================================================

local tanks = {}

local TANKS_CFG_KEY = "tank_types"
local _history = {}
local _types   = {}

function tanks.init()
  _types = config.get(TANKS_CFG_KEY, {})
end

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
  print(" Clasificado como: " .. (tankType == "fuel" and "Combustible" or "Carga"))
  sleep(1)

  return tankType
end

function tanks.readTank(tankName, periph)
  local tankType = _types[tankName] or "unknown"

  local ok, fluidTanks = pcall(function() return periph.tanks() end)
  if not ok or not fluidTanks or #fluidTanks == 0 then
    return {
      name = tankName, tankType = tankType,
      fluid = "Error", amount = 0, capacity = 1, pct = 0,
      alert = "empty",
    }
  end

  local slot = fluidTanks[1]
  for _, s in ipairs(fluidTanks) do
    if s.amount and s.amount > 0 then slot = s; break end
  end

  local amount   = slot.amount   or 0
  local capacity = slot.capacity or 1
  local fluid    = slot.name     or "Vacio"
  fluid = fluid:match(":(.+)$") or fluid
  fluid = fluid:sub(1,1):upper() .. fluid:sub(2)

  local pct = amount / capacity
  local rate, timeLeft, charging = nil, nil, false

  if tankType == "fuel" then
    local now  = os.epoch("utc") / 1000
    local prev = _history[tankName]
    if prev then
      local dt = now - prev.time
      if dt > 0.5 then
        local delta = prev.amount - amount
        rate = delta / dt
        if rate < 0 then
          charging = true
        elseif rate < 0.001 then
          rate = 0
        else
          timeLeft = amount / rate
        end
        _history[tankName] = { amount = amount, time = now }
      end
    else
      _history[tankName] = { amount = amount, time = now }
    end
  end

  local alert = "ok"
  if amount == 0       then alert = "empty"
  elseif pct < 0.05   then alert = "critical"
  elseif pct < 0.20   then alert = "low"
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

function tanks.renderTank(t, x, y, w, data)
  local useColor = t.color

  local typeTag = (data.tankType == "fuel") and "[COMB]" or
                  (data.tankType == "cargo") and "[CARGA]" or "[?]"
  local title = renderer.truncate(data.fluid, w - #typeTag - 1)
  renderer.write(t, x, y,
    title .. string.rep(" ", w - #title - #typeTag) .. typeTag,
    useColor and colors.white or nil)

  local pctStr = string.format("%3d%%", math.floor(data.pct * 100))
  local barW   = w - #pctStr - 1
  local bar    = renderer.progressBar(data.pct, barW)
  renderer.write(t, x, y+1, bar .. " " .. pctStr,
    useColor and renderer.alertColor(data.pct, true) or nil)

  local amtStr = renderer.formatNum(data.amount) .. "/" ..
                 renderer.formatNum(data.capacity) .. " mB"
  renderer.write(t, x, y+2, renderer.truncate(amtStr, w),
    useColor and colors.lightGray or nil)

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
      statusStr = string.format("%.1f mB/s", data.rate) ..
                  "  |  " .. renderer.formatTime(data.timeLeft) .. " rest."
    end
    local alertFg = useColor and (
      (data.alert == "empty" or data.alert == "critical") and colors.red or
      data.alert == "low" and colors.orange or
      colors.lightGray) or nil
    renderer.write(t, x, y+3, renderer.truncate(statusStr, w), alertFg)
  else
    renderer.write(t, x, y+3,
      renderer.truncate("Nivel: " .. string.format("%.1f%%", data.pct*100), w),
      useColor and colors.lightGray or nil)
  end
end

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
    local data = tanks.readTank(tankName, entry.periph)
    tanks.renderTank(renderTarget, x, y + (row * rowH), w, data)
    if row > 0 then
      renderer.write(renderTarget, x, y + (row * rowH) - 1,
        string.rep("-", w), renderTarget.color and colors.gray or nil)
    end
    row = row + 1
  end
end

function tanks.getTotalFuel()
  local total, cap = 0, 0
  for tankName, entry in pairs(detector.getByType("tank")) do
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

return tanks
