-- ============================================================
--  Opulent Casting Bars -- Particles_Mistweaver.lua
--  Jade mist and drifting leaves.
--  Blue-green glow and debris follow the fill front.
--  (The frame light is drawn by Bar.lua from the style's frameLight.)
-- ============================================================

local S = {}  -- Shared effect state and tuning.
local FX = {}
SCB.FX               = SCB.FX or {}
SCB.FX["mistweaver"] = FX

local function rand(a, b) return a + math.random() * (b - a) end
local function rad(deg)   return deg * math.pi / 180 end
local function lerp(a, b, t) return a + (b - a) * math.max(0, math.min(t, 1)) end
S.pi2 = math.pi * 2

S.MW_R = 0x36/255 ; S.MW_G = 0xFB/255 ; S.MW_B = 0xB6/255

-- Ambient mist timing, size and placement.
S.MIST_W_BASE = 338
S.MIST_H_BASE = 169
S.MIST_ALPHA_MAX = 0.50
S.MIST_SCALE_MIN = 0.75
S.MIST_SCALE_MAX = 1.30
S.MIST_FADE_IN = 1.8
S.MIST_HOLD_MIN = 1.2
S.MIST_HOLD_MAX = 2.5
S.MIST_FADE_OUT = 1.5
S.MIST_ROT_SPEED = 0.04
S.MIST_POSITIONS = { 2/8, 4/8, 6/8 }

-- Fill-front glow tuning.
S.GLOW_COUNT = 60
S.GLOW_SPAWN_RATE = 0.02
S.GLOW_STOP_AT = 0.87
S.GLOW_ALPHA = 0.55
S.GLOW_SIZE_MIN = 4
S.GLOW_SIZE_MAX = 9
S.GLOW_LIFE_MIN = 0.10
S.GLOW_LIFE_MAX = 0.20

-- Fill-front debris physics.
S.EMBER_COUNT = 60
S.EMBER_SPAWN = 0.03
S.emberTypes = {
    { sizeMin=8,  sizeMax=14, speedMin=25, speedMax=60,  lifeMin=0.8, lifeMax=1.6, gravity=8,  spread=140, driftX=0.4 },
    { sizeMin=4,  sizeMax=8,  speedMin=80, speedMax=160, lifeMin=0.3, lifeMax=0.7, gravity=15, spread=80,  driftX=0.0 },
    { sizeMin=6,  sizeMax=12, speedMin=40, speedMax=90,  lifeMin=0.6, lifeMax=1.2, gravity=20, spread=100, driftX=0.2 },
}

-- Drifting bar leaves and fill-front leaf tuning.
S.LEAF_COUNT = 14
S.LEAF_SPAWN_RATE = 0.18
S.LEAF_FLOW_SPEED_MIN = 35
S.LEAF_FLOW_SPEED_MAX = 85
S.LEAF_FLOW_ANGLE_MIN = -20
S.LEAF_FLOW_ANGLE_MAX = 20

S.FRONT_LEAF_COUNT = 8
S.FRONT_SPAWN_RATE = 0.09
S.FRONT_SIZE_MIN = 7
S.FRONT_SIZE_MAX = 13
S.FRONT_SPEED_MIN = 25
S.FRONT_SPEED_MAX = 70
S.FRONT_LIFE_MIN = 0.40
S.FRONT_LIFE_MAX = 0.90
S.FRONT_ALPHA = 0.75
S.FRONT_GRAVITY = 18
S.LEAF_ROT_MIN = 0.8
S.LEAF_ROT_MAX = 2.6

S.castDuration = 5
S.isActive = false
S.partsFading = false
S.partsFadeT = 0

S.mists = {}
S.glowParts = {}
S.emberParts = {}
S.leaves = {}
S.frontLeaves = {}

S.glowAcc = 0
S.emberAcc = 0
S.leafAcc = 0
S.frontLeafAcc = 0

-- Rotate UVs inside the quad (mist quads are not square, so the native
-- quad rotation would change their shape).
local function SetTextureRotation(tex, angle)
    local c, s = math.cos(angle), math.sin(angle)
    tex:SetTexCoord(
        0.5 + (-0.5)*c - (-0.5)*s,  0.5 + (-0.5)*s + (-0.5)*c,
        0.5 + (-0.5)*c - ( 0.5)*s,  0.5 + (-0.5)*s + ( 0.5)*c,
        0.5 + ( 0.5)*c - (-0.5)*s,  0.5 + ( 0.5)*s + (-0.5)*c,
        0.5 + ( 0.5)*c - ( 0.5)*s,  0.5 + ( 0.5)*s + ( 0.5)*c
    )
end

-- Ambient mist spawning and animation.
local function SpawnMist(m)
    local scale = rand(S.MIST_SCALE_MIN, S.MIST_SCALE_MAX)
    m.baseW = S.MIST_W_BASE * scale
    m.baseH = S.MIST_H_BASE * scale
    m.tex:SetSize(m.baseW, m.baseH)
    m.tex:SetAlpha(0)
    m.phase = "fadein"
    m.timer = 0
    m.duration = S.MIST_FADE_IN
    m.alpha = 0
    m.scaleT = 0
    m.scaleDir = math.random(2) == 1 and 1 or -1
end

local function UpdateMist(m, dt)
    if m.delay and m.delay > 0 then m.delay = m.delay - dt ; return end
    if m.phase == "idle" then if S.isActive then SpawnMist(m) end return end

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
    m.angle  = m.angle + S.MIST_ROT_SPEED * m.rotDir * dt

    local scalePulse = 1 + math.sin(m.scaleT * 0.45 * m.scaleDir) * 0.09
    m.tex:SetSize(m.baseW * scalePulse, m.baseH * scalePulse)
    SetTextureRotation(m.tex, m.angle)

    if m.phase == "fadein" then
        m.alpha = math.min(m.timer / m.duration, 1) * S.MIST_ALPHA_MAX
        local pulse = math.sin(m.scaleT * 1.8) * 0.035
        m.tex:SetAlpha(math.max(0, m.alpha + pulse))
        if m.timer >= m.duration then
            m.phase = "hold" ; m.timer = 0 ; m.duration = rand(S.MIST_HOLD_MIN, S.MIST_HOLD_MAX)
        end
    elseif m.phase == "hold" then
        local pulse = math.sin(m.scaleT * 1.8) * 0.06
        m.tex:SetAlpha(math.max(0, S.MIST_ALPHA_MAX + pulse))
        if m.timer >= m.duration then m.phase = "fadeout" ; m.timer = 0 ; m.duration = S.MIST_FADE_OUT end
    elseif m.phase == "fadeout" then
        m.alpha = (1 - m.timer / m.duration) * S.MIST_ALPHA_MAX
        m.tex:SetAlpha(math.max(0, m.alpha))
        if m.timer >= m.duration then m.tex:SetAlpha(0) ; m.phase = "idle" end
    end
end

-- Fill-front glow spawning and motion.
local function SpawnGlow(frontX, cy, barH)
    for _, p in ipairs(S.glowParts) do
        if not p.active then
            local spread = math.min(barH * 0.25, 10)
            p.active  = true ; p.life = 0
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

-- Fill-front debris spawning and motion.
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

-- Drifting leaves across the filled region.
local function SpawnLeaf(barLX, barRX, barCY, barH)
    for _, lf in ipairs(S.leaves) do
        if not lf.active then
            local angle    = rad(rand(S.LEAF_FLOW_ANGLE_MIN, S.LEAF_FLOW_ANGLE_MAX))
            local speed    = rand(S.LEAF_FLOW_SPEED_MIN, S.LEAF_FLOW_SPEED_MAX)
            local size     = rand(S.FRONT_SIZE_MIN, S.FRONT_SIZE_MAX)
            local rotSpeed = rand(S.LEAF_ROT_MIN, S.LEAF_ROT_MAX) * (math.random(2) == 1 and 1 or -1)
            lf.active   = true
            lf.life     = 0
            lf.maxLife  = rand(S.FRONT_LIFE_MIN, S.FRONT_LIFE_MAX)
            lf.x        = barLX + rand(-8, 4)
            lf.y        = barCY + rand(-barH * 0.30, barH * 0.30)
            lf.vx       = math.cos(angle) * speed
            lf.vy       = math.sin(angle) * speed
            lf.rot      = rand(0, S.pi2)
            lf.rotSpeed = rotSpeed
            lf.size     = size
            lf.deadX    = barRX + size * 1.5
            lf.tex:SetSize(size, size)
            lf.tex:SetAlpha(S.FRONT_ALPHA)
            lf.tex:ClearAllPoints()
            lf.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", lf.x, lf.y)
            return
        end
    end
end

local function UpdateLeaf(lf, dt, globalFade)
    if not lf.active then return end
    lf.life = lf.life + dt
    local t = lf.life / lf.maxLife
    if t >= 1 or lf.x >= lf.deadX then
        lf.active = false ; lf.tex:SetAlpha(0) ; return
    end
    lf.vy  = lf.vy - S.FRONT_GRAVITY * dt
    lf.x   = lf.x + lf.vx * dt
    lf.y   = lf.y + lf.vy * dt
    lf.rot = lf.rot + lf.rotSpeed * dt
    local alpha = (t < 0.55 and 1 or math.max(0, (1 - t) / 0.45)) * S.FRONT_ALPHA * (globalFade or 1)
    lf.tex:SetAlpha(alpha)
    lf.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", lf.x, lf.y)
    lf.tex:SetRotation(lf.rot)
end

local function SpawnFrontLeaf(frontX, barCY, barH)
    for _, lf in ipairs(S.frontLeaves) do
        if not lf.active then
            local angle    = rad(rand(40, 140))
            local speed    = rand(S.FRONT_SPEED_MIN, S.FRONT_SPEED_MAX)
            local size     = rand(S.FRONT_SIZE_MIN, S.FRONT_SIZE_MAX)
            local rotSpeed = rand(S.LEAF_ROT_MIN, S.LEAF_ROT_MAX) * (math.random(2) == 1 and 1 or -1)
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

local function UpdateFrontLeaf(lf, dt, globalFade)
    if not lf.active then return end
    lf.life = lf.life + dt
    local t = lf.life / lf.maxLife
    if t >= 1 then lf.active = false ; lf.tex:SetAlpha(0) ; return end
    lf.vy  = lf.vy - S.FRONT_GRAVITY * dt
    lf.x   = lf.x  + lf.vx * dt
    lf.y   = lf.y  + lf.vy * dt
    lf.rot = lf.rot + lf.rotSpeed * dt
    local alpha = (t < 0.55 and 1 or math.max(0, (1 - t) / 0.45)) * S.FRONT_ALPHA * (globalFade or 1)
    lf.tex:SetAlpha(alpha)
    lf.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", lf.x, lf.y)
    lf.tex:SetRotation(lf.rot)
end

function FX.Init(container, bar)

    S.glowParts = {}
    for i = 1, S.GLOW_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(SCB.TEX_PATH .. "frost\\Particle_Frost_01")
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.MW_R, S.MW_G, S.MW_B)
        tex:SetAlpha(0)
        S.glowParts[i] = { tex=tex, active=false, life=0, maxLife=0, x=0, y=0, vy=0, phase=0 }
    end

    local earthSchool = SCB.Schools.data["earth"]
    local emberTexs = {}
    if earthSchool then
        for _, t in ipairs(earthSchool.rocks or {})  do emberTexs[#emberTexs+1] = t end
        for _, t in ipairs(earthSchool.debris or {}) do emberTexs[#emberTexs+1] = t end
    end
    local function getEmberTex(i)
        if #emberTexs == 0 then return SCB.TEX_PATH .. "frost\\Particle_Frost_02" end
        return emberTexs[((i - 1) % #emberTexs) + 1]
    end

    S.emberParts = {}
    for i = 1, S.EMBER_COUNT do
        local typeIdx = ((i - 1) % 3) + 1
        local ptype = S.emberTypes[typeIdx]
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(getEmberTex(i))
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.MW_R, S.MW_G, S.MW_B)
        tex:SetAlpha(0)
        S.emberParts[i] = {
            tex=tex, ptype=ptype, typeIdx=typeIdx,
            active=false, life=0, maxLife=0,
            x=0, y=0, vx=0, vy=0, drift=0,
        }
    end

    S.mists = {}
    local _underlay = SCB.Bar and SCB.Bar.bgUnderlayHost or bar
    for i, xFrac in ipairs(S.MIST_POSITIONS) do
        local tex = _underlay:CreateTexture(nil, "BACKGROUND", nil, -1)
        tex:SetTexture(SCB.TEX_PATH .. "frost\\Mist_Frost_01")
        tex:SetSize(S.MIST_W_BASE, S.MIST_H_BASE)
        tex:SetAlpha(0)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.MW_R, S.MW_G, S.MW_B)
        S.mists[i] = {
            tex=tex, xFrac=xFrac, phase="idle", timer=0, duration=0,
            alpha=0, scaleT=0, scaleDir=1, angle=0,
            rotDir=(i % 2 == 0) and 1 or -1,
            baseW=S.MIST_W_BASE, baseH=S.MIST_H_BASE,
            delay=(i - 1) * 0.8,
        }
    end

    local natureLeaves = (SCB.Schools.data["nature"] and SCB.Schools.data["nature"].leaves) or {}
    local nLeaf = #natureLeaves
    local function getLeafTex(i)
        if nLeaf == 0 then return SCB.TEX_PATH .. "frost\\Particle_Frost_01" end
        return natureLeaves[((i - 1) % nLeaf) + 1]
    end

    S.leaves = {}
    for i = 1, S.LEAF_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(getLeafTex(i))
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.MW_R, S.MW_G, S.MW_B)
        tex:SetAlpha(0)
        S.leaves[i] = { tex=tex, active=false, x=0, y=0, vx=0, vy=0,
                      rot=0, rotSpeed=0, life=0, size=0, deadX=0 }
    end

    S.frontLeaves = {}
    for i = 1, S.FRONT_LEAF_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(getLeafTex(i + S.LEAF_COUNT))
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.MW_R, S.MW_G, S.MW_B)
        tex:SetAlpha(0)
        S.frontLeaves[i] = { tex=tex, active=false, x=0, y=0, vx=0, vy=0, rot=0, rotSpeed=0,
                           life=0, maxLife=0, size=0 }
    end
end

function FX.Start(duration)
    S.castDuration = duration or 5
    S.isActive = true
    S.partsFading = false
    S.partsFadeT = 0
    S.glowAcc, S.emberAcc, S.leafAcc, S.frontLeafAcc = 0, 0, 0, 0

    for i, m in ipairs(S.mists) do m.phase = "idle" ; m.delay = (i - 1) * 0.8 ; m.tex:SetAlpha(0) end
    for _, p in ipairs(S.glowParts) do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.emberParts) do p.active = false ; p.tex:SetAlpha(0) end
    for _, lf in ipairs(S.leaves) do lf.active = false ; lf.tex:SetAlpha(0) end
    for _, lf in ipairs(S.frontLeaves) do lf.active = false ; lf.tex:SetAlpha(0) end
end

function FX.Stop()
    S.isActive = false
    S.partsFading = true
    S.partsFadeT = 0
    S.glowAcc, S.emberAcc, S.leafAcc, S.frontLeafAcc = 0, 0, 0, 0
    for _, m in ipairs(S.mists) do
        if m.phase ~= "idle" then
            m.phase = "linger"  -- keep its alpha; the bar fade hides it
        end
    end
end

function FX.Reset()
    S.isActive = false
    S.partsFading = false
    S.partsFadeT = 0
    S.glowAcc, S.emberAcc, S.leafAcc, S.frontLeafAcc = 0, 0, 0, 0

    for _, m in ipairs(S.mists) do m.phase = "idle" ; m.tex:SetAlpha(0) end
    for _, p in ipairs(S.glowParts) do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.emberParts) do p.active = false ; p.tex:SetAlpha(0) end
    for _, lf in ipairs(S.leaves) do lf.active = false ; lf.tex:SetAlpha(0) end
    for _, lf in ipairs(S.frontLeaves) do lf.active = false ; lf.tex:SetAlpha(0) end
end

function FX.UpdateFade(dt)
    if not S.partsFading then return end
    S.partsFadeT = S.partsFadeT + dt
    local gf = 1
    if S.partsFadeT >= SCB.FX_LINGER then
        S.partsFading = false
        for _, p in ipairs(S.glowParts) do p.active = false ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.emberParts) do p.active = false ; p.tex:SetAlpha(0) end
        for _, lf in ipairs(S.leaves) do lf.active = false ; lf.tex:SetAlpha(0) end
        for _, lf in ipairs(S.frontLeaves) do lf.active = false ; lf.tex:SetAlpha(0) end
        return
    end

    for _, p in ipairs(S.glowParts) do if p.active then UpdateGlow(p, dt, gf) end end
    for _, p in ipairs(S.emberParts) do if p.active then UpdateEmber(p, dt, gf) end end
    for _, lf in ipairs(S.leaves) do if lf.active then UpdateLeaf(lf, dt, gf) end end
    for _, lf in ipairs(S.frontLeaves) do if lf.active then UpdateFrontLeaf(lf, dt, gf) end end
    for _, m in ipairs(S.mists) do if m.phase ~= "idle" then UpdateMist(m, dt) ; m.tex:SetAlpha(m.tex:GetAlpha() * gf) end end
end

function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    for _, p in ipairs(S.glowParts) do if p.active then UpdateGlow(p, dt, 1) end end
    for _, p in ipairs(S.emberParts) do if p.active then UpdateEmber(p, dt, 1) end end
    for _, lf in ipairs(S.leaves) do if lf.active then UpdateLeaf(lf, dt, 1) end end
    for _, lf in ipairs(S.frontLeaves) do if lf.active then UpdateFrontLeaf(lf, dt, 1) end end
    for _, m in ipairs(S.mists) do UpdateMist(m, dt) end

    if not S.isActive then return end

    local barLX = fillLX or (frontX - barW * progress)
    local barRX = barLX + (fillW or barW)

    S.glowAcc = S.glowAcc + dt
    if SCB.Particles.emitProgress < S.GLOW_STOP_AT and S.glowAcc >= S.GLOW_SPAWN_RATE then
        S.glowAcc = S.glowAcc - S.GLOW_SPAWN_RATE
        SpawnGlow(frontX, cy, barH)
    end

    S.emberAcc = S.emberAcc + dt
    if S.emberAcc >= S.EMBER_SPAWN then
        S.emberAcc = S.emberAcc - S.EMBER_SPAWN
        SpawnEmber(frontX, cy)
    end

    S.leafAcc = S.leafAcc + dt
    if S.leafAcc >= S.LEAF_SPAWN_RATE then
        S.leafAcc = S.leafAcc - S.LEAF_SPAWN_RATE
        SpawnLeaf(barLX, barRX, cy, barH)
    end

    S.frontLeafAcc = S.frontLeafAcc + dt
    if progress < 0.95 and S.frontLeafAcc >= S.FRONT_SPAWN_RATE then
        S.frontLeafAcc = S.frontLeafAcc - S.FRONT_SPAWN_RATE
        SpawnFrontLeaf(frontX, cy, barH)
    end
end
