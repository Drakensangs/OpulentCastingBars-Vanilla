-- ============================================================
--  Opulent Casting Bars -- Particles_Frostfire.lua
--  Revealed flame layers, floating frost mist, and mixed front particles.
-- ============================================================

local S = {}
local FX = {}
SCB.FX = SCB.FX or {}
SCB.FX["frostfire"] = FX

-- Local math helpers.
local function rand(a, b) return a + math.random() * (b - a) end
local function rad(deg)   return deg * math.pi / 180 end
local function lerp(a, b, t) return a + (b - a) * math.max(0, math.min(t, 1)) end

S.TEX_FROST = SCB.TEX_PATH .. "frost\\"
S.TEX_FIRE = SCB.TEX_PATH .. "fire\\"

-- Flame slot count and cycle timing.
S.FF_EFFECT_COUNT = 3
S.FF_EFFECT_CYCLE = 0.65
S.FF_EFFECT_FADE = 0.13
S.FF_EFFECT_BASE = { 1, 2, 3, 4, 5 }

-- Mist pool, size, opacity, and lifecycle tuning.
S.MIST_W_BASE = 338
S.MIST_H_BASE = 169
S.MIST_ALPHA_MAX = 0.38
S.MIST_SCALE_MIN = 0.70
S.MIST_SCALE_MAX = 1.20
S.MIST_FADE_IN = 1.6
S.MIST_HOLD_MIN = 1.0
S.MIST_HOLD_MAX = 2.2
S.MIST_FADE_OUT = 1.3
S.MIST_ROT_SPEED = 0.035

S.MIST_POSITIONS = { 1/5, 2/5, 3/5, 4/5 }

-- Ambient pool and emission tuning.
S.AMB_COUNT = 40
S.AMB_SPAWN = 0.09

-- Mixed front particle pool and emission tuning.
S.FRONT_COUNT = 60
S.FRONT_SPAWN = 0.028

S.frontTypes = {
    { kind="fire",  sizeMin=6,  sizeMax=13, speedMin=25, speedMax=65,  lifeMin=0.7, lifeMax=1.5, gravity=7,  spread=130, driftX=0.3  },
    { kind="frost", sizeMin=5,  sizeMax=10, speedMin=85, speedMax=160, lifeMin=0.2, lifeMax=0.55, gravity=18, spread=70,  driftX=0.0  },
    { kind="fire",  sizeMin=7,  sizeMax=12, speedMin=40, speedMax=90,  lifeMin=0.5, lifeMax=1.1, gravity=22, spread=95,  driftX=0.15 },
}

S.ffEffectSlots = {}
S.mists = {}
S.ambParts = {}
S.frontParts = {}
S.ambSpawnAcc = 0
S.frontSpawnAcc = 0
S.castDuration = 5

-- Cast and particle state.
S.isActive = false
S.givreFading = false
S.givreFadeT = 0

-- Advance frostfire reveal.
local function UpdateFrostfireReveal(progress, barW)
    if not S.ffHosts or not S.frostfireFrame then return end
    local bW = barW or (SCB.Config and SCB.Config:Get("barWidth")) or 400
    local revealW = math.max(1, bW * progress)
    SCB.LayoutArtworkRevealMask(S.ffMask, S.frostfireFrame, revealW, progress)
    for i, host in ipairs(S.ffHosts) do
        local tex = S.ffTexes[i]
        host:SetWidth(revealW)
        if tex then
            tex:SetWidth(revealW)
            tex:SetTexCoord(0, revealW / bW, 0, 1)
        end
    end
end

-- Set texture rotation.
local function SetTextureRotation(tex, angle)
    local c, s = math.cos(angle), math.sin(angle)
    tex:SetTexCoord(
        0.5 + (-0.5)*c - (-0.5)*s,  0.5 + (-0.5)*s + (-0.5)*c,
        0.5 + (-0.5)*c - ( 0.5)*s,  0.5 + (-0.5)*s + ( 0.5)*c,
        0.5 + ( 0.5)*c - (-0.5)*s,  0.5 + ( 0.5)*s + (-0.5)*c,
        0.5 + ( 0.5)*c - ( 0.5)*s,  0.5 + ( 0.5)*s + ( 0.5)*c
    )
end

S.ffEffectAlphas = {}

-- Advance fill effects.
local function UpdateFillEffects(dt)
    if not S.ffTexes or #S.ffTexes == 0 then return end

    local effectAlphas = S.ffEffectAlphas
    for i = 1, 5 do effectAlphas[i] = 0 end

    for _, slot in ipairs(S.ffEffectSlots) do
        slot.timer = slot.timer + dt
        if slot.timer >= S.FF_EFFECT_CYCLE then
            slot.timer   = slot.timer - S.FF_EFFECT_CYCLE
            slot.basePos = (slot.basePos % #S.FF_EFFECT_BASE) + 1
        end
        local t     = slot.timer / S.FF_EFFECT_CYCLE
        local fadeT = S.FF_EFFECT_FADE / S.FF_EFFECT_CYCLE
        local alpha
        if     t < fadeT       then alpha = t / fadeT
        elseif t < 1 - fadeT   then alpha = 1
        else                        alpha = (1 - t) / fadeT end
        local texIdx = S.FF_EFFECT_BASE[slot.basePos]
        effectAlphas[texIdx] = math.max(effectAlphas[texIdx], math.max(0, alpha) * 0.82)
    end

    for i, tex in ipairs(S.ffTexes) do
        local a = effectAlphas[i] or 0
        tex:SetAlpha(a)
    end
end

-- Reset fill effects.
local function ResetFillEffects()
    local bar = SCB.Bar
    if bar.texFillEffectsFrostfire then
        for _, t in ipairs(bar.texFillEffectsFrostfire) do t:Hide() end
    end
    for s = 1, S.FF_EFFECT_COUNT do
        S.ffEffectSlots[s].timer   = (s - 1) * (S.FF_EFFECT_CYCLE / S.FF_EFFECT_COUNT)
        S.ffEffectSlots[s].basePos = s
    end
end

-- Spawn mist.
local function SpawnMist(m)
    local scale = rand(S.MIST_SCALE_MIN, S.MIST_SCALE_MAX)
    m.baseW    = S.MIST_W_BASE * scale
    m.baseH    = S.MIST_H_BASE * scale
    m.tex:SetSize(m.baseW, m.baseH)
    m.tex:SetAlpha(0)
    m.phase    = "fadein"
    m.timer    = 0
    m.duration = S.MIST_FADE_IN
    m.alpha    = 0
    m.scaleT   = 0
    m.scaleDir = math.random(2) == 1 and 1 or -1
end

-- Advance mist.
local function UpdateMist(m, dt)
    if m.delay and m.delay > 0 then
        m.delay = m.delay - dt
        return
    end
    if m.phase == "idle" then
        if S.isActive then SpawnMist(m) end
        return
    end

    local f = SCB.Bar.frameInner
    local cx, cy = f:GetCenter()
    if cx then
        local barW = f:GetWidth()
        local x = cx - barW * 0.5 + barW * m.xFrac
        m.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, cy)
    end

    m.timer  = m.timer + dt
    m.scaleT = m.scaleT + dt
    m.angle  = m.angle + S.MIST_ROT_SPEED * m.rotDir * dt

    local scalePulse = 1 + math.sin(m.scaleT * 0.45 * m.scaleDir) * 0.09
    m.tex:SetSize(m.baseW * scalePulse, m.baseH * scalePulse)
    SetTextureRotation(m.tex, m.angle)

    if m.phase == "fadein" then
        m.alpha = math.min(m.timer / m.duration, 1) * S.MIST_ALPHA_MAX
        m.tex:SetAlpha(math.max(0, m.alpha + math.sin(m.scaleT * 1.8) * 0.03))
        if m.timer >= m.duration then
            m.phase = "hold" ; m.timer = 0
            m.duration = rand(S.MIST_HOLD_MIN, S.MIST_HOLD_MAX)
        end
    elseif m.phase == "hold" then
        m.tex:SetAlpha(math.max(0, S.MIST_ALPHA_MAX + math.sin(m.scaleT * 1.8) * 0.05))
        if m.timer >= m.duration then
            m.phase = "fadeout" ; m.timer = 0 ; m.duration = S.MIST_FADE_OUT
        end
    elseif m.phase == "fadeout" then
        m.alpha = (1 - m.timer / m.duration) * S.MIST_ALPHA_MAX
        m.tex:SetAlpha(math.max(0, m.alpha))
        if m.timer >= m.duration then
            m.tex:SetAlpha(0) ; m.phase = "idle"
        end
    end
end

-- Spawn ambient.
local function SpawnAmbient(progress)
    local f = SCB.Bar.frame
    local cx, cy = f:GetCenter()
    if not cx then return end
    local barW, barH = f:GetWidth(), f:GetHeight()

    for _, p in ipairs(S.ambParts) do
        if not p.active then
            local xOffset = rand(-barW * 0.5, barW * progress - barW * 0.5)
            local yOffset = rand(-barH * 0.35, barH * 0.35)
            local dirX    = xOffset > 0 and 1 or -1

            p.active  = true ; p.life = 0
            p.maxLife = rand(1.0, 2.2)
            p.x       = cx + xOffset ; p.y = cy + yOffset
            p.vx      = dirX * rand(4, 18)
            p.vy      = rand(12, 40)

            local size = rand(5, 13)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(0)
            return
        end
    end
end

-- Advance ambient.
local function UpdateAmbient(p, dt)
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
    p.tex:SetAlpha(math.max(0, alpha) * 0.50)
end

-- Spawn front particle.
local function SpawnFrontParticle(wx, wy)
    local roll = math.random(10)
    local typeIdx = roll <= 4 and 1 or (roll <= 7 and 2 or 3)
    local ptype = S.frontTypes[typeIdx]

    for _, p in ipairs(S.frontParts) do
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
            p.drift   = rand(-ptype.driftX, ptype.driftX) * 28
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(1)
            return
        end
    end
end

-- Advance front particle.
local function UpdateFrontParticle(p, dt)
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
    p.tex:SetAlpha(alpha * 0.88)
end

-- Create texture hosts, animation slots, and particle pools.
function FX.Init(container, bar)
    local fireTex1  = S.TEX_FIRE  .. "Particle_Fire_01"
    local fireTex2  = S.TEX_FIRE  .. "Particle_Fire_02"
    local fireTex3  = S.TEX_FIRE  .. "Particle_Fire_03"
    local frostTex1 = S.TEX_FROST .. "Particle_Frost_01"
    local frostTex2 = S.TEX_FROST .. "Particle_Frost_02"
    local fireMisc1 = S.TEX_FIRE  .. "Particle_Fire_01"

    local school = SCB.Schools.data["frostfire"]
    local f = SCB.Bar and SCB.Bar.frameInner
    S.frostfireFrame = f
    S.ffHosts = {}
    S.ffTexes = {}
    if SCB.Bar.texFillEffectsFrostfire then
        for _, t in ipairs(SCB.Bar.texFillEffectsFrostfire) do
            t:Hide() ; t:SetAlpha(0)
        end
    end
    if f and school and school.frostfireEffects then
        local _underlay = SCB.Bar and SCB.Bar.bgUnderlayHost or bar
        S.ffMask = SCB.NewRevealMask(_underlay)
        for i, texPath in ipairs(school.frostfireEffects) do
            local host = CreateFrame("Frame", nil, _underlay)
            host:SetPoint("TOPLEFT",    f, "TOPLEFT",    0, 0)
            host:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
            host:SetWidth(1)
            host:Hide()
            local tex = host:CreateTexture(nil, "ARTWORK", nil, 1)
            SCB.AttachMask(tex, S.ffMask)
            tex:SetPoint("TOPLEFT",    host, "TOPLEFT")
            tex:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT")
            tex:SetWidth(1)
            tex:SetTexture(texPath)
            tex:SetAlpha(0)
            S.ffHosts[i] = host
            S.ffTexes[i] = tex
        end
    end

    for s = 1, S.FF_EFFECT_COUNT do
        S.ffEffectSlots[s] = {
            timer   = (s - 1) * (S.FF_EFFECT_CYCLE / S.FF_EFFECT_COUNT),
            basePos = s,
        }
    end

    for i, xFrac in ipairs(S.MIST_POSITIONS) do
        local tex = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
        tex:SetTexture(S.TEX_FROST .. "Mist_Frost_01")
        tex:SetSize(S.MIST_W_BASE, S.MIST_H_BASE)
        tex:SetAlpha(0)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(0.72, 0.88, 1.0)
        S.mists[i] = {
            tex=tex, xFrac=xFrac, phase="idle", timer=0, duration=0,
            alpha=0, scaleT=0, scaleDir=1, angle=0,
            rotDir=(i % 2 == 0) and 1 or -1,
            baseW=S.MIST_W_BASE, baseH=S.MIST_H_BASE,
            delay=(i - 1) * 0.75,
        }
    end

    for i = 1, S.AMB_COUNT do
        local tex = container:CreateTexture(nil, "BACKGROUND")
        local t = (i % 3 == 0) and frostTex1 or ((i % 3 == 1) and fireMisc1 or fireTex2)
        tex:SetTexture(t)
        tex:SetAlpha(0)
        tex:SetBlendMode("ADD")
        if i % 3 == 0 then
            tex:SetVertexColor(0.5, 0.75, 1.0)
        else
            tex:SetVertexColor(1.0, 0.6, 0.15)
        end
        S.ambParts[i] = { tex=tex, active=false, life=0, maxLife=0, x=0, y=0, vx=0, vy=0 }
    end

    for i = 1, S.FRONT_COUNT do
        local typeIdx = ((i - 1) % 3) + 1
        local ptype   = S.frontTypes[typeIdx]
        local tex = container:CreateTexture(nil, "OVERLAY")

        local texPath
        if ptype.kind == "frost" then
            texPath = (i % 2 == 0) and frostTex1 or frostTex2
        else
            texPath = (i % 3 == 0) and fireTex1 or ((i % 3 == 1) and fireTex2 or fireTex3)
        end
        tex:SetTexture(texPath)
        tex:SetAlpha(0)
        tex:SetBlendMode("ADD")

        if ptype.kind == "frost" then
            tex:SetVertexColor(0.55, 0.85, 1.0)
        else
            tex:SetVertexColor(1.0, 0.55, 0.10)
        end

        S.frontParts[i] = {
            tex=tex, ptype=ptype, typeIdx=typeIdx,
            active=false, life=0, maxLife=0,
            x=0, y=0, vx=0, vy=0, drift=0,
        }
    end
end

-- Start a cast and reset effect timing.
function FX.Start(duration)
    UpdateFrostfireReveal(0)
    S.castDuration  = duration or 5
    S.ambSpawnAcc   = 0
    S.frontSpawnAcc = 0
    S.isActive      = true
    S.givreFading   = false
    S.givreFadeT    = 0

    ResetFillEffects()
    if S.ffHosts then for _, h in ipairs(S.ffHosts) do h:Hide() end end
    for _, m in ipairs(S.mists)      do m.phase = "idle" ; m.delay = 0 ; m.tex:SetAlpha(0) end
    for _, p in ipairs(S.ambParts)   do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.frontParts) do p.active = false ; p.tex:SetAlpha(0) end

    local bar = SCB.Bar
    if bar.texGivreFrostfire then bar.texGivreFrostfire:SetAlpha(1) end

    for i, m in ipairs(S.mists) do
        m.delay = (i - 1) * 0.75
    end
end

-- Stop emission and begin the completion fade.
function FX.Stop(success)
    if success and not SCB.Bar.isChannel then UpdateFrostfireReveal(1) end
    S.isActive    = false
    S.givreFading = true
    S.givreFadeT  = 0

    for _, m in ipairs(S.mists) do
        if m.phase ~= "idle" then
            m.phase = "linger"  -- keep its alpha; the bar fade hides it
        end
    end
end

-- Advance existing effects during the stop fade.
function FX.UpdateFade(dt)
    if not S.givreFading then return end
    S.givreFadeT = S.givreFadeT + dt
    -- The frost overlay keeps full alpha: the bar fade hides it together
    -- with every other layer.
    local t = S.givreFadeT / SCB.FX_LINGER
    local bar = SCB.Bar
    for _, m in ipairs(S.mists) do UpdateMist(m, dt) end
    for _, p in ipairs(S.ambParts)   do UpdateAmbient(p, dt) end
    for _, p in ipairs(S.frontParts) do UpdateFrontParticle(p, dt) end

    if t >= 1 then
        S.givreFading = false
        if bar.texGivreFrostfire then bar.texGivreFrostfire:SetAlpha(0) end
        for _, m in ipairs(S.mists)      do m.tex:SetAlpha(0) ; m.phase = "idle" end
        for _, p in ipairs(S.ambParts)   do p.active = false ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.frontParts) do p.active = false ; p.tex:SetAlpha(0) end
    end
end

-- Clear visible effects and pending fade state.
function FX.Reset()
    S.isActive    = false
    S.givreFading = false
    S.givreFadeT  = 0
    ResetFillEffects()
    if S.ffHosts then for _, h in ipairs(S.ffHosts) do h:Hide() end end
    for _, m in ipairs(S.mists)      do m.tex:SetAlpha(0) ; m.phase = "idle" end
    for _, p in ipairs(S.ambParts)   do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.frontParts) do p.active = false ; p.tex:SetAlpha(0) end
    if SCB.Bar.currentSchoolKey == "frostfire" then
        if SCB.Bar.texGivreFrostfire then SCB.Bar.texGivreFrostfire:SetAlpha(0) end
    end
end

-- Advance active-cast effects and emission.
function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    if not S.isActive then return end

    for _, p in ipairs(S.ambParts)   do UpdateAmbient(p, dt) end
    for _, p in ipairs(S.frontParts) do UpdateFrontParticle(p, dt) end
    for _, m in ipairs(S.mists)      do UpdateMist(m, dt) end

    UpdateFrostfireReveal(progress, barW)
    if S.ffHosts and S.frostfireFrame then
        for _, host in ipairs(S.ffHosts) do
            host:Show()
        end
    end

    UpdateFillEffects(dt)

    S.ambSpawnAcc = S.ambSpawnAcc + dt
    if S.ambSpawnAcc >= S.AMB_SPAWN then
        S.ambSpawnAcc = 0
        SpawnAmbient(progress)
    end

    S.frontSpawnAcc = S.frontSpawnAcc + dt
    if S.frontSpawnAcc >= S.FRONT_SPAWN then
        S.frontSpawnAcc = 0
        local count = math.random(2, 4)
        for _ = 1, count do SpawnFrontParticle(frontX, cy) end
    end
end
