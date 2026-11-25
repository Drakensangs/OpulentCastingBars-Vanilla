-- ============================================================
--  Opulent Casting Bars -- Particles_Chiji.lua
--  Glow, embers and ambient motes.
--  (The frame light is drawn by Bar.lua from the style's frameLight.)
-- ============================================================

local S = {}
local FX = {}
SCB.FX           = SCB.FX or {}
SCB.FX["chiji"]  = FX

local function rand(a, b)  return a + math.random() * (b - a) end
-- Average three uniform samples for center-weighted scatter.
local function gauss(r) return (rand(-r,r) + rand(-r,r) + rand(-r,r)) / 3 end
local function lerp(a, b, t) return a + (b - a) * math.max(0, math.min(t, 1)) end
S.pi2 = math.pi * 2

-- Weighted color choices for each particle category.
S.GOLD_R = 0xF5/255 ; S.GOLD_G = 0xCF/255 ; S.GOLD_B = 0x8A/255
-- Weighted color choices for each particle category.
S.TEAL_R = 0x7F/255 ; S.TEAL_G = 0xF3/255 ; S.TEAL_B = 0xE8/255

-- Glow color, pool, lifetime, and spawn tuning.
S.GLOW_COUNT = 60
S.GLOW_SPAWN_RATE = 0.02
S.GLOW_STOP_AT = 0.87
S.GLOW_ALPHA = 0.55
S.GLOW_SIZE_MIN = 4
S.GLOW_SIZE_MAX = 9
S.GLOW_LIFE_MIN = 0.10
S.GLOW_LIFE_MAX = 0.20

-- Ember pool and spawn timing.
S.EMBER_COUNT = 60
S.EMBER_SPAWN = 0.03

S.emberTypes = {
    { sizeMin=8,  sizeMax=14, speedMin=25, speedMax=60,  lifeMin=0.8, lifeMax=1.6, gravity=8,  spread=140, driftX=0.4 },
    { sizeMin=4,  sizeMax=8,  speedMin=80, speedMax=160, lifeMin=0.3, lifeMax=0.7, gravity=15, spread=80,  driftX=0.0 },
    { sizeMin=6,  sizeMax=12, speedMin=40, speedMax=90,  lifeMin=0.6, lifeMax=1.2, gravity=20, spread=100, driftX=0.2 },
}

-- Holy mote pool, lifetime, opacity, and spread tuning.
S.MISC_FRONT_COUNT = 80
S.MISC_FRONT_SPAWN_RATE = 0.08
S.MISC_FRONT_SIZE_MIN = 4
S.MISC_FRONT_SIZE_MAX = 22
S.MISC_FRONT_LIFE_MIN = 0.4
S.MISC_FRONT_LIFE_MAX = 0.9
S.MISC_FRONT_ALPHA = 0.90
S.MISC_FRONT_STOP_AT = 0.90

S.MISC_AMB_COUNT = 180
S.MISC_AMB_SPAWN_RATE = 0.07
S.MISC_AMB_SIZE_MIN = 3
S.MISC_AMB_SIZE_MAX = 26
S.MISC_AMB_LIFE_MIN = 0.5
S.MISC_AMB_LIFE_MAX = 1.6
S.MISC_AMB_ALPHA_MIN = 0.08
S.MISC_AMB_ALPHA_MAX = 0.72
S.MISC_AMB_SPREAD_X = 12
S.MISC_AMB_SPREAD_Y = 10

-- Residual particles use the shared SCB.FX_LINGER cleanup timer.

-- Cast state, artwork handles, and reusable particle pools.
S.isActive = false
S.partsFading = false
S.partsFadeT = 0
S.castDuration = 5

S.glowParts = {}
S.glowAcc = 0

S.emberParts = {}
S.emberAcc = 0

S.miscFrontParts = {}
S.miscFrontAcc = 0

S.miscAmbParts = {}
S.miscAmbAcc = 0

-- Reuse an idle glow particle near the advancing front.
local function SpawnGlow(frontX, cy, barH, isGold)
    for _, p in ipairs(S.glowParts) do
        if not p.active then
            local spread = math.min(barH * 0.25, 10)
            p.active  = true
            p.life    = 0
            p.maxLife = rand(S.GLOW_LIFE_MIN, S.GLOW_LIFE_MAX)
            p.x       = frontX + rand(-2, 2)
            p.y       = cy + rand(-spread, spread)
            p.vy      = rand(-5, 5)
            p.phase   = math.random() * S.pi2
            local size = rand(S.GLOW_SIZE_MIN, S.GLOW_SIZE_MAX)
            p.tex:SetSize(size, size)
            if isGold then
                p.tex:SetVertexColor(S.GOLD_R, S.GOLD_G, S.GOLD_B)
            else
                p.tex:SetVertexColor(S.TEAL_R, S.TEAL_G, S.TEAL_B)
            end
            p.tex:SetAlpha(0)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            return
        end
    end
end

-- Advance glow motion and its attack, hold, and fade envelope.
local function UpdateGlow(p, dt, gf)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    -- Preserve 60 Hz damping at other update rates.
    p.vy = p.vy * 0.90 ^ (dt * 60)
    p.y  = p.y + p.vy * dt + math.sin(p.life * 10 + p.phase) * 0.3 * (dt * 60)
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local env
    if t < 0.2 then env = t / 0.2
    elseif t < 0.8 then env = 1
    else env = (1 - t) / 0.2 end
    p.tex:SetAlpha(math.max(0, env) * S.GLOW_ALPHA * (gf or 1))
end

-- Choose an ember type and reuse a matching idle particle.
local function SpawnEmber(wx, wy, isGold)
    local roll    = math.random(10)
    local typeIdx = roll <= 4 and 1 or (roll <= 7 and 3 or 2)
    local ptype   = S.emberTypes[typeIdx]

    for _, p in ipairs(S.emberParts) do
        if not p.active and p.typeIdx == typeIdx then
            local tCast = math.max(0, math.min((S.castDuration - 2) / 3, 1))
            local speed = rand(lerp(ptype.speedMax * 0.5, ptype.speedMin, tCast),
                               lerp(ptype.speedMax, ptype.speedMax * 0.8, tCast))
            local angle = math.rad(90 + rand(-ptype.spread * 0.5, ptype.spread * 0.5))
            local size  = rand(ptype.sizeMin, ptype.sizeMax)

            p.active  = true ; p.life = 0
            p.maxLife = rand(ptype.lifeMin, ptype.lifeMax)
            p.x       = wx + rand(-5, 5)
            p.y       = wy + rand(-8, 8)
            p.vx      = math.cos(angle) * speed
            p.vy      = math.sin(angle) * speed
            p.drift   = rand(-ptype.driftX, ptype.driftX) * 30
            if isGold then
                p.tex:SetVertexColor(S.GOLD_R, S.GOLD_G, S.GOLD_B)
            else
                p.tex:SetVertexColor(S.TEAL_R, S.TEAL_G, S.TEAL_B)
            end
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(1)
            return
        end
    end
end

-- Integrate ember motion and fade by particle age.
local function UpdateEmber(p, dt, gf)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    p.vy = p.vy - p.ptype.gravity * dt
    p.vx = p.vx + p.drift * dt * (1 - t)
    p.x  = p.x + p.vx * dt
    p.y  = p.y + p.vy * dt
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local alpha
    if p.typeIdx == 2 then
        alpha = t < 0.15 and 1 or math.max(0, 1 - (t - 0.15) / 0.85)
    else
        alpha = t < 0.5 and 1 or math.max(0, (1 - t) / 0.5)
    end
    p.tex:SetAlpha(alpha * 0.85 * (gf or 1))
end

-- Reuse an idle mote near the advancing front.
local function SpawnMiscFront(frontX, cy, barH, i)
    for idx, p in ipairs(S.miscFrontParts) do
        if not p.active then
            local spread = math.min(barH * 0.15, 6)
            p.active  = true ; p.life = 0
            p.maxLife = rand(S.MISC_FRONT_LIFE_MIN, S.MISC_FRONT_LIFE_MAX)
            p.x       = frontX + rand(-4, 6)
            p.y       = cy + rand(-spread, spread)
            p.vx      = rand(-10, 10)
            p.vy      = rand(-18, 4)
            p.phase   = math.random() * S.pi2
            local sz  = rand(S.MISC_FRONT_SIZE_MIN, S.MISC_FRONT_SIZE_MAX)
            p.tex:SetSize(sz, sz)
            if idx % 2 == 0 then
                p.tex:SetVertexColor(S.GOLD_R, S.GOLD_G, S.GOLD_B)
            else
                p.tex:SetVertexColor(S.TEAL_R, S.TEAL_G, S.TEAL_B)
            end
            p.tex:SetAlpha(0)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            return
        end
    end
end

-- Advance front motes and their opacity envelope.
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

-- Scatter a drifting mote around the fill region.
local function SpawnMiscAmb(cx, cy, barW, barH, idx)
    for i, p in ipairs(S.miscAmbParts) do
        if not p.active then
            p.active  = true ; p.life = 0
            p.maxLife = rand(S.MISC_AMB_LIFE_MIN, S.MISC_AMB_LIFE_MAX)

            p.x     = cx + gauss(barW * 0.5 + S.MISC_AMB_SPREAD_X)
            p.y     = cy + gauss(barH * 0.5 + S.MISC_AMB_SPREAD_Y)
            p.vx    = rand(-6, 6)
            p.vy    = rand(-4, 8)
            p.phase = math.random() * S.pi2
            local sz = rand(S.MISC_AMB_SIZE_MIN, S.MISC_AMB_SIZE_MAX)
            p.tex:SetSize(sz, sz)

            p.maxAlpha = rand(S.MISC_AMB_ALPHA_MIN, S.MISC_AMB_ALPHA_MAX)
            if i % 2 == 0 then
                p.tex:SetVertexColor(S.GOLD_R, S.GOLD_G, S.GOLD_B)
            else
                p.tex:SetVertexColor(S.TEAL_R, S.TEAL_G, S.TEAL_B)
            end
            p.tex:SetAlpha(0)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            return
        end
    end
end

-- Advance ambient drift and fade by particle age.
local function UpdateMiscAmb(p, dt, gf)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    p.x = p.x + p.vx * dt + math.sin(p.life * 2 + p.phase) * 0.3 * (dt * 60)
    p.y = p.y + p.vy * dt
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local env = t < 0.25 and t/0.25 or (t < 0.65 and 1 or (1-t)/0.35)
    p.tex:SetAlpha(math.max(0, env) * (p.maxAlpha or S.MISC_AMB_ALPHA_MAX) * (gf or 1))
end

-- Create artwork layers and reusable particle pools.
function FX.Init(container, bar)

    local glowTex = SCB.TEX_PATH .. "frost\\Particle_Frost_01"
    S.glowParts = {}
    for i = 1, S.GLOW_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(glowTex)
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)
        S.glowParts[i] = { tex=tex, active=false, life=0, maxLife=0, x=0, y=0, vy=0, phase=0 }
    end

    local earthSchool = SCB.Schools.data["earth"]
    local miscTexs    = {}
    if earthSchool then
        for _, t in ipairs(earthSchool.rocks  or {}) do miscTexs[#miscTexs+1] = t end
        for _, t in ipairs(earthSchool.debris or {}) do miscTexs[#miscTexs+1] = t end
    end
    local function getEmberTex(i)
        if #miscTexs == 0 then return glowTex end
        return miscTexs[((i-1) % #miscTexs) + 1]
    end

    S.emberParts = {}
    for i = 1, S.EMBER_COUNT do
        local typeIdx = ((i - 1) % 3) + 1
        local ptype   = S.emberTypes[typeIdx]
        local tex     = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(getEmberTex(i))
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)
        S.emberParts[i] = {
            tex=tex, ptype=ptype, typeIdx=typeIdx,
            active=false, life=0, maxLife=0,
            x=0, y=0, vx=0, vy=0, drift=0,
        }
    end

    local holySchool = SCB.Schools.data["holy"]
    local holyMisc   = (holySchool and holySchool.misc) or {}
    local nMisc      = #holyMisc
    local function getMiscTex(i)
        if nMisc == 0 then return glowTex end
        return holyMisc[((i-1) % nMisc) + 1]
    end

    S.miscFrontParts = {}
    for i = 1, S.MISC_FRONT_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(getMiscTex(i))
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)
        S.miscFrontParts[i] = { tex=tex, active=false, life=0, maxLife=0, x=0, y=0, vx=0, vy=0, phase=0 }
    end

    S.miscAmbParts = {}
    for i = 1, S.MISC_AMB_COUNT do
        local tex = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
        tex:SetTexture(getMiscTex(i + S.MISC_FRONT_COUNT))
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)
        S.miscAmbParts[i] = { tex=tex, active=false, life=0, maxLife=0, x=0, y=0, vx=0, vy=0, phase=0, maxAlpha=0 }
    end
end

-- Begin a cast and clear particles from the previous cast.
function FX.Start(duration)
    S.castDuration  = duration or 5
    S.isActive      = true
    S.partsFading   = false
    S.partsFadeT    = 0
    S.glowAcc       = 0
    S.emberAcc      = 0
    S.miscFrontAcc  = 0
    S.miscAmbAcc    = 0

    for _, p in ipairs(S.glowParts)      do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.emberParts)     do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.miscFrontParts) do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.miscAmbParts)   do p.active = false ; p.tex:SetAlpha(0) end
end

-- Stop spawning and begin the residual fade.
function FX.Stop()
    S.isActive    = false
    S.partsFading = true
    S.partsFadeT  = 0
    S.glowAcc     = 0
    S.emberAcc    = 0
    S.miscFrontAcc = 0
    S.miscAmbAcc   = 0
end

-- Hide artwork and clear all active particles.
function FX.Reset()
    S.isActive    = false
    S.partsFading = false
    S.partsFadeT  = 0
    S.glowAcc     = 0
    S.emberAcc    = 0
    S.miscFrontAcc = 0
    S.miscAmbAcc   = 0

    for _, p in ipairs(S.glowParts)      do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.emberParts)     do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.miscFrontParts) do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.miscAmbParts)   do p.active = false ; p.tex:SetAlpha(0) end
end

-- Advance residual particles and artwork during the stop fade.
function FX.UpdateFade(dt)
    if not S.partsFading then return end
    S.partsFadeT = S.partsFadeT + dt
    local gf   = 1

    for _, p in ipairs(S.glowParts)      do UpdateGlow(p,       dt, gf) end
    for _, p in ipairs(S.emberParts)     do UpdateEmber(p,      dt, gf) end
    for _, p in ipairs(S.miscFrontParts) do UpdateMiscFront(p,  dt, gf) end
    for _, p in ipairs(S.miscAmbParts)   do UpdateMiscAmb(p,    dt, gf) end

    if S.partsFadeT >= SCB.FX_LINGER then
        S.partsFading = false
        for _, p in ipairs(S.glowParts)      do p.active = false ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.emberParts)     do p.active = false ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.miscFrontParts) do p.active = false ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.miscAmbParts)   do p.active = false ; p.tex:SetAlpha(0) end
    end
end

-- Update artwork reveal and particles from cast geometry.
function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)

    for _, p in ipairs(S.glowParts)      do UpdateGlow(p,       dt, 1) end
    for _, p in ipairs(S.emberParts)     do UpdateEmber(p,      dt, 1) end
    for _, p in ipairs(S.miscFrontParts) do UpdateMiscFront(p,  dt, 1) end
    for _, p in ipairs(S.miscAmbParts)   do UpdateMiscAmb(p,    dt, 1) end

    if not S.isActive then return end

    local cx = (fillLX or (frontX - barW * progress)) + (fillW or barW) * 0.5

    S.glowAcc = S.glowAcc + dt
    if SCB.Particles.emitProgress < S.GLOW_STOP_AT and S.glowAcc >= S.GLOW_SPAWN_RATE then
        S.glowAcc = 0
        local count = math.random(2, 4)
        for i = 1, count do
            SpawnGlow(frontX, cy, barH, (math.random(2) == 1))
        end
    end

    S.emberAcc = S.emberAcc + dt
    if S.emberAcc >= S.EMBER_SPAWN then
        S.emberAcc = 0
        local count = math.random(2, 4)
        for i = 1, count do
            SpawnEmber(frontX, cy, (math.random(2) == 1))
        end
    end

    S.miscFrontAcc = S.miscFrontAcc + dt
    if SCB.Particles.emitProgress < S.MISC_FRONT_STOP_AT and S.miscFrontAcc >= S.MISC_FRONT_SPAWN_RATE then
        S.miscFrontAcc = 0
        for _ = 1, 2 do SpawnMiscFront(frontX, cy, barH) end
    end

    S.miscAmbAcc = S.miscAmbAcc + dt
    if S.miscAmbAcc >= S.MISC_AMB_SPAWN_RATE then
        S.miscAmbAcc = 0
        for _ = 1, 3 do SpawnMiscAmb(cx, cy, barW, barH) end
    end
end
