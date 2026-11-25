-- ============================================================
--  Opulent Casting Bars - Particles_Arctic.lua
--  Frost mist, floating and orbiting rocks, and icy front particles.
--  Visible rocks fall under gravity when the cast ends.
-- ============================================================

local FX = {}
SCB.FX = SCB.FX or {}
SCB.FX["arctic"] = FX

local function rand(a, b) return a + math.random() * (b - a) end
local function rad(deg) return deg * math.pi / 180 end

local TEX_ARCTIC = SCB.TEX_PATH .. "arctic\\"
local TEX_FROST  = SCB.TEX_PATH .. "frost\\"

local MIST_COUNT = 4
local MIST_W, MIST_H = 338, 169
local MIST_POS = { 0.18, 0.38, 0.62, 0.82 }

local ROCK_SMALL_COUNT  = 24
local ROCK_MEDIUM_COUNT = 12
local ROCK_BIG_COUNT    = 9

local FRONT_PART_COUNT = 48
local FRONT_SPAWN_RATE = 0.045

-- Elliptical orbit radii, travel speed, and independent rock spin.
local ORBIT_MISC_COUNT   = 10
local ORBIT_RX_MIN       = 105
local ORBIT_RX_MAX       = 145
local ORBIT_RY_MIN       = 14
local ORBIT_RY_MAX       = 32
local ORBIT_SPEED_MIN    = 0.18
local ORBIT_SPEED_MAX    = 0.38
local ORBIT_SELF_ROT_MIN = 0.35
local ORBIT_SELF_ROT_MAX = 1.15

local FALL_GRAVITY = 260

local mists, rocks, orbitRocks, frontParts = {}, {}, {}, {}
local active = false
local fading = false
local fadeT = 0
local spawnAcc = 0

-- Rotate UVs inside the quad (used by the non-square mist quads).
local function SetTextureRotation(tex, angle)
    local c, s = math.cos(angle), math.sin(angle)
    tex:SetTexCoord(
        0.5 + (-0.5)*c - (-0.5)*s, 0.5 + (-0.5)*s + (-0.5)*c,
        0.5 + (-0.5)*c - ( 0.5)*s, 0.5 + (-0.5)*s + ( 0.5)*c,
        0.5 + ( 0.5)*c - (-0.5)*s, 0.5 + ( 0.5)*s + (-0.5)*c,
        0.5 + ( 0.5)*c - ( 0.5)*s, 0.5 + ( 0.5)*s + ( 0.5)*c
    )
end

-- Combine small, medium, and large Arctic rock textures.
local function BuildRockTexturePool()
    local pool = {}
    for i = 1, 8 do pool[#pool + 1] = TEX_ARCTIC .. string.format("Misc_Arctic_%02d", i) end
    for i = 1, 2 do pool[#pool + 1] = TEX_ARCTIC .. string.format("Misc_Arctic_Medium_%02d", i) end
    for i = 1, 2 do pool[#pool + 1] = TEX_ARCTIC .. string.format("Misc_Arctic_Big_%02d", i) end
    return pool
end

local ROCK_TEX_POOL = BuildRockTexturePool()
local FRONT_TEX = {
    TEX_FROST .. "Particle_Frost_01",
    TEX_FROST .. "Particle_Frost_02",
}

local function PickRockTexture(i)
    return ROCK_TEX_POOL[((i - 1) % #ROCK_TEX_POOL) + 1]
end

-- Launch an idle icy particle from the moving front.
local function SpawnFront(frontX, cy)
    for _, p in ipairs(frontParts) do
        if not p.active then
            local a = rad(rand(70, 125))
            local speed = rand(45, 125)
            p.active  = true
            p.life    = 0
            p.maxLife = rand(0.30, 0.70)
            p.x       = frontX + rand(-4, 4)
            p.y       = cy + rand(-8, 8)
            p.vx      = math.cos(a) * speed
            p.vy      = math.sin(a) * speed
            local size = rand(7, 14)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(0.9)
            return
        end
    end
end

-- Integrate icy particle gravity and lifetime fade.
local function UpdateFrontParticle(p, dt, alphaMul)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then
        p.active = false
        p.tex:SetAlpha(0)
        return
    end
    p.vy = p.vy - 110 * dt
    p.x  = p.x + p.vx * dt
    p.y  = p.y + p.vy * dt
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local a = t < 0.45 and 1 or math.max(0, (1 - t) / 0.55)
    p.tex:SetAlpha(a * 0.75 * (alphaMul or 1))
end

-- Initialize an elliptical orbit and independent rock spin.
local function SetupOrbitRock(rock)
    rock.phase = "orbit"
    rock.tex:SetTexture(PickRockTexture(math.random(1, #ROCK_TEX_POOL)))

    local base = rand(12, 28)
    rock.baseSize = base
    rock.rx = rand(ORBIT_RX_MIN, ORBIT_RX_MAX)
    rock.ry = rand(ORBIT_RY_MIN, ORBIT_RY_MAX)
    rock.orbitAngle = rand(0, math.pi * 2)
    rock.orbitSpeed = rand(ORBIT_SPEED_MIN, ORBIT_SPEED_MAX) * (math.random(2) == 1 and 1 or -1)
    rock.rot = rand(0, math.pi * 2)
    rock.rotSpeed = rand(ORBIT_SELF_ROT_MIN, ORBIT_SELF_ROT_MAX) * (math.random(2) == 1 and 1 or -1)
    rock.maxAlpha = rand(0.38, 0.72)
    rock.x = 0
    rock.y = 0
    rock.vx = 0
    rock.vy = 0

    rock.tex:SetSize(base, base)
    rock.tex:SetAlpha(0)
    rock.tex:SetRotation(rock.rot)
end

-- Move and rotate the rock around the current bar center.
local function UpdateOrbitRock(rock, dt, alphaMul, cx, cy)
    if rock.phase ~= "orbit" then return end
    if not cx then return end

    rock.orbitAngle = rock.orbitAngle + rock.orbitSpeed * dt * math.pi * 2
    rock.rot = rock.rot + rock.rotSpeed * dt

    local x = cx + math.cos(rock.orbitAngle) * rock.rx
    local y = cy + math.sin(rock.orbitAngle) * rock.ry

    rock.x, rock.y = x, y
    rock.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    rock.tex:SetAlpha(rock.maxAlpha * (alphaMul or 1))
    rock.tex:SetRotation(rock.rot)
end

-- Randomize floating rock size, reveal threshold, bobbing, and rise.
local function SetupRock(rock, kind)
    rock.kind = kind
    rock.phase = "float"
    rock.tex:SetTexture(PickRockTexture(math.random(1, #ROCK_TEX_POOL)))

    if kind == "small" then
        rock.size = rand(10, 20) * 0.60
    elseif kind == "medium" then
        rock.size = rand(20, 30) * 0.60
    else
        rock.size = rand(30, 42) * 0.60
    end

    rock.xFrac = rand(0.04, 0.96)
    rock.revealAt = rand(0.03, 0.92)
    rock.side = (math.random(2) == 1) and -1 or 1  -- Choose the upper or lower side near the bar.
    rock.yOuter = rand(-2, 4)
    rock.yBase = rand(-3, 3)
    rock.floatAmp = rand(2, 6)
    rock.floatSpeed = rand(0.8, 1.8)
    rock.floatT = rand(0, math.pi * 2)
    rock.riseSpeed = rand(2, 8)
    rock.riseOffset = rand(-4, 6)
    rock.rot = rand(0, math.pi * 2)
    rock.seed = rand(0, math.pi * 2)
    rock.rotSpeed = rand(-0.45, 0.45)
    rock.maxAlpha = rand(0.45, 0.85)
    rock.vx = 0
    rock.vy = 0
    rock.x = 0
    rock.y = 0

    rock.tex:SetSize(rock.size, rock.size)
    rock.tex:SetAlpha(0)
    rock.shownAlpha = 0
    rock.tex:SetRotation(rock.rot)
end

-- Bar center and size, read once per tick for every mist and rock.
local function BarGeometry()
    local f = SCB.Bar.frameInner
    local cx, cy = f:GetCenter()
    return cx, cy, f:GetWidth(), f:GetHeight()
end

-- Pulse and rotate mist at a fixed fraction of the bar.
local function UpdateMist(m, dt, alphaMul, cx, cy, bw)
    m.t = m.t + dt
    local pulse = 0.5 + 0.5 * math.sin(m.t * m.speed + m.seed)
    local alpha = (0.10 + pulse * 0.20) * (alphaMul or 1)
    local scale = 0.90 + 0.16 * math.sin(m.t * 0.65 + m.seed)
    if not cx then return end
    local x = cx - bw * 0.5 + bw * m.xFrac
    m.rot = m.rot + m.rotSpeed * dt
    m.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, cy + m.yOff)
    m.tex:SetSize(MIST_W * scale, MIST_H * scale)
    SetTextureRotation(m.tex, m.rot)
    m.tex:SetAlpha(alpha)
end

-- Reveal, bob, and slowly raise a fill-relative rock.
local function UpdateFloatingRock(rock, dt, progress, fillLX, fillW, cy, barH)
    rock.floatT = rock.floatT + dt * rock.floatSpeed
    rock.rot = rock.rot + rock.rotSpeed * dt
    rock.riseOffset = rock.riseOffset + rock.riseSpeed * dt

    local appear = math.min(1, math.max(0, (progress - rock.revealAt) / 0.16))
    local alpha = rock.maxAlpha * appear
    -- Not revealed yet: nothing to draw. Its motion state above still
    -- advances; position, size and turn are applied once it appears.
    if alpha <= 0 then
        if rock.shownAlpha ~= 0 then
            rock.shownAlpha = 0
            rock.tex:SetAlpha(0)
        end
        return
    end
    rock.shownAlpha = alpha

    -- Keep each rock at its fill-relative fraction with a small horizontal sway.
    local x = fillLX + fillW * rock.xFrac + math.sin(rock.floatT * 0.7 + rock.seed) * 3

    -- Combine the bar edge offset, bobbing, and continuous upward drift.
    local halfH = barH * 0.5
    local edgeBias = halfH * 0.30
    local y = (cy or 0)
        + rock.side * (edgeBias + rock.yOuter)
        + rock.yBase
        + math.sin(rock.floatT) * rock.floatAmp
        + rock.riseOffset
        + 15

    rock.x, rock.y = x, y
    rock.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    rock.tex:SetAlpha(alpha)

    local scale = 0.90 + 0.18 * (0.5 + 0.5 * math.sin(rock.floatT * 0.9 + rock.seed))
    rock.tex:SetSize(rock.size * scale, rock.size * scale)
    rock.tex:SetRotation(rock.rot)
end

-- Convert visible floating and orbiting rocks to falling debris.
local function StartFallingRocks()
    local function toFall(r)
        local a = r.tex:GetAlpha()
        if (r.phase == "float" or r.phase == "orbit") and a > 0.02 then
            r.phase = "fall"
            r.fallAlpha = a  -- keep the current opacity (partly revealed rocks)
            r.vx = rand(-18, 18)
            r.vy = rand(18, 52)
        else
            r.phase = "idle"
            r.tex:SetAlpha(0)
        end
    end

    for _, r in ipairs(rocks) do toFall(r) end
    for _, r in ipairs(orbitRocks) do toFall(r) end
end

-- Apply gravity and faster spin during the ending fade.
local function UpdateFallingRock(rock, dt, alphaMul)
    if rock.phase ~= "fall" then return end
    rock.vy = rock.vy - FALL_GRAVITY * dt
    rock.x  = rock.x + rock.vx * dt
    rock.y  = rock.y + rock.vy * dt
    rock.rot = rock.rot + rock.rotSpeed * dt * 1.8

    rock.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", rock.x, rock.y)
    rock.tex:SetAlpha((alphaMul or 1) * (rock.fallAlpha or rock.maxAlpha))
    rock.tex:SetRotation(rock.rot)
end

function FX.Init(container, bar)
    local _underlay = SCB.Bar and SCB.Bar.bgUnderlayHost or bar

    for i = 1, MIST_COUNT do
        local t = _underlay:CreateTexture(nil, "BACKGROUND", nil, -2)
        t:SetTexture(TEX_FROST .. "Mist_Frost_01")
        t:SetBlendMode("ADD")
        t:SetSize(MIST_W, MIST_H)
        t:SetAlpha(0)
        mists[i] = {
            tex = t, xFrac = MIST_POS[i], yOff = rand(-6, 6),
            t = rand(0, 7), speed = rand(0.7, 1.3), seed = rand(0, 7),
            rot = rand(0, math.pi * 2), rotSpeed = rand(-0.06, 0.06),
        }
    end

    local function allocRocks(count, kind)
        for _ = 1, count do
            local t = _underlay:CreateTexture(nil, "BACKGROUND", nil, -4)
            t:SetAlpha(0)
            local r = { tex = t, phase = "idle" }
            SetupRock(r, kind)
            rocks[#rocks + 1] = r
        end
    end

    allocRocks(ROCK_SMALL_COUNT, "small")
    allocRocks(ROCK_MEDIUM_COUNT, "medium")
    allocRocks(ROCK_BIG_COUNT, "big")

    for _ = 1, ORBIT_MISC_COUNT do
        local t = _underlay:CreateTexture(nil, "BACKGROUND", nil, -5)
        t:SetAlpha(0)
        local r = { tex = t, phase = "idle" }
        SetupOrbitRock(r)
        orbitRocks[#orbitRocks + 1] = r
    end

    for i = 1, FRONT_PART_COUNT do
        local t = container:CreateTexture(nil, "OVERLAY")
        t:SetTexture(FRONT_TEX[(i % 2) + 1])
        t:SetBlendMode("ADD")
        t:SetAlpha(0)
        frontParts[i] = { tex=t, active=false, life=0, maxLife=0, x=0, y=0, vx=0, vy=0 }
    end
end

function FX.Start(duration)
    active = true
    fading = false
    fadeT = 0
    spawnAcc = 0

    for i, m in ipairs(mists) do
        m.t = i * 0.25
        m.tex:SetAlpha(0)
    end

    for _, r in ipairs(rocks) do
        SetupRock(r, r.kind)
    end
    for _, r in ipairs(orbitRocks) do
        SetupOrbitRock(r)
    end

    for _, p in ipairs(frontParts) do
        p.active = false
        p.tex:SetAlpha(0)
    end
end

function FX.Stop()
    active = false
    fading = true
    fadeT = 0
    StartFallingRocks()
end

function FX.Reset()
    active = false
    fading = false
    for _, m in ipairs(mists) do m.tex:SetAlpha(0) end
    for _, r in ipairs(rocks) do r.phase = "idle" ; r.tex:SetAlpha(0) end
    for _, r in ipairs(orbitRocks) do r.phase = "idle" ; r.tex:SetAlpha(0) end
    for _, p in ipairs(frontParts) do p.active = false ; p.tex:SetAlpha(0) end
end

function FX.UpdateFade(dt)
    if not fading then return end
    fadeT = fadeT + dt
    local fade = 1

    local cx, cy, bw = BarGeometry()
    for _, m in ipairs(mists) do UpdateMist(m, dt, fade, cx, cy, bw) end
    for _, r in ipairs(rocks) do UpdateFallingRock(r, dt, fade) end
    for _, r in ipairs(orbitRocks) do UpdateFallingRock(r, dt, fade) end
    for _, p in ipairs(frontParts) do UpdateFrontParticle(p, dt, fade) end

    if fadeT >= SCB.FX_LINGER then
        fading = false
        for _, m in ipairs(mists) do m.tex:SetAlpha(0) end
        for _, r in ipairs(rocks) do r.phase = "idle" ; r.tex:SetAlpha(0) end
        for _, r in ipairs(orbitRocks) do r.phase = "idle" ; r.tex:SetAlpha(0) end
        for _, p in ipairs(frontParts) do p.active = false ; p.tex:SetAlpha(0) end
    end
end

function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    local bcx, bcy, bw, bh = BarGeometry()
    for _, m in ipairs(mists) do UpdateMist(m, dt, 1, bcx, bcy, bw) end

    for _, p in ipairs(frontParts) do UpdateFrontParticle(p, dt, 1) end

    if not active then return end

    for _, r in ipairs(rocks) do
        if r.phase == "float" then
            UpdateFloatingRock(r, dt, progress, fillLX, fillW, bcy, bh)
        end
    end
    for _, r in ipairs(orbitRocks) do
        if r.phase == "orbit" then
            UpdateOrbitRock(r, dt, 1, bcx, bcy)
        end
    end

    spawnAcc = spawnAcc + dt
    if SCB.Particles.emitProgress > 0.02 and SCB.Particles.emitProgress < 0.985 and spawnAcc >= FRONT_SPAWN_RATE then
        spawnAcc = 0
        local n = math.random(1, 3)
        for _ = 1, n do SpawnFront(frontX, cy) end
    end
end
