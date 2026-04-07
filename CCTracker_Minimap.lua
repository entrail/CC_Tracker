-- CCTracker_Minimap.lua
-- Minimap button that opens/closes the history window

CCTracker_Minimap = {}

local button
local isDragging = false

local function UpdatePosition()
    local angle = math.rad(CCTrackerDB.settings.minimapAngle or 225)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER",
        80 * math.cos(angle),
        80 * math.sin(angle))
end

local function CreateMinimapButton()
    CCTracker.Log("CreateMinimapButton: start")
    button = CreateFrame("Button", "CCTrackerMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)

    -- Circular backdrop
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    bg:SetSize(52, 52)
    bg:SetPoint("CENTER")

    local bgInner = button:CreateTexture(nil, "BACKGROUND")
    bgInner:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bgInner:SetSize(24, 24)
    bgInner:SetPoint("CENTER")

    -- Icon (Polymorph — iconic CC spell)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Spell_Nature_Polymorph")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Highlight
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hl:SetSize(32, 32)
    hl:SetPoint("CENTER")

    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    -- Tooltip
    button:SetScript("OnEnter", function(self)
        if isDragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("CCTracker", 1, 1, 1)
        GameTooltip:AddLine("Left-click: Open/Close history", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: Show/Hide widget", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: Reposition", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Clicks
    button:SetScript("OnClick", function(self, btn)
        if isDragging then return end
        if btn == "LeftButton" then
            CCTracker.Log("Minimap: left-click → Toggle history")
            CCTracker_History:Toggle()
        elseif btn == "RightButton" then
            local shown = CCTracker_Widget.frame and CCTracker_Widget.frame:IsShown()
            CCTracker.Log("Minimap: right-click → widget " .. (shown and "hide" or "show"))
            if shown then
                CCTracker_Widget.frame:Hide()
            else
                if CCTracker_Widget.frame then
                    CCTracker_Widget.frame:Show()
                    CCTracker_Widget:Refresh()
                end
            end
        end
    end)

    -- Dragging along the minimap rim
    local function OnDragUpdate(self)
        local mx, my = Minimap:GetCenter()
        local scale  = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / scale, cy / scale
        CCTrackerDB.settings.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
        UpdatePosition()
    end

    button:SetScript("OnDragStart", function(self)
        isDragging = true
        GameTooltip:Hide()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)

    button:SetScript("OnDragStop", function(self)
        isDragging = false
        self:SetScript("OnUpdate", nil)
    end)

    UpdatePosition()
    CCTracker.Log("CreateMinimapButton: done")
end

-- Called after ADDON_LOADED via CCTracker widget init chain
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    CreateMinimapButton()
end)

function CCTracker_Minimap:UpdatePosition()
    if button then UpdatePosition() end
end
