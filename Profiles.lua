-- ============================================================
--  Opulent Casting Bars -- Profiles.lua
--
--  Lightweight profile system built on the raw SavedVariables.
--  Profile data is shared across all characters (OpulentCastingBarsDB);
--  which profile is active is stored per-character (OpulentCastingBarsCharDB)
--  so each character remembers their own selection independently.
--
--  OpulentCastingBarsDB:
--    __profiles = {
--        ["Default"]    = { main={...}, modules={...} },
--        ["My Layout"]  = { main={...}, modules={...} },
--    }
--    __activeProfiles = {
--        ["Character-Realm"] = "ProfileName",
--    }
--
--  OpulentCastingBarsCharDB (per-character):
--    <every setting>   = this character's live settings
--    __currentProfile  = "Default"
--
--  A new character gets its own profile, named "Name-Realm" and
--  seeded from Default.
--
--  "modules" captures the settings of the optional, separately
--  installed OCB modules (Instant Cast, Unit Frame Cast Bars) when
--  they are loaded; their tables are simply absent otherwise.
--
--  Call Init() after SCB.Config:Init().
-- ============================================================

SCB.Profiles = {}

-- ---- Storage keys ------------------------------------------
local PROFILE_KEY    = "__currentProfile"
local PROFILES_KEY   = "__profiles"
local ACTIVE_MAP_KEY = "__activeProfiles"
local DEFAULT        = "Default"
SCB.Profiles.DEFAULT = DEFAULT   -- the profile that cannot be deleted

-- ---- OCBInstantCastDB flat keys (overrides table copied separately)
local IC_KEYS = { "enabled", "disableWhileMounted", "disableWhileDruidFlightForm" }

-- ---- OCBUnitFrameCastBarsDB keys (mirrors DEFAULT_CFG in that module),
-- plus the optional per-unit overrides (targetScale, ...) it can set.
local UF_KEYS = {
    "enabled", "scale", "barWidth", "barHeight",
    "targetEnabled", "focusEnabled", "bossEnabled",
    "targetPos", "focusPos", "boss1Pos", "boss2Pos", "boss3Pos", "boss4Pos", "boss5Pos",
    "hideBlizzTarget", "hideBlizzFocus",
    "targetShowFriendly", "targetShowHostile", "focusShowFriendly", "focusShowHostile",
    "showSpellName", "showCastTime", "showShield", "defaultSchool", "previewDuration",
    "textFont", "textNameSize", "textNameAnchor", "textNameX", "textNameY",
    "textTimerSize", "textTimerAnchor", "textTimerX", "textTimerY",
    "textOutline", "textShadow",
    "textNameColor", "textTimerColor",
    "textNameColorCustomR", "textNameColorCustomG", "textNameColorCustomB",
    "textTimerColorCustomR", "textTimerColorCustomG", "textTimerColorCustomB",
    -- Per-unit overrides (may be nil; captured when set, cleared on apply when absent)
    "targetScale", "focusScale", "bossScale",
    "targetWidth", "focusWidth", "bossWidth",
}

-- ---- Helpers -----------------------------------------------
local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = DeepCopy(v) end
    return c
end

-- ---- Snapshot: copy live settings into a plain table -------
-- Every value is deep-copied so table settings (e.g. textCustomColor)
-- never share references between profiles and the live DB.
local function SnapMain()
    local s = {}
    for k in pairs(SCB.Config.defaults) do s[k] = DeepCopy(SCB.Config:Get(k)) end
    return s
end

local function SnapModules()
    local m = {}
    if OCBInstantCastDB then
        local ic = {}
        for _, k in ipairs(IC_KEYS) do ic[k] = OCBInstantCastDB[k] end
        -- overrides may be nil on first-run (seeded by the module's own PLAYER_LOGIN
        -- which fires after ours); fall back to an empty table instead of nil.
        ic.overrides = DeepCopy(OCBInstantCastDB.overrides) or {}
        m.instantcast = ic
    end
    if OCBUnitFrameCastBarsDB then
        local uf = {}
        for _, k in ipairs(UF_KEYS) do uf[k] = DeepCopy(OCBUnitFrameCastBarsDB[k]) end
        m.unitframes = uf
    end
    return m
end

-- ---- Apply: push the live settings to the bar and the UI ---
local function ApplyLive()
    SCB.Bar:Resize(SCB.Config:Get("barWidth"), SCB.Config:Get("barHeight"))
    SCB.Bar.frame:SetScale(SCB.Config:Get("scale"))
    SCB.Bar.frame:ClearAllPoints()
    SCB.Bar.frame:SetPoint(
        SCB.Config:Get("anchor"), UIParent, SCB.Config:Get("anchor"),
        SCB.Config:Get("x"), SCB.Config:Get("y"))
    SCB.Bar.frame:EnableMouse(not SCB.Config:Get("locked"))
    SCB.Bar.frame:SetFrameStrata(SCB.Config:Get("barStrata") or "MEDIUM")
    if SCB.Bar.frameInner then SCB.Bar.frameInner:SetFrameStrata(SCB.Config:Get("barStrata") or "MEDIUM") end
    SCB.ApplyHideBlizzardBar(SCB.Config:Get("hideBlizzardBar"))
    SCB.Bar:ApplyTextPrefs()
    if SCB.MinimapButton_Update then SCB.MinimapButton_Update() end
    -- Redraw the options window controls (if built) from the new settings.
    if SCB.Options.RefreshWidgets then SCB.Options.RefreshWidgets() end
    if SCB.Options.RefreshFromConfig then SCB.Options.RefreshFromConfig() end
end

-- Write a profile's main settings into the live config.

local function ApplyMain(snap)
    if not snap then return end
    -- DeepCopy each value so restoring a profile doesn't share table
    -- references between the snapshot and the live DB.
    for k, v in pairs(snap) do SCB.Config:Set(k, DeepCopy(v)) end
    -- Back-fill keys that exist in defaults but are absent from this snapshot
    -- (profiles saved before a new key was added).  Prevents new settings from
    -- bleeding across profiles instead of resetting to their default value.
    for k, v in pairs(SCB.Config.defaults) do
        if snap[k] == nil then
            SCB.Config:Set(k, type(v) == "table" and DeepCopy(v) or v)
        end
    end
end

local function ApplyModules(mods)
    if not mods then return end
    -- Instant Cast
    if mods.instantcast and OCBInstantCastDB then
        for _, k in ipairs(IC_KEYS) do
            if mods.instantcast[k] ~= nil then OCBInstantCastDB[k] = mods.instantcast[k] end
        end
        if mods.instantcast.overrides then
            OCBInstantCastDB.overrides = DeepCopy(mods.instantcast.overrides)
        end
    end
    -- Point OCBSpellOverridesDB at the spellThemeOverrides table ApplyMain restored.
    if OCBSpellOverrides and OCBSpellOverrides.Sync then OCBSpellOverrides.Sync() end
    -- Unit Frame Cast Bars
    if mods.unitframes and OCBUnitFrameCastBarsDB then
        if mods.unitframes.__resetToDefaults then
            -- Blank profile: Reset() deferred to apply time (not snapshot time)
            if OCBUnitFrameCastBars and OCBUnitFrameCastBars.Reset then
                OCBUnitFrameCastBars.Reset()
            end
        else
            -- Clear per-unit overrides first so a profile that never set them
            -- doesn't carry stale values forward from a previous profile.
            OCBUnitFrameCastBarsDB.targetScale = nil
            OCBUnitFrameCastBarsDB.focusScale  = nil
            OCBUnitFrameCastBarsDB.bossScale   = nil
            OCBUnitFrameCastBarsDB.targetWidth = nil
            OCBUnitFrameCastBarsDB.focusWidth  = nil
            OCBUnitFrameCastBarsDB.bossWidth   = nil
            OCBUnitFrameCastBarsDB.bossPos     = nil  -- legacy single-key
            -- Restore snapshot values (non-nil only; nil keys were cleared above)
            for _, k in ipairs(UF_KEYS) do
                if mods.unitframes[k] ~= nil then OCBUnitFrameCastBarsDB[k] = DeepCopy(mods.unitframes[k]) end
            end
            if OCBUnitFrameCastBars and OCBUnitFrameCastBars.ApplyAllSettings then
                OCBUnitFrameCastBars.ApplyAllSettings()
            end
        end
    end
end

-- ============================================================
--  PUBLIC API
-- ============================================================

local function GetCharKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "UnknownRealm"
    return tostring(name) .. "-" .. tostring(realm)
end

local function ValidProfileName(name)
    return type(name) == "string" and name ~= ""
end

-- Create profile `name` if missing, copied from `sourceName`, else from
-- Default, else from the live settings.
local function EnsureProfile(name, sourceName)
    if not ValidProfileName(name) then return end

    local db = OpulentCastingBarsDB
    if not db then return end

    db[PROFILES_KEY] = db[PROFILES_KEY] or {}
    local profiles = db[PROFILES_KEY]
    if profiles[name] then return end

    local source = ValidProfileName(sourceName) and profiles[sourceName] or nil
    source = source or profiles[DEFAULT]

    if source then
        profiles[name] = DeepCopy(source)
    else
        profiles[name] = { main = SnapMain(), modules = SnapModules() }
    end
end

-- Remember `name` as this character's profile, both per character and in
-- the shared map (the map lets Delete() redirect other characters).
local function SetCurrentProfile(name)
    OpulentCastingBarsCharDB = OpulentCastingBarsCharDB or {}
    OpulentCastingBarsCharDB[PROFILE_KEY] = name
    OpulentCastingBarsDB[ACTIVE_MAP_KEY] = OpulentCastingBarsDB[ACTIVE_MAP_KEY] or {}
    OpulentCastingBarsDB[ACTIVE_MAP_KEY][GetCharKey()] = name
end

function SCB.Profiles:Init()
    local db = OpulentCastingBarsDB
    if not db[PROFILES_KEY] then db[PROFILES_KEY] = {} end
    -- First run: seed Default from the current settings.
    if not db[PROFILES_KEY][DEFAULT] then
        db[PROFILES_KEY][DEFAULT] = { main = SnapMain(), modules = SnapModules() }
    end
    db[ACTIVE_MAP_KEY] = db[ACTIVE_MAP_KEY] or {}

    OpulentCastingBarsCharDB = OpulentCastingBarsCharDB or {}

    -- The shared map is authoritative (Delete() can only update it, not
    -- other characters' own SavedVariables); the per-character value is
    -- the fallback if the map lost this character.
    local charKey = GetCharKey()
    local charProfile = db[ACTIVE_MAP_KEY][charKey] or OpulentCastingBarsCharDB[PROFILE_KEY]
    if not charProfile then
        -- Brand-new character: give it its own profile, seeded from Default.
        charProfile = charKey
        EnsureProfile(charProfile, DEFAULT)
    end

    -- A profile deleted on another character falls back to Default
    -- (it is never silently re-created).
    local snap = db[PROFILES_KEY][charProfile]
    if not snap then
        SetCurrentProfile(DEFAULT)
        charProfile = DEFAULT
        snap = db[PROFILES_KEY][DEFAULT]
    end
    if snap then
        SetCurrentProfile(charProfile)
        self._suspendAutosave = true
        local ok, err = pcall(function()
            ApplyMain(snap.main)
            ApplyModules(snap.modules)
            ApplyLive()
        end)
        self._suspendAutosave = nil
        if not ok then geterrorhandler()(err) end
    end
end

-- Config:Set fires on every slider tick, so the full profile snapshot is
-- batched: the first change queues one SaveCurrent shortly after, and
-- logout flushes anything still pending.
local _saveQueued = false
local function FlushSave()
    _saveQueued = false
    if not OpulentCastingBarsDB or not OpulentCastingBarsDB[PROFILES_KEY] then return end
    if not OpulentCastingBarsCharDB then return end
    SCB.Profiles:SaveCurrent()
end

function SCB.Profiles:OnSettingChanged()
    if self._suspendAutosave or _saveQueued then return end
    _saveQueued = true
    C_Timer.After(0.5, function() if _saveQueued then FlushSave() end end)
end

local _logoutFrame = CreateFrame("Frame")
_logoutFrame:RegisterEvent("PLAYER_LOGOUT")
_logoutFrame:SetScript("OnEvent", function() if _saveQueued then FlushSave() end end)

function SCB.Profiles:GetCurrent()
    return OpulentCastingBarsCharDB and OpulentCastingBarsCharDB[PROFILE_KEY] or DEFAULT
end

function SCB.Profiles:GetAll()
    EnsureProfile(DEFAULT)

    local list = {}
    for name in pairs(OpulentCastingBarsDB[PROFILES_KEY] or {}) do
        list[#list + 1] = name
    end
    table.sort(list, function(a, b)
        if a == b then return false end
        if a == DEFAULT then return true end
        if b == DEFAULT then return false end
        return a < b
    end)
    return list
end

-- Persist live settings into the currently active profile snapshot.
function SCB.Profiles:SaveCurrent()
    local name = self:GetCurrent()
    local db   = OpulentCastingBarsDB[PROFILES_KEY]
    db[name]         = db[name] or {}
    SetCurrentProfile(name)
    db[name].main    = SnapMain()
    db[name].modules = SnapModules()
end

-- Switch profiles (created from Default if missing); saves the current one first.
function SCB.Profiles:Switch(name)
    local db = OpulentCastingBarsDB
    EnsureProfile(name, DEFAULT)
    if not db[PROFILES_KEY][name] then return false end
    self:SaveCurrent()
    local snap = db[PROFILES_KEY][name]
    SetCurrentProfile(name)
    self._suspendAutosave = true
    local ok, err = pcall(function()
        ApplyMain(snap.main)
        ApplyModules(snap.modules)
        ApplyLive()
    end)
    self._suspendAutosave = nil
    if not ok then geterrorhandler()(err) end
    return true
end

-- "Fresh" module settings for a blank profile:
--   Instant Cast    : enabled, default GCD overrides only
--   Unit Frame Bars : reset to module defaults via its Reset() API
-- (Spell overrides live in the main settings, so blank main clears them.)
local function BlankModules()
    local m = {}
    if OCBInstantCastDB then
        m.instantcast = {
            enabled                     = true,
            disableWhileMounted         = false,
            disableWhileDruidFlightForm = false,
            -- Mirrors the DEFAULT_OVERRIDES table hardcoded in OCB_InstantCast.lua
            overrides = {
                [188196] = { base = 1.5 },  -- Lightning Bolt (Shaman)
                [768]    = { base = 1.0 },  -- Cat Form (Druid)
                [452201] = { base = 1.5 },  -- Tempest (Shaman)
            },
        }
    end
    if OCBUnitFrameCastBarsDB then
        -- Store a sentinel so ApplyModules calls Reset() at apply time.
        -- This avoids mutating live UF state during profile creation/snapshot.
        m.unitframes = { __resetToDefaults = true }
    end
    return m
end

-- Create a new profile, then switch to it.
--   copyFromCurrent = true  -> copy live settings
--   copyFromCurrent = false -> blank: main defaults + clean module state
function SCB.Profiles:New(name, copyFromCurrent)
    local db = OpulentCastingBarsDB
    if not ValidProfileName(name) then return false, "Invalid profile name" end
    if db[PROFILES_KEY][name] then return false, "Profile already exists" end
    -- Save the outgoing profile first, so a pending change is
    -- not lost or written into the new profile.
    self:SaveCurrent()
    if copyFromCurrent then
        db[PROFILES_KEY][name] = DeepCopy(db[PROFILES_KEY][self:GetCurrent()])
    else
        -- BlankModules() stores a sentinel for UF; ApplyModules (called below)
        -- defers the actual UF Reset() to apply time, keeping live state clean.
        db[PROFILES_KEY][name] = { main = DeepCopy(SCB.Config.defaults), modules = BlankModules() }
    end
    SetCurrentProfile(name)
    self._suspendAutosave = true
    local ok, err = pcall(function()
        ApplyMain(db[PROFILES_KEY][name].main)
        ApplyModules(db[PROFILES_KEY][name].modules)
        ApplyLive()
    end)
    self._suspendAutosave = nil
    if not ok then geterrorhandler()(err) end
    return true
end

-- Delete a named profile. Characters using it (including this one) move
-- to Default. Switch() is not used: it would SaveCurrent() first and
-- re-create the profile being deleted.
function SCB.Profiles:Delete(name)
    if name == DEFAULT then return false end   -- the Delete button is greyed out for it
    local profiles = OpulentCastingBarsDB[PROFILES_KEY]
    if not profiles[name] then return false, "Profile not found" end
    profiles[name] = nil
    local activeMap = OpulentCastingBarsDB[ACTIVE_MAP_KEY]
    if activeMap then
        for charKey, profileName in pairs(activeMap) do
            if profileName == name then activeMap[charKey] = DEFAULT end
        end
    end
    if self:GetCurrent() == name then
        -- Manually apply Default without saving to the now-gone profile.
        local snap = profiles[DEFAULT]
        SetCurrentProfile(DEFAULT)
        if snap then
            self._suspendAutosave = true
            local ok, err = pcall(function()
                ApplyMain(snap.main)
                ApplyModules(snap.modules)
                ApplyLive()
            end)
            self._suspendAutosave = nil
            if not ok then geterrorhandler()(err) end
        end
    end
    return true
end

-- Reset a profile to addon defaults (current profile if name omitted).
function SCB.Profiles:Reset(name)
    name = name or self:GetCurrent()
    local blank = DeepCopy(SCB.Config.defaults)
    local blankMods = BlankModules()  -- resets IC and UF (via sentinel)
    OpulentCastingBarsDB[PROFILES_KEY][name] = { main = blank, modules = blankMods }
    if self:GetCurrent() == name then
        self._suspendAutosave = true
        local ok, err = pcall(function()
            ApplyMain(blank)
            ApplyModules(blankMods)
            ApplyLive()
        end)
        self._suspendAutosave = nil
        if not ok then geterrorhandler()(err) end
    end
end

-- Copy the settings FROM another existing profile INTO the current profile.
-- Mirrors AceDB's CopyProfile: the active profile stays active, but its stored
-- data is replaced by a copy of the source, then applied live.
function SCB.Profiles:Copy(sourceName)
    local db = OpulentCastingBarsDB[PROFILES_KEY]
    if not db then return false, "No profiles" end
    local current = self:GetCurrent()
    if not sourceName or sourceName == current then
        return false, "Choose a different profile to copy from"
    end
    local src = db[sourceName]
    if not src then return false, "Source profile not found" end

    db[current] = DeepCopy(src)
    self._suspendAutosave = true
    local ok, err = pcall(function()
        ApplyMain(db[current].main)
        ApplyModules(db[current].modules)
        ApplyLive()
    end)
    self._suspendAutosave = nil
    if not ok then geterrorhandler()(err) end
    return true
end
