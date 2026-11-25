-- ============================================================
--  Opulent Casting Bars - Particles_Moon.lua
--  Masked moonlight follows progress with cyan front and ambient particles.
-- ============================================================

local S = {}  -- Group style settings and runtime state to limit local upvalues.
local FX = {}
SCB.FX         = SCB.FX or {}
SCB.FX["moon"] = FX

local function rand(a, b) return a + math.random() * (b - a) end
local function gauss(r) return (rand(-r,r) + rand(-r,r) + rand(-r,r)) / 3 end
S.pi2 = math.pi * 2

-- Particle pool sizes, lifetimes, and emission intervals.

-- Bright cyan tint.
S.MOON_R = 0.0 ; S.MOON_G = 0.90 ; S.MOON_B = 1.0

-- Debris emitted at the moving front.
S.MISC_FRONT_COUNT = 80
S.MISC_FRONT_SPAWN_RATE = 0.08
S.MISC_FRONT_SIZE_MIN = 4
S.MISC_FRONT_SIZE_MAX = 22
S.MISC_FRONT_LIFE_MIN = 0.4
S.MISC_FRONT_LIFE_MAX = 0.9
S.MISC_FRONT_ALPHA = 0.90
S.MISC_FRONT_STOP_AT = 0.90

-- Ambient motes distributed around the bar.
S.MISC_AMB_COUNT = 120
S.MISC_AMB_SPAWN_RATE = 0.12
S.MISC_AMB_SIZE_MIN = 3
S.MISC_AMB_SIZE_MAX = 20
S.MISC_AMB_LIFE_MIN = 0.6
S.MISC_AMB_LIFE_MAX = 1.4
S.MISC_AMB_ALPHA = 0.65
S.MISC_AMB_SPREAD_X = 5
S.MISC_AMB_SPREAD_Y = 5

-- Fine glow particles at the front.
S.GLOW_COUNT = 50
S.GLOW_SPAWN_RATE = 0.02
S.GLOW_STOP_AT = 0.87
S.GLOW_ALPHA = 0.65
S.GLOW_SIZE_MIN = 4
S.GLOW_SIZE_MAX = 10
S.GLOW_LIFE_MIN = 0.25
S.GLOW_LIFE_MAX = 0.50

-- Fade state, emission accumulators, and texture pools.

S.isActive = false
S.isFading = false
S.fadeT = 0
S.miscFrontAcc = 0
S.miscAmbAcc = 0
S.glowSpawnAcc = 0

S.miscFrontParts = {}
S.miscAmbParts = {}
S.glowParts = {}

-- Front debris spawning and motion.

local function SpawnMiscFront(frontX, cy, barH)
    for _, p in ipairs(S.miscFrontParts) do
        if not p.active then
            local spread = math.min(barH * 0.15, 6)
            p.active  = true ; p.life = 0
            p.maxLife = rand(S.MISC_FRONT_LIFE_MIN, S.MISC_FRONT_LIFE_MAX)
            p.x  = frontX + rand(-4, 6)
            p.y  = cy + rand(-spread, spread)
            p.vx = rand(-10, 10)
            p.vy = rand(-18, 4)
            p.phase = math.random() * S.pi2
            local sz = rand(S.MISC_FRONT_SIZE_MIN, S.MISC_FRONT_SIZE_MAX)
            p.tex:SetSize(sz, sz)
            p.tex:SetAlpha(0)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            return
        end
    end
end

local function UpdateMiscFront(p, dt, gf)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    p.vy = p.vy - 8 * dt
    p.x  = p.x + p.vx * dt + math.sin(p.life * 4 + p.phase) * 0.4 * (dt * 60)
    p.y  = p.y + p.vy * dt
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local env = t < 0.2 and t/0.2 or (t < 0.7 and 1 or (1-t)/0.3)
    p.tex:SetAlpha(math.max(0, env) * S.MISC_FRONT_ALPHA * (gf or 1))
end

-- Center-weighted ambient spawning and drift.

local function SpawnMiscAmb(cx, cy, barW, barH)
    for _, p in ipairs(S.miscAmbParts) do
        if not p.active then
            p.active  = true ; p.life = 0
            p.maxLife = rand(S.MISC_AMB_LIFE_MIN, S.MISC_AMB_LIFE_MAX)
            p.x  = cx + gauss(barW * 0.5 + S.MISC_AMB_SPREAD_X)
            p.y  = cy + gauss(barH * 0.5 + S.MISC_AMB_SPREAD_Y)
            p.vx = rand(-6, 6)
            p.vy = rand(-4, 8)
            p.phase = math.random() * S.pi2
            local sz = rand(S.MISC_AMB_SIZE_MIN, S.MISC_AMB_SIZE_MAX)
            p.tex:SetSize(sz, sz)
            p.tex:SetAlpha(0)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            return
        end
    end
end

local function UpdateMiscAmb(p, dt, gf)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    p.x = p.x + p.vx * dt + math.sin(p.life * 2 + p.phase) * 0.3 * (dt * 60)
    p.y = p.y + p.vy * dt
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local env = t < 0.25 and t/0.25 or (t < 0.65 and 1 or (1-t)/0.35)
    p.tex:SetAlpha(math.max(0, env) * S.MISC_AMB_ALPHA * (gf or 1))
end

-- Short-lived front glow with vertical damping.

local function SpawnGlow(frontX, cy, barH)
    for _, p in ipairs(S.glowParts) do
        if not p.active then
            local spread = math.min(barH * 0.28, 12)
            p.active  = true ; p.life = 0
            p.maxLife = rand(S.GLOW_LIFE_MIN, S.GLOW_LIFE_MAX)
            p.x = frontX + rand(-2, 4)
            p.y = cy + rand(-spread, spread)
            p.vy = rand(-8, 8)
            p.phase = math.random() * S.pi2
            p.tex:SetSize(rand(S.GLOW_SIZE_MIN, S.GLOW_SIZE_MAX), rand(S.GLOW_SIZE_MIN, S.GLOW_SIZE_MAX))
            p.tex:SetAlpha(0)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            return
        end
    end
end

local function UpdateGlow(p, dt, gf)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    p.vy = p.vy * 0.88 ^ (dt * 60)
    p.y  = p.y + p.vy * dt + math.sin(p.life * 10 + p.phase) * 0.4 * (dt * 60)
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local env = t < 0.2 and t/0.2 or (t < 0.75 and 1 or (1-t)/0.25)
    p.tex:SetAlpha(math.max(0, env) * S.GLOW_ALPHA * (gf or 1))
end

-- Style lifecycle and progress reveal.

function FX.Init(container, bar)
    local school = SCB.Schools.data["moon"]
    if not school then return end
    local f = SCB.Bar.frameInner
    if not f then return end

    -- Tint holy debris textures cyan.
    local miscTexs = school.misc or {}
    local nMisc = #miscTexs

    S.miscFrontParts = {}
    for i = 1, S.MISC_FRONT_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        if nMisc > 0 then tex:SetTexture(miscTexs[((i-1) % nMisc) + 1]) end
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.MOON_R, S.MOON_G, S.MOON_B)
        tex:SetAlpha(0)
        S.miscFrontParts[i] = { tex=tex, active=false, life=0, maxLife=0, x=0, y=0, vx=0, vy=0, phase=0 }
    end

    S.miscAmbParts = {}
    for i = 1, S.MISC_AMB_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        if nMisc > 0 then tex:SetTexture(miscTexs[((i-1) % nMisc) + 1]) end
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.MOON_R, S.MOON_G, S.MOON_B)
        tex:SetAlpha(0)
        S.miscAmbParts[i] = { tex=tex, active=false, life=0, maxLife=0, x=0, y=0, vx=0, vy=0, phase=0 }
    end

    -- Tint the frost particle texture cyan.
    local glowTex = SCB.TEX_PATH .. "frost\\Particle_Frost_01"
    S.glowParts = {}
    for i = 1, S.GLOW_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(glowTex)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.MOON_R, S.MOON_G, S.MOON_B)
        tex:SetAlpha(0)
        S.glowParts[i] = { tex=tex, active=false, life=0, maxLife=0, x=0, y=0, vy=0, phase=0 }
    end
end

function FX.Start(duration)
    S.isActive=true ; S.isFading=false ; S.fadeT=0
    S.miscFrontAcc=0 ; S.miscAmbAcc=0 ; S.glowSpawnAcc=0
    for _, p in ipairs(S.miscFrontParts) do p.active=false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.miscAmbParts)   do p.active=false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.glowParts)      do p.active=false ; p.tex:SetAlpha(0) end
end

function FX.Stop()
    S.isActive=false ; S.isFading=true ; S.fadeT=0
end

function FX.UpdateFade(dt)
    if not S.isFading then return end
    S.fadeT = S.fadeT + dt
    local gf = 1
    for _, p in ipairs(S.miscFrontParts) do UpdateMiscFront(p, dt, gf) end
    for _, p in ipairs(S.miscAmbParts)   do UpdateMiscAmb(p,   dt, gf) end
    for _, p in ipairs(S.glowParts)      do UpdateGlow(p,      dt, gf) end
    if S.fadeT >= SCB.FX_LINGER then
        S.isFading = false
        for _, p in ipairs(S.miscFrontParts) do p.active=false ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.miscAmbParts)   do p.active=false ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.glowParts)      do p.active=false ; p.tex:SetAlpha(0) end
    end
end

function FX.Reset()
    S.isActive=false ; S.isFading=false
    for _, p in ipairs(S.miscFrontParts) do p.active=false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.miscAmbParts)   do p.active=false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.glowParts)      do p.active=false ; p.tex:SetAlpha(0) end
end

function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    if not S.isActive then return end

    -- Emit front debris.
    for _, p in ipairs(S.miscFrontParts) do UpdateMiscFront(p, dt, 1) end
    if SCB.Particles.emitProgress < S.MISC_FRONT_STOP_AT then
        S.miscFrontAcc = S.miscFrontAcc + dt
        if S.miscFrontAcc >= S.MISC_FRONT_SPAWN_RATE then
            S.miscFrontAcc = 0
            for _ = 1, 2 do SpawnMiscFront(frontX, cy, barH) end
        end
    end

    -- Emit ambient motes.
    for _, p in ipairs(S.miscAmbParts) do UpdateMiscAmb(p, dt, 1) end
    S.miscAmbAcc = S.miscAmbAcc + dt
    if S.miscAmbAcc >= S.MISC_AMB_SPAWN_RATE then
        S.miscAmbAcc = 0
        local cx = fillLX + fillW * 0.5
        for _ = 1, 3 do SpawnMiscAmb(cx, cy, barW, barH) end
    end

    -- Emit front glow.
    for _, p in ipairs(S.glowParts) do UpdateGlow(p, dt, 1) end
    if SCB.Particles.emitProgress < S.GLOW_STOP_AT then
        S.glowSpawnAcc = S.glowSpawnAcc + dt
        if S.glowSpawnAcc >= S.GLOW_SPAWN_RATE then
            S.glowSpawnAcc = 0
            for _ = 1, math.random(2, 4) do SpawnGlow(frontX, cy, barH) end
        end
    end
end
