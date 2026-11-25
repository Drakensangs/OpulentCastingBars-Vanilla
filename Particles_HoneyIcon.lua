-- ============================================================
--  Opulent Casting Bars - Particles_HoneyIcon.lua
--  Left spell icon with golden tip glow and ballistic debris.
--  Holy textures provide softly drifting ambient particles around the bar.
-- ============================================================

local S = {}  -- Group style settings and runtime state to limit local upvalues.
local FX = {}
SCB.FX = SCB.FX or {}
SCB.FX["honey_icon"] = FX

local function rand(a, b) return a + math.random() * (b - a) end
local function gauss(r) return (rand(-r,r) + rand(-r,r) + rand(-r,r)) / 3 end
local function rad(deg)   return deg * math.pi / 180 end
local function lerp(a, b, t) return a + (b - a) * math.max(0, math.min(t, 1)) end

-- Spell icon rectangle (1024x512 artwork px) around the frame's round
-- opening; its mask (Mask_Icon_Honey_Icon)
-- follows that opening. See SCB.Bar:NewSpellIcon.
S.ICON_RECT = { x0 = 63.75, y0 = 156.75, x1 = 208.25, y1 = 306.5 }

-- Golden front glow pool and appearance.
S.GLOW_COUNT = 60
S.GLOW_SPAWN_RATE = 0.02
S.GLOW_STOP_AT = 0.87
S.GLOW_ALPHA = 0.55
S.GLOW_SIZE_MIN = 4
S.GLOW_SIZE_MAX = 9
S.GLOW_LIFE_MIN = 0.10
S.GLOW_LIFE_MAX = 0.20
S.GLOW_R = 0.92 ; S.GLOW_G = 0.78 ; S.GLOW_B = 0.52

-- Ballistic debris pool and emission interval.
S.EMBER_COUNT = 60
S.EMBER_SPAWN = 0.03

S.emberTypes = {
    { sizeMin=8,  sizeMax=14, speedMin=25, speedMax=60,  lifeMin=0.8, lifeMax=1.6, gravity=8,  spread=140, driftX=0.4 },
    { sizeMin=4,  sizeMax=8,  speedMin=80, speedMax=160, lifeMin=0.3, lifeMax=0.7, gravity=15, spread=80,  driftX=0.0 },
    { sizeMin=6,  sizeMax=12, speedMin=40, speedMax=90,  lifeMin=0.6, lifeMax=1.2, gravity=20, spread=100, driftX=0.2 },
}

S.EMBER_R = 0.92 ; S.EMBER_G = 0.78 ; S.EMBER_B = 0.52

-- Ambient holy motes distributed around the bar.
S.MISC_AMB_COUNT = 120
S.MISC_AMB_SPAWN_RATE = 0.12
S.MISC_AMB_SIZE_MIN = 3
S.MISC_AMB_SIZE_MAX = 20
S.MISC_AMB_LIFE_MIN = 0.6
S.MISC_AMB_LIFE_MAX = 1.4
S.MISC_AMB_ALPHA = 0.65
S.MISC_AMB_SPREAD_X = 5
S.MISC_AMB_SPREAD_Y = 5

-- Residual particles use the shared SCB.FX_LINGER cleanup timer.

-- Runtime state and reusable particle pools.
S.isActive = false
S.partsFading = false
S.partsFadeT = 0
S.castDuration = 5
S.glowParts = {}
S.glowSpawnAcc = 0
S.emberParts = {}
S.emberSpawnAcc = 0
S.miscAmbParts = {}
S.miscAmbAcc = 0

S.iconTex = nil

-- Lay the spell icon out on the frame's opening at the current bar size.
local function PositionIcon()
    if S.iconTex then S.iconTex:Layout() end
end

-- Reuse an idle front glow particle.
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

-- Damp vertical motion and apply the particle alpha envelope.
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

-- Choose a debris type and launch it with cast-scaled speed.
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

-- Integrate debris drift and gravity, then fade by lifetime.
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

-- Distribute ambient motes near the bar center.
local function SpawnMiscAmb(cx, cy, barW, barH)
    for _, p in ipairs(S.miscAmbParts) do
        if not p.active then
            p.active  = true ; p.life = 0
            p.maxLife = rand(S.MISC_AMB_LIFE_MIN, S.MISC_AMB_LIFE_MAX)
            p.x  = cx + gauss(barW * 0.5 + S.MISC_AMB_SPREAD_X)
            p.y  = cy + gauss(barH * 0.5 + S.MISC_AMB_SPREAD_Y)
            p.vx = rand(-6, 6)
            p.vy = rand(-4, 8)
            p.phase = math.random() * math.pi * 2
            local sz = rand(S.MISC_AMB_SIZE_MIN, S.MISC_AMB_SIZE_MAX)
            p.tex:SetSize(sz, sz)
            p.tex:SetAlpha(0)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            return
        end
    end
end

-- Advance ambient drift and its fade envelope.
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

function FX.Init(container, bar)
    -- Under the frame.
    S.iconTex = SCB.Bar:NewSpellIcon(bar, "ARTWORK", -3, S.ICON_RECT, SCB.Schools.data["honey_icon"])
    PositionIcon()

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

    local holy = SCB.Schools.data["holy"]
    local holyMisc = (holy and holy.misc) or {}
    local nMisc = #holyMisc

    S.miscAmbParts = {}
    for i = 1, S.MISC_AMB_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        if nMisc > 0 then tex:SetTexture(holyMisc[((i - 1) % nMisc) + 1]) end
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)
        S.miscAmbParts[i] = { tex=tex, active=false, life=0, maxLife=0, x=0, y=0, vx=0, vy=0, phase=0 }
    end
end

function FX.Start(duration)
    S.castDuration  = duration or 5
    S.isActive      = true
    S.partsFading   = false
    S.partsFadeT    = 0
    S.glowSpawnAcc  = 0
    S.emberSpawnAcc = 0
    S.miscAmbAcc    = 0

    if S.iconTex then
        S.iconTex:SetTexture(SCB.Bar.currentSpellIcon)
        S.iconTex:SetAlpha(1)
        PositionIcon()
    end

    for _, p in ipairs(S.glowParts)    do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.emberParts)   do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.miscAmbParts) do p.active = false ; p.tex:SetAlpha(0) end
end

function FX.Stop()
    S.isActive      = false
    S.partsFading   = true
    S.partsFadeT    = 0
    S.glowSpawnAcc  = 0
    S.emberSpawnAcc = 0
    S.miscAmbAcc    = 0
end

function FX.UpdateFade(dt)
    if not S.partsFading then return end
    S.partsFadeT = S.partsFadeT + dt
    local gFade = 1

    for _, p in ipairs(S.glowParts)    do UpdateGlow(p, dt, gFade) end
    for _, p in ipairs(S.emberParts)   do UpdateEmber(p, dt, gFade) end
    for _, p in ipairs(S.miscAmbParts) do UpdateMiscAmb(p, dt, gFade) end

    if S.partsFadeT >= SCB.FX_LINGER then
        S.partsFading = false
        if S.iconTex then S.iconTex:SetAlpha(0) end
        for _, p in ipairs(S.glowParts)    do p.active = false ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.emberParts)   do p.active = false ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.miscAmbParts) do p.active = false ; p.tex:SetAlpha(0) end
    end
end

function FX.Reset()
    S.partsFading = false
    if S.iconTex then S.iconTex:SetAlpha(0) end
    for _, p in ipairs(S.glowParts)    do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.emberParts)   do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.miscAmbParts) do p.active = false ; p.tex:SetAlpha(0) end
end

function FX.Update(dt, progress, frontX, cy, barW, barH)
    if not S.isActive then return end

    local f = SCB.Bar.frameInner
    local barCX, barCY = f:GetCenter()
    if not barCY then return end

    for _, p in ipairs(S.glowParts)    do UpdateGlow(p, dt, 1) end
    for _, p in ipairs(S.emberParts)   do UpdateEmber(p, dt, 1) end
    for _, p in ipairs(S.miscAmbParts) do UpdateMiscAmb(p, dt, 1) end

    if SCB.Particles.emitProgress < S.GLOW_STOP_AT then
        S.glowSpawnAcc = S.glowSpawnAcc + dt
        if S.glowSpawnAcc >= S.GLOW_SPAWN_RATE then
            S.glowSpawnAcc = 0
            local count = math.random(2, 4)
            for _ = 1, count do SpawnGlow(frontX, barCY, barH) end
        end
    end

    S.emberSpawnAcc = S.emberSpawnAcc + dt
    if S.emberSpawnAcc >= S.EMBER_SPAWN then
        S.emberSpawnAcc = 0
        local count = math.random(2, 4)
        for _ = 1, count do SpawnEmber(frontX, barCY) end
    end

    S.miscAmbAcc = S.miscAmbAcc + dt
    if S.miscAmbAcc >= S.MISC_AMB_SPAWN_RATE then
        S.miscAmbAcc = 0
        for _ = 1, 3 do SpawnMiscAmb(barCX, barCY, barW, barH) end
    end
end

