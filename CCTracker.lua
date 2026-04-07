-- CCTracker.lua
-- Core addon: initialization, combat log parsing, data management

CCTracker = {}

-- Upvalues
local playerGUID
local petGUID       -- player's active pet (Succubus, Felhunter, Hunter pet, etc.)
local totemGUIDs = {}  -- GUIDs of the player's active totems (cleared on UNIT_DIED/zone change)
local charKey       -- "CharName-Realm", used to tag sessions per character
local HOSTILE_FLAG = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040

-- Tracks active defensive buffs on all units: [unitGUID][spellId] = true
CCTracker.enemyBuffs = {}

-- ─── Debug / logging system ──────────────────────────────────────────────────

CCTracker.debugEnabled = false

local LOG_MAX = 1000  -- max entries kept in SavedVariables

-- CCTracker.Log(msg)
--   Always appends to the persistent SavedVariables log (CCTrackerLog).
--   Only prints to chat when debugEnabled = true.
--   The log file on disk is:
--     WTF\Account\<account>\SavedVariables\CCTracker.lua  (written on /reload or logout)
function CCTracker.Log(msg)
    local entry = string.format("[%s] %s", date("%Y-%m-%d %H:%M:%S"), tostring(msg))

    -- Persistent log (always, regardless of debug flag)
    if CCTrackerLog then
        CCTrackerLog[#CCTrackerLog + 1] = entry
        -- Trim oldest entries when over the cap
        if #CCTrackerLog > LOG_MAX then
            table.remove(CCTrackerLog, 1)
        end
    end

    -- Chat output only when debug is enabled
    if CCTracker.debugEnabled then
        print("|cff00ff00[CCT]|r " .. tostring(msg))
    end
end

-- ─── SavedVariables structure ───────────────────────────────────────────────
-- CCTrackerDB = {
--   sessions = { [i] = sessionObj, ... },
--   currentSession = sessionObj or nil,
--   settings = { widgetX, widgetY, widgetPoint, widgetRelPoint, minimapAngle },
-- }
--
-- sessionObj = {
--   id        = number,
--   type      = "arena"|"pvp"|"party"|"raid"|"world",
--   name      = string,   -- zone name
--   startTime = number,   -- time()
--   endTime   = number,   -- time(), nil while active
--   date      = string,   -- "YYYY-MM-DD"
--   spells    = { [spellName] = spellEntry },
-- }
--
-- spellEntry = {
--   spellId = number,
--   hits    = number,
--   misses  = { [missType] = count, ... },
--   wasted  = { [defensiveName] = count, ... },
-- }
-- ────────────────────────────────────────────────────────────────────────────

local function InitDB()
    -- Log table must be ready before any CCTracker.Log() calls
    CCTrackerLog = CCTrackerLog or {}

    CCTrackerDB = CCTrackerDB or {}
    CCTrackerDB.sessions = CCTrackerDB.sessions or {}
    CCTrackerDB.settings = CCTrackerDB.settings or {
        minimapAngle = 225,
    }
    -- Per-type tracking flags: false = don't record future sessions of that type.
    -- We merge-in defaults so existing installs get all types enabled on upgrade.
    CCTrackerDB.settings.track = CCTrackerDB.settings.track or {}
    local trackDefaults = {
        arena_rated = true, arena_skirmish = true,
        pvp = true, party = true, raid = true, world = true,
    }
    for k, v in pairs(trackDefaults) do
        if CCTrackerDB.settings.track[k] == nil then
            CCTrackerDB.settings.track[k] = v
        end
    end
    -- History window type-filter state (all enabled by default)
    CCTrackerDB.settings.historyFilter = CCTrackerDB.settings.historyFilter or {}
    local historyFilterDefaults = {
        arena_rated = true, arena_skirmish = true,
        pvp = true, party = true, raid = true, world = true,
    }
    for k, v in pairs(historyFilterDefaults) do
        if CCTrackerDB.settings.historyFilter[k] == nil then
            CCTrackerDB.settings.historyFilter[k] = v
        end
    end
    -- Close any orphaned session from a previous crash/logout.
    -- Also stamp the char key on it (charKey may not be set yet at ADDON_LOADED,
    -- so we tag it during the next PLAYER_LOGIN via a deferred pass instead;
    -- for now store a sentinel so it can be patched below).
    if CCTrackerDB.currentSession then
        CCTrackerDB.currentSession.endTime = CCTrackerDB.currentSession.endTime or time()
        table.insert(CCTrackerDB.sessions, CCTrackerDB.currentSession)
        CCTrackerDB.currentSession = nil
    end

    -- Mark the start of a new game session in the log
    CCTracker.Log("========== SESSION START ==========")
    CCTracker.Log("DB ready. Saved sessions: " .. #CCTrackerDB.sessions .. "  Log entries: " .. #CCTrackerLog)
end

function CCTracker:GetCurrentSession()
    return CCTrackerDB.currentSession
end

function CCTracker:GetOrCreateSpellEntry(session, spellName, spellId)
    if not session.spells[spellName] then
        session.spells[spellName] = {
            spellId = spellId,
            hits    = 0,
            misses  = {},
            wasted  = {},
        }
    end
    -- Always prefer a non-zero spellId for icon lookup
    if spellId and spellId > 0 then
        session.spells[spellName].spellId = spellId
    end
    return session.spells[spellName]
end

-- Returns a list of defensive spell info tables active on destGUID
local function GetActiveDefensives(destGUID)
    local buffs = CCTracker.enemyBuffs[destGUID]
    if not buffs then return nil end
    local found
    for spellId in pairs(buffs) do
        local def = CCTracker_DefensiveSpells[spellId]
        if def then
            found = found or {}
            found[#found + 1] = def
        end
    end
    return found
end

-- ─── Outgoing CC recording ───────────────────────────────────────────────────

function CCTracker:RecordHit(spellName, spellId)
    local session = self:GetCurrentSession()
    if not session then return end
    local entry = self:GetOrCreateSpellEntry(session, spellName, spellId)
    entry.hits = entry.hits + 1
    CCTracker.Log("OUT HIT: " .. spellName .. " (total: " .. entry.hits .. ")")
    if CCTracker_Widget  then CCTracker_Widget:Refresh() end
    if CCTracker_History then CCTracker_History:RefreshIfVisible() end
end

function CCTracker:RecordMiss(spellName, spellId, missType, destGUID)
    local session = self:GetCurrentSession()
    if not session then return end
    local entry = self:GetOrCreateSpellEntry(session, spellName, spellId)
    entry.misses[missType] = (entry.misses[missType] or 0) + 1
    CCTracker.Log("OUT MISS: " .. spellName .. " (" .. tostring(missType) .. ")")

    local defensives = GetActiveDefensives(destGUID)
    if defensives then
        for _, def in ipairs(defensives) do
            entry.wasted[def.name] = (entry.wasted[def.name] or 0) + 1
            CCTracker.Log("  wasted due to: " .. def.name)
        end
    end

    if CCTracker_Widget  then CCTracker_Widget:Refresh() end
    if CCTracker_History then CCTracker_History:RefreshIfVisible() end
end

-- ─── Incoming CC recording ────────────────────────────────────────────────────

function CCTracker:GetOrCreateIncomingEntry(session, spellName, spellId)
    session.incoming = session.incoming or {}
    if not session.incoming[spellName] then
        session.incoming[spellName] = {
            spellId  = spellId,
            received = 0,   -- CC actually landed on the player
            avoided  = {},  -- CC resisted/dodged/immune by the player
        }
    end
    if spellId and spellId > 0 then
        session.incoming[spellName].spellId = spellId
    end
    return session.incoming[spellName]
end

function CCTracker:RecordIncomingHit(spellName, spellId)
    local session = self:GetCurrentSession()
    if not session then return end
    local entry = self:GetOrCreateIncomingEntry(session, spellName, spellId)
    entry.received = entry.received + 1
    CCTracker.Log("IN HIT: " .. spellName .. " (received: " .. entry.received .. ")")
    if CCTracker_Widget  then CCTracker_Widget:Refresh() end
    if CCTracker_History then CCTracker_History:RefreshIfVisible() end
end

function CCTracker:RecordIncomingMiss(spellName, spellId, missType)
    local session = self:GetCurrentSession()
    if not session then return end
    local entry = self:GetOrCreateIncomingEntry(session, spellName, spellId)
    entry.avoided[missType] = (entry.avoided[missType] or 0) + 1
    CCTracker.Log("IN AVOIDED: " .. spellName .. " (" .. tostring(missType) .. ")")
    if CCTracker_Widget  then CCTracker_Widget:Refresh() end
    if CCTracker_History then CCTracker_History:RefreshIfVisible() end
end

-- ─── Utility ────────────────────────────────────────────────────────────────

function CCTracker:GetSpellAttempts(spellEntry)
    local total = spellEntry.hits
    for _, count in pairs(spellEntry.misses) do
        total = total + count
    end
    return total
end

function CCTracker:GetSpellMissTotal(spellEntry)
    local total = 0
    for _, count in pairs(spellEntry.misses) do
        total = total + count
    end
    return total
end

function CCTracker:GetIncomingAttempts(entry)
    local total = entry.received
    for _, count in pairs(entry.avoided) do
        total = total + count
    end
    return total
end

function CCTracker:FormatHitPct(hits, attempts)
    if attempts == 0 then return "N/A" end
    return string.format("%.0f%%", hits / attempts * 100)
end

function CCTracker:FormatDuration(seconds)
    if not seconds then return "?" end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    if m > 0 then
        return string.format("%dm %ds", m, s)
    else
        return string.format("%ds", s)
    end
end

-- Sorts a list of { name, entry } by ccLevel (hard→medium→light),
-- then by spell attempts descending within the same level.
-- Works for both outgoing (entry.hits+misses) and incoming (entry.received+avoided).
function CCTracker:SortCCSpellList(list, isIncoming)
    local LVL = CCTracker_CCLevelOrder
    table.sort(list, function(a, b)
        local la = LVL[(CCTracker_CCSpells[a.name] or {}).ccLevel] or 99
        local lb = LVL[(CCTracker_CCSpells[b.name] or {}).ccLevel] or 99
        if la ~= lb then return la < lb end
        local atA = isIncoming and CCTracker:GetIncomingAttempts(a.entry) or CCTracker:GetSpellAttempts(a.entry)
        local atB = isIncoming and CCTracker:GetIncomingAttempts(b.entry) or CCTracker:GetSpellAttempts(b.entry)
        if atA ~= atB then return atA > atB end
        return a.name < b.name
    end)
end

-- Returns the current character key "Name-Realm".
function CCTracker:GetCharKey()
    return charKey or (UnitName("player") .. "-" .. GetRealmName())
end

-- Returns sessions filtered by type, date, and character (all newest-first).
-- charFilter: nil or "current" = current character only; "all" = all characters.
-- typeFilter: "arena_all" matches all three arena sub-types.
-- The active currentSession is always prepended if it passes the filters, so
-- the history window reflects live world-session data without waiting for logout.
function CCTracker:GetFilteredSessions(typeFilter, dateFilter, charFilter)
    local result = {}
    local allSessions = CCTrackerDB.sessions or {}
    local myChar = CCTracker:GetCharKey()

    local function passes(s)
        -- Character filter (default: current char; legacy sessions without .char shown for current char only)
        local charMatch
        if charFilter == "all" then
            charMatch = true
        else
            charMatch = (not s.char or s.char == myChar)
        end

        -- Type filter: accepts either a multi-select table {type=bool} or a legacy string.
        local typeMatch
        if type(typeFilter) == "table" then
            -- Multi-select table from the history dropdown.
            local t = s.type
            if t == "arena" then
                -- Legacy sessions recorded before rated/skirmish distinction existed:
                -- show them if either arena sub-type is enabled.
                typeMatch = typeFilter.arena_rated or typeFilter.arena_skirmish or false
            else
                typeMatch = typeFilter[t] == true
            end
        elseif not typeFilter or typeFilter == "all" then
            typeMatch = true
        elseif typeFilter == "arena_all" then
            typeMatch = (s.type == "arena" or s.type == "arena_rated" or s.type == "arena_skirmish")
        else
            typeMatch = (s.type == typeFilter)
        end

        -- Date filter
        local dateMatch = (not dateFilter or dateFilter == "all" or s.date == dateFilter)

        return charMatch and typeMatch and dateMatch
    end

    -- Active session appears first (chronologically newest); endTime is nil so
    -- the list entry shows "active" rather than a duration.
    local current = CCTrackerDB.currentSession
    if current and passes(current) then
        result[1] = current
    end

    -- Saved sessions, newest first
    for i = #allSessions, 1, -1 do
        local s = allSessions[i]
        if passes(s) then
            result[#result + 1] = s
        end
    end
    return result
end

-- ─── Combat log handling ─────────────────────────────────────────────────────

local function OnCombatLog()
    local _, subevent, _,
        sourceGUID, _, _, _,
        destGUID, destName, destFlags, _,
        spellId, spellName, _, p15 = CombatLogGetCurrentEventInfo()

    -- Clear buff table when a unit dies; also remove from totem set if relevant
    if subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
        CCTracker.enemyBuffs[destGUID] = nil
        totemGUIDs[destGUID] = nil
        return
    end

    -- Register totems summoned by the player so their SPELL_AURA_APPLIED events
    -- are attributed to the player (totems appear as their own GUID in the combat log).
    -- SPELL_CREATE is checked too in case the client uses it for totem objects.
    if (subevent == "SPELL_SUMMON" or subevent == "SPELL_CREATE") and sourceGUID == playerGUID then
        if destName and destName:find("Totem", 1, true) then
            totemGUIDs[destGUID] = true
            CCTracker.Log("Totem registered: " .. destName .. " guid=" .. tostring(destGUID))
        end
        return
    end

    -- Track defensive buffs on ALL units (from any caster)
    if spellId and CCTracker_DefensiveSpells[spellId] then
        if subevent == "SPELL_AURA_APPLIED" then
            CCTracker.enemyBuffs[destGUID] = CCTracker.enemyBuffs[destGUID] or {}
            CCTracker.enemyBuffs[destGUID][spellId] = true
        elseif subevent == "SPELL_AURA_REMOVED" then
            if CCTracker.enemyBuffs[destGUID] then
                CCTracker.enemyBuffs[destGUID][spellId] = nil
            end
        end
    end

    if not spellName then return end
    -- Prefer spell-ID lookup (language-independent); fall back to spell name.
    local canonicalName = (spellId and CCTracker_CCSpellsByID[spellId]) or spellName
    local spellData = CCTracker_CCSpells[canonicalName]
    if not spellData then return end

    -- If PLAYER_ENTERING_WORLD fired before GetInstanceInfo() was ready, no session
    -- was created.  The first relevant CC spell we see is a reliable signal that we're
    -- inside an instance — create the session now if we still don't have one.
    if not CCTrackerDB.currentSession then
        CCTracker_Session:TryStartFromInstance()
        if not CCTrackerDB.currentSession then return end   -- open world, skip
    end

    -- ── Outgoing: player (or player's pet/totem) cast on an enemy ────────────
    if (sourceGUID == playerGUID or (petGUID and sourceGUID == petGUID) or totemGUIDs[sourceGUID])
    and destFlags and bit.band(destFlags, HOSTILE_FLAG) > 0 then

        if spellData.ccType == "aura" then
            if (subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH")
            and p15 == "DEBUFF" then
                CCTracker:RecordHit(canonicalName, spellId)
            elseif subevent == "SPELL_MISSED" then
                CCTracker:RecordMiss(canonicalName, spellId, p15, destGUID)
            end

        elseif spellData.ccType == "interrupt" then
            if subevent == "SPELL_INTERRUPT" then
                CCTracker:RecordHit(canonicalName, spellId)
            elseif subevent == "SPELL_MISSED" then
                CCTracker:RecordMiss(canonicalName, spellId, p15, destGUID)
            end
        end
    end

    -- ── Incoming: enemy cast on the player ───────────────────────────────────
    if destGUID == playerGUID and sourceGUID ~= playerGUID then

        if spellData.ccType == "aura" then
            if (subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH")
            and p15 == "DEBUFF" then
                CCTracker:RecordIncomingHit(canonicalName, spellId)
            elseif subevent == "SPELL_MISSED" then
                -- p15 = missType — why the CC failed to land on the player
                CCTracker:RecordIncomingMiss(canonicalName, spellId, p15)
            end

        elseif spellData.ccType == "interrupt" then
            if subevent == "SPELL_INTERRUPT" then
                CCTracker:RecordIncomingHit(canonicalName, spellId)
            elseif subevent == "SPELL_MISSED" then
                CCTracker:RecordIncomingMiss(canonicalName, spellId, p15)
            end
        end
    end
end

-- ─── Main frame & event registration ────────────────────────────────────────

local frame = CreateFrame("Frame", "CCTrackerMainFrame")

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_PET")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "CCTracker" then
            InitDB()
            CCTracker.Log("ADDON_LOADED fired")
        end

    elseif event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
        petGUID    = UnitGUID("pet")
        charKey    = UnitName("player") .. "-" .. GetRealmName()
        CCTracker.Log("PLAYER_LOGIN fired. playerGUID=" .. tostring(playerGUID) .. " char=" .. charKey)

    elseif event == "PLAYER_ENTERING_WORLD" then
        playerGUID = playerGUID or UnitGUID("player")
        petGUID    = UnitGUID("pet")
        totemGUIDs = {}
        CCTracker.enemyBuffs = {}
        local _, iType = GetInstanceInfo()
        CCTracker.Log("PLAYER_ENTERING_WORLD. instanceType=" .. tostring(iType) .. " zone=" .. tostring(GetZoneText()))
        CCTracker_Session:OnEnterWorld()

    elseif event == "UNIT_PET" then
        local unitId = ...
        if unitId == "player" then
            petGUID = UnitGUID("pet")
            CCTracker.Log("UNIT_PET: petGUID=" .. tostring(petGUID))
        end

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        CCTracker.Log("ZONE_CHANGED -> " .. tostring(GetZoneText()) .. " / " .. tostring(GetSubZoneText()))
        CCTracker_Session:OnZoneChanged()

    elseif event == "UPDATE_BATTLEFIELD_STATUS" then
        CCTracker.Log("UPDATE_BATTLEFIELD_STATUS")
        CCTracker_Session:OnBattlefieldStatus()

    elseif event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then
        local msg = ...
        CCTracker.Log("BG_SYSTEM_NEUTRAL: " .. tostring(msg))
        CCTracker_Session:OnBGSystemMsg(msg)

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    end
end)

-- ─── Slash commands ───────────────────────────────────────────────────────────

local function PrintHelp()
    print("|cff00ff00CCTracker|r commands:")
    print("  /cct debug      — toggle debug chat output")
    print("  /cct show       — force show the widget")
    print("  /cct hide       — hide the widget")
    print("  /cct history    — open/close the history window")
    print("  /cct reset      — reset widget to centre of screen")
    print("  /cct status     — show current session info")
    print("  /cct test       — inject fake session data for UI testing")
    print("  /cct log [N]    — print last N log entries to chat (default 20)")
    print("  /cct log clear  — clear the persistent log")
    print("  /cct help       — show this help")
    print("|cffaaaaaa(Log file: WTF/Account/<name>/SavedVariables/CCTracker.lua)|r")
end

SLASH_CCTRACKER1 = "/cctracker"
SLASH_CCTRACKER2 = "/cct"
SlashCmdList["CCTRACKER"] = function(msg)
    local cmd = strtrim(msg or ""):lower()

    if cmd == "debug" then
        CCTracker.debugEnabled = not CCTracker.debugEnabled
        print("|cff00ff00[CCTracker]|r Debug " .. (CCTracker.debugEnabled and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
        if CCTracker.debugEnabled then
            local w = CCTracker_Widget and CCTracker_Widget.frame
            CCTracker.Log("Widget frame: " .. tostring(w))
            if w then
                CCTracker.Log("Widget shown: " .. tostring(w:IsShown()))
                CCTracker.Log("Widget pos: " .. tostring(w:GetLeft()) .. ", " .. tostring(w:GetTop()))
            end
            local h = CCTracker_History and CCTracker_History.mainFrame
            CCTracker.Log("History frame: " .. tostring(h))
            if h then CCTracker.Log("History shown: " .. tostring(h:IsShown())) end
            local s = CCTrackerDB.currentSession
            CCTracker.Log("Current session: " .. (s and (s.type .. " / " .. s.name) or "none"))
            CCTracker.Log("Saved sessions: " .. #CCTrackerDB.sessions)
        end

    elseif cmd == "show" then
        local w = CCTracker_Widget and CCTracker_Widget.frame
        if w then
            w:Show()
            CCTracker_Widget:Refresh()
            print("|cff00ff00[CCTracker]|r Widget shown.")
        else
            print("|cff00ff00[CCTracker]|r Widget frame not created yet.")
        end

    elseif cmd == "hide" then
        local w = CCTracker_Widget and CCTracker_Widget.frame
        if w then w:Hide() end
        print("|cff00ff00[CCTracker]|r Widget hidden.")

    elseif cmd == "history" then
        if CCTracker_History then
            CCTracker_History:Toggle()
        else
            print("|cff00ff00[CCTracker]|r History module not loaded.")
        end

    elseif cmd == "reset" then
        local w = CCTracker_Widget and CCTracker_Widget.frame
        if w then
            w:ClearAllPoints()
            w:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
            CCTrackerDB.settings.widgetX        = nil
            CCTrackerDB.settings.widgetY        = nil
            CCTrackerDB.settings.widgetPoint    = nil
            CCTrackerDB.settings.widgetRelPoint = nil
            CCTrackerDB.settings.widgetWidth    = nil
            w:SetWidth(280)   -- back to default width
            w:Show()
            CCTracker_Widget:Refresh()
            print("|cff00ff00[CCTracker]|r Widget position reset.")
        end

    elseif cmd == "status" then
        local s = CCTrackerDB.currentSession
        if s then
            print(string.format("|cff00ff00[CCTracker]|r Active: %s — %s (started %s)",
                CCTracker_SessionTypeNames[s.type] or s.type,
                s.name, s.date))
            local total, hits = 0, 0
            for _, e in pairs(s.spells) do
                hits  = hits  + e.hits
                total = total + CCTracker:GetSpellAttempts(e)
            end
            print(string.format("  CCs: %d/%d (%s)", hits, total, CCTracker:FormatHitPct(hits, total)))
        else
            print("|cff00ff00[CCTracker]|r No active session. Saved sessions: " .. #CCTrackerDB.sessions)
        end

    elseif cmd == "test" then
        -- Inject a fake Arena session for UI testing
        local fake = {
            id        = 9999,
            type      = "arena",
            name      = "Test Arena",
            startTime = time() - 300,
            endTime   = time(),
            date      = date("%Y-%m-%d"),
            spells    = {
                ["Polymorph"] = {
                    spellId = 118,
                    hits    = 7,
                    misses  = { RESIST = 2, IMMUNE = 1 },
                    wasted  = { ["Ice Block"] = 1 },
                },
                ["Frost Nova"] = {
                    spellId = 122,
                    hits    = 3,
                    misses  = { MISS = 1 },
                    wasted  = {},
                },
                ["Counterspell"] = {
                    spellId = 2139,
                    hits    = 4,
                    misses  = {},
                    wasted  = {},
                },
            },
            incoming = {
                ["Kidney Shot"] = {
                    spellId  = 408,
                    received = 3,
                    avoided  = { RESIST = 1 },
                },
                ["Blind"] = {
                    spellId  = 2094,
                    received = 1,
                    avoided  = { IMMUNE = 2 },
                },
            },
        }
        table.insert(CCTrackerDB.sessions, fake)
        CCTrackerDB.currentSession = {
            id        = 9998,
            type      = "arena",
            name      = "Current Test Arena",
            startTime = time() - 60,
            endTime   = nil,
            date      = date("%Y-%m-%d"),
            spells    = {
                ["Polymorph"] = {
                    spellId = 118,
                    hits    = 2,
                    misses  = { RESIST = 1 },
                    wasted  = {},
                },
            },
        }
        print("|cff00ff00[CCTracker]|r Test data injected. Widget and history should now show data.")
        if CCTracker_Widget and CCTracker_Widget.frame then
            CCTracker_Widget.frame:Show()
            CCTracker_Widget:Refresh()
        end
        if CCTracker_History then CCTracker_History:RefreshIfVisible() end

    elseif cmd == "log clear" then
        local count = CCTrackerLog and #CCTrackerLog or 0
        CCTrackerLog = {}
        CCTracker.Log("Log cleared by user (" .. count .. " entries removed)")
        print("|cff00ff00[CCTracker]|r Log cleared (" .. count .. " entries removed).")

    elseif cmd:sub(1, 3) == "log" then
        -- /cct log        → last 20
        -- /cct log 50     → last 50
        local nStr = strtrim(cmd:sub(4))
        local n    = tonumber(nStr) or 20
        n = math.max(1, math.min(n, 200))  -- clamp 1-200

        local log = CCTrackerLog or {}
        local total = #log
        if total == 0 then
            print("|cff00ff00[CCTracker]|r Log is empty.")
        else
            local start = math.max(1, total - n + 1)
            print(string.format("|cff00ff00[CCTracker]|r Showing entries %d-%d of %d:", start, total, total))
            for i = start, total do
                print("|cffaaaaaa" .. log[i] .. "|r")
            end
        end

    else
        PrintHelp()
    end
end
