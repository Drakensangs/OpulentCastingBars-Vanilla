-- ============================================================
--  Opulent Casting Bars -- Particles_Herbalism.lua
--  Nature-like leaf streams, front bursts, and green glow using herbalism art.
-- ============================================================

local S = {}
local FX = {}
SCB.FX                = SCB.FX or {}
SCB.FX["herbalism"]   = FX

local function rand(a, b) return a + math.random() * (b - a) end
S.pi2 = math.pi * 2

-- Frame animation order and randomized timing.
S.FRAME_SEQUENCE = { 1, 2, 3, 2 }
S.FRAME_SEQ_LEN = #S.FRAME_SEQUENCE
S.FRAME_DUR_MIN = 0.10
S.FRAME_DUR_MAX = 0.18

-- Streaming leaf pool, wave motion, speed, rotation, and opacity.
S.LEAF_COUNT = 35
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

-- Front leaf burst pool, motion, gravity, and lifetime.
S.FRONT_COUNT = 60
S.FRONT_SPAWN_RATE = 0.027
S.FRONT_STOP_AT = 0.90
S.FRONT_SIZE_MIN = 7
S.FRONT_SIZE_MAX = 16
S.FRONT_ALPHA = 0.88
S.FRONT_SPEED_MIN = 35
S.FRONT_SPEED_MAX = 95
S.FRONT_GRAVITY = 80
S.FRONT_LIFE_MIN = 0.35
S.FRONT_LIFE_MAX = 0.75

-- Glow pool, emission cutoff, size, lifetime, and tint.
S.GLOW_COUNT = 60
S.GLOW_SPAWN_RATE = 0.02
S.GLOW_STOP_AT = 0.87
S.GLOW_ALPHA = 0.55
S.GLOW_SIZE_MIN = 6
S.GLOW_SIZE_MAX = 12
S.GLOW_LIFE_MIN = 0.18
S.GLOW_LIFE_MAX = 0.35
S.GLOW_R = 0.30 ; S.GLOW_G = 1.0 ; S.GLOW_B = 0.25

S.frameTimer = 0
S.frameDur = 0.14
S.seqPos = 1
-- Cast state, fade state, and reusable particle pools.
S.isActive = false
S.leavesFading = false
S.leavesFadeT = 0

S.leaves = {}
S.frontLeaves = {}
S.glowParts = {}
S.leafSpawnAcc = 0
S.frontSpawnAcc = 0
S.glowSpawnAcc = 0

-- Apply the current frame sequence entry to the shared bar artwork.
local function ApplyFrame()
    local bar    = SCB.Bar
    local school = SCB.Schools.data["herbalism"]
    if bar and bar.texFrame and school and school.frames then
        bar.texFrame:SetTexture(school.frames[S.FRAME_SEQUENCE[S.seqPos]])
    end
end

-- Advance the frame sequence using randomized frame durations.
local function UpdateFrame(dt)
    if S.frameTimer < 0 then
        S.frameTimer = S.frameTimer + dt
        return
    end
    S.frameTimer = S.frameTimer + dt
    if S.frameTimer >= S.frameDur then
        S.frameTimer = S.frameTimer - S.frameDur
        S.frameDur   = rand(S.FRAME_DUR_MIN, S.FRAME_DUR_MAX)
        S.seqPos     = (S.seqPos % S.FRAME_SEQ_LEN) + 1
        ApplyFrame()
    end
end

-- Launch a rotating leaf across the bar with randomized wave motion.
local function SpawnLeaf(barLX, barRX, barCY, barH)
    for _, lf in ipairs(S.leaves) do
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

-- Move a leaf along its wave path and fade near the exit.
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

-- Launch a short-lived leaf burst at the fill front.
local function SpawnFrontLeaf(frontX, barCY, barH)
    for _, lf in ipairs(S.frontLeaves) do
        if not lf.active then
            local angle    = math.rad(rand(40, 140))
            local speed    = rand(S.FRONT_SPEED_MIN, S.FRONT_SPEED_MAX)
            local size     = rand(S.FRONT_SIZE_MIN, S.FRONT_SIZE_MAX)
            local rotSpeed = rand(S.LEAF_ROT_MIN, S.LEAF_ROT_MAX)
                             * (math.random(2) == 1 and 1 or -1)
            lf.active   = true
            lf.life     = 0
            lf.maxLife  = rand(S.FRONT_LIFE_MIN, S.FRONT_LIFE_MAX)
            lf.x        = frontX + rand(-3, 3)
            lf.y        = barCY  + rand(-barH * 0.3, barH * 0.3)
            lf.vx       = math.cos(angle) * speed
            lf.vy       = math.sin(angle) * speed
            lf.rot      = rand(0, S.pi2)
            lf.rotSpeed = rotSpeed
            lf.size     = size
            lf.tex:SetSize(size, size)
            lf.tex:SetAlpha(S.FRONT_ALPHA)
            lf.tex:ClearAllPoints()
            lf.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", lf.x, lf.y)
            return
        end
    end
end

-- Apply gravity, rotation, and lifetime fading to a front leaf.
local function UpdateFrontLeaf(lf, dt, globalFade)
    if not lf.active then return end
    lf.life = lf.life + dt
    local t = lf.life / lf.maxLife
    if t >= 1 then lf.active = false ; lf.tex:SetAlpha(0) ; return end
    lf.vy  = lf.vy - S.FRONT_GRAVITY * dt
    lf.x   = lf.x  + lf.vx * dt
    lf.y   = lf.y  + lf.vy * dt
    lf.rot = lf.rot + lf.rotSpeed * dt
    local alpha = (t < 0.55 and 1 or math.max(0, (1 - t) / 0.45))
                  * S.FRONT_ALPHA * (globalFade or 1)
    lf.tex:SetAlpha(alpha)
    lf.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", lf.x, lf.y)
    lf.tex:SetRotation(lf.rot)
end

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
            p.phase   = math.random() * math.pi * 2
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

-- Create artwork and reusable texture pools.
function FX.Init(container, bar)
    local school   = SCB.Schools.data["herbalism"]
    local leafTexs = (school and school.leaves) or {}
    local nLeafs   = #leafTexs

    S.leaves = {}
    for i = 1, S.LEAF_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        if nLeafs > 0 then tex:SetTexture(leafTexs[((i-1) % nLeafs) + 1]) end
        tex:SetBlendMode("BLEND") ; tex:SetAlpha(0)
        S.leaves[i] = { tex=tex, active=false, x=0, y=0, baseY=0,
                      vx=0, vy=0, waveAmp=0, waveFreq=0, wavePhase=0,
                      rot=0, rotSpeed=0, life=0, maxAlpha=0, size=0, deadX=0 }
    end

    S.frontLeaves = {}
    for i = 1, S.FRONT_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        if nLeafs > 0 then tex:SetTexture(leafTexs[((i-1) % nLeafs) + 1]) end
        tex:SetBlendMode("BLEND") ; tex:SetAlpha(0)
        S.frontLeaves[i] = { tex=tex, active=false, x=0, y=0,
                           vx=0, vy=0, rot=0, rotSpeed=0, life=0, maxLife=0, size=0 }
    end

    S.glowParts = {}
    local glowTex = SCB.TEX_PATH .. "frost\\Particle_Frost_01"
    for i = 1, S.GLOW_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(glowTex)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.GLOW_R, S.GLOW_G, S.GLOW_B)
        tex:SetAlpha(0)
        S.glowParts[i] = { tex=tex, active=false, life=0, maxLife=0,
                         x=0, y=0, vy=0, phase=0 }
    end

    S.seqPos     = 1
    S.frameTimer = 0
    S.frameDur   = rand(S.FRAME_DUR_MIN, S.FRAME_DUR_MAX)
    ApplyFrame()

    if school and school.frames then
        for _, f in ipairs(school.frames) do
            local preload = UIParent:CreateTexture(nil, "BACKGROUND")
            preload:SetTexture(f)
            preload:SetSize(1, 1)
            preload:SetAlpha(0.0001)
            preload:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
        end
    end
end

-- Initialize a new cast and clear leftover particles.
function FX.Start(duration)
    S.isActive      = true
    S.leavesFading  = false
    S.frameDur      = rand(S.FRAME_DUR_MIN, S.FRAME_DUR_MAX)
    S.frameTimer    = -0.10
    -- ApplySchool/Reset show frames[1]; restart the sequence there so the
    -- next step is frame 2 instead of continuing the previous cast's phase.
    S.seqPos        = 1
    S.leafSpawnAcc  = 0
    S.frontSpawnAcc = 0
    S.glowSpawnAcc  = 0
    local bar = SCB.Bar
    if bar and bar.texFrame then
        bar.texFrame:SetAlpha(1)
    end
    for _, lf in ipairs(S.leaves)      do lf.active = false ; lf.tex:SetAlpha(0) end
    for _, lf in ipairs(S.frontLeaves) do lf.active = false ; lf.tex:SetAlpha(0) end
    for _, p  in ipairs(S.glowParts)   do p.active  = false ; p.tex:SetAlpha(0)  end
end

-- Stop emission and begin the style's end-of-cast behavior.
function FX.Stop()
    S.isActive      = false
    S.leavesFading  = true
    S.leavesFadeT   = 0
    S.leafSpawnAcc  = 0
    S.frontSpawnAcc = 0
    S.glowSpawnAcc  = 0
end

-- Advance residual motion and opacity after the cast ends.
function FX.UpdateFade(dt)
    if not S.leavesFading then return end
    S.leavesFadeT = S.leavesFadeT + dt
    local gFade = 1

    for _, lf in ipairs(S.leaves)      do UpdateLeaf(lf, dt, gFade) end
    for _, lf in ipairs(S.frontLeaves) do UpdateFrontLeaf(lf, dt, gFade) end
    for _, p  in ipairs(S.glowParts)   do UpdateGlow(p, dt, gFade) end

    if S.leavesFadeT >= SCB.FX_LINGER then
        S.leavesFading = false
        for _, lf in ipairs(S.leaves)      do lf.active = false ; lf.tex:SetAlpha(0) end
        for _, lf in ipairs(S.frontLeaves) do lf.active = false ; lf.tex:SetAlpha(0) end
        for _, p  in ipairs(S.glowParts)   do p.active  = false ; p.tex:SetAlpha(0)  end
    end
end

-- Clear residual effects and restore owned artwork.
function FX.Reset()
    S.leavesFading = false
    for _, lf in ipairs(S.leaves)      do lf.active = false ; lf.tex:SetAlpha(0) end
    for _, lf in ipairs(S.frontLeaves) do lf.active = false ; lf.tex:SetAlpha(0) end
    for _, p  in ipairs(S.glowParts)   do p.active  = false ; p.tex:SetAlpha(0)  end
    -- Restore shared frame artwork only while this style still owns it.
    if SCB.Bar.currentSchoolKey == "herbalism" then
        local bar    = SCB.Bar
        local school = SCB.Schools.data["herbalism"]
        if bar and bar.texFrame and school and school.frames then
            bar.texFrame:SetTexture(school.frames[1])
            bar.texFrame:SetAlpha(1)
        end
    end
end

-- Advance active-cast animation and particle emission.
function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    if not S.isActive then return end

    local f = SCB.Bar.frameInner
    local cx, barCY = f:GetCenter()
    if not cx then return end

    local barLX = cx - barW * 0.5
    local barRX = cx + barW * 0.5

    UpdateFrame(dt)

    for _, lf in ipairs(S.leaves) do UpdateLeaf(lf, dt, 1) end
    S.leafSpawnAcc = S.leafSpawnAcc + dt
    if S.leafSpawnAcc >= S.LEAF_SPAWN_RATE then
        S.leafSpawnAcc = 0
        SpawnLeaf(barLX, barRX, barCY, barH)
    end

    for _, lf in ipairs(S.frontLeaves) do UpdateFrontLeaf(lf, dt, 1) end
    if SCB.Particles.emitProgress > 0.02 and SCB.Particles.emitProgress < S.FRONT_STOP_AT then
        S.frontSpawnAcc = S.frontSpawnAcc + dt
        if S.frontSpawnAcc >= S.FRONT_SPAWN_RATE then
            S.frontSpawnAcc = 0
            SpawnFrontLeaf(frontX, barCY, barH)
        end
    end

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
