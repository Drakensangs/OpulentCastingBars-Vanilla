-- ============================================================
--  Opulent Casting Bars -- Particles_Arcaneum.lua
--  A progressively revealed central rune, orbiting rocks and magenta front particles.
-- ============================================================

local S = {}  -- Shared effect state and tuning.
local FX = {}
SCB.FX = SCB.FX or {}
SCB.FX["arcaneum"] = FX

local function rand(a, b) return a + math.random() * (b - a) end
local function rad(deg)   return deg * math.pi / 180 end
local function lerp(a, b, t) return a + (b - a) * math.max(0, math.min(t, 1)) end
local function Clamp01(v)
    if type(v) ~= "number" or v ~= v then return 0 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

S.TEX_ARCANEUM = SCB.TEX_PATH .. "arcaneum\\"

S.ORBIT_MISC_COUNT = 10
S.ORBIT_RX_MIN = 105
S.ORBIT_RX_MAX = 145
S.ORBIT_RY_MIN = 14
S.ORBIT_RY_MAX = 32
S.ORBIT_SPEED_MIN = 0.18
S.ORBIT_SPEED_MAX = 0.38
S.ORBIT_SELF_ROT_MIN = 0.35
S.ORBIT_SELF_ROT_MAX = 1.15

S.FALL_GRAVITY = 260

S.RUNE_SIZE = 180
S.RUNE_ALPHA = 0.42
S.RUNE_ROT_SPEED = 0.55

-- Magenta fill-front ash tuning.

S.EMBER_COUNT = 130
S.EMBER_SPAWN = 0.016

S.emberTypes = {
    { sizeMin=8,  sizeMax=18, speedMin=22, speedMax=65,  lifeMin=0.9, lifeMax=2.0, gravity=5,  spread=170, driftX=0.6 },
    { sizeMin=4,  sizeMax=10, speedMin=75, speedMax=180, lifeMin=0.3, lifeMax=0.8, gravity=11, spread=100, driftX=0.0 },
    { sizeMin=5,  sizeMax=15, speedMin=38, speedMax=95,  lifeMin=0.7, lifeMax=1.5, gravity=16, spread=130, driftX=0.4 },
}

S.EMBER_COLORS = {
    { 1.0,  0.15, 0.85 },
    { 0.90, 0.05, 0.95 },
    { 1.0,  0.30, 0.75 },
    { 0.85, 0.10, 1.0  },
}

-- Additive pixel-spark tuning.

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
    { 1.0,  0.15, 0.90, 1.0  },
    { 0.90, 0.10, 1.0,  0.90 },
    { 1.0,  0.35, 0.85, 0.65 },
    { 0.95, 0.05, 0.80, 0.75 },
    { 1.0,  0.50, 0.95, 0.50 },
    { 0.80, 0.10, 0.95, 0.85 },
}

-- Activity, pools and fade timers.

S.orbitRocks = {}
S.emberParts = {} ; S.sparkParts = {}
S.active = false ; S.fading = false
S.fadeT = 0 ; S.runeTimer = 0
S.emberSpawnAcc = 0 ; S.sparkSpawnAcc = 0
S.castDuration = 5
S.runeSwap = false
S.runeRevealAlpha = 0

S.texRuneCenter = nil
S.texRuneClip = nil
S.runeLaidReveal = nil   -- reveal last applied to the rune clip (nil = force)
S.runeLaidBarW = nil
-- Inactive ash particles per type: when a type is used up, SpawnEmber skips
-- scanning the whole pool (it is saturated most of a cast).
S.emberFree = { 0, 0, 0 }
S.rune01Tex = nil
S.rune02Tex = nil

-- Texture rotation and rune reveal geometry.

local function SetTextureRotation(tex, angle)
    local c, s = math.cos(angle), math.sin(angle)
    tex:SetTexCoord(
        0.5 + (-0.5)*c - (-0.5)*s, 0.5 + (-0.5)*s + (-0.5)*c,
        0.5 + (-0.5)*c - ( 0.5)*s, 0.5 + (-0.5)*s + ( 0.5)*c,
        0.5 + ( 0.5)*c - (-0.5)*s, 0.5 + ( 0.5)*s + (-0.5)*c,
        0.5 + ( 0.5)*c - ( 0.5)*s, 0.5 + ( 0.5)*s + ( 0.5)*c
    )
end

local function GetRuneReveal(frontX)
    local f = SCB.Bar and SCB.Bar.frameInner
    if not f or not frontX then return 0 end
    local barW2 = SCB.Config and SCB.Config:Get("barWidth") or 400
-- Convert the screen-space front position to a bar-local coordinate.
    local barLeft = f:GetLeft() or 0
    local frontXRel = frontX - barLeft
    local runeLeft = (barW2 - S.RUNE_SIZE) * 0.5
    return Clamp01((frontXRel - runeLeft) / S.RUNE_SIZE)
end

local function SetRuneReveal(reveal)
    if not S.texRuneCenter then return end

    reveal = Clamp01(reveal)
    S.runeRevealAlpha = reveal
    local barW = SCB.Config and SCB.Config:Get("barWidth") or 400
    -- Most ticks the front is before or past the rune (reveal stays 0 or 1):
    -- nothing to re-apply then.
    if reveal == S.runeLaidReveal and barW == S.runeLaidBarW then return end

    if reveal <= 0 then
        S.texRuneCenter:SetAlpha(0)
        S.texRuneClip:Hide()
    else
        local f = SCB.Bar and SCB.Bar.frameInner
        if not f or not barW or barW <= 0 then return end
        local runeLeft = (barW - S.RUNE_SIZE) * 0.5
        S.texRuneClip:Layout(f, runeLeft, S.RUNE_SIZE, 18, S.RUNE_SIZE, reveal)
        S.texRuneCenter:SetAlpha(S.RUNE_ALPHA)
    end
    S.runeLaidReveal, S.runeLaidBarW = reveal, barW
end

-- Rock texture selection and orbit animation.

local function BuildRockTexturePool()
    local pool = {}
    for i = 1, 8 do pool[#pool + 1] = S.TEX_ARCANEUM .. string.format("Misc_Arcaneum_%02d", i) end
    for i = 1, 2 do pool[#pool + 1] = S.TEX_ARCANEUM .. string.format("Misc_Arcaneum_Medium_%02d", i) end
    for i = 1, 2 do pool[#pool + 1] = S.TEX_ARCANEUM .. string.format("Misc_Arcaneum_Big_%02d", i) end
    return pool
end

S.ROCK_TEX_POOL = BuildRockTexturePool()

local function PickRockTexture(i)
    return S.ROCK_TEX_POOL[((i - 1) % #S.ROCK_TEX_POOL) + 1]
end

local function SetupOrbitRock(rock)
    rock.phase = "orbit"
    rock.tex:SetTexture(PickRockTexture(math.random(1, #S.ROCK_TEX_POOL)))
    local base = rand(12, 28)
    rock.baseSize = base
    rock.rx = rand(S.ORBIT_RX_MIN, S.ORBIT_RX_MAX)
    rock.ry = rand(S.ORBIT_RY_MIN, S.ORBIT_RY_MAX)
    rock.orbitAngle = rand(0, math.pi * 2)
    rock.orbitSpeed = rand(S.ORBIT_SPEED_MIN, S.ORBIT_SPEED_MAX) * (math.random(2) == 1 and 1 or -1)
    rock.rot = rand(0, math.pi * 2)
    rock.rotSpeed = rand(S.ORBIT_SELF_ROT_MIN, S.ORBIT_SELF_ROT_MAX) * (math.random(2) == 1 and 1 or -1)
    rock.maxAlpha = rand(0.38, 0.72)
    rock.tex:SetSize(base, base)
    rock.tex:SetAlpha(0)
    SetTextureRotation(rock.tex, rock.rot)
end

-- cx, cy: bar center, read once per tick by FX.Update.
local function UpdateOrbitRock(rock, dt, cx, cy)
    if rock.phase ~= "orbit" then return end
    rock.orbitAngle = rock.orbitAngle + rock.orbitSpeed * dt * math.pi * 2
    rock.rot = rock.rot + rock.rotSpeed * dt
    local x = cx + math.cos(rock.orbitAngle) * rock.rx
    local y = cy + math.sin(rock.orbitAngle) * rock.ry
    rock.x, rock.y = x, y
    rock.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    rock.tex:SetAlpha(rock.maxAlpha)   -- size was set by SetupOrbitRock
    SetTextureRotation(rock.tex, rock.rot)
end

local function UpdateFallingRock(rock, dt)
    if rock.phase ~= "fall" then return end
    rock.vy = rock.vy - S.FALL_GRAVITY * dt
    rock.x = rock.x + rock.vx * dt
    rock.y = rock.y + rock.vy * dt
    rock.rot = rock.rot + rock.rotSpeed * dt * 1.8
    rock.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", rock.x, rock.y)
    rock.tex:SetAlpha(rock.maxAlpha)
    SetTextureRotation(rock.tex, rock.rot)
end

local function StartFallingRocks()
    local function toFall(r)
        if r.phase == "orbit" and r.tex:GetAlpha() > 0.02 then
            r.phase = "fall" ; r.vx = rand(-18, 18) ; r.vy = rand(18, 52)
        else
            r.phase = "idle" ; r.tex:SetAlpha(0)
        end
    end
    for _, r in ipairs(S.orbitRocks) do toFall(r) end
end

-- Fill-front ash spawning and motion.

local function SpawnEmber(wx, wy)
    local roll    = math.random(10)
    local typeIdx = roll <= 4 and 1 or (roll <= 7 and 3 or 2)
    if S.emberFree[typeIdx] <= 0 then return end   -- every one is in flight
    local ptype   = S.emberTypes[typeIdx]
    local col     = S.EMBER_COLORS[math.random(#S.EMBER_COLORS)]

    for _, p in ipairs(S.emberParts) do
        if not p.active and p.typeIdx == typeIdx then
            S.emberFree[typeIdx] = S.emberFree[typeIdx] - 1
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

local function UpdateEmber(p, dt, globalFade)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then
        p.active = false ; p.tex:SetAlpha(0)
        S.emberFree[p.typeIdx] = S.emberFree[p.typeIdx] + 1
        return
    end
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

-- Pixel-spark spawning and motion.

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

-- Effect lifecycle and texture-pool construction.

function FX.Init(container, bar)
    local school = SCB.Schools.data["arcaneum"]
    S.rune01Tex = school and school.rune01 or (SCB.TEX_PATH .. "arcane\\Rune_01")
    S.rune02Tex = school and school.rune02 or (SCB.TEX_PATH .. "arcane\\Rune_02")

    local _underlay = SCB.Bar and SCB.Bar.bgUnderlayHost or bar
    -- Clip.lua always loads before this file (TOC order).
    S.texRuneClip = SCB.Clip:New(bar)
    S.texRuneClip:SetFixed()   -- revealed by its own fraction, not the front
    local runeLevel = math.max(0, (bar:GetFrameLevel() or 0) - 1)
    S.texRuneClip:SetFrameLevel(runeLevel)
    local child = S.texRuneClip:GetChild()
    child:SetFrameLevel(runeLevel)
    S.texRuneCenter = child:CreateTexture(nil, "BACKGROUND")
    S.texRuneCenter:SetAllPoints(child)
    S.texRuneClip:Hide()
    S.texRuneCenter:SetTexture(S.rune01Tex)
    S.texRuneCenter:SetBlendMode("ADD")
    S.texRuneCenter:SetAlpha(0)

    for _ = 1, S.ORBIT_MISC_COUNT do
        local t = _underlay:CreateTexture(nil, "BACKGROUND")
        t:SetAlpha(0)
        local r = { tex = t, phase = "idle" }
        SetupOrbitRock(r)
        S.orbitRocks[#S.orbitRocks + 1] = r
    end

-- Use Arcaneum particle textures for the ash pool.
    local FRONT_TEX = {
        S.TEX_ARCANEUM .. "Particle_Arcaneum_01",
        S.TEX_ARCANEUM .. "Particle_Arcaneum_02",
    }
    local function getMisc(i)
        return FRONT_TEX[((i - 1) % #FRONT_TEX) + 1]
    end

-- Build the ash pool.
    S.emberParts = {}
    S.emberFree = { 0, 0, 0 }
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
        S.emberFree[typeIdx] = S.emberFree[typeIdx] + 1
    end

-- Build the pixel-spark pool.
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
end

-- Hide every ash particle and mark the whole pool as free.
local function ClearEmbers()
    for _, p in ipairs(S.emberParts) do p.active = false ; p.tex:SetAlpha(0) end
    S.emberFree[1], S.emberFree[2], S.emberFree[3] = 0, 0, 0
    for _, p in ipairs(S.emberParts) do
        S.emberFree[p.typeIdx] = S.emberFree[p.typeIdx] + 1
    end
end

function FX.Start(duration)
    S.castDuration   = duration or 5
    S.active, S.fading, S.fadeT = true, false, 0
    S.runeTimer      = 0
    S.runeRevealAlpha = 0
    S.emberSpawnAcc  = 0
    S.sparkSpawnAcc  = 0

    if S.texRuneCenter then
        S.texRuneCenter:SetTexture(S.runeSwap and S.rune02Tex or S.rune01Tex)
        S.runeLaidReveal = nil   -- force the hide below
        SetRuneReveal(0)
        SetTextureRotation(S.texRuneCenter, 0)
    end
    S.runeSwap = not S.runeSwap

    for _, r in ipairs(S.orbitRocks) do SetupOrbitRock(r) end
    ClearEmbers()
    for _, p in ipairs(S.sparkParts) do p.active = false ; p.tex:SetAlpha(0) end
end

function FX.Stop()
    S.active, S.fading, S.fadeT = false, true, 0
    StartFallingRocks()
end

function FX.Reset()
    S.active, S.fading = false, false
    S.runeLaidReveal = nil
    SetRuneReveal(0)
    for _, r in ipairs(S.orbitRocks) do r.phase = "idle" ; r.tex:SetAlpha(0) end
    ClearEmbers()
    for _, p in ipairs(S.sparkParts) do p.active = false ; p.tex:SetAlpha(0) end
end

function FX.UpdateFade(dt)
    if not S.fading then return end
    S.fadeT = S.fadeT + dt
    local fade = 1
    SetRuneReveal(S.runeRevealAlpha)   -- no-op unless the bar width changed
    for _, r in ipairs(S.orbitRocks) do UpdateFallingRock(r, dt) end
    for _, p in ipairs(S.emberParts) do UpdateEmber(p, dt, fade) end
    for _, p in ipairs(S.sparkParts) do UpdateSpark(p,  dt, fade) end
    if S.fadeT >= SCB.FX_LINGER then FX.Reset() end
end

function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    if S.texRuneCenter and S.active then
        S.runeTimer = S.runeTimer + dt
        local reveal = GetRuneReveal(frontX)
        -- The rune is hidden until the front reaches it; skip spinning it then.
        if reveal > 0 then
            SetTextureRotation(S.texRuneCenter, S.runeTimer * S.RUNE_ROT_SPEED)
        end
        SetRuneReveal(reveal)
    end

    if not S.active then return end

    local bcx, bcy = SCB.Bar.frameInner:GetCenter()
    if bcx then
        for _, r in ipairs(S.orbitRocks) do
            if r.phase == "orbit" then UpdateOrbitRock(r, dt, bcx, bcy) end
        end
    end

-- Spawn magenta ash at the fill front.
    for _, p in ipairs(S.emberParts) do UpdateEmber(p, dt, 1) end
    S.emberSpawnAcc = S.emberSpawnAcc + dt
    if S.emberSpawnAcc >= S.EMBER_SPAWN then
        S.emberSpawnAcc = 0
        local count = math.random(4, 8)
        for _ = 1, count do SpawnEmber(frontX, cy) end
    end

-- Spawn pixel sparks at the fill front.
    for _, p in ipairs(S.sparkParts) do UpdateSpark(p, dt, 1) end
    S.sparkSpawnAcc = S.sparkSpawnAcc + dt
    if S.sparkSpawnAcc >= S.SPARK_SPAWN then
        S.sparkSpawnAcc = 0
        local count = math.random(3, 6)
        for _ = 1, count do SpawnSpark(frontX, cy) end
    end
end
