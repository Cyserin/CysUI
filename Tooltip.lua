--------------------------------------------------------------------------------
-- Cys's UI - Tooltip
--
-- Restyles Blizzard's tooltips (it doesn't replace them):
--   * flat dark background with a gold edge; items get a border in their rarity color
--   * player names in class color, guild line in gold, a "Targeting:" line, a slim
--     colored health bar
--   * the vendor sell price on item tooltips (Classic doesn't show it away from a vendor)
--   * default tooltip position is a movable anchor (/cui layout), or follow the mouse
--
-- Anything this touches is wrapped so a game change can't break tooltips; if they ever
-- misbehave, untick Tooltip under /cui > Modules and reload.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local format, max = string.format, math.max

local TT = {}
CUI.Tooltip = TT

local function DB() return CysUIDB.tooltip end

local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
                   "ShoppingTooltip1", "ShoppingTooltip2", "WorldMapTooltip", "EmbeddedItemTooltip" }

local GOLD_BORDER = T.border -- the live frame-edge colour

--------------------------------------------------------------------------------
-- Look
--------------------------------------------------------------------------------
local function SetEdge(tip, color)
    local p = tip.cysPanel
    if p then W.SetBorder(p.edges, color) end
end

-- Blizzard re-applies its own backdrop when a tooltip is shown, so this runs every time.
local function Prepare(tip)
    if not tip.cysPanel then
        local p = CreateFrame("Frame", nil, tip)
        p:SetAllPoints(tip)
        p:SetFrameLevel(max(tip:GetFrameLevel() - 1, 0)) -- behind the tooltip's own text
        W.Texture(p, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.95 }):SetAllPoints()
        p.edges = W.Border(p, 1, T.border, "BORDER")
        tip.cysPanel = p
    end
    if tip.SetBackdropColor then tip:SetBackdropColor(0, 0, 0, 0) end
    if tip.SetBackdropBorderColor then tip:SetBackdropBorderColor(0, 0, 0, 0) end
    if tip.NineSlice then tip.NineSlice:SetAlpha(0) end
end

local function PlayerColor(unit)
    local _, class = UnitClass(unit)
    return class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
end

local function ReactionColor(unit)
    if UnitIsDead(unit) then return { 0.5, 0.5, 0.5 } end
    local reaction = UnitReaction(unit, "player")
    if not reaction then return { 0.8, 0.8, 0.8 } end
    if reaction <= 2 then return { 0.9, 0.2, 0.2 } end   -- hostile
    if reaction == 3 or reaction == 4 then return { 1, 0.82, 0 } end -- unfriendly / neutral
    return { 0.3, 0.85, 0.4 }                             -- friendly
end

-- Returns an RGB color table for unit level difficulty relative to the player
local function GetLevelColor(unit, fallbackLevel)
    local unitLevel = UnitLevel(unit)
    if (not unitLevel or unitLevel <= 0) and fallbackLevel then
        unitLevel = fallbackLevel
    end

    if not unitLevel or unitLevel <= 0 then
        return { 0.8, 0.8, 0.8 } -- Boss / unknown
    end
    
    local playerLevel = UnitLevel("player") or 1
    local diff = unitLevel - playerLevel

    if diff >= 5 then
        return { 1.0, 0.1, 0.1 }   -- Red (+5 or higher)
    elseif diff >= 3 then
        return { 1.0, 0.5, 0.25 }  -- Orange (+3 to +4)
    elseif diff >= -2 then
        return { 1.0, 0.92, 0.0 }  -- Yellow (-2 to +2)
    else
        local greenRange = GetQuestGreenRange and GetQuestGreenRange() or 5
        if unitLevel <= (playerLevel - greenRange) then
            return { 0.6, 0.6, 0.6 } -- Grey
        end
        return { 0.2, 0.8, 0.2 }     -- Green
    end
end

--------------------------------------------------------------------------------
-- Content
--------------------------------------------------------------------------------
local function OnItem(tip)
    if not tip.cysPanel then return end
    local db = DB()
    local link = tip.GetItem and select(2, tip:GetItem())
    if not link then return end

    if db.qualityBorder then
        local quality = select(3, GetItemInfo(link))
        local c = quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if c then SetEdge(tip, { c.r, c.g, c.b }) end
    end

    if db.showIDs then
        local id = tonumber(link:match("item:(%d+)"))
        if id then tip:AddDoubleLine("Item ID", tostring(id), T.accent[1], T.accent[2], T.accent[3], 1, 1, 1) end
    end

    -- Classic only shows the sell price at a vendor, where Blizzard adds its own money line
    if db.sellPrice and (tip.shownMoneyFrames or 0) == 0 then
        local sell = select(11, GetItemInfo(link))
        if sell and sell > 0 then
            tip:AddDoubleLine("Sell price", GetCoinTextureString(sell), T.accent[1], T.accent[2], T.accent[3], 1, 1, 1)
        end
    end
    tip:Show() -- re-measure after adding lines
end

local function OnSpell(tip, data)
    if not tip.cysPanel or not DB().showIDs then return end
    local id = data and data.id
    if not id and tip.GetSpell then id = select(2, tip:GetSpell()) end
    if id then tip:AddDoubleLine("Spell ID", tostring(id), T.accent[1], T.accent[2], T.accent[3], 1, 1, 1); tip:Show() end
end

local function OnUnit(tip)
    if not tip.cysPanel then return end
    local db = DB()
    local _, unit = tip:GetUnit()
    if not unit then return end
    if db.hideUnitInCombat and InCombatLockdown() then tip:Hide() return end

    if UnitIsPlayer(unit) then
        if db.classColors then
            local c = PlayerColor(unit)
            if c and GameTooltipTextLeft1 then GameTooltipTextLeft1:SetTextColor(c.r, c.g, c.b) end
        end

        -- Query guild info and safely add/update the guild line in gold
        local guildName = GetGuildInfo(unit)
        if guildName then
            local hasGuildLine = false
            for i = 2, tip:NumLines() do
                local line = _G["GameTooltipTextLeft" .. i]
                if line then
                    local text = line:GetText()
                    if text and text:find("<") and text:find(">") then
                        hasGuildLine = true
                        line:SetText("<" .. guildName .. ">")
                        line:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
                        break
                    end
                end
            end
            if not hasGuildLine and GameTooltipTextLeft2 then
                tip:AddLine("<" .. guildName .. ">", T.accent[1], T.accent[2], T.accent[3])
            end
        end
    end

   -- Scan tooltip lines to find and color the level text wherever it lives
    for i = 2, tip:NumLines() do
        local line = _G["GameTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and (text:find("Level") or text:find("Boss")) then
                -- Parse level integer directly from text in case unit is a corpse
                local parsedLevel = tonumber(text:match("Level (%d+)"))
                local lc = GetLevelColor(unit, parsedLevel)
                local hex = format("%02x%02x%02x", math.floor(lc[1] * 255 + 0.5), math.floor(lc[2] * 255 + 0.5), math.floor(lc[3] * 255 + 0.5))

                line:SetText(format("|cFF%s%s|r", hex, text))
                break
            end
        end
    end

    local bar = GameTooltipStatusBar
    if bar and db.healthBar then
        local c = (UnitIsPlayer(unit) and PlayerColor(unit)) or nil
        local r, g, b
        if c then r, g, b = c.r, c.g, c.b else local rc = ReactionColor(unit); r, g, b = rc[1], rc[2], rc[3] end
        bar:SetStatusBarColor(r, g, b)
    end

    if db.targetLine and UnitExists(unit .. "target") then
        local targetName = UnitName(unit .. "target")
        if targetName then
            local tc = UnitIsPlayer(unit .. "target") and PlayerColor(unit .. "target")
            local text = tc and format("|cFF%02x%02x%02x%s|r", math.floor(tc.r * 255 + 0.5), math.floor(tc.g * 255 + 0.5),
                math.floor(tc.b * 255 + 0.5), targetName) or targetName
            tip:AddDoubleLine("Targeting", text, T.accent[1], T.accent[2], T.accent[3], 1, 1, 1)
        end
    end
    tip:Show()
end

local function SkinHealthBar()
    local bar = GameTooltipStatusBar
    if not bar or bar.cysSkinned then return end
    bar.cysSkinned = true
    if bar.SetStatusBarTexture then bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8") end
    bar:SetHeight(5)
end

--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------
local function HookTooltip(tip)
    if tip.cysHooked then return end
    tip.cysHooked = true
    Prepare(tip)
    tip:HookScript("OnShow", function(self)
        Prepare(self)
        self:SetScale((DB().scale or 100) / 100)
    end)
    tip:HookScript("OnTooltipCleared", function(self) SetEdge(self, GOLD_BORDER) end)
    if not TooltipDataProcessor then
        -- older clients: the tooltip frames fire these scripts
        pcall(tip.HookScript, tip, "OnTooltipSetItem", OnItem)
        pcall(tip.HookScript, tip, "OnTooltipSetUnit", OnUnit)
        pcall(tip.HookScript, tip, "OnTooltipSetSpell", OnSpell)
    end
end

function TT.Enable()
    local db = DB()
    if db.skin then
        for _, name in ipairs(TOOLTIPS) do
            local tip = _G[name]
            if tip then
                local ok, err = pcall(HookTooltip, tip)
                if not ok then CUI:Print("|cFFFF9F43Tooltip: " .. name .. " skipped (" .. tostring(err) .. ")|r") end
            end
        end
        pcall(SkinHealthBar)
        if hooksecurefunc and SharedTooltip_SetBackdropStyle then
            pcall(hooksecurefunc, "SharedTooltip_SetBackdropStyle", function(self)
                if self.cysPanel then Prepare(self) end
            end)
        end
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
            pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, OnItem)
            pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, OnUnit)
            if Enum.TooltipDataType.Spell then
                pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Spell, OnSpell)
            end
        end
    end

    -- where the default tooltip appears: a movable anchor, or the mouse
    local follow = {}
    -- two groups: tooltips of things in the world (NPCs, players; their anchor parent is UIParent)
    -- and tooltips of buttons and frames (action bars, bags, unit frames). World settings start out
    -- as a copy of the button ones until changed.
    local function Cfg(world)
        local db = DB()
        if world then
            local on = db.worldCursor
            if on == nil then on = db.anchorCursor end
            return on, db.worldLift or db.cursorLift or 20, db.worldShift or db.cursorShift or 0
        end
        return db.anchorCursor, db.cursorLift or 20, db.cursorShift or 0
    end
    TT.Cfg = Cfg
    local function PlaceAtMouse(tip)
        local _, lift, shift = Cfg(follow.world)
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        local ts = tip:GetEffectiveScale() / s
        tip:ClearAllPoints()
        tip:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", (x / s + shift) / ts, (y / s + lift) / ts)
    end
    hooksecurefunc(GameTooltip, "SetOwner", function() follow.on = false end)
    GameTooltip:HookScript("OnHide", function() follow.on = false end)
    GameTooltip:HookScript("OnUpdate", function(self)
        if follow.on and follow.tip == self then PlaceAtMouse(self) end
    end)
    local anchor = CreateFrame("Frame", "CysUITooltipAnchor", UIParent)
    anchor:SetSize(220, 70)
    CUI:RegisterMovable(anchor, "tooltip", "Tooltip", { point = "BOTTOMRIGHT", x = -60, y = 120, scalable = false })
    if GameTooltip_SetDefaultAnchor then
        hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
            if tooltip ~= GameTooltip then return end
            local world = (parent == UIParent)
            if (Cfg(world)) then
                follow.world = world
                -- the game ignores an offset on its own mouse anchor, so the tooltip follows the mouse by itself
                tooltip:SetOwner(parent, "ANCHOR_NONE")
                follow.on = true
                follow.tip = tooltip
                PlaceAtMouse(tooltip)
            else
                tooltip:ClearAllPoints()
                tooltip:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
            end
        end)
    end
end

CUI:RegisterModule({
    key = "tooltip",
    name = "Tooltip",
    addon = "CysUI",
    desc = "Flat gold-edged tooltips with rarity borders, class-colored names, vendor sell price and a movable position.",
    onEnable = TT.Enable,
    open = function() CUI:OpenConfig("Tooltip") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Tooltip", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Tooltip", width):SetPoint("TOPLEFT", 0, -4)

    local y = -34
    local function Check(label, key)
        local cb = W.Checkbox(page, label, function() return db[key] end, function(on) db[key] = on end)
        cb:SetPoint("TOPLEFT", 4, y)
        y = y - 26
        return cb
    end
    Check("Color the border by item rarity", "qualityBorder")
    Check("Show the vendor sell price on items", "sellPrice")
    Check("Class-colored player names", "classColors")
    Check("Colored health bar on units", "healthBar")
    Check("Show who a unit is targeting", "targetLine")
    Check("Show item and spell IDs", "showIDs")
    Check("Hide unit tooltips while in combat", "hideUnitInCombat")

    -- where the tooltip appears, set separately for buttons and for the world
    local function Cfg(world) return (TT.Cfg or function() return false, 20, 0 end)(world) end
    local function Group(title, world)
        W.Header(page, title, width):SetPoint("TOPLEFT", 0, y)
        y = y - 30
        local cb = W.Checkbox(page, "Follow the mouse (instead of the anchor)",
            function() return (Cfg(world)) end,
            function(on) if world then db.worldCursor = on else db.anchorCursor = on end end)
        cb:SetPoint("TOPLEFT", 4, y)
        y = y - 28
        local lift = W.Stepper(page, "Lift above the mouse",
            function() return select(2, Cfg(world)) end,
            function(v) if world then db.worldLift = v else db.cursorLift = v end end, 0, 120, 4, " px")
        lift:SetPoint("TOPLEFT", 4, y)
        y = y - 30
        local shift = W.Stepper(page, "Shift left / right",
            function() return select(3, Cfg(world)) end,
            function(v) if world then db.worldShift = v else db.cursorShift = v end end, -300, 300, 10, " px")
        shift:SetPoint("TOPLEFT", 4, y)
        y = y - 40
    end
    y = y - 6
    Group("Action bars, bags and frames", false)
    Group("World (NPCs and players)", true)

    local sizeStep = W.Stepper(page, "Tooltip size", function() return db.scale or 100 end,
        function(v) db.scale = v end, 70, 150, 5, "%")
    sizeStep:SetPoint("TOPLEFT", 4, y - 6)
    y = y - 40

    local move = W.Button(page, 240, 22, "Move the tooltip anchor (layout mode)")
    move:SetPoint("TOPLEFT", 4, y)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)
    y = y - 40

    W.Header(page, "Look (needs a /reload)", width):SetPoint("TOPLEFT", 0, y)
    local skin = W.Checkbox(page, "Restyle the tooltips (flat dark with a gold edge)", function() return db.skin end,
        function(on) db.skin = on end)
    skin:SetPoint("TOPLEFT", 4, y - 30)

    local note = W.Text(page, 11, T.desc)
    note:SetPoint("TOPLEFT", 4, y - 60)
    note:SetWidth(width)
    note:SetJustifyV("TOP")
    note:SetSpacing(3)
    note:SetText("Most options apply to the next tooltip you open. If tooltips ever misbehave, untick Tooltip on the Modules page and reload.")
end)
