-- ============================================================
--  VelosOS  |  startup.lua  |  Entry point
--  Coloca este archivo como /startup.lua en la Advanced Computer
-- ============================================================

os.loadAPI("core/renderer.lua")
os.loadAPI("core/detector.lua")
os.loadAPI("core/config.lua")
os.loadAPI("modules/hud.lua")
os.loadAPI("modules/tanks.lua")

-- Splash screen rapido
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
term.setTextColor(colors.yellow)
print(" =============================")
print("       V E L O S  O S        ")
print("       Vehicle Computer       ")
print(" =============================")
term.setTextColor(colors.lightGray)
print("")
print(" Iniciando sistemas...")
sleep(1)

-- 1. Verificar que estamos en un Sub-Level
print(" Verificando Sub-Level...")
if not sublevel.isInPlotGrid() then
  term.setTextColor(colors.red)
  print("")
  print(" [ERROR] Esta computadora no esta")
  print(" dentro de un Sub-Level de Sable.")
  print("")
  print(" Reintentando en 5s...")
  term.setTextColor(colors.lightGray)
  sleep(5)
  os.reboot()
end
term.setTextColor(colors.lime)
print(" Sub-Level OK: " .. sublevel.getName())
term.setTextColor(colors.lightGray)

-- 2. Detectar pantallas disponibles
print(" Detectando pantallas...")
local renderTarget = renderer.init()
if not renderTarget then
  term.setTextColor(colors.red)
  print(" [ERROR] No se encontro pantalla.")
  print(" Necesitas un Advanced Computer")
  print(" o un Monitor conectado.")
  return
end
term.setTextColor(colors.lime)
print(" Pantalla: " .. renderTarget.name)
term.setTextColor(colors.lightGray)

-- 3. Cargar configuracion guardada (perfil de vehiculo, tanks, etc)
print(" Cargando configuracion...")
config.load()
term.setTextColor(colors.lime)
print(" Perfil: " .. config.get("vehicle_profile", "Sin configurar"))
term.setTextColor(colors.lightGray)

-- 4. Escanear perifericos opcionales
print(" Escaneando perifericos...")
detector.scan()
sleep(0.5)

-- 5. Si no hay perfil, primer arranque
if not config.get("vehicle_profile") then
  print("")
  term.setTextColor(colors.yellow)
  print(" Primer arranque detectado.")
  term.setTextColor(colors.lightGray)
  sleep(0.5)
  config.firstTimeSetup(renderTarget)
end

sleep(0.5)

-- 6. Loop principal del OS
term.setTextColor(colors.lime)
print("")
print(" Sistemas listos. Iniciando HUD...")
sleep(0.8)

hud.run(renderTarget)
