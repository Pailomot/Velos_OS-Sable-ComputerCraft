-- ============================================================
--  VelosOS  |  startup.lua  |  Entry point
-- ============================================================

-- Cargar modulos del core
_G.renderer  = require("core.renderer")
_G.detector  = require("core.detector")
_G.config    = require("core.config")

-- Cargar modulos opcionales
_G.hud         = require("modules.hud")
_G.tanks       = require("modules.tanks")
_G.cannon      = require("modules.cannon")
_G.cannon_ui   = require("modules.cannon_ui")
_G.speaker     = require("modules.speaker")
_G.environment = require("modules.environment")
_G.energy      = require("modules.energy")
_G.chatbox     = require("modules.chatbox")

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

-- 3. Cargar configuracion guardada
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
