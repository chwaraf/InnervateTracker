local addonName = ...

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

-- Session time header
local title = f:CreateFontString(nil, "OVERLAY")
title:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
title:SetPoint("TOPLEFT", 6, -4)
title:SetTextColor(1, 0.82, 0)

-- Reset button "R"
local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
resetBtn:SetSize(16, 14)
resetBtn:SetPoint("TOPRIGHT", -5, -4)
resetBtn:SetText("R")
resetBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Reset counters and session time", 1, 1, 1)
    GameTooltip:Show()
end)
resetBtn:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

f.lines = {}
local druidList = {}
local isInitialized = false

local function GetShortName(fullName)
    if not fullName then return "" end
    return string.match(fullName, "^([^-]+)") or fullName
end

local function FormatSessionTime()
    if not InnervateTrackerDB or not InnervateTrackerDB.startTime then return "Session: 0m" end
    local diff = math.max(0, time() - InnervateTrackerDB.startTime)
    local hrs = math.floor(diff / 3600)
    local mins = math.floor((diff % 3600) / 60)
    if hrs > 0 then
        return string.format("Session: %dh%dm", hrs, mins)
    else
        return string.format("Session: %dm", mins)
    end
end

local function ResetData()
    if not InnervateTrackerDB then return end
    InnervateTrackerDB.casts = {}
    InnervateTrackerDB.receivers = {}
    InnervateTrackerDB.history = {}
    InnervateTrackerDB.activeCDs = {}
    InnervateTrackerDB.startTime = time()
    print("|cff30ff30Innervate Tracker: Stats and session time have been reset!|r")
end

resetBtn:SetScript("OnClick", function()
    ResetData()
    if UpdateDisplay then UpdateDisplay() end
end)

local function CreateVisualRow(index)
    local row = CreateFrame("Frame", nil, f)
    row:SetSize(158, 14)
    row:SetPoint("TOPLEFT", 6, -20 - ((index - 1) * 15))
    row:EnableMouse(true)

    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    row.text:SetPoint("LEFT", 0, 0)
    row.text:SetTextColor(1.0, 0.49, 0.04)

    row.readyText = row:CreateFontString(nil, "OVERLAY")
    row.readyText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    row.readyText:SetPoint("RIGHT", 0, 0)

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetSize(72, 12)
    row.bar:SetPoint("RIGHT", 0, 0)
    row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")

    row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.bar.bg:SetAllPoints(row.bar)
    row.bar.bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.bar.bg:SetVertexColor(0.2, 0.1, 0.1, 0.5)

    row.bar.text = row.bar:CreateFontString(nil, "OVERLAY")
    row.bar.text:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    row.bar.text:SetPoint("CENTER", row.bar, "CENTER", 0, 0)

    row:SetScript("OnEnter", function(self)
        if not self.druidName then return end
        local druidName = self.druidName
        local shortDruid = GetShortName(druidName)

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()

        local totalCasts = (InnervateTrackerDB and InnervateTrackerDB.casts and (InnervateTrackerDB.casts[druidName] or InnervateTrackerDB.casts[shortDruid])) or 0
        GameTooltip:AddLine(shortDruid .. " (Casts: " .. totalCasts .. ")", 1, 0.5, 0)

        local cdData = InnervateTrackerDB and InnervateTrackerDB.activeCDs and (InnervateTrackerDB.activeCDs[druidName] or InnervateTrackerDB.activeCDs[shortDruid])
        if cdData and cdData.target then
            GameTooltip:AddLine("Last Innervate for: " .. GetShortName(cdData.target), 0.2, 1, 0.2)
        end

        GameTooltip:AddLine(" ")

        local history = InnervateTrackerDB and InnervateTrackerDB.history and (InnervateTrackerDB.history[druidName] or InnervateTrackerDB.history[shortDruid])
        if history and next(history) then
            GameTooltip:AddLine("Received Innervate:", 1, 1, 1)
            for target, count in pairs(history) do
                GameTooltip:AddDoubleLine("  " .. GetShortName(target), count .. " x", 0.8, 0.8, 0.8, 0.2, 1, 0.2)
            end
        else
            GameTooltip:AddLine("No casts recorded this session.", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    f.lines[index] = row
    return row
end

local function ScanRaidRoster()
    table.wipe(druidList)
    local numGroup = GetNumGroupMembers and GetNumGroupMembers() or (IsInRaid and IsInRaid() and GetNumRaidMembers() or GetNumPartyMembers())
    local isRaid = IsInRaid and IsInRaid()

    if numGroup and numGroup > 0 then
        if isRaid then
            for i = 1, numGroup do
                local unit = "raid" .. i
                local name, server = UnitName(unit)
                if name then
                    local fullName = (server and server ~= "") and (name .. "-" .. server) or name
                    local _, class = UnitClass(unit)
                    if class == "DRUID" then
                        druidList[fullName] = true
                        druidList[name] = fullName
                    end
                end
            end
        else
            for i = 1, numGroup - 1 do
                local unit = "party" .. i
                local name, server = UnitName(unit)
                if name then
                    local fullName = (server and server ~= "") and (name .. "-" .. server) or name
                    local _, class = UnitClass(unit)
                    if class == "DRUID" then
                        druidList[fullName] = true
                        druidList[name] = fullName
                    end
                end
            end
            local _, class = UnitClass("player")
            if class == "DRUID" then
                local name = UnitName("player")
                if name then druidList[name] = name end
            end
        end
    else
        local _, class = UnitClass("player")
        if class == "DRUID" then
            local name = UnitName("player")
            if name then druidList[name] = name end
        end
    end
end

function UpdateDisplay()
    if not isInitialized or not InnervateTrackerDB then return end
    title:SetText(FormatSessionTime())

    for _, row in ipairs(f.lines) do row:Hide() end
    local index = 1
    local currentTime = time()

    local sortedDruids = {}
    local seen = {}
    for key, val in pairs(druidList) do
        local displayName = (type(val) == "string") and val or key
        if not seen[displayName] then
            seen[displayName] = true
            table.insert(sortedDruids, displayName)
        end
    end
    table.sort(sortedDruids)

    for _, name in ipairs(sortedDruids) do
        local row = f.lines[index] or CreateVisualRow(index)
        local shortName = GetShortName(name)
        row.druidName = name

        local cdData = InnervateTrackerDB.activeCDs and (InnervateTrackerDB.activeCDs[name] or InnervateTrackerDB.activeCDs[shortName])
        local elapsed = cdData and (currentTime - cdData.castTime) or 9999
        local remainingCD = INNERVATE_CD - elapsed
        local remainingBuff = INNERVATE_BUFF_DURATION - elapsed
        local casts = (InnervateTrackerDB and InnervateTrackerDB.casts and (InnervateTrackerDB.casts[name] or InnervateTrackerDB.casts[shortName])) or 0

        row.text:SetText(string.format("%s (%d)", shortName, casts))

        if remainingBuff > 0 then
            -- Active Buff (0-20s)
            row.readyText:Hide()
            row.bar:Show()
            row.bar:SetMinMaxValues(0, INNERVATE_BUFF_DURATION)
            row.bar:SetValue(remainingBuff)
            row.bar:SetStatusBarColor(0.1, 0.7, 1.0, 0.9)

            local targetNick = GetShortName(cdData.target or "Unknown")
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
                    PlaySound(5274) -- SoundKit.ReadyCheck
                    cdData.soundPlayed = true
                end
                InnervateTrackerDB.activeCDs[name] = nil
                InnervateTrackerDB.activeCDs[shortName] = nil
            end
            row.bar:Hide()
            row.readyText:SetText("|cff30ff30Ready|r")
            row.readyText:Show()
        end

        row:Show()
        index = index + 1
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
        UpdateDisplay()
    end
end)

local function InitDB()
    if isInitialized then return end

    if type(InnervateTrackerDB) ~= "table" then InnervateTrackerDB = {} end
    if not InnervateTrackerDB.casts then InnervateTrackerDB.casts = {} end
    if not InnervateTrackerDB.receivers then InnervateTrackerDB.receivers = {} end
    if not InnervateTrackerDB.history then InnervateTrackerDB.history = {} end
    if not InnervateTrackerDB.activeCDs then InnervateTrackerDB.activeCDs = {} end
    if InnervateTrackerDB.soundAlert == nil then InnervateTrackerDB.soundAlert = true end

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
    end
end

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName or loadedAddon == "InnervateTracker" then
            InitDB()
        end
    elseif event == "PLAYER_LOGIN" then
        InitDB()
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not isInitialized then InitDB() else ScanRaidRoster() end
        UpdateDisplay()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not isInitialized then InitDB() end
        local _, subEvent, _, _, sourceName, _, _, _, destName, _, _, spellID, spellName = CombatLogGetCurrentEventInfo()

        if subEvent == "SPELL_CAST_SUCCESS" and (spellID == 29166 or (spellName and INNERVATE_NAME and spellName == INNERVATE_NAME)) then
            if sourceName then
                local shortSource = GetShortName(sourceName)
                if druidList[sourceName] or druidList[shortSource] then
                    local casterName = shortSource
                    local targetName = destName and GetShortName(destName) or "Unknown"

                    InnervateTrackerDB.casts[casterName] = (InnervateTrackerDB.casts[casterName] or 0) + 1
                    if destName then
                        InnervateTrackerDB.receivers[targetName] = (InnervateTrackerDB.receivers[targetName] or 0) + 1
                    end

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
