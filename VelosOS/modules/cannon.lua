-- ============================================================
--  VelosOS  |  modules/cannon.lua
--  Control de artilleria:
--    - CBC (cbc_cannon_mount) para apuntar y disparar
--    - Create Radar controllers como alternativa/complemento
--    - Radar bearing/monitor para seleccion de objetivos
--    - Fallback graceful si falta cualquier componente
-- ============================================================

local cannon = {}

-- ============================================================
--  Estado interno
-- ============================================================
local _state = {
  -- Perifericos disponibles (nil si no estan)
  cbc        = nil,   -- cbc_cannon_mount
  crYaw      = nil,   -- create_radar:auto_yaw_controller
  crPitch    = nil,   -- create_radar:auto_pitch_controller
  crFire     = nil,   -- create_radar:fire_controller
  crMonitor  = nil,   -- create_radar:monitor
  crBearing  = nil,   -- create_radar:radar_bearing
  crPlane    = nil,   -- create_radar:plane_radar
  playerDet  = nil,   -- playerDetector (Advanced Peripherals)

  -- Modo de apuntado: "manual" | "player" | "radar" | "coords"
  aimMode    = "manual",

  -- Objetivo actual
  target     = nil,   -- { x, y, z, label, type }

  -- Teclas asignadas (se cargan de config)
  keys       = {},

  -- Ultimo angulo enviado
  lastYaw    = 0,
  lastPitch  = 0,

  -- Paso de apuntado manual (grados por pulsacion)
  stepCoarse = 5.0,
  stepFine   = 0.5,
  fineMode   = false,
}

local KEYS_CFG = "cannon_keys"
local DEFAULT_KEYS = {
  yawLeft   = keys.a,
  yawRight  = keys.d,
  pitchUp   = keys.w,
  pitchDown = keys.s,
  fire      = keys.f,
  toggleFine = keys.g,
  cycleMode = keys.tab,
}

-- ============================================================
--  Init: detectar perifericos y cargar config
-- ============================================================
function cannon.init()
  -- CBC
  local cbcEntry = detector.getByType("cannon")
  for _, e in pairs(cbcEntry) do _state.cbc = e.periph; break end

  -- Create Radar controllers
  for t, field in pairs({
    cr_yaw     = "crYaw",
    cr_pitch   = "crPitch",
    cr_fire    = "crFire",
    cr_monitor = "crMonitor",
    cr_bearing = "crBearing",
    cr_plane   = "crPlane",
  }) do
    local entries = detector.getByType(t)
    for _, e in pairs(entries) do _state[field] = e.periph; break end
  end

  -- Player Detector
  local pdEntry = detector.getByType("radar")
  for _, e in pairs(pdEntry) do _state.playerDet = e.periph; break end

  -- Cargar teclas
  local saved = config.get(KEYS_CFG, nil)
  if saved then
    _state.keys = saved
  else
    _state.keys = DEFAULT_KEYS
  end

  -- Tomar control CBC si esta disponible
  if _state.cbc then
    pcall(function() _state.cbc.setComputerControl(true) end)
  end

  return cannon.hasAnyCannon()
end

-- ============================================================
--  Capacidades disponibles
-- ============================================================
function cannon.hasAnyCannon()
  return _state.cbc ~= nil or _state.crYaw ~= nil
end

function cannon.hasRadar()
  return _state.crBearing ~= nil or _state.crMonitor ~= nil
        or _state.crPlane ~= nil
end

function cannon.hasCBC()
  return _state.cbc ~= nil
end

function cannon.hasFireController()
  return _state.crFire ~= nil
end

-- Descripcion de lo que hay disponible
function cannon.getHardwareSummary()
  local parts = {}
  if _state.cbc       then table.insert(parts, "CBC") end
  if _state.crYaw     then table.insert(parts, "Yaw-Ctrl") end
  if _state.crPitch   then table.insert(parts, "Pitch-Ctrl") end
  if _state.crFire    then table.insert(parts, "Fire-Ctrl") end
  if _state.crMonitor then table.insert(parts, "Radar-Mon") end
  if _state.crBearing then table.insert(parts, "Radar-Brg") end
  if _state.crPlane   then table.insert(parts, "PlaneRadar") end
  if _state.playerDet then table.insert(parts, "PlayerDet") end
  if #parts == 0 then return "Sin hardware de artilleria" end
  return table.concat(parts, " | ")
end

-- ============================================================
--  Ensamblado (solo CBC)
-- ============================================================
function cannon.assemble()
  if not _state.cbc then return false, "Sin CBC" end
  if _state.cbc.isAssembled() then return true end
  local ok, err = _state.cbc.assemble()
  return ok, err
end

function cannon.disassemble()
  if not _state.cbc then return false, "Sin CBC" end
  return _state.cbc.disassemble()
end

function cannon.isAssembled()
  if _state.cbc then return _state.cbc.isAssembled() end
  -- Sin CBC asumimos que los controllers de radar son independientes
  return _state.crYaw ~= nil
end

function cannon.getState()
  if _state.cbc then
    local ok, s = pcall(function() return _state.cbc.getState() end)
    if ok then return s end
  end
  return "unknown"
end

-- ============================================================
--  Apuntado — backend unificado
--  Usa Create Radar controllers si estan, CBC como fallback
-- ============================================================
function cannon.setYaw(deg)
  _state.lastYaw = deg
  if _state.crYaw then
    pcall(function() _state.crYaw.setAngle(deg) end)
  elseif _state.cbc then
    pcall(function() _state.cbc.setTargetYaw(deg) end)
  end
end

function cannon.setPitch(deg)
  _state.lastPitch = deg
  if _state.crPitch then
    pcall(function() _state.crPitch.setAngle(deg) end)
  elseif _state.cbc then
    pcall(function() _state.cbc.setTargetPitch(deg) end)
  end
end

function cannon.getYaw()
  if _state.crYaw then
    local ok, v = pcall(function() return _state.crYaw.getAngle() end)
    if ok then return v end
  end
  if _state.cbc then
    local ok, v = pcall(function() return _state.cbc.getYaw() end)
    if ok then return v end
  end
  return _state.lastYaw
end

function cannon.getPitch()
  if _state.crPitch then
    local ok, v = pcall(function() return _state.crPitch.getAngle() end)
    if ok then return v end
  end
  if _state.cbc then
    local ok, v = pcall(function() return _state.cbc.getPitch() end)
    if ok then return v end
  end
  return _state.lastPitch
end

function cannon.isAiming()
  if _state.cbc then
    local ok, v = pcall(function() return _state.cbc.isAiming() end)
    if ok then return v end
  end
  return false
end

-- Apuntar a coordenadas absolutas del mundo
-- Compensa la rotacion actual del vehiculo convirtiendo
-- el vector mundo -> espacio local del sub-level
function cannon.aimAtCoords(tx, ty, tz)
  local pose = sublevel.getLogicalPose()
  local cx   = pose.position.x
  local cy   = pose.position.y
  local cz   = pose.position.z

  -- Vector hacia el objetivo en espacio mundo
  local dx = tx - cx
  local dy = ty - cy
  local dz = tz - cz

  -- Rotar el vector por el inverso del quaternion del vehiculo
  -- para pasarlo al espacio local (relativo al frente del vehiculo)
  local q  = pose.orientation
  -- Quaternion inverso = conjugado (qx,qy,qz negados, qw igual)
  -- porque los quaternions de rotacion pura son unitarios
  local qw =  q.w
  local qx = -q.x
  local qy = -q.y
  local qz = -q.z

  -- Rotacion de un vector por un quaternion: v' = q * v * q^-1
  -- Formula directa para rotar (dx,dy,dz) por (qw,qx,qy,qz):
  local tx2 = 2.0 * (qy*dz - qz*dy)
  local ty2 = 2.0 * (qz*dx - qx*dz)
  local tz2 = 2.0 * (qx*dy - qy*dx)

  local lx = dx + qw*tx2 + qy*tz2 - qz*ty2
  local ly = dy + qw*ty2 + qz*tx2 - qx*tz2
  local lz = dz + qw*tz2 + qx*ty2 - qy*tx2

  -- Ahora calcular yaw y pitch en espacio local
  local yaw   = math.deg(math.atan2(-lx, lz))
  local hdist = math.sqrt(lx*lx + lz*lz)
  local pitch = math.deg(math.atan2(ly, hdist))

  cannon.setYaw(yaw)
  cannon.setPitch(pitch)

  return yaw, pitch
end

-- ============================================================
--  Disparo — usa fire_controller si esta, CBC como fallback
-- ============================================================
function cannon.fire()
  -- Prioridad: Create Radar fire controller
  if _state.crFire then
    local ok, err = pcall(function()
      _state.crFire.setPowered(true)
      _state.crFire.fireOn()
    end)
    -- Apagar despues de un tick
    os.sleep(0.1)
    pcall(function()
      _state.crFire.fireOff()
      _state.crFire.setPowered(false)
    end)
    return ok, err
  end

  -- Fallback: CBC
  if _state.cbc then
    if not _state.cbc.isAssembled() then
      return false, "Canon no ensamblado"
    end
    if not _state.cbc.isLoaded() then
      return false, "Canon no cargado"
    end
    return _state.cbc.fire()
  end

  return false, "Sin hardware de disparo"
end

function cannon.isLoaded()
  if _state.cbc then
    local ok, v = pcall(function() return _state.cbc.isLoaded() end)
    if ok then return v end
  end
  return nil   -- desconocido sin CBC
end

-- ============================================================
--  Radar — obtener objetivos
-- ============================================================

-- Devuelve lista unificada de tracks de todos los radares
-- Deduplicada por ID para evitar que varios radares reporten
-- la misma entidad varias veces
function cannon.getTracks()
  local byId  = {}   -- { id -> track } para deduplicar
  local pose  = sublevel.getLogicalPose()
  local ox, oy, oz = pose.position.x, pose.position.y, pose.position.z

  local function addTracks(periph)
    local ok, raw = pcall(function() return periph.getTracks() end)
    if not ok or not raw then return end
    for _, t in pairs(raw) do
      local id = tostring(t.id or "")
      -- Si ya tenemos este ID, no duplicar
      if id ~= "" and byId[id] then goto continue end

      local px = t.position and t.position.x or 0
      local py = t.position and t.position.y or 0
      local pz = t.position and t.position.z or 0
      local dx = px - ox
      local dy = py - oy
      local dz = pz - oz
      local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

      local eType = t.entityType or "unknown"
      local isMissile = eType:find("radar_projectile") or
                        eType:find("cannon_ball") or
                        eType:find("cannonball") or
                        (t.category and t.category:find("projectile"))
      local label
      if isMissile then
        label = "!! MISIL !!"
      elseif eType:find("player") then
        label = "Jugador"
      elseif eType:find("sable") then
        label = "Vehiculo"
      else
        label = eType:match(":(.+)$") or eType
        label = label:gsub("_", " ")
        label = label:sub(1,1):upper() .. label:sub(2)
      end

      local track = {
        x         = px,
        y         = py,
        z         = pz,
        label     = label,
        rawType   = eType,
        isMissile = isMissile and true or false,
        dist      = dist,
        id        = t.id,
        velocity  = t.velocity,
        category  = t.category,
      }

      if id ~= "" then byId[id] = track
      else byId[tostring(#byId + 1)] = track end

      if isMissile then
        pcall(function() speaker.missilWarning()     end)
        pcall(function() chatbox.missilWarning(dist) end)
      end

      ::continue::
    end
  end

  -- Leer tracks de todos los radares disponibles
  -- (la deduplicacion por ID evita duplicados entre ellos)
  if _state.crBearing then addTracks(_state.crBearing) end
  if _state.crMonitor then addTracks(_state.crMonitor) end
  if _state.crPlane   then addTracks(_state.crPlane)   end

  -- Fallback: playerDetector si no hay ningun radar
  if not next(byId) and _state.playerDet then
    local ok, players = pcall(function()
      return _state.playerDet.getPlayersInRange(256)
    end)
    if ok and players then
      for _, name in ipairs(players) do
        local ok2, p = pcall(function()
          return _state.playerDet.getPlayer(name)
        end)
        if ok2 and p then
          local dx = p.x - ox
          local dy = p.y - oy
          local dz = p.z - oz
          byId[name] = {
            x=p.x, y=p.y, z=p.z,
            label   = "Jugador: " .. name,
            rawType = "player",
            dist    = math.sqrt(dx*dx + dy*dy + dz*dz),
            id      = name,
          }
        end
      end
    end
  end

  -- Convertir a lista y ordenar por distancia
  local tracks = {}
  for _, tr in pairs(byId) do table.insert(tracks, tr) end
  table.sort(tracks, function(a, b) return a.dist < b.dist end)
  return tracks
end

-- Lee el objetivo seleccionado en el monitor fisico de Create Radar
-- y lo sincroniza como objetivo del OS
function cannon.syncSelectedFromMonitor()
  if not _state.crMonitor then return nil end

  -- Intentar getSelectedTrack primero, luego getSelectedTrackId
  local ok1, selected = pcall(function()
    return _state.crMonitor.getSelectedTrack()
  end)

  if ok1 and selected and selected.position then
    local pose = sublevel.getLogicalPose()
    local ox, oy, oz = pose.position.x, pose.position.y, pose.position.z
    local px = selected.position.x
    local py = selected.position.y
    local pz = selected.position.z
    local dx, dy, dz = px-ox, py-oy, pz-oz

    local eType = selected.entityType or "unknown"
    local label
    if eType:find("player") then label = "Jugador"
    elseif eType:find("sable") then label = "Vehiculo"
    else
      label = eType:match(":(.+)$") or eType
      label = label:gsub("_"," ")
      label = label:sub(1,1):upper()..label:sub(2)
    end

    local track = {
      x       = px, y=py, z=pz,
      label   = label,
      rawType = eType,
      dist    = math.sqrt(dx*dx+dy*dy+dz*dz),
      id      = selected.id,
      velocity = selected.velocity,
    }
    _state.target = track
    -- Activar modo radar automaticamente
    _state.aimMode = "radar"
    return track
  end

  return nil
end

-- ============================================================
--  Modos de apuntado
-- ============================================================
function cannon.getAimMode() return _state.aimMode end

function cannon.cycleAimMode()
  local modes = {"manual", "coords"}
  if cannon.hasRadar() or _state.playerDet then
    table.insert(modes, "radar")
  end
  for i, m in ipairs(modes) do
    if m == _state.aimMode then
      _state.aimMode = modes[(i % #modes) + 1]
      return _state.aimMode
    end
  end
  _state.aimMode = "manual"
  return _state.aimMode
end

function cannon.setTarget(track)
  _state.target = track
end

function cannon.getTarget() return _state.target end

-- Actualiza apuntado automatico si hay objetivo y modo lo requiere
function cannon.updateAutoAim()
  if _state.aimMode == "manual" then return end
  if not _state.target then return end
  cannon.aimAtCoords(_state.target.x, _state.target.y, _state.target.z)
end

-- ============================================================
--  Paso manual con teclas asignadas
-- ============================================================
function cannon.getStep()
  if _state.fineMode then return _state.stepFine end
  return _state.stepCoarse
end

function cannon.handleKey(keyCode)
  local k = _state.keys
  local step = cannon.getStep()
  local handled = false

  if keyCode == k.yawLeft then
    cannon.setYaw(cannon.getYaw() - step); handled = true
  elseif keyCode == k.yawRight then
    cannon.setYaw(cannon.getYaw() + step); handled = true
  elseif keyCode == k.pitchUp then
    cannon.setPitch(math.min(90, cannon.getPitch() + step)); handled = true
  elseif keyCode == k.pitchDown then
    cannon.setPitch(math.max(-90, cannon.getPitch() - step)); handled = true
  elseif keyCode == k.fire then
    cannon.fire(); handled = true
  elseif keyCode == k.toggleFine then
    _state.fineMode = not _state.fineMode; handled = true
  elseif keyCode == k.cycleMode then
    cannon.cycleAimMode(); handled = true
  end

  return handled
end

-- ============================================================
--  Setup interactivo de teclas
-- ============================================================
function cannon.setupKeys(renderTarget)
  local t    = renderTarget.term
  local useC = renderTarget.color
  local w    = renderTarget.w

  t.setBackgroundColor(colors.black)
  t.clear()
  t.setCursorPos(1,1)

  local function line(text, fg)
    if useC and fg then t.setTextColor(fg) end
    print(text:sub(1, w))
  end

  local function waitKey(prompt)
    line(prompt, colors.white)
    while true do
      local ev, code = os.pullEvent()
      if ev == "key" then return code end
    end
  end

  line("============================", colors.yellow)
  line("  CONFIG. TECLAS DEL CANON  ", colors.yellow)
  line("============================", colors.yellow)
  line("")
  line("Presiona la tecla para cada", colors.lightGray)
  line("funcion cuando se indique.", colors.lightGray)
  line("")

  local assignments = {}
  local prompts = {
    { id = "yawLeft",    label = "  Yaw izquierda : " },
    { id = "yawRight",   label = "  Yaw derecha   : " },
    { id = "pitchUp",    label = "  Pitch arriba  : " },
    { id = "pitchDown",  label = "  Pitch abajo   : " },
    { id = "fire",       label = "  DISPARAR      : " },
    { id = "toggleFine", label = "  Paso fino/bruto: " },
    { id = "cycleMode",  label = "  Cambiar modo  : " },
  }

  for _, p in ipairs(prompts) do
    local code = waitKey(p.label)
    assignments[p.id] = code
    -- Mostrar nombre de la tecla asignada
    local y = ({t.getCursorPos()})[2] - 1
    t.setCursorPos(#p.label + 1, y)
    if useC then t.setTextColor(colors.lime) end
    t.write("[" .. keys.getName(code) .. "]  ")
    t.setCursorPos(1, y + 1)
  end

  _state.keys = assignments
  config.set(KEYS_CFG, assignments)

  line("", colors.white)
  line("Teclas guardadas!", colors.lime)
  sleep(1.5)
end

-- ============================================================
--  Getters de estado para la UI
-- ============================================================
function cannon.getKeys()     return _state.keys end
function cannon.isFineMode()  return _state.fineMode end
function cannon.getLastYaw()  return _state.lastYaw end
function cannon.getLastPitch() return _state.lastPitch end

return cannon
