local addonName = ...

-- Keybinding Category & Action Strings for WoW Options > Keybindings > AddOns
_G["BINDING_HEADER_INNERVATETRACKER"] = "Innervate Tracker"
_G["BINDING_NAME_INNERVATETRACKER_WHISPER1"] = "Whisper Highlighted Druid #1"
_G["BINDING_NAME_INNERVATETRACKER_WHISPER2"] = "Whisper Highlighted Druid #2"
_G["BINDING_NAME_INNERVATETRACKER_WHISPER3"] = "Whisper Highlighted Druid #3"

-- Helper to safely get spell name across client versions
local function GetSpellName(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        return info and info.name
    elseif GetSpellInfo then
        return (GetSpellInfo(id))
    end
    return nil
end

local INNERVATE_NAME = GetSpellName(29166) or "Innervate"
local INNERVATE_CD = 360            -- Baseline CD: 6 minutes
local INNERVATE_BUFF_DURATION = 20   -- Buff duration: 20 seconds

-- Class color hex lookup for tooltips
local CLASS_COLORS = {
    PRIEST  = { r = 1.0,  g = 1.0,  b = 1.0  }, -- White
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, -- Pink
    SHAMAN  = { r = 0.0,  g = 0.44, b = 0.87 }, -- Blue
    MAGE    = { r = 0.25, g = 0.78, b = 0.92 }, -- Light Blue
    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 }, -- Purple
    DRUID   = { r = 1.0,  g = 0.49, b = 0.04 }, -- Orange
    HUNTER  = { r = 0.67, g = 0.83, b = 0.45 }, -- Green
    ROGUE   = { r = 1.0,  g = 0.96, b = 0.41 }, -- Yellow
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, -- Brown
}

-- Slot highlight colors for up to 3 highlighted Druids
local SLOT_COLORS = {
    [1] = { r = 1.0, g = 0.82, b = 0.0,  a = 0.35, hex = "ffd100" }, -- Slot 1: Gold / Yellow
    [2] = { r = 0.1, g = 0.80, b = 1.0,  a = 0.35, hex = "1eb3ff" }, -- Slot 2: Cyan / Blue
    [3] = { r = 0.2, g = 1.00, b = 0.3,  a = 0.35, hex = "30ff30" }, -- Slot 3: Bright Green
}

-- Create main frame
local frameTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
local f = CreateFrame("Frame", "InnervateTrackerFrame", UIParent, frameTemplate)
f:SetSize(170, 22)
f:SetClampedToScreen(true)

if f.SetBackdrop then
    f:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8, inset = 2
    })
    f:SetBackdropBorderColor(1, 1, 1, 0.4)
    f:SetBackdropColor(0, 0, 0, 0.6)
end

f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", function(self)
    if not InnervateTrackerDB or not InnervateTrackerDB.locked then
        self:StartMoving()
    end
end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    if InnervateTrackerDB then
        InnervateTrackerDB.point = point
        InnervateTrackerDB.relPoint = relPoint
        InnervateTrackerDB.x = x
        InnervateTrackerDB.y = y
    end
end)

-- Safe Keyboard Event Listener for F9, F10, F11 fallback (never touches WoW keybinding files)
if f.SetPropagateKeyboardInput then
    f:SetPropagateKeyboardInput(true)
end
f:SetScript("OnKeyDown", function(self, key)
    if key == "F9" then
        if InnervateTracker_WhisperSelected1 then InnervateTracker_WhisperSelected1() end
    elseif key == "F10" then
        if InnervateTracker_WhisperSelected2 then InnervateTracker_WhisperSelected2() end
    elseif key == "F11" then
        if InnervateTracker_WhisperSelected3 then InnervateTracker_WhisperSelected3() end
    end
end)

-- Growth Direction Button [v] / [^] (Header)
local growBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
growBtn:SetSize(16, 14)
growBtn:SetText("v")
growBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local isUp = InnervateTrackerDB and InnervateTrackerDB.growUp
    GameTooltip:SetText("Growth direction: " .. (isUp and "Upwards (^)" or "Downwards (v)"), 1, 1, 1)
    GameTooltip:Show()
end)
growBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Session time header (S: 0m)
local title = f:CreateFontString(nil, "OVERLAY")
title:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
title:SetTextColor(1, 0.82, 0)

-- Reset button "R" (Header)
local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
resetBtn:SetSize(16, 14)
resetBtn:SetText("R")
resetBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Reset counters and session time", 1, 1, 1)
    GameTooltip:Show()
end)
resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

f.lines = {}
local druidList = {}
local isInitialized = false

-- Array of up to 3 highlighted Druids: selectedDruids = { "DruidA", "DruidB", "DruidC" }
local selectedDruids = {}

-- Debounce tracking to prevent double whispers from dual trigger sources
local lastWhisperTimes = {}

-- Forward declaration
local UpdateDisplay, ScanRaidRoster

local function GetShortName(fullName)
    if not fullName then return "" end
    return string.match(fullName, "^([^-]+)") or fullName
end

-- Truncate Druid name to 7 characters max; add '*' suffix if longer
local function FormatDruidDisplayName(fullName)
    local name = GetShortName(fullName)
    if #name > 7 then
        return string.sub(name, 1, 7) .. "*"
    else
        return name
    end
end

-- Exact 30-yard Innervate Cast Range Check
local function IsUnitInInnervateRange(unit)
    if not unit or UnitIsUnit(unit, "player") then return true end
    
    -- 1. Check direct 30-yard spell range if player is a Druid
    if IsSpellInRange then
        local inRange = IsSpellInRange(INNERVATE_NAME, unit)
        if inRange == 1 then return true end
        if inRange == 0 then return false end
    end
    
    -- 2. Fallback check for non-Druid classes: Follow Distance (~28-30 yards) & Visibility
    return UnitIsVisible(unit) and CheckInteractDistance(unit, 4) == true
end

-- Detect Role from Unit or PowerType (Rage = TANK, Energy = DAMAGER, Mana = HEALER/DAMAGER)
local function DetectUnitRole(unit)
    if not unit then return "HEALER" end
    
    -- 1. Check LFG / Party Frame Assigned Role
    if UnitGroupRolesAssigned then
        local assigned = UnitGroupRolesAssigned(unit)
        if assigned and assigned ~= "NONE" then
            return assigned
        end
    end
    
    -- 2. Check MainTank Raid Assignment
    if GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) then
        return "TANK"
    end
    
    -- 3. Check Druid Shapeshift Form / Power Type (1 = Rage / Bear, 3 = Energy / Cat)
    local pType = UnitPowerType(unit)
    if pType == 1 then
        return "TANK"
    elseif pType == 3 then
        return "DAMAGER"
    end
    
    return "HEALER"
end

-- Helper to find slot index of a Druid (1, 2, 3, or nil)
local function GetDruidSlot(druidName)
    for idx, name in ipairs(selectedDruids) do
        if name == druidName then
            return idx
        end
    end
    return nil
end

-- Sync selectedDruids with SavedVariables
local function SyncSelectedDruids()
    if InnervateTrackerDB then
        InnervateTrackerDB.selectedDruids = selectedDruids
    end
end

-- Global functions executed by Keybindings or Right-Click
function InnervateTracker_WhisperSlot(slotIndex)
    local now = GetTime and GetTime() or time()
    -- Guard: Ignore duplicate trigger calls within 0.5 seconds
    if lastWhisperTimes[slotIndex] and (now - lastWhisperTimes[slotIndex]) < 0.5 then
        return
    end

    local druidName = selectedDruids[slotIndex]
    if not druidName then
        print("|cffffea00[InnervateTracker]|r No Druid is highlighted in Slot #" .. slotIndex .. "!")
        return
    end

    local druidData = druidList[druidName]
    if druidData and not druidData.inGroup then
        print("|cffffea00[InnervateTracker]|r Cannot whisper " .. druidName .. " (Druid is absent / left group).")
        return
    end

    lastWhisperTimes[slotIndex] = now

    -- In combat, check if SendChatMessage can be sent safely or open chat editbox
    if InCombatLockdown and InCombatLockdown() then
        if ChatFrame_OpenChat then
            ChatFrame_OpenChat("/w " .. druidName .. " Innervate please!")
            print("|cff30ff30[InnervateTracker]|r Opened whisper editbox for " .. druidName)
        else
            SendChatMessage("Innervate please!", "WHISPER", nil, druidName)
            print("|cff30ff30[InnervateTracker]|r Whispered " .. druidName .. " (#" .. slotIndex .. "): Innervate please!")
        end
    else
        SendChatMessage("Innervate please!", "WHISPER", nil, druidName)
        print("|cff30ff30[InnervateTracker]|r Whispered " .. druidName .. " (#" .. slotIndex .. "): Innervate please!")
    end
end

function InnervateTracker_WhisperSelected1() InnervateTracker_WhisperSlot(1) end
function InnervateTracker_WhisperSelected2() InnervateTracker_WhisperSlot(2) end
function InnervateTracker_WhisperSelected3() InnervateTracker_WhisperSlot(3) end

local function FormatSessionTime()
    if not InnervateTrackerDB or not InnervateTrackerDB.startTime then return "S: 0m" end
    local diff = math.max(0, time() - InnervateTrackerDB.startTime)
    local hrs = math.floor(diff / 3600)
    local mins = math.floor((diff % 3600) / 60)
    return hrs > 0 and string.format("S: %dh%dm", hrs, mins) or string.format("S: %dm", mins)
end

local function UpdateHeaderLayout()
    local isUp = InnervateTrackerDB and InnervateTrackerDB.growUp
    growBtn:SetText(isUp and "^" or "v")

    growBtn:ClearAllPoints()
    title:ClearAllPoints()
    resetBtn:ClearAllPoints()

    if isUp then
        growBtn:SetPoint("BOTTOMLEFT", 5, 4)
        title:SetPoint("BOTTOMLEFT", 24, 5)
        resetBtn:SetPoint("BOTTOMRIGHT", -5, 4)
    else
        growBtn:SetPoint("TOPLEFT", 5, -4)
        title:SetPoint("TOPLEFT", 24, -5)
        resetBtn:SetPoint("TOPRIGHT", -5, -4)
    end
end

local function ResetData()
    if not InnervateTrackerDB then return end
    InnervateTrackerDB.casts = {}
    InnervateTrackerDB.history = {}
    InnervateTrackerDB.activeCDs = {}
    InnervateTrackerDB.startTime = time()
    table.wipe(selectedDruids)
    SyncSelectedDruids()
    print("|cff30ff30Innervate Tracker: Stats and session time have been reset!|r")
end

growBtn:SetScript("OnClick", function()
    if not InnervateTrackerDB then return end
    InnervateTrackerDB.growUp = not InnervateTrackerDB.growUp
    
    local point, rel, relPoint, x, y = f:GetPoint()
    if point and InnervateTrackerDB.growUp then
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", UIParent, relPoint or "BOTTOMLEFT", x, y)
    elseif point then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, relPoint or "TOPLEFT", x, y)
    end

    UpdateHeaderLayout()
    if UpdateDisplay then UpdateDisplay() end
end)

resetBtn:SetScript("OnClick", function()
    ResetData()
    if ScanRaidRoster then ScanRaidRoster() end
    if UpdateDisplay then UpdateDisplay() end
end)

local function CreateVisualRow(index)
    local row = CreateFrame("Button", nil, f)
    row:SetSize(158, 14)
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Highlight backdrop
    row.highlightBg = row:CreateTexture(nil, "BACKGROUND")
    row.highlightBg:SetAllPoints(row)
    row.highlightBg:Hide()

    -- Role Icon (Tank, Healer, Damage) using Blizzard's official LFG Icon Texture
    row.roleIcon = row:CreateTexture(nil, "OVERLAY")
    row.roleIcon:SetSize(11, 11)
    row.roleIcon:SetPoint("LEFT", 2, 0)

    -- Status Bar
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetSize(68, 12)
    row.bar:SetPoint("RIGHT", 0, 0)
    row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.bar:EnableMouse(false) -- Mouse transparent so clicks pass directly to row Button

    row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.bar.bg:SetAllPoints(row.bar)
    row.bar.bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.bar.bg:SetVertexColor(0.2, 0.1, 0.1, 0.5)

    row.bar.text = row.bar:CreateFontString(nil, "OVERLAY")
    row.bar.text:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    row.bar.text:SetPoint("CENTER", row.bar, "CENTER", 0, 0)
    row.bar.text:SetWordWrap(false) -- Prevent 2-line word wrapping

    row.readyText = row:CreateFontString(nil, "OVERLAY")
    row.readyText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    row.readyText:SetPoint("RIGHT", 0, 0)
    row.readyText:SetWordWrap(false) -- Prevent 2-line word wrapping

    -- Left text bounded on LEFT by roleIcon and RIGHT by bar to prevent ANY overlap!
    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    row.text:SetPoint("LEFT", row.roleIcon, "RIGHT", 2, 0)
    row.text:SetPoint("RIGHT", row.bar, "LEFT", -2, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false) -- FORCE SINGLE LINE ONLY (PREVENT 2-LINE WRAPPING)

    -- Single OnClick event on mouse release
    row:SetScript("OnClick", function(self, button)
        if not self.druidName then return end
        local shortDruid = GetShortName(self.druidName)

        if button == "LeftButton" then
            local existingSlot = GetDruidSlot(shortDruid)
            if existingSlot then
                -- Unmark: Remove Druid and shift remaining slots up automatically!
                table.remove(selectedDruids, existingSlot)
            else
                -- Mark: Insert into next available slot (max 3 slots)
                if #selectedDruids < 3 then
                    table.insert(selectedDruids, shortDruid)
                else
                    -- Replace 3rd slot if 3 are already selected
                    selectedDruids[3] = shortDruid
                end
            end
            SyncSelectedDruids()
            if UpdateDisplay then UpdateDisplay() end

        elseif button == "RightButton" then
            local slotIndex = GetDruidSlot(shortDruid)
            if slotIndex then
                InnervateTracker_WhisperSlot(slotIndex)
            end
        end
    end)

    row:SetScript("OnEnter", function(self)
        if not self.druidName then return end
        local shortDruid = GetShortName(self.druidName)

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()

        local totalCasts = InnervateTrackerDB and InnervateTrackerDB.casts and InnervateTrackerDB.casts[shortDruid] or 0
        GameTooltip:AddLine(shortDruid .. " (Casts: " .. totalCasts .. ")", 1, 0.49, 0.04)

        local slotIndex = GetDruidSlot(shortDruid)
        local bindKeys = { "F9", "F10", "F11" }
        
        if slotIndex then
            local key1, key2 = GetBindingKey and GetBindingKey("INNERVATETRACKER_WHISPER" .. slotIndex)
            local activeKey = key1 or key2
            local colorHex = SLOT_COLORS[slotIndex] and SLOT_COLORS[slotIndex].hex or "ffd100"
            
            if activeKey then
                local keyText = GetBindingText and GetBindingText(activeKey) or activeKey
                GameTooltip:AddLine(string.format("|cff%s★ Highlighted Slot #%d (Press %s or Right-click)|r", colorHex, slotIndex, keyText))
            else
                GameTooltip:AddLine(string.format("|cff%s★ Highlighted Slot #%d (Not Bound - set key in Keybindings > AddOns)|r", colorHex, slotIndex))
            end
        else
            GameTooltip:AddLine("Left-click to highlight (Slot 1, 2, or 3)", 0.6, 0.6, 0.6)
        end

        local cdData = InnervateTrackerDB and InnervateTrackerDB.activeCDs and InnervateTrackerDB.activeCDs[shortDruid]
        if cdData and cdData.target then
            GameTooltip:AddLine("Last Innervate for: " .. GetShortName(cdData.target), 0.2, 1, 0.2)
        end

        GameTooltip:AddLine(" ")

        local history = InnervateTrackerDB and InnervateTrackerDB.history and InnervateTrackerDB.history[shortDruid]
        if history and next(history) then
            GameTooltip:AddLine("Received Innervate:", 1, 1, 1)
            for target, count in pairs(history) do
                local shortTarget = GetShortName(target)
                local color = { r = 0.8, g = 0.8, b = 0.8 }
                if UnitExists and UnitClass then
                    local _, classToken = UnitClass(shortTarget)
                    if classToken and CLASS_COLORS[classToken] then
                        color = CLASS_COLORS[classToken]
                    end
                end
                GameTooltip:AddDoubleLine("  " .. shortTarget, count .. " x", color.r, color.g, color.b, 0.2, 1, 0.2)
            end
        else
            GameTooltip:AddLine("No casts recorded this session.", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.lines[index] = row
    return row
end

ScanRaidRoster = function()
    table.wipe(druidList)

    -- 1. Current group druids
    local numGroup = GetNumGroupMembers()
    if numGroup > 0 then
        local prefix = IsInRaid() and "raid" or "party"
        for i = 1, numGroup do
            local unit = (not IsInRaid() and i == numGroup) and "player" or (prefix .. i)
            local name = UnitName(unit)
            if name then
                local shortName = GetShortName(name)
                local _, class = UnitClass(unit)
                if class == "DRUID" then
                    local role = DetectUnitRole(unit)
                    if InnervateTrackerDB and InnervateTrackerDB.roles and InnervateTrackerDB.roles[shortName] then
                        role = InnervateTrackerDB.roles[shortName]
                    end
                    druidList[shortName] = {
                        unit = unit,
                        role = role,
                        inGroup = true,
                        isDead = UnitIsDeadOrGhost(unit),
                        isOffline = not UnitIsConnected(unit),
                        inRange = IsUnitInInnervateRange(unit)
                    }
                end
            end
        end
    else
        local _, class = UnitClass("player")
        if class == "DRUID" then
            local name = UnitName("player")
            if name then
                local shortName = GetShortName(name)
                local role = DetectUnitRole("player")
                if InnervateTrackerDB and InnervateTrackerDB.roles and InnervateTrackerDB.roles[shortName] then
                    role = InnervateTrackerDB.roles[shortName]
                end
                druidList[shortName] = {
                    unit = "player",
                    role = role,
                    inGroup = true,
                    isDead = UnitIsDeadOrGhost("player"),
                    isOffline = false,
                    inRange = true
                }
            end
        end
    end

    -- 2. Retain all druids who recorded casts during this session
    if InnervateTrackerDB then
        local tables = { InnervateTrackerDB.casts, InnervateTrackerDB.activeCDs, InnervateTrackerDB.history }
        for _, tbl in ipairs(tables) do
            if tbl then
                for name in pairs(tbl) do
                    if not druidList[name] then
                        local role = (InnervateTrackerDB.roles and InnervateTrackerDB.roles[name]) or "HEALER"
                        druidList[name] = { unit = nil, role = role, inGroup = false, isDead = false, isOffline = false, inRange = false }
                    end
                end
            end
        end
    end

    -- 3. Always retain highlighted Druids in selectedDruids
    for _, name in ipairs(selectedDruids) do
        if not druidList[name] then
            local role = (InnervateTrackerDB and InnervateTrackerDB.roles and InnervateTrackerDB.roles[name]) or "HEALER"
            druidList[name] = { unit = nil, role = role, inGroup = false, isDead = false, isOffline = false, inRange = false }
        end
    end
end

UpdateDisplay = function()
    if not isInitialized or not InnervateTrackerDB then return end

    UpdateHeaderLayout()
    title:SetText(FormatSessionTime())

    local index = 1
    local currentTime = time()
    local isUp = InnervateTrackerDB.growUp

    local sortedDruids = {}
    for name in pairs(druidList) do
        table.insert(sortedDruids, name)
    end
    table.sort(sortedDruids)

    for _, name in ipairs(sortedDruids) do
        local row = f.lines[index] or CreateVisualRow(index)
        row.druidName = name

        row:ClearAllPoints()
        if isUp then
            row:SetPoint("BOTTOMLEFT", 6, 20 + ((index - 1) * 15))
        else
            row:SetPoint("TOPLEFT", 6, -20 - ((index - 1) * 15))
        end

        local druidData = druidList[name]
        local cdData = InnervateTrackerDB.activeCDs and InnervateTrackerDB.activeCDs[name]
        local elapsed = cdData and (currentTime - cdData.castTime) or 9999
        local remainingCD = INNERVATE_CD - elapsed
        local remainingBuff = INNERVATE_BUFF_DURATION - elapsed
        local casts = InnervateTrackerDB.casts and InnervateTrackerDB.casts[name] or 0

        -- Role Icon Handling using Blizzard's official LFG Icon Texture (Spelled PORTRAITROLES)
        local role = druidData and druidData.role or "HEALER"
        row.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        if role == "TANK" then
            row.roleIcon:SetTexCoord(0, 0.28125, 0.28125, 0.5625)
        elseif role == "DAMAGER" then
            row.roleIcon:SetTexCoord(0.28125, 0.5625, 0.28125, 0.5625)
        else
            -- HEALER (default)
            row.roleIcon:SetTexCoord(0.28125, 0.5625, 0, 0.28125)
        end
        row.roleIcon:Show()

        -- Formatted Druid Name (Max 7 chars, '*' suffix if longer)
        local displayName = FormatDruidDisplayName(name)

        -- Multi-Slot Highlight color check (Gold for Slot 1, Cyan for Slot 2, Green for Slot 3)
        local slotIndex = GetDruidSlot(name)
        if slotIndex and SLOT_COLORS[slotIndex] then
            local col = SLOT_COLORS[slotIndex]
            row.highlightBg:SetColorTexture(col.r, col.g, col.b, col.a)
            row.highlightBg:Show()
        else
            row.highlightBg:Hide()
        end

        -- Status, Range Opacity & Absent / Off / Dead Indicator handling
        local isRangeOk = not druidData or druidData.unit == nil or druidData.inRange

        if druidData and not druidData.inGroup then
            -- Druid is Absent (Left group) -> Muted Purple
            row.text:SetText(string.format("%s (Absent)", displayName))
            row.text:SetTextColor(0.65, 0.45, 0.65)
            row:SetAlpha(0.5)
        elseif druidData and druidData.isOffline then
            -- Druid is Offline -> Gray
            row.text:SetText(string.format("%s (Off)", displayName))
            row.text:SetTextColor(0.5, 0.5, 0.5)
            row:SetAlpha(0.5)
        elseif druidData and druidData.isDead then
            -- Druid is Dead -> Dark Red
            row.text:SetText(string.format("%s (Dead)", displayName))
            row.text:SetTextColor(0.75, 0.2, 0.2)
            row:SetAlpha(0.6)
        else
            -- Active Druid in group
            row.text:SetText(string.format("%s (%d)", displayName, casts))
            row.text:SetTextColor(1.0, 0.49, 0.04)
            if isRangeOk then
                row:SetAlpha(1.0)
            else
                -- Out of Range (30-yard Innervate range check) -> Sharp, readable 0.65 alpha fade
                row:SetAlpha(0.65)
            end
        end

        -- Right side Cooldown / Ready Status Bar
        if remainingBuff > 0 then
            -- Active Buff (0-20s)
            row.readyText:Hide()
            row.bar:Show()
            row.bar:SetMinMaxValues(0, INNERVATE_BUFF_DURATION)
            row.bar:SetValue(remainingBuff)
            row.bar:SetStatusBarColor(0.1, 0.7, 1.0, 0.9)

            local targetNick = FormatDruidDisplayName(cdData.target or "Unknown")
            row.bar.text:SetText(string.format("%s %ds", targetNick, math.ceil(remainingBuff)))

        elseif remainingCD > 0 then
            -- Cooldown Phase (20-360s)
            row.readyText:Hide()
            row.bar:Show()
            row.bar:SetMinMaxValues(0, INNERVATE_CD - INNERVATE_BUFF_DURATION)
            row.bar:SetValue(remainingCD)
            row.bar:SetStatusBarColor(1.0, 0.3, 0.3, 0.8)

            local mins = math.floor(remainingCD / 60)
            local secs = math.floor(remainingCD % 60)
            row.bar.text:SetText(string.format("%dm%02ds", mins, secs))

        else
            -- Ready
            if cdData then
                if InnervateTrackerDB.soundAlert and cdData.soundPlayed ~= true then
                    pcall(PlaySound, 5274) -- SoundKit.ReadyCheck safely wrapped
                    cdData.soundPlayed = true
                end
                InnervateTrackerDB.activeCDs[name] = nil
            end
            row.bar:Hide()
            row.readyText:SetText("|cff30ff30Ready|r")
            row.readyText:Show()
        end

        row:Show()
        index = index + 1
    end

    -- Hide any extra unused rows
    for i = index, #f.lines do
        if f.lines[i] then f.lines[i]:Hide() end
    end

    if index == 1 then
        f:SetHeight(22)
    else
        f:Show()
        f:SetHeight(20 + ((index - 1) * 15) + 6)
    end
end

f:SetScript("OnUpdate", function(self, elapsed)
    if not isInitialized or not InnervateTrackerDB then return end
    self.timer = (self.timer or 0) + elapsed
    if self.timer >= 0.1 then
        self.timer = 0
        ScanRaidRoster()
        UpdateDisplay()
    end
end)

local function InitDB()
    if isInitialized then return end

    if type(InnervateTrackerDB) ~= "table" then InnervateTrackerDB = {} end
    if not InnervateTrackerDB.casts then InnervateTrackerDB.casts = {} end
    if not InnervateTrackerDB.history then InnervateTrackerDB.history = {} end
    if not InnervateTrackerDB.activeCDs then InnervateTrackerDB.activeCDs = {} end
    if not InnervateTrackerDB.roles then InnervateTrackerDB.roles = {} end
    if InnervateTrackerDB.soundAlert == nil then InnervateTrackerDB.soundAlert = true end

    -- Restore saved marked (highlighted) Druids across /reload and relogs
    if InnervateTrackerDB.selectedDruids and type(InnervateTrackerDB.selectedDruids) == "table" then
        selectedDruids = InnervateTrackerDB.selectedDruids
    else
        InnervateTrackerDB.selectedDruids = selectedDruids
    end

    if not InnervateTrackerDB.startTime or InnervateTrackerDB.startTime == 0 then
        InnervateTrackerDB.startTime = time()
    end

    if not InnervateTrackerDB.point then
        InnervateTrackerDB.point = "CENTER"
        InnervateTrackerDB.relPoint = "CENTER"
        InnervateTrackerDB.x = 0
        InnervateTrackerDB.y = 0
    end

    f:ClearAllPoints()
    f:SetPoint(InnervateTrackerDB.point, UIParent, InnervateTrackerDB.relPoint, InnervateTrackerDB.x, InnervateTrackerDB.y)

    isInitialized = true
    ScanRaidRoster()
    UpdateDisplay()
end

SLASH_INVERNATETRACKER1 = "/it"
SlashCmdList["INVERNATETRACKER"] = function(msg)
    if msg == "reset" then
        ResetData()
        ScanRaidRoster()
        UpdateDisplay()
    elseif msg == "lock" then
        InnervateTrackerDB.locked = not InnervateTrackerDB.locked
        print("|cffffea00Innervate Tracker:|r Frame " .. (InnervateTrackerDB.locked and "|cffff0000Locked|r" or "|cff30ff30Unlocked|r"))
    elseif msg == "sound" then
        InnervateTrackerDB.soundAlert = not InnervateTrackerDB.soundAlert
        print("|cffffea00Innervate Tracker:|r Sound alert " .. (InnervateTrackerDB.soundAlert and "|cff30ff30Enabled|r" or "|cffff0000Disabled|r"))
    else
        print("|cffffea00Innervate Tracker usage:|r")
        print("  /it reset - resets counters and session time.")
        print("  /it lock  - locks / unlocks frame dragging.")
        print("  /it sound - toggles sound alert when Innervate becomes Ready.")
        print("  Keybinds: Options > Keybindings > AddOns > Innervate Tracker (F9, F10, F11)")
    end
end

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName or loadedAddon == "InnervateTracker" then
            InitDB()
        end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        InitDB()
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not isInitialized then InitDB() else ScanRaidRoster() end
        UpdateDisplay()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not isInitialized then InitDB() end
        local _, subEvent, _, _, sourceName, _, _, _, destName, _, _, spellID, spellName = CombatLogGetCurrentEventInfo()

        if subEvent == "SPELL_CAST_SUCCESS" and (spellID == 29166 or (spellName and INNERVATE_NAME and spellName == INNERVATE_NAME)) then
            if sourceName then
                local casterName = GetShortName(sourceName)
                if druidList[casterName] then
                    local targetName = destName and GetShortName(destName) or "Unknown"

                    InnervateTrackerDB.casts[casterName] = (InnervateTrackerDB.casts[casterName] or 0) + 1

                    InnervateTrackerDB.history[casterName] = InnervateTrackerDB.history[casterName] or {}
                    InnervateTrackerDB.history[casterName][targetName] = (InnervateTrackerDB.history[casterName][targetName] or 0) + 1

                    InnervateTrackerDB.activeCDs[casterName] = {
                        castTime = time(),
                        target = targetName,
                        soundPlayed = false
                    }
                    UpdateDisplay()
                end
            end
        end
    end
end)

if type(InnervateTrackerDB) == "table" and InnervateTrackerDB.startTime then
    InitDB()
end
