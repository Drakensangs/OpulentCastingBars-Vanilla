-- ============================================================
--  Opulent Casting Bars -- Particles_Gears.lua
--  Rotating gear, one fixed and four moving forks, warm sparks, and closing mist.
-- ============================================================

local S = {}
local FX = {}
SCB.FX = SCB.FX or {}
SCB.FX["gears"] = FX

local function rand(a, b) return a + math.random() * (b - a) end
local function rad(deg) return deg * math.pi / 180 end
local function lerp(a, b, t) return a + (b - a) * math.max(0, math.min(t, 1)) end

-- Centre of the round opening of the frame and the porthole (1024x512
-- artwork px), around which the gear turns.
S.OPENING_CX, S.OPENING_CY = 153.03, 240.36
-- Spell icon rectangle (artwork px); its mask (Mask_Icon_Gears)
-- follows the opening of the frame, the porthole
-- and the turning gear. See SCB.Bar:NewSpellIcon.
S.ICON_RECT = { x0 = 54.75, y0 = 141.5, x1 = 251.5, y1 = 339.0 }

-- The gear (Misc_Gears, 512x512) turns around the opening's centre.
-- Its own centre is not the texture's: it lies at texel (257.4, 253.2),
-- which is the rotation pivot and the point placed on the opening centre.
S.MISC_ART_SIZE = 284.16           -- artwork px (111 px on a 400 px bar)
S.MISC_PIVOT_X  = 257.4 / 512      -- from the left
S.MISC_PIVOT_Y  = 1 - 253.2 / 512  -- from the bottom (SetRotation's pivot)
S.MISC_ROT_SPEED = 18

-- Fork spacing and capped progress travel.
S.FORK_COUNT = 5
S.FORK_STEP_X = 10
S.FORK_MAX_SHIFT = { 0, 35, 65, 95, 125 }
S.FORK_TRACK_RANGE = 125

-- Glow pool, emission cutoff, size, lifetime, and tint.
S.GLOW_COUNT = 60
S.GLOW_SPAWN_RATE = 0.02
S.GLOW_STOP_AT = 0.87
S.GLOW_ALPHA = 0.55
S.GLOW_SIZE_MIN = 4
S.GLOW_SIZE_MAX = 9
S.GLOW_LIFE_MIN = 0.10
S.GLOW_LIFE_MAX = 0.20
S.GLOW_R = 0.92 ; S.GLOW_G = 0.78 ; S.GLOW_B = 0.52

-- Fragment pool, emission interval, motion types, and colors.
S.EMBER_COUNT = 60
S.EMBER_SPAWN = 0.03
S.EMBER_R = 0.92 ; S.EMBER_G = 0.78 ; S.EMBER_B = 0.52

S.emberTypes = {
    { sizeMin=8,  sizeMax=14, speedMin=25, speedMax=60,  lifeMin=0.8, lifeMax=1.6, gravity=8,  spread=140, driftX=0.4 },
    { sizeMin=4,  sizeMax=8,  speedMin=80, speedMax=160, lifeMin=0.3, lifeMax=0.7, gravity=15, spread=80,  driftX=0.0 },
    { sizeMin=6,  sizeMax=12, speedMin=40, speedMax=90,  lifeMin=0.6, lifeMax=1.2, gravity=20, spread=100, driftX=0.2 },
}

-- Fork rewind duration and rapid-recast window.
S.FORK_REWIND_DUR = 0.22
S.RECAST_WINDOW = 0.45

-- Closing mist expansion, fade timing, and warm tint.
S.PSHIT_DUR = 0.22
S.PSHIT_SIZE_START = 192
S.PSHIT_SIZE_END = 372
S.PSHIT_ALPHA_PEAK = 0.85
S.PSHIT_R = 0.95 ; S.PSHIT_G = 0.62 ; S.PSHIT_B = 0.32

-- Cast state, fade state, and reusable particle pools.
S.isActive = false
S.partsFading = false
S.partsFadeT = 0
S.castDuration = 5
S.glowParts = {}
S.glowSpawnAcc = 0
S.emberParts = {}
S.emberSpawnAcc = 0
S.miscAngle = 0
S.lastProgress = 0
S.rewindActive = false
S.rewindStartProg = 0
S.rewindT = 0
S.pshitActive = false
S.pshitT = 0
S.pshitX = 0
S.pshitY = 0
S.pshitBurstDone = false
S.pshitFrontX = 0
S.pshitFrontY = 0
S.pshitDriftX = 0
S.pshitDriftY = 0
S.pshitFrontDriftX = 0
S.pshitFrontDriftY = 0
S.lastStopTime = 0

S.iconTex = nil
S.forks = {}
local miscTex, circleTex, pshitTex, pshitFrontTex

-- Place the spell icon and the gear on the frame's opening at the current
-- bar size (the gear keeps a uniform scale: it turns).
local function PositionIconAndGear()
    local f = SCB.Bar.frameInner
    if not f then return end
    if S.iconTex then S.iconTex:Layout() end
    if miscTex then
        local sx, sy = SCB.Bar:GetArtScale()
        local size = S.MISC_ART_SIZE * math.sqrt(sx * sy)
        -- Quad centre so that the pivot lands on the opening centre.
        local qx = S.OPENING_CX * sx - (S.MISC_PIVOT_X - 0.5) * size
        local qy = -S.OPENING_CY * sy - (S.MISC_PIVOT_Y - 0.5) * size
        miscTex:ClearAllPoints()
        miscTex:SetPoint("CENTER", f, "TOPLEFT", qx, qy)
        miscTex:SetSize(size, size)
    end
end

-- Fork travel was tuned on a 400 px wide bar.
local function PositionElements(progress)
    local f = SCB.Bar.frameInner
    if not f then return end
    local k = (SCB.Bar:GetArtScale()) * 1024 / 400
    local track = math.max(0, math.min(progress or 0, 1)) * S.FORK_TRACK_RANGE
    for i = 1, S.FORK_COUNT do
        local t = S.forks[i]
        if t then
            local shift = 0
            if i > 1 then
                shift = math.min(track, S.FORK_MAX_SHIFT[i] or 0)
            end
            local baseShift = (i - 1) * S.FORK_STEP_X
            local totalShift = (baseShift + shift) * k
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", f, "TOPLEFT", totalShift, 0)
            t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", totalShift, 0)
        end
    end
end

-- Reuse a glow particle near the fill front.
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

-- Reuse a matching fragment type; cast duration tunes launch speed.
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

-- Integrate fragment gravity and drift, then apply its lifetime envelope.
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

-- Create artwork and reusable texture pools.
function FX.Init(container, bar)
    local school = SCB.Schools.data["gears"] or {}

    -- Under the frame, the circle and the gear.
    S.iconTex = SCB.Bar:NewSpellIcon(bar, "ARTWORK", -3, S.ICON_RECT, school)

    miscTex = (SCB.Bar and SCB.Bar.decoHost or bar):CreateTexture(nil, "OVERLAY", nil, 2)
    miscTex:SetTexture(school.misc)
    miscTex:SetAlpha(0)

    circleTex = (SCB.Bar and SCB.Bar.decoHost or bar):CreateTexture(nil, "OVERLAY", nil, 3)
    circleTex:SetAllPoints(bar)
    circleTex:SetTexture(school.circle)
    circleTex:SetAlpha(0)

    pshitTex = (SCB.Bar and SCB.Bar.decoHost or bar):CreateTexture(nil, "OVERLAY", nil, 6)
    pshitTex:SetTexture(SCB.TEX_PATH .. "frost\\Mist_Frost_01")
    pshitTex:SetBlendMode("ADD")
    pshitTex:SetVertexColor(S.PSHIT_R, S.PSHIT_G, S.PSHIT_B)
    pshitTex:SetAlpha(0)

    pshitFrontTex = (SCB.Bar and SCB.Bar.decoHost or bar):CreateTexture(nil, "OVERLAY", nil, 6)
    pshitFrontTex:SetTexture(SCB.TEX_PATH .. "frost\\Mist_Frost_01")
    pshitFrontTex:SetBlendMode("ADD")
    pshitFrontTex:SetVertexColor(S.PSHIT_R, S.PSHIT_G, S.PSHIT_B)
    pshitFrontTex:SetAlpha(0)

    S.forks = {}
    for i = 1, S.FORK_COUNT do
        local t = (SCB.Bar and SCB.Bar.decoHost or bar):CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetTexture(school.fork)
        t:SetAlpha(0)
        S.forks[i] = t
    end

    PositionElements(0)

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
        for _, t in ipairs(earthSchool.rocks or {}) do miscTexs[#miscTexs + 1] = t end
        for _, t in ipairs(earthSchool.debris or {}) do miscTexs[#miscTexs + 1] = t end
    end

    S.emberParts = {}
    for i = 1, S.EMBER_COUNT do
        local typeIdx = ((i - 1) % 3) + 1
        local ptype = S.emberTypes[typeIdx]
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(miscTexs[((i - 1) % math.max(#miscTexs, 1)) + 1] or glowTex)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.EMBER_R, S.EMBER_G, S.EMBER_B)
        tex:SetAlpha(0)
        S.emberParts[i] = {
            tex=tex, ptype=ptype, typeIdx=typeIdx,
            active=false, life=0, maxLife=0,
            x=0, y=0, vx=0, vy=0, drift=0,
        }
    end
end

-- Initialize a new cast and clear leftover particles.
function FX.Start(duration)
    S.castDuration  = duration or 5
    S.isActive      = true
    S.partsFading   = false
    S.partsFadeT    = 0
    S.glowSpawnAcc  = 0
    S.emberSpawnAcc = 0
    S.miscAngle     = 0

    local now = GetTime()
    if S.lastProgress > 0.02 and (now - (S.lastStopTime or 0)) <= S.RECAST_WINDOW then
        S.rewindActive = true
        S.rewindStartProg = S.lastProgress
        S.rewindT = 0
    else
        S.rewindActive = false
        S.rewindStartProg = 0
        S.rewindT = 0
    end

    S.pshitActive = false
    S.pshitT = 0
    S.pshitBurstDone = false
    if pshitTex then pshitTex:SetAlpha(0) end
    if pshitFrontTex then pshitFrontTex:SetAlpha(0) end

    if S.iconTex then
        S.iconTex:SetTexture(SCB.Bar.currentSpellIcon)
        S.iconTex:SetAlpha(1)
    end
    PositionIconAndGear()
    if miscTex then
        miscTex:SetRotation(0, S.MISC_PIVOT_X, S.MISC_PIVOT_Y)
        miscTex:SetAlpha(1)
    end
    if circleTex then circleTex:SetAlpha(1) end
    for _, t in ipairs(S.forks) do if t then t:SetAlpha(1) end end

    PositionElements(0)

    for _, p in ipairs(S.glowParts)  do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.emberParts) do p.active = false ; p.tex:SetAlpha(0) end
end

-- Stop emission and begin the style's end-of-cast behavior.
function FX.Stop()
    S.isActive      = false
    S.partsFading   = true
    S.partsFadeT    = 0
    S.glowSpawnAcc  = 0
    S.emberSpawnAcc = 0
    S.lastStopTime = GetTime()
    S.pshitActive = true
    S.pshitT = 0
    S.pshitBurstDone = false

    local f = SCB.Bar and SCB.Bar.frameInner
    if f then
        local cx, cy = f:GetCenter()
        if cx and cy then
            S.pshitX = cx - 40 + rand(-8, 8)
            S.pshitY = cy + rand(-4, 4)
        end
    end
    S.pshitDriftX = rand(-4, 4)
    S.pshitDriftY = rand(3, 7)
    S.pshitFrontDriftX = rand(-3, 3)
    S.pshitFrontDriftY = rand(2, 5)

    if pshitTex then
        pshitTex:SetSize(S.PSHIT_SIZE_START, S.PSHIT_SIZE_START * 0.58)
        pshitTex:ClearAllPoints()
        pshitTex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", S.pshitX, S.pshitY)
        pshitTex:SetAlpha(0)
    end
    if pshitFrontTex then
        pshitFrontTex:SetSize(S.PSHIT_SIZE_START, S.PSHIT_SIZE_START * 0.58)
        pshitFrontTex:ClearAllPoints()
        pshitFrontTex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", S.pshitFrontX, S.pshitFrontY)
        pshitFrontTex:SetAlpha(0)
    end
end

-- Advance residual motion and opacity after the cast ends.
function FX.UpdateFade(dt)
    if not S.partsFading then return end
    S.partsFadeT = S.partsFadeT + dt
    local gFade = 1
    local pshitFade = 1

    if S.iconTex then S.iconTex:SetAlpha(gFade) end
    if miscTex then miscTex:SetAlpha(gFade) end
    if circleTex then circleTex:SetAlpha(gFade) end
    for _, t in ipairs(S.forks) do if t then t:SetAlpha(gFade) end end

    if S.pshitActive and pshitTex then
        if not S.pshitBurstDone then
            S.pshitT = S.pshitT + dt
            local tp = math.min(S.pshitT / S.PSHIT_DUR, 1)
            local size = S.PSHIT_SIZE_START + (S.PSHIT_SIZE_END - S.PSHIT_SIZE_START) * tp
            local driftT = S.partsFadeT
            pshitTex:SetSize(size, size * 0.58)
            pshitTex:ClearAllPoints()
            pshitTex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", S.pshitX + tp * 10 + driftT * S.pshitDriftX, S.pshitY + tp * 2 + driftT * S.pshitDriftY)
            local env = tp < 0.18 and tp / 0.18 or math.max(0.45, (1 - tp) / 0.82)
            pshitTex:SetAlpha(env * S.PSHIT_ALPHA_PEAK * pshitFade)
            if pshitFrontTex then
                pshitFrontTex:SetSize(size, size * 0.58)
                pshitFrontTex:ClearAllPoints()
                pshitFrontTex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", S.pshitFrontX + tp * 12 + driftT * S.pshitFrontDriftX, S.pshitFrontY + tp * 3 + driftT * S.pshitFrontDriftY)
                pshitFrontTex:SetAlpha(env * (S.PSHIT_ALPHA_PEAK * 0.9) * pshitFade)
            end
            if tp >= 1 then
                S.pshitBurstDone = true
            end
        else
            local driftT = S.partsFadeT
            pshitTex:ClearAllPoints()
            pshitTex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", S.pshitX + 10 + driftT * S.pshitDriftX, S.pshitY + 2 + driftT * S.pshitDriftY)
            pshitTex:SetAlpha(S.PSHIT_ALPHA_PEAK * 0.45 * pshitFade)
            if pshitFrontTex then
                pshitFrontTex:ClearAllPoints()
                pshitFrontTex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", S.pshitFrontX + 12 + driftT * S.pshitFrontDriftX, S.pshitFrontY + 3 + driftT * S.pshitFrontDriftY)
                pshitFrontTex:SetAlpha((S.PSHIT_ALPHA_PEAK * 0.9) * 0.45 * pshitFade)
            end
        end
    end

    for _, p in ipairs(S.glowParts)  do UpdateGlow(p, dt, gFade) end
    for _, p in ipairs(S.emberParts) do UpdateEmber(p, dt, gFade) end

    if S.partsFadeT >= SCB.FX_LINGER then
        S.partsFading = false
        if S.iconTex then S.iconTex:SetAlpha(0) end
        if miscTex then miscTex:SetAlpha(0) end
        if circleTex then circleTex:SetAlpha(0) end
        for _, t in ipairs(S.forks) do if t then t:SetAlpha(0) end end
        S.pshitActive = false
        if pshitTex then pshitTex:SetAlpha(0) end
        if pshitFrontTex then pshitFrontTex:SetAlpha(0) end
        for _, p in ipairs(S.glowParts)  do p.active = false ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.emberParts) do p.active = false ; p.tex:SetAlpha(0) end
    end
end

-- Clear residual effects and restore owned artwork.
function FX.Reset()
    S.partsFading = false
    S.pshitActive = false
    S.pshitT = 0
    S.pshitBurstDone = false
    S.pshitDriftX, S.pshitDriftY = 0, 0
    S.pshitFrontDriftX, S.pshitFrontDriftY = 0, 0
    if pshitTex then pshitTex:SetAlpha(0) end
    if pshitFrontTex then pshitFrontTex:SetAlpha(0) end
    S.rewindActive = false
    S.rewindStartProg = 0
    S.rewindT = 0
    if S.iconTex then S.iconTex:SetAlpha(0) end
    if miscTex then
        miscTex:SetAlpha(0)
        miscTex:SetRotation(0, S.MISC_PIVOT_X, S.MISC_PIVOT_Y)
    end
    if circleTex then circleTex:SetAlpha(0) end
    for _, t in ipairs(S.forks) do if t then t:SetAlpha(0) end end
    for _, p in ipairs(S.glowParts)  do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.emberParts) do p.active = false ; p.tex:SetAlpha(0) end
end

-- Advance active-cast animation and particle emission.
function FX.Update(dt, progress, frontX, cy, barW, barH)
    if not S.isActive then return end

    S.miscAngle = S.miscAngle + dt * S.MISC_ROT_SPEED
    if miscTex then miscTex:SetRotation(math.rad(S.miscAngle), S.MISC_PIVOT_X, S.MISC_PIVOT_Y) end

    local visualProgress = progress
    if S.rewindActive then
        S.rewindT = S.rewindT + dt
        local tr = math.min(S.rewindT / S.FORK_REWIND_DUR, 1)
        local rewindProgress = S.rewindStartProg * (1 - tr)
        visualProgress = math.max(progress, rewindProgress)
        if tr >= 1 then
            S.rewindActive = false
            S.rewindStartProg = 0
            S.rewindT = 0
        end
    end
    PositionElements(visualProgress)
    S.lastProgress = progress
    S.pshitFrontX = frontX
    S.pshitFrontY = cy

    local f = SCB.Bar.frameInner
    local _, barCY = f:GetCenter()
    if not barCY then return end

    for _, p in ipairs(S.glowParts) do UpdateGlow(p, dt, 1) end
    if SCB.Particles.emitProgress < S.GLOW_STOP_AT then
        S.glowSpawnAcc = S.glowSpawnAcc + dt
        if S.glowSpawnAcc >= S.GLOW_SPAWN_RATE then
            S.glowSpawnAcc = 0
            local count = math.random(2, 4)
            for _ = 1, count do SpawnGlow(frontX, barCY, barH) end
        end
    end

    for _, p in ipairs(S.emberParts) do UpdateEmber(p, dt, 1) end
    S.emberSpawnAcc = S.emberSpawnAcc + dt
    if S.emberSpawnAcc >= S.EMBER_SPAWN then
        S.emberSpawnAcc = 0
        local count = math.random(2, 4)
        for _ = 1, count do SpawnEmber(frontX, barCY) end
    end
end
