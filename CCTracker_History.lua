-- CCTracker_History.lua
-- History window: session list with type/date filters + per-session detail panel

CCTracker_History = {}

local WIN_W, WIN_H      = 780, 520
local LIST_W            = 260
local DETAIL_X          = LIST_W + 20
local DETAIL_W          = WIN_W - DETAIL_X - 14
local ENTRY_H           = 44

-- Filter state
-- filterTypes: multi-select table — true = include this type in the history list.
local filterTypes = {
    arena_rated    = true,
    arena_skirmish = true,
    pvp            = true,
    party          = true,
    raid           = true,
    world          = true,
}
local filterDate = "all"
local filterChar = "current"   -- "current" = my char only | "all" = all characters

-- Combined-stats mode: when true the detail panel shows aggregated data
-- for all currently-filtered sessions instead of a single session.
local showingCombined = false

-- Currently selected session index within the filtered list
local selectedIndex = nil
local filteredSessions = {}

-- Entry button pool
local entryButtons = {}

local C_TITLE   = { 1,    0.82, 0 }
local C_HEADER  = { 0.6,  0.6,  0.6 }
local C_TEXT    = { 0.9,  0.9,  0.9 }
local C_GOOD    = { 0.3,  1,    0.3 }
local C_BAD     = { 1,    0.4,  0.4 }
local C_WARN    = { 1,    0.7,  0.1 }
local C_NEUTRAL = { 0.65, 0.65, 0.65 }
local C_SEL     = { 0.2,  0.4,  0.7,  0.5 }
local C_OUT     = { 0.3,  0.6,  1   }   -- blue  — outgoing section labels
local C_IN      = { 1,    0.55, 0.1 }   -- orange — incoming section labels

local function SetBackdropSafe(f, cfg)
    if f.SetBackdrop then f:SetBackdrop(cfg) end
end

local function MakeFont(parent, size, justify, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontNormal")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size or 11, "OUTLINE")
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function MakeSeparator(parent, yOfs)
    local sep = parent:CreateTexture(nil, "BACKGROUND")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  parent, "TOPLEFT",  8,       yOfs)
    sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8,      yOfs)
    sep:SetTexture(0.4, 0.4, 0.4, 0.6)
    return sep
end

-- ─── Filter helpers ──────────────────────────────────────────────────────────

-- Ordered list of session types shown in the multi-select type dropdown.
local TYPE_ORDER = {
    { key = "arena_rated",    label = "Rated Arena" },
    { key = "arena_skirmish", label = "Skirmish Arena" },
    { key = "pvp",            label = "Battleground" },
    { key = "party",          label = "Dungeon" },
    { key = "raid",           label = "Raid" },
    { key = "world",          label = "Open World" },
}

-- Returns the short label shown on the type-filter dropdown button.
local function GetTypeSummary()
    local count = 0
    for _, t in ipairs(TYPE_ORDER) do
        if filterTypes[t.key] then count = count + 1 end
    end
    if count == #TYPE_ORDER then return "All Types" end
    if count == 0            then return "No Types"  end
    -- Build a short label from what's selected.
    local parts = {}
    if filterTypes.arena_rated and filterTypes.arena_skirmish then
        parts[#parts + 1] = "Arena"
    elseif filterTypes.arena_rated then
        parts[#parts + 1] = "Rated"
    elseif filterTypes.arena_skirmish then
        parts[#parts + 1] = "Skirmish"
    end
    if filterTypes.pvp   then parts[#parts + 1] = "BG"      end
    if filterTypes.party then parts[#parts + 1] = "Dungeon"  end
    if filterTypes.raid  then parts[#parts + 1] = "Raid"     end
    if filterTypes.world then parts[#parts + 1] = "World"    end
    return (#parts <= 2) and table.concat(parts, ", ") or (count .. " types")
end

-- Populated in BuildHistory() — referenced by preset-button closures.
local typeDropdown   = nil
local typeCheckboxes = {}

local function SaveFilterTypes()
    if CCTrackerDB and CCTrackerDB.settings then
        local hf = CCTrackerDB.settings.historyFilter or {}
        CCTrackerDB.settings.historyFilter = hf
        for k, v in pairs(filterTypes) do hf[k] = v end
    end
end

local function GetDateOptions()
    local today     = date("%Y-%m-%d")
    local yesterday = date("%Y-%m-%d", time() - 86400)
    local weekAgo   = date("%Y-%m-%d", time() - 7 * 86400)
    return {
        { key = "all",       label = "All Dates" },
        { key = today,       label = "Today" },
        { key = yesterday,   label = "Yesterday" },
        { key = "week",      label = "This Week",  weekAgo = weekAgo },
    }
end

local dateOptions    = {}
local dateCycleIndex = 1

local function CycleDateFilter(btn)
    dateOptions = GetDateOptions()
    dateCycleIndex = (dateCycleIndex % #dateOptions) + 1
    filterDate = dateOptions[dateCycleIndex].key
    btn:SetText(dateOptions[dateCycleIndex].label)
    selectedIndex = nil
    CCTracker_History:RebuildList()
end

local function SessionMatchesDate(session)
    if filterDate == "all" then return true end
    -- "week" pseudo-key
    if filterDate == "week" then
        local opts = GetDateOptions()
        for _, o in ipairs(opts) do
            if o.key == "week" then
                return session.date >= o.weekAgo
            end
        end
        return true
    end
    return session.date == filterDate
end

-- ─── Aggregation helper ──────────────────────────────────────────────────────

-- Combines spells/incoming tables from multiple sessions into single tables.
local function AggregateSessions(sessions)
    local spells   = {}
    local incoming = {}
    for _, session in ipairs(sessions) do
        for name, entry in pairs(session.spells or {}) do
            local agg = spells[name]
            if not agg then
                agg = { spellId = entry.spellId, hits = 0, misses = {}, wasted = {} }
                spells[name] = agg
            end
            if entry.spellId and entry.spellId > 0 then agg.spellId = entry.spellId end
            agg.hits = agg.hits + entry.hits
            for mt, c in pairs(entry.misses) do
                agg.misses[mt] = (agg.misses[mt] or 0) + c
            end
            for defName, c in pairs(entry.wasted) do
                agg.wasted[defName] = (agg.wasted[defName] or 0) + c
            end
        end
        for name, entry in pairs(session.incoming or {}) do
            local agg = incoming[name]
            if not agg then
                agg = { spellId = entry.spellId, received = 0, avoided = {} }
                incoming[name] = agg
            end
            if entry.spellId and entry.spellId > 0 then agg.spellId = entry.spellId end
            agg.received = agg.received + entry.received
            for mt, c in pairs(entry.avoided) do
                agg.avoided[mt] = (agg.avoided[mt] or 0) + c
            end
        end
    end
    return spells, incoming
end

-- ─── Detail panel rendering ──────────────────────────────────────────────────

local detailPanel   -- set during Build()
local detailRows    = {}

local function ClearDetailPanel()
    for _, f in ipairs(detailRows) do f:Hide() end
    detailRows = {}
end

local function AddDetailRow(parent, yOfs, leftText, rightText, lr, lg, lb, rr, rg, rb)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(18)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  8,        yOfs)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8,       yOfs)

    local lbl = MakeFont(row, 11, "LEFT")
    lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
    lbl:SetWidth(DETAIL_W * 0.55)
    lbl:SetText(leftText or "")
    lbl:SetTextColor(lr or C_TEXT[1], lg or C_TEXT[2], lb or C_TEXT[3])

    local val = MakeFont(row, 11, "RIGHT")
    val:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    val:SetWidth(DETAIL_W * 0.44)
    val:SetText(rightText or "")
    val:SetTextColor(rr or C_TEXT[1], rg or C_TEXT[2], rb or C_TEXT[3])

    row:Show()
    detailRows[#detailRows + 1] = row
    return row
end

local function AddDetailLine(parent, yOfs, text, r, g, b)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(18)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  8,  yOfs)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, yOfs)

    local lbl = MakeFont(row, 11, "LEFT")
    lbl:SetAllPoints()
    lbl:SetText(text or "")
    lbl:SetTextColor(r or C_TEXT[1], g or C_TEXT[2], b or C_TEXT[3])

    row:Show()
    detailRows[#detailRows + 1] = row
    return row
end

local function AddDetailSeparator(parent, yOfs)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(6)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  4,  yOfs)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, yOfs)
    local sep = row:CreateTexture(nil, "BACKGROUND")
    sep:SetHeight(1)
    sep:SetAllPoints()
    sep:SetTexture(0.35, 0.35, 0.35, 0.7)
    row:Show()
    detailRows[#detailRows + 1] = row
    return row
end

local SPELL_ROW_H = 20
local SPELL_ICON  = 16

local function AddSpellRow(parent, yOfs, spellId, name, rightText, lr, lg, lb, rr, rg, rb)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(SPELL_ROW_H)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  8,  yOfs)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, yOfs)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(SPELL_ICON, SPELL_ICON)
    icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture((spellId and spellId > 0 and GetSpellTexture(spellId))
        or "Interface\\Icons\\INV_Misc_QuestionMark")

    local lbl = MakeFont(row, 11, "LEFT")
    lbl:SetPoint("LEFT", row, "LEFT", SPELL_ICON + 4, 0)
    lbl:SetWidth(DETAIL_W * 0.55 - SPELL_ICON - 4)
    lbl:SetText(name or "")
    lbl:SetTextColor(lr or C_TEXT[1], lg or C_TEXT[2], lb or C_TEXT[3])

    local val = MakeFont(row, 11, "RIGHT")
    val:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    val:SetWidth(DETAIL_W * 0.44)
    val:SetText(rightText or "")
    val:SetTextColor(rr or C_TEXT[1], rg or C_TEXT[2], rb or C_TEXT[3])

    row:Show()
    detailRows[#detailRows + 1] = row
    return row
end

local function RenderDetail(session)
    ClearDetailPanel()
    if not session then
        AddDetailLine(detailPanel, -10, "Select a session from the list.", C_NEUTRAL[1], C_NEUTRAL[2], C_NEUTRAL[3])
        return
    end

    local yOfs = -6

    if session._isCombined then
        -- ── Combined-stats header ─────────────────────────────────────────────
        AddDetailLine(detailPanel, yOfs,
            string.format("Combined Statistics  (%d sessions)", session._sessionCount),
            C_TITLE[1], C_TITLE[2], C_TITLE[3])
        yOfs = yOfs - 18
        if session._filterDesc and session._filterDesc ~= "" then
            AddDetailLine(detailPanel, yOfs, session._filterDesc, C_NEUTRAL[1], C_NEUTRAL[2], C_NEUTRAL[3])
            yOfs = yOfs - 16
        end
    else
        -- ── Single-session header ─────────────────────────────────────────────
        local typeName = CCTracker_SessionTypeNames[session.type] or session.type
        local duration = session.endTime and CCTracker:FormatDuration(session.endTime - session.startTime) or "In progress"

        AddDetailLine(detailPanel, yOfs,
            string.format("%s  —  %s", typeName, session.name),
            C_TITLE[1], C_TITLE[2], C_TITLE[3])
        yOfs = yOfs - 18

        -- Start / end / duration
        local startStr   = date("%Y-%m-%d %H:%M:%S", session.startTime)
        local endDateStr = session.endTime and date("%Y-%m-%d", session.endTime)
        local endStr
        if session.endTime then
            endStr = (endDateStr == session.date) and date("%H:%M:%S", session.endTime)
                      or date("%Y-%m-%d %H:%M:%S", session.endTime)
        else
            endStr = "In progress"
        end

        AddDetailRow(detailPanel, yOfs, "Start:", startStr,
            C_NEUTRAL[1], C_NEUTRAL[2], C_NEUTRAL[3], C_TEXT[1], C_TEXT[2], C_TEXT[3])
        yOfs = yOfs - 16
        AddDetailRow(detailPanel, yOfs, "End:", endStr,
            C_NEUTRAL[1], C_NEUTRAL[2], C_NEUTRAL[3], C_TEXT[1], C_TEXT[2], C_TEXT[3])
        yOfs = yOfs - 16
        AddDetailRow(detailPanel, yOfs, "Duration:", duration,
            C_NEUTRAL[1], C_NEUTRAL[2], C_NEUTRAL[3], C_TEXT[1], C_TEXT[2], C_TEXT[3])
        yOfs = yOfs - 18
    end

    AddDetailSeparator(detailPanel, yOfs)
    yOfs = yOfs - 8

    -- ── Outgoing CC ───────────────────────────────────────────────────────────
    AddDetailLine(detailPanel, yOfs, "Your CC  (outgoing)", C_OUT[1], C_OUT[2], C_OUT[3])
    yOfs = yOfs - 18

    AddDetailRow(detailPanel, yOfs, "Spell", "Hit%  (H / Tries)",
        C_HEADER[1], C_HEADER[2], C_HEADER[3],
        C_HEADER[1], C_HEADER[2], C_HEADER[3])
    yOfs = yOfs - 18

    local spellList = {}
    for name, entry in pairs(session.spells) do
        spellList[#spellList + 1] = { name = name, entry = entry }
    end
    CCTracker:SortCCSpellList(spellList, false)

    local totalAttempts, totalHits = 0, 0
    local currentLevel = nil

    for _, sd in ipairs(spellList) do
        local entry    = sd.entry
        local attempts = CCTracker:GetSpellAttempts(entry)
        totalAttempts  = totalAttempts + attempts
        totalHits      = totalHits + entry.hits

        -- Group header when CC level changes
        local spellData = CCTracker_CCSpells[sd.name]
        local level     = spellData and spellData.ccLevel or "hard"
        if level ~= currentLevel then
            local li = CCTracker_CCLevelInfo[level] or CCTracker_CCLevelInfo.hard
            AddDetailLine(detailPanel, yOfs, "  -- " .. li.label .. " --", li.r, li.g, li.b)
            yOfs = yOfs - 16
            currentLevel = level
        end

        local pct    = CCTracker:FormatHitPct(entry.hits, attempts)
        local pctVal = attempts > 0 and (entry.hits / attempts) or 0
        local pr, pg, pb = unpack(pctVal >= 0.75 and C_GOOD or (pctVal >= 0.50 and C_WARN or C_BAD))

        AddSpellRow(detailPanel, yOfs, entry.spellId,
            CCTracker:GetSpellDisplayName(entry.spellId, sd.name),
            string.format("%s  (%d / %d)", pct, entry.hits, attempts),
            C_TEXT[1], C_TEXT[2], C_TEXT[3], pr, pg, pb)
        yOfs = yOfs - SPELL_ROW_H

        -- Miss breakdown
        local hasMiss = false
        for _, mt in ipairs(CCTracker_MissTypeOrder) do
            local c = entry.misses[mt]
            if c and c > 0 then
                hasMiss = true
                AddDetailRow(detailPanel, yOfs,
                    string.format("    %s", CCTracker_MissTypeText[mt] or mt),
                    string.format("%d  (%.0f%%)", c, c / attempts * 100),
                    C_NEUTRAL[1], C_NEUTRAL[2], C_NEUTRAL[3],
                    C_BAD[1], C_BAD[2], C_BAD[3])
                yOfs = yOfs - 16
            end
        end

        -- Wasted due to enemy defensives
        local hasWaste = false
        for _ in pairs(entry.wasted) do hasWaste = true; break end
        if hasWaste then
            AddDetailLine(detailPanel, yOfs, "    Wasted — enemy defensive:", C_WARN[1], C_WARN[2], C_WARN[3])
            yOfs = yOfs - 16
            for defName, count in pairs(entry.wasted) do
                AddDetailRow(detailPanel, yOfs,
                    string.format("      %s", defName), tostring(count),
                    C_NEUTRAL[1], C_NEUTRAL[2], C_NEUTRAL[3],
                    1, 0.5, 0.1)
                yOfs = yOfs - 16
            end
        end

        if hasMiss or hasWaste then yOfs = yOfs - 2 end
    end

    if #spellList == 0 then
        AddDetailLine(detailPanel, yOfs, "  No outgoing CC data for this session.",
            C_NEUTRAL[1], C_NEUTRAL[2], C_NEUTRAL[3])
        yOfs = yOfs - 18
    end

    -- Outgoing totals line
    AddDetailRow(detailPanel, yOfs,
        "  Outgoing total",
        string.format("%s  (%d / %d)", CCTracker:FormatHitPct(totalHits, totalAttempts), totalHits, totalAttempts),
        C_OUT[1], C_OUT[2], C_OUT[3],
        C_OUT[1], C_OUT[2], C_OUT[3])
    yOfs = yOfs - 22

    AddDetailSeparator(detailPanel, yOfs)
    yOfs = yOfs - 8

    -- ── Incoming CC ───────────────────────────────────────────────────────────
    AddDetailLine(detailPanel, yOfs, "Incoming CC  (enemy -> you)", C_IN[1], C_IN[2], C_IN[3])
    yOfs = yOfs - 18

    AddDetailRow(detailPanel, yOfs, "Spell", "Avoid%  (A / Tries)",
        C_HEADER[1], C_HEADER[2], C_HEADER[3],
        C_HEADER[1], C_HEADER[2], C_HEADER[3])
    yOfs = yOfs - 18

    local inSpellList = {}
    for name, entry in pairs(session.incoming or {}) do
        inSpellList[#inSpellList + 1] = { name = name, entry = entry }
    end
    CCTracker:SortCCSpellList(inSpellList, true)

    local totalInAttempts, totalAvoided = 0, 0
    local currentInLevel = nil

    for _, sd in ipairs(inSpellList) do
        local entry    = sd.entry
        local attempts = CCTracker:GetIncomingAttempts(entry)
        local avoided  = attempts - entry.received
        totalInAttempts = totalInAttempts + attempts
        totalAvoided    = totalAvoided + avoided

        -- Group header when CC level changes
        local spellData = CCTracker_CCSpells[sd.name]
        local level     = spellData and spellData.ccLevel or "hard"
        if level ~= currentInLevel then
            local li = CCTracker_CCLevelInfo[level] or CCTracker_CCLevelInfo.hard
            AddDetailLine(detailPanel, yOfs, "  -- " .. li.label .. " --", li.r, li.g, li.b)
            yOfs = yOfs - 16
            currentInLevel = level
        end

        local avoidVal = attempts > 0 and (avoided / attempts) or 0
        local avoidPct = attempts > 0 and string.format("%.0f%%", avoidVal * 100) or "—"
        -- higher avoid% is better (green)
        local pr, pg, pb = unpack(avoidVal >= 0.5 and C_GOOD or (avoidVal >= 0.25 and C_WARN or C_BAD))

        AddSpellRow(detailPanel, yOfs, entry.spellId,
            CCTracker:GetSpellDisplayName(entry.spellId, sd.name),
            string.format("%s  (%d / %d)", avoidPct, avoided, attempts),
            C_TEXT[1], C_TEXT[2], C_TEXT[3], pr, pg, pb)
        yOfs = yOfs - SPELL_ROW_H

        -- Avoid type breakdown
        local hasAvoid = false
        for _, mt in ipairs(CCTracker_MissTypeOrder) do
            local c = entry.avoided[mt]
            if c and c > 0 then
                hasAvoid = true
                AddDetailRow(detailPanel, yOfs,
                    string.format("    %s", CCTracker_MissTypeText[mt] or mt),
                    string.format("%d  (%.0f%%)", c, c / attempts * 100),
                    C_NEUTRAL[1], C_NEUTRAL[2], C_NEUTRAL[3],
                    C_GOOD[1], C_GOOD[2], C_GOOD[3])
                yOfs = yOfs - 16
            end
        end

        if hasAvoid then yOfs = yOfs - 2 end
    end

    if #inSpellList == 0 then
        AddDetailLine(detailPanel, yOfs, "  No incoming CC data for this session.",
            C_NEUTRAL[1], C_NEUTRAL[2], C_NEUTRAL[3])
        yOfs = yOfs - 18
    end

    -- Incoming totals line
    local inAvoidPct = totalInAttempts > 0
        and string.format("%.0f%%", totalAvoided / totalInAttempts * 100) or "—"
    AddDetailRow(detailPanel, yOfs,
        "  Incoming total",
        string.format("%s  (%d avoided / %d)", inAvoidPct, totalAvoided, totalInAttempts),
        C_IN[1], C_IN[2], C_IN[3],
        C_IN[1], C_IN[2], C_IN[3])
    yOfs = yOfs - 22

    detailPanel:SetHeight(math.abs(yOfs) + 20)
end

-- Builds a human-readable description of the active filters (used in combined header).
local function BuildFilterDesc()
    local parts = {}
    local typeSummary = GetTypeSummary()
    if typeSummary ~= "All Types" then parts[#parts + 1] = typeSummary end
    if filterDate ~= "all" then
        local dateOpts = GetDateOptions()
        for _, o in ipairs(dateOpts) do
            if o.key == filterDate then parts[#parts + 1] = o.label; break end
        end
    end
    if filterChar == "all" then parts[#parts + 1] = "All Characters" end
    return #parts > 0 and ("Filter: " .. table.concat(parts, "  |  ")) or ""
end

local function RenderCombinedStats(sessions)
    if not sessions or #sessions == 0 then
        ClearDetailPanel()
        AddDetailLine(detailPanel, -10, "No sessions match the current filters.",
            C_NEUTRAL[1], C_NEUTRAL[2], C_NEUTRAL[3])
        return
    end
    local spells, incoming = AggregateSessions(sessions)
    local virtual = {
        _isCombined    = true,
        _sessionCount  = #sessions,
        _filterDesc    = BuildFilterDesc(),
        spells         = spells,
        incoming       = incoming,
    }
    RenderDetail(virtual)
end

-- ─── Session list ─────────────────────────────────────────────────────────────

local scrollFrame
local scrollChild

local function GetOrCreateEntry(index)
    if entryButtons[index] then return entryButtons[index] end

    local btn = CreateFrame("Button", nil, scrollChild)
    btn:SetHeight(ENTRY_H)

    -- Selection highlight
    local selTex = btn:CreateTexture(nil, "BACKGROUND")
    selTex:SetAllPoints()
    selTex:SetTexture(C_SEL[1], C_SEL[2], C_SEL[3], C_SEL[4])
    selTex:Hide()
    btn.selTex = selTex

    -- Hover highlight — manual show/hide avoids the default bright-green button glow
    local hlTex = btn:CreateTexture(nil, "ARTWORK")
    hlTex:SetAllPoints()
    hlTex:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    hlTex:SetVertexColor(0.75, 0.75, 0.75, 0.18)
    hlTex:Hide()
    btn.hlTex = hlTex

    -- Type icon area (coloured badge)
    local badge = btn:CreateTexture(nil, "ARTWORK")
    badge:SetSize(6, ENTRY_H - 8)
    badge:SetPoint("LEFT", btn, "LEFT", 4, 0)
    btn.badge = badge

    -- Text lines — offset by 3 more px to centre in the taller row
    local topLine = MakeFont(btn, 11, "LEFT")
    topLine:SetPoint("TOPLEFT",  btn, "TOPLEFT",  16, -7)
    topLine:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, -7)
    btn.topLine = topLine

    local botLine = MakeFont(btn, 10, "LEFT")
    botLine:SetPoint("TOPLEFT",  btn, "TOPLEFT",  16, -20)
    botLine:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, -20)
    botLine:SetTextColor(C_NEUTRAL[1], C_NEUTRAL[2], C_NEUTRAL[3])
    btn.botLine = botLine

    btn:SetScript("OnClick", function(self)
        selectedIndex   = self.sessionIndex
        showingCombined = false
        CCTracker_History:RefreshList()
        RenderDetail(filteredSessions[selectedIndex])
    end)
    btn:SetScript("OnEnter", function(self) self.hlTex:Show() end)
    btn:SetScript("OnLeave", function(self) self.hlTex:Hide() end)

    entryButtons[index] = btn
    return btn
end

local BADGE_COLORS = {
    arena  = { 1,    0.3,  0.3 },
    pvp    = { 0.3,  0.6,  1   },
    party  = { 0.3,  1,    0.5 },
    raid   = { 0.8,  0.3,  1   },
    world  = { 0.7,  0.7,  0.7 },
}

function CCTracker_History:RefreshList()
    -- Hide all previously created entry buttons
    for i = 1, #entryButtons do
        entryButtons[i]:Hide()
    end

    local y = 0
    for i, session in ipairs(filteredSessions) do
        local btn = GetOrCreateEntry(i)

        local typeName = CCTracker_SessionTypeNames[session.type] or session.type
        local duration = session.endTime
            and CCTracker:FormatDuration(session.endTime - session.startTime)
            or "active"
        local totalAtt, totalHits = 0, 0
        for _, e in pairs(session.spells) do
            totalHits = totalHits + e.hits
            totalAtt  = totalAtt  + CCTracker:GetSpellAttempts(e)
        end
        local pct = CCTracker:FormatHitPct(totalHits, totalAtt)

        local totalInAtt, totalAvoided = 0, 0
        for _, e in pairs(session.incoming or {}) do
            local att = CCTracker:GetIncomingAttempts(e)
            totalInAtt  = totalInAtt  + att
            totalAvoided = totalAvoided + (att - e.received)
        end

        local startClock = date("%H:%M", session.startTime)
        btn.topLine:SetText(string.format("%s  |  %s", typeName, session.name))
        btn.botLine:SetText(string.format("%s  •  %s  •  Out: %d/%d (%s)  In: %d/%d avd",
            startClock, duration, totalHits, totalAtt, pct, totalAvoided, totalInAtt))

        local bc = BADGE_COLORS[session.type] or BADGE_COLORS.world
        btn.badge:SetTexture(bc[1], bc[2], bc[3], 1)

        btn.sessionIndex = i
        btn.selTex:SetShown(i == selectedIndex)

        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  0, -y)
        btn:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
        btn:Show()

        y = y + ENTRY_H
    end

    scrollChild:SetHeight(math.max(y, 1))
end

function CCTracker_History:RebuildList()
    filteredSessions = CCTracker:GetFilteredSessions(
        filterTypes,
        (filterDate ~= "all" and filterDate ~= "week") and filterDate or nil,
        filterChar)

    -- Handle "week" specially
    if filterDate == "week" then
        local weekAgo = date("%Y-%m-%d", time() - 7 * 86400)
        local result  = {}
        for _, s in ipairs(filteredSessions) do
            if s.date >= weekAgo then result[#result + 1] = s end
        end
        filteredSessions = result
    end

    -- Scroll back to top on filter change
    if scrollFrame then scrollFrame:SetVerticalScroll(0) end
    self:RefreshList()

    -- Update totals footer
    local totalAtt, totalHits = 0, 0
    local totalInAtt, totalAvoided = 0, 0
    for _, s in ipairs(filteredSessions) do
        for _, e in pairs(s.spells) do
            totalHits = totalHits + e.hits
            totalAtt  = totalAtt  + CCTracker:GetSpellAttempts(e)
        end
        for _, e in pairs(s.incoming or {}) do
            local att = CCTracker:GetIncomingAttempts(e)
            totalInAtt   = totalInAtt   + att
            totalAvoided = totalAvoided + (att - e.received)
        end
    end
    local outPct  = CCTracker:FormatHitPct(totalHits, totalAtt)
    local inAvPct = totalInAtt > 0
        and string.format("%.0f%%", totalAvoided / totalInAtt * 100) or "—"
    CCTracker_History.totalText:SetText(
        string.format("Showing %d sessions  |  Out: %d/%d (%s)  |  In: %d/%d avoided (%s)",
            #filteredSessions, totalHits, totalAtt, outPct, totalAvoided, totalInAtt, inAvPct))

    -- Re-render the right panel
    if showingCombined then
        RenderCombinedStats(filteredSessions)
    elseif selectedIndex and filteredSessions[selectedIndex] then
        RenderDetail(filteredSessions[selectedIndex])
    else
        selectedIndex = nil
        RenderDetail(nil)
    end
end

function CCTracker_History:RefreshIfVisible()
    if self.mainFrame and self.mainFrame:IsShown() then
        self:RebuildList()
    end
end

-- ─── Build the main window ───────────────────────────────────────────────────

local function BuildHistory()
    CCTracker.Log("BuildHistory: start")
    if CCTracker_History.mainFrame then
        CCTracker.Log("BuildHistory: already built, skipping")
        return
    end

    -- Restore persisted filter state (all-true by default on first load)
    local saved = CCTrackerDB and CCTrackerDB.settings and CCTrackerDB.settings.historyFilter
    if saved then
        for k in pairs(filterTypes) do
            if saved[k] ~= nil then filterTypes[k] = saved[k] end
        end
    end

    -- ── Main frame (fully manual — no UIPanelDialogTemplate) ────────────────
    local f = CreateFrame("Frame", "CCTrackerHistoryFrame", UIParent)
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetScript("OnShow", function() CCTracker_History:RebuildList() end)

    -- Background — solid black at 50% opacity
    -- WHITE8X8 is a built-in 1-pixel white texture present in all WoW versions;
    -- SetVertexColor tints it to any colour we want.
    local mainBg = f:CreateTexture(nil, "BACKGROUND")
    mainBg:SetAllPoints(f)
    mainBg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    mainBg:SetVertexColor(0, 0, 0, 0.5)

    -- ── Title bar ────────────────────────────────────────────────────────────
    local titleBg = f:CreateTexture(nil, "BACKGROUND")
    titleBg:SetPoint("TOPLEFT",  f, "TOPLEFT",  12, -12)
    titleBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -12)
    titleBg:SetHeight(26)
    titleBg:SetTexture(0, 0, 0, 0.5)

    local titleFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("LEFT",  titleBg, "LEFT",  6,  0)
    titleFS:SetPoint("RIGHT", titleBg, "RIGHT", -30, 0)
    titleFS:SetText("CCTracker — Session History")
    titleFS:SetTextColor(1, 0.82, 0, 1)

    -- Close button
    local closeBtn = CreateFrame("Button", "CCTrackerHistoryClose", f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Separator below title
    MakeSeparator(f, -42)

    -- ── Filter bar ───────────────────────────────────────────────────────────
    -- Row 1: type | date | char | Reset
    -- Row 2: Combined (right side) | Clear All (far right)
    local filterY = -50

    -- ── Type multi-select dropdown button ────────────────────────────────────
    local typeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    typeBtn:SetSize(130, 24)
    typeBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 14, filterY)
    typeBtn:SetText(GetTypeSummary())

    -- ── Build the type-filter popup dropdown ──────────────────────────────────
    -- DROP_H = preset row (28) + separator (6) + 6 rows (26 each) + bottom pad (8)
    local DROP_W  = 175
    local DROP_H  = 28 + 6 + #TYPE_ORDER * 26 + 8
    typeDropdown  = CreateFrame("Frame", "CCTrackerTypeDropdown", UIParent)
    typeDropdown:SetSize(DROP_W, DROP_H)
    typeDropdown:SetFrameStrata("TOOLTIP")
    typeDropdown:Hide()

    -- Background
    local dropBg = typeDropdown:CreateTexture(nil, "BACKGROUND")
    dropBg:SetAllPoints()
    dropBg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    dropBg:SetVertexColor(0.05, 0.05, 0.05, 0.97)
    -- Border (1-px inset)
    local dropBorder = typeDropdown:CreateTexture(nil, "BORDER")
    dropBorder:SetAllPoints()
    dropBorder:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    dropBorder:SetVertexColor(0.45, 0.45, 0.45, 0.9)
    local dropInner = typeDropdown:CreateTexture(nil, "BACKGROUND")
    dropInner:SetPoint("TOPLEFT",     typeDropdown, "TOPLEFT",      1, -1)
    dropInner:SetPoint("BOTTOMRIGHT", typeDropdown, "BOTTOMRIGHT", -1,  1)
    dropInner:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    dropInner:SetVertexColor(0.05, 0.05, 0.05, 0.97)

    -- Preset quick-select buttons: All | PvP | PvE | None
    local PRESETS = {
        {
            label = "All",
            fn    = function()
                for _, t in ipairs(TYPE_ORDER) do filterTypes[t.key] = true end
            end,
        },
        {
            label = "PvP",
            fn    = function()
                for _, t in ipairs(TYPE_ORDER) do filterTypes[t.key] = false end
                filterTypes.arena_rated = true; filterTypes.arena_skirmish = true
                filterTypes.pvp = true
            end,
        },
        {
            label = "PvE",
            fn    = function()
                for _, t in ipairs(TYPE_ORDER) do filterTypes[t.key] = false end
                filterTypes.party = true; filterTypes.raid = true
            end,
        },
        {
            label = "None",
            fn    = function()
                for _, t in ipairs(TYPE_ORDER) do filterTypes[t.key] = false end
            end,
        },
    }

    local presetW = math.floor((DROP_W - 10) / #PRESETS) - 2
    for i, p in ipairs(PRESETS) do
        local pb = CreateFrame("Button", nil, typeDropdown, "UIPanelButtonTemplate")
        pb:SetSize(presetW, 20)
        pb:SetPoint("TOPLEFT", typeDropdown, "TOPLEFT", 4 + (i - 1) * (presetW + 2), -4)
        pb:SetText(p.label)
        pb:SetScript("OnClick", function()
            p.fn()
            -- Sync checkboxes in the dropdown to the new state
            for _, cb in ipairs(typeCheckboxes) do
                cb:SetChecked(filterTypes[cb.typeKey])
            end
            typeBtn:SetText(GetTypeSummary())
            selectedIndex = nil
            SaveFilterTypes()
            CCTracker_History:RebuildList()
        end)
    end

    -- Thin separator below preset row
    local dropSep = typeDropdown:CreateTexture(nil, "ARTWORK")
    dropSep:SetHeight(1)
    dropSep:SetPoint("TOPLEFT",  typeDropdown, "TOPLEFT",   4, -28)
    dropSep:SetPoint("TOPRIGHT", typeDropdown, "TOPRIGHT", -4, -28)
    dropSep:SetTexture(0.4, 0.4, 0.4, 0.8)

    -- One checkbox row per session type
    typeCheckboxes = {}
    for i, t in ipairs(TYPE_ORDER) do
        local cb = CreateFrame("CheckButton", nil, typeDropdown, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", typeDropdown, "TOPLEFT", 4, -34 - (i - 1) * 26)
        cb.typeKey = t.key
        cb:SetChecked(filterTypes[t.key])

        local lbl = typeDropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetText(t.label)
        lbl:SetTextColor(0.9, 0.9, 0.9)

        cb:SetScript("OnClick", function(self)
            filterTypes[self.typeKey] = self:GetChecked() and true or false
            typeBtn:SetText(GetTypeSummary())
            selectedIndex = nil
            SaveFilterTypes()
            CCTracker_History:RebuildList()
        end)
        typeCheckboxes[#typeCheckboxes + 1] = cb
    end

    -- Toggle dropdown open / closed when the type button is clicked
    typeBtn:SetScript("OnClick", function()
        if typeDropdown:IsShown() then
            typeDropdown:Hide()
        else
            -- Sync checkboxes before showing
            for _, cb in ipairs(typeCheckboxes) do
                cb:SetChecked(filterTypes[cb.typeKey])
            end
            typeDropdown:ClearAllPoints()
            typeDropdown:SetPoint("TOPLEFT", typeBtn, "BOTTOMLEFT", 0, -2)
            typeDropdown:Show()
            typeDropdown:Raise()
        end
    end)

    -- Hide dropdown when the history window is hidden
    f:SetScript("OnHide", function() typeDropdown:Hide() end)

    local dateBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    dateBtn:SetSize(110, 24)
    dateBtn:SetPoint("LEFT", typeBtn, "RIGHT", 6, 0)
    dateBtn:SetText("All Dates")
    dateBtn:SetScript("OnClick", function(self) CycleDateFilter(self) end)

    -- Character filter: "My Char" / "All Chars"
    local charBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    charBtn:SetSize(100, 24)
    charBtn:SetPoint("LEFT", dateBtn, "RIGHT", 6, 0)
    charBtn:SetText("My Char")
    charBtn:SetScript("OnClick", function(self)
        if filterChar == "current" then
            filterChar = "all"
            self:SetText("All Chars")
        else
            filterChar = "current"
            self:SetText("My Char")
        end
        selectedIndex   = nil
        showingCombined = false
        CCTracker_History:RebuildList()
    end)
    CCTracker_History.charBtn = charBtn

    local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBtn:SetSize(70, 24)
    resetBtn:SetPoint("LEFT", charBtn, "RIGHT", 6, 0)
    resetBtn:SetText("Reset")
    resetBtn:SetScript("OnClick", function()
        -- Reset all type checkboxes to enabled
        for _, t in ipairs(TYPE_ORDER) do filterTypes[t.key] = true end
        filterDate      = "all"
        filterChar      = "current"
        dateCycleIndex  = 1
        showingCombined = false
        typeBtn:SetText(GetTypeSummary())
        -- Sync the dropdown checkboxes if the popup was already built
        for _, cb in ipairs(typeCheckboxes) do
            cb:SetChecked(true)
        end
        dateBtn:SetText("All Dates")
        charBtn:SetText("My Char")
        SaveFilterTypes()
        selectedIndex = nil
        CCTracker_History:RebuildList()
    end)

    -- Combined stats button — right side of filter row
    local combinedBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    combinedBtn:SetSize(120, 24)
    combinedBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, filterY)
    combinedBtn:SetText("Combined Stats")
    combinedBtn:SetScript("OnClick", function()
        showingCombined = not showingCombined
        if showingCombined then
            selectedIndex = nil
            CCTracker_History:RefreshList()
            RenderCombinedStats(filteredSessions)
        else
            RenderDetail(nil)
        end
    end)

    -- Clear data button (right side, second row)
    StaticPopupDialogs["CCTRACKER_CONFIRM_CLEAR"] = {
        text         = "Delete session history for %s? This cannot be undone.",
        button1      = "Delete",
        button2      = "Cancel",
        OnAccept     = function()
            if filterChar == "all" then
                -- Clear all characters
                CCTrackerDB.sessions       = {}
                CCTrackerDB.currentSession = nil
            else
                -- Clear only current character's sessions
                local myChar = CCTracker:GetCharKey()
                local keep   = {}
                for _, s in ipairs(CCTrackerDB.sessions or {}) do
                    if s.char and s.char ~= myChar then
                        keep[#keep + 1] = s
                    end
                end
                CCTrackerDB.sessions = keep
                local cs = CCTrackerDB.currentSession
                if cs and (not cs.char or cs.char == myChar) then
                    CCTrackerDB.currentSession = nil
                end
            end
            selectedIndex   = nil
            showingCombined = false
            CCTracker_History:RebuildList()
            if CCTracker_Widget then CCTracker_Widget:Refresh() end
        end,
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
    }
    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(90, 24)
    clearBtn:SetPoint("RIGHT", combinedBtn, "LEFT", -6, 0)
    clearBtn:SetText("Clear Data")
    clearBtn:SetScript("OnClick", function()
        local who = filterChar == "all" and "ALL characters" or UnitName("player")
        StaticPopup_Show("CCTRACKER_CONFIRM_CLEAR", who)
    end)

    -- Separator below filters
    local contentTopY = filterY - 30
    MakeSeparator(f, contentTopY)

    -- ── Session list (left) ──────────────────────────────────────────────────
    local listFrame = CreateFrame("Frame", nil, f)
    listFrame:SetPoint("TOPLEFT",    f, "TOPLEFT",   10, contentTopY - 4)
    listFrame:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 36)
    listFrame:SetWidth(LIST_W)

    local listBg = listFrame:CreateTexture(nil, "BACKGROUND")
    listBg:SetAllPoints(listFrame)
    listBg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    listBg:SetVertexColor(0, 0, 0, 0.4)

    -- Plain ScrollFrame — no FauxScrollFrame template dependency
    scrollFrame = CreateFrame("ScrollFrame", "CCTrackerHistoryScroll", listFrame)
    scrollFrame:SetPoint("TOPLEFT",     listFrame, "TOPLEFT",     4,  -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -4,  4)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * ENTRY_H)))
    end)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(LIST_W - 12)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- ── Detail panel (right) ─────────────────────────────────────────────────
    local detailFrame = CreateFrame("ScrollFrame", "CCTrackerDetailScroll", f)
    detailFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",     DETAIL_X,  contentTopY - 4)
    detailFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14,        36)
    detailFrame:EnableMouseWheel(true)

    local detailBg = detailFrame:CreateTexture(nil, "BACKGROUND")
    detailBg:SetAllPoints(detailFrame)
    detailBg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    detailBg:SetVertexColor(0, 0, 0, 0.4)

    -- Manual scrollbar for the detail panel
    local detailSB = CreateFrame("Slider", "CCTrackerDetailScrollBar", detailFrame, "UIPanelScrollBarTemplate")
    detailSB:SetPoint("TOPRIGHT",    detailFrame, "TOPRIGHT",  -2, -16)
    detailSB:SetPoint("BOTTOMRIGHT", detailFrame, "BOTTOMRIGHT", -2,  16)
    detailSB:SetMinMaxValues(0, 0)
    detailSB:SetValueStep(20)
    detailSB:SetValue(0)
    detailSB:SetScript("OnValueChanged", function(self, val)
        detailFrame:SetVerticalScroll(val)
    end)
    detailFrame:SetScript("OnScrollRangeChanged", function(self, _, yRange)
        local maxVal = yRange or 0
        detailSB:SetMinMaxValues(0, maxVal)
        if maxVal <= 0 then detailSB:Hide() else detailSB:Show() end
    end)
    detailFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = detailSB:GetValue()
        detailSB:SetValue(cur - delta * 30)
    end)

    detailPanel = CreateFrame("Frame", nil, detailFrame)
    detailPanel:SetWidth(DETAIL_W - 20)
    detailPanel:SetHeight(1)
    detailFrame:SetScrollChild(detailPanel)

    -- ── Footer totals bar ────────────────────────────────────────────────────
    MakeSeparator(f, -WIN_H + 32)

    local totalText = MakeFont(f, 11, "LEFT")
    totalText:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  16, 14)
    totalText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
    totalText:SetTextColor(C_NEUTRAL[1], C_NEUTRAL[2], C_NEUTRAL[3])
    CCTracker_History.totalText = totalText

    CCTracker_History.mainFrame = f

    RenderDetail(nil)
    f:Hide()

    CCTracker.Log("BuildHistory: done")
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function CCTracker_History:Toggle()
    CCTracker.Log("History:Toggle called. mainFrame=" .. tostring(self.mainFrame))
    if not self.mainFrame then
        CCTracker.Log("History:Toggle — calling BuildHistory()")
        BuildHistory()
    end
    if not self.mainFrame then
        CCTracker.Log("History:Toggle — mainFrame still nil after BuildHistory!")
        return
    end
    if self.mainFrame:IsShown() then
        CCTracker.Log("History:Toggle — hiding")
        self.mainFrame:Hide()
    else
        CCTracker.Log("History:Toggle — showing")
        self.mainFrame:Show()
    end
end

-- Initialise on login
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    local ok, err = pcall(BuildHistory)
    if not ok then
        print("|cffff4444[CCTracker] History build ERROR:|r " .. tostring(err))
    end
end)
