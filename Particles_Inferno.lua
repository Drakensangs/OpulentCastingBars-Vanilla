-- ============================================================
--  Opulent Casting Bars -- Particles_Inferno.lua
--  Crossfading flames, rising smoke, embers, sparks, and side emissions.
-- ============================================================

local S = {}
local FX = {}
SCB.FX            = SCB.FX or {}
SCB.FX["inferno"] = FX

-- Local math helpers.
local function rand(a, b) return a + math.random() * (b - a) end
local function rad(deg)   return deg * math.pi / 180 end
local function lerp(a, b, t) return a + (b - a) * math.max(0, math.min(t, 1)) end

-- Clamp invalid alpha values to the unit interval.
local function Clamp01(v)
    if type(v) ~= "number" or v ~= v then return 0 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

-- Rotate texture coordinates around the image center.
local function SetTexRot(tex, angle)
    local c, s = math.cos(angle), math.sin(angle)
    tex:SetTexCoord(
        0.5+(-0.5)*c-(-0.5)*s, 0.5+(-0.5)*s+(-0.5)*c,
        0.5+(-0.5)*c-( 0.5)*s, 0.5+(-0.5)*s+( 0.5)*c,
        0.5+( 0.5)*c-(-0.5)*s, 0.5+( 0.5)*s+(-0.5)*c,
        0.5+( 0.5)*c-( 0.5)*s, 0.5+( 0.5)*s+( 0.5)*c
    )
end

-- Flame sequence, crossfade timing, and background slot tuning.
S.INFERNO_SEQ = {1,2,3,4,5,6,7,8,9,10,11,12,11,10,9,8,7,6,5,4,3,2}
S.INFERNO_SEQ_LEN = #S.INFERNO_SEQ
S.INFERNO_SLOT_COUNT = 3
S.INFERNO_FRAME_DUR = 0.20
S.INFERNO_XFADE_DUR = 0.18
S.INFERNO_SLOT_ALPHA = 0.32
S.INFERNO_RAND_COUNT = 3
S.INFERNO_RAND_FADE_IN = 0.50
S.INFERNO_RAND_FADE_OUT = 0.70
S.INFERNO_RAND_HOLD_MIN = 0.35
S.INFERNO_RAND_HOLD_MAX = 1.1
S.INFERNO_RAND_ALPHA = 0.30
S.INFERNO_LIGHT_BG_COUNT = 3
S.INFERNO_LIGHT_BG_ALPHA = 0.18
S.INFERNO_LIGHT_BG_FADE_IN = 0.45
S.INFERNO_LIGHT_BG_FADE_OUT = 0.55
S.INFERNO_LIGHT_BG_HOLD_MIN = 0.9
S.INFERNO_LIGHT_BG_HOLD_MAX = 2.8

-- Smoke size, opacity, lifetime, and distribution.
S.SMOKE_W_BASE = 310
S.SMOKE_H_BASE = 155
S.SMOKE_ALPHA_MAX = 0.40
S.SMOKE_SCALE_MIN = 0.8
S.SMOKE_SCALE_MAX = 1.5
S.SMOKE_FADE_IN = 1.8
S.SMOKE_HOLD_MIN = 1.2
S.SMOKE_HOLD_MAX = 2.8
S.SMOKE_FADE_OUT = 1.5
S.SMOKE_ROT_SPEED = 0.03
S.SMOKE_POSITIONS = {1/8, 2/8, 3/8, 4/8, 5/8, 6/8}

-- Front ember pool and emission tuning.
S.EMBER_COUNT = 130
S.EMBER_SPAWN = 0.016

S.emberTypes = {
    { sizeMin=8,  sizeMax=18, speedMin=22, speedMax=65,  lifeMin=0.9, lifeMax=2.0, gravity=5,  spread=170, driftX=0.6 },
    { sizeMin=4,  sizeMax=10, speedMin=75, speedMax=180, lifeMin=0.3, lifeMax=0.8, gravity=11, spread=100, driftX=0.0 },
    { sizeMin=5,  sizeMax=15, speedMin=38, speedMax=95,  lifeMin=0.7, lifeMax=1.5, gravity=16, spread=130, driftX=0.4 },
}

-- Ember palette.
S.EMBER_COLORS = {
    { 1.0, 0.30, 0.01 },
    { 1.0, 0.10, 0.00 },
    { 1.0, 0.50, 0.03 },
    { 1.0, 0.65, 0.10 },
}

-- Pixel spark pool and motion tuning.
S.SPARK_COUNT = 75
S.SPARK_SPAWN = 0.025
S.SPARK_SIZE_MIN = 3
S.SPARK_SIZE_MAX = 8
S.SPARK_LIFE_MIN = 0.4
S.SPARK_LIFE_MAX = 1.3
S.SPARK_SPEED_MIN = 35
S.SPARK_SPEED_MAX = 115
S.SPARK_GRAVITY = 22

S.SPARK_COLORS = {
    { 1.0, 0.95, 0.15, 1.0  },
    { 1.0, 0.75, 0.05, 0.90 },
    { 1.0, 0.98, 0.35, 0.65 },
    { 1.0, 0.60, 0.02, 0.75 },
    { 1.0, 1.00, 0.55, 0.50 },
    { 1.0, 0.40, 0.00, 0.85 },
}

-- Ambient pool and emission tuning.
S.AMB_COUNT = 60
S.AMB_SPAWN = 0.055
S.OUTSIDE_COUNT = 30
S.OUTSIDE_SPAWN = 0.040

S.castDuration = 5

-- Cast and particle state.
S.isActive = false
S.partsFading = false
S.partsFadeT = 0
S.smokes = {}
S.emberParts = {}
S.sparkParts = {}
S.ambParts = {}
S.outsideParts = {}
S.emberSpawnAcc = 0
S.sparkSpawnAcc = 0
S.ambSpawnAcc = 0
S.outsideSpawnAcc = 0

S.infernoBgPaths = {}
S.infernoSlots = {}
S.infernoRandSlots = {}
S.infernoLightBgSlots = {}

-- Shared reveal mask; padded bounds keep its transparent border outside the art.
S.infernoLightMask = nil

-- Crop a flame host and its texture to the revealed width.
local function revealHost(host, tex, revealW, uRight)
    if not host then return end
    host:SetWidth(revealW)
    if tex then
        tex:SetWidth(revealW)
        tex:SetTexCoord(0, uRight, 0, 1)
    end
    -- Hosts are hidden only when created; show each one once.
    if not host.ocbShown then
        host.ocbShown = true
        host:Show()
    end
end

-- Advance inferno mask.
local function UpdateInfernoMask(progress)
    local barW = (SCB.Config and SCB.Config:Get("barWidth")) or 400
    local revealW = math.max(1, barW * progress)
    local uRight  = revealW / barW

    local mask = S.infernoLightMask
    if mask then
        local f = SCB.Bar.frame
        local padX = revealW * 2 / 252
        local padY = f:GetHeight() * 2 / 252
        mask:SetPoint("TOPLEFT", f, "TOPLEFT", -padX, padY)
        mask:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -padX, -padY)
        mask:SetWidth(revealW + 2 * padX)
        SCB.SetRevealMaskProgress(mask, progress)
    end

    for _, slot in ipairs(S.infernoSlots or {}) do
        revealHost(slot.hostCur,  slot.texCur,  revealW, uRight)
        revealHost(slot.hostNext, slot.texNext, revealW, uRight)
    end
    for _, slot in ipairs(S.infernoRandSlots or {}) do
        revealHost(slot.host, slot.tex, revealW, uRight)
    end
    for _, slot in ipairs(S.infernoLightBgSlots or {}) do
        revealHost(slot.host, slot.tex, revealW, uRight)
    end
end

-- Advance inferno background.
local function UpdateInfernoBackground(dt, globalFade)
    local gf = globalFade or 1

    for _, slot in ipairs(S.infernoSlots) do
        slot.timer = slot.timer + dt
        if slot.timer >= S.INFERNO_FRAME_DUR then
            slot.timer   = slot.timer - S.INFERNO_FRAME_DUR
            slot.seqPos  = (slot.seqPos % S.INFERNO_SEQ_LEN) + 1
            slot.texCur, slot.texNext = slot.texNext, slot.texCur
        end
        local xfStart = S.INFERNO_FRAME_DUR - S.INFERNO_XFADE_DUR
        if slot.timer >= xfStart then
            local xfT    = math.min((slot.timer - xfStart) / S.INFERNO_XFADE_DUR, 1)
            local nxtPos = (slot.seqPos % S.INFERNO_SEQ_LEN) + 1
            local nextPath = S.infernoBgPaths[S.INFERNO_SEQ[nxtPos]]
            if slot.texNext._ocbPath ~= nextPath then
                slot.texNext:SetTexture(nextPath)
                slot.texNext._ocbPath = nextPath
            end
            slot.texCur:SetAlpha(Clamp01((1 - xfT) * S.INFERNO_SLOT_ALPHA * gf))
            slot.texNext:SetAlpha(Clamp01(xfT * S.INFERNO_SLOT_ALPHA * gf))
        else
            slot.texCur:SetAlpha(Clamp01(S.INFERNO_SLOT_ALPHA * gf))
            slot.texNext:SetAlpha(0)
        end
    end

    for _, slot in ipairs(S.infernoRandSlots) do
        slot.timer = slot.timer + dt
        if slot.phase == "fadein" then
            local a = math.min(slot.timer / S.INFERNO_RAND_FADE_IN, 1)
            slot.tex:SetAlpha(Clamp01(a * S.INFERNO_RAND_ALPHA * gf))
            if slot.timer >= S.INFERNO_RAND_FADE_IN then
                slot.phase = "hold" ; slot.timer = 0
                slot.duration = rand(S.INFERNO_RAND_HOLD_MIN, S.INFERNO_RAND_HOLD_MAX)
            end
        elseif slot.phase == "hold" then
            slot.tex:SetAlpha(Clamp01(S.INFERNO_RAND_ALPHA * gf))
            if slot.timer >= slot.duration then
                slot.phase = "fadeout" ; slot.timer = 0
            end
        elseif slot.phase == "fadeout" then
            local a = math.max(0, 1 - slot.timer / S.INFERNO_RAND_FADE_OUT)
            slot.tex:SetAlpha(Clamp01(a * S.INFERNO_RAND_ALPHA * gf))
            if slot.timer >= S.INFERNO_RAND_FADE_OUT then
                local idx = math.random(12)
                slot.tex:SetTexture(S.infernoBgPaths[idx])
                slot.phase = "fadein" ; slot.timer = 0
            end
        end
    end

    for _, slot in ipairs(S.infernoLightBgSlots) do
        slot.timer = slot.timer + dt
        if slot.phase == "fadein" then
            local a = math.min(slot.timer / S.INFERNO_LIGHT_BG_FADE_IN, 1)
            slot.tex:SetAlpha(Clamp01(a * S.INFERNO_LIGHT_BG_ALPHA * gf))
            if slot.timer >= S.INFERNO_LIGHT_BG_FADE_IN then
                slot.phase = "hold" ; slot.timer = 0
                slot.duration = rand(S.INFERNO_LIGHT_BG_HOLD_MIN, S.INFERNO_LIGHT_BG_HOLD_MAX)
            end
        elseif slot.phase == "hold" then
            slot.tex:SetAlpha(Clamp01(S.INFERNO_LIGHT_BG_ALPHA * gf))
            if slot.timer >= slot.duration then
                slot.phase = "fadeout" ; slot.timer = 0
            end
        elseif slot.phase == "fadeout" then
            local a = math.max(0, 1 - slot.timer / S.INFERNO_LIGHT_BG_FADE_OUT)
            slot.tex:SetAlpha(Clamp01(a * S.INFERNO_LIGHT_BG_ALPHA * gf))
            if slot.timer >= S.INFERNO_LIGHT_BG_FADE_OUT then
                slot.tex:SetTexture(S.infernoBgPaths[math.random(12)])
                slot.phase = "fadein" ; slot.timer = 0
            end
        end
    end
end

-- Reset inferno background.
local function ResetInfernoBackground()
    local step = math.floor(S.INFERNO_SEQ_LEN / S.INFERNO_SLOT_COUNT)
    for i, slot in ipairs(S.infernoSlots) do
        slot.seqPos = ((i - 1) * step) % S.INFERNO_SEQ_LEN + 1
        slot.timer  = 0
        slot.texCur:SetTexture(S.infernoBgPaths[S.INFERNO_SEQ[slot.seqPos]])
        slot.texCur._ocbPath = S.infernoBgPaths[S.INFERNO_SEQ[slot.seqPos]]
        slot.texCur:SetAlpha(S.INFERNO_SLOT_ALPHA)
        slot.texNext:SetAlpha(0)
    end
    for i, slot in ipairs(S.infernoRandSlots) do
        slot.phase    = "fadein"
        slot.timer    = (i - 1) * (S.INFERNO_RAND_HOLD_MIN * 0.8)
        slot.tex:SetTexture(S.infernoBgPaths[math.random(12)])
        slot.tex:SetAlpha(0)
    end
    for i, slot in ipairs(S.infernoLightBgSlots) do
        slot.phase    = "fadein"
        slot.timer    = (i - 1) * 0.7
        slot.duration = rand(S.INFERNO_LIGHT_BG_HOLD_MIN, S.INFERNO_LIGHT_BG_HOLD_MAX)
        slot.tex:SetTexture(S.infernoBgPaths[math.random(12)])
        slot.tex:SetAlpha(0)
    end
end

-- Hide inferno background.
local function HideInfernoBackground()
    for _, slot in ipairs(S.infernoSlots) do
        slot.texCur:SetAlpha(0) ; slot.texNext:SetAlpha(0)
    end
    for _, slot in ipairs(S.infernoRandSlots)    do slot.tex:SetAlpha(0) end
    for _, slot in ipairs(S.infernoLightBgSlots) do slot.tex:SetAlpha(0) end
end

-- Spawn smoke.
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

-- Advance smoke.
local function UpdateSmoke(m, dt, globalFade)
    if m.delay and m.delay > 0 then m.delay = m.delay - dt ; return end
    if m.phase == "idle" then
        if S.isActive then SpawnSmoke(m) end
        return
    end

    local f = SCB.Bar.frameInner
    local cx, cy = f:GetCenter()
    if cx then
        local barW = f:GetWidth()
        local x    = cx - barW * 0.5 + barW * m.xFrac
        m.riseY = (m.riseY or cy) + 12 * dt
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
        m.tex:SetAlpha(Clamp01(math.max(0, m.alpha) * gf))
        if m.timer >= m.duration then
            m.phase = "hold" ; m.timer = 0
            m.duration = rand(S.SMOKE_HOLD_MIN, S.SMOKE_HOLD_MAX)
        end
    elseif m.phase == "hold" then
        local pulse = math.sin(m.scaleT * 1.5) * 0.04
        m.tex:SetAlpha(Clamp01(math.max(0, S.SMOKE_ALPHA_MAX + pulse) * gf))
        if m.timer >= m.duration then
            m.phase = "fadeout" ; m.timer = 0 ; m.duration = S.SMOKE_FADE_OUT
        end
    elseif m.phase == "fadeout" then
        m.alpha = (1 - m.timer / m.duration) * S.SMOKE_ALPHA_MAX
        m.tex:SetAlpha(Clamp01(math.max(0, m.alpha) * gf))
        if m.timer >= m.duration then
            m.tex:SetAlpha(0) ; m.phase = "idle"
        end
    end
end

-- Spawn ember.
local function SpawnEmber(wx, wy)
    local roll    = math.random(10)
    local typeIdx = roll <= 4 and 1 or (roll <= 7 and 3 or 2)
    local ptype   = S.emberTypes[typeIdx]
    local col     = S.EMBER_COLORS[math.random(#S.EMBER_COLORS)]

    for _, p in ipairs(S.emberParts) do
        if not p.active and p.typeIdx == typeIdx then
            local tCast = math.max(0, math.min((S.castDuration - 2) / 3, 1))
            local speed = rand(lerp(ptype.speedMax * 0.5, ptype.speedMin, tCast),
                               lerp(ptype.speedMax, ptype.speedMax * 0.8, tCast))
            local angle = rad(90 + rand(-ptype.spread * 0.5, ptype.spread * 0.5))
            local size  = rand(ptype.sizeMin, ptype.sizeMax)
            p.active  = true ; p.life = 0
            p.maxLife = rand(ptype.lifeMin, ptype.lifeMax)
            p.x       = wx + rand(-8, 8)
            p.y       = wy + rand(-10, 10)
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

-- Advance ember.
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
    p.tex:SetAlpha(Clamp01(alpha * 0.9 * (globalFade or 1)))
end

-- Spawn spark.
local function SpawnSpark(wx, wy)
    local col = S.SPARK_COLORS[math.random(#S.SPARK_COLORS)]
    for _, p in ipairs(S.sparkParts) do
        if not p.active then
            local angle = rad(rand(25, 155))
            local speed = rand(S.SPARK_SPEED_MIN, S.SPARK_SPEED_MAX)
            p.active    = true ; p.life = 0
            p.maxLife   = rand(S.SPARK_LIFE_MIN, S.SPARK_LIFE_MAX)
            p.x         = wx + rand(-5, 5)
            p.y         = wy + rand(-8, 8)
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

-- Advance spark.
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
    p.tex:SetAlpha(Clamp01(math.max(0, env) * p.baseAlpha * (globalFade or 1)))
end

-- Spawn an ambient particle within the revealed bar.
local function SpawnAmb(progress)
    local f = SCB.Bar.frame
    local cx, cy = f:GetCenter()
    if not cx then return end
    local barW, barH = f:GetWidth(), f:GetHeight()

    for _, p in ipairs(S.ambParts) do
        if not p.active then
            local fillEdge = (progress - 0.5) * barW
            local xOffset = rand(-barW * 0.5, math.max(-barW * 0.5 + 4, fillEdge))
            local yOffset = rand(-barH * 0.40, barH * 0.40)
            local wx, wy  = cx + xOffset, cy + yOffset
            local dirX    = xOffset > 0 and 1 or -1
            local angle   = rad(rand(55, 125)) * (yOffset > 0 and 1 or -1)
            local speed   = rand(18, 55)
            local col     = S.EMBER_COLORS[math.random(#S.EMBER_COLORS)]

            p.active  = true ; p.life = 0
            p.maxLife = rand(1.0, 2.5)
            p.x       = wx ; p.y = wy
            p.vx      = dirX * rand(5, 25)
            p.vy      = math.sin(angle) * speed
            p.tex:SetVertexColor(col[1], col[2], col[3])
            local size = rand(5, 15)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(0)
            return
        end
    end
end

-- Advance amb.
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
    p.tex:SetAlpha(Clamp01(math.max(0, alpha) * 0.60 * (globalFade or 1)))
end

-- Spawn outside.
local function SpawnOutside()
    local f = SCB.Bar.frame
    local cx, cy = f:GetCenter()
    if not cx then return end
    local barW, barH = f:GetWidth(), f:GetHeight()
    local col = S.EMBER_COLORS[math.random(#S.EMBER_COLORS)]

    for _, p in ipairs(S.outsideParts) do
        if not p.active then
            local edge = math.random(4)
            local wx, wy, baseAng
            if edge == 1 then
                wx = cx + rand(-barW * 0.5, barW * 0.5)
                wy = cy + barH * 0.5 + rand(2, 8)
                baseAng = rand(55, 125)
            elseif edge == 2 then
                wx = cx + rand(-barW * 0.5, barW * 0.5)
                wy = cy - barH * 0.5 - rand(2, 8)
                baseAng = rand(60, 120)
            elseif edge == 3 then
                wx = cx - barW * 0.5 - rand(2, 14)
                wy = cy + rand(-barH * 0.5, barH * 0.5)
                baseAng = rand(60, 120)
            else
                wx = cx + barW * 0.5 + rand(2, 14)
                wy = cy + rand(-barH * 0.5, barH * 0.5)
                baseAng = rand(60, 120)
            end
            local angle = rad(baseAng + rand(-15, 15))
            local speed = rand(45, 130)

            p.active  = true ; p.life = 0
            p.maxLife = rand(0.6, 1.9)
            p.x       = wx ; p.y = wy
            p.vx      = math.cos(angle) * speed
            p.vy      = math.sin(angle) * speed
            p.drift   = rand(-18, 18)
            p.tex:SetVertexColor(col[1], col[2], col[3])
            local size = rand(5, 15)
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(0)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            return
        end
    end
end

-- Advance outside.
local function UpdateOutside(p, dt, globalFade)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    p.vy = p.vy - 7 * dt
    p.vx = p.vx + p.drift * dt * (1 - t)
    p.x  = p.x + p.vx * dt
    p.y  = p.y + p.vy * dt
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local alpha
    if t < 0.12 then alpha = t / 0.12
    elseif t < 0.60 then alpha = 1
    else alpha = (1 - t) / 0.40 end
    p.tex:SetAlpha(Clamp01(math.max(0, alpha) * 0.85 * (globalFade or 1)))
end

-- Create texture hosts, animation slots, and particle pools.
function FX.Init(container, bar)
    local texPath = SCB.TEX_PATH
    local f       = SCB.Bar.frame

    S.infernoBgPaths = {}
    for i = 1, 12 do
        S.infernoBgPaths[i] = texPath .. string.format("inferno\\Fire_Inferno_%02d", i)
    end

    local _underlay = SCB.Bar and SCB.Bar.bgUnderlayHost or f
    S.infernoLightMask = SCB.NewRevealMask(_underlay)

    local function makeHostTex(f)
        local host = CreateFrame("Frame", nil, _underlay)
        host:SetPoint("TOPLEFT",    f, "TOPLEFT",    0, 0)
        host:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        host:SetWidth(1)
        host:Hide()
        local t = host:CreateTexture(nil, "BACKGROUND")
        SCB.AttachMask(t, S.infernoLightMask)
        t:SetPoint("TOPLEFT",    host, "TOPLEFT")
        t:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT")
        t:SetWidth(1)
        t:SetBlendMode("ADD")
        t:SetAlpha(0)
        return host, t
    end

    S.infernoSlots = {}
    for i = 1, S.INFERNO_SLOT_COUNT do
        local hostCur,  texCur  = makeHostTex(f)
        local hostNext, texNext = makeHostTex(f)
        S.infernoSlots[i] = {
            texCur  = texCur,  hostCur  = hostCur,
            texNext = texNext, hostNext = hostNext,
            seqPos  = 1,
            timer   = 0,
        }
    end

    S.infernoRandSlots = {}
    for i = 1, S.INFERNO_RAND_COUNT do
        local host, tex = makeHostTex(f)
        tex:SetTexture(S.infernoBgPaths[math.random(12)])
        S.infernoRandSlots[i] = {
            tex = tex, host = host,
            phase    = "fadein",
            timer    = (i - 1) * 0.45,
            duration = rand(S.INFERNO_RAND_HOLD_MIN, S.INFERNO_RAND_HOLD_MAX),
        }
    end

    S.infernoLightBgSlots = {}
    for i = 1, S.INFERNO_LIGHT_BG_COUNT do
        local host, tex = makeHostTex(f)
        tex:SetTexture(S.infernoBgPaths[math.random(12)])
        S.infernoLightBgSlots[i] = {
            tex = tex, host = host,
            phase    = "fadein",
            timer    = (i - 1) * 0.7,
            duration = rand(S.INFERNO_LIGHT_BG_HOLD_MIN, S.INFERNO_LIGHT_BG_HOLD_MAX),
        }
    end

    UpdateInfernoMask(0)

    S.smokes = {}
    local mistTex = texPath .. "frost\\Mist_Frost_01"
    for i, xFrac in ipairs(S.SMOKE_POSITIONS) do
        for pass = 1, 2 do
            local idx = (i - 1) * 2 + pass
            local tex = bar:CreateTexture(nil, "BACKGROUND", nil, -2)
            tex:SetTexture(mistTex)
            tex:SetSize(S.SMOKE_W_BASE, S.SMOKE_H_BASE)
            tex:SetAlpha(0)
            tex:SetBlendMode("ADD")
            tex:SetVertexColor(0.10, 0.03, 0.01)
            local xf = pass == 1 and xFrac or math.min(xFrac + 0.04, 0.98)
            S.smokes[idx] = {
                tex      = tex,
                xFrac    = xf,
                phase    = "idle",
                timer    = 0,
                duration = 0,
                alpha    = 0,
                scaleT   = 0,
                scaleDir = (pass == 1) and 1 or -1,
                angle    = rand(0, math.pi * 2),
                rotDir   = (idx % 2 == 0) and 1 or -1,
                baseW    = S.SMOKE_W_BASE * (pass == 1 and 1.0 or 0.85),
                baseH    = S.SMOKE_H_BASE * (pass == 1 and 1.0 or 0.85),
                delay    = (idx - 1) * 0.38,
                riseY    = 0,
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
        if #miscTexs == 0 then return texPath .. "frost\\Particle_Frost_01" end
        return miscTexs[((i - 1) % #miscTexs) + 1]
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
    local sparkTex = texPath .. "frost\\Particle_Frost_01"
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

    S.outsideParts = {}
    for i = 1, S.OUTSIDE_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(getMisc(i))
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)
        S.outsideParts[i] = {
            tex=tex, active=false, life=0, maxLife=0,
            x=0, y=0, vx=0, vy=0, drift=0,
        }
    end
end

-- Start a cast and reset effect timing.
function FX.Start(duration)
    S.castDuration    = duration or 5
    S.isActive        = true
    S.partsFading     = false
    S.emberSpawnAcc   = 0
    S.sparkSpawnAcc   = 0
    S.ambSpawnAcc     = 0
    S.outsideSpawnAcc = 0

    local bar = SCB.Bar
    UpdateInfernoMask(0)

    local fi = bar.frameInner
    local _, cy = fi:GetCenter()
    for i, m in ipairs(S.smokes) do
        m.phase = "idle" ; m.delay = (i - 1) * 0.38
        m.tex:SetAlpha(0) ; m.riseY = cy or 0
    end

    for _, p in ipairs(S.emberParts)   do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.sparkParts)   do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.ambParts)     do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.outsideParts) do p.active = false ; p.tex:SetAlpha(0) end

    ResetInfernoBackground()
end

-- Stop emission and begin the completion fade.
function FX.Stop(success)
    if success and not SCB.Bar.isChannel then UpdateInfernoMask(1) end
    S.isActive        = false
    S.partsFading     = true
    S.partsFadeT      = 0
    S.emberSpawnAcc   = 0
    S.sparkSpawnAcc   = 0
    S.ambSpawnAcc     = 0
    S.outsideSpawnAcc = 0
    for _, m in ipairs(S.smokes) do
        if m.phase ~= "idle" then
            m.phase = "linger"  -- keep its alpha; the bar fade hides it
        end
    end
end

-- Advance existing effects during the stop fade.
function FX.UpdateFade(dt)
    if not S.partsFading then return end
    S.partsFadeT = S.partsFadeT + dt
    local gFade = 1
    UpdateInfernoBackground(dt, gFade)
    for _, m in ipairs(S.smokes)       do UpdateSmoke(m,   dt, gFade) end
    for _, p in ipairs(S.emberParts)   do UpdateEmber(p,   dt, gFade) end
    for _, p in ipairs(S.sparkParts)   do UpdateSpark(p,   dt, gFade) end
    for _, p in ipairs(S.ambParts)     do UpdateAmb(p,     dt, gFade) end
    for _, p in ipairs(S.outsideParts) do UpdateOutside(p, dt, gFade) end
    if S.partsFadeT >= SCB.FX_LINGER then
        S.partsFading = false
        HideInfernoBackground()
        for _, m in ipairs(S.smokes)       do m.tex:SetAlpha(0) ; m.phase = "idle" end
        for _, p in ipairs(S.emberParts)   do p.active = false  ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.sparkParts)   do p.active = false  ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.ambParts)     do p.active = false  ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.outsideParts) do p.active = false  ; p.tex:SetAlpha(0) end
    end
end

-- Clear visible effects and pending fade state.
function FX.Reset()
    S.isActive    = false
    S.partsFading = false
    for _, m in ipairs(S.smokes)       do m.tex:SetAlpha(0) ; m.phase = "idle" end
    for _, p in ipairs(S.emberParts)   do p.active = false  ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.sparkParts)   do p.active = false  ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.ambParts)     do p.active = false  ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.outsideParts) do p.active = false  ; p.tex:SetAlpha(0) end
    HideInfernoBackground()
end

-- Advance active-cast effects and emission.
function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    if not S.isActive then return end
    local fi = SCB.Bar.frameInner
    local _, barCY = fi:GetCenter()
    if not barCY then return end

    UpdateInfernoBackground(dt, 1)
    UpdateInfernoMask(progress)

    for _, m in ipairs(S.smokes) do UpdateSmoke(m, dt, 1) end

    for _, p in ipairs(S.emberParts) do UpdateEmber(p, dt, 1) end
    S.emberSpawnAcc = S.emberSpawnAcc + dt
    if S.emberSpawnAcc >= S.EMBER_SPAWN then
        S.emberSpawnAcc = 0
        local count = math.random(4, 8)
        for _ = 1, count do SpawnEmber(frontX, barCY) end
    end

    for _, p in ipairs(S.sparkParts) do UpdateSpark(p, dt, 1) end
    S.sparkSpawnAcc = S.sparkSpawnAcc + dt
    if S.sparkSpawnAcc >= S.SPARK_SPAWN then
        S.sparkSpawnAcc = 0
        local count = math.random(3, 6)
        for _ = 1, count do SpawnSpark(frontX, barCY) end
    end

    for _, p in ipairs(S.ambParts) do UpdateAmb(p, dt, 1) end
    S.ambSpawnAcc = S.ambSpawnAcc + dt
    if S.ambSpawnAcc >= S.AMB_SPAWN then
        S.ambSpawnAcc = 0
        SpawnAmb(progress)
    end

    for _, p in ipairs(S.outsideParts) do UpdateOutside(p, dt, 1) end
    S.outsideSpawnAcc = S.outsideSpawnAcc + dt
    if S.outsideSpawnAcc >= S.OUTSIDE_SPAWN then
        S.outsideSpawnAcc = 0
        SpawnOutside()
    end
end
