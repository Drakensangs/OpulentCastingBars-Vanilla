-- ============================================================
--  Opulent Casting Bars -- Particles_Arcane.lua
--  Scrolling mirrored fill strips over the Fill_Bar_Arcane base, revealed
--  background runes, side runes and violet glow.
-- ============================================================

local S = {}
local FX = {}
SCB.FX           = SCB.FX or {}
SCB.FX["arcane"] = FX

local function rand(a, b) return a + math.random() * (b - a) end
S.pi2 = math.pi * 2
-- Clamp numeric input to the unit interval.
local function Clamp01(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

-- Fill strip aspect ratio, UV speed, opacity, and mask artwork bounds.
S.FILL_RATIO = 128 / 8112
S.FILL_SCROLL_SPEED = 0.12
S.FILL_BASE_ALPHA = 0.90
S.FILL_MIRROR_ALPHA = 0.45
S.FILL_BOTH_ALPHA = 0.30
S.FILL_MASK_SRC_H = 512
S.FILL_MASK_MIN_Y = 232
S.FILL_MASK_MAX_Y = 315
S.FILL_MASK_CENTER_Y = (S.FILL_MASK_MIN_Y + S.FILL_MASK_MAX_Y) * 0.5
S.FILL_MASK_HEIGHT = S.FILL_MASK_MAX_Y - S.FILL_MASK_MIN_Y + 1

-- Side rune size, rotation, pulse, offsets, and growth cutoff.
S.RUNE_SIZE = 141
S.RUNE_ROT_SPEED = 0.6
S.RUNE_PULSE_SPEED = 1.8
S.RUNE_ALPHA_MIN = 0.55
S.RUNE_ALPHA_MAX = 0.90
S.RUNE_OFFSET_Y = 8
S.RUNE_OFFSET_X = 28
S.RUNE_GROW_END = 0.35

-- Background rune geometry and pulse opacity.
S.RUNE_BACK_W = 460
S.RUNE_BACK_H = 115
S.RUNE_BACK_OFFSET_Y = 56
S.RUNE_BACK_ALPHA = 0.55
S.RUNE_BACK_PULSE_SPEED = 1.4

-- Glow pool, emission cutoff, size, lifetime, and tint.
S.GLOW_COUNT = 60
S.GLOW_SPAWN_RATE = 0.02
S.GLOW_STOP_AT = 0.87
S.GLOW_ALPHA = 0.55
S.GLOW_SIZE_MIN = 6
S.GLOW_SIZE_MAX = 12
S.GLOW_LIFE_MIN = 0.18
S.GLOW_LIFE_MAX = 0.35
S.GLOW_R = 0.55 ; S.GLOW_G = 0.20 ; S.GLOW_B = 1.0

-- Cast state, fade state, and reusable particle pools.
S.isActive = false
S.scrollU = 0
S.runeTimer = 0
S.runeBackTimer  = 0
S.maskRuneBack   = nil
S.maskRuneBack2  = nil
S.glowSpawnAcc = 0

S.rune01Tex = nil
S.rune02Tex = nil
S.swapNext = false

S.texFillBar = nil
S.texFillA = nil
S.texFillB = nil
S.texFillC = nil
S.texFillFlash = nil     -- additive copy of strip A (Fill_Arcane) for the shared flash
S.flashMask = nil        -- unfeathered mask: the flash covers the whole fill region
S.texFillBarFlash = nil  -- additive copy of Fill_Bar_Arcane for the shared flash
S.fillBarFlashClip = nil
S.fillBarFlashBlend = "ADD"  -- current blend mode of texFillBarFlash
S.flashGeom = {}         -- fill geometry from the last UpdateFill, used by FX.SetFlash
S.fillRevealMask = nil
S.texRuneBack = nil
S.texRuneBack2 = nil
S.texRune01 = nil
S.texRune02 = nil
S.glowParts = {}

-- Reuse a glow particle near the fill front.
local function SpawnGlow(frontX, cy, barH)
    for _, p in ipairs(S.glowParts) do
        if not p.active then
            local spread = math.min(barH * 0.25, 10)
            p.active  = true
            p.life    = 0
            p.maxLife = rand(S.GLOW_LIFE_MIN, S.GLOW_LIFE_MAX)
            p.x       = frontX + rand(0, 3)
            p.y       = cy + rand(-spread, spread)
            p.vy      = rand(-5, 5)
            p.phase   = math.random() * S.pi2
            local size = rand(S.GLOW_SIZE_MIN, S.GLOW_SIZE_MAX)
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(0)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            return
        end
    end
end

-- Damp vertical drift and apply oscillation and lifetime fading.
local function UpdateGlow(p, dt, globalFade)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    p.vy = p.vy * 0.90 ^ (dt * 60)
    p.y  = p.y + p.vy * dt + math.sin(p.life * 10 + p.phase) * 0.3 * (dt * 60)
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local env
    if t < 0.2 then env = t / 0.2
    elseif t < 0.8 then env = 1
    else env = (1 - t) / 0.2 end
    p.tex:SetAlpha(math.max(0, env) * S.GLOW_ALPHA * (globalFade or 1))
end

-- Size and anchor a revealed fill strip within the bar. The anchor only
-- changes with the margins or the bar size, so it is re-set only then;
-- the cast itself only changes the width.
local fillAnchors = {}
local function LayoutFillTexture(tex, frame, fillLeftPx, revealW, fillH, yOff)
    if not tex then return end
    local a = fillAnchors[tex]
    if not a then a = {} ; fillAnchors[tex] = a end
    if a.frame ~= frame or a.x ~= fillLeftPx or a.y ~= yOff then
        tex:ClearAllPoints()
        tex:SetPoint("LEFT", frame, "LEFT", fillLeftPx, yOff)
        a.frame, a.x, a.y = frame, fillLeftPx, yOff
    end
    tex:SetSize(revealW, fillH)
end

-- Synchronize fill geometry, reveal masks, scrolling UVs, and background pulse.
local function UpdateFill(dt, progress, barW, barH, fillLX, fillW)
    if not S.texFillA then return end

    local f = SCB.Bar.frameInner
    local cx = f and f:GetCenter()
    if not cx then return end

    progress = Clamp01(progress)
    fillW = math.max(fillW or 1, 1)
    local liveBarW = barW or f:GetWidth()
    local liveBarH = barH or f:GetHeight()
    local barLeft = cx - liveBarW * 0.5
    local fillLeftPx = (fillLX or barLeft) - barLeft
    local revealW = math.max(fillW * progress, 1)
    local fillH = math.max(liveBarH * (S.FILL_MASK_HEIGHT / S.FILL_MASK_SRC_H), 1)
    local yOff = ((S.FILL_MASK_CENTER_Y - S.FILL_MASK_SRC_H * 0.5) / S.FILL_MASK_SRC_H) * liveBarH

    if S.fillBarClip then
        S.fillBarClip:Layout(f, fillLeftPx, fillW, 0, liveBarH, progress)
        if S.texFillBar then
            if S.texFillBarAnchor ~= f then
                S.texFillBarAnchor = f
                S.texFillBar:SetPoint("LEFT", f, "LEFT", 0, 0)
            end
            S.texFillBar:SetSize(liveBarW, liveBarH)
        end
    end
    if S.maskRuneBack then
        S.maskRuneBack:SetWidth(math.max(revealW + fillLeftPx, 1))
        SCB.SetRevealMaskProgress(S.maskRuneBack, progress)
    end
    if S.maskRuneBack2 then
        S.maskRuneBack2:SetWidth(math.max(revealW + fillLeftPx, 1))
        SCB.SetRevealMaskProgress(S.maskRuneBack2, progress)
    end
    LayoutFillTexture(S.texFillA, f, fillLeftPx, revealW, fillH, yOff)
    LayoutFillTexture(S.texFillB, f, fillLeftPx, revealW, fillH, yOff)
    LayoutFillTexture(S.texFillC, f, fillLeftPx, revealW, fillH, yOff)
    if S.fillRevealMask then
        -- Keep the transparent clamp border outside the scrolling strip.
        SCB.LayoutArtworkRevealMask(S.fillRevealMask, S.texFillA, revealW, progress)
    end
    local g = S.flashGeom
    g.f, g.left, g.w, g.h, g.yOff, g.barW, g.barH = f, fillLeftPx, fillW, fillH, yOff, liveBarW, liveBarH
    g.revealW, g.progress = revealW, progress

    S.scrollU = (S.scrollU + S.FILL_SCROLL_SPEED * dt) % 1
    local u = 1 - S.scrollU

    local naturalTileW = math.max(1, fillH / S.FILL_RATIO)
    local span = math.max(revealW / naturalTileW, 0.001)

    -- Clamp channel sampling inside the image to avoid repeated edge streaks;
    -- leave normal-cast UV mapping unchanged.
    if SCB.Bar.isChannel then
        span = math.min(span, 1)
        u = u * (1 - span)
    end
    S.texFillA:SetTexCoord(u, 0,  u, 1,  u+span, 0,  u+span, 1)

    S.texFillB:SetTexCoord(1-u, 0,  1-u, 1,  1-u-span, 0,  1-u-span, 1)

    S.texFillC:SetTexCoord(1-u, 1,  1-u, 0,  1-u-span, 1,  1-u-span, 0)

    if S.texRuneBack2 then
        S.runeBackTimer = S.runeBackTimer + dt
        local pulse = 0.5 + 0.5 * math.sin(S.runeBackTimer * S.RUNE_BACK_PULSE_SPEED)
        S.texRuneBack2:SetAlpha(pulse * S.RUNE_BACK_ALPHA)
    end
end

-- Grow side runes during early progress, then pulse and counter-rotate them.
local function UpdateRunes(dt, progress, fillLX, fillW, barCY)
    if not S.texRune01 then return end

    S.runeTimer = S.runeTimer + dt
    local pulse = S.RUNE_ALPHA_MIN + (S.RUNE_ALPHA_MAX - S.RUNE_ALPHA_MIN)
                  * (0.5 + 0.5 * math.sin(S.runeTimer * S.RUNE_PULSE_SPEED))

    local scale
    if progress < S.RUNE_GROW_END then
        scale = progress / S.RUNE_GROW_END
        scale = math.max(scale, 0.05)
    else
        scale = 1.0
    end
    local size = S.RUNE_SIZE * scale

    local rightX = fillLX + fillW

    S.texRune01:SetSize(size, size)
    S.texRune01:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
        fillLX - S.RUNE_OFFSET_X, barCY + S.RUNE_OFFSET_Y)
    S.texRune01:SetRotation(S.runeTimer * S.RUNE_ROT_SPEED)
    S.texRune01:SetAlpha(pulse * scale)

    S.texRune02:SetSize(size, size)
    S.texRune02:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
        rightX + S.RUNE_OFFSET_X, barCY + S.RUNE_OFFSET_Y)
    S.texRune02:SetRotation(-S.runeTimer * S.RUNE_ROT_SPEED)
    S.texRune02:SetAlpha(pulse * scale)
end

-- Create artwork and reusable texture pools.
function FX.Init(container, bar)
    local school = SCB.Schools.data["arcane"]
    if not school then return end

    local f = SCB.Bar.frameInner
    local fLevel = f:GetFrameLevel() or 3

    -- RevealMask has transparent edges; opaque WHITE8X8 edges do not clip.
    -- Anchor masks over the full glow height to avoid vertical cropping.
    local runeBackHost = CreateFrame("Frame", nil, f)
    runeBackHost:SetAllPoints(f)
    runeBackHost:SetFrameLevel(fLevel - 1)
    S.texRuneBack = runeBackHost:CreateTexture(nil, "BACKGROUND", nil, -1)
    S.texRuneBack:SetTexture(school.runeBack)
    S.texRuneBack:SetBlendMode("ADD")
    S.texRuneBack:SetSize(S.RUNE_BACK_W, S.RUNE_BACK_H)
    S.texRuneBack:SetPoint("CENTER", f, "CENTER", 0, S.RUNE_BACK_OFFSET_Y)
    S.texRuneBack:SetAlpha(S.RUNE_BACK_ALPHA)
    S.maskRuneBack = SCB.NewRevealMask(runeBackHost)
    S.maskRuneBack:SetPoint("LEFT",   f, "LEFT", 0, 0)
    S.maskRuneBack:SetPoint("TOP",    S.texRuneBack, "TOP")
    S.maskRuneBack:SetPoint("BOTTOM", S.texRuneBack, "BOTTOM")
    S.maskRuneBack:SetWidth(1)
    SCB.AttachMask(S.texRuneBack, S.maskRuneBack)

    S.texRuneBack2 = runeBackHost:CreateTexture(nil, "BACKGROUND", nil, -2)
    S.texRuneBack2:SetTexture(school.runeBack)
    S.texRuneBack2:SetBlendMode("ADD")
    S.texRuneBack2:SetSize(S.RUNE_BACK_W, S.RUNE_BACK_H)
    S.texRuneBack2:SetPoint("CENTER", f, "CENTER", 0, S.RUNE_BACK_OFFSET_Y)
    S.texRuneBack2:SetAlpha(0)
    S.maskRuneBack2 = SCB.NewRevealMask(runeBackHost)
    S.maskRuneBack2:SetPoint("LEFT",   f, "LEFT", 0, 0)
    S.maskRuneBack2:SetPoint("TOP",    S.texRuneBack2, "TOP")
    S.maskRuneBack2:SetPoint("BOTTOM", S.texRuneBack2, "BOTTOM")
    S.maskRuneBack2:SetWidth(1)
    SCB.AttachMask(S.texRuneBack2, S.maskRuneBack2)

    local fillBarClip = SCB.Clip:New(f)
    fillBarClip:SetFrameLevel(fLevel)
    local fillBarChild = fillBarClip:GetChild()
    S.texFillBar = fillBarChild:CreateTexture(nil, "ARTWORK", nil, 0)
    if school.fillBar then S.texFillBar:SetTexture(school.fillBar) end
    S.texFillBar:SetPoint("LEFT", f, "LEFT", 0, 0)
    S.texFillBar:SetSize(1, 1)
    S.texFillBar:SetAlpha(0)
    S.fillBarClip = fillBarClip

    -- Flash copy of Fill_Bar_Arcane, one level above it (with the strips).
    -- Its own clip covers the whole fill region (see FX.SetFlash).
    local fillBarFlashClip = SCB.Clip:New(f)
    fillBarFlashClip:SetFixed()
    fillBarFlashClip:SetFrameLevel(fLevel + 1)
    S.texFillBarFlash = fillBarFlashClip:GetChild():CreateTexture(nil, "ARTWORK", nil, 1)
    if school.fillBar then S.texFillBarFlash:SetTexture(school.fillBar) end
    S.texFillBarFlash:SetBlendMode("ADD")
    S.texFillBarFlash:SetPoint("LEFT", f, "LEFT", 0, 0)
    S.texFillBarFlash:SetSize(1, 1)
    S.texFillBarFlash:SetAlpha(0)
    S.fillBarFlashClip = fillBarFlashClip

    local fillAHost = CreateFrame("Frame", nil, f)
    fillAHost:SetAllPoints(f)
    fillAHost:SetFrameLevel(fLevel + 1)

    local fillTex = school.fill
    S.texFillA = fillAHost:CreateTexture(nil, "ARTWORK", nil, 2)
    S.texFillA:SetTexture(fillTex, "REPEAT", "REPEAT")
    S.texFillA:SetBlendMode("ADD")
    S.texFillA:SetPoint("LEFT", f, "LEFT", 0, 0)
    S.texFillA:SetSize(1, 1)
    S.texFillA:SetAlpha(0)

    S.texFillB = fillAHost:CreateTexture(nil, "ARTWORK", nil, 3)
    S.texFillB:SetTexture(fillTex, "REPEAT", "REPEAT")
    S.texFillB:SetBlendMode("ADD")
    S.texFillB:SetPoint("LEFT", f, "LEFT", 0, 0)
    S.texFillB:SetSize(1, 1)
    S.texFillB:SetAlpha(0)

    S.texFillC = fillAHost:CreateTexture(nil, "ARTWORK", nil, 4)
    S.texFillC:SetTexture(fillTex, "REPEAT", "REPEAT")
    S.texFillC:SetBlendMode("ADD")
    S.texFillC:SetPoint("LEFT", f, "LEFT", 0, 0)
    S.texFillC:SetSize(1, 1)
    S.texFillC:SetAlpha(0)

    -- Flash copy of strip A (driven by Animations through FX.SetFlash).
    S.texFillFlash = fillAHost:CreateTexture(nil, "ARTWORK", nil, 5)
    S.texFillFlash:SetTexture(fillTex, "REPEAT", "REPEAT")
    S.texFillFlash:SetBlendMode("ADD")
    S.texFillFlash:SetPoint("LEFT", f, "LEFT", 0, 0)
    S.texFillFlash:SetSize(1, 1)
    S.texFillFlash:SetAlpha(0)
    S.texFillFlash:Hide()

    -- Feather only the front; the translucent Fill_Mask artwork would dim strips.
    S.fillRevealMask = SCB.NewRevealMask(fillAHost)
    for _, tex in ipairs({ S.texFillA, S.texFillB, S.texFillC }) do
        SCB.AttachMask(tex, S.fillRevealMask)
    end
    -- The flash has its own unfeathered mask over the whole fill region.
    S.flashMask = SCB.NewRevealMask(fillAHost)
    SCB.SetRevealMaskFixed(S.flashMask)
    SCB.SetRevealMaskProgress(S.flashMask, 1)
    SCB.AttachMask(S.texFillFlash, S.flashMask)

    local school_r = SCB.Schools.data["arcane"]
    S.rune01Tex = school_r.rune01
    S.rune02Tex = school_r.rune02

    S.texRune01 = container:CreateTexture(nil, "OVERLAY")
    S.texRune01:SetTexture(S.rune01Tex)
    S.texRune01:SetBlendMode("ADD")
    S.texRune01:SetSize(S.RUNE_SIZE, S.RUNE_SIZE)
    S.texRune01:SetAlpha(0)

    S.texRune02 = container:CreateTexture(nil, "OVERLAY")
    S.texRune02:SetTexture(S.rune02Tex)
    S.texRune02:SetBlendMode("ADD")
    S.texRune02:SetSize(S.RUNE_SIZE, S.RUNE_SIZE)
    S.texRune02:SetAlpha(0)

    local glowTex = SCB.TEX_PATH .. "frost\\Particle_Frost_01"
    S.glowParts = {}
    for i = 1, S.GLOW_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(glowTex)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.GLOW_R, S.GLOW_G, S.GLOW_B)
        tex:SetAlpha(0)
        S.glowParts[i] = { tex=tex, active=false, life=0, maxLife=0,
                         x=0, y=0, vy=0, phase=0 }
    end
end

-- Initialize a new cast and clear leftover particles.
function FX.Start(duration)

    -- Animations.lua tints this strip on pushback (see VisibleFills).
    FX.texFillA = S.texFillA
    S.isActive      = true
    S.scrollU       = 0
    S.runeTimer     = 0
    S.runeBackTimer = 0
    S.glowSpawnAcc  = 0
    if S.fillRevealMask then SCB.SetRevealMaskProgress(S.fillRevealMask, 0) end

    -- Select from stable source textures, alternating the slots every cast.
    if S.texRune01 and S.texRune02 then
        S.texRune01:SetTexture(S.swapNext and S.rune02Tex or S.rune01Tex)
        S.texRune02:SetTexture(S.swapNext and S.rune01Tex or S.rune02Tex)
    end
    S.swapNext = not S.swapNext

    if S.texRuneBack then S.texRuneBack:SetAlpha(S.RUNE_BACK_ALPHA) end

    if S.texFillBar  then S.texFillBar:SetAlpha(1)              end
    if S.fillBarClip then S.fillBarClip:Hide() end
    if S.texFillA    then S.texFillA:SetAlpha(S.FILL_BASE_ALPHA)  end
    if S.texFillB    then S.texFillB:SetAlpha(S.FILL_MIRROR_ALPHA) end
    if S.texFillC    then S.texFillC:SetAlpha(S.FILL_BOTH_ALPHA)  end
    if S.maskRuneBack  then S.maskRuneBack:SetWidth(1)  ; SCB.SetRevealMaskProgress(S.maskRuneBack, 0)  end
    if S.maskRuneBack2 then S.maskRuneBack2:SetWidth(1) ; SCB.SetRevealMaskProgress(S.maskRuneBack2, 0) end
    if S.texRune01   then S.texRune01:SetAlpha(S.RUNE_ALPHA_MIN)  end
    if S.texRune02   then S.texRune02:SetAlpha(S.RUNE_ALPHA_MIN)  end

    for _, p in ipairs(S.glowParts) do p.active = false ; p.tex:SetAlpha(0) end
end

-- Shared end-of-cast flash (see Animations.lua): additive copies
-- of both fills (Fill_Arcane strip A and Fill_Bar_Arcane) over the whole
-- fill region. `alpha` 0 hides it. A completed bar that ends empty flashes
-- its background instead; failed or cancelled casts (channels included) call
-- this with `partial` to flash only the revealed part.
-- Fill_Bar_Arcane is dark artwork: added over the full base after a cast it
-- brightens it, but added over an emptied bar (channels) it barely shows.
-- There the copy is drawn normally instead, untinted, following the flash
-- envelope, so the bar artwork flashes in like at the end of a cast.
-- `partial` (cancelled cast): flash only the revealed part of both fills,
-- with the same width, scroll and soft front as the fill itself.
function FX.SetFlash(alpha, col, partial)
    local t, tb = S.texFillFlash, S.texFillBarFlash
    if not t then return end
    if not alpha or alpha <= 0 then
        t:SetAlpha(0) ; t:Hide()
        if tb then tb:SetAlpha(0) ; S.fillBarFlashClip:Hide() end
        return
    end
    local g = S.flashGeom
    if g.f then
        -- Fill_Arcane copy: its UVs continue strip A's pattern.
        local w = partial and (g.revealW or g.w) or g.w
        LayoutFillTexture(t, g.f, g.left, w, g.h, g.yOff)
        if partial then
            SCB.LayoutArtworkRevealMask(S.flashMask, t, w, g.progress or 1)
            SCB.MatchRevealMask(S.flashMask, S.fillRevealMask)
        else
            SCB.LayoutArtworkRevealMask(S.flashMask, t, w, 1)
        end
        local u = 1 - S.scrollU
        local span = math.max(w / math.max(1, g.h / S.FILL_RATIO), 0.001)
        if SCB.Bar.isChannel then
            span = math.min(span, 1)
            u = u * (1 - span)
        end
        t:SetTexCoord(u, 0,  u, 1,  u+span, 0,  u+span, 1)
        -- Fill_Bar_Arcane copy: full-bar artwork shown over the fill region.
        if tb then
            S.fillBarFlashClip:Layout(g.f, g.left, g.w, 0, g.barH, partial and (g.progress or 1) or 1)
            if partial and S.fillBarClip then
                SCB.MatchRevealMask(S.fillBarFlashClip.mask, S.fillBarClip.mask)
            end
            tb:SetSize(g.barW, g.barH)
            local mode = SCB.Bar.fillEmptying and "BLEND" or "ADD"
            if S.fillBarFlashBlend ~= mode then
                S.fillBarFlashBlend = mode
                tb:SetBlendMode(mode)
            end
            if mode == "BLEND" then
                local peak = SCB.Animations.FLASH_PEAK_ALPHA or 0.90
                tb:SetVertexColor(1, 1, 1)
                tb:SetAlpha(math.min(1, alpha / peak))
            else
                tb:SetVertexColor(col[1], col[2], col[3])
                tb:SetAlpha(alpha)
            end
        end
    end
    t:SetVertexColor(col[1], col[2], col[3])
    t:SetAlpha(alpha)
    t:Show()
end

-- Stop emission and begin the style's end-of-cast behavior.
function FX.Stop(success)
    S.isActive = false
    -- A cast that ends on its STOP event can be a hair short of 100%: snap
    -- the fill to complete, like the bar's own fill (Bar:StopCast).
    if success and not SCB.Bar.isChannel then
        local f = SCB.Bar.frame
        local cx = f and f:GetCenter()
        if cx then
            local barW, barH = f:GetWidth(), f:GetHeight()
            local school = SCB.Bar.currentSchool
            local mL = (school and school.fillMarginL or 0) * barW + (school and school.fillMarginLPx or 0)
            local mR = (school and school.fillMarginR or 0) * barW + (school and school.fillMarginRPx or 0)
            UpdateFill(0, 1, barW, barH, cx - barW * 0.5 + mL, barW - mL - mR)
        end
    end
end

-- Clear residual effects and restore owned artwork.
function FX.Reset()
    S.isActive = false
    if S.texFillBar  then S.texFillBar:SetAlpha(0)   end
    if S.fillBarClip then S.fillBarClip:Hide() end
    if S.texFillA    then S.texFillA:SetAlpha(0)     end
    if S.texFillB    then S.texFillB:SetAlpha(0)     end
    if S.texFillC    then S.texFillC:SetAlpha(0)     end
    if S.texFillFlash then S.texFillFlash:SetAlpha(0) ; S.texFillFlash:Hide() end
    if S.texFillBarFlash then S.texFillBarFlash:SetAlpha(0) ; S.fillBarFlashClip:Hide() end
    if S.texRuneBack  then S.texRuneBack:SetAlpha(0)  end
    if S.texRuneBack2 then S.texRuneBack2:SetAlpha(0) end
    if S.maskRuneBack  then S.maskRuneBack:SetWidth(1)  ; SCB.SetRevealMaskProgress(S.maskRuneBack, 0)  end
    if S.maskRuneBack2 then S.maskRuneBack2:SetWidth(1) ; SCB.SetRevealMaskProgress(S.maskRuneBack2, 0) end
    if S.texRune01   then S.texRune01:SetAlpha(0)    end
    if S.texRune02   then S.texRune02:SetAlpha(0)    end
    for _, p in ipairs(S.glowParts) do p.active = false ; p.tex:SetAlpha(0) end

end

-- Advance active-cast animation and particle emission.
function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    if not S.isActive then return end

    local f = SCB.Bar.frameInner
    local cx, barCY = f:GetCenter()
    if not cx then return end

    UpdateFill(dt, progress, barW, barH, fillLX, fillW)
    UpdateRunes(dt, progress, fillLX, fillW, barCY)

    for _, p in ipairs(S.glowParts) do UpdateGlow(p, dt, 1) end
    if SCB.Particles.emitProgress < S.GLOW_STOP_AT then
        S.glowSpawnAcc = S.glowSpawnAcc + dt
        if S.glowSpawnAcc >= S.GLOW_SPAWN_RATE then
            S.glowSpawnAcc = 0
            local count = math.random(2, 4)
            for _ = 1, count do SpawnGlow(frontX, barCY, barH) end
        end
    end
end
