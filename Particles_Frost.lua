-- ============================================================
--  Opulent Casting Bars - Particles_Frost.lua
--  Two staggered mist layers pulse and rotate around the bar.
--  Icy front particles use cast-dependent speed and lifetime; FrostBG reveals with progress.
-- ============================================================

local FX = {}
SCB.FX = SCB.FX or {}
SCB.FX["frost"] = FX

-- Local random, angle, and interpolation helpers.

local function rand(a, b) return a + math.random() * (b - a) end
local function rad(deg)   return deg * math.pi / 180 end
local function lerp(a, b, t) return a + (b - a) * math.max(0, math.min(t, 1)) end

local TEX = SCB.TEX_PATH .. "frost\\"

-- Mist dimensions, alpha, pulse scale, and phase durations.

local MIST_W_BASE    = 338
local MIST_H_BASE    = 169
local MIST_ALPHA_MAX = 0.08
local MIST_SCALE_MIN = 0.45
local MIST_SCALE_MAX = 0.75
local MIST_FADE_IN   = 1.8
local MIST_HOLD_MIN  = 1.2
local MIST_HOLD_MAX  = 2.5
local MIST_FADE_OUT  = 1.5
local MIST_ROT_SPEED = 0.04

local MIST_POSITIONS = { 3/8, 5/8 }

-- Particle pool, gravity, and short/long cast motion ranges.

local PART_COUNT           = 16
local PART_SIZE_BASE       = 7
local PART_SPREAD          = 70
local PART_GRAVITY         = 30
local PART_SPAWN_RATE      = 0.12
local PART_SPEED_SHORT_MIN = 90
local PART_SPEED_SHORT_MAX = 180
local PART_LIFE_SHORT_MIN  = 0.25
local PART_LIFE_SHORT_MAX  = 0.55
local PART_SPEED_LONG_MIN  = 40
local PART_SPEED_LONG_MAX  = 110
local PART_LIFE_LONG_MIN   = 0.6
local PART_LIFE_LONG_MAX   = 1.4

-- Runtime pools, emission timer, and background reveal mask.
local mists        = {}
local parts        = {}
local spawnAccum   = 0
local castDuration = 5
local frostBGMask = nil

local function UpdateFrostBGMask(progress)
    local f = SCB.Particles.frostBGFrame
    local barW = (SCB.Config and SCB.Config:Get("barWidth")) or 400
    SCB.LayoutArtworkRevealMask(frostBGMask, f, math.max(1, barW * progress), progress)
end

-- Rotate texture UV coordinates around the center.
local function SetTextureRotation(tex, angle)
    local c, s = math.cos(angle), math.sin(angle)
    tex:SetTexCoord(
        0.5 + (-0.5)*c - (-0.5)*s,  0.5 + (-0.5)*s + (-0.5)*c,
        0.5 + (-0.5)*c - ( 0.5)*s,  0.5 + (-0.5)*s + ( 0.5)*c,
        0.5 + ( 0.5)*c - (-0.5)*s,  0.5 + ( 0.5)*s + (-0.5)*c,
        0.5 + ( 0.5)*c - ( 0.5)*s,  0.5 + ( 0.5)*s + ( 0.5)*c
    )
end

local function SpawnMist(m)  -- Staggered mist lifecycle: fade in, hold, then fade out.
    local scale = rand(MIST_SCALE_MIN, MIST_SCALE_MAX)
    m.baseW    = MIST_W_BASE * scale
    m.baseH    = MIST_H_BASE * scale
    m.tex:SetSize(m.baseW, m.baseH)
    m.tex:SetAlpha(0)
    m.phase    = "fadein"
    m.timer    = 0
    m.duration = MIST_FADE_IN
    m.alpha    = 0
    m.scaleT   = 0
    m.scaleDir = math.random(2) == 1 and 1 or -1
end

local function UpdateMist(m, dt)
    if m.delay and m.delay > 0 then
        m.delay = m.delay - dt
        return
    end
    if m.phase == "idle" then
        SpawnMist(m)
        return
    end

    -- Anchored to the bar itself, so it follows moves with no per-tick
    -- work; re-anchored only when the offset changes (resize).
    local f = SCB.Bar.frameInner
    local ox = f:GetWidth() * (m.xFrac - 0.5)
    if m.anchorX ~= ox then
        m.anchorX = ox
        m.tex:SetPoint("CENTER", f, "CENTER", ox, 0)
    end

    m.timer  = m.timer + dt
    m.scaleT = m.scaleT + dt
    m.angle  = m.angle + MIST_ROT_SPEED * m.rotDir * dt

    local scalePulse = 1 + math.sin(m.scaleT * 0.45 * m.scaleDir) * 0.09
    m.tex:SetSize(m.baseW * scalePulse, m.baseH * scalePulse)
    SetTextureRotation(m.tex, m.angle)

    if m.phase == "fadein" then
        m.alpha = math.min(m.timer / m.duration, 1) * MIST_ALPHA_MAX
        local pulse = math.sin(m.scaleT * 1.8) * 0.018
        m.tex:SetAlpha(math.max(0, m.alpha + pulse))
        if m.timer >= m.duration then
            m.phase = "hold" ; m.timer = 0
            m.duration = rand(MIST_HOLD_MIN, MIST_HOLD_MAX)
        end
    elseif m.phase == "hold" then
        local pulse = math.sin(m.scaleT * 1.8) * 0.025
        m.tex:SetAlpha(math.max(0, MIST_ALPHA_MAX + pulse))
        if m.timer >= m.duration then
            m.phase = "fadeout" ; m.timer = 0 ; m.duration = MIST_FADE_OUT
        end
    elseif m.phase == "fadeout" then
        m.alpha = (1 - m.timer / m.duration) * MIST_ALPHA_MAX
        m.tex:SetAlpha(math.max(0, m.alpha))
        if m.timer >= m.duration then
            m.tex:SetAlpha(0) ; m.phase = "idle"
        end
    end
end

local function GetPartParams()
    local t = math.max(0, math.min((castDuration - 2) / 3, 1))
    return  -- Cast-scaled ballistic front particles.
        lerp(PART_SPEED_SHORT_MIN, PART_SPEED_LONG_MIN, t),
        lerp(PART_SPEED_SHORT_MAX, PART_SPEED_LONG_MAX, t),
        lerp(PART_LIFE_SHORT_MIN,  PART_LIFE_LONG_MIN,  t),
        lerp(PART_LIFE_SHORT_MAX,  PART_LIFE_LONG_MAX,  t)
end

local function SpawnParticle(wx, wy)
    local speedMin, speedMax, lifeMin, lifeMax = GetPartParams()
    for _, p in ipairs(parts) do
        if not p.active then
            local angle = rad(90 + rand(-PART_SPREAD, PART_SPREAD))
            local speed = rand(speedMin, speedMax)
            local size  = PART_SIZE_BASE + rand(-3, 5)
            p.active  = true
            p.life    = 0
            p.maxLife = rand(lifeMin, lifeMax)
            p.x       = wx + rand(-4, 4)
            p.y       = wy + rand(-6, 6)
            p.vx      = math.cos(angle) * speed
            p.vy      = math.sin(angle) * speed
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(0.42)
            return
        end
    end
end

local function UpdateParticle(p, dt)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    p.vy = p.vy - PART_GRAVITY * dt
    p.x  = p.x + p.vx * dt
    p.y  = p.y + p.vy * dt
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local alpha = t < 0.4 and 1 or (1 - (t - 0.4) / 0.6)
    p.tex:SetAlpha(math.max(0, alpha) * 0.42)
end

function FX.Init(container, bar)
    local _underlay = SCB.Bar and SCB.Bar.bgUnderlayHost or bar
    local f = SCB.Bar and SCB.Bar.frameInner or bar
    -- Style lifecycle and background setup.
    local frostBGHost = CreateFrame("Frame", nil, _underlay)
    frostBGHost:SetPoint("TOPLEFT",    f, "TOPLEFT",    0, 0)
    frostBGHost:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    frostBGHost:SetWidth(1)  -- Create FrostBG behind the fill on the underlay host.
    frostBGHost:Hide()
    local frostBGTex = frostBGHost:CreateTexture(nil, "BACKGROUND", nil, -8)
    frostBGMask = SCB.NewRevealMask(_underlay)  -- Use a frame-backed texture and reveal mask for the background artwork.
    SCB.AttachMask(frostBGTex, frostBGMask)
    frostBGTex:SetPoint("TOPLEFT",    frostBGHost, "TOPLEFT")
    frostBGTex:SetPoint("BOTTOMLEFT", frostBGHost, "BOTTOMLEFT")
    frostBGTex:SetWidth(1)
    frostBGTex:SetTexture(TEX .. "FrostBG_Frost")
    frostBGTex:SetBlendMode("BLEND")
    frostBGTex:SetVertexColor(1, 1, 1)
    frostBGTex:SetAlpha(0)
    SCB.Particles.frostBGHost = frostBGHost
    SCB.Particles.frostBGTex  = frostBGTex
    SCB.Particles.frostBGFrame = f
    UpdateFrostBGMask(0)

    local textures = { TEX .. "Particle_Frost_01", TEX .. "Particle_Frost_02" }
    for i = 1, PART_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(textures[(i % 2) + 1])
        tex:SetAlpha(0)
        tex:SetBlendMode("ADD")
        parts[i] = { tex=tex, active=false, life=0, maxLife=0, x=0, y=0, vx=0, vy=0 }
    end

    for i, xFrac in ipairs(MIST_POSITIONS) do
        local tex = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
        tex:SetTexture(TEX .. "Mist_Frost_01")
        tex:SetSize(MIST_W_BASE, MIST_H_BASE)
        tex:SetAlpha(0)
        tex:SetBlendMode("BLEND")
        mists[i] = {
            tex=tex, xFrac=xFrac, phase="idle", timer=0, duration=0,
            alpha=0, scaleT=0, scaleDir=1, angle=0,
            rotDir=(i % 2 == 0) and 1 or -1,
            baseW=MIST_W_BASE, baseH=MIST_H_BASE,
            delay=(i - 1) * 0.8,
        }
    end
end
-- Defer positioning until Update, when bar geometry is available.
function FX.Start(duration)
    UpdateFrostBGMask(0)
    castDuration = duration or 5
    spawnAccum   = 0
    for i, m in ipairs(mists) do
        m.phase = "idle" ; m.delay = (i - 1) * 0.8 ; m.tex:SetAlpha(0)
    end
    for _, p in ipairs(parts) do p.active = false ; p.tex:SetAlpha(0) end
end

function FX.Stop(success)
    if success and not SCB.Bar.isChannel then
        SCB.Particles:UpdateFrostBG("frost", 1)
        UpdateFrostBGMask(1)
    end
    for _, m in ipairs(mists) do
        if m.phase ~= "idle" then
            m.phase = "linger"  -- keep its alpha; the bar fade hides it
        end
    end
    -- Restore FrostBG after the dispatcher clears it before Stop.
    -- The bar completion/failure animation fades this layer with the bar.
    -- ResetAll performs final cleanup after the fade completes.
    if SCB.Particles.frostBGTex then
        SCB.Particles.frostBGTex:SetAlpha(1)
    end
    if SCB.Particles.frostBGHost then
        SCB.Particles.frostBGHost:Show()
    end
end

-- Keep lingering mist moving at its current alpha and finish particle flights.
function FX.UpdateFade(dt)
    for _, m in ipairs(mists) do
        if m.phase == "linger" then UpdateMist(m, dt) end
    end
    for _, p in ipairs(parts) do UpdateParticle(p, dt) end
end

function FX.Reset()
    SCB.Particles:ResetFrostBG()
    for _, p in ipairs(parts) do p.active = false ; p.tex:SetAlpha(0) end
    for _, m in ipairs(mists) do m.tex:SetAlpha(0) ; m.phase = "idle" end
end

function FX.Update(dt, progress, frontX, cy, barW, barH)
    UpdateFrostBGMask(progress)
    for _, p in ipairs(parts) do UpdateParticle(p, dt) end  -- Advance particles already in flight.
    for _, m in ipairs(mists) do UpdateMist(m, dt) end

    spawnAccum = spawnAccum + dt  -- Emit particles during active updates only.
    if spawnAccum >= PART_SPAWN_RATE then
        spawnAccum = 0
        local count = (math.random(1, 4) == 1) and 2 or 1
        for _ = 1, count do SpawnParticle(frontX, cy) end
    end
end
