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

-- Cached sorted roster list: rebuilt only when druidList membership changes,
-- instead of re-collecting + table.sort on every 100ms UI tick
local cachedSortedDruids = nil

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

-- Relative age for tooltip cast log ("12s ago", "3m ago", "1h ago")
local function FormatRelativeAge(castTime)
    local age = math.max(0, time() - castTime)
    if age < 60 then
        return string.format("%ds ago", age)
    elseif age < 3600 then
        return string.format("%dm ago", math.floor(age / 60))
    else
        return string.format("%dh ago", math.floor(age / 3600))
    end
end

-- Version-safe range query: Anniversary/Retail builds expose C_Spell.IsSpellInRange;
-- older Classic builds use the global IsSpellInRange. Returns 1/0/nil.
local function QuerySpellRange(identifier, unit)
    if C_Spell and C_Spell.IsSpellInRange then
        return C_Spell.IsSpellInRange(identifier, unit)
    elseif IsSpellInRange then
        return IsSpellInRange(identifier, unit)
    end
    return nil
end

-- Candidate rules learned the hard way:
--   * Do NOT filter with IsSpellKnown (unreliable for base IDs in Classic).
--   * Do NOT probe IsSpellInRange(name, "player") - the player usually HAS their
--     own MotW/Fortitude, so the probe nils out exactly the spells we need.
--   * Do NOT cache an empty list - the first call can fire before spell data is
--     queryable; retry on subsequent calls until at least one name resolves.
local rangeSpellNames = nil

local function GetRangeSpellCandidates()
    -- Only cache once non-empty; earlier calls (loading screen) may resolve nothing
    if rangeSpellNames then return rangeSpellNames end

    local _, playerClass = UnitClass("player")
    local candidates = {
        DRUID   = { 1126, 2893, 29166 },         -- Mark of the Wild, Abolish Poison, Innervate (all 30yd)
        MAGE    = { 1459, 604, 602 },            -- Arcane Intellect, Dampen Magic, Amplify Magic (30yd)
        PRIEST  = { 1243, 14752, 976 },          -- PW:Fortitude, Divine Spirit, Shadow Protection (30yd)
        PALADIN = { 19740, 19742, 20217 },       -- Blessing of Might, Wisdom, Kings (30yd)
        SHAMAN  = { 526, 2870, 2008 },           -- Cure Poison, Cure Disease, Ancestral Spirit
        WARLOCK = { 5697, 132 },                 -- Unending Breath, Detect Invisibility (30yd)
    }

    local usable = {}
    for _, id in ipairs(candidates[playerClass] or {}) do
        local name = GetSpellName(id)
        if name then
            table.insert(usable, name)
        end
    end
    if #usable > 0 then
        rangeSpellNames = usable
    end
    return usable
end

local function IsUnitInInnervateRange(unit)
    if not unit or UnitIsUnit(unit, "player") then return true end

    for _, name in ipairs(GetRangeSpellCandidates()) do
        local inRange = QuerySpellRange(name, unit)
        if inRange == 1 or inRange == true then return true end
        if inRange == 0 or inRange == false then return false end
        -- nil = spell not applicable to this unit (already buffed etc.) -> try next spell
    end

    -- Fallback: all spells inconclusive. UnitInRange is ~38-40yd (slightly generous
    -- vs Innervate's 30yd) but 100% unprotected and safe in combat.
    if UnitInRange then
        local inRange, checked = UnitInRange(unit)
        if checked then return inRange end
    end

    return UnitIsVisible(unit) == true
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
    local now = GetTime()
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

    -- Prefer full name (with realm) for cross-realm group members; fall back to stored short name
    local whisperTarget = (druidData and druidData.fullName) or druidName
    SendChatMessage("Innervate please!", "WHISPER", nil, whisperTarget)
    print("|cff30ff30[InnervateTracker]|r Whispered " .. whisperTarget .. " (#" .. slotIndex .. "): Innervate please!")
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
    -- Normalize to a strict boolean: on fresh installs growUp is nil, and
    -- nil == nil would wrongly skip the FIRST layout (header buttons get their
    -- anchors only here, so skipping leaves them unpositioned)
    local isUp = (InnervateTrackerDB and InnervateTrackerDB.growUp) == true

    -- Layout only changes when growth direction flips; skip anchor churn otherwise
    if growBtn.lastIsUp == isUp then return end
    growBtn.lastIsUp = isUp

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
    InnervateTrackerDB.castLog = {}
    InnervateTrackerDB.startTime = time()
    table.wipe(selectedDruids)
    SyncSelectedDruids()
    print("|cff30ff30Innervate Tracker: Stats and session time have been reset!|r")
end

growBtn:SetScript("OnClick", function()
    if not InnervateTrackerDB then return end
    InnervateTrackerDB.growUp = not InnervateTrackerDB.growUp

    -- Preserve the EXACT on-screen rectangle across the toggle: read the frame's
    -- current bottom-left corner (in screen coords) BEFORE touching anchors, then
    -- re-pin BOTTOMLEFT to that same spot. This makes the window hold perfectly
    -- still in BOTH axes regardless of previous anchor state - no drift possible.
    local left, bottom = f:GetLeft(), f:GetBottom()
    if left and bottom then
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        InnervateTrackerDB.point = "BOTTOMLEFT"
        InnervateTrackerDB.relPoint = "BOTTOMLEFT"
        InnervateTrackerDB.x = left
        InnervateTrackerDB.y = bottom
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
    -- Created as a standard unprotected Button (allowing ClearAllPoints/SetPoint during combat with zero taint)
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
    -- Texture path is constant: bind it once here instead of every redraw tick
    row.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")

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

    -- OnClick handles LeftButton for marking/unmarking and RightButton for whispering
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
            -- Only highlighted druids can be right-click whispered: prevents
            -- accidental "Innervate please!" from a misclick on an unmarked row
            local slotIndex = GetDruidSlot(shortDruid)
            if slotIndex then
                InnervateTracker_WhisperSlot(slotIndex)
            else
                print("|cffffea00[InnervateTracker]|r " .. shortDruid .. " is not highlighted - left-click to mark first (or use the slot keybind).")
            end
        end
    end)

    row:SetScript("OnEnter", function(self)
        if not self.druidName then return end
        local shortDruid = GetShortName(self.druidName)
        local db = InnervateTrackerDB

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()

        -- ── Header: name + total casts ─────────────────────────────
        local totalCasts = db and db.casts and db.casts[shortDruid] or 0
        GameTooltip:AddLine(shortDruid, 1.0, 0.49, 0.04) -- druid orange
        if totalCasts > 0 then
            GameTooltip:AddLine(string.format("Total Innervates: %d", totalCasts), 0.9, 0.9, 0.9)
        else
            GameTooltip:AddLine("No Innervates cast this session.", 0.6, 0.6, 0.6)
        end

        -- ── Status line (slot / whisper hint) ──────────────────────
        local slotIndex = GetDruidSlot(shortDruid)
        if slotIndex then
            local key1, key2 = GetBindingKey and GetBindingKey("INNERVATETRACKER_WHISPER" .. slotIndex)
            local activeKey = key1 or key2
            local colorHex = SLOT_COLORS[slotIndex] and SLOT_COLORS[slotIndex].hex or "ffd100"
            if activeKey then
                local keyText = GetBindingText and GetBindingText(activeKey) or activeKey
                GameTooltip:AddLine(string.format("|cff%s* Slot #%d - %s / Right-click|r", colorHex, slotIndex, keyText))
            else
                GameTooltip:AddLine(string.format("|cff%s* Slot #%d - Right-click to whisper|r", colorHex, slotIndex))
            end
        else
            GameTooltip:AddLine("Left-click to highlight / Right-click to whisper", 0.6, 0.6, 0.6)
        end

        -- ── Current cooldown status ─────────────────────────────────
        local cdData = db and db.activeCDs and db.activeCDs[shortDruid]
        if cdData then
            local elapsed = time() - cdData.castTime
            local remainingBuff = INNERVATE_BUFF_DURATION - elapsed
            local remainingCD = INNERVATE_CD - elapsed
            if remainingBuff > 0 then
                GameTooltip:AddDoubleLine(
                    string.format("Buff on %s:", GetShortName(cdData.target)),
                    string.format("%ds", math.ceil(remainingBuff)),
                    0.2, 1, 0.2, 0.2, 1, 0.2)
            elseif remainingCD > 0 then
                GameTooltip:AddDoubleLine(
                    "Cooldown:",
                    string.format("%dm%02ds", math.floor(remainingCD / 60), math.floor(remainingCD % 60)),
                    1.0, 0.3, 0.3, 1.0, 0.3, 0.3)
            end
        end

        -- ── Recent casts (newest first, with relative time) ─────────
        local castLog = db and db.castLog and db.castLog[shortDruid]
        if castLog and #castLog > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Recent Casts", 1, 0.82, 0)
            for i, entry in ipairs(castLog) do
                -- Color by age: fresh (<60s) green, older gray
                local isFresh = (time() - entry.t) < 60
                GameTooltip:AddDoubleLine(
                    string.format("  > %s", GetShortName(entry.target)),
                    FormatRelativeAge(entry.t),
                    0.8, 0.8, 0.8,
                    isFresh and 0.3 or 0.55, isFresh and 1 or 0.55, isFresh and 0.3 or 0.55)
            end
        end

        -- ── Recipient history (sorted: most-received first) ─────────
        local history = db and db.history and db.history[shortDruid]
        if history and next(history) then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Session Totals", 1, 0.82, 0)

            -- Sort recipients by count descending for stable, meaningful order
            local recipients = {}
            for target, count in pairs(history) do
                table.insert(recipients, { target = target, count = count })
            end
            table.sort(recipients, function(a, b) return a.count > b.count end)

            for _, rec in ipairs(recipients) do
                local shortTarget = GetShortName(rec.target)
                local color = { r = 0.8, g = 0.8, b = 0.8 }
                if UnitExists and UnitClass then
                    local _, classToken = UnitClass(shortTarget)
                    if classToken and CLASS_COLORS[classToken] then
                        color = CLASS_COLORS[classToken]
                    end
                end
                GameTooltip:AddDoubleLine(
                    string.format("  %s", shortTarget),
                    string.format("%d x", rec.count),
                    color.r, color.g, color.b, 0.2, 1, 0.2)
            end
        end

        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.lines[index] = row
    return row
end

ScanRaidRoster = function()
    table.wipe(druidList)
    cachedSortedDruids = nil -- invalidate cache; rebuilt lazily in UpdateDisplay

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
                    local isDead = UnitIsDeadOrGhost(unit)
                    local isOffline = not UnitIsConnected(unit)
                    druidList[shortName] = {
                        unit = unit,
                        fullName = name,
                        role = role,
                        inGroup = true,
                        isDead = isDead,
                        isOffline = isOffline,
                        -- Skip the (unprotected but wasteful) range query for dead/offline units
                        inRange = (isDead or isOffline) or IsUnitInInnervateRange(unit)
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
    -- Session label only changes once per minute; skip redundant format+SetText
    local sessionText = FormatSessionTime()
    if title:GetText() ~= sessionText then
        title:SetText(sessionText)
    end

    local index = 1
    local currentTime = time()
    local isUp = InnervateTrackerDB.growUp

    -- Reuse the sorted list across ticks; only rebuild when roster membership changed
    if not cachedSortedDruids then
        cachedSortedDruids = {}
        for name in pairs(druidList) do
            table.insert(cachedSortedDruids, name)
        end
        table.sort(cachedSortedDruids)
    end

    for _, name in ipairs(cachedSortedDruids) do
        local row = f.lines[index] or CreateVisualRow(index)

        -- Rows are recycled by position: if this row now renders a DIFFERENT druid,
        -- invalidate all cached visual state from the previous occupant
        if row.lastName ~= name then
            row.lastName = name
            row.lastState = nil
            row.lastBarPhase = nil
            row.anchoredIndex = nil
        end
        row.druidName = name

        -- Re-anchor only when position actually changes (anchor churn is the most
        -- expensive layout op per tick; rows rarely move between consecutive ticks)
        if row.anchoredIndex ~= index or row.anchoredGrowUp ~= isUp then
            row:ClearAllPoints()
            if isUp then
                row:SetPoint("BOTTOMLEFT", 6, 20 + ((index - 1) * 15))
            else
                row:SetPoint("TOPLEFT", 6, -20 - ((index - 1) * 15))
            end
            row.anchoredIndex = index
            row.anchoredGrowUp = isUp
        end

        local druidData = druidList[name]
        local cdData = InnervateTrackerDB.activeCDs and InnervateTrackerDB.activeCDs[name]
        local elapsed = cdData and (currentTime - cdData.castTime) or 9999
        local remainingCD = INNERVATE_CD - elapsed
        local remainingBuff = INNERVATE_BUFF_DURATION - elapsed
        local casts = InnervateTrackerDB.casts and InnervateTrackerDB.casts[name] or 0

        -- Role Icon: texture path bound once at row creation; only TexCoord varies per role
        local role = druidData and druidData.role or "HEALER"
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

        -- Slot lookup must happen BEFORE any use below (was previously declared
        -- after the highlight check, making that check read a nil global)
        local slotIndex = GetDruidSlot(name)

        -- Multi-Slot Highlight color check (Gold for Slot 1, Cyan for Slot 2, Green for Slot 3)
        if slotIndex and SLOT_COLORS[slotIndex] then
            local col = SLOT_COLORS[slotIndex]
            row.highlightBg:SetColorTexture(col.r, col.g, col.b, col.a)
            row.highlightBg:Show()
        else
            row.highlightBg:Hide()
        end

        -- Status, Range Opacity & Absent / Off / Dead Indicator handling
        local isRangeOk = not druidData or druidData.unit == nil or druidData.inRange

        -- Compute the row's visual state; only touch UI when it changes
        local stateKey
        if druidData and not druidData.inGroup then
            stateKey = "absent"
        elseif druidData and druidData.isOffline then
            stateKey = "offline"
        elseif druidData and druidData.isDead then
            stateKey = "dead"
        elseif isRangeOk then
            -- Casts + slot folded into key so counter/highlight updates still render
            stateKey = "active|" .. casts .. "|" .. (slotIndex or 0)
        else
            stateKey = "active_oor|" .. casts .. "|" .. (slotIndex or 0)
        end

        if row.lastState ~= stateKey then
            row.lastState = stateKey
            if stateKey == "absent" then
                -- Druid is Absent (Left group) -> Muted Purple
                row.text:SetText(string.format("%s (Absent)", displayName))
                row.text:SetTextColor(0.65, 0.45, 0.65)
                row:SetAlpha(0.5)
            elseif stateKey == "offline" then
                -- Druid is Offline -> Gray
                row.text:SetText(string.format("%s (Off)", displayName))
                row.text:SetTextColor(0.5, 0.5, 0.5)
                row:SetAlpha(0.5)
            elseif stateKey == "dead" then
                -- Druid is Dead -> Dark Red
                row.text:SetText(string.format("%s (Dead)", displayName))
                row.text:SetTextColor(0.75, 0.2, 0.2)
                row:SetAlpha(0.6)
            else
                -- Active Druid in group
                row.text:SetText(string.format("%s (%d)", displayName, casts))
                row.text:SetTextColor(1.0, 0.49, 0.04)
                -- NOTE: stateKey is "active|casts|slot" (or "active_oor|..."), so it can
                -- never exactly equal "active" - use the isRangeOk flag directly
                row:SetAlpha(isRangeOk and 1.0 or 0.65)
            end
        end

        -- Right side Cooldown / Ready Status Bar
        if remainingBuff > 0 then
            -- Active Buff (0-20s)
            if row.lastBarPhase ~= "buff" then
                row.lastBarPhase = "buff"
                row.readyText:Hide()
                row.bar:Show()
                row.bar:SetMinMaxValues(0, INNERVATE_BUFF_DURATION)
                row.bar:SetStatusBarColor(0.1, 0.7, 1.0, 0.9)
            end
            row.bar:SetValue(remainingBuff)

            local buffText = string.format("%s %ds", FormatDruidDisplayName(cdData.target or "Unknown"), math.ceil(remainingBuff))
            if row.bar.text:GetText() ~= buffText then
                row.bar.text:SetText(buffText)
            end

        elseif remainingCD > 0 then
            -- Cooldown Phase (20-360s)
            if row.lastBarPhase ~= "cd" then
                row.lastBarPhase = "cd"
                row.readyText:Hide()
                row.bar:Show()
                row.bar:SetMinMaxValues(0, INNERVATE_CD - INNERVATE_BUFF_DURATION)
                row.bar:SetStatusBarColor(1.0, 0.3, 0.3, 0.8)
            end
            row.bar:SetValue(remainingCD)

            local mins = math.floor(remainingCD / 60)
            local secs = math.floor(remainingCD % 60)
            local cdText = string.format("%dm%02ds", mins, secs)
            if row.bar.text:GetText() ~= cdText then
                row.bar.text:SetText(cdText)
            end

        else
            -- Ready
            if cdData then
                -- Only play the alert for a fresh in-session transition (castTime seen
                -- this session); stale entries pruned at init never trigger sound
                if InnervateTrackerDB.soundAlert and cdData.soundPlayed ~= true and cdData.castTime and (currentTime - cdData.castTime) < INNERVATE_CD then
                    pcall(PlaySound, 5274) -- SoundKit.ReadyCheck safely wrapped
                end
                InnervateTrackerDB.activeCDs[name] = nil
            end
            row.bar:Hide()
            if row.lastBarPhase ~= "ready" then
                row.lastBarPhase = "ready"
                row.readyText:SetText("|cff30ff30Ready|r")
            end
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

        -- Roster scan is the expensive part (dozens of C API calls per member:
        -- UnitName/UnitClass/UnitPowerType/range). Run it at 2 Hz; visual state
        -- changes it feeds are rare events, so latency is imperceptible.
        self.scanTimer = (self.scanTimer or 0) + 0.1
        if self.scanTimer >= 0.5 then
            self.scanTimer = 0
            ScanRaidRoster()
        end

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
    if not InnervateTrackerDB.castLog then InnervateTrackerDB.castLog = {} end
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

    -- Prune stale cooldowns persisted from a previous session (prevents spurious
    -- ReadyCheck sounds for cooldowns that expired while logged out)
    if InnervateTrackerDB.activeCDs then
        local now = time()
        for name, cd in pairs(InnervateTrackerDB.activeCDs) do
            if type(cd) == "table" and cd.castTime and (now - cd.castTime) >= INNERVATE_CD then
                InnervateTrackerDB.activeCDs[name] = nil
            end
        end
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
    elseif msg == "bind" then
        -- Session-only bindings: SetBinding without SaveBindings is never persisted,
        -- so player binding files are never touched (see tbc_addon_instructions.md)
        local defaults = { "F9", "F10", "F11" }
        local bound, skipped = 0, 0
        for i, key in ipairs(defaults) do
            local existingAction = GetBindingAction and GetBindingAction(key)
            if existingAction == "" or existingAction == nil then
                SetBinding(key, "INNERVATETRACKER_WHISPER" .. i)
                bound = bound + 1
            else
                skipped = skipped + 1
                print("|cffffea00[InnervateTracker]|r Skipped " .. key .. " (already bound to another action)")
            end
        end
        local suffix = skipped > 0 and ("; " .. skipped .. " skipped (use Keybindings menu to override).") or "."
        print("|cff30ff30[InnervateTracker]|r Bound " .. bound .. " slot key(s) for this session only" .. suffix)
        print("|cffffea00[InnervateTracker]|r Session bindings are lost on logout/reload - bind permanently via Options > Keybindings > AddOns.")
    elseif msg == "rangecheck" then
        -- Diagnostic: prints ground truth for the range-check chain
        local _, playerClass = UnitClass("player")
        print("|cffffea00[InnervateTracker]|r Range check diagnostics - class: " .. tostring(playerClass))
        print("  C_Spell.IsSpellInRange: " .. tostring(C_Spell and C_Spell.IsSpellInRange ~= nil) ..
              " | global IsSpellInRange: " .. tostring(IsSpellInRange ~= nil) ..
              " | UnitInRange: " .. tostring(UnitInRange ~= nil))
        local cands = GetRangeSpellCandidates()
        print("  Candidate spells (" .. #cands .. "): " .. table.concat(cands, ", "))
        local numGroup = GetNumGroupMembers()
        if numGroup == 0 then
            print("  Not in a group - nothing to check. (Solo: range fade never applies to yourself.)")
        else
            local prefix = IsInRaid() and "raid" or "party"
            for i = 1, math.min(numGroup, 10) do
                local unit = (not IsInRaid() and i == numGroup) and "player" or (prefix .. i)
                local name = UnitName(unit)
                if name then
                    local results = {}
                    for _, spellName in ipairs(cands) do
                        table.insert(results, spellName .. "=" .. tostring(QuerySpellRange(spellName, unit)))
                    end
                    local uir, checked
                    if UnitInRange then
                        uir, checked = UnitInRange(unit)
                    end
                    print(string.format("  %s (%s): %s | UnitInRange=%s(checked=%s)",
                        name, unit, table.concat(results, " "), tostring(uir), tostring(checked)))
                end
            end
            if numGroup > 10 then print("  ... (showing first 10 of " .. numGroup .. ")") end
        end
    else
        print("|cffffea00Innervate Tracker usage:|r")
        print("  /it reset - resets counters and session time.")
        print("  /it lock  - locks / unlocks frame dragging.")
        print("  /it sound - toggles sound alert when Innervate becomes Ready.")
        print("  /it bind  - binds F9/F10/F11 to whisper slots (this session only).")
        print("  /it rangecheck - prints range-check diagnostics for debugging.")
        print("  Keybinds: Options > Keybindings > AddOns > Innervate Tracker")
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

                    -- Timestamped log for the tooltip (newest first, capped at 10)
                    local log = InnervateTrackerDB.castLog[casterName]
                    if not log then
                        log = {}
                        InnervateTrackerDB.castLog[casterName] = log
                    end
                    table.insert(log, 1, {
                        t = time(),
                        target = targetName,
                        buffEnds = time() + INNERVATE_BUFF_DURATION,
                    })
                    if #log > 10 then table.remove(log) end

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
