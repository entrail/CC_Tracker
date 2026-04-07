-- CCTracker_Session.lua
-- Session detection and lifecycle management

CCTracker_Session = {}

local sessionIdCounter = 0

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
-- GetBattlefieldInfo(i) in TBC returns:
--   name, canQueue, status, minLevel, maxLevel, numGroupMembersQueued, isRated
local function DetectArenaType()
    for i = 1, 10 do
        local name, _, status, _, _, _, isRated = GetBattlefieldInfo(i)
        if name and (status == "active" or status == "confirm") then
            return isRated and "arena_rated" or "arena_skirmish"
        end
    end
    return "arena"  -- fallback when GetBattlefieldInfo cannot determine the type
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

    -- Respect the per-type tracking toggles set in the options panel.
    -- "arena" is the fallback when rated/skirmish cannot be detected yet;
    -- allow it if either arena sub-type is enabled.
    do
        local track = CCTrackerDB.settings and CCTrackerDB.settings.track
        if track then
            local enabled
            if sessionType == "arena" then
                enabled = track.arena_rated ~= false or track.arena_skirmish ~= false
            else
                enabled = track[sessionType] ~= false
            end
            if not enabled then
                CCTracker.Log("StartSession: type=" .. tostring(sessionType) .. " disabled in options — skipping")
                return
            end
        end
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
        -- Arenas and BGs: leaving to open world means the match is over — end immediately.
        -- World sessions: just update the zone label and keep accumulating.
        -- Dungeons and raids: keep alive (corpse run through open world).
        if current then
            local t = current.type
            if t == "arena" or t == "arena_rated" or t == "arena_skirmish" or t == "pvp" then
                self:EndCurrentSession()
            elseif t == "world" then
                local newName = GetZoneName()
                current.name = newName
                CCTracker.Log("OnEnterWorld: world session zone -> " .. newName)
                if CCTracker_Widget then CCTracker_Widget:Refresh() end
            end
        end
        return
    end

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

function CCTracker_Session:OnZoneChanged()
    local iName, instanceType, difficultyID, mapID = GetInstanceDetails()
    local current = CCTrackerDB.currentSession

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

        -- Update session name if the sub-zone label changed (instances).
        local suffix = (instanceType == "party") and (DIFF_SUFFIX[difficultyID] or "") or ""
        local newName = iName .. suffix
        if newName ~= "" and newName ~= current.name then
            current.name = newName
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

