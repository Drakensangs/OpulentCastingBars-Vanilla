-- ============================================================
--  Opulent Casting Bars -- Particles_Thunder.lua
--  Progress-revealed light, lightning flashes, and blue front motes.
-- ============================================================

-- Effect tuning: counts, timing, geometry, and colors.
local FX = {}
SCB.FX            = SCB.FX or {}
SCB.FX["thunder"] = FX

-- Sample a uniform value within the given range.
local function rand(a, b) return a + math.random() * (b - a) end
local pi2 = math.pi * 2

local LIGHTNING_COUNT       = 3
local LIGHTNING_HOLD_MIN    = 0.04
local LIGHTNING_HOLD_MAX    = 0.10
local LIGHTNING_FADE_MIN    = 0.15
local LIGHTNING_FADE_MAX    = 0.35
local LIGHTNING_PAUSE_MIN   = 0.20
local LIGHTNING_PAUSE_MAX   = 0.80
local LIGHTNING_ALPHA       = 0.95

local GLOW_COUNT            = 50
local GLOW_SPAWN_RATE       = 0.025
local GLOW_STOP_AT          = 0.90
local GLOW_ALPHA            = 0.65
local GLOW_SIZE_MIN         = 5
local GLOW_SIZE_MAX         = 14
local GLOW_LIFE_MIN         = 0.15
local GLOW_LIFE_MAX         = 0.30
local GLOW_R, GLOW_G, GLOW_B = 0.6, 0.85, 1.0

-- Particle pools and cast lifecycle state.
local isActive      = false
local isFading      = false
local fadeT         = 0
local glowSpawnAcc  = 0

local lightnings    = {}
local glowParts     = {}

-- Activate an available glow particle and initialize its motion.
local function SpawnGlow(frontX, cy, barH)
    for _, p in ipairs(glowParts) do
        if not p.active then
            local spread = math.min(barH * 0.30, 14)
            p.active=true ; p.life=0
            p.maxLife = rand(GLOW_LIFE_MIN, GLOW_LIFE_MAX)
            p.x = frontX + rand(-4, 4)
            p.y = cy + rand(-spread, spread)
            p.vy = rand(-8, 12)
            p.phase = math.random() * pi2
            p.tex:SetSize(rand(GLOW_SIZE_MIN, GLOW_SIZE_MAX), rand(GLOW_SIZE_MIN, GLOW_SIZE_MAX))
            p.tex:SetAlpha(0)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            return
        end
    end
end

-- Advance particle motion and its lifetime opacity envelope.
local function UpdateGlow(p, dt)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active=false ; p.tex:SetAlpha(0) ; return end
    p.vy = p.vy * (0.88 ^ (dt * 60))
    p.y  = p.y + p.vy * dt + math.sin(p.life * 12 + p.phase) * 0.4 * (dt * 60)
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local env = t < 0.15 and t/0.15 or (t < 0.75 and 1 or (1-t)/0.25)
    p.tex:SetAlpha(math.max(0, env) * GLOW_ALPHA)
end

-- Initialize a lightning flash and its pause timer.
local function ResetLightning(ln, fillLX, fillW, progress, cy, barH)

    ln.phase     = "pause"
    ln.phaseT    = 0
    ln.pauseDur  = rand(LIGHTNING_PAUSE_MIN, LIGHTNING_PAUSE_MAX)
    ln.tex:SetAlpha(0)
end

-- Advance pause, hold, and fade phases of a lightning flash.
local function UpdateLightning(ln, dt, fillLX, fillW, progress, cy, barH, gf)
    ln.phaseT = ln.phaseT + dt

    if ln.phase == "pause" then
        if ln.phaseT >= ln.pauseDur then

            ln.phase    = "hold"
            ln.phaseT   = 0
            ln.holdDur  = rand(LIGHTNING_HOLD_MIN, LIGHTNING_HOLD_MAX)
            ln.fadeDur  = rand(LIGHTNING_FADE_MIN, LIGHTNING_FADE_MAX)

            ln.tex:SetAlpha(LIGHTNING_ALPHA * (gf or 1))
        end

    elseif ln.phase == "hold" then
        if ln.phaseT >= ln.holdDur then
            ln.phase  = "fade"
            ln.phaseT = 0
        end

    elseif ln.phase == "fade" then
        local t = math.min(ln.phaseT / ln.fadeDur, 1)
        ln.tex:SetAlpha((1-t) * LIGHTNING_ALPHA * (gf or 1))
        if t >= 1 then
            ln.tex:SetAlpha(0)
            ResetLightning(ln, fillLX, fillW, progress, cy, barH)
        end
    end
end

-- Create textures and initialize the particle pools.
function FX.Init(container, bar)
    local school = SCB.Schools.data["thunder"]
    if not school then return end

    local f = SCB.Bar.frameInner

    -- The bar light comes from the style's frameLight (Bar.lua).
    local ltnTexs = school.lightnings or {}
    lightnings = {}
    for i = 1, LIGHTNING_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY", nil, 7)
        if ltnTexs[i] then tex:SetTexture(ltnTexs[i]) end
        tex:SetBlendMode("ADD")
        tex:SetAllPoints(f)
        SCB.AttachMask(tex, SCB.Bar.texMask)
        tex:SetAlpha(0)
        lightnings[i] = {
            tex=tex, phase="pause", phaseT=0,
            pauseDur=0, holdDur=0, fadeDur=0,
            cx=0, cy=0,
        }
    end

    glowParts = {}
    local glowTex = SCB.TEX_PATH .. "frost\\Particle_Frost_01"
    for i = 1, GLOW_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(glowTex)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(GLOW_R, GLOW_G, GLOW_B)
        tex:SetAlpha(0)
        glowParts[i] = { tex=tex, active=false, life=0, maxLife=0, x=0, y=0, vy=0, phase=0 }
    end
end

-- Begin a cast and reset existing particles.
function FX.Start(duration)
    isActive=true ; isFading=false ; fadeT=0 ; glowSpawnAcc=0

    for _, p  in ipairs(glowParts)  do p.active=false ; p.tex:SetAlpha(0) end

    for i, ln in ipairs(lightnings) do
        ln.phase    = "pause"
        ln.phaseT   = 0
        ln.pauseDur = rand(0, LIGHTNING_PAUSE_MAX) * (i / LIGHTNING_COUNT)
        ln.tex:SetAlpha(0)
    end
end

-- End emission and begin effect cleanup.
function FX.Stop()
    isActive=false ; isFading=true ; fadeT=0
    for _, ln in ipairs(lightnings) do ln.tex:SetAlpha(0) end
end

-- Advance existing effects during fade-out without emitting particles.
function FX.UpdateFade(dt)
    if not isFading then return end
    fadeT = fadeT + dt
    for _, p  in ipairs(glowParts)  do UpdateGlow(p, dt) end
    if fadeT >= SCB.FX_LINGER then
        isFading = false
        for _, p in ipairs(glowParts) do p.active=false ; p.tex:SetAlpha(0) end
    end
end

-- Hide effect textures and clear particle activity.
function FX.Reset()
    isActive=false ; isFading=false
    for _, ln in ipairs(lightnings) do ln.tex:SetAlpha(0) end
    for _, p  in ipairs(glowParts)  do p.active=false ; p.tex:SetAlpha(0) end
end

-- Advance the active cast effect and emit new particles.
function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    if not isActive then return end

    for _, ln in ipairs(lightnings) do
        UpdateLightning(ln, dt, fillLX, fillW, progress, cy, barH, 1)
    end

    for _, p in ipairs(glowParts) do UpdateGlow(p, dt) end
    if SCB.Particles.emitProgress < GLOW_STOP_AT then
        glowSpawnAcc = glowSpawnAcc + dt
        if glowSpawnAcc >= GLOW_SPAWN_RATE then
            glowSpawnAcc = 0
            for _ = 1, math.random(2, 4) do SpawnGlow(frontX, cy, barH) end
        end
    end
end
