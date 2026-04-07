-- CCTracker_Options.lua
-- Registers a panel under ESC → Interface → AddOns.
-- Panel creation is deferred to ADDON_LOADED so that Blizzard's
-- InterfaceOptions system is fully initialised before we register.

local TRACK_TYPES = {
    { key = "arena_rated",    label = "Rated Arena",    desc = "2v2 / 3v3 / 5v5 rated arenas" },
    { key = "arena_skirmish", label = "Skirmish Arena", desc = "Unranked arena skirmishes" },
    { key = "pvp",            label = "Battleground",   desc = "Alterac Valley, WSG, AB, EotS, etc." },
    { key = "party",          label = "Dungeon",        desc = "5-man instances (normal & heroic)" },
    { key = "raid",           label = "Raid",           desc = "10 and 25-man raid instances" },
    { key = "world",          label = "Open World",     desc = "Any CC cast outside an instance" },
}

local function BuildOptionsPanel()
    local panel = CreateFrame("Frame", "CCTrackerOptionsPanel", UIParent)
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

    -- Thin separator line
    local sep = panel:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  16, -128)
    sep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -128)
    sep:SetTexture(0.4, 0.4, 0.4, 0.7)

    -- Checkboxes
    local checks = {}
    local CB_Y0   = -144
    local CB_STEP = 32

    for i, info in ipairs(TRACK_TYPES) do
        local y = CB_Y0 - (i - 1) * CB_STEP

        local cb = CreateFrame("CheckButton", "CCTrackerOpt_" .. info.key, panel, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
        cb.typeKey = info.key
        cb.Text:SetText(info.label .. "  |cff888888— " .. info.desc .. "|r")

        cb:SetScript("OnClick", function(self)
            if CCTrackerDB and CCTrackerDB.settings and CCTrackerDB.settings.track then
                CCTrackerDB.settings.track[self.typeKey] = self:GetChecked() and true or false
            end
        end)

        checks[#checks + 1] = cb
    end

    local function SyncCheckboxes()
        local track = CCTrackerDB and CCTrackerDB.settings and CCTrackerDB.settings.track
        for _, cb in ipairs(checks) do
            local enabled = (not track) or (track[cb.typeKey] ~= false)
            cb:SetChecked(enabled)
        end
    end

    -- Called by InterfaceOptions_AddCategory API when panel becomes visible
    panel.refresh = SyncCheckboxes
    -- Called by the modern Settings API (RegisterCanvasLayoutCategory)
    panel:SetScript("OnShow", SyncCheckboxes)

    if _G.Settings and _G.Settings.RegisterCanvasLayoutCategory then
        local category = _G.Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        if category then
            category.ID = panel.name
            _G.Settings.RegisterAddOnCategory(category)
        end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

-- Defer registration until our addon has fully loaded
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "CCTracker" then
        self:UnregisterEvent("ADDON_LOADED")
        BuildOptionsPanel()
    end
end)
