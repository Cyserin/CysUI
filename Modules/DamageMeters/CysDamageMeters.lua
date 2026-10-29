--------------------------------------------------------------------------------
-- Cys's Damage Meters
--   * A "Cys's UI" skin for the Details! damage meter: flat dark window, gold edge, flat class-coloured bars.
--     It is installed into Details! when both are loaded; pick it in Details' own skin list or use the button
--     on the Damage Meters page of /cui. Nothing is changed in Details until you choose the skin.
--   * The reskin of Blizzard's own damage meter will be added once Forever is out and it can be tested.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "damagemeters", name = "Cys's Damage Meters",
    desc = "A Cys's UI skin for the Details! damage meter (flat dark bars with gold edges). Blizzard's own meter comes after Forever.",
    open = function() CysUI:OpenConfig("Damage Meters") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T

CysUIDB.damageMeters = CysUIDB.damageMeters or {}
local db = CysUIDB.damageMeters
if db.border == nil then db.border = true end

local SKIN = "Cys's UI"
local installed = false

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = DeepCopy(v) end
    return c
end

-- gold edge around a Details window (follows the Border color setting like the rest of Cys's UI)
local function Decorate(instance)
    local bf = instance and instance.baseframe
    if not bf then return end
    if not bf.cysBorder then
        local b = CreateFrame("Frame", nil, bf)
        b:SetPoint("TOPLEFT", bf, "TOPLEFT", -2, 2)
        b:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", 2, -2)
        b:SetFrameLevel(bf:GetFrameLevel() + 5)
        W.Border(b, 2, T.border, "OVERLAY")
        bf.cysBorder = b
    end
    -- the title strip sits just above the window: back it with our own dark strip (behind Details' title text and buttons)
    if not bf.cysTitle then
        local tf = CreateFrame("Frame", nil, bf)
        tf:SetFrameLevel(math.max(0, bf:GetFrameLevel() - 1))
        tf:SetPoint("BOTTOMLEFT", bf, "TOPLEFT", -2, 0)
        tf:SetPoint("BOTTOMRIGHT", bf, "TOPRIGHT", 2, 0)
        tf:SetHeight(21)
        W.Texture(tf, "BACKGROUND", { 0.067, 0.067, 0.067, 0.95 }):SetAllPoints()
        -- the edge lives in its own frame above Details' toolbar pieces, which otherwise cover part of it
        local ef = CreateFrame("Frame", nil, bf)
        ef:SetFrameLevel(bf:GetFrameLevel() + 6)
        ef:SetPoint("TOPLEFT", tf, "TOPLEFT")
        ef:SetPoint("BOTTOMRIGHT", tf, "BOTTOMRIGHT")
        W.Border(ef, 2, T.border, "OVERLAY")
        tf.edge = ef
        bf.cysTitle = tf
    end
    -- undo the earlier attempt that stretched Details' own top texture into black squares
    local tb = bf.cabecalho and bf.cabecalho.top_bg
    if tb and instance.skin == SKIN then tb:SetAlpha(0) end
    -- every window using the skin keeps the same bar spacing and icon position, even one that was switched to the skin earlier
    local ri = instance.skin == SKIN and instance.row_info
    if ri then
        local off, sp = ri.icon_offset, ri.space
        if not off or off[1] ~= 1 or not sp or sp.left ~= 0 or sp.right ~= -3 then
            ri.icon_offset = { 1, 0 }
            ri.space = ri.space or {}
            ri.space.left, ri.space.right, ri.space.between = 0, -3, 1
            if instance.InstanceRefreshRows then instance:InstanceRefreshRows() end
            if instance.RefreshBars then instance:RefreshBars() end
        end
    end
    local mine = db.border and instance.skin == SKIN
    bf.cysBorder:SetShown(mine)
    bf.cysTitle:SetShown(mine)
    if bf.cysTitle.edge then bf.cysTitle.edge:SetShown(mine) end
end

local function BuildSkin(D)
    local base = D.skins and D.skins["Forced Square"]
    if not (base and base.instance_cprops) then return end
    local s = DeepCopy(base)
    s.is_cached_skin = nil
    s.author = "Cys's UI"
    s.version = "1.0"
    s.site = ""
    s.desc = "Flat dark window with a gold edge and flat class-coloured bars, to match Cys's UI."
    s.no_cache = true
    s.callback = function(_, instance) pcall(Decorate, instance) end
    s.skin_options = nil
    local cp = s.instance_cprops
    cp.bg_alpha = 0.9
    cp.bg_r, cp.bg_g, cp.bg_b = 0.067, 0.067, 0.067
    cp.show_sidebars = false
    cp.wallpaper = cp.wallpaper or {}
    cp.wallpaper.enabled = false
    local ri = cp.row_info
    if ri then
        ri.texture = "Details Flat"
        ri.texture_file = "Interface\\Buttons\\WHITE8X8"
        ri.texture_class_colors = true
        ri.alpha = 0.72
        ri.height = 18
        ri.space = { left = 0, right = -3, between = 1 }
        ri.texture_background_class_color = false
        ri.texture_background_file = "Interface\\Buttons\\WHITE8X8"
        ri.fixed_texture_background_color = { 0.16, 0.16, 0.16, 0.6 }
        ri.backdrop = ri.backdrop or {}
        ri.backdrop.enabled = false
        -- the same game font as the rest of the UI instead of Details' pixel font
        ri.font_face = "Friz Quadrata TT"
        ri.font_face_file = "Fonts\\FRIZQT__.TTF"
        ri.font_size = 11
        ri.icon_offset = { 1, 0 }
        ri.textL_class_colors = false
        ri.textR_class_colors = false
        ri.fixed_text_color = { 1, 1, 1, 1 }
        ri.textL_outline = false
        ri.textR_outline = false
    end
    -- window title ("Damage Done"): game font, gold
    local at = cp.attribute_text
    if at then
        at.text_face = "Friz Quadrata TT"
        at.text_size = 11
        at.text_color = { 1, 0.82, 0, 1 }
        at.shadow = false
    end
    if s.micro_frames then s.micro_frames.font = "Friz Quadrata TT" end
    return s
end

local function Install()
    local D = _G.Details
    if not (D and D.InstallSkin and D.skins) then return false end
    if installed and D.skins[SKIN] then return true end
    local skin = BuildSkin(D)
    if not skin then return false end
    local ok, res = pcall(D.InstallSkin, D, SKIN, skin)
    installed = ok and res and true or false
    return installed
end

local function EachInstance(fn)
    local D = _G.Details
    if not (D and D.GetInstance) then return end
    for i = 1, 12 do
        local inst = D:GetInstance(i)
        if inst then pcall(fn, inst) end
    end
end

local function UseSkinEverywhere()
    if not Install() then return false end
    EachInstance(function(inst)
        inst:ChangeSkin(SKIN)
        Decorate(inst)
    end)
    return true
end

-- Details loads after us, so keep trying for a while; afterwards keep the edge in step with the chosen skin
do
    local tries = 0
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self, event, name)
        -- install the skin the moment Details exists, before it builds its windows, so no default window flashes first
        if event == "ADDON_LOADED" then
            if name == "Details" then pcall(Install) end
            return
        end
        if event == "PLAYER_LOGIN" then pcall(Install) return end
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(0.25, function(t)
                tries = tries + 1
                if Install() or tries > 80 then t:Cancel() end
            end)
            C_Timer.NewTicker(0.5, function() EachInstance(Decorate) end)
        else
            Install()
        end
    end)
end

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Damage Meters", function(page)
    local width = 480
    W.Header(page, "Damage Meters", width):SetPoint("TOPLEFT", 0, -4)

    local status = W.Text(page, 12, T.text)
    status:SetPoint("TOPLEFT", 4, -34)
    local function Status()
        local D = _G.Details
        if not D then status:SetText("Details! is not loaded.")
        elseif installed then status:SetText("Details! found: the |cFFFFD100" .. SKIN .. "|r skin is installed.")
        else status:SetText("Details! found, but its skin list is not ready yet (try again in a moment).") end
    end

    local use = W.Button(page, 330, 24, "Use the Cys's UI skin on all Details windows")
    use:SetPoint("TOPLEFT", 4, -62)
    use:SetScript("OnClick", function()
        if UseSkinEverywhere() then CUI:Print("Details windows now use the " .. SKIN .. " skin.")
        else CUI:Print("Details! is not ready (is it loaded?).") end
        Status()
    end)

    local cb = W.Checkbox(page, "Gold edge around Details windows", function() return db.border end,
        function(on) db.border = on; EachInstance(Decorate) end)
    cb:SetPoint("TOPLEFT", 4, -96)

    W.Notes(page, 4, -134, width, "", {
        { "Details!", "the skin is also in Details' own skin list (its Options, then Skin Selection), where you can pick it per window." },
        "Nothing in Details is changed until you choose the skin.",
        { "Blizzard's own damage meter", "gets the same treatment once Forever is out and it can be tested." },
    })
    Status()
    page.contentHeight = 320
end, function() end)

end,
})
