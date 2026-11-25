-- ============================================================
--  Opulent Casting Bars - Particles_Fishing.lua
--  Cyan droplets arc from the front under gravity; flattened ripples expand
--  and fade in place while fine ambient spray rises around the bar.
-- ============================================================

local S = {}  -- Group style settings and runtime state to limit local upvalues.
local FX = {}
SCB.FX            = SCB.FX or {}
SCB.FX["fishing"] = FX

local function rand(a, b) return a + math.random() * (b - a) end

-- Droplet pool, ballistic motion, lifetime, and cyan tint.
S.DROP_COUNT = 55
S.DROP_SPAWN_RATE = 0.045
S.DROP_BURST_MIN = 1
S.DROP_BURST_MAX = 3
S.DROP_STOP_AT = 0.93
S.DROP_SIZE_MIN = 5
S.DROP_SIZE_MAX = 13
S.DROP_SPEED_MIN = 45
S.DROP_SPEED_MAX = 115
S.DROP_GRAVITY = 160
S.DROP_LIFE_MIN = 0.30
S.DROP_LIFE_MAX = 0.70
S.DROP_ALPHA = 0.88
S.DROP_ANGLE_MIN = math.rad(45)
S.DROP_ANGLE_MAX = math.rad(135)
S.DROP_R = 0.35 ; S.DROP_G = 0.80 ; S.DROP_B = 1.0

-- Ripple pool, expansion size, lifetime, and peak alpha.
S.RIP_COUNT = 12
S.RIP_SPAWN_RATE = 0.18
S.RIP_SIZE_START = 8
S.RIP_SIZE_END = 38
S.RIP_LIFE = 0.55
S.RIP_ALPHA_PEAK = 0.45
S.RIP_R = 0.45 ; S.RIP_G = 0.88 ; S.RIP_B = 1.0

-- Fine ambient spray density, drift, and lifetime.
S.AMB_COUNT = 40
S.AMB_SPAWN_RATE = 0.08
S.AMB_STOP_AT = 0.95
S.AMB_SIZE_MIN = 3
S.AMB_SIZE_MAX = 8
S.AMB_VY_MIN = 8
S.AMB_VY_MAX = 22
S.AMB_VX_MIN = -12
S.AMB_VX_MAX = 12
S.AMB_LIFE_MIN = 0.6
S.AMB_LIFE_MAX = 1.4
S.AMB_ALPHA = 0.38

-- Particle pools, emission timers, and fade state.
S.isActive = false
S.isFading = false
S.fadeT = 0
S.drops = {}
S.ripples = {}
S.ambs = {}
S.dropAcc = 0
S.ripAcc = 0
S.ambAcc = 0

-- Spawn and animate ballistic droplets.
local function SpawnDrop(frontX, cy, barH)
    for _, p in ipairs(S.drops) do
        if not p.active then
            local angle = rand(S.DROP_ANGLE_MIN, S.DROP_ANGLE_MAX)
            local speed = rand(S.DROP_SPEED_MIN, S.DROP_SPEED_MAX)
            local spread = math.min(barH * 0.3, 12)
            p.active  = true
            p.life    = 0
            p.maxLife = rand(S.DROP_LIFE_MIN, S.DROP_LIFE_MAX)
            p.x       = frontX + rand(-5, 6)
            p.y       = cy + rand(-spread, spread)
            p.vx      = math.cos(angle) * speed
            p.vy      = math.sin(angle) * speed
            local size = rand(S.DROP_SIZE_MIN, S.DROP_SIZE_MAX)
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(0)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            return
        end
    end
end

local function UpdateDrop(p, dt, gf)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    p.vy = p.vy - S.DROP_GRAVITY * dt
    p.x  = p.x  + p.vx * dt
    p.y  = p.y  + p.vy * dt
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local env = t < 0.12 and t/0.12 or (t < 0.60 and 1 or math.max(0, (1-t)/0.40))
    p.tex:SetAlpha(env * S.DROP_ALPHA * (gf or 1))
end

-- Expand flattened ripples without moving their centers.
local function SpawnRipple(frontX, cy, barH)
    for _, r in ipairs(S.ripples) do
        if not r.active then
            local spread = math.min(barH * 0.25, 10)
            r.active = true
            r.life   = 0
            r.x      = frontX + rand(-6, 6)
            r.y      = cy + rand(-spread, spread)
            r.tex:SetSize(S.RIP_SIZE_START, S.RIP_SIZE_START * 0.45)
            r.tex:SetAlpha(0)
            r.tex:ClearAllPoints()
            r.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", r.x, r.y)
            return
        end
    end
end

local function UpdateRipple(r, dt, gf)
    if not r.active then return end
    r.life = r.life + dt
    local t = r.life / S.RIP_LIFE
    if t >= 1 then r.active = false ; r.tex:SetAlpha(0) ; return end
    local size = S.RIP_SIZE_START + (S.RIP_SIZE_END - S.RIP_SIZE_START) * t
    r.tex:SetSize(size, size * 0.45)
    local env = t < 0.25 and t/0.25 or math.max(0, (1-t)/0.75)
    r.tex:SetAlpha(env * S.RIP_ALPHA_PEAK * (gf or 1))
end

-- Spawn and animate fine spray across the bar.
local function SpawnAmb(barLX, barW, cy, barH)
    for _, p in ipairs(S.ambs) do
        if not p.active then
            local spread = math.min(barH * 0.4, 16)
            p.active  = true
            p.life    = 0
            p.maxLife = rand(S.AMB_LIFE_MIN, S.AMB_LIFE_MAX)
            p.x       = barLX + rand(0, barW)
            p.y       = cy + rand(-spread, spread)
            p.vx      = rand(S.AMB_VX_MIN, S.AMB_VX_MAX)
            p.vy      = rand(S.AMB_VY_MIN, S.AMB_VY_MAX)
            local size = rand(S.AMB_SIZE_MIN, S.AMB_SIZE_MAX)
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(0)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            return
        end
    end
end

local function UpdateAmb(p, dt, gf)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local env = t < 0.20 and t/0.20 or (t < 0.70 and 1 or math.max(0, (1-t)/0.30))
    p.tex:SetAlpha(env * S.AMB_ALPHA * (gf or 1))
end

-- Style lifecycle and per-frame emission.
function FX.Init(container, bar)
    local dropTex = SCB.TEX_PATH .. "frost\\Particle_Frost_01"
    local ripTex  = SCB.TEX_PATH .. "frost\\Particle_Frost_02"

    S.drops = {}
    for i = 1, S.DROP_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(dropTex)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.DROP_R, S.DROP_G, S.DROP_B)
        tex:SetAlpha(0)
        S.drops[i] = { tex=tex, active=false, life=0, maxLife=0, x=0, y=0, vx=0, vy=0 }
    end

    S.ripples = {}
    for i = 1, S.RIP_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(ripTex)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.RIP_R, S.RIP_G, S.RIP_B)
        tex:SetAlpha(0)
        S.ripples[i] = { tex=tex, active=false, life=0, x=0, y=0 }
    end

    S.ambs = {}
    for i = 1, S.AMB_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(i % 2 == 0 and dropTex or ripTex)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.DROP_R * 0.8, S.DROP_G * 0.9, S.DROP_B)
        tex:SetAlpha(0)
        S.ambs[i] = { tex=tex, active=false, life=0, maxLife=0, x=0, y=0, vx=0, vy=0 }
    end

    -- Warm textures before their first visible use.
    for _, t in ipairs({ dropTex, ripTex }) do
        local pl = UIParent:CreateTexture(nil, "BACKGROUND")
        pl:SetTexture(t) ; pl:SetSize(1,1) ; pl:SetAlpha(0.0001)
        pl:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    end
end

function FX.Start(duration)
    S.isActive = true
    S.isFading = false
    S.fadeT    = 0
    S.dropAcc  = 0
    S.ripAcc   = 0
    S.ambAcc   = 0
    for _, p in ipairs(S.drops)   do p.active = false ; p.tex:SetAlpha(0) end
    for _, r in ipairs(S.ripples) do r.active = false ; r.tex:SetAlpha(0) end
    for _, p in ipairs(S.ambs)    do p.active = false ; p.tex:SetAlpha(0) end
end

function FX.Stop()
    S.isActive = false
    S.isFading = true
    S.fadeT    = 0
end

function FX.UpdateFade(dt)
    if not S.isFading then return end
    S.fadeT = S.fadeT + dt
    local gf = 1
    for _, p in ipairs(S.drops)   do UpdateDrop(p, dt, gf) end
    for _, r in ipairs(S.ripples) do UpdateRipple(r, dt, gf) end
    for _, p in ipairs(S.ambs)    do UpdateAmb(p, dt, gf) end
    if S.fadeT >= SCB.FX_LINGER then
        S.isFading = false
        for _, p in ipairs(S.drops)   do p.active = false ; p.tex:SetAlpha(0) end
        for _, r in ipairs(S.ripples) do r.active = false ; r.tex:SetAlpha(0) end
        for _, p in ipairs(S.ambs)    do p.active = false ; p.tex:SetAlpha(0) end
    end
end

function FX.Reset()
    S.isActive = false
    S.isFading = false
    for _, p in ipairs(S.drops)   do p.active = false ; p.tex:SetAlpha(0) end
    for _, r in ipairs(S.ripples) do r.active = false ; r.tex:SetAlpha(0) end
    for _, p in ipairs(S.ambs)    do p.active = false ; p.tex:SetAlpha(0) end
end

function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    if not S.isActive then return end

    local f = SCB.Bar.frameInner
    local cx, barCY = f:GetCenter()
    if not cx then return end
    local barLX = cx - barW * 0.5

    -- Emit front droplets.
    for _, p in ipairs(S.drops) do UpdateDrop(p, dt, 1) end
    if SCB.Particles.emitProgress > 0.01 and SCB.Particles.emitProgress < S.DROP_STOP_AT then
        S.dropAcc = S.dropAcc + dt
        if S.dropAcc >= S.DROP_SPAWN_RATE then
            S.dropAcc = 0
            for _ = 1, math.random(S.DROP_BURST_MIN, S.DROP_BURST_MAX) do
                SpawnDrop(frontX, barCY, barH)
            end
        end
    end

    -- Emit surface ripples.
    for _, r in ipairs(S.ripples) do UpdateRipple(r, dt, 1) end
    if SCB.Particles.emitProgress > 0.01 and SCB.Particles.emitProgress < S.DROP_STOP_AT then
        S.ripAcc = S.ripAcc + dt
        if S.ripAcc >= S.RIP_SPAWN_RATE then
            S.ripAcc = 0
            SpawnRipple(frontX, barCY, barH)
        end
    end

    -- Emit ambient spray.
    for _, p in ipairs(S.ambs) do UpdateAmb(p, dt, 1) end
    if SCB.Particles.emitProgress > 0.01 and SCB.Particles.emitProgress < S.AMB_STOP_AT then
        S.ambAcc = S.ambAcc + dt
        if S.ambAcc >= S.AMB_SPAWN_RATE then
            S.ambAcc = 0
            SpawnAmb(barLX, barW, barCY, barH)
        end
    end
end
