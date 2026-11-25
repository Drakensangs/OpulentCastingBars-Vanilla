-- ============================================================
--  Opulent Casting Bars -- Particles_Aim.lua
--  Leaves, red glows, flashes, and airborne particles on two inward-moving fronts.
-- ============================================================

local S = {}
local FX = {}
SCB.FX          = SCB.FX or {}
SCB.FX["aim"]   = FX

local function rand(a, b) return a + math.random() * (b - a) end
S.pi2 = math.pi * 2

-- Leaf pool, drift, rotation, and wave tuning.
S.LEAF_COUNT = 30
S.LEAF_SPAWN_RATE = 0.13
S.LEAF_SIZE_MIN = 9
S.LEAF_SIZE_MAX = 20
S.LEAF_ALPHA_MIN = 0.40
S.LEAF_ALPHA_MAX = 0.75
S.LEAF_ROT_MIN = 0.8
S.LEAF_ROT_MAX = 2.8
S.LEAF_WAVE_AMP_MIN = 3
S.LEAF_WAVE_AMP_MAX = 9
S.LEAF_WAVE_FREQ_MIN = 1.2
S.LEAF_WAVE_FREQ_MAX = 2.8
S.LEAF_VY_MIN = -3
S.LEAF_VY_MAX = 3
S.LEAF_SPEED_MIN = 50
S.LEAF_SPEED_MAX = 110

-- Glow color, pool, lifetime, and spawn tuning.
S.GLOW_COUNT = 70
S.GLOW_SPAWN_RATE = 0.024
S.GLOW_STOP_AT = 0.96
S.GLOW_ALPHA = 0.62
S.GLOW_SIZE_MIN = 5
S.GLOW_SIZE_MAX = 13
S.GLOW_LIFE_MIN = 0.15
S.GLOW_LIFE_MAX = 0.32
S.GLOW_R = 1.0 ; S.GLOW_G = 0.18 ; S.GLOW_B = 0.05

-- Airborne front particle tuning.
S.FRONT_COUNT = 60
S.FRONT_SPAWN_RATE = 0.030
S.FRONT_STOP_AT = 0.96
S.FRONT_SIZE_MIN = 6
S.FRONT_SIZE_MAX = 14
S.FRONT_ALPHA = 0.78
S.FRONT_SPEED_MIN = 28
S.FRONT_SPEED_MAX = 75
S.FRONT_GRAVITY = 65
S.FRONT_LIFE_MIN = 0.28
S.FRONT_LIFE_MAX = 0.65

-- Flash timing, color, and size tuning.
S.FLASH_PER_SIDE = 3
S.FLASH_HOLD_MIN = 0.04
S.FLASH_HOLD_MAX = 0.10
S.FLASH_FADE_MIN = 0.12
S.FLASH_FADE_MAX = 0.28
S.FLASH_PAUSE_MIN = 0.20
S.FLASH_PAUSE_MAX = 0.80
S.FLASH_OFFSET_X = 18
S.FLASH_ALPHA = 0.92
S.FLASH_SIZE_MIN = 7
S.FLASH_SIZE_MAX = 16
S.FLASH_R = 1.0 ; S.FLASH_G = 0.12 ; S.FLASH_B = 0.06

-- Residual particles use the shared SCB.FX_LINGER cleanup timer.

-- Cast state, artwork handles, and reusable particle pools.
S.isActive = false
S.isFading = false
S.fadeT = 0
S.glowSpawnAcc = 0
S.leafSpawnAcc = 0
S.frontSpawnAcc = 0

S.leaves = {}
S.frontParts = {}
S.glowParts = {}
S.flashPartsL = {}
S.flashPartsR = {}

-- Start a rotating leaf to the left of the bar.
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

-- Launch a rotating particle upward from either fill front.
local function SpawnFrontPart(pool, tipX, barCY, barH, sideSign)
    for _, lf in ipairs(pool) do
        if not lf.active then

            -- 60-120 degrees, mirrored horizontally by sideSign below.
            local angleDeg = 60 + rand(0, 60)
            local angle    = math.rad(angleDeg)

            local vx = math.cos(angle) * rand(S.FRONT_SPEED_MIN, S.FRONT_SPEED_MAX) * (-sideSign)
            local vy = math.sin(angle) * rand(S.FRONT_SPEED_MIN, S.FRONT_SPEED_MAX)
            local size     = rand(S.FRONT_SIZE_MIN, S.FRONT_SIZE_MAX)
            local rotSpeed = rand(S.LEAF_ROT_MIN, S.LEAF_ROT_MAX)
                             * (math.random(2) == 1 and 1 or -1)
            lf.active   = true
            lf.life     = 0
            lf.maxLife  = rand(S.FRONT_LIFE_MIN, S.FRONT_LIFE_MAX)
            lf.x        = tipX  + rand(-3, 3)
            lf.y        = barCY + rand(-barH * 0.25, barH * 0.25)
            lf.vx       = vx
            lf.vy       = vy
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

-- Apply gravity and fade the airborne particle.
local function UpdateFrontPart(lf, dt, globalFade)
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

-- Reuse an idle glow particle at either advancing front.
local function SpawnGlowAt(tipX, cy, barH)
    for _, p in ipairs(S.glowParts) do
        if not p.active then
            local spread = math.min(barH * 0.28, 12)
            p.active  = true
            p.life    = 0
            p.maxLife = rand(S.GLOW_LIFE_MIN, S.GLOW_LIFE_MAX)
            p.x       = tipX + rand(-5, 5)
            p.y       = cy   + rand(-spread, spread)
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

local function ResetFlash(fl)
    fl.phase    = "pause"
    fl.phaseT   = 0
    fl.pauseDur = rand(S.FLASH_PAUSE_MIN, S.FLASH_PAUSE_MAX)
    fl.tex:SetAlpha(0)
end

local function UpdateFlash(fl, dt, tipX, cy, barH, gf)
    fl.phaseT = fl.phaseT + dt

    if fl.phase == "pause" then
        if fl.phaseT >= fl.pauseDur then
            fl.phase   = "hold"
            fl.phaseT  = 0
            fl.holdDur = rand(S.FLASH_HOLD_MIN, S.FLASH_HOLD_MAX)
            fl.fadeDur = rand(S.FLASH_FADE_MIN, S.FLASH_FADE_MAX)

            fl.cx      = tipX + rand(-S.FLASH_OFFSET_X, S.FLASH_OFFSET_X)
            fl.cy      = cy
            local size = rand(S.FLASH_SIZE_MIN, S.FLASH_SIZE_MAX)
            fl.tex:SetSize(size, size)
            fl.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", fl.cx, fl.cy)
            fl.tex:SetAlpha(S.FLASH_ALPHA * (gf or 1))
        end

    elseif fl.phase == "hold" then
        -- Stays where it was placed when the pause ended (fl.cx / fl.cy).
        if fl.phaseT >= fl.holdDur then
            fl.phase  = "fade"
            fl.phaseT = 0
        end

    elseif fl.phase == "fade" then
        local t = math.min(fl.phaseT / fl.fadeDur, 1)
        fl.tex:SetAlpha((1 - t) * S.FLASH_ALPHA * (gf or 1))
        if t >= 1 then
            fl.tex:SetAlpha(0)
            ResetFlash(fl)
        end
    end
end

-- Create artwork layers and reusable particle pools.
function FX.Init(container, bar)
    local school   = SCB.Schools.data["aim"]
    local leafTexs = (school and school.leaves) or {}
    local miscTexs = (school and school.misc)   or {}

    local allTexs = {}
    for i = 1, #leafTexs do allTexs[#allTexs+1] = leafTexs[i] end
    for i = 1, #leafTexs do allTexs[#allTexs+1] = leafTexs[i] end
    for i = 1, #leafTexs do allTexs[#allTexs+1] = leafTexs[i] end
    for i = 1, #miscTexs do allTexs[#allTexs+1] = miscTexs[i] end
    local nAll = #allTexs

    S.leaves = {}
    for i = 1, S.LEAF_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        if nAll > 0 then tex:SetTexture(allTexs[((i-1) % nAll) + 1]) end
        tex:SetBlendMode("BLEND") ; tex:SetAlpha(0)
        S.leaves[i] = { tex=tex, active=false, x=0, y=0, baseY=0,
                      vx=0, vy=0, waveAmp=0, waveFreq=0, wavePhase=0,
                      rot=0, rotSpeed=0, life=0, maxAlpha=0, size=0, deadX=0 }
    end

    S.frontParts = {}
    for i = 1, S.FRONT_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        if nAll > 0 then tex:SetTexture(allTexs[((i-1) % nAll) + 1]) end
        tex:SetBlendMode("BLEND") ; tex:SetAlpha(0)
        S.frontParts[i] = { tex=tex, active=false, x=0, y=0,
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

    S.flashPartsL = {}
    local flashTex = SCB.TEX_PATH .. "frost\\Particle_Frost_01"
    for i = 1, S.FLASH_PER_SIDE do
        local tex = container:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetTexture(flashTex)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.FLASH_R, S.FLASH_G, S.FLASH_B)
        tex:SetAlpha(0)
        S.flashPartsL[i] = {
            tex=tex, phase="pause", phaseT=0,

            pauseDur = rand(0, S.FLASH_PAUSE_MAX) * (i / S.FLASH_PER_SIDE),
            holdDur=0, fadeDur=0, cx=0, cy=0,
        }
    end

    S.flashPartsR = {}
    for i = 1, S.FLASH_PER_SIDE do
        local tex = container:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetTexture(flashTex)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.FLASH_R, S.FLASH_G, S.FLASH_B)
        tex:SetAlpha(0)
        S.flashPartsR[i] = {
            tex=tex, phase="pause", phaseT=0,
            pauseDur = rand(0, S.FLASH_PAUSE_MAX) * (i / S.FLASH_PER_SIDE),
            holdDur=0, fadeDur=0, cx=0, cy=0,
        }
    end
end

-- Begin a cast and clear particles from the previous cast.
function FX.Start(duration)
    S.isActive      = true
    S.isFading      = false
    S.fadeT         = 0
    S.leafSpawnAcc  = 0
    S.frontSpawnAcc = 0
    S.glowSpawnAcc  = 0

    for _, lf in ipairs(S.leaves)     do lf.active = false ; lf.tex:SetAlpha(0) end
    for _, lf in ipairs(S.frontParts) do lf.active = false ; lf.tex:SetAlpha(0) end
    for _, p  in ipairs(S.glowParts)  do p.active  = false ; p.tex:SetAlpha(0)  end
    for i, fl in ipairs(S.flashPartsL) do
        fl.phase    = "pause"
        fl.phaseT   = 0
        fl.pauseDur = rand(0, S.FLASH_PAUSE_MAX) * (i / S.FLASH_PER_SIDE)
        fl.tex:SetAlpha(0)
    end
    for i, fl in ipairs(S.flashPartsR) do
        fl.phase    = "pause"
        fl.phaseT   = 0
        fl.pauseDur = rand(0, S.FLASH_PAUSE_MAX) * (i / S.FLASH_PER_SIDE)
        fl.tex:SetAlpha(0)
    end
end

-- Stop spawning and begin the residual fade.
function FX.Stop()
    S.isActive      = false
    S.isFading      = true
    S.fadeT         = 0
    S.leafSpawnAcc  = 0
    S.frontSpawnAcc = 0
    S.glowSpawnAcc  = 0
    for _, fl in ipairs(S.flashPartsL) do fl.tex:SetAlpha(0) end
    for _, fl in ipairs(S.flashPartsR) do fl.tex:SetAlpha(0) end
end

-- Advance residual particles and artwork during the stop fade.
function FX.UpdateFade(dt)
    if not S.isFading then return end
    S.fadeT = S.fadeT + dt
    local gf = 1

    for _, lf in ipairs(S.leaves)     do UpdateLeaf(lf, dt, gf)      end
    for _, lf in ipairs(S.frontParts) do UpdateFrontPart(lf, dt, gf) end
    for _, p  in ipairs(S.glowParts)  do UpdateGlow(p, dt, gf)       end

    if S.fadeT >= SCB.FX_LINGER then
        S.isFading = false
        for _, lf in ipairs(S.leaves)     do lf.active = false ; lf.tex:SetAlpha(0) end
        for _, lf in ipairs(S.frontParts) do lf.active = false ; lf.tex:SetAlpha(0) end
        for _, p  in ipairs(S.glowParts)  do p.active  = false ; p.tex:SetAlpha(0)  end
    end
end

-- Hide artwork and clear all active particles.
function FX.Reset()
    S.isActive = false
    S.isFading = false
    for _, lf in ipairs(S.leaves)      do lf.active = false ; lf.tex:SetAlpha(0) end
    for _, lf in ipairs(S.frontParts)  do lf.active = false ; lf.tex:SetAlpha(0) end
    for _, p  in ipairs(S.glowParts)   do p.active  = false ; p.tex:SetAlpha(0)  end
    for _, fl in ipairs(S.flashPartsL) do fl.tex:SetAlpha(0) end
    for _, fl in ipairs(S.flashPartsR) do fl.tex:SetAlpha(0) end
end

-- Update artwork reveal and particles from cast geometry.
function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW, fillLXRight, fillWRight)
    if not S.isActive then return end

    local f = SCB.Bar.frameInner
    local barCX, barCY = f:GetCenter()
    if not barCX then return end

    local barLX = barCX - barW * 0.5
    local barRX = barCX + barW * 0.5

    local halfFillW = fillW * 0.5
    local leftTipX  = fillLX + halfFillW * progress

    local rFillLX = fillLXRight or fillLX
    local rFillW  = fillWRight  or fillW
    local rightTipX = rFillLX + rFillW - rFillW * 0.5 * progress

    for _, lf in ipairs(S.leaves) do UpdateLeaf(lf, dt, 1) end
    S.leafSpawnAcc = S.leafSpawnAcc + dt
    if S.leafSpawnAcc >= S.LEAF_SPAWN_RATE then
        S.leafSpawnAcc = 0
        SpawnLeaf(barLX, barRX, barCY, barH)
    end

    for _, lf in ipairs(S.frontParts) do UpdateFrontPart(lf, dt, 1) end
    if SCB.Particles.emitProgress < S.FRONT_STOP_AT then
        S.frontSpawnAcc = S.frontSpawnAcc + dt
        if S.frontSpawnAcc >= S.FRONT_SPAWN_RATE then
            S.frontSpawnAcc = 0

            SpawnFrontPart(S.frontParts, leftTipX,  barCY, barH,  1)
            SpawnFrontPart(S.frontParts, rightTipX, barCY, barH, -1)
        end
    end

    for _, p in ipairs(S.glowParts) do UpdateGlow(p, dt, 1) end
    if SCB.Particles.emitProgress < S.GLOW_STOP_AT then
        S.glowSpawnAcc = S.glowSpawnAcc + dt
        if S.glowSpawnAcc >= S.GLOW_SPAWN_RATE then
            S.glowSpawnAcc = 0

            local n = math.random(1, 3)
            for _ = 1, n do SpawnGlowAt(leftTipX,  barCY, barH) end
            for _ = 1, n do SpawnGlowAt(rightTipX, barCY, barH) end
        end
    end

    for _, fl in ipairs(S.flashPartsL) do
        UpdateFlash(fl, dt, leftTipX,  barCY, barH, 1)
    end
    for _, fl in ipairs(S.flashPartsR) do
        UpdateFlash(fl, dt, rightTipX, barCY, barH, 1)
    end
end
