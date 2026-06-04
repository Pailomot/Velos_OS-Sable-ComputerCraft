-- ============================================================
--  VelosOS  |  core/renderer.lua
--  Detecta la mejor pantalla disponible y devuelve un
--  "renderTarget" unificado que el resto del OS usa.
--
--  renderTarget = {
--    term    : objeto terminal (para escribir)
--    w, h    : ancho y alto en caracteres
--    color   : boolean (soporta color?)
--    name    : string descriptivo
--    type    : "computer" | "monitor" | "display_link"
--    extras  : tabla con pantallas secundarias activas
--  }
-- ============================================================

-- Pantallas secundarias activas (Display Links conectados)
local _extras = {}

-- ============================================================
--  Deteccion y construccion del renderTarget principal
-- ============================================================
function init()
  local target = nil

  -- Prioridad 1: Monitor externo (pantalla mas grande)
  local mon = peripheral.find("monitor")
  if mon then
    mon.setTextScale(0.5)   -- mas caracteres en pantalla
    mon.setBackgroundColor(colors.black)
    mon.clear()
    local w, h = mon.getSize()
    target = {
      term  = mon,
      w     = w,
      h     = h,
      color = mon.isColour and mon.isColour() or false,
      name  = "Monitor externo (" .. w .. "x" .. h .. ")",
      type  = "monitor",
      extras = _extras,
    }
  end

  -- Prioridad 2: Advanced Computer (si no hay monitor, o como fallback)
  if not target then
    local w, h = term.getSize()
    local isColor = term.isColour()
    if isColor then
      target = {
        term  = term,
        w     = w,
        h     = h,
        color = true,
        name  = "Advanced Computer (" .. w .. "x" .. h .. ")",
        type  = "computer",
        extras = _extras,
      }
    else
      -- Computadora normal sin color: funcional pero limitada
      target = {
        term  = term,
        w     = w,
        h     = h,
        color = false,
        name  = "Computer (sin color, " .. w .. "x" .. h .. ")",
        type  = "computer",
        extras = _extras,
      }
    end
  end

  -- Buscar Display Links como pantallas secundarias
  _scanDisplayLinks()

  return target
end

-- ============================================================
--  Escanear Display Links (create_source)
-- ============================================================
function _scanDisplayLinks()
  _extras = {}
  local sources = { peripheral.find("create_source") }
  for i, src in ipairs(sources) do
    local w, h = src.getSize()
    table.insert(_extras, {
      term  = src,
      w     = w,
      h     = h,
      color = false,   -- create_source no soporta color
      name  = "Display Link #" .. i,
      type  = "display_link",
      mode  = "mirror",   -- "mirror" | "fuel" | "nav" | "free"
    })
  end
  return _extras
end

-- Llamado por detector cuando se conecta/desconecta un periferico
function refreshExtras()
  _scanDisplayLinks()
end

function getExtras()
  return _extras
end

-- ============================================================
--  Utilidades de dibujo compartidas
-- ============================================================

-- Escribe texto en una posicion con colores opcionales
function write(t, x, y, text, fg, bg)
  if fg then t.term.setTextColor(fg) end
  if bg then t.term.setBackgroundColor(bg) end
  t.term.setCursorPos(x, y)
  t.term.write(text)
end

-- Dibuja una linea horizontal de relleno
function hline(t, y, char, fg, bg)
  char = char or "-"
  write(t, 1, y, string.rep(char, t.w), fg, bg)
end

-- Barra de progreso ASCII
--   fill: 0.0 a 1.0
--   width: largo total de la barra (incluyendo brackets)
function progressBar(fill, width, colorFull, colorEmpty, useColor)
  width = width or 10
  local inner = width - 2   -- espacio dentro de los brackets
  local filled = math.floor(fill * inner + 0.5)
  filled = math.max(0, math.min(inner, filled))
  local empty = inner - filled

  if useColor then
    -- Retorna tabla {text, fg, bg} para blit manual
    local bar = "[" .. string.rep("\127", filled) .. string.rep(" ", empty) .. "]"
    return bar
  else
    return "[" .. string.rep("#", filled) .. string.rep(".", empty) .. "]"
  end
end

-- Centra un texto en un ancho dado
function center(text, width)
  local pad = math.max(0, math.floor((width - #text) / 2))
  return string.rep(" ", pad) .. text
end

-- Trunca texto si es mas largo que maxLen
function truncate(text, maxLen)
  if #text <= maxLen then return text end
  return string.sub(text, 1, maxLen - 1) .. ">"
end

-- Color de alerta segun porcentaje (1.0 = lleno, 0.0 = vacio)
function alertColor(pct, useColor)
  if not useColor then return colors.white end
  if pct > 0.5 then return colors.lime end
  if pct > 0.2 then return colors.yellow end
  if pct > 0.05 then return colors.orange end
  return colors.red
end

-- Formatea segundos a mm:ss o hh:mm:ss
function formatTime(seconds)
  if seconds < 0 or seconds ~= seconds then return "--:--" end  -- NaN guard
  seconds = math.floor(seconds)
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if h > 0 then
    return string.format("%dh %02dm", h, m)
  else
    return string.format("%02d:%02d", m, s)
  end
end

-- Formatea un numero con separador de miles
function formatNum(n, decimals)
  decimals = decimals or 0
  if decimals > 0 then
    return string.format("%." .. decimals .. "f", n)
  end
  return tostring(math.floor(n))
end
