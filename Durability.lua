--------------------------------------------------------------------------------
-- Cys's UI - Durability
--
-- Replaces Blizzard's little armor figure (the yellow / red man that pops up and gets in the way)
-- with a small Cys box that only shows when gear needs attention:
--   "Repair soon: Chest 18%"      (any piece at or under your warning level)
--   "Broken: Chest, Legs"         (red, when a piece is at 0 and gives no stats)
-- Move it with layout mode. Settings: /cui -> Durability.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local DEFAULTS = { warnAt = 20, hideBlizzard = true }

local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.durability = CysUIDB.durability or {}
    local db = CysUIDB.durability
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    return db
end

local SLOT_NAMES = {
    [1] = "Head", [3] = "Shoulders", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
    [9] = "Wrists", [10] = "Hands", [16] = "Main hand", [17] = "Off hand", [18] = "Ranged",
}
local SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

local box, text
local hidden = CreateFrame("Frame")
hidden:Hide()

local function HideBlizzard()
    local f = _G.DurabilityFrame
    if not f or f.cysHidden then return end
    if not DB().hideBlizzard then return end
    f.cysHidden = true
    f:SetParent(hidden)
    f:Hide()
end

local function Update()
    if not box then return end
    local db = DB()
    local broken, low = {}, {}
    local lowestPct
    for _, slot in ipairs(SLOTS) do
        local cur, maxDur = GetInventoryItemDurability(slot)
        if cur and maxDur and maxDur > 0 then
            local pct = math.floor(cur / maxDur * 100 + 0.5)
            if cur == 0 then
                broken[#broken + 1] = SLOT_NAMES[slot]
            elseif pct <= db.warnAt then
                low[#low + 1] = { name = SLOT_NAMES[slot], pct = pct }
                if not lowestPct or pct < lowestPct then lowestPct = pct end
            end
        end
    end
    if #broken > 0 then
        text:SetText("|cFFFF4040Broken:|r " .. table.concat(broken, ", ") .. "  |cFF999999(repair to get the stats back)|r")
    elseif #low > 0 then
        table.sort(low, function(a, b) return a.pct < b.pct end)
        local parts = {}
        for i = 1, math.min(3, #low) do parts[i] = low[i].name .. " " .. low[i].pct .. "%" end
        if #low > 3 then parts[#parts + 1] = "+" .. (#low - 3) .. " more" end
        text:SetText("|cFFFF9F43Repair soon:|r " .. table.concat(parts, ", "))
    else
        box:SetShown(CUI.layoutMode and true or false)
        text:SetText("Durability warning")
        return
    end
    box:SetWidth(math.max(160, text:GetStringWidth() + 24))
    box:Show()
end

local function Enable()
    if box then return end
    DB()
    box = CreateFrame("Frame", "CysUIDurability", UIParent)
    box:SetSize(220, 24)
    box:SetFrameStrata("MEDIUM")
    W.Texture(box, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.9 }):SetAllPoints()
    W.Border(box, 1, T.border, "BORDER")
    text = W.Text(box, 12, T.text, "CENTER")
    text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    text:SetPoint("CENTER", 0, 0)
    box:Hide()
    CUI:RegisterMovable(box, "durability", "Durability warning", { point = "TOP", x = 0, y = -170 })

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function() HideBlizzard(); Update() end)
    HideBlizzard()
    Update()
end

CUI.Durability = { Update = function() Update() end }

CUI:RegisterModule({
    key = "durability",
    name = "Durability",
    addon = "CysUI",
    desc = "Replaces Blizzard's armor figure with a small box that only shows when gear needs repairing or is broken. Move it in layout mode.",
    onEnable = Enable,
    open = function() CUI:OpenConfig("Durability") end,
})

CUI:RegisterPage("Durability", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Durability", width):SetPoint("TOPLEFT", 0, -4)
    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34); intro:SetWidth(width - 8); intro:SetJustifyV("TOP"); intro:SetSpacing(3)
    intro:SetText("A small box that only shows when a piece of gear needs repairing (orange) or is broken (red). It moves in layout mode.")

    local wl = W.Text(page, 12, T.accent)
    wl:SetPoint("TOPLEFT", 4, -84)
    wl:SetText("Warn when a piece is at or under")
    local dd = W.Dropdown(page, 160, { { 10, "10%" }, { 20, "20%" }, { 30, "30%" }, { 50, "50%" } },
        function() return db.warnAt end, function(v) db.warnAt = v; Update() end)
    dd:SetPoint("TOPLEFT", 4, -104)

    local cb = W.Checkbox(page, "Hide Blizzard's armor figure (back on needs a /reload)",
        function() return db.hideBlizzard end, function(on) db.hideBlizzard = on; HideBlizzard() end)
    cb:SetPoint("TOPLEFT", 4, -144)

    W.Notes(page, 4, -184, width, "", {
        { "Broken", "gear (0 durability) gives none of its stats or armor until it is repaired." },
        "The info bar's Durability shows your average all the time; this box is the warning.",
    })
end)
