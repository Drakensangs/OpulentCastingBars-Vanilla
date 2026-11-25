-- ============================================================
--  Opulent Casting Bars -- Particles_Earth.lua
--  Orbiting rocks and debris with fragments emitted at the fill front.
-- ============================================================

-- Effect tuning: counts, timing, geometry, and colors.
local FX = {}
SCB.FX        = SCB.FX or {}
SCB.FX["earth"] = FX

-- Sample a uniform value within the given range.
local function rand(a, b) return a + math.random() * (b - a) end
-- Convert degrees to radians.
local function rad(deg)   return deg * math.pi / 180 end

local ROCK_COUNT        = 4
local ROCK_SIZE         = 28
local ROCK_ORBIT_RX_MIN = 130
local ROCK_ORBIT_RX_MAX = 160
local ROCK_ORBIT_RY_MIN = 28
local ROCK_ORBIT_RY_MAX = 42
local ROCK_SPEED_MIN    = 0.18
local ROCK_SPEED_MAX    = 0.28
local ROCK_SELF_ROT     = 1.2
local ROCK_ALPHA        = 0.90

local DEBRIS_COUNT      = 14
local DEBRIS_SIZE_MIN   = 10
local DEBRIS_SIZE_MAX   = 18
local DEBRIS_ORBIT_RX_MIN = 100
local DEBRIS_ORBIT_RX_MAX = 135
local DEBRIS_ORBIT_RY_MIN = 18
local DEBRIS_ORBIT_RY_MAX = 36
local DEBRIS_SPEED_MIN  = 0.30
local DEBRIS_SPEED_MAX  = 0.55
local DEBRIS_SELF_ROT   = 2.5
local DEBRIS_ALPHA      = 0.75

local PART_COUNT      = 50
local PART_SPAWN_RATE = 0.035
local PART_STOP_AT    = 0.87
local PART_ALPHA      = 0.85

local rocks    = {}
local debris   = {}
-- Particle pools and cast lifecycle state.
local parts    = {}
local spawnAcc = 0
local isActive = false

-- Advance an elliptical orbit, texture rotation, and initial fade-in.
local function UpdateOrbit(obj, dt, cx, cy)
    obj.angle    = obj.angle    + obj.speed    * dt * math.pi * 2
    obj.selfAngle = obj.selfAngle + obj.selfRot * dt

    local x = cx + math.cos(obj.angle) * obj.rx
    local y = cy + math.sin(obj.angle) * obj.ry

    if obj.fadeIn < 1 then
        obj.fadeIn = math.min(obj.fadeIn + dt / 1.0, 1)
        obj.tex:SetAlpha(obj.fadeIn * obj.maxAlpha)
    end

    obj.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    obj.tex:SetRotation(obj.selfAngle)
end

-- Activate an idle particle and initialize its motion.
local function SpawnParticle(frontX, cy)
    for _, p in ipairs(parts) do
        if not p.active then
            local angle = rad(rand(50, 130))
            local speed = rand(40, 110)
            p.active  = true
            p.life    = 0
            p.maxLife = rand(0.4, 0.9)
            p.x       = frontX + rand(-3, 3)
            p.y       = cy + rand(-8, 8)
            p.vx      = math.cos(angle) * speed
            p.vy      = math.sin(angle) * speed

            local size = rand(6, 14)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            p.tex:SetSize(size, size)

            p.tex:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
            p.tex:SetAlpha(PART_ALPHA)
            return
        end
    end
end

-- Advance particle motion and its lifetime opacity envelope.
local function UpdateParticle(p, dt)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end

    p.vy = p.vy - 120 * dt
    p.x  = p.x + p.vx * dt
    p.y  = p.y + p.vy * dt

    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)

    local alpha = t < 0.6 and 1 or math.max(0, (1 - t) / 0.4)
    p.tex:SetAlpha(alpha * PART_ALPHA)
end

-- Create textures and initialize the particle pools.
function FX.Init(container, bar)
    local school = SCB.Schools.data["earth"]
    if not school then return end

    local rockTex   = school.rocks
    local debrisTex = school.debris
    local _underlay = SCB.Bar and SCB.Bar.bgUnderlayHost or bar

    for i = 1, ROCK_COUNT do
        local tex = _underlay:CreateTexture(nil, "BACKGROUND", nil, -8)
        tex:SetTexture(rockTex[((i - 1) % #rockTex) + 1])
        tex:SetBlendMode("BLEND")
        tex:SetSize(ROCK_SIZE, ROCK_SIZE)
        tex:SetAlpha(0)

        rocks[i] = {
            tex       = tex,
            angle     = (i - 1) * (math.pi * 2 / ROCK_COUNT),
            selfAngle = rand(0, math.pi * 2),
            speed     = rand(ROCK_SPEED_MIN, ROCK_SPEED_MAX) * (math.random(2) == 1 and 1 or -1),
            selfRot   = rand(ROCK_SELF_ROT * 0.5, ROCK_SELF_ROT) * (math.random(2) == 1 and 1 or -1),
            rx        = rand(ROCK_ORBIT_RX_MIN, ROCK_ORBIT_RX_MAX),
            ry        = rand(ROCK_ORBIT_RY_MIN, ROCK_ORBIT_RY_MAX),
            maxAlpha  = ROCK_ALPHA,
            fadeIn    = 0,
        }
    end

    for i = 1, DEBRIS_COUNT do
        local tex = _underlay:CreateTexture(nil, "BACKGROUND", nil, -8)
        tex:SetTexture(debrisTex[((i - 1) % #debrisTex) + 1])
        tex:SetBlendMode("BLEND")
        local size = rand(DEBRIS_SIZE_MIN, DEBRIS_SIZE_MAX)
        tex:SetSize(size, size)
        tex:SetAlpha(0)

        debris[i] = {
            tex       = tex,
            angle     = (i - 1) * (math.pi * 2 / DEBRIS_COUNT) + math.pi / DEBRIS_COUNT,
            selfAngle = rand(0, math.pi * 2),
            speed     = rand(DEBRIS_SPEED_MIN, DEBRIS_SPEED_MAX) * (math.random(2) == 1 and 1 or -1),
            selfRot   = rand(DEBRIS_SELF_ROT * 0.5, DEBRIS_SELF_ROT) * (math.random(2) == 1 and 1 or -1),
            rx        = rand(DEBRIS_ORBIT_RX_MIN, DEBRIS_ORBIT_RX_MAX),
            ry        = rand(DEBRIS_ORBIT_RY_MIN, DEBRIS_ORBIT_RY_MAX),
            maxAlpha  = DEBRIS_ALPHA,
            fadeIn    = 0,
        }
    end

    for i = 1, PART_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(debrisTex[((i - 1) % #debrisTex) + 1])
        tex:SetBlendMode("BLEND")
        tex:SetAlpha(0)

        parts[i] = {
            tex = tex, active = false,
            life = 0, maxLife = 0,
            x = 0, y = 0, vx = 0, vy = 0,
        }
    end
end

-- Begin a cast and reset existing particles.
function FX.Start(duration)
    isActive = true
    spawnAcc = 0

    for _, r in ipairs(rocks)   do r.fadeIn = 0 ; r.tex:SetAlpha(0) end
    for _, d in ipairs(debris)  do d.fadeIn = 0 ; d.tex:SetAlpha(0) end
    for _, p in ipairs(parts)   do p.active = false ; p.tex:SetAlpha(0) end
end

-- End emission and begin effect cleanup.
function FX.Stop()
    isActive = false
end

-- Keep rocks, debris and particles moving while the bar fades them out
-- (no new spawns: isActive is false). FX.Reset() hides them afterwards.
function FX.UpdateFade(dt)
    local f = SCB.Bar.frame
    local cx, barCY = f:GetCenter()
    if not cx then return end
    for _, r in ipairs(rocks)  do UpdateOrbit(r, dt, cx, barCY) end
    for _, d in ipairs(debris) do UpdateOrbit(d, dt, cx, barCY) end
    for _, p in ipairs(parts)  do UpdateParticle(p, dt) end
end

-- Hide effect textures and clear particle activity.
function FX.Reset()
    isActive = false
    for _, r in ipairs(rocks)  do r.tex:SetAlpha(0) ; r.fadeIn = 0 end
    for _, d in ipairs(debris) do d.tex:SetAlpha(0) ; d.fadeIn = 0 end
    for _, p in ipairs(parts)  do p.active = false ; p.tex:SetAlpha(0) end
end

-- Advance the active cast effect and emit new particles.
function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    local f = SCB.Bar.frame
    local cx, barCY = f:GetCenter()
    if not cx then return end

    for _, r in ipairs(rocks)  do UpdateOrbit(r, dt, cx, barCY) end

    for _, d in ipairs(debris) do UpdateOrbit(d, dt, cx, barCY) end

    for _, p in ipairs(parts)  do UpdateParticle(p, dt) end

    if isActive and SCB.Particles.emitProgress > 0.02 and SCB.Particles.emitProgress < PART_STOP_AT then
        spawnAcc = spawnAcc + dt
        if spawnAcc >= PART_SPAWN_RATE then
            spawnAcc = 0
            local count = math.random(1, 3)
            for _ = 1, count do SpawnParticle(frontX, barCY) end
        end
    end
end
