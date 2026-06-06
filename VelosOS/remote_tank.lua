-- ============================================================
--  VelosOS  |  remote_tank.lua
--  Script STANDALONE para una computadora remota junto a un tank.
--  Lee el tank local y transmite los datos por rednet
--  al vehiculo principal cada N segundos.
--
--  INSTALACION:
--    1. Pon una Advanced Computer + Modem + Fluid Tank juntos
--    2. Copia este archivo como /startup.lua en esa computadora
--    3. El vehiculo con VelosOS los recibira automaticamente
-- ============================================================

local PROTOCOL    = "velosOS"
local SEND_EVERY  = 2.0   -- segundos entre transmisiones
local LABEL       = os.getComputerLabel() or ("Tank-" .. os.getComputerID())

-- ============================================================
--  Buscar modem y abrirlo
-- ============================================================
local modemSide = nil
for _, side in ipairs({"top","bottom","left","right","front","back"}) do
  if peripheral.getType(side) == "modem" then
    modemSide = side
    break
  end
end

if not modemSide then
  print("[ERROR] No se encontro modem.")
  print("Conecta un modem a esta computadora.")
  return
end

rednet.open(modemSide)
print("[OK] Modem abierto en: " .. modemSide)

-- ============================================================
--  Buscar tanks conectados
-- ============================================================
local FLUID_TYPES = {
  "fluid_storage","fluidStorage","create:fluid_tank",
  "forge:fluid_handler",
}

local function findTanks()
  local found = {}
  for _, name in ipairs(peripheral.getNames()) do
    local ptypes = peripheral.getType(name)
    if type(ptypes) == "string" then ptypes = {ptypes} end
    for _, pt in ipairs(ptypes or {}) do
      for _, ft in ipairs(FLUID_TYPES) do
        if pt == ft then
          table.insert(found, { name=name, periph=peripheral.wrap(name) })
          break
        end
      end
    end
  end
  return found
end

-- ============================================================
--  Leer datos de un tank
-- ============================================================
local function readTank(name, periph)
  local ok, slots = pcall(function() return periph.tanks() end)
  if not ok or not slots or #slots == 0 then
    return { name=name, fluid="Error", amount=0, capacity=1, pct=0 }
  end

  local amount, capacity, fluid = 0, 0, "Vacio"
  for _, s in ipairs(slots) do
    amount   = amount   + (s.amount   or 0)
    capacity = capacity + (s.capacity or 0)
    if s.amount and s.amount > 0 and s.name then
      fluid = s.name:match(":(.+)$") or s.name
      fluid = fluid:gsub("_"," ")
      fluid = fluid:sub(1,1):upper() .. fluid:sub(2)
    end
  end

  -- Intentar tankCapacity()
  local ok2, cap2 = pcall(function() return periph.tankCapacity() end)
  if ok2 and type(cap2)=="number" and cap2 > capacity then
    capacity = cap2
  end

  if capacity <= 0 then capacity = 1 end
  return {
    name     = name,
    fluid    = fluid,
    amount   = amount,
    capacity = capacity,
    pct      = math.min(1.0, amount / capacity),
  }
end

-- ============================================================
--  Loop principal
-- ============================================================
term.setBackgroundColor(colors.black)
term.setTextColor(colors.yellow)
term.clear()
term.setCursorPos(1,1)
print("============================")
print("  VelosOS  |  Tank Remoto  ")
print("============================")
term.setTextColor(colors.white)
print("")
print(" Label: " .. LABEL)
print(" Protocolo: " .. PROTOCOL)
print("")

local tanks = findTanks()
if #tanks == 0 then
  term.setTextColor(colors.red)
  print(" [!] No se encontraron tanks.")
  print(" Conecta un Fluid Tank a esta")
  print(" computadora y reinicia.")
  return
end

term.setTextColor(colors.lime)
print(" Tanks encontrados: " .. #tanks)
for _, t in ipairs(tanks) do
  print("   " .. t.name)
end
term.setTextColor(colors.lightGray)
print("")
print(" Transmitiendo cada " .. SEND_EVERY .. "s...")
print(" (Ctrl+T para detener)")
print("")

local timer = os.startTimer(SEND_EVERY)

while true do
  local ev, p1, p2, p3 = os.pullEvent()

  if ev == "timer" and p1 == timer then
    -- Leer todos los tanks
    local data = {}
    for _, t in ipairs(tanks) do
      table.insert(data, readTank(t.name, t.periph))
    end

    -- Transmitir
    local payload = textutils.serialise({
      type   = "tank_data",
      data   = data,
      sender = LABEL,
    })
    rednet.broadcast(payload, PROTOCOL)

    -- Actualizar pantalla
    term.setCursorPos(1, 12)
    term.setTextColor(colors.lime)
    term.write(" TX: " .. textutils.formatTime(os.time(), true) .. "  ")
    term.setTextColor(colors.lightGray)

    timer = os.startTimer(SEND_EVERY)

  elseif ev == "rednet_message" then
    -- Responder pings del vehiculo
    local ok, msg = pcall(function() return textutils.unserialise(p2) end)
    if ok and type(msg)=="table" and msg.type == "ping" then
      local pong = textutils.serialise({
        type   = "pong",
        data   = { name = LABEL .. " (tank)" },
        sender = LABEL,
      })
      rednet.send(p1, pong, PROTOCOL)
    end
  end
end
