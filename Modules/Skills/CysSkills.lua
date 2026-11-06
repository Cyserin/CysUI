--------------------------------------------------------------------------------
-- Cys's UI - Skills (skill-up text; replaced the old Skill Tracker box on 6 Nov 2026)
--
-- When a skill goes up, a short line floats up and fades out on screen, e.g. "Axes 13 / 85", so you don't
-- have to open the skill page. Weapon skills, Defense and professions. It starts just above the player
-- frame; move it in layout mode. Works on Classic Era and WoW Forever (it reads the game's own
-- "Your skill in X has increased to N." message).
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local LINES, LIFE, FADE, RISE = 3, 3.5, 1.2, 14 -- lines shown, seconds, fade-out seconds, pixels risen per second

-- weapon skills (and Defense) cap at 5 x your level in Classic; used where the game has no skill list (Forever)
local WEAPON = {
    ["Axes"] = true, ["Two-Handed Axes"] = true, ["Swords"] = true, ["Two-Handed Swords"] = true,
    ["Maces"] = true, ["Two-Handed Maces"] = true, ["Daggers"] = true, ["Staves"] = true, ["Polearms"] = true,
    ["Fist Weapons"] = true, ["Bows"] = true, ["Guns"] = true, ["Crossbows"] = true, ["Thrown"] = true,
    ["Wands"] = true, ["Unarmed"] = true, ["Defense"] = true,
}

local holder
local pool, active = {}, {}

-- "Your skill in %s has increased to %d." -> a pattern that captures the name and the new value
local function MessagePattern()
    local s = SKILL_RANK_UP or "Your skill in %s has increased to %d."
    s = s:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    s = s:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. s .. "$"
end
local PATTERN

local function MaxRank(name)
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local n, isHeader, _, _, _, _, maxRank = GetSkillLineInfo(i)
            if n == name and not isHeader then return maxRank end
        end
    end
    if WEAPON[name] then return math.min((UnitLevel("player") or 1) * 5, 300) end
end

local function Layout()
    -- newest at the bottom, older lines above it, each drifting up as it ages
    local now = GetTime()
    for i, line in ipairs(active) do
        local age = now - line.start
        local slot = #active - i -- 0 = newest
        line.fs:ClearAllPoints()
        line.fs:SetPoint("BOTTOM", holder, "BOTTOM", 0, slot * 18 + age * RISE)
        local left = LIFE - age
        line.fs:SetAlpha(left < FADE and math.max(left / FADE, 0) or 1)
    end
end

local function Tick()
    local now = GetTime()
    for i = #active, 1, -1 do
        if now - active[i].start >= LIFE then
            local line = table.remove(active, i)
            line.fs:Hide()
            pool[#pool + 1] = line
        end
    end
    if #active == 0 then holder:SetScript("OnUpdate", nil) end
    Layout()
end

local function Show(name, rank)
    if not holder then return end
    local maxRank = MaxRank(name)
    local line = table.remove(pool)
    if not line then
        local fs = holder:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")
        line = { fs = fs }
    end
    local g = T.accent
    local name_ = string.format("|cff%02x%02x%02x%s|r", g[1] * 255, g[2] * 255, g[3] * 255, name)
    line.fs:SetText(maxRank and string.format("%s  %d / %d", name_, rank, maxRank) or string.format("%s  %d", name_, rank))
    line.start = GetTime()
    line.fs:Show()
    active[#active + 1] = line
    while #active > LINES do
        local old = table.remove(active, 1)
        old.fs:Hide()
        pool[#pool + 1] = old
    end
    holder:SetScript("OnUpdate", Tick)
    Layout()
end

local function OnSkill(msg)
    if CysUICompat and CysUICompat.Secret and CysUICompat.Secret(msg) then return end
    if type(msg) ~= "string" then return end
    PATTERN = PATTERN or MessagePattern()
    local name, rank = msg:match(PATTERN)
    rank = tonumber(rank)
    if name and rank then Show(name, rank) end
end

local function Enable()
    if holder then return end
    holder = CreateFrame("Frame", "CysUISkillUps", UIParent)
    holder:SetSize(260, 60)
    holder:SetFrameStrata("MEDIUM")
    -- default spot: just above Cys's player frame (worked out once the unit frames have their place)
    C_Timer.After(0.5, function()
        local x, y = -230, -170
        local pm = CUI.movers and CUI.movers.player and CUI.movers.player.mover
        local cx, top = pm and pm:GetCenter(), pm and pm:GetTop()
        local ux, uy = UIParent:GetCenter()
        if cx and top and ux then
            x = math.floor(cx - ux + 0.5)
            y = math.floor(top - uy + 40 + 0.5)
        end
        CUI:RegisterMovable(holder, "skillups", "Skill-ups", { point = "CENTER", x = x, y = y })
    end)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("CHAT_MSG_SKILL")
    ev:SetScript("OnEvent", function(_, _, msg) pcall(OnSkill, msg) end)
end

CUI.SkillUps = { Test = function() Show("Axes", 13) end }

CUI:RegisterModule({
    key = "skills", -- the old Skill Tracker's switch, so it stays on for anyone who had it on
    name = "Skills",
    addon = "CysUI",
    desc = "When a weapon skill, Defense or profession goes up, a short line like \"Axes 13 / 85\" floats up above your player frame and fades. Move it in layout mode.",
    onEnable = Enable,
})
