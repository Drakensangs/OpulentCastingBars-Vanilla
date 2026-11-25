-- ============================================================
--  Opulent Casting Bars -- Options.lua
--
--  Minimap button handlers and the addon's pages in ClassicAPI's
--  Options window (AddOns tab):
--
--    Opulent Casting Bars      overview and slash commands
--      General                 size, position, behaviour
--      Style                   school detection, default style
--      Text                    font, spell name and timer text
--      Schools                 school / profession -> style
--      Spells                  per-spell style overrides
--      Profiles                switch, create, copy, delete, reset
--
--  Pages are built with SettingsUI.lua on the window's own
--  Settings API. Saved settings proxy SCB.Config keys; preview and
--  editor selections last for the session only.
-- ============================================================

SCB.Options = SCB.Options or {}

local L  = SCB.L
local UI = SCB.UI
local ADDON_TITLE  = "Opulent Casting Bars"
local ADDON_PREFIX = "|cff00CCFFOpulent Casting Bars|r -- "

-- ============================================================
--  MINIMAP BUTTON  (frame defined in OpulentCastingBars.xml)
-- ============================================================

local OCB_MINIMAP_RADIUS        = 80
local OCB_MINIMAP_DEFAULT_ANGLE = 225

local function OCBMinimapGetAngle()
    return SCB.Config:Get("minimapButtonAngle") or OCB_MINIMAP_DEFAULT_ANGLE
end

local function OCBMinimapSaveAngle(angle)
    SCB.Config:Set("minimapButtonAngle", angle)
end

local function OCBMinimapUpdatePosition()
    local frame = OCBMinimapButtonFrame
    if not frame then return end
    local angle = OCBMinimapGetAngle()
    local rad   = math.rad(angle)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(rad) * OCB_MINIMAP_RADIUS, math.sin(rad) * OCB_MINIMAP_RADIUS)
end

-- Show/hide the button according to the "minimapButton" setting.
function SCB.MinimapButton_Update()
    local frame = OCBMinimapButtonFrame
    if not frame then return end
    if SCB.Config:Get("minimapButton") then
        frame:Show()
        OCBMinimapUpdatePosition()
    else
        frame:Hide()
    end
end

function SCB.MinimapButton_Init()
    SCB.MinimapButton_Update()
end

-- While right-dragging: follow the cursor around the minimap edge.
function OCBMinimapButton_OnUpdate()
    local mx, my = Minimap:GetCenter()
    local scale  = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx = cx / scale
    cy = cy / scale
    local angle = math.deg(math.atan2(cy - my, cx - mx))
    local frame = OCBMinimapButtonFrame
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(math.rad(angle)) * OCB_MINIMAP_RADIUS, math.sin(math.rad(angle)) * OCB_MINIMAP_RADIUS)
    OCBMinimapSaveAngle(angle)
end

function OCBMinimapButton_OnMouseDown(button)
    if button == "RightButton" then
        OCBMinimapButton:SetScript("OnUpdate", OCBMinimapButton_OnUpdate)
    end
end

function OCBMinimapButton_OnMouseUp(button)
    if button == "RightButton" then
        OCBMinimapButton:SetScript("OnUpdate", nil)
        OCBMinimapUpdatePosition()
    elseif button == "LeftButton" then
        if IsShiftKeyDown() then
            SCB.PreviewSchool(SCB.Config:Get("defaultSchool"))
        else
            SCB.Options:Toggle()
        end
    end
end

function OCBMinimapButton_OnEnter()
    GameTooltip:SetOwner(OCBMinimapButton, "ANCHOR_LEFT")
    GameTooltip:SetText("|cff00CCFFOpulent Casting Bars|r")
    GameTooltip:AddLine(L["Left click to open the options menu."], 1, 1, 1)
    GameTooltip:AddLine(L["Shift left click to preview the cast bar."], 1, 1, 1)
    GameTooltip:AddLine(L["Hold right click to move the minimap button."], 1, 1, 1)
    GameTooltip:Show()
end

function OCBMinimapButton_OnLeave()
    GameTooltip:Hide()
end

-- ============================================================
--  CONSTANTS
-- ============================================================

-- Every selectable style. Lists are shown sorted by (localized) label.
local STYLE_ORDER = {
    "neutral","neutral2","neutral3","metal","metal_icon","gears",
    "honey_icon","mossystone_icon","mossystone","viking","alliance","horde",
    "aim","arcane","arcaneum","arctic","earth","felfire","fire","fishing",
    "frost","frostfire","herbalism","holy","inferno","lava","lumber","mining","moon",
    "nature","paladin","sacred","shadow","skinning","thunder","water",
    "chaos","fists","mistweaver","chiji","bronze","void",
}
-- English labels; they double as localization keys.
local STYLE_LABELS = {
    neutral="Neutral", neutral2="Neutral 2", neutral3="Neutral 3",
    metal="Metal", metal_icon="Metal Icon", gears="Gears",
    honey_icon="Honey Icon", mossystone_icon="Mossy Stone Icon",
    mossystone="Mossy Stone", viking="Viking Icon", alliance="Alliance",
    horde="Horde", aim="Aim", arcane="Arcane", arcaneum="Arcaneum",
    arctic="Arctic", earth="Earth", felfire="Felfire", fire="Fire",
    fishing="Fishing", frost="Frost", frostfire="Frostfire",
    herbalism="Herbalism", holy="Holy", inferno="Inferno", lava="Lava",
    lumber="Lumber", mining="Mining", moon="Moon", nature="Nature", paladin="Paladin",
    sacred="Sacred", shadow="Shadow", skinning="Skinning", thunder="Thunder",
    water="Water", chaos="Chaos", fists="Fists of Fury", mistweaver="Mistweaver",
    chiji="Chi'ji", bronze="Bronze", void="Void",
}

-- Rows of "School -> Style". key = the style detection returns for that
-- school (see ASSIGNMENT_PARENT in Schools.lua for styles sharing a row).
local ASSIGN_ROWS = {
    { key="inferno",   label="Fire"          },
    { key="arctic",    label="Frost"         },
    { key="arcaneum",  label="Arcane"        },
    { key="nature",    label="Nature"        },
    { key="shadow",    label="Shadow"        },
    { key="paladin",   label="Paladin"       },
    { key="sacred",    label="Sacred"        },
    { key="earth",     label="Earth"         },
    { key="thunder",   label="Thunder"       },
    { key="moon",      label="Arcane Druid"  },
    { key="felfire",   label="Felfire"       },
    { key="frostfire", label="Frostfire"     },
    { key="misc",      label="Misc / default"},
    { key="water",     label="Water"         },
}
table.sort(ASSIGN_ROWS, function(a, b) return L[a.label]:lower() < L[b.label]:lower() end)

-- Gathering styles: listed under "School -> Profession Style" but stored
-- in themeAssignments, because these casts are detected by style (spellTable).
local GATHER_ROWS = {
    { key="fishing",   label="Fishing"   },
    { key="mining",    label="Mining"    },
    { key="herbalism", label="Herbalism" },
    { key="skinning",  label="Skinning"  },
}

-- Font dropdown. name is the saved fontFace value (Bar.lua maps it to a
-- file); path draws the dropdown entries and the sample line.
local BUNDLED_FONTS = {
    { name="Kenyan Coffee",     path="Interface\\AddOns\\OpulentCastingBars\\fonts\\KenyanCoffee.ttf" },
    { name="Friz Quadrata TT",  path=STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" },
    { name="Gaegu",             path="Interface\\AddOns\\OpulentCastingBars\\fonts\\Gaegu-Bold.ttf" },
    { name="Teko",              path="Interface\\AddOns\\OpulentCastingBars\\fonts\\Teko-Bold.ttf" },
    { name="Titan One",         path="Interface\\AddOns\\OpulentCastingBars\\fonts\\TitanOne-Regular.ttf" },
    { name="Yanone Kaffeesatz", path="Interface\\AddOns\\OpulentCastingBars\\fonts\\YanoneKaffeesatz-Bold.ttf" },
    { name="Expressway",        path="Interface\\AddOns\\OpulentCastingBars\\fonts\\expressway.ttf" },
    { name="Nexa",              path="Interface\\AddOns\\OpulentCastingBars\\fonts\\Nexa-Heavy.ttf" },
    { name="Casual Memories",   path="Interface\\AddOns\\OpulentCastingBars\\fonts\\CasualMemoriesBold.ttf" },
    { name="Alte Haas Grotesk", path="Interface\\AddOns\\OpulentCastingBars\\fonts\\AlteHaasGroteskBold.ttf" },
    { name="Steelfish",         path="Interface\\AddOns\\OpulentCastingBars\\fonts\\Steelfish.ttf" },
}
-- Extra game fonts; only the Latin-alphabet clients ship these files.
do
    local loc = GetLocale()
    if loc ~= "koKR" and loc ~= "zhCN" and loc ~= "zhTW" then
        table.insert(BUNDLED_FONTS, 3, { name="Arial Narrow", path="Fonts\\ARIALN.TTF" })
        table.insert(BUNDLED_FONTS, 4, { name="Morpheus",     path="Fonts\\MORPHEUS.TTF" })
        table.insert(BUNDLED_FONTS, 5, { name="Skurri",       path="Fonts\\skurri.ttf" })
    end
end
-- Alphabetical, like the other dropdowns.
table.sort(BUNDLED_FONTS, function(a, b) return a.name:lower() < b.name:lower() end)

-- ============================================================
--  HELPERS
-- ============================================================

-- Localized display name of a style key (or of the "none"/"blizzard" choices).
local function StyleLabel(key)
    if key == "none"     then return L["-- None --"] end
    if key == "blizzard" then return L["-- Blizzard UI --"] end
    local label = STYLE_LABELS[key]
    if label then return L[label] end
    return key or "?"
end

-- Every style as dropdown items, sorted by label.
local function SortedStyleItems()
    local items = {}
    for _, k in ipairs(STYLE_ORDER) do items[#items+1] = { key = k, label = StyleLabel(k) } end
    table.sort(items, function(a, b) return a.label:lower() < b.label:lower() end)
    return items
end

-- name, rank, icon of a spell ID (nil if unknown).
local function SpellInfo(sid)
    sid = tonumber(sid)
    if not sid then return nil end
    return GetSpellInfo(sid)
end

-- " (Rank 3)", or "" without a rank.
local function RankSuffix(rank)
    return (rank and rank ~= "") and (" ("..rank..")") or ""
end

local function Cfg(key) return SCB.Config:Get(key) end
local function SetCfg(key, v) SCB.Config:Set(key, v) end

local function RepositionBar()
    local a = Cfg("anchor") or "CENTER"
    SCB.Bar.frame:ClearAllPoints()
    SCB.Bar.frame:SetPoint(a, UIParent, a, Cfg("x") or 0, Cfg("y") or -250)
end

local function ApplyStrata()
    local s = Cfg("barStrata") or "MEDIUM"
    SCB.Bar.frame:SetFrameStrata(s)
    if SCB.Bar.frameInner then SCB.Bar.frameInner:SetFrameStrata(s) end
end

local function ApplyText() if SCB.Bar then SCB.Bar:ApplyTextPrefs() end end

-- Blizzard-bar hiding depends on which styles are assigned to it, so
-- re-evaluate it whenever an assignment changes.
local function ReapplyBlizzardHide()
    if SCB.ApplyHideBlizzardBar then
        SCB.ApplyHideBlizzardBar(Cfg("hideBlizzardBar"))
    end
end

-- Push every setting to the bar (after defaults or a profile change).
local function ApplyAll()
    if SCB.Bar and SCB.Bar.frame then
        SCB.Bar.frame:SetScale(Cfg("scale"))
        SCB.Bar:Resize(Cfg("barWidth"), Cfg("barHeight"))
        RepositionBar()
        local castVisible = SCB.Bar.isActive or SCB.Bar.isFading
        SCB.Bar.frame:EnableMouse((not Cfg("locked")) and castVisible)
        ApplyStrata()
        SCB.ApplyHideBlizzardBar(Cfg("hideBlizzardBar"))
        SCB.Bar:ApplyTextPrefs()
    end
    SCB.MinimapButton_Update()
end

-- Show a fake cast of a style. The bar is raised above the Options
-- window for the preview and returns to its own strata once it hides.
local function PreviewSchool(key, dur)
    if not key or key == "none" or key == "blizzard" then
        key = Cfg("defaultSchool") or "neutral"
    end
    if SCB.Bar.isActive or SCB.Bar.isFading then SCB.Bar:StopCast(false) end
    SCB.Bar.frame:SetFrameStrata("TOOLTIP")
    SCB.Bar:StartCast(string.format(L["Preview: %s"], StyleLabel(key)), dur or Cfg("previewDuration") or 3, key)
    SCB.Bar.frame:SetScript("OnHide", function(self)
        self:SetFrameStrata(SCB.Config:Get("barStrata") or "MEDIUM")
        self:SetScript("OnHide", nil)
    end)
end
SCB.PreviewSchool = function(key, dur) PreviewSchool(key, dur) end

-- ============================================================
--  SETTINGS
-- ============================================================

-- A proxy setting for one SCB.Config key. apply(value) runs after the
-- value is stored. Defaults come from SCB.Config.defaults.
local function KeyAccess(key, apply, fallback)
    local function get()
        local v = Cfg(key)
        if v == nil then v = fallback end
        return v
    end
    local function set(v)
        SetCfg(key, v)
        if apply then apply(v) end
    end
    local default = SCB.Config.defaults[key]
    if default == nil then default = fallback end
    return default, get, set
end

local function CheckKey(page, variable, label, key, apply, tooltip)
    local default, get, set = KeyAccess(key, apply, false)
    return page:Checkbox(variable, label, tooltip, default, function() return get() and true or false end, set)
end

-- Two saved on/off settings on one row. Each argument:
-- { variable, label, key, apply, tooltip }.
local function CheckKeyPair(page, left, right)
    local function Spec(o)
        local default, get, set = KeyAccess(o[3], o[4], false)
        return { variable = o[1], label = o[2], tooltip = o[5], default = default,
                 get = function() return get() and true or false end, set = set }
    end
    return page:CheckboxPair(Spec(left), Spec(right))
end

-- Slider values are snapped to the step (the slider's own values can be
-- off by a rounding error, e.g. 0.30000000000000004).
local function SliderKey(page, variable, label, minV, maxV, step, key, apply, tooltip)
    local default, get, set = KeyAccess(key, apply, minV)
    local function snap(v)
        v = minV + math.floor((v - minV) / step + 0.5) * step
        return tonumber(string.format("%.4f", math.max(minV, math.min(maxV, v))))
    end
    return page:Slider(variable, label, tooltip, minV, maxV, step, default, get,
        function(v) set(snap(v)) end)
end

local function DropdownKey(page, variable, label, items, key, fallback, apply, tooltip, button)
    local default, get, set = KeyAccess(key, apply, fallback)
    return page:Dropdown(variable, label, tooltip, items, default, get, set, button)
end

-- True while the window's Defaults button is resetting settings.
local function SettingDefaults()
    return SettingsPanel and SettingsPanel.CheckIsSettingDefaults and SettingsPanel:CheckIsSettingDefaults()
end

-- A session-only choice (not saved). Its default is its current value, so
-- the Defaults button leaves it alone.
local function SessionValue(initial)
    local value = initial
    return function() return value end,
           function() return value end,
           function(v) value = v end
end

-- ============================================================
--  PAGES
-- ============================================================

SCB.Options.pages = {}
local pages = SCB.Options.pages

-- Category -> page, for IsOpen() and the Defaults hooks.
local pageOfCategory = {}

-- Redraw every OCB control from the saved settings (defaults, profile
-- switch, slash command, bar dragged while the window is open).
function SCB.Options.RefreshWidgets()
    UI.NotifyAll()
    for _, p in pairs(pages) do
        if p.Refresh then p.Refresh() end
    end
end

-- Called after every cast; the Spells page replaces it.
function SCB.Options.RefreshFromConfig() end

local function NewPage(id, name, parent)
    local page = UI.NewPage(name, parent)
    page.id = id
    pages[id] = page
    pageOfCategory[page.category] = page
    return page
end

-- ============================================================
--  OVERVIEW  (the "Opulent Casting Bars" entry)
-- ============================================================

local function BuildMain(page)
    page:Section(L["Commands"])
    for _, h in ipairs(SCB.Commands.HELP) do
        page:TextRow(h[1], h[2])
    end

    -- This page has no settings of its own: its Defaults restores all of
    -- OCB's settings (the current profile stays selected).
    page.onDefault = function() SCB.Config:Reset() end
end

-- ============================================================
--  GENERAL
-- ============================================================

local function BuildGeneral(page)
    page:Section(L["Bar Size"])
    SliderKey(page, "OCB_SCALE", L["Scale"], 0.3, 2.0, 0.05, "scale", function(v)
        local f = SCB.Bar and SCB.Bar.frame
        if not f then return end
        -- The saved x/y are in the bar's own (scaled) coordinates: rescale
        -- them so the bar stays where it is on screen. Not while Defaults
        -- runs: x/y are reset to their own defaults then.
        if not SettingDefaults() then
            local oldScale = f:GetScale()
            SetCfg("x", (Cfg("x") or 0) * oldScale / v)
            SetCfg("y", (Cfg("y") or -250) * oldScale / v)
        end
        f:SetScale(v)
        RepositionBar()
        UI.NotifyUpdate("OCB_X")
        UI.NotifyUpdate("OCB_Y")
    end)
    SliderKey(page, "OCB_BAR_WIDTH", L["Bar Width"], 100, 800, 10, "barWidth", function(v)
        if SCB.Bar then SCB.Bar:Resize(v, Cfg("barHeight")) end
    end)

    page:Section(L["Position"])
    SliderKey(page, "OCB_X", L["Position X"], -800, 800, 1, "x", function()
        if SCB.Bar and SCB.Bar.frame then RepositionBar() end
    end)
    SliderKey(page, "OCB_Y", L["Position Y"], -800, 800, 1, "y", function()
        if SCB.Bar and SCB.Bar.frame then RepositionBar() end
    end)

    page:Section(L["Behaviour"])
    CheckKeyPair(page,
        { "OCB_LOCKED", L["Lock bar position"], "locked", function(v)
            if SCB.Bar and SCB.Bar.frame then
                local castVisible = SCB.Bar.isActive or SCB.Bar.isFading
                SCB.Bar.frame:EnableMouse((not v) and castVisible)
            end
        end },
        { "OCB_HIDE_BLIZZARD", L["Hide Blizzard cast bar"], "hideBlizzardBar", function(v)
            SCB.ApplyHideBlizzardBar(v)
        end })
    CheckKeyPair(page,
        { "OCB_PRECACHE", L["Pre-warm textures on login"], "precacheOnLogin" },
        { "OCB_MINIMAP", L["Show minimap button"], "minimapButton", function()
            SCB.MinimapButton_Update()
        end })
    local strataItems = {
        {key="BACKGROUND", label=L["Background"]}, {key="LOW",        label=L["Low"]},
        {key="MEDIUM",     label=L["Medium"]},     {key="HIGH",       label=L["High"]},
        {key="DIALOG",     label=L["Dialog"]},     {key="FULLSCREEN", label=L["Fullscreen"]},
        {key="TOOLTIP",    label=L["Tooltip"]},
    }
    DropdownKey(page, "OCB_STRATA", L["Frame Strata"], strataItems, "barStrata", "MEDIUM", ApplyStrata)
    SliderKey(page, "OCB_PREVIEW_DURATION", L["Preview duration"], 0.5, 10, 0.5, "previewDuration", nil,
        L["How long a preview cast lasts, in seconds."])

    page:Button(nil, L["Preview"], function()
        PreviewSchool(Cfg("defaultSchool"))
    end)

    -- Saved with this page but not shown on it: Defaults resets them too.
    page.extraKeys = { "barHeight", "anchor" }
end

-- ============================================================
--  STYLE
-- ============================================================

local function BuildStyle(page)
    local styleItems = SortedStyleItems()

    page:Section(L["School Detection"])
    CheckKeyPair(page,
        { "OCB_DETECT", L["Auto-detect spell school"], "useSchoolDetection" },
        { "OCB_ASSIGNMENTS", L["Use school -> style assignments"], "useThemeAssignments", ReapplyBlizzardHide })

    page:Section(L["Default / Fixed Style"])
    DropdownKey(page, "OCB_DEFAULT_STYLE", L["Style"], styleItems, "defaultSchool", "neutral", nil,
        L["Used when detection is off, or for unknown schools."],
        { text = L["Preview"],
          onClick = function(v) PreviewSchool(v) end, noLabel = true })

    -- Not a setting: picking a style previews it.
    page:Section(L["Preview Any Style"])
    local default, get, set = SessionValue(Cfg("defaultSchool") or "neutral")
    page:Dropdown("OCB_PREVIEW_STYLE", L["Style"], L["Pick a style to preview it."], styleItems,
        default, get,
        function(v)
            set(v)
            if not SettingDefaults() then PreviewSchool(v) end
        end,
        { text = L["Preview"], onClick = function(v) PreviewSchool(v) end, noLabel = true })
end

-- ============================================================
--  TEXT
-- ============================================================

local function FontPath(name)
    for _, fi in ipairs(BUNDLED_FONTS) do
        if fi.name == name then return fi.path end
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

-- "AARRGGBB" of the name/timer color: the custom color, or white.
local function TextColorHex()
    local col = Cfg("textCustomColor")
    if Cfg("textNameColor") == "custom" and col and col.r then
        return string.format("ff%02x%02x%02x",
            math.floor(col.r * 255 + 0.5), math.floor(col.g * 255 + 0.5), math.floor(col.b * 255 + 0.5))
    end
    return "ffffffff"
end

local function SetTextColorHex(hex)
    local r = tonumber(string.sub(hex, 3, 4), 16) or 255
    local g = tonumber(string.sub(hex, 5, 6), 16) or 255
    local b = tonumber(string.sub(hex, 7, 8), 16) or 255
    if r == 255 and g == 255 and b == 255 then
        SetCfg("textCustomColor", {r=1, g=1, b=1})
        SetCfg("textNameColor",  "white")
        SetCfg("textTimerColor", "white")
    else
        SetCfg("textCustomColor", {r=r/255, g=g/255, b=b/255})
        SetCfg("textNameColor",  "custom")
        SetCfg("textTimerColor", "custom")
    end
    ApplyText()
end

local function BuildText(page)
    local fontItems = {}
    for _, fi in ipairs(BUNDLED_FONTS) do
        fontItems[#fontItems+1] = { key = fi.name, label = fi.name }
    end

    -- Sample line in the selected font.
    local sample
    local function UpdateSample()
        if not sample then return end
        local fs = sample.Value
        fs:SetFontObject(GameFontHighlight)
        pcall(fs.SetFont, fs, FontPath(Cfg("fontFace") or "Friz Quadrata TT"), 15,
            Cfg("textOutline") and "OUTLINE" or "")
        fs:SetText((GetSpellInfo(133) or "Fireball") .. "   1.5")
    end
    page.Refresh = UpdateSample

    page:Section(L["Font"])
    local default, get, set = KeyAccess("fontFace", function() ApplyText(); UpdateSample() end, "Friz Quadrata TT")
    page:Dropdown("OCB_FONT", L["Font"], nil, fontItems, default, get, set, { noLabel = true }, FontPath)
    page:TextRow(L["Preview"], "", nil,
        function(frame) sample = frame; UpdateSample() end,
        function(frame) if sample == frame then sample = nil end end)

    CheckKeyPair(page,
        { "OCB_OUTLINE", L["Text outline"], "textOutline", function() ApplyText(); UpdateSample() end },
        { "OCB_CENTERED", L["Center both name and timer"], "textCentered", ApplyText })

    local alignItems = {
        {key="LEFT",   label=L["Left"]},
        {key="CENTER", label=L["Center"]},
        {key="RIGHT",  label=L["Right"]},
    }

    page:Section(L["Spell Name Text"])
    CheckKeyPair(page,
        { "OCB_SHOW_NAME", L["Show spell name"], "showSpellName", ApplyText },
        { "OCB_TRUNCATE", L["Truncate long names (>30 chars)"], "textNameTruncate", ApplyText })
    SliderKey(page, "OCB_NAME_SIZE", L["Size"],     6,    30,  1, "textNameSize", ApplyText)
    SliderKey(page, "OCB_NAME_X",    L["X offset"], -200, 200, 1, "textNamePosX", ApplyText)
    SliderKey(page, "OCB_NAME_Y",    L["Y offset"], -100, 100, 1, "textNamePosY", ApplyText)
    DropdownKey(page, "OCB_NAME_ALIGN", UI.NoColon(L["Alignment:"]), alignItems, "textNameAlign", "LEFT", ApplyText)

    page:Section(L["Timer Text"])
    CheckKey(page, "OCB_SHOW_TIMER", L["Show cast timer"], "showCastTime", ApplyText)
    SliderKey(page, "OCB_TIMER_SIZE", L["Size"],     6,    30,  1, "textTimerSize", ApplyText)
    SliderKey(page, "OCB_TIMER_X",    L["X offset"], -200, 200, 1, "textTimerPosX", ApplyText)
    SliderKey(page, "OCB_TIMER_Y",    L["Y offset"], -100, 100, 1, "textTimerPosY", ApplyText)
    DropdownKey(page, "OCB_TIMER_ALIGN", UI.NoColon(L["Alignment:"]), alignItems, "textTimerAlign", "RIGHT", ApplyText)

    page:Section(L["Text Color"])
    page:ColorSwatch("OCB_TEXT_COLOR", L["Name & timer color"], nil, "ffffffff", TextColorHex, SetTextColorHex,
        L["Reset"], { text = L["Preview"], tooltip = L["Preview Text"], onClick = function()
            ApplyText()
            PreviewSchool(Cfg("defaultSchool"))
        end })

    -- Saved with this page but not shown on it: Defaults resets them too.
    page.extraKeys = { "textCustomColor", "textNameColor", "textTimerColor" }
end

-- ============================================================
--  SCHOOLS
-- ============================================================

local function BuildSchools(page)
    page:Note(L["Enable \"Use school -> style assignments\" on the Style page to activate these."])

    local assignItems = { {key="none", label=L["-- None (auto) --"]}, {key="blizzard", label=L["-- Blizzard UI --"]} }
    for _, item in ipairs(SortedStyleItems()) do assignItems[#assignItems+1] = item end

    -- One row: dropdown + Preview. tbl is the settings key of the table,
    -- key the entry; "none" is stored as no entry. fallback() is the
    -- style previewed for "none"/"blizzard".
    local function AssignRow(variable, label, tbl, key, fallback)
        local function get() return (Cfg(tbl) or {})[key] or "none" end
        local function set(v)
            local t = Cfg(tbl) or {}
            if v == "none" then v = nil end
            t[key] = v
            SetCfg(tbl, t)
            ReapplyBlizzardHide()
        end
        page:Dropdown(variable, label, nil, assignItems, "none", get, set,
            { text = L["Preview"], onClick = function(v)
                if not v or v == "none" or v == "blizzard" then v = fallback() end
                PreviewSchool(v)
            end })
    end

    page:Section(L["School -> Style"])
    for _, row in ipairs(ASSIGN_ROWS) do
        local key = row.key
        AssignRow("OCB_ASSIGN_" .. key, L[row.label], "themeAssignments", key, function() return key end)
    end

    -- Gathering rows (themeAssignments) and crafting professions
    -- (professionAssignments[skillID]) in one alphabetical list.
    page:Section(L["School -> Profession Style"])
    local profRows = {}
    for _, row in ipairs(GATHER_ROWS) do
        profRows[#profRows+1] = { label=L[row.label], theme=row }
    end
    for _, prof in ipairs(SCB.Schools:GetProfessions()) do
        profRows[#profRows+1] = { label=L[prof.label], skillID=prof.id }
    end
    table.sort(profRows, function(a, b) return a.label:lower() < b.label:lower() end)
    for _, pr in ipairs(profRows) do
        if pr.theme then
            local key = pr.theme.key
            AssignRow("OCB_ASSIGN_" .. key, pr.label, "themeAssignments", key, function() return key end)
        else
            AssignRow("OCB_PROF_" .. pr.skillID, pr.label, "professionAssignments", pr.skillID,
                function() return Cfg("defaultSchool") end)
        end
    end

    page:Button(L["Clear All Assignments"], L["Clear"], function()
        UI.Confirm(L["Clear All Assignments"] .. "?", function()
            SetCfg("themeAssignments", {})
            SetCfg("professionAssignments", {})
            ReapplyBlizzardHide()
            SCB.Options.RefreshWidgets()
        end)
    end)

    -- The rows only cover the listed keys; Defaults clears the whole tables.
    page.extraKeys = { "themeAssignments", "professionAssignments" }
end

-- ============================================================
--  SPELLS
-- ============================================================

local GOLD  = "|cffffd100"
local GREY  = "|cff999999"
local WHITE = "|cffffffff"

-- Spell IDs of every rank of a spell in the player's spellbook.
local function GetAllRankIDs(spellName)
    local ids = {}
    if not spellName then return ids end
    for t = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
        local tab = C_SpellBook.GetSpellBookSkillLineInfo(t)
        if tab then
            for slot = tab.itemIndexOffset + 1, tab.itemIndexOffset + tab.numSpellBookItems do
                local info = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
                if info and info.name == spellName and info.spellID then
                    ids[#ids+1] = info.spellID
                end
            end
        end
    end
    return ids
end

local function BuildSpells(page)
    page:Note(L["Force a specific style for any spell by ID."])

    local selectedOverrideId
    local input, overrideList, historyList

    -- ---- Recent Casts ----
    page:Section(L["Recent Casts"])
    page:Note(L["Click a row to load that spell into the fields below."])

    local function HistoryEntries()
        local raw = SCB.Events.recentCasts or {}
        -- One row per spell (first occurrence = most recent).
        local seen, casts = {}, {}
        for _, rec in ipairs(raw) do
            local key = tostring(rec.id or "") .. "_" .. (rec.name or "")
            if not seen[key] then
                seen[key] = true
                local recId = rec.id
                -- School: ClassicAPI's English school name, shown translated.
                local schoolName
                if recId then
                    local _, sn = GetSpellSchool(recId)
                    if sn then schoolName = L[sn] end
                end
                if not schoolName and rec.naturalSchool then schoolName = StyleLabel(rec.naturalSchool) end
                local icon = rec.icon
                if not icon and recId then
                    local _, _, ic = GetSpellInfo(recId)
                    icon = ic
                end
                casts[#casts+1] = {
                    id = recId, name = rec.name or "?", rankStr = RankSuffix(rec.rank or ""),
                    school = schoolName or "?", icon = icon,
                }
            end
        end
        return casts
    end

    historyList = page:ListBox(112, HistoryEntries, function(button, rec)
        UI.SetListEntry(button, rec.icon, string.format("%s%s%s|r   %s%s|r %s   %s%s|r %s",
            GOLD, rec.name, rec.rankStr, GREY, L["ID:"], rec.id and tostring(rec.id) or "?",
            GREY, L["School:"], rec.school))
    end, function(rec)
        if rec.id then input.state.text = tostring(rec.id) end
        if input.frame then input.frame:Refresh() end
    end, L["No spells cast yet."])

    -- RefreshFromConfig runs after every cast: only redraw a shown list.
    SCB.Options.RefreshFromConfig = function()
        local f = historyList.frame
        if f and f:IsVisible() then f:Refresh() end
    end

    -- ---- Override editor ----
    page:Section(L["Per-Spell Style Override"])

    input = page:SpellInput(UI.NoColon(L["Spell ID:"]), nil, function(sid)
        if not sid then return "" end
        local name, rank = SpellInfo(sid)
        if name then return GOLD .. name .. RankSuffix(rank) .. "|r" end
        return "|cffff5555" .. L["Unknown spell ID"] .. "|r"
    end)

    local defStyle, getStyle, setStyle = SessionValue("neutral")
    page:Dropdown("OCB_FORCE_STYLE", UI.NoColon(L["Force Style:"]), nil, SortedStyleItems(), defStyle, getStyle, setStyle,
        { text = L["Preview"], onClick = function(v) PreviewSchool(v) end })

    local defRanks, getRanks, setRanks = SessionValue(false)
    page:Checkbox("OCB_ALL_RANKS", L["Apply to all ranks"], nil, defRanks, getRanks, setRanks)

    -- ---- Override list ----
    local function OverrideEntries()
        local entries = {}
        local found = false
        for idKey, style in pairs(Cfg("spellThemeOverrides") or {}) do
            local sid = tonumber(idKey)
            if sid and style and style ~= "" then
                local name, rank, icon = SpellInfo(sid)
                entries[#entries+1] = { id=sid, style=style, name=name, rank=rank, icon=icon }
                if sid == selectedOverrideId then found = true end
            end
        end
        if not found then selectedOverrideId = nil end
        table.sort(entries, function(a, b)
            local na, nb = a.name or "", b.name or ""
            if na ~= nb then return na < nb end
            return a.id < b.id
        end)
        return entries
    end

    local function RefreshOverrides()
        if overrideList.frame then overrideList.frame:Refresh() end
    end

    page:Button(L["Add / Update Override"], L["Add / Update"], function()
        local sid = tonumber(input.state.text)
        if not sid or sid <= 0 then print(ADDON_PREFIX..L["Enter a valid spell ID."]); return end
        local style = getStyle()
        if not SCB.Schools:Exists(style) then print(ADDON_PREFIX..string.format(L["Unknown style: %s"], tostring(style))); return end
        local name = SpellInfo(sid)
        local ids = (getRanks() and name) and GetAllRankIDs(name) or {}
        if #ids > 0 then
            for _, rankID in ipairs(ids) do OCBSpellOverrides.Set(rankID, style) end
        else
            -- One ID (also when the spellbook has no rank of this spell).
            OCBSpellOverrides.Set(sid, style)
        end
        selectedOverrideId = sid
        RefreshOverrides()
    end)

    overrideList = page:ListBox(132, OverrideEntries, function(button, entry)
        UI.SetListEntry(button, entry.icon, string.format("%s%s%s|r   %s%s|r %s   %s->|r  %s%s|r",
            GOLD, entry.name or (L["ID:"].." "..entry.id), RankSuffix(entry.rank),
            GREY, L["ID:"], tostring(entry.id), GREY, WHITE, StyleLabel(entry.style)),
            entry.id == selectedOverrideId)
    end, function(entry)
        selectedOverrideId = entry.id
        input.state.text = tostring(entry.id)
        if input.frame then input.frame:Refresh() end
        Settings.SetValue("OCB_FORCE_STYLE", entry.style)
        if overrideList.frame then overrideList.frame:Redraw() end
    end, L["No spell overrides configured."])

    page:Button(L["Remove Override"], L["Remove"], function()
        if not selectedOverrideId then
            print(ADDON_PREFIX..L["Select an override from the list first."])
            return
        end
        local overrideId = selectedOverrideId
        UI.Confirm(L["Remove the selected spell override?"], function()
            OCBSpellOverrides.Remove(overrideId)
            RefreshOverrides()
        end)
    end)

    -- Remove the override of every rank of the selected spell.
    page:Button(L["Remove Rank Overrides"], L["Remove"], function()
        if not selectedOverrideId then
            print(ADDON_PREFIX..L["Select an override from the list first."])
            return
        end
        local overrideId = selectedOverrideId
        local baseName = SpellInfo(overrideId)
        if not baseName then
            print(ADDON_PREFIX..L["Could not resolve the spell name."])
            return
        end
        UI.Confirm(string.format(L["Remove all rank overrides for\n%s?"], baseName), function()
            local removed = 0
            local overrides = Cfg("spellThemeOverrides") or {}
            for _, rankID in ipairs(GetAllRankIDs(baseName)) do
                if overrides[rankID] or overrides[tostring(rankID)] then
                    OCBSpellOverrides.Remove(rankID)
                    removed = removed + 1
                end
            end
            -- Nothing found through the spellbook: remove the selected ID.
            if removed == 0 then OCBSpellOverrides.Remove(overrideId) end
            RefreshOverrides()
        end)
    end)

    page:Button(L["Clear All Overrides"], L["Clear"], function()
        UI.Confirm(L["Clear all spell overrides?"], function()
            OCBSpellOverrides.Clear()
            RefreshOverrides()
        end)
    end)

    page.Refresh = function()
        RefreshOverrides()
        SCB.Options.RefreshFromConfig()
    end
    -- Defaults on this page (or for all settings) clears the overrides.
    page.onDefault = function()
        OCBSpellOverrides.Clear()
        RefreshOverrides()
    end
end

-- ============================================================
--  PROFILES
-- ============================================================

local function BuildProfiles(page)
    local P = SCB.Profiles
    page:Note(L["Profiles are shared by all your characters. Each character remembers the profile it uses."])

    local function Report(ok, err)
        if not ok and err then print(ADDON_PREFIX .. L[err]) end
        SCB.Options.RefreshWidgets()
    end

    local function ProfileItems()
        local items = {}
        for _, name in ipairs(P:GetAll()) do items[#items+1] = { key = name, label = name } end
        return items
    end

    page:Dropdown("OCB_PROFILE", L["Profile"], L["The profile this character uses."],
        function() return ProfileItems() end,
        function() return P:GetCurrent() end,   -- Defaults keeps the profile
        function() return P:GetCurrent() end,
        function(name) if name ~= P:GetCurrent() then P:Switch(name) end end,
        { text = L["Delete"], enabled = function(name)
            return name ~= nil and name ~= "" and name ~= P.DEFAULT
        end, onClick = function(name)
            if not name or name == "" or name == P.DEFAULT then return end
            UI.Confirm(string.format(L["Delete the profile \"%s\"?"], name), function()
                Report(P:Delete(name))
            end)
        end })

    page:Button(L["New Profile"], L["New"], function()
        UI.Prompt(L["Name of the new profile (copy of the current one):"], function(name)
            Report(P:New(name, true))
        end)
    end, L["Creates a copy of the current profile and switches to it."])

    page:Button(L["Reset Profile"], L["Reset"], function()
        UI.Confirm(string.format(L["Reset the profile \"%s\" to the default settings?"], P:GetCurrent()), function()
            P:Reset()
            SCB.Options.RefreshWidgets()
        end)
    end, L["Sets every setting of the current profile back to its default."])
end

-- ============================================================
--  CREATE AND REGISTER
-- ============================================================

-- Defaults: reset the keys a page saves but does not show, and run the
-- page's own reset. "These Settings" does it for the shown page, "All
-- Settings" for every page.
local function ResetExtra(page)
    for _, k in ipairs(page.extraKeys or {}) do
        local v = SCB.Config.defaults[k]
        if type(v) == "table" then
            local c = {}
            for tk, tv in pairs(v) do c[tk] = tv end
            v = c
        end
        SetCfg(k, v)
    end
    if page.onDefault then page.onDefault() end
end

local function OnDefaulted(category)
    local any = false
    for _, page in pairs(pages) do
        if category == nil or page.category == category then
            ResetExtra(page)
            any = true
        end
    end
    if any then
        ApplyAll()
        SCB.Options.RefreshWidgets()
    end
end

function SCB.Options:Create()
    if self.created then return end
    self.created = true

    local main = NewPage("main", ADDON_TITLE)
    local list = {
        { page = main, build = BuildMain },
        { id = "general",  name = L["General"],  build = BuildGeneral  },
        { id = "style",    name = L["Style"],    build = BuildStyle    },
        { id = "text",     name = L["Text"],     build = BuildText     },
        { id = "schools",  name = L["Schools"],  build = BuildSchools  },
        { id = "spells",   name = L["Spells"],   build = BuildSpells   },
        { id = "profiles", name = L["Profiles"], build = BuildProfiles },
    }
    for i, info in ipairs(list) do
        local page = info.page or NewPage(info.id, info.name, main)
        -- A page that fails to build is reported; the others still work.
        local ok, err = pcall(info.build, page)
        if not ok then
            print("|cffFF0000[OCB]|r "..string.format(L["Options page %d failed to build:"], i).." "..tostring(err))
        end
    end
    UI.Register(main)

    EventRegistry:RegisterCallback("Settings.CategoryDefaulted", function(_, category) OnDefaulted(category) end, self)
    EventRegistry:RegisterCallback("Settings.Defaulted", function() OnDefaulted(nil) end, self)
    EventRegistry:RegisterCallback("Settings.CategoryChanged", function(_, category)
        if pageOfCategory[category] then self.lastPage = pageOfCategory[category] end
    end, self)
end

-- ============================================================
--  OPEN / CLOSE
-- ============================================================

-- True while the Options window shows one of our pages.
function SCB.Options:IsOpen()
    local category = UI.GetShownCategory()
    return category ~= nil and pageOfCategory[category] ~= nil
end

-- Open the Options window on a page (the last one viewed by default).
function SCB.Options:Open(page)
    page = page or self.lastPage or pages.general or pages.main
    if not page then return end
    Settings.OpenToCategory(page.category:GetID())
end

-- Close the window without opening the game menu behind it.
function SCB.Options:Close()
    if SettingsPanel and SettingsPanel:IsShown() then SettingsPanel:Close(true) end
end

function SCB.Options:Toggle()
    if self:IsOpen() then self:Close() else self:Open() end
end
