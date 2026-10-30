--------------------------------------------------------------------------------
-- Cys's UI - Totem Bar settings page (listed under Class > Shaman)
-- The bar itself is in CysTotems.lua and is mostly run from its right-click menus; this page holds the
-- switches and explains the clicks. It is listed for every class so the Class section shows what Shamans have.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T
local _, myClass = UnitClass("player")

CUI:RegisterPage("Totem Bar", function(page)
    local width = 480
    W.Header(page, "Totem bar", width):SetPoint("TOPLEFT", 0, -4)

    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34)
    intro:SetWidth(width - 8)
    intro:SetJustifyV("TOP")
    intro:SetSpacing(3)
    if myClass ~= "SHAMAN" then
        intro:SetText("Shaman only: a bar with a button for each totem element. There is nothing to set on your class; log in on a Shaman to see the options.")
        page.contentHeight = 120
        return
    end
    intro:SetText("A bar with one button per totem element, Drop All and a weapon-imbue button. Switch it off under Modules; move it with the button below or /cui layout.")

    local db = CysTotemsDB or {}
    local y = -92
    local function Check(label, key)
        local c = W.Checkbox(page, label, function() return db[key] end, function(on) db[key] = on and true or false end)
        c:SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    Check("Warn before a totem runs out", "alertExpiring")
    Check("Tell me when a totem is gone", "alertGone")

    y = y - 8
    local move = W.Button(page, 240, 22, "Move the bar (layout mode)")
    move:SetPoint("TOPLEFT", 4, y)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)
    y = y - 40

    W.Notes(page, 4, y, width, "", {
        { "Left-click", "a totem button drops the totem you picked for that element." },
        { "Right-click", "a totem button to pick a different totem (only totems you know are listed)." },
        { "Drop All", "drops your four picks in order, one per press. Right-click it for loadouts and options, including keeping action-bar macros in step with your picks." },
        { "/cystotems", "load <name> switches to a saved loadout and works in a macro." },
    })
end, nil, "SHAMAN")
