-- ============================================================
--  Opulent Casting Bars -- Core.lua  (vanilla 1.12.1 / ClassicAPI)
--  Global namespace, saved settings, cast event handling and
--  login initialization.
-- ============================================================

local ADDON_NAME = "OpulentCastingBars"

-- Global namespace shared by every module. localization.lua loads
-- first and has already created it (with SCB.L), so extend it.
SCB = SCB or {}
SCB.TEX_PATH   = "Interface\\AddOns\\OpulentCastingBars\\textures\\"
-- Seconds FX layers stay at their current alpha once a cast ends. Longer
-- than every end-of-cast animation, so the single bar fade (Animations.lua)
-- is what fades them: every texture fades at the same rate.
SCB.FX_LINGER  = 1.2

-- ============================================================
--  SETTINGS (SavedVariables)
-- ============================================================

SCB.Config = {}

SCB.Config.defaults = {
    x            = 0,
    y            = -250,
    anchor       = "CENTER",
    barWidth     = 400,
    barHeight    = 200,
    locked            = true,
    showCastTime      = true,
    showSpellName     = true,
    hideBlizzardBar   = true,
    scale        = 0.8,
    defaultSchool = "metal",
    previewDuration = 3,
    useSchoolDetection = true,
    useThemeAssignments = false,
    themeAssignments = {},
    professionAssignments = {},
    spellThemeOverrides = {},
    -- Spell name text
    textNameSize   = 13,
    textNameAlign  = "LEFT",
    textNameColor  = "white",
    textNameTruncate = true,
    barStrata    = "MEDIUM",
    precacheOnLogin = true,
    -- Timer text
    textTimerSize  = 13,
    textTimerAlign = "RIGHT",
    textTimerColor = "white",
    -- Font and shared text style
    fontFace       = "Friz Quadrata TT",
    textOutline    = false,
    textCentered   = false,
    textCustomColor = {r=1.0, g=1.0, b=1.0},
    -- User XY offsets, added on top of each style's own text offsets
    textNamePosX  = 0,
    textNamePosY  = 0,
    textTimerPosX = 0,
    textTimerPosY = 0,
    -- Minimap button
    minimapButton      = true,
    minimapButtonAngle = 225,
}

-- Load the per-character SavedVariables table, fill in any missing defaults
-- (tables are copied so the defaults are never mutated). The account-wide
-- OpulentCastingBarsDB only holds the profiles (see Profiles.lua).
function SCB.Config:Init()
    OpulentCastingBarsDB = OpulentCastingBarsDB or {}
    OpulentCastingBarsCharDB = OpulentCastingBarsCharDB or {}
    for k, v in pairs(self.defaults) do
        if OpulentCastingBarsCharDB[k] == nil then
            if type(v) == "table" then
                local c = {}
                for tk, tv in pairs(v) do c[tk] = tv end
                OpulentCastingBarsCharDB[k] = c
            else
                OpulentCastingBarsCharDB[k] = v
            end
        end
    end
    self.db = OpulentCastingBarsCharDB
end

function SCB.Config:Get(key)
    return self.db[key]
end

-- Every write queues a save into the active profile (one at a time).
function SCB.Config:Set(key, value)
    self.db[key] = value
    if SCB and SCB.Profiles and SCB.Profiles.OnSettingChanged then
        SCB.Profiles:OnSettingChanged()
    end
end

-- Restore every setting to its default (table defaults are copied).
function SCB.Config:Reset()
    for k, v in pairs(self.defaults) do
        if type(v) == "table" then
            local c = {}
            for tk, tv in pairs(v) do c[tk] = tv end
            self.db[k] = c
        else
            self.db[k] = v
        end
    end
    -- The overrides table was replaced: re-point OCBSpellOverridesDB at it.
    if OCBSpellOverrides and OCBSpellOverrides.Sync then OCBSpellOverrides.Sync() end
    if SCB.Profiles and SCB.Profiles.OnSettingChanged then SCB.Profiles:OnSettingChanged() end
end

-- ============================================================
--  CAST EVENTS
-- ============================================================

SCB.Events = {}

-- Prefer the icon of the item actually being used, not an arbitrary item
-- that shares the spell. IsCurrentItem is ClassicAPI's active-use predicate.
-- Equipment and carried bags are scanned once per cast start (never per
-- tick), and only for spells that are not in the spellbook. Keeps the spell
-- texture when no item is in use or its icon is not cached yet.
function SCB.Events:ResolveCastIcon(spellTexture)
    for slot = 0, 19 do
        local itemID = GetInventoryItemID("player", slot)
        if itemID and IsCurrentItem(itemID) then
            return GetItemIcon(itemID) or spellTexture
        end
    end
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID and IsCurrentItem(itemID) then
                return GetItemIcon(itemID) or spellTexture
            end
        end
    end
    return spellTexture
end

-- Name, rank and icon of a spell ID (ClassicAPI GetSpellInfo works for any ID).
local function GetSpellIdentityByID(spellID)
    spellID = tonumber(spellID)
    if not spellID then return nil end
    return GetSpellInfo(spellID)
end

-- True when name matches and, if an expected rank is given, the rank matches too.
local function SpellIdentityMatches(name, rank, expectedName, expectedRank)
    if not name or not expectedName or name ~= expectedName then return false end
    if expectedRank and expectedRank ~= "" then
        return rank ~= nil and rank ~= "" and rank == expectedRank
    end
    return true
end

-- Find a spell's ID in the player's spellbook. With a rank, the first exact
-- match is returned; without one, the highest matching ID (top rank).
-- ClassicAPI's GetSpellInfo("Name") / GetSpellInfo("Name(Rank N)") resolves
-- a known spell in one call (its 10th return is the spellID); the result is
-- kept only if its name and rank really match. Otherwise (other subtexts,
-- such as profession ranks) the spellbook is walked with
-- C_SpellBook.GetSpellBookItemInfo, which gives name, rank and spellID.
local function FindSpellBookID(spellName, spellRank)
    if not spellName then return nil end

    local query = spellName
    if spellRank and spellRank ~= "" then query = spellName .. "(" .. spellRank .. ")" end
    local _, _, _, _, _, _, _, _, _, quickID = GetSpellInfo(query)
    quickID = tonumber(quickID)
    if quickID then
        local idName, idRank = GetSpellInfo(quickID)
        if SpellIdentityMatches(idName, idRank, spellName, spellRank) then return quickID end
    end

    local bank = Enum.SpellBookSpellBank.Player
    local bestID
    for tab = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
        local tabInfo = C_SpellBook.GetSpellBookSkillLineInfo(tab)
        if tabInfo then
            local offset = tabInfo.itemIndexOffset or 0
            for slot = offset + 1, offset + (tabInfo.numSpellBookItems or 0) do
                local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                local spellID = info and tonumber(info.spellID)
                if spellID and SpellIdentityMatches(info.name, info.subName, spellName, spellRank) then
                    if spellRank and spellRank ~= "" then return spellID end
                    if not bestID or spellID > bestID then bestID = spellID end
                end
            end
        end
    end
    return bestID
end

SCB.Events.spellIdentityCache = {}   -- "name\031rank" -> spellID, or false when unresolved
SCB.Events.recentCasts = {}          -- newest first, capped at 10 (Spells page history)
SCB.Events.castSerial = 0

-- Best spell ID for a cast. The event's own spellID is trusted only when
-- it really names this spell; otherwise fall back to the spellbook, then
-- to the addon's spell table (accepted only if it gives a single answer).
function SCB.Events:ResolveSpellID(eventSpellID, spellName, spellRank)
    local numericID = tonumber(eventSpellID)
    if numericID then
        local idName, idRank = GetSpellIdentityByID(numericID)
        if SpellIdentityMatches(idName, idRank, spellName, spellRank) then
            return numericID
        end
    end

    if not spellName then return nil end
    local cacheKey = spellName .. "\031" .. tostring(spellRank or "")
    -- false caches a miss, so an unresolvable spell does not rescan the
    -- spellbook and spell table on every cast (cleared on SPELLS_CHANGED).
    local cached = self.spellIdentityCache[cacheKey]
    if cached ~= nil then return cached or nil end

    local resolved = FindSpellBookID(spellName, spellRank)

    if not resolved and SCB.Schools and SCB.Schools.spellTable then
        local onlyMatch
        for id in pairs(SCB.Schools.spellTable) do
            local idName, idRank = GetSpellIdentityByID(id)
            if SpellIdentityMatches(idName, idRank, spellName, spellRank) then
                if spellRank and spellRank ~= "" then
                    onlyMatch = tonumber(id)
                    break
                elseif onlyMatch and onlyMatch ~= tonumber(id) then
                    onlyMatch = nil
                    break
                else
                    onlyMatch = tonumber(id)
                end
            end
        end
        resolved = onlyMatch
    end

    self.spellIdentityCache[cacheKey] = resolved or false
    return resolved
end

-- Record a cast start in the history. A repeat of the same spell within
-- 0.75 s updates the newest entry instead of adding a duplicate.
function SCB.Events:RememberLastCast(eventSpellID, spellName, spellRank, icon)
    local resolvedID = self:ResolveSpellID(eventSpellID, spellName, spellRank)
    self.lastCastSpellID = resolvedID
    self.lastCastName = spellName
    self.lastCastRank = spellRank
    self.lastCastIcon = icon

    local now = GetTime()
    local newest = self.recentCasts[1]
    local isDuplicate = newest
        and newest.name == spellName
        and tostring(newest.rank or "") == tostring(spellRank or "")
        and (now - (newest.time or 0)) < 0.75
    local record
    if isDuplicate then
        record = newest
        record.id = resolvedID or record.id
        record.icon = icon or record.icon
        record.rawEventSpellID = eventSpellID
        record.time = now
    else
        self.castSerial = self.castSerial + 1
        record = {
            serial = self.castSerial,
            id = resolvedID,
            name = spellName,
            rank = spellRank,
            icon = icon,
            rawEventSpellID = eventSpellID,
            time = now,
        }
        table.insert(self.recentCasts, 1, record)
        while #self.recentCasts > 10 do table.remove(self.recentCasts) end
    end
    self.lastCastRecord = record
    -- The Spells page refreshes once, in RecordCastResolution, which always follows.
    return record
end

-- Attach the detection result (natural style, override, final style) to the
-- newest history entry so the Spells page can explain it.
function SCB.Events:RecordCastResolution(eventSpellID, spellName, spellRank, finalStyle)
    local record = self.lastCastRecord
    if not record then return end

    local schools = SCB.Schools
    local naturalSchool = schools and schools.GetNaturalSchoolForSpell
        and schools:GetNaturalSchoolForSpell(self.lastCastSpellID, spellName) or nil
    record.rawEventSpellID = eventSpellID
    record.id = self.lastCastSpellID or record.id
    record.name = spellName or record.name
    record.rank = spellRank or record.rank
    record.naturalSchool = naturalSchool
    record.overrideID = schools and schools.lastOverrideMatchID or nil
    record.overrideTheme = schools and schools.lastOverrideMatchTheme or nil
    record.finalStyle = finalStyle
    self.lastResolution = record

    if SCB.Options and SCB.Options.RefreshFromConfig then
        SCB.Options.RefreshFromConfig()
    end
end

function SCB.Events:Register(frame)

    -- Player only: ClassicAPI fires START/STOP/CHANNEL_* once per unit token
    -- for every visible caster (target, party, nameplates...). The unit
    -- filter drops those before they reach Lua.
    frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    -- Tells a completed cast (SUCCEEDED, then STOP) from a cancelled one.
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
    frame:RegisterEvent("SPELLS_CHANGED")
    -- Sent by nampower only (spell queueing); harmless without it.
    frame:RegisterEvent("SPELL_QUEUE_EVENT")
    -- Handlers receive positional args (ClassicAPI SetModernScriptArgs).
    -- UNIT_SPELLCAST_* args: unit, castGUID, spellID, spellName, rank.
    frame:SetScript("OnEvent", function(self, event, a1, a2, a3, a4, a5)
        SCB.Events:Dispatch(event, a1, a2, a3, a4, a5)
    end)
end

-- Fishing channels report no usable timing; show a fixed 30 s bar.
local FISHING_IDS = { [7620]=true, [7731]=true, [7732]=true, [18248]=true }

-- STOP / CHANNEL_STOP fire whether the spell completed or was cut short
-- (a channel is never followed by INTERRUPTED, and a cancelled cast's STOP
-- may arrive before its INTERRUPTED). Decide which one it was, so a cut
-- short spell plays the cancel animation (flash of what was revealed)
-- rather than the completion flash:
--   * a cast completed if SUCCEEDED fired for it;
--   * otherwise (and for every channel, whose SUCCEEDED fires at its
--     start) it completed only if it stopped at, or within this margin
--     of, its scheduled end. Event timing is not exact, so the margin
--     keeps a spell that ends on time from reading as cancelled.
local EARLY_STOP_MARGIN = 0.25   -- seconds

function SCB.Events:IsCompletedStop(event, castGUID)
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if self.activeIsFishing then return true end
    elseif self.succeededGUID == castGUID then
        return true
    end
    -- nampower hand-off to a queued spell: never a cancel (see FAILED below).
    if self.npQueuedSpellID then return true end
    local bar = SCB.Bar
    if not (bar and bar.isActive and bar.castEnd) then return true end
    return (bar.castEnd - GetTime()) <= EARLY_STOP_MARGIN
end

function SCB.Events:Dispatch(event, unit, castGUID, spellID, spellName, spellRank)
    if event == "SPELLS_CHANGED" then
        self.spellIdentityCache = {}
        return
    end
    if event == "SPELL_QUEUE_EVENT" then
        -- nampower args are (eventCode, spellID), so they arrive in the
        -- unit / castGUID slots here.
        local eventCode = unit
        if eventCode == 2 or eventCode == 4 then  -- NORMAL_QUEUED / NON_GCD_QUEUED
            self.npQueuedSpellID = castGUID
        elseif eventCode == 3 or eventCode == 5 then  -- NORMAL_QUEUE_POPPED / NON_GCD_QUEUE_POPPED
            self.npQueuedSpellID = nil
        end
        return
    end

    if unit ~= "player" then return end

    if SCB._debugMode then
        print(string.format("|cffFF9900[OCB Debug]|r event=|cffffff00%s|r spellID=|cffAAFFAA%s|r name=|cffffff00%s|r",
            tostring(event), tostring(spellID), tostring(spellName)))
    end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        local isChannel = (event == "UNIT_SPELLCAST_CHANNEL_START")

        -- Name/rank come with the event; timing and icon come from
        -- C_Spell.CastingInfo / ChannelInfo, the player-only forms of
        -- UnitCastingInfo / UnitChannelInfo (positional returns: name,
        -- displayName, texture, startTimeMs, endTimeMs, ...).
        local name = spellName
        local texture, startMS, endMS

        if isChannel then
            local n, _, tex, sms, ems = C_Spell.ChannelInfo()
            name    = name or n
            texture = tex
            startMS = sms
            endMS   = ems
        else
            local n, _, tex, sms, ems = C_Spell.CastingInfo()
            name    = name or n
            texture = tex
            startMS = sms
            endMS   = ems
        end
        if not name then return end

        self:RememberLastCast(spellID, name, spellRank, texture)

        if SCB._debugMode then
            print(string.format("|cffFF9900[OCB Debug]|r  -> name=|cffffff00%s|r", tostring(name)))
        end

        local duration
        if FISHING_IDS[tonumber(spellID) or 0] then
            duration = 30
            startMS  = GetTime() * 1000
            endMS    = startMS + 30000
        else
            duration = math.max(((endMS or 0) - (startMS or 0)) / 1000, 0)
            -- Timing can be missing right after a cancel + instant recast.
            -- Reuse this spell's last known duration so StartCast does not
            -- receive 0 and bail out.
            local durKey = spellID or name   -- never index with nil
            if duration <= 0 then
                duration = (self._lastDuration and self._lastDuration[durKey]) or 0
                startMS  = nil
                endMS    = nil
            else
                self._lastDuration = self._lastDuration or {}
                self._lastDuration[durKey] = duration
            end
        end

        local school   = SCB.Schools:DetectFromSpell(spellID, name, spellRank)
        self:RecordCastResolution(spellID, name, spellRank, school)

        -- A new cast makes any late FAILED/INTERRUPTED for the previous
        -- one irrelevant; without this, such an event would stop this cast.
        self.lastStoppedGUID = nil

        if school == "blizzard" then
            -- This spell is assigned to the default Blizzard bar.
            if SCB._blizzardDynamic then SCB.HideBlizzardBarFrames(false) end
            self.activeCastGUID = castGUID
            return
        end

        self.activeCastGUID = castGUID
        self.succeededGUID  = nil
        self.activeIsChannel = isChannel
        -- Fishing's bar is a fixed 30 s: the channel normally ends early
        -- (a catch), so its stop always counts as a completion.
        self.activeIsFishing = FISHING_IDS[tonumber(spellID) or 0] and true or false
        -- This cast consumed the spell nampower had queued.
        if self.npQueuedSpellID == spellID then
            self.npQueuedSpellID = nil
        end
        -- A spell from the spellbook is never an item's use effect: skip the
        -- equipment and bag scan for it (ClassicAPI IsSpellKnown).
        local numericID = tonumber(spellID)
        local barIcon = (numericID and IsSpellKnown(numericID)) and texture
            or self:ResolveCastIcon(texture)
        SCB.Bar:StartCast(name, duration, school, isChannel, barIcon, startMS, endMS)

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Casts: SUCCEEDED comes right before STOP when the spell goes off.
        -- (A channel fires it at its start, so it says nothing there.)
        if castGUID == self.activeCastGUID and not self.activeIsChannel then
            self.succeededGUID = castGUID
        end

    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if castGUID ~= self.activeCastGUID then return end
        self.activeCastGUID = nil
        self.lastStoppedGUID = castGUID
        SCB.Bar:StopCast(self:IsCompletedStop(event, castGUID))
        self.succeededGUID = nil

    elseif event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- A failure normally precedes STOP. One that arrives after STOP for
        -- the cast that just ended (lastStoppedGUID) is still accepted, but
        -- the end animation STOP chose keeps playing.
        if castGUID ~= self.activeCastGUID and castGUID ~= self.lastStoppedGUID then return end
        self.activeCastGUID  = nil
        self.lastStoppedGUID = nil
        -- nampower already announced a queued spell: this "interrupt" is the
        -- hand-off to the next cast, not a real cancel, so skip the fail animation.
        if self.npQueuedSpellID then
            self.npQueuedSpellID = nil
            return
        end
        SCB.Bar:StopCast(false)

    elseif event == "UNIT_SPELLCAST_DELAYED"
        or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        if castGUID ~= self.activeCastGUID then return end
        -- Pushback: the event carries no timing, so re-read it.
        local _, _, _, sms, ems
        if event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
            _, _, _, sms, ems = C_Spell.ChannelInfo()
        else
            _, _, _, sms, ems = C_Spell.CastingInfo()
        end
        if sms and ems then
            SCB.Bar:ApplyPushback(sms / 1000, ems / 1000)
        end
    end
end

-- ============================================================
--  HIDE BLIZZARD CAST BAR
-- ============================================================

local BLIZZARD_BARS = {
    "CastingBarFrame",
}

-- Two hiding modes:
--   static  : the Blizzard bar is always hidden (alpha 0).
--   dynamic : used when some school/profession is assigned to the
--             "Blizzard UI" style; the bar is hidden or shown per cast.
SCB._blizzardDynamic = false
local _blizzStaticHide = false
local _blizzHooked = {}

-- Static hide: hook the Blizzard bar's own OnShow/OnUpdate so the cost is
-- only paid while that bar is shown, and its scripts stay intact so it
-- can be restored when the option is turned off.
local function HookBlizzardBars()
    for _, name in ipairs(BLIZZARD_BARS) do
        local f = _G[name]
        if f and not _blizzHooked[name] then
            _blizzHooked[name] = true
            local function enforce()
                if _blizzStaticHide and f:GetAlpha() ~= 0 then f:SetAlpha(0) end
            end
            f:HookScript("OnShow", enforce)
            f:HookScript("OnUpdate", enforce)
        end
    end
end

-- True when any school or profession is assigned to the Blizzard bar.
local function HasBlizzardAssignments()
    if not (SCB.Config and SCB.Config:Get("useThemeAssignments")) then return false end
    local assignments = SCB.Config:Get("themeAssignments") or {}
    for _, v in pairs(assignments) do
        if v == "blizzard" then return true end
    end
    local profs = SCB.Config:Get("professionAssignments") or {}
    for skillID, v in pairs(profs) do
        -- Skip professions this client does not have (Turtle-only ones
        -- on other clients, e.g. from a shared profile).
        if v == "blizzard" and SCB.Schools:IsProfessionAvailable(skillID) then
            return true
        end
    end
    return false
end

function SCB.HideBlizzardBarFrames(hide)
    local a = hide and 0 or 1
    for _, name in ipairs(BLIZZARD_BARS) do
        local f = _G[name]
        if f then f:SetAlpha(a) end
    end
end

function SCB.ApplyHideBlizzardBar(hide)
    if hide then
        if HasBlizzardAssignments() then
            SCB._blizzardDynamic = true
            _blizzStaticHide = false
            SCB.HideBlizzardBarFrames(true)
        else
            SCB._blizzardDynamic = false
            _blizzStaticHide = true
            HookBlizzardBars()
            SCB.HideBlizzardBarFrames(true)
        end
    else
        SCB._blizzardDynamic = false
        _blizzStaticHide = false
        for _, name in ipairs(BLIZZARD_BARS) do
            local f = _G[name]
            if f then
                f:SetAlpha(1)
                for _, child in ipairs({f:GetChildren()}) do child:SetAlpha(1) end
                for _, region in ipairs({f:GetRegions()}) do region:SetAlpha(1) end
            end
        end
    end
end

-- ============================================================
--  INIT
-- ============================================================

-- ADDON_LOADED (ours): SavedVariables are available -> load settings.
-- PLAYER_LOGIN: every addon is loaded -> build the bar and the UI.
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")

initFrame:SetScript("OnEvent", function(self, event, addonName)

    if event == "ADDON_LOADED" and addonName == ADDON_NAME then
        SCB.Config:Init()

        -- Public spell-override API (OCBSpellOverrides), also used by the
        -- Spells page. OCBSpellOverridesDB always points at the live
        -- spellThemeOverrides table of the current settings.
        local function SyncSpellOverridesDB()
            local db = SCB.Config:Get("spellThemeOverrides")
            if type(db) ~= "table" then
                db = {}
                SCB.Config:Set("spellThemeOverrides", db)
            end
            OCBSpellOverridesDB = db
            return db
        end

        SyncSpellOverridesDB()
        OCBSpellOverrides = OCBSpellOverrides or {}
        OCBSpellOverrides.Sync = SyncSpellOverridesDB
        function OCBSpellOverrides.Set(spellID, school)
            spellID = tonumber(spellID)
            if not spellID or spellID <= 0 then return false end
            if not school or (SCB.Schools and not SCB.Schools:Exists(school)) then return false end
            local db = SyncSpellOverridesDB()
            db[tostring(spellID)] = nil
            db[spellID] = school
            SCB.Config:Set("spellThemeOverrides", db)
            return true
        end
        function OCBSpellOverrides.Remove(spellID)
            spellID = tonumber(spellID)
            if not spellID then return end
            local db = SyncSpellOverridesDB()
            db[spellID] = nil
            db[tostring(spellID)] = nil
            SCB.Config:Set("spellThemeOverrides", db)
        end
        function OCBSpellOverrides.Clear()
            SCB.Config:Set("spellThemeOverrides", {})
            SyncSpellOverridesDB()
        end

    elseif event == "PLAYER_LOGIN" then
        SCB.Bar:Create()
        SCB.Profiles:Init()      -- loads this character's profile first,
        SCB.Options:Create()     -- so the pages start with its values
        if OCBSpellOverrides and OCBSpellOverrides.Sync then
            OCBSpellOverrides.Sync()
        end
        SCB.Commands:Register()

        local bar = SCB.Bar.frame
        bar:SetScale(SCB.Config:Get("scale"))
        bar:ClearAllPoints()
        bar:SetPoint(
            SCB.Config:Get("anchor"), UIParent, SCB.Config:Get("anchor"),
            SCB.Config:Get("x"), SCB.Config:Get("y"))
        bar:EnableMouse(not SCB.Config:Get("locked"))

        SCB.ApplyHideBlizzardBar(SCB.Config:Get("hideBlizzardBar"))
        SCB.MinimapButton_Init()

        -- Init is done: Register() replaces this handler with the cast-event
        -- dispatcher, which must not receive later ADDON_LOADED events.
        initFrame:UnregisterEvent("ADDON_LOADED")
        initFrame:UnregisterEvent("PLAYER_LOGIN")
        SCB.Events:Register(initFrame)

        if SCB.Precache and SCB.Config:Get("precacheOnLogin") then
            C_Timer.After(10, function() SCB.Precache:Start() end)
        end

        -- Inferno and Void are the heaviest styles: build Inferno's FX early
        -- so its first cast after login does not hitch, and, unless the full
        -- pre-warm option already covers them, warm both styles' textures
        -- (Void's include the fill vortex).
        C_Timer.After(2, function()
            if SCB.Particles and SCB.Particles.PrewarmFX then
                SCB.Particles:PrewarmFX("inferno")
            end
            if SCB.Precache and SCB.Precache.StartSchool and not SCB.Config:Get("precacheOnLogin") then
                SCB.Precache:StartSchool("inferno", 1)
                SCB.Precache:StartSchool("void", 1)
            end
        end)

    end
end)
