--------------------------------------------------------------------------------
-- Cys's UI - Group Loot Skin
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local max, min, floor = math.max, math.min, math.floor

local GL = {}
CUI.GroupLoot = GL

local holder

local function DB()
    if not CysUIDB then CysUIDB = {} end
    if not CysUIDB.grouploot then
        CysUIDB.grouploot = { enable = true, scale = 1.0, customWidth = 280, customHeight = 60 }
    end
    if CysUIDB.grouploot.scale == nil then CysUIDB.grouploot.scale = 1.0 end
    if CysUIDB.grouploot.customWidth == nil then CysUIDB.grouploot.customWidth = 280 end
    if CysUIDB.grouploot.customHeight == nil then CysUIDB.grouploot.customHeight = 60 end
    if CysUIDB.grouploot.qualityColors == nil then CysUIDB.grouploot.qualityColors = true end
    return CysUIDB.grouploot
end

-- Blizzard places the icon, name, roll buttons and timer for its own box size. Lay them out again for ours:
-- icon on the left, name beside it (one line, cut short rather than wrapped), Need / Greed / Pass on the right,
-- the timer along the bottom.
local function Part(frame, key)
    local n = frame:GetName()
    return frame[key] or (n and _G[n .. key])
end

local function LayoutRollFrame(frame)
    if not frame or not frame.cysSkinned then return end
    local w, h = frame:GetWidth(), frame:GetHeight()
    if not w or not h or w < 10 then return end
    local isz = max(18, min(h - 12, 44))

    local iconFrame = Part(frame, "IconFrame")
    local icon = Part(frame, "Icon") or (iconFrame and iconFrame.Icon)
    if iconFrame then
        iconFrame:ClearAllPoints()
        iconFrame:SetPoint("LEFT", frame, "LEFT", 6, 3)
        iconFrame:SetSize(isz, isz)
        local border = Part(iconFrame, "Border") or Part(frame, "IconFrameBorder")
        if border and border.SetAlpha then border:SetAlpha(0) end
        if icon then
            icon:ClearAllPoints()
            icon:SetAllPoints(iconFrame)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end

    -- buttons, right to left: Pass, Greed, Disenchant, Need
    local bsize = max(18, min(floor((h - 12) * 0.6), 28))
    local anchor, anchorPoint, gap = frame, "RIGHT", -6
    local leftmost
    for _, key in ipairs({ "PassButton", "GreedButton", "DisenchantButton", "NeedButton" }) do
        local b = Part(frame, key)
        if b and b.SetPoint and (b:IsShown() or key == "PassButton") then
            b:ClearAllPoints()
            b:SetSize(bsize, bsize)
            b:SetPoint("RIGHT", anchor, anchorPoint, gap, 3)
            anchor, anchorPoint, gap = b, "LEFT", -4
            leftmost = b
        end
    end

    local name = Part(frame, "Name")
    if name and name.SetPoint then
        name:ClearAllPoints()
        if iconFrame then
            name:SetPoint("LEFT", iconFrame, "RIGHT", 8, 0)
        else
            name:SetPoint("LEFT", frame, "LEFT", isz + 14, 3)
        end
        name:SetPoint("RIGHT", leftmost or frame, leftmost and "LEFT" or "RIGHT", -8, 0)
        name:SetJustifyH("LEFT")
        if name.SetWordWrap then name:SetWordWrap(false) end
        if name.SetMaxLines then name:SetMaxLines(1) end
    end

    local timer = Part(frame, "Timer")
    if timer then
        timer:ClearAllPoints()
        timer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 3)
        timer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 3)
        timer:SetHeight(5)
    end
end
GL.LayoutRollFrame = LayoutRollFrame

local function ApplyDimensions()
    if holder then
        holder:SetScale(DB().scale)
        holder:SetSize(DB().customWidth, DB().customHeight)
    end
    -- Keep preview size synced while sliding or pushing adjustments
    if GL.previewFrame and GL.previewActive then
        GL.previewFrame:SetSize(DB().customWidth, DB().customHeight)
        GL.previewFrame:SetScale(DB().scale)
    end
    for i = 1, 4 do
        local frame = _G["GroupLootFrame" .. i]
        if frame then
            frame:SetSize(DB().customWidth, DB().customHeight)
            LayoutRollFrame(frame)
        end
    end
end


local function SkinGroupLootFrame(frame)
    if not frame or frame.cysSkinned then return end
    frame.cysSkinned = true

    -- Strip default Blizzard textures
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "Texture" then
            region:SetTexture(nil)
        end
    end

    -- Create CysUI Panel Background & Gold Border
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetAllPoints(frame)
    panel:SetFrameLevel(max(frame:GetFrameLevel() - 1, 0))
    W.Texture(panel, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.95 }):SetAllPoints()
    frame.cysEdges = W.Border(panel, 1, T.border, "BORDER")

    -- Restyle the Timer Bar
    local timer = frame.Timer or _G[frame:GetName() .. "Timer"]
    if timer then
        timer:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        timer:SetStatusBarColor(T.accent[1], T.accent[2], T.accent[3], 0.8)
        if timer.Background then timer.Background:SetAlpha(0) end
        W.Border(timer, 1, T.border, "BORDER")
    end

    -- Style Item Icon
    local icon = frame.Icon or _G[frame:GetName() .. "Icon"]
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    frame:HookScript("OnShow", function(self)
        if GL.previewActive then GL.TogglePreview(false) end -- a real roll is here: the sample steps aside
        GL.ColorByQuality(self)
        LayoutRollFrame(self)
        C_Timer.After(0, function() LayoutRollFrame(self) end) -- Blizzard fills in the buttons just after showing
    end)
end

-- Border and timer bar take the colour of the item being rolled on (green / blue / purple...)
function GL.ColorByQuality(frame)
    if not frame or not frame.cysEdges then return end
    local c
    if DB().qualityColors and frame.rollID and GetLootRollItemInfo then
        local ok, _, _, _, quality = pcall(GetLootRollItemInfo, frame.rollID)
        c = ok and quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    end
    W.SetBorder(frame.cysEdges, c and { c.r, c.g, c.b } or T.border)
    local timer = frame.Timer or _G[frame:GetName() .. "Timer"]
    if timer then
        if c then timer:SetStatusBarColor(c.r, c.g, c.b, 0.85)
        else timer:SetStatusBarColor(T.accent[1], T.accent[2], T.accent[3], 0.8) end
    end
end

function GL.RecolorAll()
    for i = 1, 4 do GL.ColorByQuality(_G["GroupLootFrame" .. i]) end
end

-- Toggle function to preview Group Loot frame safely out of group
function GL.TogglePreview(forceState)
    if forceState ~= nil then
        GL.previewActive = forceState
    else
        GL.previewActive = not GL.previewActive
    end

    -- Create a dedicated mock preview frame if it doesn't exist yet
    if not GL.previewFrame then
        GL.previewFrame = CreateFrame("Frame", "CysUI_GroupLootPreviewBox", UIParent)
        
        -- Style background texture matching your UI's configuration
        GL.previewFrame.bg = GL.previewFrame:CreateTexture(nil, "BACKGROUND")
        GL.previewFrame.bg:SetAllPoints()
        GL.previewFrame.bg:SetColorTexture(unpack(T.bg))
        
        -- Sharp gold border
        GL.previewFrame.border = W.Border(GL.previewFrame, 1, T.border, "BORDER")
        
        -- Mock Item Icon
        GL.previewFrame.icon = GL.previewFrame:CreateTexture(nil, "ARTWORK")
        GL.previewFrame.icon:SetPoint("TOPLEFT", GL.previewFrame, "TOPLEFT", 6, -6)
        GL.previewFrame.icon:SetPoint("BOTTOMLEFT", GL.previewFrame, "BOTTOMLEFT", 6, 6)
        GL.previewFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        GL.previewFrame.icon:SetTexture("Interface\\Icons\\INV_Weapon_ShortBlade_11") -- Skinned Cavern Dagger texture
        
        -- Dynamic scale setup to maintain square proportions
        GL.previewFrame:SetScript("OnSizeChanged", function(self, width, height)
            if self.icon then
                self.icon:SetWidth(height - 12)
            end
        end)

        -- Mock Text Label (Set to Blue/Rare item color text)
        GL.previewFrame.text = GL.previewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        GL.previewFrame.text:SetPoint("TOPLEFT", GL.previewFrame.icon, "TOPRIGHT", 8, -6)
        GL.previewFrame.text:SetText("Tail Spike")
        GL.previewFrame.text:SetTextColor(0.0, 0.44, 0.87) -- Rare Quality Blue
        
        -- Helper function to generate mock unsecure roll click buttons
        local function CreateMockButton(parent, texture, size, xOffset)
            local btn = CreateFrame("Button", nil, parent)
            btn:SetSize(size, size)
            btn:SetPoint("RIGHT", parent, "RIGHT", xOffset, 0)
            
            btn.normal = btn:CreateTexture(nil, "ARTWORK")
            btn.normal:SetAllPoints()
            btn.normal:SetTexture(texture)
            
            btn:SetScript("OnEnter", function(self) self.normal:SetVertexColor(1, 1, 1, 1) end)
            btn:SetScript("OnLeave", function(self) self.normal:SetVertexColor(0.8, 0.8, 0.8, 0.9) end)
            btn:SetScript("OnClick", function(self)
                CUI:Print("|cff00aaffCysUI Preview: Click registered without errors!|r")
            end)
            btn.normal:SetVertexColor(0.8, 0.8, 0.8, 0.9)
            return btn
        end

        -- Add standard Blizzard asset graphics for rolls
        GL.previewFrame.passBtn  = CreateMockButton(GL.previewFrame, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", 20, -8)
        GL.previewFrame.greedBtn = CreateMockButton(GL.previewFrame, "Interface\\Buttons\\UI-GroupLoot-Coin-Up", 20, -32)
        GL.previewFrame.needBtn  = CreateMockButton(GL.previewFrame, "Interface\\Buttons\\UI-GroupLoot-Dice-Up", 20, -56)

        -- Mock Timer Bar simulation
        GL.previewFrame.timer = CreateFrame("StatusBar", nil, GL.previewFrame)
        GL.previewFrame.timer:SetPoint("BOTTOMLEFT", GL.previewFrame, "BOTTOMLEFT", 4, 2)
        GL.previewFrame.timer:SetPoint("BOTTOMRIGHT", GL.previewFrame, "BOTTOMRIGHT", -4, 2)
        GL.previewFrame.timer:SetHeight(4)
        GL.previewFrame.timer:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        GL.previewFrame.timer:SetStatusBarColor(unpack(T.accent))
        GL.previewFrame.timer:SetMinMaxValues(0, 100)
        GL.previewFrame.timer:SetValue(65)
    end

    if GL.previewActive then
        -- Match exact real measurements configured in options
        GL.previewFrame:SetSize(DB().customWidth, DB().customHeight)
        GL.previewFrame:SetScale(DB().scale)
        GL.previewFrame:ClearAllPoints()
        
        -- Anchor securely to your movable container link frame
        if holder then
            GL.previewFrame:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
        else
            GL.previewFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        
        GL.previewFrame:Show()
        CUI:Print("|cFF00FF00Group Loot Preview: ENABLED|r")
    else
        if GL.previewFrame then
            GL.previewFrame:Hide()
        end
        CUI:Print("|cFFFF9F43Group Loot Preview: DISABLED|r")
    end
end




function GL.Enable()
    if not DB().enable then return end

    -- Register Layout Movable Anchor for Group Loot (Need/Greed)
    holder = CreateFrame("Frame", "CysUI_GroupLootAnchor", UIParent)
    holder:SetSize(DB().customWidth, DB().customHeight)
    CUI:RegisterMovable(holder, "grouploot_box", "Group Loot Boxes", {
        point = "TOPLEFT", x = 16, y = -120,
        scalable = false,
        resizable = true, minW = 150, maxW = 500, minH = 30, maxH = 140,
        onResize = function(_, w, h)
            DB().customWidth, DB().customHeight = math.floor(w + 0.5), math.floor(h + 0.5)
            if GL.ApplyDims then GL.ApplyDims() end
        end,
    })
    GL.ApplyDims = ApplyDimensions
    
    ApplyDimensions()

    -- Skin existing Blizzard GroupLoot frames (1 to 4) and anchor to movable holder
    for i = 1, 4 do
        local frame = _G["GroupLootFrame" .. i]
        if frame then
            SkinGroupLootFrame(frame)
            frame:SetSize(DB().customWidth, DB().customHeight)
            LayoutRollFrame(frame)
            
            -- Hook SetPoint directly on each frame so Blizzard can't override it
            hooksecurefunc(frame, "SetPoint", function(self)
                if self.isRepositioning or not holder then return end
                self.isRepositioning = true
                self:ClearAllPoints()
                if i == 1 then
                    self:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
                else
                    local prev = _G["GroupLootFrame" .. (i - 1)]
                    if prev then
                        self:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, 4)
                    end
                end
                self.isRepositioning = nil
            end)
        end
    end

    -- Hook layout updates when roll windows appear
    if hooksecurefunc and GroupLootContainer_Update then
        hooksecurefunc("GroupLootContainer_Update", function()
            if holder and not GL.previewActive then
                for i = 1, 4 do
                    local frame = _G["GroupLootFrame" .. i]
                    if frame and frame:IsShown() then
                        frame:SetSize(DB().customWidth, DB().customHeight)
                        LayoutRollFrame(frame)
                        frame:ClearAllPoints()
                        if i == 1 then
                            frame:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
                        else
                            local prev = _G["GroupLootFrame" .. (i - 1)]
                            if prev then
                                frame:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, 4)
                            end
                        end
                    end
                end
            end
        end)
    end
end

CUI:RegisterModule({
    key = "grouploot",
    name = "Group Loot Boxes",
    addon = "CysUI",
    desc = "Skins Blizzard's default Need/Greed roll boxes with flat gold borders.",
    onEnable = GL.Enable,
    open = function() CUI:OpenConfig("Loot") end,
})

CUI:RegisterPage("Loot", function(page)
    local db = DB()
    local width = 480

    -- the loot window (the "Items" box you click to pick up loot)
    W.Header(page, "Loot window", width):SetPoint("TOPLEFT", 0, -4)
    local intro = W.Text(page, 11, T.desc)
    intro:SetPoint("TOPLEFT", 4, -32)
    intro:SetWidth(width)
    intro:SetText("Where the window with the items opens when you loot a mob or chest.")
    local skinsDB = function() return (CUI.Skins and CUI.Skins.DB) and CUI.Skins.DB() or {} end
    local lootButtons = {}
    local function PaintLoot()
        local sdb = skinsDB()
        for key, b in pairs(lootButtons) do b:SetPrimary((sdb.lootPos or "fixed") == key) end
    end
    local bx = 4
    for _, def in ipairs({ { "default", "Blizzard's spot" }, { "cursor", "At the mouse" }, { "fixed", "Fixed spot (move it)" } }) do
        local b = W.Button(page, 150, 24, def[2])
        b:SetPoint("TOPLEFT", bx, -54)
        b:SetScript("OnClick", function()
            skinsDB().lootPos = def[1]
            PaintLoot()
            if CUI.Skins and CUI.Skins.ApplyLootCursorSetting then CUI.Skins.ApplyLootCursorSetting() end
            if def[1] == "fixed" then CUI:Print("Loot window: fixed spot. Move it in /cui layout (Loot Window).") end
        end)
        lootButtons[def[1]] = b
        bx = bx + 158
    end
    PaintLoot()
    local moveLoot = W.Button(page, 240, 22, "Move the loot window (layout mode)")
    moveLoot:SetPoint("TOPLEFT", 4, -88)
    moveLoot:SetScript("OnClick", function() CUI:ToggleLayout() end)

    -- group loot (Need / Greed / Pass roll boxes)
    W.Header(page, "Group loot boxes", width):SetPoint("TOPLEFT", 0, -130)
    local cb = W.Checkbox(page, "Enable Group Loot Box Skin (requires /reload)", function() return db.enable end, function(on) db.enable = on end)
    cb:SetPoint("TOPLEFT", 4, -160)
    local cq = W.Checkbox(page, "Color the border and timer by item quality", function() return db.qualityColors end,
        function(on) db.qualityColors = on; GL.RecolorAll() end)
    cq:SetPoint("TOPLEFT", 4, -186)

    local move = W.Button(page, 240, 22, "Move the group loot boxes (layout mode)")
    move:SetPoint("TOPLEFT", 4, -220)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)

    local previewBtn = W.Button(page, 240, 22, "Toggle group loot preview")
    previewBtn:SetPoint("TOPLEFT", 4, -250)
    previewBtn:SetScript("OnClick", function() GL.TogglePreview() end)

    W.Header(page, "Group loot size", width):SetPoint("TOPLEFT", 0, -286)
    local w = W.Stepper(page, "Box width", function() return db.customWidth end,
        function(v) db.customWidth = v; ApplyDimensions() end, 150, 500, 10, " px")
    w:SetPoint("TOPLEFT", 4, -318)
    local h = W.Stepper(page, "Box height", function() return db.customHeight end,
        function(v) db.customHeight = v; ApplyDimensions() end, 40, 150, 5, " px")
    h:SetPoint("TOPLEFT", 4, -348)
    local sc = W.Stepper(page, "Scale", function() return floor(db.scale * 100 + 0.5) end,
        function(v) db.scale = v / 100; ApplyDimensions() end, 60, 150, 5, "%")
    sc:SetPoint("TOPLEFT", 4, -378)
    page.contentHeight = 420
end)
