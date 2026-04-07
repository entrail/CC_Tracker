-- CCTracker_Widget.lua
-- Small movable widget showing current session CC stats (outgoing + incoming)

CCTracker_Widget = {}

local WIDGET_WIDTH  = 280   -- default / initial width
local WIDGET_MIN_W  = 200   -- minimum allowed width when resizing
local WIDGET_MAX_W  = 600   -- maximum allowed width when resizing
local WIDGET_MIN_H  = 130   -- ← adjust this line to change the minimum height
local ROW_HEIGHT    = 22
local HEADER_HEIGHT = 28
local SECTION_H     = 16   -- section label height
local COL_H         = 14   -- column-header label height
local PADDING       = 8
local MAX_ROWS      = 10
local ICON_SIZE     = 16
-- Fixed horizontal space consumed by the icon + right-side columns (used to derive the
-- adaptive spell-name column width from the current widget width).
-- = PADDING(left) + ICON_SIZE + icon_gap(5) + PADDING(right) + tries(52) + gap(4) + pct(52)
local NAME_COL_RESERVED = PADDING + ICON_SIZE + 5 + PADDING + 52 + 4 + 52  -- 145

local C_TITLE   = { 1,    0.82, 0 }
local C_HEADER  = { 0.6,  0.6,  0.6 }
local C_TEXT    = { 0.9,  0.9,  0.9 }
local C_GOOD    = { 0.2,  0.8,  0.2 }
local C_BAD     = { 1,    0.3,  0.3 }
local C_WARN    = { 1,    0.7,  0.1 }
local C_NEUTRAL = { 0.7,  0.7,  0.7 }
local C_OUT     = { 0.4,  0.8,  1   }   -- blue tint for outgoing section
local C_IN      = { 1,    0.5,  0.3 }   -- orange tint for incoming section

-- Row pools — separate pools for outgoing and incoming rows
local outRows = {}
local inRows  = {}

local function MakeFont(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size or 11, "OUTLINE")
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- ─── Tooltips ────────────────────────────────────────────────────────────────

local function ShowOutgoingTooltip(row, spellName, entry)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local attempts = CCTracker:GetSpellAttempts(entry)
    local misses   = CCTracker:GetSpellMissTotal(entry)
    GameTooltip:AddLine(spellName .. "  (Outgoing)", C_OUT[1], C_OUT[2], C_OUT[3])
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Attempts:", tostring(attempts), 1,1,1, unpack(C_TEXT))
    GameTooltip:AddDoubleLine("Hits:",
        string.format("%d  (%s)", entry.hits, CCTracker:FormatHitPct(entry.hits, attempts)),
        1,1,1, C_GOOD[1], C_GOOD[2], C_GOOD[3])
    if misses > 0 then
        GameTooltip:AddDoubleLine("Misses:", tostring(misses), 1,1,1, C_BAD[1], C_BAD[2], C_BAD[3])
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Miss breakdown:", unpack(C_HEADER))
        for _, mt in ipairs(CCTracker_MissTypeOrder) do
            local c = entry.misses[mt]
            if c and c > 0 then
                GameTooltip:AddDoubleLine(
                    "  " .. (CCTracker_MissTypeText[mt] or mt) .. ":",
                    string.format("%d  (%.0f%%)", c, c / attempts * 100),
                    unpack(C_NEUTRAL), C_BAD[1], C_BAD[2], C_BAD[3])
            end
        end
    end
    local hasWaste = false
    for _ in pairs(entry.wasted) do hasWaste = true; break end
    if hasWaste then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Wasted — enemy had defensive up:", 1, 0.7, 0.1)
        for defName, count in pairs(entry.wasted) do
            GameTooltip:AddDoubleLine("  " .. defName .. ":", tostring(count),
                unpack(C_NEUTRAL), 1, 0.5, 0.1)
        end
    end
    GameTooltip:Show()
end

local function ShowIncomingTooltip(row, spellName, entry)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local attempts = CCTracker:GetIncomingAttempts(entry)
    local avoided  = attempts - entry.received
    GameTooltip:AddLine(spellName .. "  (Incoming)", C_IN[1], C_IN[2], C_IN[3])
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Times targeted:", tostring(attempts), 1,1,1, unpack(C_TEXT))
    GameTooltip:AddDoubleLine("Got CC'd:",
        string.format("%d  (%.0f%%)", entry.received,
            attempts > 0 and entry.received / attempts * 100 or 0),
        1,1,1, C_BAD[1], C_BAD[2], C_BAD[3])
    if avoided > 0 then
        GameTooltip:AddDoubleLine("Avoided:",
            string.format("%d  (%s)", avoided, CCTracker:FormatHitPct(avoided, attempts)),
            1,1,1, C_GOOD[1], C_GOOD[2], C_GOOD[3])
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Avoidance breakdown:", unpack(C_HEADER))
        for _, mt in ipairs(CCTracker_MissTypeOrder) do
            local c = entry.avoided[mt]
            if c and c > 0 then
                GameTooltip:AddDoubleLine(
                    "  " .. (CCTracker_MissTypeText[mt] or mt) .. ":",
                    string.format("%d  (%.0f%%)", c, c / attempts * 100),
                    unpack(C_NEUTRAL), C_GOOD[1], C_GOOD[2], C_GOOD[3])
            end
        end
    end
    GameTooltip:Show()
end

-- ─── Row factory ─────────────────────────────────────────────────────────────

local function MakeRow(pool, parent, index, tooltipFn)
    if pool[index] then return pool[index] end

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    local name = MakeFont(row, 11, "LEFT")
    name:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    name:SetWidth(120)
    row.name = name

    local pct = MakeFont(row, 11, "RIGHT")
    pct:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    pct:SetWidth(52)
    row.pct = pct

    local tries = MakeFont(row, 10, "RIGHT")
    tries:SetPoint("RIGHT", pct, "LEFT", -4, 0)
    tries:SetWidth(52)
    tries:SetTextColor(unpack(C_HEADER))
    row.tries = tries

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if self.spellName and self.entry then
            tooltipFn(self, self.spellName, self.entry)
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    pool[index] = row
    return row
end

-- ─── Build the frame ─────────────────────────────────────────────────────────

local function BuildWidget()
    CCTracker.Log("BuildWidget: start")
    local f = CreateFrame("Frame", "CCTrackerWidget", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    -- Solid black background at 50% opacity
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    bg:SetVertexColor(0, 0, 0, 0.5)

    -- Drag handlers
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        CCTrackerDB.settings.widgetPoint    = point
        CCTrackerDB.settings.widgetRelPoint = relPoint
        CCTrackerDB.settings.widgetX        = x
        CCTrackerDB.settings.widgetY        = y
    end)

    -- ── Resize grip (bottom-right corner) ────────────────────────────────────
    local grip = CreateFrame("Frame", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    grip:SetFrameLevel(f:GetFrameLevel() + 2)
    grip:EnableMouse(true)

    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

    grip:SetScript("OnEnter", function()
        gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Over")
    end)
    grip:SetScript("OnLeave", function()
        gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    end)
    grip:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then f:StartSizing("RIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        -- Clamp width to allowed range, then re-layout (Refresh enforces WIDGET_MIN_H).
        local w = math.max(WIDGET_MIN_W, math.min(WIDGET_MAX_W, f:GetWidth()))
        CCTrackerDB.settings.widgetWidth = w
        CCTracker_Widget:Refresh()
    end)

    -- ── Outgoing section ─────────────────────────────────────────────────────
    local outLabel = MakeFont(f, 11, "LEFT")
    outLabel:SetTextColor(C_OUT[1], C_OUT[2], C_OUT[3])
    outLabel:SetText("Your CC")
    f.outLabel = outLabel

    local outColTries = MakeFont(f, 9, "RIGHT")
    outColTries:SetTextColor(unpack(C_HEADER))
    outColTries:SetText("Tries")
    f.outColTries = outColTries

    local outColPct = MakeFont(f, 9, "RIGHT")
    outColPct:SetTextColor(unpack(C_HEADER))
    outColPct:SetText("Hit%")
    f.outColPct = outColPct

    local outContainer = CreateFrame("Frame", nil, f)
    f.outContainer = outContainer

    local outEmpty = MakeFont(f, 10, "CENTER")
    outEmpty:SetTextColor(unpack(C_HEADER))
    outEmpty:SetText("No outgoing CCs tracked.")
    f.outEmpty = outEmpty

    local outSep = f:CreateTexture(nil, "BACKGROUND")
    outSep:SetHeight(1)
    outSep:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    outSep:SetVertexColor(0.3, 0.3, 0.3, 0.8)
    f.outSep = outSep

    -- ── Incoming section ─────────────────────────────────────────────────────
    local inLabel = MakeFont(f, 11, "LEFT")
    inLabel:SetTextColor(C_IN[1], C_IN[2], C_IN[3])
    inLabel:SetText("Incoming CC")
    f.inLabel = inLabel

    local inColTries = MakeFont(f, 9, "RIGHT")
    inColTries:SetTextColor(unpack(C_HEADER))
    inColTries:SetText("Tries")
    f.inColTries = inColTries

    local inColPct = MakeFont(f, 9, "RIGHT")
    inColPct:SetTextColor(unpack(C_HEADER))
    inColPct:SetText("Avoid%")
    f.inColPct = inColPct

    local inContainer = CreateFrame("Frame", nil, f)
    f.inContainer = inContainer

    local inEmpty = MakeFont(f, 10, "CENTER")
    inEmpty:SetTextColor(unpack(C_HEADER))
    inEmpty:SetText("No incoming CCs tracked.")
    f.inEmpty = inEmpty

    -- ── Footer ────────────────────────────────────────────────────────────────
    local footerSep = f:CreateTexture(nil, "BACKGROUND")
    footerSep:SetHeight(1)
    footerSep:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    footerSep:SetVertexColor(0.3, 0.3, 0.3, 0.8)
    f.footerSep = footerSep

    local footerText = MakeFont(f, 10, "CENTER")
    footerText:SetTextColor(unpack(C_HEADER))
    f.footerText = footerText

    CCTracker_Widget.frame = f
    CCTracker.Log("BuildWidget: done")
    return f
end

-- ─── Helpers ─────────────────────────────────────────────────────────────────

-- Positions a FontString at an absolute y from f's top-left/right.
local function PlaceWide(fs, f, y, padL, padR)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT",  f, "TOPLEFT",  padL or PADDING, y)
    fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(padR or PADDING), y)
end

local function PlaceRight(fs, f, y, w)
    fs:ClearAllPoints()
    fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PADDING, y)
    fs:SetWidth(w or 52)
end

local function PlaceRight2(fs, f, y, rightOf, w)
    fs:ClearAllPoints()
    fs:SetPoint("TOPRIGHT", rightOf, "TOPLEFT", -4, 0)
    fs:SetWidth(w or 52)
end

local function ColourPct(fs, val)
    if val >= 0.75 then
        fs:SetTextColor(C_GOOD[1], C_GOOD[2], C_GOOD[3])
    elseif val >= 0.50 then
        fs:SetTextColor(C_WARN[1], C_WARN[2], C_WARN[3])
    else
        fs:SetTextColor(C_BAD[1], C_BAD[2], C_BAD[3])
    end
end

-- ─── Refresh ─────────────────────────────────────────────────────────────────

function CCTracker_Widget:Refresh()
    local f = self.frame
    CCTracker.Log("Widget:Refresh called. frame=" .. tostring(f)
        .. " shown=" .. tostring(f and f:IsShown()))
    if not f or not f:IsShown() then return end

    -- ── Session data ──────────────────────────────────────────────────────────
    local session = CCTrackerDB.currentSession
    if not session then
        -- Show the most recent session belonging to the current character
        local sessions = CCTrackerDB.sessions
        local myChar   = CCTracker:GetCharKey()
        if sessions then
            for i = #sessions, 1, -1 do
                local s = sessions[i]
                if not s.char or s.char == myChar then
                    session = s
                    break
                end
            end
        end
    end

    local isActive = (session == CCTrackerDB.currentSession) and session ~= nil

    -- ── Build sorted spell lists ──────────────────────────────────────────────
    local outList, inList = {}, {}
    if session then
        for name, entry in pairs(session.spells or {}) do
            outList[#outList + 1] = { name = name, entry = entry }
        end
        for name, entry in pairs(session.incoming or {}) do
            inList[#inList + 1] = { name = name, entry = entry }
        end
        CCTracker:SortCCSpellList(outList, false)
        CCTracker:SortCCSpellList(inList,  true)
    end
    local outCount = math.min(#outList, MAX_ROWS)
    local inCount  = math.min(#inList,  MAX_ROWS)

    -- Adaptive spell-name column width — grows and shrinks with the widget.
    local nameW = math.max(60, f:GetWidth() - NAME_COL_RESERVED)

    -- Hide all previously active rows
    for _, r in ipairs(outRows) do r:Hide() end
    for _, r in ipairs(inRows)  do r:Hide() end

    -- ── Layout engine — running y from top ───────────────────────────────────
    local y = -PADDING   -- start at top with just a small padding gap

    -- ── OUTGOING SECTION ─────────────────────────────────────────────────────
    -- Section label
    f.outLabel:ClearAllPoints()
    f.outLabel:SetPoint("TOPLEFT",  f, "TOPLEFT",  PADDING, y)
    f.outLabel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PADDING, y)
    f.outLabel:SetHeight(SECTION_H)
    -- Column headers (right-aligned)
    f.outColPct:ClearAllPoints()
    f.outColPct:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PADDING, y)
    f.outColPct:SetWidth(52)
    f.outColTries:ClearAllPoints()
    f.outColTries:SetPoint("TOPRIGHT", f.outColPct, "TOPLEFT", -4, 0)
    f.outColTries:SetWidth(52)
    y = y - SECTION_H - 2

    -- Outgoing rows or empty label
    local oc = f.outContainer
    oc:ClearAllPoints()
    oc:SetPoint("TOPLEFT",  f, "TOPLEFT",  PADDING, y)
    oc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PADDING, y)

    if outCount == 0 then
        f.outEmpty:ClearAllPoints()
        f.outEmpty:SetPoint("TOPLEFT",  oc, "TOPLEFT",  0, 0)
        f.outEmpty:SetPoint("TOPRIGHT", oc, "TOPRIGHT", 0, 0)
        f.outEmpty:Show()
        oc:SetHeight(ROW_HEIGHT)
        y = y - ROW_HEIGHT
    else
        f.outEmpty:Hide()
        for i = 1, outCount do
            local sd    = outList[i]
            local entry = sd.entry
            local row   = MakeRow(outRows, oc, i, ShowOutgoingTooltip)
            local attempts = CCTracker:GetSpellAttempts(entry)
            local pctVal   = attempts > 0 and (entry.hits / attempts) or 0

            local displayName = CCTracker:GetSpellDisplayName(entry.spellId, sd.name)
            row.icon:SetTexture(GetSpellTexture(entry.spellId) or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetWidth(nameW)
            row.name:SetText(displayName)
            row.tries:SetText("(" .. attempts .. ")")
            row.pct:SetText(CCTracker:FormatHitPct(entry.hits, attempts))
            ColourPct(row.pct, pctVal)
            row.spellName = displayName
            row.entry     = entry

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  oc, "TOPLEFT",  0, -(i - 1) * ROW_HEIGHT)
            row:SetPoint("TOPRIGHT", oc, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
            row:Show()
        end
        oc:SetHeight(outCount * ROW_HEIGHT)
        y = y - outCount * ROW_HEIGHT
    end

    -- Separator between sections
    y = y - 4
    f.outSep:ClearAllPoints()
    f.outSep:SetPoint("TOPLEFT",  f, "TOPLEFT",  PADDING,  y)
    f.outSep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PADDING, y)
    y = y - 5

    -- ── INCOMING SECTION ─────────────────────────────────────────────────────
    -- Section label
    f.inLabel:ClearAllPoints()
    f.inLabel:SetPoint("TOPLEFT",  f, "TOPLEFT",  PADDING, y)
    f.inLabel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PADDING, y)
    f.inLabel:SetHeight(SECTION_H)
    -- Column headers
    f.inColPct:ClearAllPoints()
    f.inColPct:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PADDING, y)
    f.inColPct:SetWidth(52)
    f.inColTries:ClearAllPoints()
    f.inColTries:SetPoint("TOPRIGHT", f.inColPct, "TOPLEFT", -4, 0)
    f.inColTries:SetWidth(52)
    y = y - SECTION_H - 2

    -- Incoming rows or empty label
    local ic = f.inContainer
    ic:ClearAllPoints()
    ic:SetPoint("TOPLEFT",  f, "TOPLEFT",  PADDING, y)
    ic:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PADDING, y)

    if inCount == 0 then
        f.inEmpty:ClearAllPoints()
        f.inEmpty:SetPoint("TOPLEFT",  ic, "TOPLEFT",  0, 0)
        f.inEmpty:SetPoint("TOPRIGHT", ic, "TOPRIGHT", 0, 0)
        f.inEmpty:Show()
        ic:SetHeight(ROW_HEIGHT)
        y = y - ROW_HEIGHT
    else
        f.inEmpty:Hide()
        for i = 1, inCount do
            local sd       = inList[i]
            local entry    = sd.entry
            local row      = MakeRow(inRows, ic, i, ShowIncomingTooltip)
            local attempts = CCTracker:GetIncomingAttempts(entry)
            local avoided  = attempts - entry.received
            local pctVal   = attempts > 0 and (avoided / attempts) or 0

            local displayName = CCTracker:GetSpellDisplayName(entry.spellId, sd.name)
            row.icon:SetTexture(GetSpellTexture(entry.spellId) or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetWidth(nameW)
            row.name:SetText(displayName)
            row.tries:SetText("(" .. attempts .. ")")
            row.pct:SetText(CCTracker:FormatHitPct(avoided, attempts))
            ColourPct(row.pct, pctVal)
            row.spellName = displayName
            row.entry     = entry

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  ic, "TOPLEFT",  0, -(i - 1) * ROW_HEIGHT)
            row:SetPoint("TOPRIGHT", ic, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
            row:Show()
        end
        ic:SetHeight(inCount * ROW_HEIGHT)
        y = y - inCount * ROW_HEIGHT
    end

    -- Footer
    y = y - 4
    f.footerSep:ClearAllPoints()
    f.footerSep:SetPoint("TOPLEFT",  f, "TOPLEFT",  PADDING,  y)
    f.footerSep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PADDING, y)
    y = y - 16

    -- Totals line: outgoing + incoming
    local totalOutAtt, totalOutHits = 0, 0
    local totalInAtt,  totalInAvoid = 0, 0
    if session then
        for _, e in pairs(session.spells   or {}) do
            totalOutHits = totalOutHits + e.hits
            totalOutAtt  = totalOutAtt  + CCTracker:GetSpellAttempts(e)
        end
        for _, e in pairs(session.incoming or {}) do
            local att = CCTracker:GetIncomingAttempts(e)
            totalInAvoid = totalInAvoid + (att - e.received)
            totalInAtt   = totalInAtt   + att
        end
    end
    f.footerText:SetText(string.format(
        "Out: %d/%d (%s)   In: %d/%d avoided (%s)",
        totalOutHits, totalOutAtt, CCTracker:FormatHitPct(totalOutHits, totalOutAtt),
        totalInAvoid, totalInAtt,  CCTracker:FormatHitPct(totalInAvoid, totalInAtt)))
    f.footerText:ClearAllPoints()
    f.footerText:SetPoint("TOP",    f, "TOP",   0, y)
    f.footerText:SetPoint("LEFT",   f, "LEFT",  PADDING, 0)
    f.footerText:SetPoint("RIGHT",  f, "RIGHT", -PADDING, 0)

    y = y - PADDING
    -- Preserve the current (possibly resized) width; height snaps to content but
    -- never below WIDGET_MIN_H (adjust that constant at the top of this file).
    f:SetSize(f:GetWidth(), math.max(WIDGET_MIN_H, math.abs(y)))
end

-- ─── Initialise ──────────────────────────────────────────────────────────────

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    local ok, err = pcall(function()
        local f = BuildWidget()

        local s = CCTrackerDB.settings
        if s.widgetX and s.widgetY then
            f:ClearAllPoints()
            f:SetPoint(
                s.widgetPoint    or "CENTER",
                UIParent,
                s.widgetRelPoint or "CENTER",
                s.widgetX, s.widgetY)
        else
            f:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
        end

        local savedW = (s.widgetWidth and s.widgetWidth >= WIDGET_MIN_W) and s.widgetWidth or WIDGET_WIDTH
        f:SetSize(savedW, 80)
        f:Show()
        CCTracker_Widget:Refresh()
    end)
    if not ok then
        print("|cffff4444[CCTracker] Widget build ERROR:|r " .. tostring(err))
    else
        print("|cff00ff00[CCTracker]|r Loaded. /cct help for commands.")
    end
end)
