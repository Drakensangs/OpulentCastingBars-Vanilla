-- ============================================================
--  Opulent Casting Bars -- Commands.lua
--  Slash commands: /ocb and /opulentcastingbars
-- ============================================================

SCB.Commands = {}

local L = SCB.L
local PREFIX = "|cff00CCFF[OCB]|r "

-- Help lines, also shown on the overview page in Options.lua.
-- Each entry: command syntax, localized description.
SCB.Commands.HELP = {
    { "/ocb",                                L["Open the options window"] },
    { "/ocb test " .. L["[style] [seconds]"], L["Preview a cast"] },
    { "/ocb stop",                           L["Stop the current cast"] },
    { "/ocb lock | unlock",                  L["Lock or unlock the bar"] },
    { "/ocb debug",                          L["Toggle debug output"] },
    { "/ocb help",                           L["Show this help"] },
}

function SCB.Commands:Register()
    SLASH_OCB1 = "/ocb"
    SLASH_OCB2 = "/opulentcastingbars"
    SlashCmdList["OCB"] = function(msg)
        SCB.Commands:Handle(msg)
    end
end

function SCB.Commands:Handle(msg)
    -- Split into lower-case words.
    local args = {}
    for word in (msg or ""):gmatch("%S+") do
        table.insert(args, word:lower())
    end

    local cmd = args[1]

    -- /ocb, /ocb options | config | opt : toggle the options window
    if not cmd or cmd == "options" or cmd == "config" or cmd == "opt" then
        SCB.Options:Toggle()
        return
    end

    -- /ocb test [style] [seconds]   (defaults: neutral, 3 s; clamped to 0.5-60 s)
    --   e.g. /ocb test frost 5
    if cmd == "test" then
        local school   = args[2] or "neutral"
        local duration = tonumber(args[3]) or 3

        if not SCB.Schools:Exists(school) then
            print(PREFIX .. string.format(L["Unknown style \"%s\". Using Neutral instead."], school))
            school = "neutral"
        end

        duration = math.max(0.5, math.min(duration, 60))

        local displayName = SCB.Schools:Get(school).name
        print(PREFIX .. string.format(L["Testing %s for %.1f s."],
            "|cffffff00" .. displayName .. "|r", duration))

        SCB.Bar:StartCast(string.format(L["%s (Test)"], displayName), duration, school)
        return
    end

    -- /ocb debug : print cast events and spell IDs to chat
    if cmd == "debug" then
        SCB._debugMode = not SCB._debugMode
        if SCB._debugMode then
            print(PREFIX .. "|cffFF9900" .. L["Debug mode enabled. Cast spells to print their spell IDs."] .. "|r")
        else
            print(PREFIX .. L["Debug mode disabled."])
        end
        return
    end

    if cmd == "stop" then
        SCB.Bar:StopCast(false)
        return
    end

    if cmd == "lock" then
        SCB.Config:Set("locked", true)
        SCB.Bar.frame:EnableMouse(false)
        print(PREFIX .. "|cffFF4444" .. L["Bar locked."] .. "|r")
        return
    end

    if cmd == "unlock" then
        SCB.Config:Set("locked", false)
        SCB.Bar.frame:EnableMouse(true)
        print(PREFIX .. "|cff00FF00" .. L["Bar unlocked. Drag it to reposition."] .. "|r")
        return
    end

    -- /ocb help, or anything unrecognized
    self:PrintHelp()
end

function SCB.Commands:PrintHelp()
    print("|cff00CCFFOpulent Casting Bars|r -- " .. L["Commands:"])
    for _, h in ipairs(self.HELP) do
        print("  |cffffff00" .. h[1] .. "|r  -  " .. h[2])
    end
    print(" ")
    -- Built from the live style table so it never goes stale.
    local keys = {}
    for k in pairs(SCB.Schools.data or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    print("  " .. L["Styles:"] .. " " .. table.concat(keys, ", "))
    print("  " .. L["Example:"] .. " |cffffff00/ocb test earth 5|r")
end
