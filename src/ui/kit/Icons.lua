-- Lucide ISC/Feather MIT icons, rasterized offline into one shared texture.
local Icons = {}
local names = {
  "settings",
  "x",
  "arrow-left-right",
  "puzzle",
  "search",
  "globe",
  "paintbrush",
  "download",
  "pencil",
  "folder",
  "upload",
  "file-pen-line",
  "trash",
  "check",
  "chevron-right",
  "lock",
  "lock-open",
  "mail",
}
local editorNames = {
  "chevron-left",
  "chevron-up",
  "chevron-down",
  "plus",
  "minus",
  "undo-2",
  "redo-2",
  "save",
  "rotate-ccw",
  "ellipsis",
  "copy",
  "heart",
  "package",
  "backpack",
  "list-filter",
  "arrow-up",
  "arrow-down",
  "arrow-left",
  "arrow-right",
  "arrow-up-down",
  "eye",
  "award",
  "book-open",
  "shield-check",
  "map-pin",
  "grid-2x2",
  "sliders-horizontal",
  "expand",
  "chevrons-up",
  "users",
  "user-round",
  "wallet",
  "flag",
  "sparkles",
  "shuffle",
  "folder-open",
}
local atlases = {
  { path = "assets/launcher/lucide/icons.png", names = names },
  { path = "assets/launcher/lucide/editor.png", names = editorNames },
}
local cells = {}
Icons.NAMES = {}
Icons.ATLASES = atlases
for _, atlas in ipairs(atlases) do
  for i, name in ipairs(atlas.names) do
    Icons.NAMES[#Icons.NAMES + 1] = name
    cells[name] = { atlas = atlas, index = i }
  end
end

Icons.NAMES[#Icons.NAMES + 1] = "triangle-alert"
local vectors = {}
for _, name in ipairs({ "circle-help", "music", "play", "square", "monitor", "gamepad-2", "chart-no-axes-column" }) do
  Icons.NAMES[#Icons.NAMES + 1] = name; vectors[name] = true
end
local MUSIC_NOTES = { { .3, .79 }, { .7, .68 } }
local CHART_BARS = { { .2, .45 }, { .45, .2 }, { .7, .32 } }
function Icons.has(name)
  return name == "triangle-alert" or vectors[name] == true or cells[name] ~= nil
end

function Icons.draw(name, x, y, size, color, alpha)
  local g = love and love.graphics
  if g and name == "circle-help" then
    g.push("all")
    g.setColor(color[1] / 255, color[2] / 255, color[3] / 255, alpha or 1)
    g.setLineWidth(math.max(1, size * 0.075))
    g.circle("line", x + size * .5, y + size * .5, size * .42)
    g.line(x + size * .35, y + size * .36, x + size * .39, y + size * .29,
      x + size * .53, y + size * .27, x + size * .64, y + size * .34,
      x + size * .63, y + size * .43, x + size * .5, y + size * .51, x + size * .5, y + size * .57)
    g.circle("fill", x + size * .5, y + size * .71, size * .04)
    g.pop()
    return
  end
  if g and vectors[name] then
    g.push("all")
    g.setColor(color[1] / 255, color[2] / 255, color[3] / 255, alpha or 1)
    g.setLineWidth(math.max(1, size * .075))
    if g.setLineJoin then g.setLineJoin("bevel") end
    if name == "music" then
      g.line(x + size * .42, y + size * .76, x + size * .42, y + size * .25,
        x + size * .82, y + size * .15, x + size * .82, y + size * .65)
      for i = 1, #MUSIC_NOTES do
        local note = MUSIC_NOTES[i]
        if g.ellipse then g.ellipse("fill", x + size * note[1], y + size * note[2], size * .12, size * .075)
        else g.circle("fill", x + size * note[1], y + size * note[2], size * .09) end
      end
    elseif name == "play" then
      g.polygon("fill", x + size * .28, y + size * .18, x + size * .84, y + size * .5, x + size * .28, y + size * .82)
    elseif name == "square" then
      g.rectangle("fill", x + size * .22, y + size * .22, size * .56, size * .56, size * .06)
    elseif name == "monitor" then
      g.rectangle("line", x + size * .1, y + size * .15, size * .8, size * .58, size * .07)
      g.line(x + size * .5, y + size * .73, x + size * .5, y + size * .9)
      g.line(x + size * .32, y + size * .9, x + size * .68, y + size * .9)
    elseif name == "gamepad-2" then
      g.line(x + size * .15, y + size * .28, x + size * .85, y + size * .28,
        x + size * .94, y + size * .65, x + size * .92, y + size * .78,
        x + size * .78, y + size * .78, x + size * .66, y + size * .61,
        x + size * .34, y + size * .61, x + size * .22, y + size * .78,
        x + size * .08, y + size * .78, x + size * .06, y + size * .65, x + size * .15, y + size * .28)
      g.line(x + size * .25, y + size * .46, x + size * .42, y + size * .46)
      g.line(x + size * .335, y + size * .37, x + size * .335, y + size * .55)
      g.circle("fill", x + size * .73, y + size * .42, size * .035)
      g.circle("fill", x + size * .81, y + size * .5, size * .035)
    elseif name == "chart-no-axes-column" then
      for i = 1, #CHART_BARS do
        local bar = CHART_BARS[i]
        g.rectangle("fill", x + size * bar[1], y + size * bar[2], size * .11, size * (.82 - bar[2]))
      end
      g.line(x + size * .1, y + size * .9, x + size * .9, y + size * .9)
    end
    g.pop()
    return
  end
  if g and name == "triangle-alert" then
    g.push("all")
    g.setColor(color[1] / 255, color[2] / 255, color[3] / 255, alpha or 1)
    g.setLineWidth(math.max(1, size * 0.075))
    g.polygon("line", x + size * 0.5, y + size * 0.1,
      x + size * 0.08, y + size * 0.88, x + size * 0.92, y + size * 0.88)
    g.line(x + size * 0.5, y + size * 0.35, x + size * 0.5, y + size * 0.59)
    g.circle("fill", x + size * 0.5, y + size * 0.74, size * 0.045)
    g.pop()
    return
  end
  if not g or not g.newQuad or not g.newImage then
    return
  end
  local cell = cells[name]
  if not cell then
    return
  end
  local atlas = cell.atlas
  if not atlas.image then
    atlas.image = g.newImage(atlas.path)
    if atlas.image.setFilter then
      atlas.image:setFilter("linear", "linear")
    end
    atlas.quads = {}
    for i, id in ipairs(atlas.names) do
      atlas.quads[id] = g.newQuad((i - 1) * 96, 0, 96, 96, #atlas.names * 96, 96)
    end
  end
  local quad = atlas.quads[name]
  if not quad then
    return
  end
  g.setColor(color[1] / 255, color[2] / 255, color[3] / 255, alpha or 1)
  g.draw(atlas.image, quad, x, y, 0, size / 96, size / 96)
end

return Icons
