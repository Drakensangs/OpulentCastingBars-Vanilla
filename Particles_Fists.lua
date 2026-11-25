-- ============================================================
--  Opulent Casting Bars -- Particles_Fists.lua
--  Cyan glow and embers, mirrored fists and pink leaves.
--  (The frame light is drawn by Bar.lua from the style's frameLight.)
-- ============================================================

local S = {}
local FX = {}
SCB.FX          = SCB.FX or {}
SCB.FX["fists"] = FX

local function rand(a, b) return a + math.random() * (b - a) end
local function rad(deg)   return deg * math.pi / 180 end
local function lerp(a, b, t) return a + (b - a) * math.max(0, math.min(t, 1)) end
S.pi2 = math.pi * 2

-- Glow color, pool, lifetime, and spawn tuning.
S.GLOW_R = 103/255 ; S.GLOW_G = 205/255 ; S.GLOW_B = 230/255

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

-- Fist pool, size, lifetime, and spawn tuning.
S.FIST_COUNT = 80
S.FIST_SPAWN_RATE = 0.07
S.FIST_SIZE_MIN = 55
S.FIST_SIZE_MAX = 125
S.FIST_ALPHA = 0.90
S.FIST_LIFE_MIN = 0.30
S.FIST_LIFE_MAX = 0.65
S.FIST_STOP_AT = 0.95

-- Leaf pool, drift, rotation, and wave tuning.
S.LEAF_COUNT = 17
S.LEAF_SPAWN_RATE = 0.12
S.LEAF_SIZE_MIN = 10
S.LEAF_SIZE_MAX = 22
S.LEAF_ALPHA_MIN = 0.55
S.LEAF_ALPHA_MAX = 0.90
S.LEAF_ROT_MIN = 0.8
S.LEAF_ROT_MAX = 2.8
S.LEAF_WAVE_AMP_MIN = 3
S.LEAF_WAVE_AMP_MAX = 9
S.LEAF_WAVE_FREQ_MIN = 1.2
S.LEAF_WAVE_FREQ_MAX = 2.8
S.LEAF_VY_MIN = -4
S.LEAF_VY_MAX = 4
S.LEAF_SPEED_MIN = 55
S.LEAF_SPEED_MAX = 120

-- Residual particles use the shared SCB.FX_LINGER cleanup timer.

-- Cast state, artwork handles, and reusable particle pools.
S.isActive = false
S.isFading = false
S.fadeT = 0
S.castDuration = 5

S.glowParts = {}
S.glowSpawnAcc = 0

S.emberParts = {}
S.emberSpawnAcc = 0

S.fistParts = {}
S.fistSpawnAcc = 0

S.leafParts = {}
S.leafSpawnAcc = 0

-- Reuse an idle glow particle near the advancing front.
local function SpawnGlow(frontX, cy, barH)
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
            p.tex:SetAlpha(0)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            return
        end
    end
end

-- Advance glow motion and its attack, hold, and fade envelope.
local function UpdateGlow(p, dt, globalFade)
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
    p.tex:SetAlpha(math.max(0, env) * S.GLOW_ALPHA * (globalFade or 1))
end

-- Choose an ember type and reuse a matching idle particle.
local function SpawnEmber(wx, wy)
    local roll = math.random(10)
    local typeIdx = roll <= 4 and 1 or (roll <= 7 and 3 or 2)
    local ptype = S.emberTypes[typeIdx]

    for _, p in ipairs(S.emberParts) do
        if not p.active and p.typeIdx == typeIdx then
            local tCast = math.max(0, math.min((S.castDuration - 2) / 3, 1))
            local speed = rand(lerp(ptype.speedMax * 0.5, ptype.speedMin, tCast),
                               lerp(ptype.speedMax, ptype.speedMax * 0.8, tCast))
            local angle = rad(90 + rand(-ptype.spread * 0.5, ptype.spread * 0.5))
            local size  = rand(ptype.sizeMin, ptype.sizeMax)
            p.active  = true ; p.life = 0
            p.maxLife = rand(ptype.lifeMin, ptype.lifeMax)
            p.x       = wx + rand(-5, 5)
            p.y       = wy + rand(-8, 8)
            p.vx      = math.cos(angle) * speed
            p.vy      = math.sin(angle) * speed
            p.drift   = rand(-ptype.driftX, ptype.driftX) * 30
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(1)
            return
        end
    end
end

-- Integrate ember motion and fade by particle age.
local function UpdateEmber(p, dt, globalFade)
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
    p.tex:SetAlpha(alpha * 0.85 * (globalFade or 1))
end

-- Mirror the lower fists vertically.
local function SetFistUV(tex, isTop)
    if isTop then

        tex:SetTexCoord(0, 1, 0, 1)
    else

        tex:SetTexCoord(0, 1, 1, 0)
    end
end

-- Launch a fist to the right, above or below the bar center.
local function SpawnFist(frontX, cy, barH)
    for _, p in ipairs(S.fistParts) do
        if not p.active then
            local isTop = math.random(2) == 1
            local side  = isTop and 1 or -1
            local sz    = rand(S.FIST_SIZE_MIN, S.FIST_SIZE_MAX)

            local spawnX = frontX + rand(-35, 10)

            local extraUp = isTop and 0 or 15
            local spawnY  = cy + side * math.max(4, barH * 0.5 + rand(4, 12) - 60 - extraUp)

            local speed = rand(45, 95)
            local vx    = speed * rand(0.7, 1.0)
            local vy    = side * speed * rand(0.4, 0.7)

            p.active  = true
            p.life    = 0
            p.maxLife = rand(S.FIST_LIFE_MIN, S.FIST_LIFE_MAX)
            p.x       = spawnX
            p.y       = spawnY
            p.vx      = vx
            p.vy      = vy
            p.isTop   = isTop
            p.tex:SetSize(sz, sz)
            p.tex:SetAlpha(0)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            SetFistUV(p.tex, isTop)
            return
        end
    end
end

-- Advance and decelerate a fist while fading its impact.
local function UpdateFist(p, dt, gf)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    p.x  = p.x + p.vx * dt
    p.y  = p.y + p.vy * dt

    p.vx = p.vx * (1 - dt * 2.0)
    p.vy = p.vy * (1 - dt * 2.0)
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)

    local env = t < 0.12 and (t / 0.12) or math.max(0, (1 - t) / 0.88)
    p.tex:SetAlpha(env * S.FIST_ALPHA * (gf or 1))
end

-- Start a rotating leaf to the left of the bar.
local function SpawnLeaf(barLX, barRX, barCY, barH)
    for _, lf in ipairs(S.leafParts) do
        if not lf.active then
            local size     = rand(S.LEAF_SIZE_MIN, S.LEAF_SIZE_MAX)
            local speed    = rand(S.LEAF_SPEED_MIN, S.LEAF_SPEED_MAX)
            local waveAmp  = rand(S.LEAF_WAVE_AMP_MIN, S.LEAF_WAVE_AMP_MAX)
            local waveFreq = rand(S.LEAF_WAVE_FREQ_MIN, S.LEAF_WAVE_FREQ_MAX)
            local vy       = rand(S.LEAF_VY_MIN, S.LEAF_VY_MAX)
            local rotSpeed = rand(S.LEAF_ROT_MIN, S.LEAF_ROT_MAX)
                             * (math.random(2) == 1 and 1 or -1)
            local startY   = barCY + rand(-barH * 0.2, barH * 0.2)
            lf.active    = true
            lf.x         = barLX - size
            lf.y         = startY
            lf.baseY     = startY
            lf.vx        = speed
            lf.vy        = vy
            lf.waveAmp   = waveAmp
            lf.waveFreq  = waveFreq
            lf.wavePhase = rand(0, S.pi2)
            lf.rot       = rand(0, S.pi2)
            lf.rotSpeed  = rotSpeed
            lf.life      = 0
            lf.maxAlpha  = rand(S.LEAF_ALPHA_MIN, S.LEAF_ALPHA_MAX)
            lf.size      = size
            lf.deadX     = barRX + size * 2
            lf.tex:SetSize(size, size)
            lf.tex:SetAlpha(0)
            lf.tex:ClearAllPoints()
            lf.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", lf.x, lf.y)
            return
        end
    end
end

-- Move a leaf across the bar with a time-based wave.
local function UpdateLeaf(lf, dt, globalFade)
    if not lf.active then return end
    lf.life = lf.life + dt
    lf.x    = lf.x + lf.vx * dt
    lf.y    = lf.baseY
              + math.sin(lf.life * lf.waveFreq + lf.wavePhase) * lf.waveAmp
              + lf.vy * lf.life
    lf.rot  = lf.rot + lf.rotSpeed * dt
    local fadeIn = math.min(lf.life / 0.5, 1)
    local alpha
    if lf.x > lf.deadX - 40 then
        local t = math.max(0, 1 - (lf.deadX - lf.x) / 40)
        alpha = lf.maxAlpha * fadeIn * (1 - t)
    else
        alpha = lf.maxAlpha * fadeIn
    end
    alpha = alpha * (globalFade or 1)
    if lf.x >= lf.deadX then
        lf.active = false ; lf.tex:SetAlpha(0) ; return
    end
    lf.tex:SetAlpha(alpha)
    lf.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", lf.x, lf.y)
    lf.tex:SetRotation(lf.rot)
end

-- Create artwork layers and reusable particle pools.
function FX.Init(container, bar)
    local school = SCB.Schools.data["fists"]
    if not school then return end
    local f = SCB.Bar.frameInner
    if not f then return end

    local glowTex = SCB.TEX_PATH .. "frost\\Particle_Frost_01"
    S.glowParts = {}
    for i = 1, S.GLOW_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(glowTex)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.GLOW_R, S.GLOW_G, S.GLOW_B)
        tex:SetAlpha(0)
        S.glowParts[i] = { tex=tex, active=false, life=0, maxLife=0, x=0, y=0, vy=0, phase=0 }
    end

    local earthSchool = SCB.Schools.data["earth"]
    local miscTexs = {}
    if earthSchool then
        for _, t in ipairs(earthSchool.rocks  or {}) do miscTexs[#miscTexs+1] = t end
        for _, t in ipairs(earthSchool.debris or {}) do miscTexs[#miscTexs+1] = t end
    end
    local function getMisc(i)
        if #miscTexs == 0 then return glowTex end
        return miscTexs[((i-1) % #miscTexs) + 1]
    end

    S.emberParts = {}
    for i = 1, S.EMBER_COUNT do
        local typeIdx = ((i - 1) % 3) + 1
        local ptype   = S.emberTypes[typeIdx]
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(getMisc(i))
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.GLOW_R, S.GLOW_G, S.GLOW_B)
        tex:SetAlpha(0)
        S.emberParts[i] = {
            tex=tex, ptype=ptype, typeIdx=typeIdx,
            active=false, life=0, maxLife=0,
            x=0, y=0, vx=0, vy=0, drift=0,
        }
    end

    local fistTexs = school.fists or {}
    local nFist = #fistTexs
    S.fistParts = {}
    for i = 1, S.FIST_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        if nFist > 0 then
            tex:SetTexture(fistTexs[((i-1) % nFist) + 1])
        end
        tex:SetBlendMode("BLEND")
        tex:SetAlpha(0)
        S.fistParts[i] = { tex=tex, active=false, life=0, maxLife=0,
                         x=0, y=0, vx=0, vy=0, isTop=true }
    end

    local leafTexs = school.leaves or {}
    local nLeafs   = #leafTexs
    S.leafParts = {}
    for i = 1, S.LEAF_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        if nLeafs > 0 then tex:SetTexture(leafTexs[((i-1) % nLeafs) + 1]) end
        tex:SetBlendMode("BLEND")
        tex:SetAlpha(0)
        S.leafParts[i] = { tex=tex, active=false, x=0, y=0, baseY=0,
                         vx=0, vy=0, waveAmp=0, waveFreq=0, wavePhase=0,
                         rot=0, rotSpeed=0, life=0, maxAlpha=0, size=0, deadX=0 }
    end
end

-- Begin a cast and clear particles from the previous cast.
function FX.Start(duration)
    S.castDuration  = duration or 5
    S.isActive      = true
    S.isFading      = false
    S.fadeT         = 0
    S.glowSpawnAcc  = 0
    S.emberSpawnAcc = 0
    S.fistSpawnAcc  = 0
    S.leafSpawnAcc  = 0
    for _, p  in ipairs(S.glowParts)  do p.active = false ; p.tex:SetAlpha(0) end
    for _, p  in ipairs(S.emberParts) do p.active = false ; p.tex:SetAlpha(0) end
    for _, p  in ipairs(S.fistParts)  do p.active = false ; p.tex:SetAlpha(0) end
    for _, lf in ipairs(S.leafParts)  do lf.active = false ; lf.tex:SetAlpha(0) end
end

-- Stop spawning and begin the residual fade.
function FX.Stop()
    S.isActive      = false
    S.isFading      = true
    S.fadeT         = 0
    S.glowSpawnAcc  = 0
    S.emberSpawnAcc = 0
    S.fistSpawnAcc  = 0
    S.leafSpawnAcc  = 0
end

-- Advance residual particles and artwork during the stop fade.
function FX.UpdateFade(dt)
    if not S.isFading then return end
    S.fadeT = S.fadeT + dt
    local gf = 1
    for _, p  in ipairs(S.glowParts)  do UpdateGlow(p,   dt, gf) end
    for _, p  in ipairs(S.emberParts) do UpdateEmber(p,  dt, gf) end
    for _, p  in ipairs(S.fistParts)  do UpdateFist(p,   dt, gf) end
    for _, lf in ipairs(S.leafParts)  do UpdateLeaf(lf,  dt, gf) end
    if S.fadeT >= SCB.FX_LINGER then
        S.isFading = false
        for _, p  in ipairs(S.glowParts)  do p.active = false ; p.tex:SetAlpha(0) end
        for _, p  in ipairs(S.emberParts) do p.active = false ; p.tex:SetAlpha(0) end
        for _, p  in ipairs(S.fistParts)  do p.active = false ; p.tex:SetAlpha(0) end
        for _, lf in ipairs(S.leafParts)  do lf.active = false ; lf.tex:SetAlpha(0) end
    end
end

-- Hide artwork and clear all active particles.
function FX.Reset()
    S.isActive = false ; S.isFading = false
    for _, p  in ipairs(S.glowParts)  do p.active = false ; p.tex:SetAlpha(0) end
    for _, p  in ipairs(S.emberParts) do p.active = false ; p.tex:SetAlpha(0) end
    for _, p  in ipairs(S.fistParts)  do p.active = false ; p.tex:SetAlpha(0) end
    for _, lf in ipairs(S.leafParts)  do lf.active = false ; lf.tex:SetAlpha(0) end
end

-- Update artwork reveal and particles from cast geometry.
function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    if not S.isActive then return end

    local f = SCB.Bar.frameInner
    local cx, barCY = f:GetCenter()
    if not cx then return end

    for _, p in ipairs(S.glowParts) do UpdateGlow(p, dt, 1) end
    if SCB.Particles.emitProgress < S.GLOW_STOP_AT then
        S.glowSpawnAcc = S.glowSpawnAcc + dt
        if S.glowSpawnAcc >= S.GLOW_SPAWN_RATE then
            S.glowSpawnAcc = 0
            for _ = 1, math.random(2, 4) do SpawnGlow(frontX, barCY, barH) end
        end
    end

    for _, p in ipairs(S.emberParts) do UpdateEmber(p, dt, 1) end
    S.emberSpawnAcc = S.emberSpawnAcc + dt
    if S.emberSpawnAcc >= S.EMBER_SPAWN then
        S.emberSpawnAcc = 0
        for _ = 1, math.random(2, 4) do SpawnEmber(frontX, barCY) end
    end

    for _, p in ipairs(S.fistParts) do UpdateFist(p, dt, 1) end
    if SCB.Particles.emitProgress > 0.02 and SCB.Particles.emitProgress < S.FIST_STOP_AT then
        S.fistSpawnAcc = S.fistSpawnAcc + dt
        if S.fistSpawnAcc >= S.FIST_SPAWN_RATE then
            S.fistSpawnAcc = 0
            for _ = 1, math.random(2, 4) do
                SpawnFist(frontX, barCY, barH)
            end
        end
    end

    local barLX = cx - barW * 0.5
    local barRX = cx + barW * 0.5
    for _, lf in ipairs(S.leafParts) do UpdateLeaf(lf, dt, 1) end
    S.leafSpawnAcc = S.leafSpawnAcc + dt
    if S.leafSpawnAcc >= S.LEAF_SPAWN_RATE then
        S.leafSpawnAcc = 0
        SpawnLeaf(barLX, barRX, barCY, barH)
    end
end
