-- ============================================================
--  VelosOS  |  core/renderer.lua
-- ============================================================

local renderer = {}

function renderer.init()
  -- Buscar monitor conectado
  for _, name in ipairs(peripheral.getNames()) do
    local types = peripheral.getType(name)
    if type(types) == "string" then types = { types } end
    for _, t in ipairs(types) do
      if t == "monitor" then
        local mon = peripheral.wrap(name)
        if mon then
          mon.setTextScale(0.5)
          local w, h = mon.getSize()
          return {
            name  = "Monitor [" .. name .. "]",
            term  = mon,
            w     = w,
            h     = h,
            color = mon.isColor(),
          }
        end
      end
    end
  end

  -- Fallback: pantalla del computer
  local w, h = term.getSize()
  return {
    name  = "Computer",
    term  = term,
    w     = w,
    h     = h,
    color = term.isColor(),
  }
end

function renderer.refreshExtras()
  -- Hook para detector.onAttach / onDetach
end

return renderer
