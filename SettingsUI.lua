-- ============================================================
--  Opulent Casting Bars -- SettingsUI.lua
--
--  Builds OCB's pages in ClassicAPI's Options window (AddOns
--  tab) with the window's own Settings API, so every page uses
--  the window's scroll list, scroll bar, section headers,
--  checkboxes, sliders, dropdowns, buttons and Defaults button.
--
--  OCB adds a few rows of its own (SettingsTemplates.xml), each
--  built on one of ClassicAPI's rows: a slider with a box to type
--  a value, a dropdown with a button after it, plain text, a
--  spell ID box and a list box.
-- ============================================================

SCB.UI = SCB.UI or {}
local UI = SCB.UI
local L  = SCB.L

-- Every setting variable OCB registered, for NotifyAll().
UI.variables = {}

local function InitTooltip(initializer)
    Settings.InitTooltip(initializer:GetName(), initializer:GetTooltip())
end

-- 1.12's IsEnabled returns 1 or 0 (and 0 is true in Lua).
local function SetEnabled(widget, enabled)
    if enabled then widget:Enable() else widget:Disable() end
end

-- Width a button needs for its text.
local function FitButton(button, minWidth)
    local fs = button:GetFontString()
    local w = fs and fs:GetStringWidth() or 0
    button:SetWidth(math.max(minWidth or 0, math.ceil(w) + 24))
end

-- Edit boxes keep the focus until something else takes it; drop it
-- when the mouse is pressed anywhere else.
-- Box scripts use the box they were set on, never the script's
-- argument: in 1.12 a focus change can run one box's script with
-- the other box passed in, which wrote one box's text to another.
local focusWatcher = CreateFrame("Frame")
focusWatcher:Hide()
focusWatcher:SetScript("OnUpdate", function()
    local eb = focusWatcher.editBox
    if not eb or not eb:IsVisible() then
        if eb then eb:ClearFocus() end
        focusWatcher:Hide()
    elseif IsMouseButtonDown() and not eb:IsMouseOver() then
        eb:ClearFocus()
    end
end)

local function WatchFocus(eb, onGained)
    eb:SetScript("OnEditFocusGained", function()
        eb:HighlightText()
        focusWatcher.editBox = eb
        focusWatcher:Show()
        if onGained then onGained() end
    end)
end

local function UnwatchFocus(eb)
    eb:HighlightText(0, 0)
    if focusWatcher.editBox == eb then
        focusWatcher.editBox = nil
        focusWatcher:Hide()
    end
end

-- ============================================================
--  DIALOGS (the game's own StaticPopup)
-- ============================================================

local pendingAccept
StaticPopupDialogs["OCB_OPTIONS_CONFIRM"] = {
    text         = "%s",
    button1      = L["Confirm"],
    button2      = L["Cancel"],
    OnAccept     = function()
        local fn = pendingAccept
        pendingAccept = nil
        if fn then fn() end
    end,
    OnCancel     = function() pendingAccept = nil end,
    timeout      = 0,
    whileDead    = 1,
    hideOnEscape = 1,
}

function UI.Confirm(text, onAccept)
    pendingAccept = onAccept
    StaticPopup_Show("OCB_OPTIONS_CONFIRM", text)
end

-- Ask for a line of text (a profile name).
local pendingText
local function PromptAccept(dialog)
    local eb = dialog.editBox or _G[dialog:GetName() .. "EditBox"]
    local text = eb and strtrim(eb:GetText() or "") or ""
    local fn = pendingText
    pendingText = nil
    if fn and text ~= "" then fn(text) end
end
StaticPopupDialogs["OCB_OPTIONS_PROMPT"] = {
    text         = "%s",
    button1      = L["Confirm"],
    button2      = L["Cancel"],
    hasEditBox   = 1,
    maxLetters   = 32,
    OnAccept     = function() PromptAccept(this:GetParent()) end,
    EditBoxOnEnterPressed = function()
        local dialog = this:GetParent()
        PromptAccept(dialog)
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function() this:GetParent():Hide() end,
    OnShow       = function()
        local eb = _G[this:GetName() .. "EditBox"]
        if eb then eb:SetText(""); eb:SetFocus() end
    end,
    OnHide       = function() pendingText = nil end,
    timeout      = 0,
    whileDead    = 1,
    hideOnEscape = 1,
}

function UI.Prompt(text, onAccept)
    pendingText = onAccept
    StaticPopup_Show("OCB_OPTIONS_PROMPT", text)
end

-- ============================================================
--  ROW MIXINS (templates in SettingsTemplates.xml)
-- ============================================================

-- ---- Slider + value box -------------------------------------
-- The box shows the value; Enter or a click elsewhere sets the typed
-- value (snapped to the slider's step and range), Escape puts it back.
OCBSettingsSliderControlMixin = CreateFromMixins(SettingsSliderControlMixin)

local function FormatValue(v)
    return string.format("%g", tonumber(string.format("%.4f", v or 0)))
end

function OCBSettingsSliderControlMixin:OnLoad()
    SettingsSliderControlMixin.OnLoad(self)
    local box = self.ValueBox
    box:ClearAllPoints()
    box:SetPoint("LEFT", self.SliderWithSteppers, "RIGHT", 10, 3)
    box:SetJustifyH("CENTER")
    Mixin(box, DefaultTooltipMixin)
    DefaultTooltipMixin.OnLoad(box)
    -- Remember which setting the edit began on; rows are pooled, so
    -- the row may show another setting by the time the focus is lost.
    WatchFocus(box, function()
        box.escaped = nil
        box.editSetting = self.data and self:GetSetting()
    end)
    box:SetScript("OnEnterPressed", function() box:ClearFocus() end)
    box:SetScript("OnEscapePressed", function()
        box.escaped = true
        box:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function()
        UnwatchFocus(box)
        local setting = self.data and self:GetSetting()   -- nil once released
        local same = setting and box.editSetting == setting
        local escaped = box.escaped
        box.escaped, box.editSetting = nil, nil
        if same and not escaped then self:CommitText(box:GetText()) end
        if setting then self:ShowValue(setting:GetValue()) end
    end)
end

function OCBSettingsSliderControlMixin:Init(initializer)
    SettingsSliderControlMixin.Init(self, initializer)
    self.ValueBox.escaped, self.ValueBox.editSetting = nil, nil
    self.ValueBox:SetTooltipFunc(GenerateClosure(InitTooltip, initializer))
    self:ShowValue(self:GetSetting():GetValue())
end

function OCBSettingsSliderControlMixin:ShowValue(value)
    self.ValueBox:SetText(FormatValue(value))
    self.ValueBox:SetCursorPosition(0)
end

function OCBSettingsSliderControlMixin:CommitText(text)
    local v = tonumber(text)
    if not v then return end
    local o = self:GetElementData():GetOptions()
    local step = o.step or ((o.maxValue - o.minValue) / o.steps)
    if step > 0 then v = o.minValue + math.floor((v - o.minValue) / step + 0.5) * step end
    v = math.max(o.minValue, math.min(o.maxValue, v))
    v = tonumber(string.format("%.4f", v))
    if v ~= self:GetSetting():GetValue() then
        self:GetSetting():SetValue(v)
    end
end

function OCBSettingsSliderControlMixin:SetValue(value)
    SettingsSliderControlMixin.SetValue(self, value)
    if not self.ValueBox:HasFocus() then self:ShowValue(value) end
end

function OCBSettingsSliderControlMixin:EvaluateState()
    SettingsSliderControlMixin.EvaluateState(self)
    SetEnabled(self.ValueBox, self:IsEnabled())
end

function OCBSettingsSliderControlMixin:Release()
    self.ValueBox.editSetting = nil   -- drop the edit, don't commit it
    self.ValueBox:ClearFocus()
    SettingsSliderControlMixin.Release(self)
end

-- ---- Button row ---------------------------------------------
-- ClassicAPI's button row, but with the silver UIMenuButtonStretchTemplate
-- button in place of the red UIPanelButtonTemplate one.
OCBSettingsButtonControlMixin = CreateFromMixins(SettingsButtonControlMixin)

function OCBSettingsButtonControlMixin:OnLoad()
    SettingsListElementMixin.OnLoad(self)
    self.Button = CreateFrame("Button", nil, self, "UIMenuButtonStretchTemplate")
    self.Button:SetWidth(200)
    self.Button:SetHeight(22)
    Mixin(self.Button, DefaultTooltipMixin)
    DefaultTooltipMixin.OnLoad(self.Button)
end

-- Rows without a label (data.noLabel) show a separate button in the
-- label's place, with no tooltip. The normal button is left untouched,
-- so pooled rows keep their layout.
function OCBSettingsButtonControlMixin:Init(initializer)
    SettingsButtonControlMixin.Init(self, initializer)
    local data = initializer:GetData()
    if data.noLabel then
        if not self.SoloButton then
            local b = CreateFrame("Button", nil, self, "UIMenuButtonStretchTemplate")
            b:SetHeight(22)
            b:SetPoint("LEFT", self, "LEFT", 37, 0)
            self.SoloButton = b
        end
        local b = self.SoloButton
        b:SetText(data.buttonText or "")
        FitButton(b, 70)
        b:SetScript("OnClick", function() if data.buttonClick then data.buttonClick() end end)
        b:Show()
        self.Button:Hide()
        if self.Text then self.Text:Hide() end
    else
        if self.SoloButton then
            self.SoloButton:Hide()
            self.SoloButton:SetScript("OnClick", nil)
        end
        self.Button:Show()
        if self.Text then self.Text:Show() end
    end
end

-- ---- Dropdown + button ---------------------------------------
-- data.buttonText, data.buttonClick(value), data.buttonTooltip,
-- data.buttonEnabled(value) (optional): false greys the button out.
OCBSettingsDropdownButtonControlMixin = CreateFromMixins(SettingsDropdownControlMixin)

function OCBSettingsDropdownButtonControlMixin:OnLoad()
    SettingsDropdownControlMixin.OnLoad(self)
    local b = CreateFrame("Button", nil, self, "UIMenuButtonStretchTemplate")
    b:SetHeight(22)
    b:SetPoint("LEFT", self.Control.IncrementButton, "RIGHT", 8, 0)
    Mixin(b, DefaultTooltipMixin)
    DefaultTooltipMixin.OnLoad(b)
    self.ActionButton = b
    -- Where the dropdown normally sits, for rows shown without a label.
    if self.Control and self.Control.GetNumPoints then
        self.controlPoints = {}
        for i = 1, self.Control:GetNumPoints() do
            self.controlPoints[i] = { self.Control:GetPoint(i) }
        end
    end
end

-- data.noLabel: hide the label and put the dropdown in its place. Rows
-- are pooled, so the normal layout is put back for the other rows.
function OCBSettingsDropdownButtonControlMixin:PlaceControl(noLabel)
    local c = self.Control
    if not c then return end
    if noLabel then
        if self.Text then self.Text:Hide() end
        c:ClearAllPoints()
        c:SetPoint("LEFT", self, "LEFT", 37, 0)
    else
        if self.Text then self.Text:Show() end
        if self.controlPoints and self.controlPoints[1] then
            c:ClearAllPoints()
            for _, pt in ipairs(self.controlPoints) do c:SetPoint(unpack(pt)) end
        end
    end
end

function OCBSettingsDropdownButtonControlMixin:Init(initializer)
    SettingsDropdownControlMixin.Init(self, initializer)
    local data = initializer:GetData()
    self:PlaceControl(data.noLabel)
    local b = self.ActionButton
    b:SetText(data.buttonText or "")
    FitButton(b, 70)
    if data.buttonText then b:Show() else b:Hide() end
    self:UpdateActionButton()
    b:SetScript("OnClick", function()
        if data.buttonClick then data.buttonClick(self:GetSetting():GetValue()) end
    end)
    if data.buttonTooltip then
        b:SetTooltipFunc(function() Settings.InitTooltip(data.buttonText, data.buttonTooltip) end)
    else
        b:SetTooltipFunc(nil)
    end
end

-- The button is usable when the row is and, with data.buttonEnabled,
-- when the shown value allows it.
function OCBSettingsDropdownButtonControlMixin:UpdateActionButton(value)
    local enabled = self:IsEnabled()
    local data = self.GetElementData and self:GetElementData()
    data = data and data.GetData and data:GetData()
    if enabled and data and data.buttonEnabled then
        if value == nil then value = self:GetSetting():GetValue() end
        enabled = data.buttonEnabled(value) and true or false
    end
    SetEnabled(self.ActionButton, enabled)
end

function OCBSettingsDropdownButtonControlMixin:EvaluateState()
    local enabled = SettingsDropdownControlMixin.EvaluateState(self)
    self:UpdateActionButton()
    return enabled
end

function OCBSettingsDropdownButtonControlMixin:SetValue(value)
    SettingsDropdownControlMixin.SetValue(self, value)
    self:UpdateActionButton(value)
end

function OCBSettingsDropdownButtonControlMixin:Release()
    self.ActionButton:SetScript("OnClick", nil)
    SettingsDropdownControlMixin.Release(self)
end

-- ---- Two checkboxes on one row --------------------------------
-- data.left / data.right: control initializers for ClassicAPI's own
-- checkbox row (SettingsCheckboxControlTemplate). Each half of the row
-- holds one of those rows, so the checkboxes look and behave like the
-- window's others (tooltip, Defaults, enabled state); only the label
-- and box are placed to fit half a row.
OCBSettingsCheckboxPairMixin = {}

local PAIR_SIDES = { "Left", "Right" }

function OCBSettingsCheckboxPairMixin:OnLoad()
    local left = CreateFrame("Frame", nil, self, "SettingsCheckboxControlTemplate")
    left:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", self, "BOTTOM", 0, 0)
    local right = CreateFrame("Frame", nil, self, "SettingsCheckboxControlTemplate")
    right:SetPoint("TOPLEFT", self, "TOP", 0, 0)
    right:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
    self.Left, self.Right = left, right
end

-- Both halves keep the same gap between label and box as a single
-- checkbox row (label at 37 px, box left edge at CENTER - 80): the left
-- box sits exactly where a single row's box does, and the right box is
-- that same distance from its own label.
local SINGLE_TEXT_LEFT, SINGLE_BOX_FROM_CENTER = 37, -80

local function PlaceHalf(row, half, textLeft, boxPoint, boxRel, boxX)
    if half.Checkbox then
        half.Checkbox:ClearAllPoints()
        half.Checkbox:SetPoint("LEFT", row, boxRel, boxX, 0)
    end
    if half.Text then
        half.Text:ClearAllPoints()
        half.Text:SetPoint("LEFT", row, boxPoint, textLeft, 0)
        if half.Checkbox then
            half.Text:SetPoint("RIGHT", half.Checkbox, "LEFT", -5, 0)
        end
        half.Text:SetJustifyH("LEFT")
    end
end

function OCBSettingsCheckboxPairMixin:Init(initializer)
    local data = initializer:GetData()
    for _, side in ipairs(PAIR_SIDES) do
        local half, init = self[side], data[string.lower(side)]
        -- Not in the scroll list, so give each half its own element data.
        half.GetElementData = function() return init end
        half:Init(init)
        half:Show()
    end
    -- Right label at CENTER + 12; the single-row gap (width/2 - 117)
    -- then puts its box at RIGHT - 105, whatever the row's width.
    PlaceHalf(self, self.Left, SINGLE_TEXT_LEFT, "LEFT", "CENTER", SINGLE_BOX_FROM_CENTER)
    PlaceHalf(self, self.Right, 12, "CENTER", "RIGHT", 12 + SINGLE_BOX_FROM_CENTER - SINGLE_TEXT_LEFT)
end

function OCBSettingsCheckboxPairMixin:Release()
    for _, side in ipairs(PAIR_SIDES) do
        local half = self[side]
        if half.Release then half:Release() end
    end
end

-- ---- Text row -------------------------------------------------
-- data.name, data.text (string or function), data.setup(frame) and
-- data.cleanup(frame) for a row that styles its own text.
OCBSettingsTextRowMixin = CreateFromMixins(SettingsListElementMixin)

function OCBSettingsTextRowMixin:Init(initializer)
    SettingsListElementMixin.Init(self, initializer)
    local text = self.data.text
    if type(text) == "function" then text = text() end
    self.Value:SetFontObject(GameFontHighlight)   -- rows are pooled
    self.Value:SetText(text or "")
    if self.data.setup then self.data.setup(self) end
end

function OCBSettingsTextRowMixin:Release()
    if self.data and self.data.cleanup then self.data.cleanup(self) end
    SettingsListElementMixin.Release(self)
end

-- ---- Note -------------------------------------------------------
-- data.text; the row is as tall as the wrapped text.
OCBSettingsNoteMixin = {}

function OCBSettingsNoteMixin:Init(initializer)
    self.Text:SetText(initializer:GetData().text or "")
end

local measure
local function NoteExtent(text)
    if not measure then
        measure = UIParent:CreateFontString(nil, "BACKGROUND", "GameFontHighlight")
        measure:Hide()
        measure:SetWidth(520)   -- the page's narrowest text width
    end
    measure:SetText(text or "")
    return math.max(16, math.ceil(measure:GetStringHeight() or 16)) + 2
end

-- ---- Spell ID box ---------------------------------------------
-- data.name, data.tooltip, data.state (holds .text across redraws),
-- data.describe(spellID) -> text after the box, data.onChanged(spellID)
OCBSettingsSpellInputMixin = CreateFromMixins(SettingsListElementMixin)

function OCBSettingsSpellInputMixin:OnLoad()
    SettingsListElementMixin.OnLoad(self)
    local eb = self.EditBox
    Mixin(eb, DefaultTooltipMixin)
    DefaultTooltipMixin.OnLoad(eb)
    WatchFocus(eb)
    eb:SetScript("OnEnterPressed", function() eb:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function() eb:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", function() UnwatchFocus(eb) end)
    eb:SetScript("OnTextChanged", function()
        local data = self.data
        if not data or data.frame ~= self then return end
        data.state.text = eb:GetText()
        self:Describe()
        if data.onChanged then data.onChanged(tonumber(data.state.text)) end
    end)
end

function OCBSettingsSpellInputMixin:Init(initializer)
    SettingsListElementMixin.Init(self, initializer)
    self.EditBox:SetTooltipFunc(GenerateClosure(InitTooltip, initializer))
    self.data.frame = self
    self:Refresh()
end

function OCBSettingsSpellInputMixin:Refresh()
    local data = self.data
    if self.EditBox:GetText() ~= (data.state.text or "") then
        self.EditBox:SetText(data.state.text or "")
    end
    self:Describe()
end

function OCBSettingsSpellInputMixin:Describe()
    self.SpellName:SetText(self.data.describe(tonumber(self.data.state.text)) or "")
end

function OCBSettingsSpellInputMixin:Release()
    if self.data then self.data.frame = nil end
    self.EditBox:ClearFocus()
    SettingsListElementMixin.Release(self)
end

-- ---- List box --------------------------------------------------
-- data.getEntries() -> array, data.initEntry(button, entry),
-- data.onClick(entry), data.emptyText, data.height
OCBSettingsListBoxMixin = {}

local LIST_BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function OCBSettingsListBoxMixin:OnLoad()
    self.Inset:SetBackdrop(LIST_BACKDROP)
    self.Inset:SetBackdropColor(0, 0, 0, 0.5)
    self.Inset:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(20)
    view:SetElementInitializer("OCBSettingsListEntryTemplate", function(button, entry)
        local data = self.data
        if not data then return end
        button:SetScript("OnClick", function()
            if self.data and self.data.onClick then self.data.onClick(entry) end
        end)
        data.initEntry(button, entry)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view)
end

function OCBSettingsListBoxMixin:Init(initializer)
    self.data = initializer:GetData()
    self.data.frame = self
    self.EmptyText:SetText(self.data.emptyText or "")
    self:Refresh()
end

-- The list only reloads while shown, and a list filled while the
-- window was hidden draws no rows until scrolled. So on show, reload
-- one frame later (once the list has its size) from the top.
local function ShowRefresh(list)
    list:SetScript("OnUpdate", nil)
    if list.data and list:IsVisible() then list:Refresh(true) end
end

function OCBSettingsListBoxMixin:OnShow()
    local list = self
    self:SetScript("OnUpdate", function() ShowRefresh(list) end)
end

-- Reload the entries; keeps the scroll position unless toTop.
function OCBSettingsListBoxMixin:Refresh(toTop)
    local entries = self.data.getEntries() or {}
    self.ScrollBox:SetDataProvider(CreateDataProvider(entries),
        not toTop and ScrollBoxConstants.RetainScrollPosition)
    if toTop then self.ScrollBox:ScrollToBegin(ScrollBoxConstants.NoScrollInterpolation) end
    self.EmptyText:SetShown(#entries == 0)
end

-- Redraw the entries in view (a selection changed).
function OCBSettingsListBoxMixin:Redraw()
    local data = self.data
    self.ScrollBox:ForEachFrame(function(button, entry) data.initEntry(button, entry) end)
end

function OCBSettingsListBoxMixin:Release()
    self:SetScript("OnUpdate", nil)
    if self.data then self.data.frame = nil end
    self.data = nil
end

-- Icon and text of a list entry; icon may be nil.
function UI.SetListEntry(button, icon, text, selected)
    if icon then
        button.Icon:SetTexture(icon)
        button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        button.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        button.Icon:SetTexCoord(0, 1, 0, 1)
    end
    button.Label:SetText(text)
    button.Selected:SetShown(selected and true or false)
end

-- ============================================================
--  PAGES
-- ============================================================

local Page = {}
Page.__index = Page

-- A page of the AddOns tab. parent is another page (nil = top level).
function UI.NewPage(name, parent)
    local category, layout
    if parent then
        category, layout = Settings.RegisterVerticalLayoutSubcategory(parent.category, name)
    else
        category, layout = Settings.RegisterVerticalLayoutCategory(name)
    end
    return setmetatable({ category = category, layout = layout, name = name }, Page)
end

function Page:Add(initializer)
    self.layout:AddInitializer(initializer)
    return initializer
end

function Page:Section(text)
    return self:Add(CreateSettingsListSectionHeaderInitializer(text))
end

function Page:Note(text)
    local init = Settings.CreateElementInitializer("OCBSettingsNoteTemplate", { text = text })
    local extent = NoteExtent(text)
    init.GetExtent = function() return extent end
    return self:Add(init)
end

function Page:TextRow(label, text, tooltip, setup, cleanup)
    local init = Settings.CreateElementInitializer("OCBSettingsTextRowTemplate",
        { name = label, text = text, tooltip = tooltip, setup = setup, cleanup = cleanup })
    init:AddSearchTags(label)
    return self:Add(init)
end

-- A setting stored by OCB. get() returns the value, set(value) stores it.
local function Register(page, variable, varType, label, default, get, set)
    local setting = Settings.RegisterProxySetting(page.category, variable, varType, label, default, get, set)
    UI.variables[#UI.variables + 1] = variable
    return setting
end

function Page:Checkbox(variable, label, tooltip, default, get, set)
    local s = Register(self, variable, Settings.VarType.Boolean, label, default, get, set)
    return Settings.CreateCheckbox(self.category, s, tooltip), s
end

-- Two checkboxes side by side. left / right: { variable, label,
-- tooltip, default, get, set }.
function Page:CheckboxPair(left, right)
    local function Make(o)
        local s = Register(self, o.variable, Settings.VarType.Boolean, o.label, o.default, o.get, o.set)
        return Settings.CreateControlInitializer("SettingsCheckboxControlTemplate", s, nil, o.tooltip), s
    end
    local leftInit, leftSetting = Make(left)
    local rightInit, rightSetting = Make(right)
    local init = Settings.CreateElementInitializer("OCBSettingsCheckboxPairTemplate",
        { left = leftInit, right = rightInit })
    init:AddSearchTags(left.label)
    init:AddSearchTags(right.label)
    self:Add(init)
    return init, leftSetting, rightSetting
end

function Page:Slider(variable, label, tooltip, minV, maxV, step, default, get, set)
    local s = Register(self, variable, Settings.VarType.Number, label, default, get, set)
    local options = Settings.CreateSliderOptions(minV, maxV, step)
    options.step = step
    local init = Settings.CreateControlInitializer("OCBSettingsSliderControlTemplate", s, options, tooltip)
    return self:Add(init), s
end

-- Menu text only takes font objects (SetFont is blocked there): one per
-- font file, made on first use.
local fontObjects = {}
local function FontObjectFor(path)
    if not path then return nil end
    local font = fontObjects[path]
    if not font then
        font = CreateFont("OCBSettingsMenuFont" .. (#UI.fontPaths + 1))
        font:SetFont(path, 13)
        font:SetShadowColor(0, 0, 0, 1)
        font:SetShadowOffset(1, -1)
        UI.fontPaths[#UI.fontPaths + 1] = path
        fontObjects[path] = font
    end
    return font
end
UI.fontPaths = {}

-- items: array of { key=, label= }, or a function that returns one.
-- button (optional): { text=, onClick=function(value), tooltip=, noLabel=,
--   enabled=function(value) (false greys the button out) }
--   noLabel: no label on the row, the dropdown takes its place.
--   Without text, no button is shown (a dropdown with no label only).
-- entryFont (optional): function(key) -> font file to draw that entry in.
function Page:Dropdown(variable, label, tooltip, items, default, get, set, button, entryFont)
    local s = Register(self, variable, Settings.VarType.String, label, default, get, set)
    local function Options()
        local c = Settings.CreateControlTextContainer()
        local list = type(items) == "function" and items() or items
        for _, it in ipairs(list) do c:Add(it.key, it.label) end
        return c:GetData()
    end
    local init
    if button then
        init = Settings.CreateControlInitializer("OCBSettingsDropdownButtonControlTemplate", s, Options, tooltip)
        local data = init:GetData()
        data.buttonText, data.buttonClick, data.buttonTooltip = button.text, button.onClick, button.tooltip
        data.buttonEnabled = button.enabled
        data.noLabel = button.noLabel
        self:Add(init)
    else
        init = Settings.CreateDropdown(self.category, s, Options, tooltip)
    end
    if entryFont then
        -- The window's own entries, each drawn in its font. The menu gives
        -- pooled entry text its normal font back, so other menus keep theirs.
        init.customMenuGenerator = function(_, root)
            root:SetGridMode(MenuConstants.VerticalGridDirection)
            local list = type(items) == "function" and items() or items
            for _, it in ipairs(list) do
                local desc = Settings.CreateDropdownButton(root,
                    { text = it.label, label = it.label, value = it.key, controlType = Settings.ControlType.Radio },
                    function(o) return s:GetValue() == o.value end,
                    function(o) return s:SetValue(o.value) end)
                local font = FontObjectFor(entryFont(it.key))
                if font then
                    -- Runs after the entry's own setup; sizes the text
                    -- the same way (fit + 45 px for the check mark).
                    desc:AddInitializer(function(entryButton)
                        local fs = entryButton.Text
                        if fs then
                            local r, g, b = fs:GetTextColor()   -- selected / normal color
                            fs:SetFontObject(font)
                            fs:SetTextColor(r, g, b)
                            fs:SetTextToFit(it.label)
                            fs:SetWidth(fs:GetWidth() + 45)
                        end
                    end)
                end
            end
        end
    end
    return init, s
end

-- Colors are "AARRGGBB" strings, as ClassicAPI's color swatch row uses.
-- reset (optional): text of a button right of the swatch that puts the
-- default color back.
-- extra (optional): { text=, onClick=, tooltip= } for a second button,
-- right of the reset button. The row is ClassicAPI's own swatch row; the button
-- is added to it when it is drawn and hidden again when it is let go, as
-- rows are pooled.
function Page:ColorSwatch(variable, label, tooltip, default, get, set, reset, extra)
    local s = Register(self, variable, Settings.VarType.String, label, default, get, set)
    local init = Settings.CreateColorSwatch(self.category, s, tooltip)
    if reset and init.InitFrame then
        local initFrame = init.InitFrame
        init.InitFrame = function(it, frame)
            initFrame(it, frame)
            local b = frame.OCBResetButton
            if not b then
                b = CreateFrame("Button", nil, frame, "UIMenuButtonStretchTemplate")
                b:SetHeight(22)
                frame.OCBResetButton = b
                -- Hide it once the row is drawn for another setting.
                local release = frame.Release
                frame.Release = function(f, ...)
                    if f.OCBResetButton then
                        f.OCBResetButton:Hide()
                        f.OCBResetButton:SetScript("OnClick", nil)
                    end
                    if f.OCBExtraButton then
                        f.OCBExtraButton:Hide()
                        f.OCBExtraButton:SetScript("OnClick", nil)
                        f.OCBExtraButton:SetScript("OnEnter", nil)
                        f.OCBExtraButton:SetScript("OnLeave", nil)
                    end
                    if release then return release(f, ...) end
                end
            end
            local swatch = frame.ColorSwatch or frame.Swatch or frame.Control
            b:ClearAllPoints()
            if swatch then
                b:SetPoint("LEFT", swatch, "RIGHT", 10, 0)
            else
                b:SetPoint("LEFT", frame, "CENTER", -40, 0)
            end
            b:SetText(reset)
            FitButton(b, 70)
            b:SetScript("OnClick", function() s:SetValue(default) end)
            b:Show()
            if extra then
                local e = frame.OCBExtraButton
                if not e then
                    e = CreateFrame("Button", nil, frame, "UIMenuButtonStretchTemplate")
                    e:SetHeight(22)
                    frame.OCBExtraButton = e
                end
                e:ClearAllPoints()
                e:SetPoint("LEFT", b, "RIGHT", 6, 0)
                e:SetText(extra.text)
                FitButton(e, 70)
                e:SetScript("OnClick", function() extra.onClick() end)
                if extra.tooltip then
                    e:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(extra.tooltip, 1, 1, 1, 1, true)
                        GameTooltip:Show()
                    end)
                    e:SetScript("OnLeave", function() GameTooltip:Hide() end)
                end
                e:Show()
            elseif frame.OCBExtraButton then
                frame.OCBExtraButton:Hide()
            end
        end
    end
    init:AddSearchTags(label)
    return init, s
end

-- label nil: the button is shown without a label or tooltip.
function Page:Button(label, buttonText, onClick, tooltip)
    local data = { name = label or "", buttonText = buttonText, buttonClick = onClick,
                   tooltip = tooltip, noLabel = not label }
    local init = Settings.CreateElementInitializer("OCBSettingsButtonControlTemplate", data)
    if label then init:AddSearchTags(label) end
    init:AddSearchTags(buttonText)
    return self:Add(init)
end

function Page:SpellInput(label, tooltip, describe, onChanged)
    local data = { name = label, tooltip = tooltip, state = {}, describe = describe, onChanged = onChanged }
    local init = Settings.CreateElementInitializer("OCBSettingsSpellInputTemplate", data)
    init:AddSearchTags(label)
    self:Add(init)
    return data
end

-- Returns the data table; data.frame is the list while it is shown.
function Page:ListBox(height, getEntries, initEntry, onClick, emptyText)
    local data = { getEntries = getEntries, initEntry = initEntry, onClick = onClick, emptyText = emptyText }
    local init = Settings.CreateElementInitializer("OCBSettingsListBoxTemplate", data)
    init.GetExtent = function() return height end
    self:Add(init)
    return data
end

-- ============================================================
--  REGISTRATION AND STATE
-- ============================================================

-- "Spell ID:" -> "Spell ID" (row labels have no colon).
function UI.NoColon(text)
    return (string.gsub(text or "", "%s*:%s*$", ""))
end

function UI.Register(page)
    Settings.RegisterAddOnCategory(page.category)
end

-- Redraw every OCB control from the saved settings (profile change,
-- slash command, bar dragged while the window is open).
function UI.NotifyAll()
    for _, variable in ipairs(UI.variables) do
        Settings.NotifyUpdate(variable)
    end
end

function UI.NotifyUpdate(variable)
    Settings.NotifyUpdate(variable)
end

-- The category the window shows, or nil when it is closed.
function UI.GetShownCategory()
    if SettingsPanel and SettingsPanel:IsShown() then
        return SettingsPanel:GetCurrentCategory()
    end
end
