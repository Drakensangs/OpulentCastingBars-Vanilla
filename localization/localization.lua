-- ============================================================
--  Opulent Casting Bars -- localization.lua
--  Default (English) strings.
--
--  This file always loads. The matching localization.<xx>.lua
--  file loads right after it on non-English clients (gated in the
--  TOC with ClassicAPI's [AllowLoadTextLocale]) and overrides
--  any entry it translates.
--
--  Code reads strings as SCB.L["English text"]. A key with no
--  entry falls back to the key itself, so a missing translation
--  shows English instead of an error.
-- ============================================================

SCB = SCB or {}

local L = setmetatable({}, { __index = function(_, key) return key end })
SCB.L = L

-- ---- Minimap button ----------------------------------------
L["Left click to open the options menu."] = "Left click to open the options menu."
L["Shift left click to preview the cast bar."] = "Shift left click to preview the cast bar."
L["Hold right click to move the minimap button."] = "Hold right click to move the minimap button."

-- ---- Shared labels -----------------------------------------
L["Confirm"] = "Confirm"
L["Cancel"] = "Cancel"
L["Preview"] = "Preview"
L["Reset"] = "Reset"
L["-- None --"] = "-- None --"
L["-- None (auto) --"] = "-- None (auto) --"
L["-- Blizzard UI --"] = "-- Blizzard UI --"
L["Preview: %s"] = "Preview: %s"
L["Options page %d failed to build:"] = "Options page %d failed to build:"

-- ---- Tabs --------------------------------------------------
L["General"] = "General"
L["Style"] = "Style"
L["Text"] = "Text"
L["Schools"] = "Schools"
L["Spells"] = "Spells"

-- ---- General tab -------------------------------------------
L["Bar Size"] = "Bar Size"
L["Scale"] = "Scale"
L["Bar Width"] = "Bar Width"
L["Position"] = "Position"
L["Position X"] = "Position X"
L["Position Y"] = "Position Y"
L["Behaviour"] = "Behaviour"
L["Lock bar position"] = "Lock bar position"
L["Hide Blizzard cast bar"] = "Hide Blizzard cast bar"
L["Pre-warm textures on login"] = "Pre-warm textures on login"
L["Show minimap button"] = "Show minimap button"
L["Frame Strata"] = "Frame Strata"
L["Background"] = "Background"
L["Low"] = "Low"
L["Medium"] = "Medium"
L["High"] = "High"
L["Dialog"] = "Dialog"
L["Fullscreen"] = "Fullscreen"
L["Tooltip"] = "Tooltip"

-- ---- Style tab ---------------------------------------------
L["School Detection"] = "School Detection"
L["Auto-detect spell school"] = "Auto-detect spell school"
L["Use school -> style assignments"] = "Use school -> style assignments"
L["Default / Fixed Style"] = "Default / Fixed Style"
L["Used when detection is off, or for unknown schools."] = "Used when detection is off, or for unknown schools."
L["Preview Any Style"] = "Preview Any Style"
L["Pick a style to preview it."] = "Pick a style to preview it."

-- ---- Text tab ----------------------------------------------
L["Font"] = "Font"
L["Text outline"] = "Text outline"
L["Center both name and timer"] = "Center both name and timer"
L["Spell Name Text"] = "Spell Name Text"
L["Size"] = "Size"
L["X offset"] = "X offset"
L["Y offset"] = "Y offset"
L["Alignment:"] = "Alignment:"
L["Left"] = "Left"
L["Center"] = "Center"
L["Right"] = "Right"
L["Show spell name"] = "Show spell name"
L["Truncate long names (>30 chars)"] = "Truncate long names (>30 chars)"
L["Timer Text"] = "Timer Text"
L["Show cast timer"] = "Show cast timer"
L["Text Color"] = "Text Color"
L["Name & timer color"] = "Name & timer color"
L["Preview Text"] = "Preview Text"

-- ---- Schools tab -------------------------------------------
L["Enable \"Use school -> style assignments\" on the Style page to activate these."] = "Enable \"Use school -> style assignments\" on the Style page to activate these."
L["School -> Style"] = "School -> Style"
L["School -> Profession Style"] = "School -> Profession Style"
L["Clear All Assignments"] = "Clear All Assignments"
L["Arcane Druid"] = "Arcane Druid"
L["Misc / default"] = "Misc / default"

-- ---- Spell schools (also used as assignment row labels) ----
L["Physical"] = "Physical"
L["Holy"] = "Holy"
L["Fire"] = "Fire"
L["Nature"] = "Nature"
L["Frost"] = "Frost"
L["Shadow"] = "Shadow"
L["Arcane"] = "Arcane"

-- ---- Professions -------------------------------------------
L["First Aid"] = "First Aid"
L["Cooking"] = "Cooking"
L["Leatherworking"] = "Leatherworking"
L["Blacksmithing"] = "Blacksmithing"
L["Alchemy"] = "Alchemy"
L["Enchanting"] = "Enchanting"
L["Engineering"] = "Engineering"
L["Tailoring"] = "Tailoring"
L["Fishing"] = "Fishing"
L["Mining"] = "Mining"
L["Herbalism"] = "Herbalism"
L["Skinning"] = "Skinning"
L["Jewelcrafting"] = "Jewelcrafting"
L["Survival"] = "Survival"

-- ---- Style names (not already listed above) ----------------
L["Neutral"] = "Neutral"
L["Neutral 2"] = "Neutral 2"
L["Neutral 3"] = "Neutral 3"
L["Metal"] = "Metal"
L["Metal Icon"] = "Metal Icon"
L["Gears"] = "Gears"
L["Honey Icon"] = "Honey Icon"
L["Mossy Stone"] = "Mossy Stone"
L["Mossy Stone Icon"] = "Mossy Stone Icon"
L["Viking Icon"] = "Viking Icon"
L["Alliance"] = "Alliance"
L["Horde"] = "Horde"
L["Aim"] = "Aim"
L["Arcaneum"] = "Arcaneum"
L["Arctic"] = "Arctic"
L["Earth"] = "Earth"
L["Felfire"] = "Felfire"
L["Frostfire"] = "Frostfire"
L["Inferno"] = "Inferno"
L["Lava"] = "Lava"
L["Lumber"] = "Lumber"
L["Moon"] = "Moon"
L["Paladin"] = "Paladin"
L["Sacred"] = "Sacred"
L["Thunder"] = "Thunder"
L["Water"] = "Water"
L["Chaos"] = "Chaos"
L["Fists of Fury"] = "Fists of Fury"
L["Mistweaver"] = "Mistweaver"
L["Chi'ji"] = "Chi'ji"
L["Bronze"] = "Bronze"
L["Void"] = "Void"

-- ---- Spells tab --------------------------------------------
L["Per-Spell Style Override"] = "Per-Spell Style Override"
L["Force a specific style for any spell by ID."] = "Force a specific style for any spell by ID."
L["Recent Casts"] = "Recent Casts"
L["Click a row to load that spell into the fields below."] = "Click a row to load that spell into the fields below."
L["No spells cast yet."] = "No spells cast yet."
L["ID:"] = "ID:"
L["School:"] = "School:"
L["Spell ID:"] = "Spell ID:"
L["Unknown spell ID"] = "Unknown spell ID"
L["Force Style:"] = "Force Style:"
L["Apply to all ranks"] = "Apply to all ranks"
L["No spell overrides configured."] = "No spell overrides configured."
L["Add / Update Override"] = "Add / Update Override"
L["Remove Override"] = "Remove Override"
L["Clear All Overrides"] = "Clear All Overrides"
L["Remove Rank Overrides"] = "Remove Rank Overrides"
L["Enter a valid spell ID."] = "Enter a valid spell ID."
L["Unknown style: %s"] = "Unknown style: %s"
L["Select an override from the list first."] = "Select an override from the list first."
L["Remove the selected spell override?"] = "Remove the selected spell override?"
L["Clear all spell overrides?"] = "Clear all spell overrides?"
L["Could not resolve the spell name."] = "Could not resolve the spell name."
L["Remove all rank overrides for\n%s?"] = "Remove all rank overrides for\n%s?"

-- ---- Slash commands ----------------------------------------
L["Unknown style \"%s\". Using Neutral instead."] = "Unknown style \"%s\". Using Neutral instead."
L["Testing %s for %.1f s."] = "Testing %s for %.1f s."
L["%s (Test)"] = "%s (Test)"
L["Debug mode enabled. Cast spells to print their spell IDs."] = "Debug mode enabled. Cast spells to print their spell IDs."
L["Debug mode disabled."] = "Debug mode disabled."
L["Bar locked."] = "Bar locked."
L["Bar unlocked. Drag it to reposition."] = "Bar unlocked. Drag it to reposition."
L["Commands:"] = "Commands:"
L["Open the options window"] = "Open the options window"
L["Preview a cast"] = "Preview a cast"
L["Preview duration"] = "Preview duration"
L["How long a preview cast lasts, in seconds."] = "How long a preview cast lasts, in seconds."
L["Stop the current cast"] = "Stop the current cast"
L["Lock or unlock the bar"] = "Lock or unlock the bar"
L["Toggle debug output"] = "Toggle debug output"
L["Show this help"] = "Show this help"
L["[style] [seconds]"] = "[style] [seconds]"
L["Styles:"] = "Styles:"
L["Example:"] = "Example:"

-- ---- AddOn Options panel -----------------------------------
L["Commands"] = "Commands"

-- ---- Buttons on the pages ---------------------------------
L["Add / Update"] = "Add / Update"
L["Clear"] = "Clear"
L["Remove"] = "Remove"

-- ---- Profiles page ---------------------------------------
L["Profiles"] = "Profiles"
L["Profiles are shared by all your characters. Each character remembers the profile it uses."] = "Profiles are shared by all your characters. Each character remembers the profile it uses."
L["Profile"] = "Profile"
L["The profile this character uses."] = "The profile this character uses."
L["New Profile"] = "New Profile"
L["New"] = "New"
L["Creates a copy of the current profile and switches to it."] = "Creates a copy of the current profile and switches to it."
L["Name of the new profile (copy of the current one):"] = "Name of the new profile (copy of the current one):"
L["Delete"] = "Delete"
L["Delete the profile \"%s\"?"] = "Delete the profile \"%s\"?"
L["Reset Profile"] = "Reset Profile"
L["Sets every setting of the current profile back to its default."] = "Sets every setting of the current profile back to its default."
L["Reset the profile \"%s\" to the default settings?"] = "Reset the profile \"%s\" to the default settings?"
L["Invalid profile name"] = "Invalid profile name"
L["Profile already exists"] = "Profile already exists"
L["Profile not found"] = "Profile not found"
L["No profiles"] = "No profiles"
L["Choose a different profile to copy from"] = "Choose a different profile to copy from"
L["Source profile not found"] = "Source profile not found"
