-- ============================================================
--  Opulent Casting Bars -- Schools.lua
--  Style ("school") definitions and spell -> style detection.
-- ============================================================

SCB.Schools = {}

-- ---- Style definitions ---------------------------------------
-- Common fields (all optional except name/frame/fill/bg):
--   name                 label shown in the options window
--   frame / fill / bg    frame border, progress fill, background
--   fillMarginL/R        empty space left/right of the fill, as a fraction
--                        of the bar width; fillMarginLPx/RPx add pixels
--   fillOffsetY          vertical fill offset (px)
--   fillPlainOffsetX     horizontal shift of the fill texture (px on a 400 px wide bar)
--   barScale             size multiplier for this style
--   textNameOffX, textTimerOffX, textOffY   text offsets (px)
--   frameLight           light layer revealed with the cast; it fades out
--                        with the bar (frameLightAlpha, frameLightBlend,
--                        frameLightAdd, frameLightFollowsFill)
--   bgLight              background glow spanning the bar, revealed with the
--                        cast (bgLightBlend, bgLightArtworkReveal)
--   contour / contours   static or animated contour on top
--   gems                 frame gems that light up as the fill reaches them
--   noReverse            channels fill instead of emptying
--   frameLightMatchesFrame  the frameLight artwork is the frame artwork plus a glow
--                        (spread over the whole bar on completion: see Bar:SpreadFrameLight)
--   fillMask             fill drawn by the style's FX module instead
--   noCompletionHold     skip the end-of-cast flash (style plays its own)
-- The end-of-cast flash (an additive copy of the fill, or of the background
-- when the bar ends empty: channels, reverse fills) and the fade-out are
-- shared by every style; see Animations.lua.
-- Any other table of texture paths (leaves, misc, flames, ...) is read by
-- the style's Particles_*.lua file. Every texture path listed here is also
-- picked up by Precache.
SCB.Schools.data = {

    chaos = {
        name         = "Chaos",
        frame        = SCB.TEX_PATH .. "chaos\\Frame_Chaos",
        fill         = SCB.TEX_PATH .. "chaos\\Fill_Chaos",
        bg           = SCB.TEX_PATH .. "chaos\\BG_Chaos",
        fillMarginL  = 0.1221,
        fillMarginR  = 0.1162,
        spikeBGs     = {
            SCB.TEX_PATH .. "chaos\\Spike_BG_01",
            SCB.TEX_PATH .. "chaos\\Spike_BG_02",
            SCB.TEX_PATH .. "chaos\\Spike_BG_03",
            SCB.TEX_PATH .. "chaos\\Spike_BG_04",
        },
    },

    fists = {
        name         = "Fists of Fury",
        frame        = SCB.TEX_PATH .. "fists\\Frame_Fists",
        fill         = SCB.TEX_PATH .. "fists\\Fill_Fists",
        bg           = SCB.TEX_PATH .. "fists\\BG_Fists",
        fillMarginL  = 0.19,
        fillMarginR  = 0.0977,
        noReverse    = true,
        textOffY      = 2,
        textNameOffX  = 35,
        textTimerOffX = -15,
        frameLight   = SCB.TEX_PATH .. "fists\\Frame_Fists_Light",
        fists = {
            SCB.TEX_PATH .. "fists\\Fists_01",
            SCB.TEX_PATH .. "fists\\Fists_02",
            SCB.TEX_PATH .. "fists\\Fists_03",
            SCB.TEX_PATH .. "fists\\Fists_04",
            SCB.TEX_PATH .. "fists\\Fists_Small",
        },
        leaves = {
            SCB.TEX_PATH .. "fists\\Leafpink_01",
            SCB.TEX_PATH .. "fists\\Leafpink_02",
            SCB.TEX_PATH .. "fists\\Leafpink_03",
            SCB.TEX_PATH .. "fists\\Leafpink_04",
            SCB.TEX_PATH .. "fists\\Leafpink_05",
        },
    },

    mistweaver = {
        name         = "Mistweaver",
        frame        = SCB.TEX_PATH .. "mistweaver\\Frame_Mistweaver",
        fill         = SCB.TEX_PATH .. "mistweaver\\Fill_Mistweaver",
        bg           = SCB.TEX_PATH .. "mistweaver\\BG_Mistweaver",
		frameLightBlend = "BLEND",
        frameLightAlpha = 1,
        fillMarginL  = 0.0908,
        fillMarginLPx = 20,
        fillMarginR  = 0.0977,
        textOffY     = 2,
        textNameOffX = 35,
        frameLight   = SCB.TEX_PATH .. "mistweaver\\Frame_Mistweaver_Light",
    },

    chiji = {
        name         = "Chi'ji",
        frame        = SCB.TEX_PATH .. "chiji\\Frame_Chiji",
        fill         = SCB.TEX_PATH .. "chiji\\Fill_Chiji",
        bg           = SCB.TEX_PATH .. "chiji\\BG_Chiji",
		frameLightBlend = "BLEND",
        frameLightAlpha = 1,
        fillMarginL  = 0.0908,
        fillMarginLPx = 20,
        fillMarginR  = 0.0977,
        textOffY     = 2,
        textNameOffX = 35,
        frameLight   = SCB.TEX_PATH .. "chiji\\Frame_Chiji_Light",
    },

    bronze = {
        name        = "Bronze",
        frame       = SCB.TEX_PATH .. "bronze\\Frame_Bronze",
        fill        = SCB.TEX_PATH .. "bronze\\Fill_Bronze",
        bg          = SCB.TEX_PATH .. "bronze\\BG_Bronze",
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        textOffY    = 2,
        sable       = SCB.TEX_PATH .. "bronze\\Sable_Bronze",   -- falling sand layer
        sableDropPx = 23,                                       -- total sand drop (px)
    },

    void = {
        name         = "Void",
        frame        = SCB.TEX_PATH .. "void\\Frame_Void",
        fill         = SCB.TEX_PATH .. "void\\Fill_Void",
        bg           = SCB.TEX_PATH .. "void\\BG_Void",
        frameLightBlend = "BLEND",
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        textOffY     = 2,
        frameLight   = SCB.TEX_PATH .. "void\\Frame_Void_Light",
        frameLightAlpha = 1.0,  -- solid, like Frame_Paladin_Light
        vortex       = SCB.TEX_PATH .. "void\\Vortex",
        misc         = {
            SCB.TEX_PATH .. "holy\\Misc_Holy_01",
            SCB.TEX_PATH .. "holy\\Misc_Holy_02",
        },
    },

    shadow = {
        name          = "Shadow",
        contour       = nil,
        frame         = SCB.TEX_PATH .. "shadow\\Frame_Shadow",
        fill          = SCB.TEX_PATH .. "shadow\\Fill_Shadow",
        bg            = SCB.TEX_PATH .. "shadow\\BG_Shadow",
        fillMarginL      = 0.1484,
        fillMarginR      = 0.1396,
        fillPlainOffsetX = -6,
        textNameOffX  =  31,
        textTimerOffX = -31,
        textOffY      =  2,
        circle  = SCB.TEX_PATH .. "shadow\\Circle_Shadow",
        contours = {
            SCB.TEX_PATH .. "shadow\\Flame_Shadow_01",
            SCB.TEX_PATH .. "shadow\\Flame_Shadow_02",
            SCB.TEX_PATH .. "shadow\\Flame_Shadow_03",
            SCB.TEX_PATH .. "shadow\\Flame_Shadow_04",
            SCB.TEX_PATH .. "shadow\\Flame_Shadow_05",
        },
    },

    nature = {
        name        = "Nature",
        contour     = nil,
        frame       = SCB.TEX_PATH .. "nature\\Frame_Nature_01",
        fill        = SCB.TEX_PATH .. "nature\\Fill_Nature",
        bg          = SCB.TEX_PATH .. "nature\\BG_Nature",
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        frames = {
            SCB.TEX_PATH .. "nature\\Frame_Nature_01",
            SCB.TEX_PATH .. "nature\\Frame_Nature_02",
            SCB.TEX_PATH .. "nature\\Frame_Nature_03",
        },
        leaves = {
            SCB.TEX_PATH .. "nature\\Leaf_01",
            SCB.TEX_PATH .. "nature\\Leaf_02",
            SCB.TEX_PATH .. "nature\\Leaf_03",
            SCB.TEX_PATH .. "nature\\Leaf_04",
            SCB.TEX_PATH .. "nature\\Leaf_05",
        },
    },

    thunder = {
        name        = "Thunder",
        bg          = SCB.TEX_PATH .. "thunder\\BG_Thunder",
        fill        = SCB.TEX_PATH .. "thunder\\Fill_Thunder",
        frame       = SCB.TEX_PATH .. "thunder\\Frame_Thunder",
        fillMarginL  = 0.1709,
        fillMarginR  = 0.1562,
        textOffY    = -2,
        textNameOffX  = 20,
        textTimerOffX = -21,
        frameLight  = SCB.TEX_PATH .. "thunder\\Light_Thunder",
        lightnings  = {
            SCB.TEX_PATH .. "thunder\\Lightning_01",
            SCB.TEX_PATH .. "thunder\\Lightning_02",
            SCB.TEX_PATH .. "thunder\\Lightning_03",
        },
    },

    -- Hunter style: two fills that meet in the middle, plus a portrait orb.
    aim = {
        name         = "Aim",
        bg           = SCB.TEX_PATH .. "aim\\BG_Aim",
        fill         = SCB.TEX_PATH .. "aim\\Fill_Left_Aim",    -- left half
        fillRight    = SCB.TEX_PATH .. "aim\\Fill_Right_Aim",   -- right half
        fillEnding   = SCB.TEX_PATH .. "aim\\Fill_Aim_Ending",  -- flash near the end
        frame        = SCB.TEX_PATH .. "aim\\Frame_Aim",
        splitFill    = true,
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0865,
        -- Right-half margins: L = inset from the bar center, R = inset from
        -- the bar's right edge.
        fillMarginLRight = 0.0908,
        fillMarginRRight = 0.0865,
        textOffY     = 2,
        -- Particles: Nature leaves plus Skinning debris.
        leaves = {
            SCB.TEX_PATH .. "nature\\Leaf_01",
            SCB.TEX_PATH .. "nature\\Leaf_02",
            SCB.TEX_PATH .. "nature\\Leaf_03",
            SCB.TEX_PATH .. "nature\\Leaf_04",
            SCB.TEX_PATH .. "nature\\Leaf_05",
        },
        misc = {
            SCB.TEX_PATH .. "skinning\\Misc_Skinning_01",
            SCB.TEX_PATH .. "skinning\\Misc_Skinning_02",
        },
    },

    holy = {
        name         = "Holy",
        frame        = SCB.TEX_PATH .. "holy\\Frame_Holy",
        fill         = SCB.TEX_PATH .. "holy\\Fill_Holy",
        bg           = SCB.TEX_PATH .. "holy\\BG_Holy",
		frameLightAlpha = 0.8,
        fillMarginL  = 0.1758,
        fillMarginR  = 0.1709,
        frameLight   = SCB.TEX_PATH .. "holy\\Light_Holy",
        misc         = {
            SCB.TEX_PATH .. "holy\\Misc_Holy_01",
            SCB.TEX_PATH .. "holy\\Misc_Holy_02",
        },
        textNameOffX  =  19,
        textTimerOffX = -25,
        textOffY      =   2,
    },

    moon = {
        name         = "Moon",
        frame        = SCB.TEX_PATH .. "moon\\Frame_Moon",
        fill         = SCB.TEX_PATH .. "moon\\Fill_Moon",
        bg           = SCB.TEX_PATH .. "moon\\BG_Moon",
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        textOffY     = 2,
        frameLight   = SCB.TEX_PATH .. "moon\\Frame_Moon_Light",
        -- Holy particles, tinted by Particles_Moon.
        misc         = {
            SCB.TEX_PATH .. "holy\\Misc_Holy_01",
            SCB.TEX_PATH .. "holy\\Misc_Holy_02",
        },
    },

    water = {
        name          = "Water",
        frame         = SCB.TEX_PATH .. "water\\Frame_Water",
        fill          = SCB.TEX_PATH .. "water\\Fill_Water",
        bg            = SCB.TEX_PATH .. "water\\BG_Water",
        fillMarginL  = 0.19,
        fillMarginR  = 0.21,
        textNameOffX  =  34,
        textTimerOffX = -48,
        textOffY      = 2,
        -- Animated ripple circles.
        circle        = SCB.TEX_PATH .. "water\\Water_Circle",
        frameLight    = SCB.TEX_PATH .. "water\\Frame_Water_Light",
    },

    sacred = {
        name         = "Sacred",
        frame        = SCB.TEX_PATH .. "sacred\\Frame_Sacred",
        fill         = SCB.TEX_PATH .. "sacred\\Fill_Sacred",
        bg           = SCB.TEX_PATH .. "sacred\\BG_Sacred",
		frameLightAlpha = 0.75,
        frameLightBlend    = "BLEND",
        frameLightAdd      = 0.5,
        fillMarginL  = 0.105,
        fillMarginR  = 0.105,
        frameLight   = SCB.TEX_PATH .. "sacred\\Frame_Sacred_Light",
        misc         = {
            SCB.TEX_PATH .. "holy\\Misc_Holy_01",
            SCB.TEX_PATH .. "holy\\Misc_Holy_02",
        },
        textNameOffX  =  -1,
        textTimerOffX =  -5,
        textOffY      = -11,
    },

    paladin = {
        name         = "Paladin",
        frame        = SCB.TEX_PATH .. "paladin\\Frame_Paladin",
        fill         = SCB.TEX_PATH .. "paladin\\Fill_Paladin",
        bg           = SCB.TEX_PATH .. "paladin\\BG_Paladin",
        frameLightBlend    = "BLEND",
        frameLightAdd      = 0.5,
        fillMarginL  = 0.075,
        fillMarginR  = 0.105,
        frameLight   = SCB.TEX_PATH .. "paladin\\Frame_Paladin_Light",
        misc         = {
            SCB.TEX_PATH .. "holy\\Misc_Holy_01",
            SCB.TEX_PATH .. "holy\\Misc_Holy_02",
        },
        textNameOffX  =  -1,
        textTimerOffX =  -5,
        textOffY      = -11,
    },

    arcane = {
        name         = "Arcane",
        frame        = SCB.TEX_PATH .. "arcane\\Frame_Arcane",
        fill         = SCB.TEX_PATH .. "arcane\\Fill_Arcane",
        bg           = SCB.TEX_PATH .. "arcane\\BG_Arcane",
        contour      = nil,
        -- Margins match Fill_Mask (its empty pixels are in the mask, not the fill).
        fillMarginL  = 0.1377,
        fillMarginR  = 0.1475,
        -- Drawn by Particles_Arcane.
        fillMask     = SCB.TEX_PATH .. "arcane\\Fill_Mask",
        fillBar      = SCB.TEX_PATH .. "arcane\\Fill_Bar_Arcane",
        runeBack     = SCB.TEX_PATH .. "arcane\\Rune_Back",
        rune01       = SCB.TEX_PATH .. "arcane\\Rune_01",
        rune02       = SCB.TEX_PATH .. "arcane\\Rune_02",
        textNameOffX  = 6,
        textTimerOffX = -14,
    },

    arcaneum = {
        name         = "Arcaneum",
        barScale     = 1,
        -- Reuses the Arctic frame and background with its own fill and light.
        frame        = SCB.TEX_PATH .. "arctic\\Frame_Arctic",
        frameLight   = SCB.TEX_PATH .. "arcaneum\\Frame_Arcaneum_Light",
        fill         = SCB.TEX_PATH .. "arcaneum\\Fill_Arcaneum",
        bg           = SCB.TEX_PATH .. "arctic\\BG_Arctic",
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        fillMarginRPx = 20,
        textOffY      = 4,
        textNameOffX  = 35,
        textTimerOffX = -35,
        rune01       = SCB.TEX_PATH .. "arcane\\Rune_01",
        rune02       = SCB.TEX_PATH .. "arcane\\Rune_02",
    },

    fishing = {
        name        = "Fishing",
        contour     = nil,
        frame       = SCB.TEX_PATH .. "fishing\\Frame_Fishing",
        fill        = SCB.TEX_PATH .. "fishing\\Fill_Fishing",
        bg          = SCB.TEX_PATH .. "fishing\\BG_Fishing",
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        textTimerOffX = -5,
        textOffY    = 2,
    },

    skinning = {
        name        = "Skinning",
        contour     = nil,
        frame       = SCB.TEX_PATH .. "skinning\\Frame_Skinning",
        -- Swapped on purpose: the fur (Fill_Skinning) is the background and
        -- the flesh (BG_Skinning) is the fill that replaces it.
        fill        = SCB.TEX_PATH .. "skinning\\BG_Skinning",
        bg          = SCB.TEX_PATH .. "skinning\\Fill_Skinning",
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        textOffY    = 2,
        misc = {
            SCB.TEX_PATH .. "skinning\\Misc_Skinning_01",
            SCB.TEX_PATH .. "skinning\\Misc_Skinning_02",
        },
    },
    -- Lumber: no regular fill. Particles_Lumber shows progress by swapping
    -- the log texture (Lumber_01 -> 05); the bar background is hidden
    -- during the cast and restored afterwards.
    lumber = {
        name        = "Lumber",
        barScale    = 0.80,
        contour     = nil,
        -- Only seen until the FX module takes over.
        bg          = SCB.TEX_PATH .. "lumber\\Lumber_01",
        fill        = SCB.TEX_PATH .. "lumber\\Lumber_01",
        frame       = nil,
        fillMask          = true,   -- no regular fill
        noCompletionHold  = true,   -- no end-of-cast hold; the FX plays its own split
        -- A channel grows the log like a cast (whole log -> cut), and a
        -- channel that runs to its end splits it, like a cast.
        noReverse         = true,
        fillMarginL = 0,
        fillMarginR = 0,
        textOffY    = 0,
        -- Particles_Lumber has its own copy of these paths; they are listed
        -- here so Precache warms them too.
        lumberStages = {
            SCB.TEX_PATH .. "lumber\\Lumber_01",
            SCB.TEX_PATH .. "lumber\\Lumber_02",
            SCB.TEX_PATH .. "lumber\\Lumber_03",
            SCB.TEX_PATH .. "lumber\\Lumber_04",
            SCB.TEX_PATH .. "lumber\\Lumber_05",
        },
        lumberLeft  = SCB.TEX_PATH .. "lumber\\Lumber_Left",
        lumberRight = SCB.TEX_PATH .. "lumber\\Lumber_Right",
        misc = {
            SCB.TEX_PATH .. "lumber\\Lumber_Misc_01",
            SCB.TEX_PATH .. "lumber\\Lumber_Misc_02",
            SCB.TEX_PATH .. "lumber\\Lumber_Misc_03",
            SCB.TEX_PATH .. "lumber\\Lumber_Misc_04",
            SCB.TEX_PATH .. "lumber\\Lumber_Misc_05",
        },
    },
    mining = {
        name        = "Mining",
        contour     = nil,
        frame       = SCB.TEX_PATH .. "mining\\Frame_Mining",
        fill        = SCB.TEX_PATH .. "mining\\Fill_Mining",
        bg          = SCB.TEX_PATH .. "mining\\BG_Mining",
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        textOffY    = 2,
        stones = {
            SCB.TEX_PATH .. "mining\\Stone_01",
            SCB.TEX_PATH .. "mining\\Stone_02",
            SCB.TEX_PATH .. "mining\\Stone_03",
            SCB.TEX_PATH .. "mining\\Stone_04",
            SCB.TEX_PATH .. "mining\\Stone_05",
            SCB.TEX_PATH .. "mining\\Stone_06",
        },
    },

    herbalism = {
        name        = "Herbalism",
        contour     = nil,
        frame       = SCB.TEX_PATH .. "herbalism\\Frame_Herbalism_01",
        fill        = SCB.TEX_PATH .. "herbalism\\Fill_Herbalism",
        bg          = SCB.TEX_PATH .. "herbalism\\BG_Herbalism",
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        textOffY     = 2,
        textNameOffX  =  10,
        textTimerOffX = -12,
        frames = {
            SCB.TEX_PATH .. "herbalism\\Frame_Herbalism_01",
            SCB.TEX_PATH .. "herbalism\\Frame_Herbalism_02",
            SCB.TEX_PATH .. "herbalism\\Frame_Herbalism_03",
        },
        -- Nature leaves.
        leaves = {
            SCB.TEX_PATH .. "nature\\Leaf_01",
            SCB.TEX_PATH .. "nature\\Leaf_02",
            SCB.TEX_PATH .. "nature\\Leaf_03",
            SCB.TEX_PATH .. "nature\\Leaf_04",
            SCB.TEX_PATH .. "nature\\Leaf_05",
        },
    },

    earth = {
        name        = "Earth",
        contour     = nil,
        frame       = SCB.TEX_PATH .. "earth\\Frame_Earth",
        fill        = SCB.TEX_PATH .. "earth\\Fill_Earth",
        bg          = SCB.TEX_PATH .. "earth\\BG_Earth",
        fillMarginL  = 0.123,
        fillMarginR  = 0.1084,
        rocks = {
            SCB.TEX_PATH .. "earth\\Misc_Earth_01",
            SCB.TEX_PATH .. "earth\\Misc_Earth_02",
            SCB.TEX_PATH .. "earth\\Misc_Earth_03",
            SCB.TEX_PATH .. "earth\\Misc_Earth_04",
        },
        debris = {
            SCB.TEX_PATH .. "earth\\Misc_Earth_05",
            SCB.TEX_PATH .. "earth\\Misc_Earth_06",
            SCB.TEX_PATH .. "earth\\Misc_Earth_07",
            SCB.TEX_PATH .. "earth\\Misc_Earth_08",
            SCB.TEX_PATH .. "earth\\Misc_Earth_09",
            SCB.TEX_PATH .. "earth\\Misc_Earth_10",
            SCB.TEX_PATH .. "earth\\Misc_Earth_11",
        },
        textOffY = 2,
    },

    neutral = {
        name        = "Neutral",
        contour     = nil,
        frame       = SCB.TEX_PATH .. "neutral\\Frame_Neutral",
        fill        = SCB.TEX_PATH .. "neutral\\Fill_Neutral",
        bg          = SCB.TEX_PATH .. "neutral\\BG_Neutral",
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        textOffY    = 2,
    },

    neutral3 = {
        name        = "Neutral 3",
        contour     = nil,
        frame       = SCB.TEX_PATH .. "neutral3\\Frame_Neutral3",
        fill        = SCB.TEX_PATH .. "neutral3\\Fill_Neutral3",
        bg          = SCB.TEX_PATH .. "neutral3\\BG_Neutral3",
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        textOffY    = 2,
    },

    neutral2 = {
        name        = "Neutral 2",
        contour     = nil,
        frame       = SCB.TEX_PATH .. "neutral2\\Frame_Neutral2",
        fill        = SCB.TEX_PATH .. "neutral2\\Fill_Neutral2",
        bg          = SCB.TEX_PATH .. "neutral2\\BG_Neutral2",
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        textOffY    = 2,
        -- Nature leaves, tinted by Particles_Neutral2.
        leaves = {
            SCB.TEX_PATH .. "nature\\Leaf_01",
            SCB.TEX_PATH .. "nature\\Leaf_02",
            SCB.TEX_PATH .. "nature\\Leaf_03",
            SCB.TEX_PATH .. "nature\\Leaf_04",
            SCB.TEX_PATH .. "nature\\Leaf_05",
        },
    },

    viking = {
        name        = "Viking Icon",
        contour     = nil,
        frame       = SCB.TEX_PATH .. "viking\\Frame_Neutral2_Ennemy",
        fill        = SCB.TEX_PATH .. "viking\\Fill_Neutral2_Ennemy",
        bg          = SCB.TEX_PATH .. "viking\\BG_Neutral2_Ennemy",
        bubble      = SCB.TEX_PATH .. "viking\\Bulle_Neutral2_Ennemy",
        circle      = SCB.TEX_PATH .. "viking\\Circle_Neutral2_Ennemy",
        iconMask    = SCB.TEX_PATH .. "viking\\Mask_Icon_Viking",
        fillMarginL  = 0.225,
        fillMarginR  = 0.085,
        textNameOffX = 57,
        textOffY    = 2,
    },

    metal = {
        name        = "Neutral - Metal",
        contour     = nil,
        frame       = SCB.TEX_PATH .. "metal\\Frame_Metal",
        fill        = SCB.TEX_PATH .. "metal\\Fill_Metal",
        bg          = SCB.TEX_PATH .. "metal\\BG_Metal",
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        textOffY    = 2,
    },

    gears = {
        name          = "Gears",
        contour       = nil,
        frame         = SCB.TEX_PATH .. "gears\\Frame_Gears",
        fill          = SCB.TEX_PATH .. "gears\\Fill_Gears",
        bg            = SCB.TEX_PATH .. "gears\\BG_Gears",
        fillMarginL  = 0.25,
        fillMarginR  = 0.044,
        textNameOffX  = 62,
        textTimerOffX = 16,
        textOffY      = 2,
        misc          = SCB.TEX_PATH .. "gears\\Misc_Gears",
        iconMask      = SCB.TEX_PATH .. "gears\\Mask_Icon_Gears",
        circle        = SCB.TEX_PATH .. "gears\\Circle_Gears",
        fork          = SCB.TEX_PATH .. "gears\\Fork_Gears",
    },

    metal_icon = {
        name         = "Metal Icon",
        contour      = nil,
        frame        = SCB.TEX_PATH .. "Metal_Icon\\Frame_Metalicon",
        fill         = SCB.TEX_PATH .. "Metal_Icon\\Fill_Metalicon",
        bg           = SCB.TEX_PATH .. "Metal_Icon\\BG_Metalicon",
        iconMask     = SCB.TEX_PATH .. "Metal_Icon\\Mask_Icon_Metalicon",
        -- Margins match the visible part of Fill_Metalicon.
        fillMarginL  = 0.182,
        fillMarginR  = 0.06,
        textNameOffX  = 37,
        textTimerOffX = 8,
        textOffY      = 2,
    },

    honey_icon = {
        name          = "Honey - Icons",
        contour       = nil,
        frame         = SCB.TEX_PATH .. "honey\\Frame_Honey_Icon",
        fill          = SCB.TEX_PATH .. "honey\\Fill_Honey_Icon",
        bg            = SCB.TEX_PATH .. "honey\\BG_Honey_Icon",
        iconMask      = SCB.TEX_PATH .. "honey\\Mask_Icon_Honey_Icon",
        -- Margins match the visible part of the fill texture.
        fillMarginL  = 0.25,
        fillMarginR  = 0.138,
        textNameOffX  = 52,
        textTimerOffX = -5,
        textOffY      = 2,
    },

    mossystone_icon = {
        name          = "Mossy Stone - Icons",
        contour       = nil,
        frame         = SCB.TEX_PATH .. "mossystone\\Frame_Mossystone_Icon",
        frameLight    = SCB.TEX_PATH .. "mossystone\\Frame_Mossystone_Icon_Light",
        frameLightBlend = "BLEND",
        frameLightFollowsFill = true,
        frameLightMatchesFrame = true,  -- see Bar:SpreadFrameLight
        fill          = SCB.TEX_PATH .. "mossystone\\Fill_Mossystone_Icon",
        bg            = SCB.TEX_PATH .. "mossystone\\BG_Mossystone_Icon",
        iconMask      = SCB.TEX_PATH .. "mossystone\\Mask_Icon_Mossystone_Icon",
        -- Larger left margin to skip the fill's transparent left area.
        fillMarginL  = 0.175,
        fillMarginR  = 0.02,
        textNameOffX  = 52,
        textTimerOffX = -5,
        textOffY      = 2,
    },

    mossystone = {
        name            = "Mossy Stone",
        contour         = nil,
        frame           = SCB.TEX_PATH .. "mossystone\\Frame_Mossystone",
        frameLight      = SCB.TEX_PATH .. "mossystone\\Frame_Mossystone_Light",
        frameLightBlend = "BLEND",
        frameLightFollowsFill = true,
        frameLightMatchesFrame = true,  -- see Bar:SpreadFrameLight
        fill            = SCB.TEX_PATH .. "mossystone\\Fill_Mossystone",
        bg              = SCB.TEX_PATH .. "mossystone\\BG_Mossystone",
        fillMarginL  = 0.05,
        fillMarginR  = 0.05,
        textNameOffX    = -5,
        textOffY        = 2,
    },

    alliance = {
        name        = "Alliance",
        contour     = nil,
        frame       = SCB.TEX_PATH .. "alliance\\Frame_Alliance",
        fill        = SCB.TEX_PATH .. "alliance\\Fill_Alliance",
        bg          = SCB.TEX_PATH .. "alliance\\BG_Alliance",
        bgLight     = SCB.TEX_PATH .. "alliance\\BG_Alliance_Light",
        bgLightArtworkReveal = true,
        gems        = SCB.TEX_PATH .. "alliance\\Saphir_Alliance",
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        textOffY    = 2,
    },

    horde = {
        name        = "Horde",
        contour     = nil,
        frame       = SCB.TEX_PATH .. "horde\\Frame_Horde",
        fill        = SCB.TEX_PATH .. "horde\\Fill_Horde",
        bg          = SCB.TEX_PATH .. "horde\\BG_Horde",
        bgLight     = SCB.TEX_PATH .. "horde\\BG_Light_Horde",
        bgLightArtworkReveal = true,
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        textOffY    = 2,
    },

    frost = {
        name        = "Frost",
        contour     = SCB.TEX_PATH .. "frost\\Contour_Frost",
        frame       = SCB.TEX_PATH .. "frost\\Frame_Frost",
        fill        = SCB.TEX_PATH .. "frost\\Fill_Frost",
        bg          = SCB.TEX_PATH .. "frost\\BG_Frost",
        fillMarginL  = 0.1338,
        fillMarginR  = 0.125,
    },

    arctic = {
        name         = "Arctic",
        barScale     = 1,
        contour      = nil,
        frame        = SCB.TEX_PATH .. "arctic\\Frame_Arctic",
        frameLight   = SCB.TEX_PATH .. "arctic\\Frame_Arctic_Light",
        fill         = SCB.TEX_PATH .. "arctic\\Fill_Arctic",
        bg           = SCB.TEX_PATH .. "arctic\\BG_Arctic",
        bgLight          = SCB.TEX_PATH .. "arctic\\FrostBG_Arctic",
        bgLightBlend     = "BLEND",
        fillMarginL  = 0.1338,
        fillMarginR  = 0.12,
        fillMarginRPx = 20,
        textOffY     = 4,
        textNameOffX = 35,
        textTimerOffX= -35,
    },

    frostfire = {
        name           = "Frostfire",
        frame          = SCB.TEX_PATH .. "frostfire\\Frame_Frostfire",
        fill           = SCB.TEX_PATH .. "frostfire\\Fill_Frostfire",
        bg             = SCB.TEX_PATH .. "frostfire\\BG_Frostfire",
        fillMarginL  = 0.1309,
        fillMarginR  = 0.1289,
        textOffY       = 2,
        -- Frost overlay revealed with the cast, above the frame.
        frostfireGivre = SCB.TEX_PATH .. "frostfire\\Texture_Givre_Frostfire",
        -- Animated flames (like Fire's fillEffects).
        frostfireEffects = {
            SCB.TEX_PATH .. "frostfire\\Effect_Frostfire_01",
            SCB.TEX_PATH .. "frostfire\\Effect_Frostfire_02",
            SCB.TEX_PATH .. "frostfire\\Effect_Frostfire_03",
            SCB.TEX_PATH .. "frostfire\\Effect_Frostfire_04",
            SCB.TEX_PATH .. "frostfire\\Effect_Frostfire_05",
        },
    },

    felfire = {
        name        = "Felfire",
        contour     = nil,
        frame       = SCB.TEX_PATH .. "felfire\\Frame_Felfire",
        frameLight  = SCB.TEX_PATH .. "felfire\\Frame_Felfire_Light",
        fill        = SCB.TEX_PATH .. "felfire\\Fill_Felfire",
        bg          = SCB.TEX_PATH .. "felfire\\BG_Felfire",
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        textOffY    = 2,
    },

    lava = {
        name        = "Lava",
        contour     = nil,
        frame       = SCB.TEX_PATH .. "fire2\\Frame_Fire2",
        frameLight  = SCB.TEX_PATH .. "fire2\\Frame_Fire2_Light",
        fill        = SCB.TEX_PATH .. "fire2\\Fill_Fire2",
        bg          = SCB.TEX_PATH .. "fire2\\BG_Fire2",
        fillMarginL  = 0.0908,
        fillMarginR  = 0.0977,
        textOffY    = 2,
    },

    inferno = {
        name        = "Inferno",
        barScale    = 1,
        contour     = nil,
        frameLight  = SCB.TEX_PATH .. "inferno\\Frame_Inferno_Light",
		frameLightBlend = "BLEND",
        frame       = SCB.TEX_PATH .. "inferno\\Frame_Inferno",
        fill        = SCB.TEX_PATH .. "inferno\\Fill_Inferno",
        bg          = SCB.TEX_PATH .. "inferno\\BG_Inferno",
        flames      = {
            SCB.TEX_PATH .. "inferno\\Fire_Inferno_01",
            SCB.TEX_PATH .. "inferno\\Fire_Inferno_02",
            SCB.TEX_PATH .. "inferno\\Fire_Inferno_03",
            SCB.TEX_PATH .. "inferno\\Fire_Inferno_04",
            SCB.TEX_PATH .. "inferno\\Fire_Inferno_05",
            SCB.TEX_PATH .. "inferno\\Fire_Inferno_06",
            SCB.TEX_PATH .. "inferno\\Fire_Inferno_07",
            SCB.TEX_PATH .. "inferno\\Fire_Inferno_08",
            SCB.TEX_PATH .. "inferno\\Fire_Inferno_09",
            SCB.TEX_PATH .. "inferno\\Fire_Inferno_10",
            SCB.TEX_PATH .. "inferno\\Fire_Inferno_11",
            SCB.TEX_PATH .. "inferno\\Fire_Inferno_12",
        },
        fillMarginL  = 0.0908,
        fillMarginLPx = 20,
        fillMarginR  = 0.1477,
        textOffY      = 4,
        textNameOffX  = 35,
        textTimerOffX = -35,
    },

    fire = {
        name        = "Fire",
        contour     = SCB.TEX_PATH .. "fire\\Contour_Fire_01",
        frame       = SCB.TEX_PATH .. "fire\\Frame_Fire",
        fill        = SCB.TEX_PATH .. "fire\\Fill_Fire",
        bg          = SCB.TEX_PATH .. "fire\\BG_Fire",
        fillMarginL  = 0.1260,
        fillMarginR  = 0.1191,
        -- Red layers revealed with the cast, cycling fill effects and
        -- animated contours (see Particles_Fire).
        bgRed     = SCB.TEX_PATH .. "fire\\BG_Fire_Red",
        frameRed  = SCB.TEX_PATH .. "fire\\Frame_Fire_Red",
        fillEffects = {
            SCB.TEX_PATH .. "fire\\Fill_Fire_Effect_01",
            SCB.TEX_PATH .. "fire\\Fill_Fire_Effect_02",
            SCB.TEX_PATH .. "fire\\Fill_Fire_Effect_03",
            SCB.TEX_PATH .. "fire\\Fill_Fire_Effect_04",
            SCB.TEX_PATH .. "fire\\Fill_Fire_Effect_05",
            SCB.TEX_PATH .. "fire\\Fill_Fire_Effect_06",
        },
        contours  = {
            SCB.TEX_PATH .. "fire\\Contour_Fire_01",
            SCB.TEX_PATH .. "fire\\Contour_Fire_02",
            SCB.TEX_PATH .. "fire\\Contour_Fire_03",
            SCB.TEX_PATH .. "fire\\Contour_Fire_04",
            SCB.TEX_PATH .. "fire\\Contour_Fire_05",
        },
        particles = {
            SCB.TEX_PATH .. "fire\\Particle_Fire_01",
            SCB.TEX_PATH .. "fire\\Particle_Fire_02",
            SCB.TEX_PATH .. "fire\\Particle_Fire_03",
        },
        textOffY = 2,
    },
}

-- ---- Spell school bit -> default style -----------------------------
-- 1 Physical, 2 Holy, 4 Fire, 8 Nature, 16 Frost, 32 Shadow, 64 Arcane
SCB.Schools.maskMap = {
    [64] = "arcane",
    [32] = "shadow",
    [16] = "frost",
    [8]  = "nature",
    [4]  = "lava",
    [2]  = "sacred",
    [1]  = "metal",
}

-- ---- Per-class style for a spell school ------------------------------
-- Applies only to spells in the player's spellbook that are not listed in
-- spellTable (items such as grenades keep the maskMap style). Priority:
--   spellTable > classSchoolMap > maskMap
-- Keys: class file token (UnitClass 2nd return, e.g. "PALADIN"), then the
-- spell school as returned by ClassicAPI GetSpellSchool, lowercase:
--   physical, holy, fire, nature, frost, shadow, arcane
-- Values: any style key from SCB.Schools.data.
SCB.Schools.classSchoolMap = {
    MAGE = { fire = "inferno" },
	PALADIN = { holy = "paladin" },
	PRIEST = { shadow = "shadow" },
	DRUID = { arcane = "moon" },
	SHAMAN = { nature = "water" },
    -- Examples:
    -- WARLOCK = { fire = "felfire" },
    -- PRIEST  = { holy = "sacred", shadow = "shadow" },
}

-- ---- spellID -> style -----------------------------------------------
-- Checked before the spell's school. Lists casts and channels only
-- (instant spells never show a bar).
SCB.Schools.spellTable = {
    -- =====================================================
    --  HUNTER
    -- =====================================================

    -- Pet abilities
    [2641] = "aim", -- Dismiss Pet
    [982]  = "aim", -- Revive Pet - nature
    [1515] = "aim", -- Tame Beast - nature

    -- Vision abilities
    [6197] = "aim", -- Eagle Eye - arcane
    [1002] = "aim", -- Eyes of the Beast - nature

    -- Scare Beast
    [1513]  = "aim", -- rank 1 - nature
    [14326] = "aim", -- rank 2 - nature
    [14327] = "aim", -- rank 3 - nature

    -- Volley
    [1510]  = "aim", -- rank 1 - arcane
    [14294] = "aim", -- rank 2 - arcane
    [14295] = "aim", -- rank 3 - arcane
	
	-- Aimed Shot
	[19434] = "aim", -- rank 1
	[20900] = "aim", -- rank 2
	[20901] = "aim", -- rank 3
	[20902] = "aim", -- rank 4
	[20903] = "aim", -- rank 5
	[20904] = "aim", -- rank 6

    -- =====================================================
    --  SHAMAN
    -- =====================================================

    -- Lightning Bolt
    [403]   = "thunder", -- rank 1
    [529]   = "thunder", -- rank 2
    [548]   = "thunder", -- rank 3
    [915]   = "thunder", -- rank 4
    [943]   = "thunder", -- rank 5
    [6041]  = "thunder", -- rank 6
    [10391] = "thunder", -- rank 7
    [10392] = "thunder", -- rank 8
    [15207] = "thunder", -- rank 9
    [15208] = "thunder", -- rank 10

    -- Chain Lightning
    [421]   = "thunder", -- rank 1
    [930]   = "thunder", -- rank 2
    [2860]  = "thunder", -- rank 3
    [10605] = "thunder", -- rank 4

	[2645] = "nature", -- Ghost Wolf
	[6196] = "nature", -- Far Sight
	[556]  = "nature", -- Astral Recall

	-- =====================================================
	--  FISHING
	-- =====================================================

	[7620]	= "fishing", -- Apprentice
	[7731]	= "fishing", -- Journeyman
	[7732]	= "fishing", -- Expert
	[18248] = "fishing", -- Artisan

	-- =====================================================
	--  MINING
	-- =====================================================

	[2575]	= "mining", -- Apprentice
	[2576]	= "mining", -- Journeyman
	[3564]	= "mining", -- Expert
	[10248] = "mining", -- Artisan

	-- =====================================================
	--  SKINNING
	-- =====================================================

	[8613]	= "skinning", -- Apprentice
	[8617]	= "skinning", -- Journeyman
	[8618]	= "skinning", -- Expert
	[10768] = "skinning", -- Artisan

	-- =====================================================
	--  HERBALISM
	-- =====================================================

	[2366]	= "herbalism", -- Apprentice
	[2368]	= "herbalism", -- Journeyman
	[3570]	= "herbalism", -- Expert
	[11993] = "herbalism", -- Artisan

	-- Hidden Herb Gathering variants that can appear in cast events
	[2369]	= "herbalism",
	[2371]	= "herbalism",
	
	-- =====================================================
	--  Engineering grenades
	-- =====================================================
	[4054] 	= "gears", -- Rough Dynamite
	[4061] 	= "gears", -- Coarse Dynamite
	[4062] 	= "gears", -- Heavy Dynamite
	[4064] 	= "gears", -- Rough Copper Bomb
	[4065] 	= "gears", -- Large Copper Bomb
	[4066] 	= "gears", -- Small Bronze Bomb
	[4067] 	= "gears", -- Big Bronze Bomb
	[4068] 	= "gears", -- Iron Grenade
	[4069] 	= "gears", -- Big Iron Bomb
	[8331] 	= "gears", -- Ez-Thro Dynamite
	[12419]	= "gears", -- Solid Dynamite
	[12421]	= "gears", -- Mithril Frag Bomb
	[12543]	= "gears", -- Hi-Explossive Bomb
	[12562]	= "gears", -- The Big One
	[19769]	= "gears", -- Thorium Grenade
	[19784]	= "gears", -- Dark Iron Bomb
	[19821]	= "gears", -- Arcane Bomb
	[23000]	= "gears", -- Ez-Thro Dynamite II
	[23063]	= "gears", -- Dense Dynamite

	-- =====================================================
	--  SURVIVAL (TW)
	-- =====================================================
	[33427]	= "lumber", -- Cut Wood -- Apprentice
	[33428]	= "lumber", -- Cut Wood -- Journeyman
	[33429]	= "lumber", -- Cut Wood -- Expert
	[33430]	= "lumber", -- Cut Wood -- Artisan
}

-- ============================================================
--  LOOKUPS
-- ============================================================

-- Style definition by key (falls back to Neutral).
function SCB.Schools:Get(key)
    return self.data[key] or self.data["neutral"] or self.data["frost"]
end

function SCB.Schools:Exists(key)
    return self.data[key] ~= nil
end

-- Style for casts no rule matched: the "Misc" assignment row ("blizzard"
-- included), else the default style, else Neutral.
function SCB.Schools:_firstAvailable()
    if SCB.Config and SCB.Config:Get("useThemeAssignments") then
        local assignments = SCB.Config:Get("themeAssignments") or {}
        local misc = assignments.misc
        if misc == "blizzard" then return "blizzard" end
        if misc and misc ~= "none" and self.data[misc] then return misc end
    end
    local default = SCB.Config and SCB.Config:Get("defaultSchool")
    if default and self.data[default] then return default end
    if self.data.neutral then return "neutral" end
    return next(self.data)
end

-- Detected style -> row of the "School -> Style" assignment list, for
-- styles that share a row.
local ASSIGNMENT_PARENT = {
    neutral  = "misc",     -- neutral school -> misc row
    lava     = "inferno",  -- non-Mage fire (Warlock, Shaman) -> Fire row
    frost    = "arctic",   -- non-Mage frost spells -> Frost row
    arcane   = "arcaneum", -- non-Mage arcane spells -> Arcane row
}

-- Apply the user's "School -> Style" choice to a detected style.
-- Returns the detected style, the chosen one, or "blizzard".
function SCB.Schools:_applyThemeAssignment(schoolKey)
    if not schoolKey then return schoolKey end
    if SCB.Config and SCB.Config:Get("useThemeAssignments") then
        local assignments = SCB.Config:Get("themeAssignments") or {}
        local lookupKey = ASSIGNMENT_PARENT[schoolKey] or schoolKey
        local mapped = assignments[schoolKey] or (lookupKey ~= schoolKey and assignments[lookupKey])
        -- "none": keep the detected style.
        if mapped == "none" then
            return schoolKey
        end
        -- "blizzard": OCB stays hidden and the Blizzard bar shows this cast.
        if mapped == "blizzard" then
            return "blizzard"
        end
        if mapped and self.data[mapped] then
            return mapped
        end
    end
    return schoolKey
end

-- Player class file ("MAGE", ...), cached on first use.
function SCB.Schools:_PlayerClass()
    if not self._playerClass then
        local _, classFile = UnitClass("player")
        self._playerClass = classFile
    end
    return self._playerClass
end

-- Kept as a pass-through: per-class school styles are configured only in
-- classSchoolMap (e.g. MAGE = { frost = "arctic" }), never hardcoded here.
function SCB.Schools:_remapDetectedSchoolForPlayer(key)
    return key
end

-- ============================================================
--  DETECTION BY NAME
--  Fallback for a cast that arrives without a usable spellID:
--  localized spell name -> style, built once from spellTable
--  through GetSpellInfo.
-- ============================================================
SCB.Schools.nameTable = nil

function SCB.Schools:BuildNameTable()
    local nameTable = {}
    for id, theme in pairs(self.spellTable) do
        local spellName = GetSpellInfo(id)
        if spellName and nameTable[spellName] == nil then
            nameTable[spellName] = theme
        end
    end
    self.nameTable = nameTable
    return nameTable
end

function SCB.Schools:GetThemeForName(spellName)
    if not spellName then return nil end
    if not self.nameTable then self:BuildNameTable() end
    return self.nameTable[spellName]
end

-- ClassicAPI: GetSpellSchool(spellID) -> schoolID (1-based, Spell.dbc).
-- Used when a spell is not listed in spellTable, so it still receives the
-- default style of its school (e.g. Holy Light -> "sacred").
local CLASSICAPI_SCHOOL_MASK = { [1]=1, [2]=2, [3]=4, [4]=8, [5]=16, [6]=32, [7]=64 }

function SCB.Schools:GetSchoolKeyFromClassicAPI(spellID)
    local numericID = tonumber(spellID)
    if not numericID or numericID <= 0 then return nil end
    local schoolID, schoolName = GetSpellSchool(numericID)  -- nil for an invalid ID
    if not schoolID then return nil end

    -- 1) Per-class override (schoolName is English on every locale)
	-- Only for spells in the player's spellbook, so items (grenades,
    -- potions, etc) keep the school's default style from maskMap.
    if schoolName and IsSpellKnown(numericID) then
        local classFile = self:_PlayerClass()
        local byClass = classFile and self.classSchoolMap and self.classSchoolMap[classFile]
        local forced = byClass and byClass[string.lower(schoolName)]
        if forced and self.data[forced] then return forced end
    end

    -- 2) The school's default style
    local mask = CLASSICAPI_SCHOOL_MASK[schoolID]
    local key = mask and self.maskMap[mask]
    if not key then return nil end
    key = self:_remapDetectedSchoolForPlayer(key)
    if self.data[key] then return key end
    return nil
end

-- Natural school before school-style assignments or per-spell overrides. This
-- is used by the override editor to explain the automatic result.
function SCB.Schools:GetNaturalSchoolForSpell(spellID, spellName)
    local numericID = tonumber(spellID)
    local detected = numericID and self.spellTable[numericID] or nil
    if not detected and spellName then detected = self:GetThemeForName(spellName) end
    if detected then detected = self:_remapDetectedSchoolForPlayer(detected) end
    if detected and self.data[detected] then return detected end
    return self:GetSchoolKeyFromClassicAPI(numericID)
end

-- Localized name and rank of a spellID (ClassicAPI GetSpellInfo works for
-- any ID; the rank is "" for unranked spells).
local function GetSpellIdentity(spellID)
    local spellName, spellRank = GetSpellInfo(spellID)
    return spellName, spellRank
end

-- Same name, and same rank when the cast reports one.
local function SpellIdentityMatchesCast(idName, idRank, castName, castRank)
    if not idName or not castName or idName ~= castName then return false end
    if castRank and castRank ~= "" then
        return idRank ~= nil and idRank ~= "" and idRank == castRank
    end
    return true
end

-- Per-spell style override ("Spells" tab). An override saved for the
-- cast's spellID wins; otherwise each saved ID's name/rank is compared with
-- the cast (every rank has its own spellID). Returns style, matchedID.
function SCB.Schools:GetSpellOverride(spellID, spellName, spellRank)
    self.lastOverrideMatchID = nil
    self.lastOverrideMatchTheme = nil
    if not (SCB.Config and SCB.Config:Get("useThemeAssignments")) then return nil end

    local overrides = SCB.Config:Get("spellThemeOverrides")
    if type(overrides) ~= "table" then overrides = OCBSpellOverridesDB end
    if type(overrides) ~= "table" then return nil end

    -- Exact ID from the cast event.
    local numericID = tonumber(spellID)
    if numericID then
        local forced = overrides[numericID] or overrides[tostring(numericID)]
        if forced and self.data[forced] then
            self.lastOverrideMatchID = numericID
            self.lastOverrideMatchTheme = forced
            return forced, numericID
        end

        -- A valid ID without an override goes on to normal detection; the
        -- name/rank scan below only runs when the ID does not match the cast.
        local idName, idRank = GetSpellIdentity(numericID)
        if SpellIdentityMatchesCast(idName, idRank, spellName, spellRank) then
            return nil
        end
    end

    if not spellName then return nil end

    -- Lowest matching ID wins, so the result does not depend on pairs() order.
    local bestID, bestTheme
    for savedID, theme in pairs(overrides) do
        local id = tonumber(savedID)
        if id and self.data[theme] then
            local idName, idRank = GetSpellIdentity(id)
            if SpellIdentityMatchesCast(idName, idRank, spellName, spellRank)
               and (not bestID or id < bestID) then
                bestID, bestTheme = id, theme
            end
        end
    end
    if bestTheme then
        self.lastOverrideMatchID = bestID
        self.lastOverrideMatchTheme = bestTheme
    end
    return bestTheme, bestID
end

-- ============================================================
--  PROFESSION OVERRIDES
--  Crafting professions only. A cast whose SkillLine (ClassicAPI
--  C_SpellBook.GetSpellSkillLine) is one of these skill IDs uses the
--  style chosen in "School -> Profession Style" (professionAssignments).
-- ============================================================
SCB.Schools.professions = {
    { id = 129, label = "First Aid" },
    { id = 185, label = "Cooking" },
    { id = 165, label = "Leatherworking" },
    { id = 164, label = "Blacksmithing" },
    { id = 171, label = "Alchemy" },
    { id = 333, label = "Enchanting" },
    { id = 202, label = "Engineering" },
    { id = 197, label = "Tailoring" },
    -- Turtle WoW professions (turtle = true): listed and used only on a
    -- Turtle WoW client or one built on it. SkillLine IDs from the Turtle
    -- client data (Jewelcrafting 755; Survival 142, the secondary
    -- profession, not the Hunter talent tree, which is 51).
    { id = 755, label = "Jewelcrafting", turtle = true },
    { id = 142, label = "Survival",      turtle = true },
}
SCB.Schools.professionByID = {}
for _, p in ipairs(SCB.Schools.professions) do SCB.Schools.professionByID[p.id] = p end

-- True on a Turtle WoW client or a client built on it (Capybara Paradise,
-- OctoWoW, RavenCraft, ...). ClassicAPI defines the completed-quest
-- functions only on those clients (API.md, "Completed quests").
function SCB.IsTurtleClient()
    return type(GetQuestsCompleted) == "function"
        or type(QueryQuestsCompleted) == "function"
end

-- True when the profession exists on this client.
function SCB.Schools:IsProfessionAvailable(skillID)
    local p = self.professionByID[tonumber(skillID) or 0]
    if not p then return false end
    return (not p.turtle) or SCB.IsTurtleClient()
end

-- The professions this client has, in list order.
function SCB.Schools:GetProfessions()
    local list = {}
    for _, p in ipairs(self.professions) do
        if self:IsProfessionAvailable(p.id) then list[#list + 1] = p end
    end
    return list
end

-- spellID -> profession skillID, or false. Spell data never changes, so
-- each spell is looked up via ClassicAPI only once per session.
SCB.Schools._profSkillCache = {}

-- Returns the profession skill ID a spell belongs to, or nil.
function SCB.Schools:GetProfessionSkillForSpell(spellID)
    local numericID = tonumber(spellID)
    if not numericID or numericID <= 0 then return nil end
    local cached = self._profSkillCache[numericID]
    if cached ~= nil then return cached or nil end
    local _, skillID = C_SpellBook.GetSpellSkillLine(numericID)
    skillID = tonumber(skillID)
    local result = (skillID and self:IsProfessionAvailable(skillID)) and skillID or false
    self._profSkillCache[numericID] = result
    return result or nil
end

-- Style override for a profession spell, or nil when none applies.
function SCB.Schools:GetProfessionOverride(spellID)
    if not (SCB.Config and SCB.Config:Get("useThemeAssignments")) then return nil end
    local pa = SCB.Config:Get("professionAssignments")
    if type(pa) ~= "table" then return nil end
    local skillID = self:GetProfessionSkillForSpell(spellID)
    if not skillID then return nil end
    local mapped = pa[skillID]
    if not mapped or mapped == "none" then return nil end
    if mapped == "blizzard" then return "blizzard" end
    if self.data[mapped] then return mapped end
    return nil
end

-- Style for a cast. Order: per-spell override, profession override,
-- spellTable (by ID, then by name), the spell's school, then the default
-- style. May return "blizzard" (let the Blizzard bar show the cast).
function SCB.Schools:DetectFromSpell(spellID, spellName, spellRank)
    self.lastOverrideMatchID = nil
    self.lastOverrideMatchTheme = nil
    -- Detection off: use the Misc assignment, otherwise the default style.
    if SCB.Config and not SCB.Config:Get("useSchoolDetection") then
        return self:_firstAvailable()
    end

    local forced = self:GetSpellOverride(spellID, spellName, spellRank)
    if forced then return forced end

    local profStyle = self:GetProfessionOverride(spellID)
    if profStyle then return profStyle end

    -- spellTable by ID, trusted only if the ID's name matches the cast.
    if spellID then
        local manual = self.spellTable[spellID]
        if manual then
            local idMatchesCast = true
            if spellName then
                local idName = GetSpellInfo(spellID)
                if idName and idName ~= spellName then
                    idMatchesCast = false
                end
            end
            if idMatchesCast then
                local mapped = self:_remapDetectedSchoolForPlayer(manual)
                if self.data[mapped] then return self:_applyThemeAssignment(mapped) end
            end
        end
    end

    -- spellTable by localized name.
    if spellName then
        local byName = self:GetThemeForName(spellName)
        if byName then
            local mapped = self:_remapDetectedSchoolForPlayer(byName)
            if self.data[mapped] then return self:_applyThemeAssignment(mapped) end
        end
    end

    -- The spell's school (ClassicAPI GetSpellSchool).
    local key = self:GetSchoolKeyFromClassicAPI(spellID)
    if key then return self:_applyThemeAssignment(key) end

    return self:_firstAvailable()
end