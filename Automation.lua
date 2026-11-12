--------------------------------------------------------------------------------
-- Cys's UI - Automation
--
-- Small time-savers, each with its own switch and all OFF until you tick them:
--   * Fast loot              - with auto-loot on, every item is taken at once (no loot window flicker)
--   * Auto quests            - accepts quests, turns in finished ones, and picks the reward when there
--                              is only one. Hold Shift while talking to an NPC to do it by hand.
--   * Auto release in BGs    - releases your spirit when you die in a battleground
--   * Ding                   - says "Ding! Level 23" in the chat you choose when you level up
--   * Decline duels          - turns down duel requests (friends and guildmates still get the normal popup)
--   * Decline guild charters - closes guild charter signing requests (hold Shift when it opens to read it)
--   * Cursor ring            - a gold ring around the mouse cursor while you are in combat
--   * Group level check      - in a dungeon, a box lists anyone in your group below its level range
-- Settings: /cui -> Automation.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local DEFAULTS = {
    fastLoot = false,
    autoQuest = false,
    autoRelease = false,
    ding = false,
    dingChannel = "party",  -- party (falls back to guild, then nothing) / guild / say / self
    dingText = "Ding! Level %d",
    declineDuels = false,
    declineCharters = false,
    cursorRing = false,
    groupCheck = false,
    autoDelete = true,       -- type DELETE into the "destroy a good item" box
    autoBags = true,         -- open Cys's Bags at a vendor / bank / mailbox / Auction House, close them after
    hideEmptyBagCats = true, -- Cys's Bags sidebar leaves out empty categories
    bagsAutoSize = true,     -- Cys's Bags grows to fit its items (no scrolling)
    bagsMaxH = 650,          -- ...but no taller than this; more items scroll
    acceptInvites = false,   -- accept group invites from friends and guildmates
    questAnnounce = false,   -- tell the party when one of your quests is ready to turn in
    bagSplit = true,         -- Cys's Bags: own split box on Shift-click (type a number, split to a free slot)
    bagRecent = true,        -- Cys's Bags: New Items section (what came in since you last closed the bags)
    bagPin = true,           -- Cys's Bags: Alt-click pins / unpins an item
    bagPlusSlots = true,     -- Cys's Bags: a "+" drop slot at the end of each category
    trainAll = true,         -- a Train all button on trainer windows (nothing is bought until you click it)
    openContainers = true,   -- open clams, sacks and other openable bag items (Classic Era)
    autoResurrect = false,   -- accept a resurrection, unless the caster is still in a fight
    skipCinematics = false,  -- skip in-game cinematics (hold Shift to watch)
    hideErrors = false,      -- hide the red error spam ("Not enough rage", "Out of range"...)
}

local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.automation = CysUIDB.automation or {}
    local db = CysUIDB.automation
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

--------------------------------------------------------------------------------
-- Fast loot
--------------------------------------------------------------------------------
local lastLoot = 0
local function FastLoot()
    if not DB().fastLoot then return end
    -- auto-loot on (and the auto-loot key not held), same rule the game uses
    local auto = GetCVarBool and GetCVarBool("autoLootDefault")
    if IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") then auto = not auto end
    if not auto then return end
    local now = GetTime()
    if now - lastLoot < 0.3 then return end
    lastLoot = now
    for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
end

--------------------------------------------------------------------------------
-- Auto quests (hold Shift to pause)
--------------------------------------------------------------------------------
local function QuestsOn()
    return DB().autoQuest and not IsShiftKeyDown()
end

local function OnGossip()
    if not QuestsOn() then return end
    local G = C_GossipInfo
    if G and G.GetActiveQuests then
        for _, q in ipairs(G.GetActiveQuests() or {}) do
            if q.isComplete and q.questID then G.SelectActiveQuest(q.questID) return end
        end
        for _, q in ipairs(G.GetAvailableQuests() or {}) do
            if q.questID then G.SelectAvailableQuest(q.questID) return end
        end
    end
end

local function OnGreeting() -- NPCs with the old quest list window instead of gossip
    if not QuestsOn() then return end
    for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
        local _, complete = GetActiveTitle(i)
        if complete then SelectActiveQuest(i) return end
    end
    if (GetNumAvailableQuests and GetNumAvailableQuests() or 0) > 0 then SelectAvailableQuest(1) end
end

local function OnQuestEvent(event)
    if not QuestsOn() then return end
    if event == "QUEST_DETAIL" then
        AcceptQuest()
    elseif event == "QUEST_ACCEPT_CONFIRM" then -- a group member started an escort quest
        if ConfirmAcceptQuest then ConfirmAcceptQuest() end
    elseif event == "QUEST_PROGRESS" then
        -- never hand over gold automatically
        if IsQuestCompletable() and (GetQuestMoneyToGet and GetQuestMoneyToGet() or 0) == 0 then CompleteQuest() end
    elseif event == "QUEST_COMPLETE" then
        local n = GetNumQuestChoices() or 0
        if n <= 1 then GetQuestReward(n) end -- several rewards: you pick (Cys's coin marks the best seller)
    elseif event == "GOSSIP_SHOW" then
        OnGossip()
    elseif event == "QUEST_GREETING" then
        OnGreeting()
    end
end

--------------------------------------------------------------------------------
-- Auto release in battlegrounds
--------------------------------------------------------------------------------
local function OnDeath()
    if not DB().autoRelease then return end
    local _, kind = IsInInstance()
    if kind ~= "pvp" then return end
    if HasSoulstone and HasSoulstone() then return end -- soulstone / Reincarnation: let the player choose
    C_Timer.After(0.5, function()
        if UnitIsDeadOrGhost("player") and not UnitIsGhost("player") then RepopMe() end
    end)
end

--------------------------------------------------------------------------------
-- Ding
--------------------------------------------------------------------------------
local DING_CHANNELS = {
    { "party", "Party (guild if you're solo)" },
    { "guild", "Guild" },
    { "say",   "Say" },
    { "self",  "Only show it to me" },
}

local function SayDing(level)
    local db = DB()
    if not db.ding then return end
    local ok, text = pcall(string.format, db.dingText or DEFAULTS.dingText, level)
    if not ok then text = string.format(DEFAULTS.dingText, level) end
    local ch = db.dingChannel
    if ch == "party" then
        if IsInRaid and IsInRaid() then ch = "RAID"
        elseif IsInGroup and IsInGroup() then ch = "PARTY"
        elseif IsInGuild and IsInGuild() then ch = "GUILD"
        else ch = nil end
    elseif ch == "guild" then ch = (IsInGuild and IsInGuild()) and "GUILD" or nil
    elseif ch == "say" then ch = "SAY"
    else ch = nil end
    if ch then pcall(SendChatMessage, text, ch) else CUI:Print(text) end
end

--------------------------------------------------------------------------------
-- Declining duels and guild charters
--------------------------------------------------------------------------------
local function IsFriendOrGuild(name)
    if not name then return false end
    local short = Ambiguate and Ambiguate(name, "none") or name
    local C = C_FriendList
    if C and C.GetFriendInfo and C.GetFriendInfo(short) then return true end
    if IsInGuild and IsInGuild() and GetNumGuildMembers then
        for i = 1, GetNumGuildMembers() do
            local n = GetGuildRosterInfo(i)
            if n and (Ambiguate and Ambiguate(n, "none") or n) == short then return true end
        end
    end
    return false
end

local function OnDuel(who)
    if not DB().declineDuels or IsFriendOrGuild(who) then return end
    CancelDuel()
    if StaticPopup_Hide then StaticPopup_Hide("DUEL_REQUESTED") end
    CUI:Print("Declined a duel from " .. (who or "someone") .. ".")
end

local function OnCharter()
    if not DB().declineCharters or IsShiftKeyDown() then return end
    -- only charters someone is asking you to sign, not one you are handing out
    if CanSignPetition and not CanSignPetition() then return end
    ClosePetition()
    CUI:Print("Closed a guild charter signing request (hold Shift next time to read it).")
end

--------------------------------------------------------------------------------
-- Cursor ring (combat only)
--------------------------------------------------------------------------------
local ring
local function RingUpdate(self)
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
end
local function RingShow(on)
    if on and not DB().cursorRing then on = false end
    if on and not ring then
        ring = CreateFrame("Frame", nil, UIParent)
        ring:SetSize(34, 34)
        ring:SetFrameStrata("TOOLTIP")
        ring.tex = ring:CreateTexture(nil, "OVERLAY")
        ring.tex:SetAllPoints()
        ring.tex:SetTexture("Interface\\AddOns\\CysUI\\Media\\Ring")
        ring:EnableMouse(false)
        ring:SetScript("OnUpdate", RingUpdate)
    end
    if ring and on then ring.tex:SetVertexColor(T.brand[1], T.brand[2], T.brand[3], 0.85) end -- follows the Border color
    if ring then ring:SetShown(on and true or false) end
end

--------------------------------------------------------------------------------
-- Group level check: who is under the dungeon's level range
--------------------------------------------------------------------------------
-- [instance ID] = { lowest recommended level, highest }
local DUNGEONS = {
    [389] = { 13, 18 }, [43] = { 17, 24 }, [36] = { 17, 26 }, [33] = { 22, 30 }, [48] = { 24, 32 },
    [34] = { 24, 32 }, [90] = { 29, 38 }, [47] = { 29, 38 }, [189] = { 28, 45 }, [129] = { 37, 46 },
    [70] = { 41, 51 }, [209] = { 42, 54 }, [349] = { 46, 55 }, [109] = { 50, 56 }, [230] = { 52, 60 },
    [229] = { 55, 60 }, [429] = { 55, 60 }, [289] = { 58, 60 }, [329] = { 58, 60 },
    [409] = { 60, 60 }, [469] = { 60, 60 }, [249] = { 60, 60 }, [309] = { 60, 60 }, [509] = { 60, 60 },
    [531] = { 60, 60 }, [533] = { 60, 60 },
}

local check, checkText
local function BuildCheck()
    if check then return end
    check = CreateFrame("Frame", "CysUIGroupCheck", UIParent)
    check:SetSize(300, 60)
    check:SetFrameStrata("MEDIUM")
    W.Texture(check, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.92 }):SetAllPoints()
    W.Border(check, 1, T.border, "BORDER")
    local title = W.Text(check, 12, T.accent)
    title:SetPoint("TOPLEFT", 10, -8)
    check.title = title
    checkText = W.Text(check, 12, T.text)
    checkText:SetPoint("TOPLEFT", 10, -28)
    checkText:SetJustifyV("TOP")
    checkText:SetSpacing(2)
    local x = CreateFrame("Button", nil, check)
    x:SetSize(18, 18)
    x:SetPoint("TOPRIGHT", -4, -4)
    x.t = W.Text(x, 12, { 1, 1, 1 }, "CENTER")
    x.t:SetPoint("CENTER")
    x.t:SetText("X")
    x:SetScript("OnClick", function() check:Hide(); check.dismissed = true end)
    check:Hide()
    CUI:RegisterMovable(check, "groupcheck", "Group level check", { point = "TOP", x = 0, y = -220 })
end

-- While your group is listed in the Looking For Group panel: the listed dungeons' suggested levels
-- (the lowest of them when several are listed), so a too-low member shows before anyone travels.
local function ListedRange()
    local L = C_LFGList
    if not (L and L.HasActiveEntryInfo and L.HasActiveEntryInfo() and L.GetActiveEntryInfo) then return nil end
    local ok, entry = pcall(L.GetActiveEntryInfo)
    if not ok or not entry then return nil end
    local ids = entry.activityIDs or (entry.activityID and { entry.activityID }) or {}
    local lo, hi, names = nil, nil, {}
    for _, aid in ipairs(ids) do
        local ok2, a = pcall(L.GetActivityInfoTable, aid)
        if ok2 and a then
            local mn = (a.minLevelSuggestion and a.minLevelSuggestion > 0 and a.minLevelSuggestion) or a.minLevel or 0
            local mx = (a.maxLevelSuggestion and a.maxLevelSuggestion > 0 and a.maxLevelSuggestion) or a.maxLevel or 0
            if mn > 0 and (not lo or mn < lo) then lo, hi = mn, mx end
            names[#names + 1] = a.shortName or a.fullName
        end
    end
    if not lo then return nil end
    return { lo, (hi and hi > 0) and hi or lo }, (#names == 1 and names[1]) or (#names .. " listed dungeons")
end

local function GroupCheck()
    if not DB().groupCheck then if check then check:Hide() end return end
    local zone, kind, _, _, _, _, _, id = GetInstanceInfo()
    local range = (kind == "party" or kind == "raid") and DUNGEONS[id]
    if not range then
        local listed, label = ListedRange()
        if listed then range, zone = listed, label end
    end
    if not range or not (IsInGroup and IsInGroup()) then
        if check then check:Hide(); check.dismissed = nil end
        return
    end
    BuildCheck()
    if check.dismissed then return end
    local under = {}
    local function Look(unit)
        if not UnitExists(unit) then return end
        local lvl = UnitLevel(unit) or 0
        if lvl > 0 and lvl < range[1] then
            local _, cls = UnitClass(unit)
            local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
            local name = UnitName(unit) or "?"
            if c then name = string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name) end
            under[#under + 1] = name .. "  |cFFFF9F43level " .. lvl .. "|r"
        end
    end
    Look("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do if not UnitIsUnit("raid" .. i, "player") then Look("raid" .. i) end end
    else
        for i = 1, 4 do Look("party" .. i) end
    end
    if #under == 0 then check:Hide() return end
    check.title:SetText(string.format("Below %s's level range (%d-%d)", zone or "this dungeon", range[1], range[2]))
    checkText:SetText(table.concat(under, "\n"))
    check:SetWidth(math.max(260, check.title:GetStringWidth() + 46))
    check:SetHeight(36 + checkText:GetStringHeight() + 8)
    check:Show()
end

--------------------------------------------------------------------------------
-- Delete confirmation: the DELETE word typed in for you (classic and Forever popups)
--------------------------------------------------------------------------------
local DELETE_POPUPS = { DELETE_GOOD_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }
local function FillDelete(which)
    if not DB().autoDelete or not DELETE_POPUPS[which] or not DELETE_ITEM_CONFIRM_STRING then return end
    local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible(which)
    if not dialog then return end
    local eb = dialog.editBox or dialog.EditBox or (dialog.GetEditBox and dialog:GetEditBox())
    if eb and eb.SetText then eb:SetText(DELETE_ITEM_CONFIRM_STRING) end
end

--------------------------------------------------------------------------------
-- Bags open at a vendor, bank, mailbox or Auction House (and close again only if we opened them)
--------------------------------------------------------------------------------
local OPEN_EVENTS  = { MERCHANT_SHOW = true, BANKFRAME_OPENED = true, MAIL_SHOW = true, AUCTION_HOUSE_SHOW = true }
local CLOSE_EVENTS = { MERCHANT_CLOSED = true, BANKFRAME_CLOSED = true, MAIL_CLOSED = true, AUCTION_HOUSE_CLOSED = true }
local bagsOpenedByUs
local function AutoBags(open)
    local bags = _G.CysBags
    if not (DB().autoBags and bags and bags.IsShown and bags.Open) then return end
    if open then
        if not bags:IsShown() then bags:Open(); bagsOpenedByUs = true end
    else
        if bagsOpenedByUs and bags:IsShown() then bags:Close() end
        bagsOpenedByUs = nil
    end
end

--------------------------------------------------------------------------------
-- Openable bag items (clams, sacks, unlocked boxes) are opened one at a time, out of combat, when nothing
-- else is going on. Each item is tried once per session, so a locked box doesn't keep failing.
-- Classic Era only for now (WoW Forever may block opening items from addon code).
--------------------------------------------------------------------------------
local tried, busy = {}, false
local function OpenOne()
    if not DB().openContainers or (CysUICompat and CysUICompat.isForever) then return end
    if busy or InCombatLockdown() or UnitIsDeadOrGhost("player") then return end
    if (LootFrame and LootFrame:IsShown()) or (MerchantFrame and MerchantFrame:IsShown())
        or (BankFrame and BankFrame:IsShown()) or (MailFrame and MailFrame:IsShown()) or CursorHasItem() then return end
    if not (C_Container and C_Container.GetContainerItemInfo and C_Container.UseContainerItem) then return end
    for bag = 0, 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hasLoot and not info.isLocked and info.hyperlink and not tried[info.hyperlink .. bag .. slot] then
                tried[info.hyperlink .. bag .. slot] = true
                busy = true
                C_Timer.After(1, function() busy = false end)
                C_Container.UseContainerItem(bag, slot)
                return
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Group invites from friends and guildmates are accepted (hold Shift to see the popup instead)
--------------------------------------------------------------------------------
local function Plain(name) return name and (name:gsub("%-.*$", "")) end
local function IsFriendOrGuild(name)
    name = Plain(name)
    if not name then return false end
    if C_FriendList and C_FriendList.GetNumFriends then
        for i = 1, C_FriendList.GetNumFriends() or 0 do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and Plain(info.name) == name then return true end
        end
    end
    if IsInGuild() and GetNumGuildMembers then
        for i = 1, GetNumGuildMembers() or 0 do
            local n = GetGuildRosterInfo(i)
            if Plain(n) == name then return true end
        end
    end
    return false
end
local function OnInvite(name)
    if not DB().acceptInvites or IsShiftKeyDown() then return end
    if CysUICompat and CysUICompat.Secret and CysUICompat.Secret(name) then return end
    if IsFriendOrGuild(name) then
        AcceptGroup()
        if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
-- Quest announce: when the last objective of a quest is done while you are in a party (not a raid), say so in
-- party chat. Only a quest seen unfinished first is announced, so nothing fires at login or for a quest picked up
-- already complete. A line that comes up mid-fight is held until the fight ends.
--------------------------------------------------------------------------------
local questDone, questSeeded, questQueued = {}, false, false
local questLines = {}
local function FlushQuestLines()
    if InCombatLockdown() then return end
    for i = 1, #questLines do
        if IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) then pcall(SendChatMessage, questLines[i], "PARTY") end
        questLines[i] = nil
    end
end
local function ScanQuests()
    questQueued = false
    local Q = C_QuestLog
    if not (Q and Q.GetNumQuestLogEntries and Q.GetInfo and Q.IsComplete and Q.GetNumQuestObjectives) then return end
    local now = {}
    for i = 1, (Q.GetNumQuestLogEntries() or 0) do
        local info = Q.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local goals = Q.GetNumQuestObjectives(info.questID)
            -- a plain delivery quest counts as complete from the start; only quests with objectives are watched
            local done = type(goals) == "number" and goals > 0 and Q.IsComplete(info.questID) and true or false
            now[info.questID] = done
            if done and questSeeded and questDone[info.questID] == false and DB().questAnnounce
                and type(info.title) == "string" then
                questLines[#questLines + 1] = "Quest complete: " .. info.title
            end
        end
    end
    questDone, questSeeded = now, true
    FlushQuestLines()
end
local function QueueQuestScan()
    if questQueued then return end
    questQueued = true
    C_Timer.After(0.5, function() pcall(ScanQuests); questQueued = false end)
end

--------------------------------------------------------------------------------
-- Train all: a button on the trainer window that learns everything you can learn and afford right now, one
-- after another. Point at it for the count and the total cost. Nothing is bought until you click.
--------------------------------------------------------------------------------
local trainBtn, training
-- the list differs between clients (name, rank, category... or name, category...): look for the word itself
local function TrainerAvailable(i)
    local _, b, c = GetTrainerServiceInfo(i)
    return b == "available" or c == "available"
end
-- how many can be learned now, what they cost together, and the first one you can pay for
local function TrainerTally()
    local n, total, first = 0, 0, nil
    local money = GetMoney() or 0
    for i = 1, (GetNumTrainerServices and GetNumTrainerServices() or 0) do
        if TrainerAvailable(i) then
            local cost = GetTrainerServiceCost(i) or 0
            n, total = n + 1, total + cost
            if not first and cost <= money then first = i end
        end
    end
    return n, total, first
end
local function TrainStep()
    if not training then return end
    local _, _, first = TrainerTally()
    if not first then training = false return end
    BuyTrainerService(first)
    -- the list refreshes after each purchase; carry on a moment later
    C_Timer.After(0.25, function() pcall(TrainStep) end)
end
local function TrainerButton()
    local host = _G.ClassTrainerFrame
    if not host then return end
    if not trainBtn then
        trainBtn = W.Button(host, 84, 22, "Train all")
        local anchor = _G.ClassTrainerTrainButton
        if anchor then trainBtn:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
        else trainBtn:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 16, 8) end
        trainBtn:SetFrameLevel((anchor and anchor:GetFrameLevel() or host:GetFrameLevel()) + 2)
        trainBtn:SetScript("OnClick", function()
            if training then training = false return end
            training = true
            pcall(TrainStep)
        end)
        trainBtn:HookScript("OnEnter", function(self)
            local n, total = TrainerTally()
            local money = GetMoney() or 0
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Train all", T.accent[1], T.accent[2], T.accent[3])
            if n == 0 then
                GameTooltip:AddLine("Nothing to learn here right now.", 1, 1, 1)
            else
                GameTooltip:AddDoubleLine(n == 1 and "1 to learn" or (n .. " to learn"), GetCoinTextureString(total), 1, 1, 1, 1, 1, 1)
                GameTooltip:AddDoubleLine("You have", GetCoinTextureString(money), 1, 1, 1, 1, 1, 1)
                if total > money then
                    GameTooltip:AddLine("Not enough for all of them: it learns what you can pay for, top of the list first.", 1, 0.5, 0.3, true)
                end
            end
            GameTooltip:Show()
        end)
        trainBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    trainBtn:SetShown(DB().trainAll ~= false)
end

--------------------------------------------------------------------------------
-- Accept resurrections (not while the caster is fighting)
--------------------------------------------------------------------------------
local function CasterInCombat(name)
    local short = name and Ambiguate(name, "none")
    if not short then return false end
    local prefix, n = "party", 4
    if IsInRaid() then prefix, n = "raid", 40 end
    for i = 1, n do
        local unit = prefix .. i
        if UnitExists(unit) and UnitName(unit) == short then
            local ok, fighting = pcall(UnitAffectingCombat, unit)
            if not ok or (CysUICompat and CysUICompat.Secret(fighting)) then return true end -- can't tell: ask
            return fighting and true or false
        end
    end
    return false
end

local function OnResurrect(name)
    if not DB().autoResurrect or CasterInCombat(name) then return end
    C_Timer.After(0.3, function()
        if UnitIsDeadOrGhost("player") and AcceptResurrect then
            pcall(AcceptResurrect)
            if StaticPopup_Hide then
                for _, which in ipairs({ "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }) do
                    pcall(StaticPopup_Hide, which)
                end
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Skip cinematics (hold Shift when it starts to watch it)
--------------------------------------------------------------------------------
local function OnCinematic()
    if not DB().skipCinematics or IsShiftKeyDown() then return end
    C_Timer.After(0.1, function()
        if CinematicFrame_CancelCinematic then pcall(CinematicFrame_CancelCinematic)
        elseif StopCinematic then pcall(StopCinematic) end
    end)
end

--------------------------------------------------------------------------------
-- Hide the red error spam. A few errors you need to see still show.
--------------------------------------------------------------------------------
local errFrame, errTaken = nil, false
local function KeepError(msg)
    for _, g in ipairs({ "ERR_INV_FULL", "ERR_BAG_FULL", "ERR_QUEST_LOG_FULL", "ERR_ITEM_MAX_COUNT",
                         "ERR_NOT_ENOUGH_MONEY", "ERR_LOOT_GONE", "ERR_TOO_MANY_CHAT_CHANNELS" }) do
        if _G[g] and msg == _G[g] then return true end
    end
    return false
end

function CUI.ApplyErrorFilter()
    local f = UIErrorsFrame
    if not f then return end
    if DB().hideErrors then
        if not errFrame then
            errFrame = CreateFrame("Frame")
            errFrame:SetScript("OnEvent", function(_, _, a1, a2)
                local msg = type(a2) == "string" and a2 or a1
                if type(msg) == "string" and KeepError(msg) then f:AddMessage(msg, 1, 0.1, 0.1, 1) end
            end)
        end
        if not errTaken then
            f:UnregisterEvent("UI_ERROR_MESSAGE")
            errFrame:RegisterEvent("UI_ERROR_MESSAGE")
            errTaken = true
        end
    elseif errTaken then
        errFrame:UnregisterEvent("UI_ERROR_MESSAGE")
        f:RegisterEvent("UI_ERROR_MESSAGE")
        errTaken = false
    end
end

--------------------------------------------------------------------------------
local frame
local function Enable()
    if frame then return end
    DB()
    frame = CreateFrame("Frame")
    for _, e in ipairs({ "LOOT_READY", "LOOT_OPENED", "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM", "QUEST_PROGRESS",
                         "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_GREETING", "PLAYER_DEAD", "PLAYER_LEVEL_UP",
                         "DUEL_REQUESTED", "PETITION_SHOW", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                         "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "UNIT_LEVEL", "LFG_LIST_ACTIVE_ENTRY_UPDATE",
                         "MERCHANT_SHOW", "MERCHANT_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "MAIL_SHOW",
                         "MAIL_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "PARTY_INVITE_REQUEST",
                         "BAG_UPDATE_DELAYED", "LOOT_CLOSED", "QUEST_LOG_UPDATE", "TRAINER_SHOW", "TRAINER_CLOSED",
                         "RESURRECT_REQUEST", "CINEMATIC_START" }) do
        pcall(frame.RegisterEvent, frame, e)
    end
    if StaticPopup_Show then
        hooksecurefunc("StaticPopup_Show", function(which)
            if DELETE_POPUPS[which] and C_Timer and C_Timer.After then
                C_Timer.After(0, function() pcall(FillDelete, which) end)
            end
        end)
    end
    pcall(CUI.ApplyErrorFilter)
    frame:SetScript("OnEvent", function(_, event, arg1)
        if event == "RESURRECT_REQUEST" then
            pcall(OnResurrect, arg1)
        elseif event == "CINEMATIC_START" then
            OnCinematic()
        elseif event == "PARTY_INVITE_REQUEST" then
            pcall(OnInvite, arg1)
        elseif event == "QUEST_LOG_UPDATE" then
            QueueQuestScan()
        elseif event == "TRAINER_SHOW" then
            training = false
            pcall(TrainerButton)
        elseif event == "TRAINER_CLOSED" then
            training = false
        elseif event == "BAG_UPDATE_DELAYED" or event == "LOOT_CLOSED" then
            C_Timer.After(0.3, function() pcall(OpenOne) end)
        elseif OPEN_EVENTS[event] or CLOSE_EVENTS[event] then
            AutoBags(OPEN_EVENTS[event])
        elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
            FastLoot()
        elseif event == "PLAYER_DEAD" then
            OnDeath()
        elseif event == "PLAYER_LEVEL_UP" then
            SayDing(arg1 or UnitLevel("player"))
            GroupCheck()
        elseif event == "DUEL_REQUESTED" then
            OnDuel(arg1)
        elseif event == "PETITION_SHOW" then
            OnCharter()
        elseif event == "PLAYER_REGEN_DISABLED" then
            RingShow(true)
        elseif event == "PLAYER_REGEN_ENABLED" then
            RingShow(false)
            pcall(FlushQuestLines)
        elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" or event == "UNIT_LEVEL"
            or event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
            C_Timer.After(1, GroupCheck)
        else
            OnQuestEvent(event)
        end
    end)
end

CUI:RegisterModule({
    key = "automation",
    name = "Automation",
    addon = "CysUI",
    desc = "Small time-savers, each switched on separately: fast loot, auto quests, auto release in battlegrounds, a Ding message, declining duels and guild charters, a combat cursor ring and a dungeon level check for your group.",
    onEnable = Enable,
    open = function() CUI:OpenConfig("Automation") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Automation", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Automation", width):SetPoint("TOPLEFT", 0, -4)

    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34)
    intro:SetWidth(width - 8)
    intro:SetJustifyV("TOP")
    intro:SetSpacing(3)
    intro:SetText("Tick what you want. Changes work straight away, no reload needed.")

    local y = -70
    local function Check(label, key)
        local c = W.Checkbox(page, label, function() return db[key] end, function(on) db[key] = on end)
        c:SetPoint("TOPLEFT", 4, y)
        y = y - 26
        return c
    end
    Check("Fast loot (takes everything at once when auto-loot is on)", "fastLoot")
    Check("Accept quests and turn in finished ones (hold Shift to pause)", "autoQuest")
    Check("Release your spirit automatically when you die in a battleground", "autoRelease")
    Check("Decline duels (friends and guildmates still get the popup)", "declineDuels")
    Check("Close guild charter signing requests (hold Shift to read one)", "declineCharters")
    Check("Gold ring around the mouse cursor while in combat", "cursorRing")
    Check("Show who in the group is below the dungeon's level range", "groupCheck")
    Check("Say Ding when you level up", "ding")
    Check("Type DELETE for you when you destroy a good item", "autoDelete")
    Check("Open Cys's Bags at a vendor, bank, mailbox or Auction House", "autoBags")
    local hideEmpty = Check("Cys's Bags: hide empty categories in the sidebar", "hideEmptyBagCats")
    hideEmpty:HookScript("OnClick", function() if _G.CysBags and CysBags.UpdateSidebar then pcall(CysBags.UpdateSidebar, CysBags) end end)
    Check("Accept group invites from friends and guildmates (Shift: ask)", "acceptInvites")
    Check("Tell your party when you finish a quest's objectives", "questAnnounce")
    if not (CysUICompat and CysUICompat.isForever) then
        Check("Open clams, sacks and other openable items (out of combat)", "openContainers")
    end
    Check("Cys's Bags: own split box on Shift-click (type the amount)", "bagSplit")
    local function BagsRefresh() if _G.CysBags and CysBags.IsShown and CysBags:IsShown() then CysBags.dirty = true; pcall(CysBags.Refresh, CysBags) end end
    Check("Cys's Bags: New Items section at the top", "bagRecent"):HookScript("OnClick", BagsRefresh)
    Check("Cys's Bags: Alt-click an item to pin or unpin it", "bagPin")
    Check("Cys's Bags: + drop slot at the end of each category", "bagPlusSlots"):HookScript("OnClick", BagsRefresh)
    Check("Train all button on trainer windows (cost on mouseover)", "trainAll")
    local fit = Check("Cys's Bags: grow to fit the items, so nothing scrolls", "bagsAutoSize")
    fit:HookScript("OnClick", function() if _G.CysBags and CysBags.Refresh and CysBags.IsShown and CysBags:IsShown() then CysBags.dirty = true; pcall(CysBags.Refresh, CysBags) end end)
    W.Stepper(page, "Cys's Bags: tallest height", function() return db.bagsMaxH end, function(v)
        db.bagsMaxH = v
        if _G.CysBags and CysBags.Refresh and CysBags.IsShown and CysBags:IsShown() then CysBags.dirty = true; pcall(CysBags.Refresh, CysBags) end
    end, 300, 1000, 25, " px"):SetPoint("TOPLEFT", 4, y)
    y = y - 28
    Check("Accept resurrections (not while the caster is still fighting)", "autoResurrect")
    Check("Skip cinematics (hold Shift when one starts to watch it)", "skipCinematics")
    Check("Hide red error messages (bag full and similar still show)", "hideErrors"):HookScript("OnClick", function() pcall(CUI.ApplyErrorFilter) end)

    local chLabel = W.Text(page, 12, T.accent)
    chLabel:SetPoint("TOPLEFT", 4, y - 8)
    chLabel:SetText("Where to say Ding")
    local dd = W.Dropdown(page, 260, DING_CHANNELS, function() return db.dingChannel end, function(v) db.dingChannel = v end)
    dd:SetPoint("TOPLEFT", 4, y - 28)

    local test = W.Button(page, 120, 22, "Show an example")
    test:SetPoint("LEFT", dd, "RIGHT", 10, 0)
    test:SetScript("OnClick", function()
        CUI:Print("Example: " .. string.format(DEFAULTS.dingText, (UnitLevel("player") or 1) + 1))
    end)

    W.Notes(page, 4, y - 72, width, "", {
        { "Auto quests", "never pays gold to finish a quest, and leaves the choice to you when a quest offers several rewards." },
        { "Auto release", "waits if you have a Soulstone or Reincarnation, so you can still use it." },
        { "Fast loot", "follows the game's auto-loot setting and the auto-loot key." },
        { "Resurrections", "are accepted a moment after the offer, unless the caster is still in combat; then the normal pop-up stays." },
        { "Bags height", "with grow to fit on, the bags grow with your items up to the tallest height, then scroll. Dragging the corner grip sets your own height instead." },
        { "Red errors", "hides messages like Not enough rage and Out of range. Bags full, quest log full and not enough money still show." },
        { "Level check", "works while your group is listed in Looking For Group (using the listed dungeon) and inside the dungeon. It shows when someone joins; close it with the X and move it in layout mode." },
    })
end)
