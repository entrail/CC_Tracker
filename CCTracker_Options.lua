-- CCTracker_Options.lua
-- Registers a panel in ESC → Interface → AddOns so session tracking
-- preferences survive across sessions and are easily accessible.

-- Session types the player can toggle tracking for.
-- Keys must match the sessionType values used in CCTracker_Session.lua.
local TRACK_TYPES = {
    { key = "arena_rated",    label = "Rated Arena",    desc = "2v2 / 3v3 / 5v5 rated arenas" },
    { key = "arena_skirmish", label = "Skirmish Arena", desc = "Unranked arena skirmishes" },
    { key = "pvp",            label = "Battleground",   desc = "Alterac Valley, WSG, AB, EotS, etc." },
    { key = "party",          label = "Dungeon",        desc = "5-man instances (normal & heroic)" },
    { key = "raid",           label = "Raid",           desc = "10 and 25-man raid instances" },
    { key = "world",          label = "Open World",     desc = "Any CC cast outside an instance" },
}

-- ─── Build the options panel ─────────────────────────────────────────────────

local panel = CreateFrame("Frame", "CCTrackerOptionsPanel")
panel.name = "CCTracker"

-- Title
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
title:SetText("CCTracker")

-- Subtitle
local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -46)
subtitle:SetText("Crowd control spell tracking for PvP and PvE sessions.")
subtitle:SetTextColor(0.8, 0.8, 0.8)

-- Section header
local sectionLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
sectionLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -76)
sectionLabel:SetText("Session Recording")
sectionLabel:SetTextColor(1, 0.82, 0)

-- Section description
local sectionDesc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
sectionDesc:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -96)
sectionDesc:SetText("Uncheck a type to stop recording future sessions of that kind.\nExisting sessions are never deleted.")
sectionDesc:SetTextColor(0.75, 0.75, 0.75)

-- Thin separator line under the description
local sep = panel:CreateTexture(nil, "ARTWORK")
sep:SetHeight(1)
sep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  16, -128)
sep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -128)
sep:SetTexture(0.4, 0.4, 0.4, 0.7)

-- Checkboxes — one per session type
local checks = {}
local CB_Y0   = -144   -- y of first checkbox (from panel top)
local CB_STEP = 32     -- pixels between checkbox rows

for i, info in ipairs(TRACK_TYPES) do
    local y = CB_Y0 - (i - 1) * CB_STEP

    -- Plain CheckButton (UICheckButtonTemplate gives the standard WoW tick-box graphic)
    local cb = CreateFrame("CheckButton", "CCTrackerOpt_" .. info.key, panel, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    cb.typeKey = info.key

    -- Label to the right of the checkbox
    local lbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    lbl:SetText(info.label)

    -- Short description further to the right
    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    desc:SetText("— " .. info.desc)
    desc:SetTextColor(0.55, 0.55, 0.55)

    -- Write to SavedVariables on click
    cb:SetScript("OnClick", function(self)
        if CCTrackerDB and CCTrackerDB.settings and CCTrackerDB.settings.track then
            CCTrackerDB.settings.track[self.typeKey] = self:GetChecked() and true or false
        end
    end)

    checks[#checks + 1] = cb
end

-- refresh(): called by the InterfaceOptions system each time the panel is shown.
-- Reads the current SavedVariables so the checkboxes always reflect live state.
panel.refresh = function()
    local track = CCTrackerDB and CCTrackerDB.settings and CCTrackerDB.settings.track
    for _, cb in ipairs(checks) do
        -- Default to true if the key is absent (first-time or upgrade)
        local enabled = (not track) or (track[cb.typeKey] ~= false)
        cb:SetChecked(enabled)
    end
end

-- Register with the Interface Options panel
InterfaceOptions_AddCategory(panel)
