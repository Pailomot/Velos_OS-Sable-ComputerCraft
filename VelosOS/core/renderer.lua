-- ============================================================
--  VelosOS  |  core/renderer.lua
-- ============================================================

local renderer = {}

local _extras = {}

function renderer.init()
  local target = nil

  local mon = peripheral.find("monitor")
  if mon then
    mon.setTextScale(0.5)
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

  if not target then
    local w, h = term.getSize()
    target = {
      term  = term,
      w     = w,
      h     = h,
      color = term.isColour(),
      name  = "Computer (" .. w .. "x" .. h .. ")",
      type  = "computer",
      extras = _extras,
    }
  end

  renderer._scanDisplayLinks()
  return target
end

function renderer._scanDisplayLinks()
  _extras = {}
  local sources = { peripheral.find("create_source") }
  for i, src in ipairs(sources) do
    local w, h = src.getSize()
    table.insert(_extras, {
      term  = src,
      w     = w,
      h     = h,
      color = false,
      name  = "Display Link #" .. i,
      type  = "display_link",
      mode  = "mirror",
    })
  end
  return _extras
end

function renderer.refreshExtras()
  renderer._scanDisplayLinks()
end

function renderer.getExtras()
  return _extras
end

function renderer.write(t, x, y, text, fg, bg)
  if fg then t.term.setTextColor(fg) end
  if bg then t.term.setBackgroundColor(bg) end
  t.term.setCursorPos(x, y)
  t.term.write(text)
  t.term.setBackgroundColor(colors.black)
end

-- Escribe texto rellenando con espacios hasta el ancho w
-- para sobreescribir contenido anterior sin hacer clear()
function renderer.writeLine(t, x, y, text, w, fg, bg)
  local available = w - x + 1
  if #text > available then
    text = text:sub(1, available - 1) .. ">"
  else
    text = text .. string.rep(" ", available - #text)
  end
  if fg then t.term.setTextColor(fg) end
  if bg then t.term.setBackgroundColor(bg) end
  t.term.setCursorPos(x, y)
  t.term.write(text)
  t.term.setBackgroundColor(colors.black)
end

-- Limpia un rango de lineas sobreescribiendo con espacios
function renderer.clearLines(t, fromY, toY)
  for y = fromY, toY do
    renderer.writeLine(t, 1, y, "", t.w)
  end
end

function renderer.hline(t, y, char, fg, bg)
  char = char or "-"
  renderer.write(t, 1, y, string.rep(char, t.w), fg, bg)
end

function renderer.progressBar(fill, width)
  width = width or 10
  local inner = width - 2
  local filled = math.max(0, math.min(inner, math.floor(fill * inner + 0.5)))
  local empty = inner - filled
  return "[" .. string.rep("#", filled) .. string.rep(".", empty) .. "]"
end

function renderer.center(text, width)
  local pad = math.max(0, math.floor((width - #text) / 2))
  return string.rep(" ", pad) .. text
end

function renderer.truncate(text, maxLen)
  if #text <= maxLen then return text end
  return string.sub(text, 1, maxLen - 1) .. ">"
end

function renderer.alertColor(pct, useColor)
  if not useColor then return colors.white end
  if pct > 0.5  then return colors.lime   end
  if pct > 0.2  then return colors.yellow end
  if pct > 0.05 then return colors.orange end
  return colors.red
end

function renderer.formatTime(seconds)
  if not seconds or seconds < 0 then return "--:--" end
  seconds = math.floor(seconds)
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if h > 0 then
    return string.format("%dh %02dm", h, m)
  end
  return string.format("%02d:%02d", m, s)
end

function renderer.formatNum(n, decimals)
  decimals = decimals or 0
  if decimals > 0 then
    return string.format("%." .. decimals .. "f", n)
  end
  return tostring(math.floor(n))
end

return renderer
