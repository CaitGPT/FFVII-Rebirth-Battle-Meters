-- Runs overlay.lua against fake UMG objects to check the compact drawing path: bars on one layer and text on the one
-- above, widgets reused between draws, unused ones collapsed, and nothing set twice. Whether UMG draws it as intended is
-- for a live test.
local saved = {loaded = package.loaded.overlay}
local globals = {"StaticFindObject", "StaticConstructObject", "FName", "FText"}
for _, name in ipairs(globals) do saved[name] = _G[name] end

local calls = {}
local function count(name) calls[name] = (calls[name] or 0) + 1 end
local function object(kind, fields)
    fields = fields or {}
    fields.kind = kind
    fields.IsValid = function() return true end
    return fields
end
local function widget(kind)
    local w = object(kind, {visibility = nil, children = {}})
    function w:SetVisibility(v) count("SetVisibility"); self.visibility = v end
    function w:SetColorAndOpacity(c) count("SetColorAndOpacity"); self.color = c end
    if kind == "CanvasPanel" then
        function w:AddChildToCanvas(child)
            local slot = {child = child}
            function slot:SetAutoSize() end
            function slot:SetPosition(p) count("SetPosition"); self.position = p end
            function slot:SetSize(s) count("SetSize"); self.size = s end
            self.children[#self.children + 1] = child
            child.slot = slot
            return slot
        end
    elseif kind == "Image" then
        w.Brush = {}
        function w:SetBrushResourceObject(r) self.resource = r end
    elseif kind == "TextBlock" then
        w.Font = {}
        function w:SetShadowOffset() end
        function w:SetShadowColorAndOpacity() end
        function w:SetJustification(j) self.justify = j end
        function w:SetText(t) count("SetText"); self.text = t end
    elseif kind == "UserWidget" then
        function w:AddToViewport() end
        function w:IsInViewport() return true end
    end
    return w
end

local classes = {}
for _, kind in ipairs({"UserWidget", "TextBlock", "Image", "WidgetTree", "CanvasPanel"}) do
    classes["/Script/UMG." .. kind] = object("class", {makes = kind})
end
local root_widget
local objects = {
    ["/Script/Engine.Default__GameplayStatics"] = object("statics", {GetPlayerController = function() return object("pc") end}),
    ["/Script/UMG.Default__WidgetBlueprintLibrary"] = object("library", {Create = function()
        root_widget = widget("UserWidget")
        return root_widget
    end}),
    ["/Game/Menu/Resident/Texture/U_Status_Base_01.U_Status_Base_01"] = object("texture"),
}
StaticFindObject = function(path) return classes[path] or objects[path] end
StaticConstructObject = function(class) return widget(class.makes) end
FName = function(s) return s end
FText = function(s) return s end

package.loaded.overlay = nil
local ok, err = pcall(function()
    local overlay = require("overlay")
    local View = require("compact_view")
    local function kind(average, total, by_source, attributed)
        return {average = average, recent = 0, total = total, biggest = 100, by_source = by_source or {}, attributed = attributed}
    end
    local snapshot = {elapsed = 30, kinds = {
        damage = kind(100, 3000, {Cloud = 2000, Tifa = 1000}, true),
        heal = kind(10, 300, {Cloud = 300}, true),
        taken = kind(20, 600, {Cloud = 400, Tifa = 200}),
        mp = kind(0, 0),
    }}
    local config = {layout = "compact", overlay_x = 48, overlay_y = 240, rolling_window_seconds = 5}

    local grid = View.build(snapshot, "grid", config)
    overlay.show(grid, config, object("world"))
    local root = root_widget.WidgetTree.RootWidget
    assert(root and root.kind == "CanvasPanel", "a root canvas")
    assert(#root.children == 3, "the panel, then two layers: " .. #root.children)
    local panel, bars, words = root.children[1], root.children[2], root.children[3]
    assert(panel.kind == "Image" and panel.resource, "the panel sprite comes first, at the back")
    assert(bars.kind == "CanvasPanel" and words.kind == "CanvasPanel", "then the bar layer and the text layer")
    for _, child in ipairs(bars.children) do assert(child.kind == "Image", "only bars on the bar layer") end
    for _, child in ipairs(words.children) do assert(child.kind == "TextBlock", "only text on the text layer") end
    assert(#bars.children == #grid.rects and #words.children == #grid.texts)
    assert(panel.slot.size.X == grid.width and panel.slot.size.Y == grid.height, "the panel fits the layout")
    assert(panel.slot.position.X == 48 and panel.slot.position.Y == 240)

    -- The same view again sets nothing: every setter is a reflected call on the game thread.
    calls = {}
    overlay.show(grid, config, object("world"))
    assert(not calls.SetText and not calls.SetPosition and not calls.SetSize and not calls.SetColorAndOpacity,
        "nothing changed, nothing set")

    -- A smaller layout reuses the widgets and collapses what it doesn't need.
    local single = View.build(snapshot, "dps_compact", config)
    overlay.show(single, config, object("world"))
    assert(#bars.children == #grid.rects, "no new bars")
    local shown, collapsed = 0, 0
    for _, child in ipairs(words.children) do
        if child.visibility == 1 then collapsed = collapsed + 1 elseif child.visibility == 3 then shown = shown + 1 end
    end
    assert(shown == #single.texts, string.format("%d texts shown for %d", shown, #single.texts))
    assert(shown + collapsed <= #words.children)
    local texts = {}
    for _, child in ipairs(words.children) do if child.visibility == 3 then texts[child.text] = true end end
    assert(texts["DMG"] and texts["Cloud"] and texts["67%"] and not texts["HEAL"], "the single meter's text")

    overlay.hide()
    assert(root_widget.visibility == 1, "hidden")
end)

for _, name in ipairs(globals) do _G[name] = saved[name] end
package.loaded.overlay = saved.loaded
if not ok then error(err) end
