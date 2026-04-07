-- CCTracker_Session.lua
-- Session detection and lifecycle management

CCTracker_Session = {}

local sessionIdCounter = 0

-- ── Deferred arena/pvp session end (timer-based) ────────────────────────────
-- In TBC Anniversary both PLAYER_ENTERING_WORLD and ZONE_CHANGED_NEW_AREA fire with
-- instanceType="none" when the arena gate opens — identical to actually leaving the
-- arena.  We can't tell the two apart by event alone, so instead we wait a few
-- seconds: if CC activity fires in that window the player is still fighting and we
-- keep the session alive; otherwise we assume they've left and close it.
-- (C_Timer doesn't exist in TBC, so we use an OnUpdate frame.)

local ARENA_END_DELAY = 6     -- seconds to wait before confirming arena exit
local arenaEndSession = nil   -- session object waiting for confirmation; nil = idle
local arenaEndElapsed = 0

local arenaEndFrame = CreateFrame("Frame")
arenaEndFrame:Hide()
arenaEndFrame:SetScript("OnUpdate", function(self, dt)
    arenaEndElapsed = arenaEndElapsed + dt
    if arenaEndElapsed < ARENA_END_DELAY then return end

    self:Hide()
    local s        = arenaEndSession
    arenaEndSession = nil
    arenaEndElapsed = 0
    if not s then return end

    local _, iType = GetInstanceInfo()
    if (not iType or iType == "none") and CCTrackerDB.currentSession == s then
        CCTracker.Log("ArenaEndTimer: " .. ARENA_END_DELAY .. "s elapsed, confirming arena exit")
        CCTracker_Session:EndCurrentSession()
    else
        CCTracker.Log("ArenaEndTimer: back in instance or session changed — keeping session")
    end
end)

local function ScheduleArenaEnd(session)
    if arenaEndSession == session then return end  -- already scheduled for this session
    arenaEndSession = session
    arenaEndElapsed = 0
    arenaEndFrame:Show()
    CCTracker.Log("ArenaEnd: scheduled in " .. ARENA_END_DELAY .. "s")
end

local function CancelArenaEnd()
    if not arenaEndSession then return end
    arenaEndSession = nil
    arenaEndFrame:Hide()
    CCTracker.Log("ArenaEnd: cancelled (CC activity or re-entered instance)")
end

local function NewSessionId()
    sessionIdCounter = sessionIdCounter + 1
    return sessionIdCounter
end

local function GetZoneName()
    local sub = GetSubZoneText()
    if sub and sub ~= "" then return sub end
    return GetZoneText() or "Unknown"
end

-- Returns name, instanceType, difficultyID, mapID from GetInstanceInfo safely.
local function GetInstanceDetails()
    local iName, iType, diffID, _, _, _, _, mapID = GetInstanceInfo()
    return
        (iName and iName ~= "") and iName or GetZoneName(),
        iType  or "none",
        diffID or 1,
        mapID  or 0
end

-- Difficulty suffix appended to session names.
-- Only heroic dungeons get one in TBC — raids are implicitly sized by type.
local DIFF_SUFFIX = {
    -- party (5-man)
    [2] = " [H]",
}

-- Attempt to distinguish rated arenas from skirmishes via GetBattlefieldInfo.
-- Returns "arena_rated", "arena_skirmish", or "arena" (fallback if detection fails).
-- Wrapped in pcall because GetBattlefieldInfo can throw a Lua error in TBC
-- Anniversary when called from inside an arena instance.
local function DetectArenaType()
    local ok, result = pcall(function()
        for i = 1, 10 do
            local name, _, status, _, _, _, isRated = GetBattlefieldInfo(i)
            if name and (status == "active" or status == "confirm") then
                return isRated and "arena_rated" or "arena_skirmish"
            end
        end
        return "arena"
    end)
    if ok then
        return result or "arena"
    else
        CCTracker.Log("DetectArenaType: GetBattlefieldInfo error: " .. tostring(result))
        return "arena"
    end
end

local function StartSession(instanceType, mapID, difficultyID)
    -- End any previous session first
    CCTracker_Session:EndCurrentSession()

    local iName = GetInstanceDetails()   -- first return is the instance/zone name
    local suffix = (instanceType == "party") and (DIFF_SUFFIX[difficultyID] or "") or ""
    local sessionName = iName .. suffix

    -- For arenas, try to detect rated vs skirmish immediately.
    -- We also refine this later in OnBGSystemMsg when the match officially starts.
    local sessionType = instanceType
    if instanceType == "arena" then
        sessionType = DetectArenaType()
    end

    local session = {
        id           = NewSessionId(),
        type         = sessionType,
        char         = CCTracker:GetCharKey(),
        name         = sessionName,
        mapID        = mapID        or 0,
        difficultyID = difficultyID or 1,
        startTime    = time(),
        endTime      = nil,
        date         = date("%Y-%m-%d"),
        spells       = {},    -- outgoing CCs (player → enemy)
        incoming     = {},    -- incoming CCs (enemy → player)
    }

    CCTrackerDB.currentSession = session
    CCTracker.Log(string.format("Session START: type=%s name=%s mapID=%d diff=%d char=%s",
        sessionType, sessionName, mapID or 0, difficultyID or 1, session.char or "?"))

    if CCTracker_Widget  then CCTracker_Widget:Refresh() end
    if CCTracker_History then CCTracker_History:RefreshIfVisible() end
end

function CCTracker_Session:EndCurrentSession()
    local session = CCTrackerDB.currentSession
    if not session then return end

    CCTracker.Log("Session END: type=" .. session.type .. " name=" .. session.name)
    session.endTime = time()

    -- Only save sessions that had at least one CC attempt (outgoing or incoming)
    local hasData = false
    for _ in pairs(session.spells)            do hasData = true; break end
    if not hasData then
        for _ in pairs(session.incoming or {}) do hasData = true; break end
    end

    if hasData then
        table.insert(CCTrackerDB.sessions, session)
    end

    CCTrackerDB.currentSession = nil

    if CCTracker_Widget  then CCTracker_Widget:Refresh() end
    if CCTracker_History then CCTracker_History:RefreshIfVisible() end
end

function CCTracker_Session:OnEnterWorld()
    local iName, instanceType, difficultyID, mapID = GetInstanceDetails()
    CCTracker.Log(string.format("OnEnterWorld: type=%s mapID=%d diff=%d",
        instanceType, mapID, difficultyID))

    local current = CCTrackerDB.currentSession

    if instanceType == "none" then
        -- Open world / loading screen.
        -- World sessions: just update the zone label and keep accumulating.
        -- Dungeons and raids: keep alive (corpse run through open world).
        -- Arenas/BGs: schedule a delayed end — both PLAYER_ENTERING_WORLD and
        -- ZONE_CHANGED_NEW_AREA fire with "none" at gate-open, so we can't end
        -- immediately.  The timer fires after ARENA_END_DELAY seconds; CC activity
        -- during that window cancels it (player is still fighting).
        if current then
            local t = current.type
            if t == "arena" or t == "arena_rated" or t == "arena_skirmish" or t == "pvp" then
                ScheduleArenaEnd(current)
            elseif t == "world" then
                local newName = GetZoneName()
                current.name = newName
                CCTracker.Log("OnEnterWorld: world session zone -> " .. newName)
                if CCTracker_Widget then CCTracker_Widget:Refresh() end
            end
        end
        return
    end

    -- Entering an instance — cancel any pending arena end (was a false alarm).
    CancelArenaEnd()

    -- ── Entering an instance ─────────────────────────────────────────────────
    if current then
        -- Same instance + same type (e.g. returning after a corpse run)?
        local currentMapID = current.mapID or 0
        if currentMapID == mapID and current.type == instanceType and mapID ~= 0 then
            CCTracker.Log("OnEnterWorld: re-entering same instance, continuing session")
            -- Refresh the zone name in case the sub-zone changed.
            local suffix = (instanceType == "party") and (DIFF_SUFFIX[difficultyID] or "") or ""
            current.name = iName .. suffix
            if CCTracker_Widget  then CCTracker_Widget:Refresh() end
            return
        end
        -- Different instance — StartSession will call EndCurrentSession.
    end

    StartSession(instanceType, mapID, difficultyID)
end

-- Public: start a session if we don't have one yet.
-- For instanced content this fires on PLAYER_ENTERING_WORLD.
-- For open world this fires lazily on the first CC combat-log event.
function CCTracker_Session:TryStartFromInstance()
    if CCTrackerDB.currentSession then return end
    local iName, instanceType, difficultyID, mapID = GetInstanceDetails()
    if instanceType ~= "none" then
        CCTracker.Log("TryStartFromInstance: starting " .. instanceType)
        StartSession(instanceType, mapID, difficultyID)
    else
        -- Open world — start a world session lazily (first CC attempt triggers this)
        CCTracker.Log("TryStartFromInstance: starting world session in " .. (GetZoneText() or "?"))
        StartSession("world", 0, 0)
    end
end

function CCTracker_Session:CancelPendingEnd()
    CancelArenaEnd()
end

function CCTracker_Session:OnZoneChanged()
    local iName, instanceType, difficultyID, mapID = GetInstanceDetails()
    local current = CCTrackerDB.currentSession

    -- If we're confirmed back inside an instance, the arena-end timer was a false
    -- alarm (gate-open).  Cancel it so the session is kept.
    if instanceType ~= "none" then
        CancelArenaEnd()
    end

    if instanceType ~= "none" and not current then
        -- Session wasn't created during PLAYER_ENTERING_WORLD (GetInstanceInfo timing).
        -- ZONE_CHANGED_NEW_AREA fires slightly later and is reliable — start now.
        CCTracker.Log("OnZoneChanged: no session in " .. instanceType .. " — starting")
        StartSession(instanceType, mapID, difficultyID)
        return
    end

    if current then
        if instanceType == "none" and current.type == "world" then
            -- Moved to a different open-world zone — update the location label so
            -- history shows where the last CC activity was, but keep accumulating.
            local newName = GetZoneName()
            if newName ~= "" and newName ~= current.name then
                current.name = newName
                CCTracker.Log("OnZoneChanged: world session zone -> " .. newName)
                if CCTracker_Widget then CCTracker_Widget:Refresh() end
            end
            return
        end

        -- Update session name if the sub-zone label changed (instances only).
        if instanceType ~= "none" then
            local suffix = (instanceType == "party") and (DIFF_SUFFIX[difficultyID] or "") or ""
            local newName = iName .. suffix
            if newName ~= "" and newName ~= current.name then
                current.name = newName
            end
        end
    end
end

function CCTracker_Session:OnBattlefieldStatus()
    -- UPDATE_BATTLEFIELD_STATUS fires on queue changes and BG end.
    -- We rely on PLAYER_ENTERING_WORLD for actual session start/end;
    -- this hook is here for future extension (e.g. detecting BG result).
end

-- Arena match start announcement
local ARENA_START_MSG = "The Arena battle has begun!"

function CCTracker_Session:OnBGSystemMsg(msg)
    if msg and msg:find(ARENA_START_MSG) then
        -- Arena combat officially started; session should already be open from PLAYER_ENTERING_WORLD.
        local current = CCTrackerDB.currentSession
        local t = current and current.type
        local _, iType, _, _, _, _, _, iMapID = GetInstanceInfo()
        CCTracker.Log(string.format(
            "ARENA_START_MSG: session=%s iType=%s mapID=%s timerActive=%s",
            current and (t.."/"..current.name) or "NIL",
            tostring(iType), tostring(iMapID),
            tostring(arenaEndSession ~= nil)))
        if current and (t == "arena" or t == "arena_rated" or t == "arena_skirmish") then
            -- Re-detect rated/skirmish now that the match is live (more reliable than at load-in).
            local detected = DetectArenaType()
            if detected ~= "arena" then
                current.type = detected
                CCTracker.Log("Arena type refined: " .. detected)
            end
            -- Reset the start time to actual match start if no CCs yet.
            local hasData = false
            for _ in pairs(current.spells) do hasData = true; break end
            if not hasData then
                current.startTime = time()
            end
        end
    end
end

