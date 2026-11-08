-- The on-screen meter: plain UMG widgets built at runtime, so the mod needs no Blueprint assets, drawn with the
-- game's own HUD sprites and colours so it sits with the party panels. Text uses the engine's Roboto: the game's
-- EndTextBlock and EndImage draw nothing when created at runtime, and its bitmap fonts only work with them.
-- Draws a plain view table (see meter_view.lua). Called on the game thread.
local M = {}

local WIDTH, PAD = 300, 16
local LABEL = {R = 0.68, G = 0.84, B = 0.95, A = 1}   -- a brighter take on the party panel's "HP" label, for this smaller text
local WHITE = {R = 1, G = 1, B = 1, A = 1}
local DIM = {R = 0.62, G = 0.70, B = 0.76, A = 1}
local SHADOW = {R = 0, G = 0, B = 0, A = 0.6}
local SPRITES = "/Game/Menu/Resident/Texture/"
local VISIBLE, COLLAPSED = 3, 1                       -- ESlateVisibility: HitTestInvisible, Collapsed
local RIGHT = 2                                       -- ETextJustify
local STATS, SECTIONS = 12, 8                         -- HPS: 6 lines, then up to 5 characters and Unattributed
local LINE_HEIGHT = 10
local LINE_EDGE = {R = 0.8, G = 0.92, B = 1, A = 0.7}
local GAUGE_BACK = {R = 0.25, G = 0.33, B = 0.42, A = 1}

local ui = nil

local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil
end
local function valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end
local function find(path)
    local object = safe(StaticFindObject, path)
    return valid(object) and object or nil
end
local function sprite(name)
    return find(SPRITES .. name .. "." .. name)
end

local function new_name(self, prefix)
    self.count = self.count + 1
    return FName("BattleMeters" .. prefix .. self.count)
end

local function add_image(self, resource, margin, tint)
    local image = StaticConstructObject(self.image_class, self.tree, new_name(self, "Image"))
    if resource then
        image:SetBrushResourceObject(resource)
        image.Brush.DrawAs = 1
        image.Brush.Margin = margin
    end
    image:SetColorAndOpacity(tint or WHITE)
    local slot = self.canvas:AddChildToCanvas(image)
    slot:SetAutoSize(false)
    return {widget = image, slot = slot}
end

local function add_text(self, size, color, justify)
    local text = StaticConstructObject(self.text_class, self.tree, new_name(self, "Text"))
    text.Font.Size = size
    text.Font.TypefaceFontName = FName("Regular")
    text:SetColorAndOpacity({SpecifiedColor = color, ColorUseRule = 0})
    text:SetShadowOffset({X = 2, Y = 1})
    text:SetShadowColorAndOpacity(SHADOW)
    if justify then text:SetJustification(justify) end
    local slot = self.canvas:AddChildToCanvas(text)
    slot:SetAutoSize(false)
    return {widget = text, slot = slot, shown = nil}
end

local function create(config, world_object)
    local statics = find("/Script/Engine.Default__GameplayStatics")
    local library = find("/Script/UMG.Default__WidgetBlueprintLibrary")
    local widget_class = find("/Script/UMG.UserWidget")
    local text_class, image_class = find("/Script/UMG.TextBlock"), find("/Script/UMG.Image")
    if not (statics and library and widget_class and text_class and image_class) then return nil, "UMG classes not found" end
    local controller = safe(function() return statics:GetPlayerController(world_object, 0) end)
    if not valid(controller) then return nil, "no player controller" end
    local widget = safe(function() return library:Create(controller, widget_class, controller) end)
    if not valid(widget) then return nil, "Create failed" end

    local tree = StaticConstructObject(find("/Script/UMG.WidgetTree"), widget, FName("BattleMetersTree"))
    widget.WidgetTree = tree
    local canvas = StaticConstructObject(find("/Script/UMG.CanvasPanel"), tree, FName("BattleMetersCanvas"))
    tree.RootWidget = canvas
    local self = {widget = widget, tree = tree, canvas = canvas, text_class = text_class, image_class = image_class,
        x = config.overlay_x, y = config.overlay_y, count = 0, rows = {}, sections = {}}

    -- Everything is made up front; what isn't needed is collapsed. Drawn in this order, back to front.
    self.panel = add_image(self, sprite("U_Status_Base_01"), {Left = 0, Top = 0.3, Right = 0, Bottom = 0.3}, {R = 1, G = 1, B = 1, A = 0.95})
    self.edge = add_image(self, nil, nil, LINE_EDGE)
    self.back = add_image(self, nil, nil, GAUGE_BACK)
    for i = 1, SECTIONS do self.sections[i] = add_image(self, nil, nil, WHITE) end
    self.title = add_text(self, 22, WHITE)
    self.value = add_text(self, 26, WHITE, RIGHT)
    for i = 1, STATS do
        self.rows[i] = {label = add_text(self, 15, LABEL), value = add_text(self, 17, WHITE, RIGHT)}
    end
    widget:AddToViewport(1000)
    widget:SetVisibility(VISIBLE)
    return self
end

local function place(self, item, x, y, w, h)
    -- Each setter is a reflected call on the game thread, so only touch what changed.
    if item.x ~= x or item.y ~= y then
        item.slot:SetPosition({X = self.x + x, Y = self.y + y})
        item.x, item.y = x, y
    end
    if item.w ~= w or item.h ~= h then
        item.slot:SetSize({X = w, Y = h})
        item.w, item.h = w, h
    end
    if item.hidden ~= false then
        item.widget:SetVisibility(VISIBLE)
        item.hidden = false
    end
end

local function collapse(item)
    if item.hidden ~= true then
        item.widget:SetVisibility(COLLAPSED)
        item.hidden = true
    end
end

local function set_text(self, item, value, x, y, w, h)
    if item.shown ~= value then
        item.widget:SetText(FText(value))
        item.shown = value
    end
    place(self, item, x, y, w, h)
end

local function set_color(item, color)
    if item.color ~= color then
        item.widget:SetColorAndOpacity(color)
        item.color = color
    end
end

local function draw(self, view)
    local inner = WIDTH - PAD * 2
    local y = 8
    set_text(self, self.title, view.title, PAD, y + 3, inner * 0.4, 32)
    set_text(self, self.value, view.value, PAD + inner * 0.3, y, inner * 0.7, 38)
    y = y + 40
    for i = 1, STATS do
        local stat, pair = view.stats[i], self.rows[i]
        if stat then
            set_text(self, pair.label, stat[1], PAD, y + 2, inner * 0.65, 24)
            set_text(self, pair.value, stat[2], PAD + inner * 0.35, y, inner * 0.65, 24)
            y = y + 24
        else
            collapse(pair.label); collapse(pair.value)
        end
    end
    y = y + 6
    -- The line: the whole party, one section per character. Black has to show on the dark panel, hence the edge.
    if view.show_line then
        place(self, self.edge, PAD - 1, y - 1, inner + 2, LINE_HEIGHT + 2)
        place(self, self.back, PAD, y, inner, LINE_HEIGHT)
    else
        collapse(self.edge); collapse(self.back)
    end
    local x = 0
    for i = 1, SECTIONS do
        local segment, item = view.segments[i], self.sections[i]
        if segment then
            local width = segment.share * inner
            set_color(item, segment.color)
            place(self, item, PAD + x, y, width, LINE_HEIGHT)
            x = x + width
        else
            collapse(item)
        end
    end
    place(self, self.panel, 0, 0, WIDTH, y + (view.show_line and LINE_HEIGHT + 14 or 4))
end

function M.show(view, config, world_object)
    -- A level change takes the panel off the screen without destroying it.
    if not (ui and valid(ui.widget) and safe(function() return ui.widget:IsInViewport() end) == true) then
        local made, problem = create(config, world_object)
        if not made then
            if M.last_error ~= problem then print("[BattleMeters] overlay: " .. tostring(problem) .. "\n") end
            M.last_error = problem
            return
        end
        ui = made
        print("[BattleMeters] overlay created\n")
    end
    if ui.hidden then
        ui.widget:SetVisibility(VISIBLE)
        ui.hidden = false
    end
    draw(ui, view)
end

function M.hide()
    if ui and not ui.hidden and valid(ui.widget) then
        ui.widget:SetVisibility(COLLAPSED)
        ui.hidden = true
    end
end

return M
