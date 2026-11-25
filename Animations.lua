-- ============================================================
--  Opulent Casting Bars -- Animations.lua
--
--  End-of-cast animations: completion flash + fade, failure
--  shake + fade, and pushback flash.
--  Fades are driven by a dedicated OnUpdate rather than an
--  AnimationGroup, so cancelling one never snaps the alpha.
--
--  Consistency rules (every style):
--   * The completion flash is one additive glow, tinted with the style
--     color. A bar that ends full flashes a copy of the style's fill
--     (Bar.texFlash / texFlashRight, or the FX module's FX.SetFlash for
--     fillMask styles) over the whole fill region. A bar that ends empty
--     (channels, reverse fills: Bar.fillEmptying) flashes its background
--     instead (Bar.texFlashBG / texFlashBGGlow): a full-fill flash over a
--     drained bar would read as a ghost of a bar that is no longer there.
--   * A cancelled or interrupted cast flashes too, but only the part of
--     the fill that was revealed when it stopped (same rectangle and soft
--     front as the fill itself), then shakes and fades out.
--   * A new cast never flashes: the flash covers the whole fill region,
--     so over the new (still empty) fill it would read as a ghost of the
--     previous cast's full bar.
--   * The fade-out is one alpha ramp on the bar wrapper: bar textures, FX
--     layers, particles and spell icons are its children and fade together
--     (see SCB.FX_LINGER). The FX underlay fades a little faster so it
--     never shows through the layers above it.
-- ============================================================

SCB.Animations = {}

-- Durations in seconds
local COMPLETE_HOLD_DURATION  = 0.30   -- flash, bar kept at full alpha
local COMPLETE_FADE_DURATION  = 0.65
local FAIL_SHAKE_INTERVAL     = 0.04
local FAIL_SHAKE_COUNT        = 4
local FAIL_SHAKE_AMOUNT       = 3
local FAIL_FADE_DURATION      = 0.50
local FAIL_FLASH_DURATION     = 0.30   -- cancel flash of the revealed fill, bar at full alpha
local FAIL_FLASH_MIN_REVEAL   = 0.01   -- below this revealed share there is nothing to flash
local FRAME_LIGHT_SPREAD_SHARE = 0.50  -- share of the flash hold spent spreading / dimming the frame light
local PUSHBACK_FLASH_DURATION = 0.25

-- Flash look
local FLASH_PEAK_ALPHA   = 0.90   -- completion flash peak (additive)
SCB.Animations.FLASH_PEAK_ALPHA = FLASH_PEAK_ALPHA  -- read by FX.SetFlash
local FLASH_ATTACK       = 0.25   -- share of the flash spent ramping up
local FLASH_WHITE_MIX    = 0.30   -- lift the style color toward white
local FLASH_BG_GLOW_MIX  = 0.45   -- background flash: solid glow, share of the flash alpha
local PUSHBACK_FLASH_COLOR = { 1.0, 0.25, 0.15 }  -- red-orange "hit" tint

-- Per-style flash color. Every style is listed so none falls back to the
-- near-white default by accident.
local HIGHLIGHT_COLORS = {
    frost           = { 0.70, 0.95, 1.00 },
    arctic          = { 0.62, 0.90, 1.00 },
    frostfire       = { 0.60, 0.85, 1.00 },
    fire            = { 1.00, 0.60, 0.15 },
    lava            = { 1.00, 0.50, 0.05 },
    inferno         = { 1.00, 0.40, 0.02 },
    felfire         = { 0.15, 1.00, 0.15 },
    earth           = { 0.90, 0.75, 0.45 },
    shadow          = { 0.60, 0.20, 0.90 },
    void            = { 0.55, 0.25, 1.00 },
    nature          = { 0.30, 1.00, 0.25 },
    herbalism       = { 0.30, 1.00, 0.25 },
    lumber          = { 0.72, 0.50, 0.22 },
    mining          = { 0.80, 0.65, 0.35 },
    skinning        = { 0.85, 0.60, 0.40 },
    fishing         = { 0.35, 0.80, 1.00 },
    water           = { 0.35, 0.75, 1.00 },
    arcane          = { 0.70, 0.30, 1.00 },
    arcaneum        = { 0.62, 0.40, 1.00 },
    holy            = { 1.00, 0.95, 0.50 },
    sacred          = { 1.00, 0.90, 0.55 },
    paladin         = { 1.00, 0.85, 0.55 },
    moon            = { 0.60, 0.80, 1.00 },
    thunder         = { 0.60, 0.80, 1.00 },
    aim             = { 1.00, 0.15, 0.05 },
    alliance        = { 0.20, 0.50, 1.00 },
    horde           = { 1.00, 0.15, 0.05 },
    metal           = { 0.95, 0.82, 0.58 },
    metal_icon      = { 0.95, 0.82, 0.58 },
    gears           = { 0.95, 0.82, 0.58 },
    viking          = { 0.95, 0.80, 0.55 },
    honey_icon      = { 1.00, 0.82, 0.30 },
    mossystone      = { 0.55, 0.95, 0.45 },
    mossystone_icon = { 0.55, 0.95, 0.45 },
    bronze          = { 1.00, 0.85, 0.50 },
    chaos           = { 0.35, 1.00, 0.30 },
    fists           = { 0.60, 1.00, 1.00 },
    mistweaver      = { 0.50, 1.00, 0.85 },
    chiji           = { 1.00, 0.55, 0.30 },
    neutral         = { 1.00, 1.00, 0.85 },
    neutral2        = { 1.00, 1.00, 0.85 },
    neutral3        = { 1.00, 0.60, 0.50 },
    default         = { 1.00, 1.00, 0.85 },
}

-- Animation driver. Hidden while idle (OnUpdate only runs on shown
-- frames), so it costs nothing between casts; Wake() starts it.
local fadeFrame = CreateFrame("Frame")
fadeFrame:Hide()
local function Wake() fadeFrame:Show() end

local _fadeActive = false
local _fadeDone   = nil
local _fadeTarget = nil
local _fadeT      = 0      -- seconds into the fade phase
local _fadeDur    = 1
local _fadeFrom   = 1      -- alpha at the start of the fade phase
local _fadePhase  = "fade" -- "hold" (completion / cancel flash) or "fade"
local _fadeHold   = 0
local _holdDur    = COMPLETE_HOLD_DURATION
local _holdFail   = false  -- current hold is the flash of a cancelled cast
local _holdCol    = nil

local _pushbackFlash = false
local _pushbackTimer = 0
local _pushbackFill  = nil  -- fill texture(s) currently tinted by the flash
local _pushbackFill2 = nil

local _flashFX = nil        -- FX module whose SetFlash was last driven
local _flashOnBG = false    -- current flash lights the background (bar ended empty)
local _flashPartial = false -- current flash covers only the revealed fill (cancel)

-- Layered textures fade individually (no group opacity), so a layer that
-- is normally hidden behind another one shows through it while the bar is
-- semi-transparent. The FX underlay (drawn below the bar background, e.g.
-- Inferno's flames, whose cut-out would otherwise show through the fill)
-- fades ahead of the bar. Everything else fades in lockstep; hidden art
-- is removed up front instead (see the header).
local function ApplyLayerFade(k)
    local bar = SCB.Bar
    if not bar then return end
    if bar.bgUnderlayHost then bar.bgUnderlayHost:SetAlpha(k * k) end
end

-- ------------------------------------------------------------
--  Helpers
-- ------------------------------------------------------------

local function StyleColor()
    local key = SCB.Bar and SCB.Bar.currentSchoolKey
    local col = (key and HIGHLIGHT_COLORS[key]) or HIGHLIGHT_COLORS.default
    local w = FLASH_WHITE_MIX
    return { col[1] + (1 - col[1]) * w, col[2] + (1 - col[2]) * w, col[3] + (1 - col[3]) * w }
end

-- The fill texture(s) the player actually sees (pushback tint target):
-- the FX module's own fill for fillMask styles, otherwise texFillPlain,
-- plus the right half for the Aim style (splitFill).
-- The plain fill (Bar.fillStrips, a one-texture list): returned as a list.
local function VisibleFills()
    local bar = SCB.Bar
    if not bar then return nil end
    local school = bar.currentSchool
    if school and school.fillMask then
        local fx = SCB.FX and SCB.FX[bar.currentSchoolKey]
        return (fx and fx.texFillA) or bar.texFill
    end
    return bar.fillStrips or bar.texFillPlain or bar.texFill,
           school and school.splitFill and bar.texFillRight or nil
end

-- Tint a fill (a texture or a list of textures):
-- 1 - (1 - color) * intensity (0 = untinted, 1 = full color).
local function Tint(tex, col, intensity)
    if not tex then return end
    local r = 1 - (1 - col[1]) * intensity
    local g = 1 - (1 - col[2]) * intensity
    local b = 1 - (1 - col[3]) * intensity
    if tex.SetVertexColor then
        tex:SetVertexColor(r, g, b)
    else
        for _, t in ipairs(tex) do t:SetVertexColor(r, g, b) end
    end
end
local WHITE = { 1, 1, 1 }

local function Glow(tex, col, alpha)
    if not tex then return end
    if alpha <= 0 then
        tex:SetAlpha(0) ; tex:Hide()
    else
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(col[1], col[2], col[3])
        tex:SetAlpha(alpha)
        tex:Show()
    end
end

-- Show the shared flash for the current style at `alpha` (0 hides it).
local function SetFlash(col, alpha)
    local bar = SCB.Bar
    local school = bar and bar.currentSchool
    if not school then return end
    if _flashOnBG then
        -- The bar ended empty: light up the background, not the fill.
        Glow(bar.texFlashBG, col, alpha)
        Glow(bar.texFlashBGGlow, col, alpha * FLASH_BG_GLOW_MIX)
        return
    end
    if school.fillMask then
        local fx = SCB.FX and SCB.FX[bar.currentSchoolKey]
        if fx and fx.SetFlash then
            _flashFX = fx
            fx.SetFlash(alpha, col, _flashPartial)
        end
        return
    end
    Glow(bar.texFlash, col, alpha)
    if school.splitFill then Glow(bar.texFlashRight, col, alpha) end
end

-- Hide every flash layer (bar copies and the last FX flash).
local function ClearFlash()
    local bar = SCB.Bar
    if bar then
        Glow(bar.texFlash, WHITE, 0)
        Glow(bar.texFlashRight, WHITE, 0)
        Glow(bar.texFlashBG, WHITE, 0)
        Glow(bar.texFlashBGGlow, WHITE, 0)
    end
    if _flashFX and _flashFX.SetFlash then _flashFX.SetFlash(0, WHITE) end
    _flashFX = nil
end

local function PrepareFlash(partial)
    if SCB.Bar and SCB.Bar.LayoutFlash then SCB.Bar:LayoutFlash(partial) end
end

-- Flash envelope over t = 0..1: quick rise, smooth decay.
local function FlashEnvelope(t)
    if t <= 0 or t >= 1 then return 0 end
    if t < FLASH_ATTACK then
        local a = t / FLASH_ATTACK
        return a * (2 - a)                      -- ease-out rise
    end
    local d = 1 - (t - FLASH_ATTACK) / (1 - FLASH_ATTACK)
    return d * d * (3 - 2 * d)                  -- smoothstep decay
end

-- ------------------------------------------------------------
--  Driver
-- ------------------------------------------------------------

fadeFrame:SetScript("OnUpdate", function(self_frame, dt)
    dt = dt or 0

    -- Pushback flash: short red pulse on the fill when the cast is delayed.
    if _pushbackFlash then
        _pushbackTimer = _pushbackTimer + dt
        local t = _pushbackTimer / PUSHBACK_FLASH_DURATION
        if t >= 1 then
            _pushbackFlash = false
            Tint(_pushbackFill, WHITE, 1) ; Tint(_pushbackFill2, WHITE, 1)
            _pushbackFill, _pushbackFill2 = nil, nil
        else
            local intensity = math.sin(t * math.pi)
            Tint(_pushbackFill,  PUSHBACK_FLASH_COLOR, intensity)
            Tint(_pushbackFill2, PUSHBACK_FLASH_COLOR, intensity)
        end
    end

    if not _fadeActive or not _fadeTarget then
        if not _pushbackFlash then self_frame:Hide() end
        return
    end

    if _fadePhase == "hold" then
        _fadeHold = _fadeHold + dt
        local t = _fadeHold / _holdDur
        _fadeTarget:SetAlpha(1)
        if SCB.Bar then
            local d = math.min(1, t / FRAME_LIGHT_SPREAD_SHARE)
            d = d * d * (3 - 2 * d)
            if _holdFail then
                -- A cancelled cast's frame light dies out with the flash,
                -- so the frame fades as one even layer.
                SCB.Bar:SetFrameLightFade(1 - d)
            elseif not _flashOnBG then
                -- A bar that ends full: its frame light spreads over the
                -- whole frame, which then fades as one even layer.
                SCB.Bar:SpreadFrameLight(d)
            end
        end
        if t >= 1 then
            ClearFlash()
            _fadePhase = "fade"
            _fadeT, _fadeFrom = 0, 1
        else
            SetFlash(_holdCol or StyleColor(), FlashEnvelope(t) * FLASH_PEAK_ALPHA)
        end
        return
    end

    -- "fade" phase: one smooth alpha ramp for the whole bar.
    _fadeT = _fadeT + dt
    local t = _fadeT / _fadeDur
    if t >= 1 then
        _fadeActive = false
        _fadeTarget:SetAlpha(0)
        ApplyLayerFade(0)
        _fadeTarget = nil
        local done = _fadeDone
        _fadeDone = nil
        if done then done() end
        return
    end
    -- Smoothstep: no visible "pop" at the start or the end of the fade.
    local k = 1 - t * t * (3 - 2 * t)
    _fadeTarget:SetAlpha(_fadeFrom * k)
    ApplyLayerFade(_fadeFrom * k)
end)

-- Fade frame from its current alpha to 0 over duration, then call onDone.
local function StartFade(frame, duration, onDone)
    _fadeTarget = frame
    _fadeFrom   = frame:GetAlpha() or 1
    _fadeT      = 0
    _fadeDur    = math.max(duration, 0.01)
    _fadePhase  = "fade"
    _fadeDone   = onDone
    _fadeActive = true
    Wake()
end

-- Stop every running effect and restore alpha and fill tints.
local function CancelFade()
    if _fadeActive and _fadeTarget then
        _fadeTarget:SetAlpha(1)
    end
    -- Only the underlay is restored here (the frame light is restored by
    -- the next cast's first tick).
    if SCB.Bar and SCB.Bar.bgUnderlayHost then SCB.Bar.bgUnderlayHost:SetAlpha(1) end
    Tint(_pushbackFill, WHITE, 1) ; Tint(_pushbackFill2, WHITE, 1)
    _pushbackFill, _pushbackFill2 = nil, nil
    _pushbackFlash = false
    -- Also clear any tint left on the current fill(s).
    local fill, fill2 = VisibleFills()
    Tint(fill, WHITE, 1) ; Tint(fill2, WHITE, 1)
    ClearFlash()
    _flashOnBG  = false
    _flashPartial = false
    _fadeActive = false
    _fadePhase  = "fade"
    _fadeHold   = 0
    _holdDur    = COMPLETE_HOLD_DURATION
    _holdFail   = false
    _holdCol    = nil
    _fadeDone   = nil
    _fadeTarget = nil
end

-- ============================================================
--  PUBLIC API
-- ============================================================

-- Called once from SCB.Bar:Create() so no stale state ever targets the
-- freshly created textures.
function SCB.Animations:Reset()
    _fadeActive    = false
    _fadeDone      = nil
    _fadeTarget    = nil
    _fadeT, _fadeDur, _fadeFrom = 0, 1, 1
    _fadePhase     = "fade"
    _fadeHold      = 0
    _holdDur       = COMPLETE_HOLD_DURATION
    _holdFail      = false
    _holdCol       = nil
    _pushbackFlash = false
    _pushbackTimer = 0
    _pushbackFill  = nil
    _pushbackFill2 = nil
    _flashFX       = nil
    _flashOnBG     = false
    _flashPartial  = false
end

-- Abort any end-of-cast animation and restore the bar's position and
-- alpha. Does not Show() the bar: StartCast does that once it is ready.
function SCB.Animations:Cancel(frame)
    CancelFade()
    if SCB.Bar and SCB.Bar.frameInner then
        SCB.Bar.frameInner:SetAlpha(1)
    end
    local anchor = SCB.Config:Get("anchor")
    local x      = SCB.Config:Get("x")
    local y      = SCB.Config:Get("y")
    frame:ClearAllPoints()
    frame:SetPoint(anchor, UIParent, anchor, x, y)
    frame:SetAlpha(1)
end

-- Successful cast: flash ("hold", bar at full alpha), then fade out.
-- gen is the cast generation that requested it.
function SCB.Animations:PlayComplete(frame, gen, onDone)
    -- A newer cast already started: nothing to animate.
    if gen ~= SCB.Bar.castGeneration then
        if onDone then onDone() end
        return
    end

    CancelFade()
    frame:SetAlpha(1)

    local school = SCB.Bar.currentSchool
    if school and school.noCompletionHold then
        -- The style plays its own end animation (e.g. Lumber's split).
        _fadePhase = "fade"
    else
        PrepareFlash(false)
        -- Channels and reverse fills end empty (Aim and noReverse styles
        -- always fill): flash their background instead of the fill.
        _flashOnBG = SCB.Bar.fillEmptying and true or false
        _flashPartial = false
        _holdCol   = StyleColor()
        _holdDur   = COMPLETE_HOLD_DURATION
        _holdFail  = false
        _fadePhase = "hold"
        _fadeHold  = 0
    end

    _fadeTarget = frame
    _fadeT, _fadeFrom = 0, 1
    _fadeDur    = COMPLETE_FADE_DURATION
    _fadeDone   = onDone
    _fadeActive = true
    Wake()
end

-- ============================================================
--  CANCELLED / FAILED / INTERRUPTED CAST:
--  flash of the revealed fill + shake, then fade out
-- ============================================================

function SCB.Animations:PlayFail(frame, gen, onDone)
    CancelFade()

    local anchor = SCB.Config:Get("anchor")
    local origX  = SCB.Config:Get("x")
    local origY  = SCB.Config:Get("y")
    local shakeCount = 0
    -- Shake steps are timers; tie them to this cast so a step that fires
    -- after a newer cast started never moves that cast's bar.
    gen = gen or SCB.Bar.castGeneration

    frame:SetAlpha(1)
    local function finish()
        frame:ClearAllPoints()
        frame:SetPoint(anchor, UIParent, anchor, origX, origY)
        if onDone then onDone() end
    end

    local bar = SCB.Bar
    local school = bar.currentSchool
    if school and not school.noCompletionHold
       and gen == bar.castGeneration
       and (bar:GetRevealedFraction() or 0) >= FAIL_FLASH_MIN_REVEAL then
        -- Flash exactly what was revealed, like a completed cast flashes
        -- its full bar, then fade.
        PrepareFlash(true)
        _flashOnBG    = false
        _flashPartial = true
        _holdCol      = StyleColor()
        _holdDur      = FAIL_FLASH_DURATION
        _holdFail     = true
        _fadePhase    = "hold"
        _fadeHold     = 0
        _fadeTarget   = frame
        _fadeT, _fadeFrom = 0, 1
        _fadeDur      = FAIL_FADE_DURATION
        _fadeDone     = finish
        _fadeActive   = true
        Wake()
    else
        StartFade(frame, FAIL_FADE_DURATION, finish)
    end

    local function doShake()
        if gen ~= SCB.Bar.castGeneration or not SCB.Bar.isFading then return end

        shakeCount = shakeCount + 1
        if shakeCount > FAIL_SHAKE_COUNT then
            frame:ClearAllPoints()
            frame:SetPoint(anchor, UIParent, anchor, origX, origY)
            return
        end

        local offsetX = (shakeCount % 2 == 0) and FAIL_SHAKE_AMOUNT or -FAIL_SHAKE_AMOUNT
        frame:ClearAllPoints()
        frame:SetPoint(anchor, UIParent, anchor, origX + offsetX, origY)
        C_Timer.After(FAIL_SHAKE_INTERVAL, doShake)
    end

    doShake()
end

-- ============================================================
--  PUSHBACK
-- ============================================================

-- Red flash on the visible fill.
function SCB.Animations:PlayPushback()
    Tint(_pushbackFill, WHITE, 1) ; Tint(_pushbackFill2, WHITE, 1)
    _pushbackFill, _pushbackFill2 = VisibleFills()
    _pushbackTimer = 0
    _pushbackFlash = true
    Wake()
end
