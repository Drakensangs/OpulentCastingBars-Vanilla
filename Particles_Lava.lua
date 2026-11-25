-- ============================================================
--  Opulent Casting Bars -- Particles_Lava.lua
--  Dark rising smoke, warm ash fragments, and bright pixel sparks.
-- ============================================================

local S = {}
local FX = {}
SCB.FX          = SCB.FX or {}
SCB.FX["lava"]  = FX

local function rand(a, b) return a + math.random() * (b - a) end
local function rad(deg)   return deg * math.pi / 180 end
local function lerp(a, b, t) return a + (b - a) * math.max(0, math.min(t, 1)) end

-- Rotate texture UVs around their center.
local function SetTexRot(tex, angle)
    local c, s = math.cos(angle), math.sin(angle)
    tex:SetTexCoord(
        0.5+(-0.5)*c-(-0.5)*s, 0.5+(-0.5)*s+(-0.5)*c,
        0.5+(-0.5)*c-( 0.5)*s, 0.5+(-0.5)*s+( 0.5)*c,
        0.5+( 0.5)*c-(-0.5)*s, 0.5+( 0.5)*s+(-0.5)*c,
        0.5+( 0.5)*c-( 0.5)*s, 0.5+( 0.5)*s+( 0.5)*c
    )
end

-- Smoke size, opacity phases, rotation, and horizontal spawn positions.
S.SMOKE_W_BASE = 280
S.SMOKE_H_BASE = 140
S.SMOKE_ALPHA_MAX = 0.35
S.SMOKE_SCALE_MIN = 0.8
S.SMOKE_SCALE_MAX = 1.4
S.SMOKE_FADE_IN = 2.0
S.SMOKE_HOLD_MIN = 1.5
S.SMOKE_HOLD_MAX = 3.0
S.SMOKE_FADE_OUT = 1.8
S.SMOKE_ROT_SPEED = 0.025
S.SMOKE_POSITIONS = { 1/6, 2/6, 3/6, 4/6 }

-- Fragment pool, emission interval, motion types, and colors.
S.EMBER_COUNT = 90
S.EMBER_SPAWN = 0.02

S.emberTypes = {
    { sizeMin=8,  sizeMax=16, speedMin=20, speedMax=55,  lifeMin=0.9, lifeMax=1.8, gravity=6,  spread=150, driftX=0.5 },
    { sizeMin=4,  sizeMax=9,  speedMin=70, speedMax=150, lifeMin=0.3, lifeMax=0.7, gravity=12, spread=90,  driftX=0.0 },
    { sizeMin=5,  sizeMax=13, speedMin=35, speedMax=80,  lifeMin=0.7, lifeMax=1.3, gravity=18, spread=110, driftX=0.3 },
}

S.EMBER_COLORS = {
    { 1.0, 0.35, 0.02 },
    { 1.0, 0.15, 0.01 },
    { 1.0, 0.55, 0.05 },
}

-- Pixel spark pool, launch motion, lifetime, and palette.
S.SPARK_COUNT = 50
S.SPARK_SPAWN = 0.035
S.SPARK_SIZE_MIN = 3
S.SPARK_SIZE_MAX = 7
S.SPARK_LIFE_MIN = 0.4
S.SPARK_LIFE_MAX = 1.1
S.SPARK_SPEED_MIN = 30
S.SPARK_SPEED_MAX = 90
S.SPARK_GRAVITY = 25

S.SPARK_COLORS = {
    { 1.0, 0.90, 0.10, 1.0  },
    { 1.0, 0.70, 0.05, 0.85 },
    { 1.0, 0.95, 0.30, 0.6  },
    { 1.0, 0.55, 0.02, 0.7  },
    { 1.0, 1.00, 0.50, 0.45 },
}

-- Current cast duration; longer casts get faster, longer-lived embers.
S.castDuration = 5

-- Cast state, fade state, and reusable particle pools.
S.isActive = false
S.partsFading = false
S.partsFadeT = 0
S.smokes = {}
S.emberParts = {}
S.sparkParts = {}
S.ambParts = {}
S.emberSpawnAcc = 0
S.sparkSpawnAcc = 0
S.ambSpawnAcc = 0

S.AMB_COUNT = 40
S.AMB_SPAWN = 0.07

-- Restart a rising smoke cycle with randomized size and pulse direction.
local function SpawnSmoke(m)
    local scale = rand(S.SMOKE_SCALE_MIN, S.SMOKE_SCALE_MAX)
    m.baseW    = S.SMOKE_W_BASE * scale
    m.baseH    = S.SMOKE_H_BASE * scale
    m.tex:SetSize(m.baseW, m.baseH)
    m.tex:SetAlpha(0)
    m.phase    = "fadein"
    m.timer    = 0
    m.duration = S.SMOKE_FADE_IN
    m.alpha    = 0
    m.scaleT   = 0
    m.scaleDir = math.random(2) == 1 and 1 or -1

    local f = SCB.Bar.frameInner
    local _, cy = f:GetCenter()
    m.riseY = cy or m.riseY or 0
end

-- Advance smoke rise, rotation, pulse, and opacity phases.
local function UpdateSmoke(m, dt, globalFade)
    if m.delay and m.delay > 0 then m.delay = m.delay - dt ; return end
    if m.phase == "idle" then if S.isActive then SpawnSmoke(m) end return end

    local f = SCB.Bar.frameInner
    local cx, cy = f:GetCenter()
    if cx then
        local barW = f:GetWidth()
        local x = cx - barW * 0.5 + barW * m.xFrac
        m.riseY = (m.riseY or cy) + 10 * dt
        m.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, m.riseY)
    end

    m.timer  = m.timer + dt
    m.scaleT = m.scaleT + dt
    m.angle  = m.angle + S.SMOKE_ROT_SPEED * m.rotDir * dt

    local scalePulse = 1 + math.sin(m.scaleT * 0.35 * m.scaleDir) * 0.08
    m.tex:SetSize(m.baseW * scalePulse, m.baseH * scalePulse)
    SetTexRot(m.tex, m.angle)

    local gf = globalFade or 1
    if m.phase == "fadein" then
        m.alpha = math.min(m.timer / m.duration, 1) * S.SMOKE_ALPHA_MAX
        m.tex:SetAlpha(math.max(0, m.alpha) * gf)
        if m.timer >= m.duration then
            m.phase = "hold" ; m.timer = 0
            m.duration = rand(S.SMOKE_HOLD_MIN, S.SMOKE_HOLD_MAX)
        end
    elseif m.phase == "hold" then
        local pulse = math.sin(m.scaleT * 1.5) * 0.04
        m.tex:SetAlpha(math.max(0, S.SMOKE_ALPHA_MAX + pulse) * gf)
        if m.timer >= m.duration then
            m.phase = "fadeout" ; m.timer = 0 ; m.duration = S.SMOKE_FADE_OUT
        end
    elseif m.phase == "fadeout" then
        m.alpha = (1 - m.timer / m.duration) * S.SMOKE_ALPHA_MAX
        m.tex:SetAlpha(math.max(0, m.alpha) * gf)
        if m.timer >= m.duration then
            m.tex:SetAlpha(0) ; m.phase = "idle"
        end
    end
end

-- Reuse a matching fragment type; cast duration tunes launch speed.
local function SpawnEmber(wx, wy)
    local roll = math.random(10)
    local typeIdx = roll <= 4 and 1 or (roll <= 7 and 3 or 2)
    local ptype = S.emberTypes[typeIdx]
    local col   = S.EMBER_COLORS[math.random(#S.EMBER_COLORS)]

    for _, p in ipairs(S.emberParts) do
        if not p.active and p.typeIdx == typeIdx then
            local tCast = math.max(0, math.min((S.castDuration - 2) / 3, 1))
            local speed = rand(lerp(ptype.speedMax * 0.5, ptype.speedMin, tCast),
                               lerp(ptype.speedMax, ptype.speedMax * 0.8, tCast))
            local angle = rad(90 + rand(-ptype.spread * 0.5, ptype.spread * 0.5))
            local size  = rand(ptype.sizeMin, ptype.sizeMax)
            p.active  = true ; p.life = 0
            p.maxLife = rand(ptype.lifeMin, ptype.lifeMax)
            p.x       = wx + rand(-6, 6)
            p.y       = wy + rand(-8, 8)
            p.vx      = math.cos(angle) * speed
            p.vy      = math.sin(angle) * speed
            p.drift   = rand(-ptype.driftX, ptype.driftX) * 30
            p.tex:SetVertexColor(col[1], col[2], col[3])
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(1)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
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
    p.tex:SetAlpha(alpha * 0.9 * (globalFade or 1))
end

-- Launch a bright pixel spark from the fill front.
local function SpawnSpark(wx, wy)
    local col = S.SPARK_COLORS[math.random(#S.SPARK_COLORS)]
    for _, p in ipairs(S.sparkParts) do
        if not p.active then
            local angle = rad(rand(30, 150))
            local speed = rand(S.SPARK_SPEED_MIN, S.SPARK_SPEED_MAX)
            p.active    = true ; p.life = 0
            p.maxLife   = rand(S.SPARK_LIFE_MIN, S.SPARK_LIFE_MAX)
            p.x         = wx + rand(-4, 4)
            p.y         = wy + rand(-6, 6)
            p.vx        = math.cos(angle) * speed
            p.vy        = math.sin(angle) * speed
            p.baseAlpha = col[4]
            p.tex:SetVertexColor(col[1], col[2], col[3])
            local size = rand(S.SPARK_SIZE_MIN, S.SPARK_SIZE_MAX)
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(0)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            return
        end
    end
end

-- Apply spark gravity, flicker, and lifetime fading.
local function UpdateSpark(p, dt, globalFade)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    p.vy = p.vy - S.SPARK_GRAVITY * dt
    p.x  = p.x + p.vx * dt
    p.y  = p.y + p.vy * dt
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local env
    if t < 0.15 then env = t / 0.15
    elseif t < 0.75 then env = 1 + math.sin(p.life * 18) * 0.15
    else env = (1 - t) / 0.25 end
    local sparkAlpha = math.max(0, env) * p.baseAlpha * (globalFade or 1)
    p.tex:SetAlpha(math.min(1, sparkAlpha))
end

-- Scatter ambient ash around the bar as progress advances.
local function SpawnAmb(progress)
    local f = SCB.Bar.frame
    local cx, cy = f:GetCenter()
    if not cx then return end
    local barW, barH = f:GetWidth(), f:GetHeight()

    for _, p in ipairs(S.ambParts) do
        if not p.active then
            local xOffset = rand(-barW * 0.5, barW * progress - barW * 0.5)
            local yOffset = rand(-barH * 0.35, barH * 0.35)
            local wx, wy  = cx + xOffset, cy + yOffset
            local dirX    = xOffset > 0 and 1 or -1
            local angle   = rad(rand(60, 120)) * (yOffset > 0 and 1 or -1)
            local speed   = rand(15, 45)
            local col     = S.EMBER_COLORS[math.random(#S.EMBER_COLORS)]

            p.active  = true ; p.life = 0
            p.maxLife = rand(1.0, 2.2)
            p.x       = wx ; p.y = wy
            p.vx      = dirX * rand(5, 20)
            p.vy      = math.sin(angle) * speed
            p.tex:SetVertexColor(col[1], col[2], col[3])
            local size = rand(5, 13)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(0)
            return
        end
    end
end

-- Move ambient ash and apply its lifetime fade.
local function UpdateAmb(p, dt, globalFade)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    p.vy = p.vy - 4 * dt
    p.x  = p.x + p.vx * dt
    p.y  = p.y + p.vy * dt
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local alpha
    if t < 0.1 then alpha = t / 0.1
    elseif t < 0.65 then alpha = 1
    else alpha = (1 - t) / 0.35 end
    p.tex:SetAlpha(math.max(0, alpha) * 0.55 * (globalFade or 1))
end

-- Create artwork and reusable texture pools.
function FX.Init(container, bar)
    local mistTex = SCB.TEX_PATH .. "frost\\Mist_Frost_01"

    S.smokes = {}
    for i, xFrac in ipairs(S.SMOKE_POSITIONS) do
        for pass = 1, 2 do
            local idx = (i - 1) * 2 + pass
            local tex = bar:CreateTexture(nil, "BACKGROUND", nil, -2)
            tex:SetTexture(mistTex)
            tex:SetSize(S.SMOKE_W_BASE, S.SMOKE_H_BASE)
            tex:SetAlpha(0)
            tex:SetBlendMode("ADD")
            tex:SetVertexColor(0.07, 0.03, 0.03)
            local xf = pass == 1 and xFrac or (xFrac + 0.06)
            S.smokes[idx] = {
                tex=tex, xFrac=xf, phase="idle", timer=0, duration=0,
                alpha=0, scaleT=0, scaleDir=(pass == 1) and 1 or -1,
                angle=rand(0, math.pi * 2),
                rotDir=(idx % 2 == 0) and 1 or -1,
                baseW=S.SMOKE_W_BASE * (pass == 1 and 1 or 0.8),
                baseH=S.SMOKE_H_BASE * (pass == 1 and 1 or 0.8),
                delay=((idx - 1) * 0.55),
                riseY=0,
            }
        end
    end

    local earthSchool = SCB.Schools.data["earth"]
    local miscTexs = {}
    if earthSchool then
        for _, t in ipairs(earthSchool.rocks  or {}) do miscTexs[#miscTexs+1] = t end
        for _, t in ipairs(earthSchool.debris or {}) do miscTexs[#miscTexs+1] = t end
    end
    local function getMisc(i)
        if #miscTexs == 0 then return SCB.TEX_PATH .. "frost\\Particle_Frost_01" end
        return miscTexs[((i-1) % #miscTexs) + 1]
    end

    S.emberParts = {}
    for i = 1, S.EMBER_COUNT do
        local typeIdx = ((i - 1) % 3) + 1
        local ptype   = S.emberTypes[typeIdx]
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(getMisc(i))
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)
        S.emberParts[i] = {
            tex=tex, ptype=ptype, typeIdx=typeIdx,
            active=false, life=0, maxLife=0,
            x=0, y=0, vx=0, vy=0, drift=0,
        }
    end

    S.sparkParts = {}
    local sparkTex = SCB.TEX_PATH .. "frost\\Particle_Frost_01"
    for i = 1, S.SPARK_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(sparkTex)
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)
        S.sparkParts[i] = {
            tex=tex, active=false, life=0, maxLife=0,
            x=0, y=0, vx=0, vy=0, baseAlpha=1,
        }
    end

    S.ambParts = {}
    for i = 1, S.AMB_COUNT do
        local tex = container:CreateTexture(nil, "BACKGROUND")
        tex:SetTexture(getMisc(i))
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)
        S.ambParts[i] = {
            tex=tex, active=false, life=0, maxLife=0,
            x=0, y=0, vx=0, vy=0,
        }
    end
end

-- Initialize a new cast and clear leftover particles.
function FX.Start(duration)
    S.castDuration  = duration or 5
    S.isActive      = true
    S.partsFading   = false
    S.emberSpawnAcc = 0
    S.sparkSpawnAcc = 0
    S.ambSpawnAcc   = 0
    local f = SCB.Bar.frameInner
    local _, cy = f:GetCenter()
    for i, m in ipairs(S.smokes) do
        m.phase = "idle" ; m.delay = (i - 1) * 0.45
        m.tex:SetAlpha(0) ; m.riseY = cy or 0
    end
    for _, p in ipairs(S.emberParts) do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.sparkParts) do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.ambParts)   do p.active = false ; p.tex:SetAlpha(0) end
end

-- Stop emission and begin the style's end-of-cast behavior.
function FX.Stop()
    S.isActive      = false
    S.partsFading   = true
    S.partsFadeT    = 0
    S.emberSpawnAcc = 0
    S.sparkSpawnAcc = 0
    S.ambSpawnAcc   = 0
    for _, m in ipairs(S.smokes) do
        if m.phase ~= "idle" then
            m.phase = "linger"  -- keep its alpha; the bar fade hides it
        end
    end
end

-- Advance residual motion and opacity after the cast ends.
function FX.UpdateFade(dt)
    if not S.partsFading then return end
    S.partsFadeT = S.partsFadeT + dt
    local gFade = 1
    for _, m in ipairs(S.smokes)     do UpdateSmoke(m, dt, gFade) end
    for _, p in ipairs(S.emberParts) do UpdateEmber(p, dt, gFade) end
    for _, p in ipairs(S.sparkParts) do UpdateSpark(p, dt, gFade) end
    for _, p in ipairs(S.ambParts)   do UpdateAmb(p,   dt, gFade) end
    if S.partsFadeT >= SCB.FX_LINGER then
        S.partsFading = false
        for _, m in ipairs(S.smokes)     do m.tex:SetAlpha(0) ; m.phase = "idle" end
        for _, p in ipairs(S.emberParts) do p.active = false  ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.sparkParts) do p.active = false  ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.ambParts)   do p.active = false  ; p.tex:SetAlpha(0) end
    end
end

-- Clear residual effects and restore owned artwork.
function FX.Reset()
    S.partsFading = false
    for _, m in ipairs(S.smokes)     do m.tex:SetAlpha(0) ; m.phase = "idle" end
    for _, p in ipairs(S.emberParts) do p.active = false  ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.sparkParts) do p.active = false  ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.ambParts)   do p.active = false  ; p.tex:SetAlpha(0) end
end

-- Advance active-cast animation and particle emission.
function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    if not S.isActive then return end
    local f = SCB.Bar.frameInner
    local _, barCY = f:GetCenter()
    if not barCY then return end

    for _, m in ipairs(S.smokes) do UpdateSmoke(m, dt, 1) end

    for _, p in ipairs(S.emberParts) do UpdateEmber(p, dt, 1) end
    S.emberSpawnAcc = S.emberSpawnAcc + dt
    if S.emberSpawnAcc >= S.EMBER_SPAWN then
        S.emberSpawnAcc = 0
        local count = math.random(3, 6)
        for _ = 1, count do SpawnEmber(frontX, barCY) end
    end

    for _, p in ipairs(S.sparkParts) do UpdateSpark(p, dt, 1) end
    S.sparkSpawnAcc = S.sparkSpawnAcc + dt
    if S.sparkSpawnAcc >= S.SPARK_SPAWN then
        S.sparkSpawnAcc = 0
        local count = math.random(2, 4)
        for _ = 1, count do SpawnSpark(frontX, barCY) end
    end

    for _, p in ipairs(S.ambParts) do UpdateAmb(p, dt, 1) end
    S.ambSpawnAcc = S.ambSpawnAcc + dt
    if S.ambSpawnAcc >= S.AMB_SPAWN then
        S.ambSpawnAcc = 0
        SpawnAmb(progress)
    end
end
