-- ============================================================
--  Opulent Casting Bars -- Particles_Water.lua
--  Blue glow and droplets at the fill front, and rotating water
--  circles cut in half along the bar's middle line.
-- ============================================================

local S = {}  -- Shared effect state and tuning.
local FX = {}
SCB.FX           = SCB.FX or {}
SCB.FX["water"]  = FX

local function rand(a, b)   return a + math.random() * (b - a) end
local function lerp(a, b, t) return a + (b - a) * math.max(0, math.min(t, 1)) end
local function rad(deg)      return deg * math.pi / 180 end
S.pi2 = math.pi * 2

-- Water tint: #3bbcdc.
S.WATER_R = 0x3b/255 ; S.WATER_G = 0xbc/255 ; S.WATER_B = 0xdc/255

-- Short-lived fill-front glow.
S.GLOW_COUNT = 60
S.GLOW_SPAWN_RATE = 0.02
S.GLOW_STOP_AT = 0.87
S.GLOW_ALPHA = 0.55
S.GLOW_SIZE_MIN = 4
S.GLOW_SIZE_MAX = 9
S.GLOW_LIFE_MIN = 0.10
S.GLOW_LIFE_MAX = 0.20

-- Droplet physics and spawn interval.
S.EMBER_COUNT = 60
S.EMBER_SPAWN = 0.03

S.emberTypes = {
    { sizeMin=8,  sizeMax=14, speedMin=25,  speedMax=60,  lifeMin=0.8, lifeMax=1.6, gravity=8,  spread=140, driftX=0.4 },
    { sizeMin=4,  sizeMax=8,  speedMin=80,  speedMax=160, lifeMin=0.3, lifeMax=0.7, gravity=15, spread=80,  driftX=0.0 },
    { sizeMin=6,  sizeMax=12, speedMin=40,  speedMax=90,  lifeMin=0.6, lifeMax=1.2, gravity=20, spread=100, driftX=0.2 },
}

-- Water-circle lifetime, opacity and scale.
S.CIRCLE_COUNT = 12
S.CIRCLE_SPAWN_MIN = 0.20  -- Minimum circle spawn interval (s).
S.CIRCLE_SPAWN_MAX = 0.37  -- Maximum circle spawn interval (s).
S.CIRCLE_LIFE_MIN = 1.20
S.CIRCLE_LIFE_MAX = 2.20
S.CIRCLE_ALPHA_MAX = 0.80
S.CIRCLE_FG_ALPHA_MAX = S.CIRCLE_ALPHA_MAX * 0.50
S.CIRCLE_SCALE_MIN = 0.80
S.CIRCLE_SCALE_MAX = 1.48

S.CIRCLE_CLIP_OFFSET = 0      -- clip line, as a share of bar height from the center (0.5 = edge)
S.CIRCLE_OFFSET_Y    = 0      -- circle-center distance beyond the clip line (px)
S.CIRCLE_OFFSET_X    = 0      -- horizontal shift of circle centers (px)
S.CIRCLE_SIZE_FACTOR = 0.4    -- base diameter, as a multiple of bar height
S.CIRCLE_STRETCH_X   = 1.8    -- texture width multiplier (height unchanged)
S.CIRCLE_SPREAD      = 0.5    -- spawn spread, as a share of the fill width
S.CIRCLE_MAX_WIDTH   = 9999   -- maximum spawn-zone width (px)

-- Activity, particle pools and spawn timers.
S.isActive = false
S.partsFading = false
S.partsFadeT = 0
S.castDuration = 5

S.glowParts = {}
S.glowSpawnAcc = 0

S.emberParts = {}
S.emberSpawnAcc = 0

S.circleParts = {}
S.circleAcc = 0
S.circleNext = 0

S.circleFGParts = {}
S.circleFGAcc = 0
S.circleFGNext = 0

-- Fill-front glow spawning and motion.
local function SpawnGlow(frontX, cy, barH)
    for _, p in ipairs(S.glowParts) do
        if not p.active then
            local spread  = math.min(barH * 0.25, 10)
            p.active  = true
            p.life    = 0
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

local function UpdateGlow(p, dt)
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    p.vy = p.vy * 0.90 ^ (dt * 60)
    p.y  = p.y + p.vy * dt + math.sin(p.life * 10 + p.phase) * 0.3 * (dt * 60)
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local env
    if     t < 0.2 then env = t / 0.2
    elseif t < 0.8 then env = 1
    else             env = (1 - t) / 0.2 end
    p.tex:SetAlpha(math.max(0, env) * S.GLOW_ALPHA)
end

-- Droplet spawning and motion.
local function SpawnEmber(wx, wy)
    local roll    = math.random(10)
    local typeIdx = roll <= 4 and 1 or (roll <= 7 and 3 or 2)
    local ptype   = S.emberTypes[typeIdx]
    for _, p in ipairs(S.emberParts) do
        if not p.active and p.typeIdx == typeIdx then
            local tCast = math.max(0, math.min((S.castDuration - 2) / 3, 1))
            local speed = rand(
                lerp(ptype.speedMax * 0.5, ptype.speedMin,       tCast),
                lerp(ptype.speedMax,       ptype.speedMax * 0.8, tCast))
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

local function UpdateEmber(p, dt)
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    p.vy = p.vy - p.ptype.gravity * dt
    p.vx = p.vx + p.drift * dt * (1 - t)
    p.x  = p.x  + p.vx * dt
    p.y  = p.y  + p.vy * dt
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    local alpha
    if p.typeIdx == 2 then
        alpha = t < 0.15 and 1 or math.max(0, 1 - (t - 0.15) / 0.85)
    else
        alpha = t < 0.5  and 1 or math.max(0, (1 - t) / 0.5)
    end
    p.tex:SetAlpha(alpha * 0.85)
end

-- Rotate a UV point around the texture center (c, s = cos/sin of the angle,
-- computed once per circle by the caller).
local function RotateCircleUV(u, v, c, s)
    local x, y = u - 0.5, v - 0.5
    return 0.5 + x * c - y * s, 0.5 + x * s + y * c
end

-- Absolute circle rotation speed range (rad/s).
S.CIRCLE_ROT_SPEED_MIN = 0.25
S.CIRCLE_ROT_SPEED_MAX = 0.80

-- Water-circle slicing, spawning and animation.
-- A circle never moves: its slice (the half on one side of the clip line)
-- is laid out once at spawn, and each tick only turns its texture
-- coordinates (the art rotates inside the fixed slice).

-- Lay out the slice of a freshly spawned circle. Returns false when the
-- slice is empty (the circle then stays hidden for its whole life).
local function LayoutCircleSlice(p)
    local diameter = p.diameter or 0
    local radius   = p.radius or 0
    if diameter <= 0 or radius <= 0 then return false end

    -- The slice keeps the circle's whole width ...
    local stretchW   = p.stretchW or diameter
    local sliceLeft  = p.x - stretchW * 0.5
    local sliceRight = p.x + stretchW * 0.5

    -- ... and the half on the outer side of the clip line.
    local texBottom = p.y - radius
    local texTop    = p.y + radius
    local sliceBottom = p.isAbove and p.clipY or texBottom
    local sliceTop    = p.isAbove and texTop   or p.clipY
    if sliceBottom < texBottom then sliceBottom = texBottom end
    if sliceTop > texTop then sliceTop = texTop end

    local sliceH = sliceTop - sliceBottom
    if sliceH <= 0 then return false end

    local vTop    = (texTop - sliceTop)    / diameter
    local vBottom = (texTop - sliceBottom) / diameter
    if vTop < 0 then vTop = 0 end
    if vBottom > 1 then vBottom = 1 end
    p.vTop, p.vBottom = vTop, vBottom

    p.tex:SetSize(sliceRight - sliceLeft, sliceH)
    p.tex:ClearAllPoints()
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
        (sliceLeft + sliceRight) * 0.5, (sliceBottom + sliceTop) * 0.5)
    return true
end

-- Turn the art inside the slice to the circle's current angle.
local function RotateCircleSlice(p)
    local angle = p.angle or 0
    local c, s = math.cos(angle), math.sin(angle)
    local tlU, tlV = RotateCircleUV(0, p.vTop,    c, s)
    local blU, blV = RotateCircleUV(0, p.vBottom, c, s)
    local trU, trV = RotateCircleUV(1, p.vTop,    c, s)
    local brU, brV = RotateCircleUV(1, p.vBottom, c, s)
    p.tex:SetTexCoord(tlU, tlV, blU, blV, trU, trV, brU, brV)
end

local function SpawnCircle(parts, fillLX, filledW, barCY, barH)
    if filledW <= 0 then return end

    for _, p in ipairs(parts) do
        if not p.active then
            local zoneCenter = fillLX + filledW * 0.5
            local zoneHalf   = math.min(filledW * 0.5 * S.CIRCLE_SPREAD,
                                        S.CIRCLE_MAX_WIDTH * 0.5)
            local xMin = zoneCenter - zoneHalf
            local xMax = zoneCenter + zoneHalf
            if xMin >= xMax then xMin = fillLX + filledW * 0.5 ; xMax = xMin end
            local x = rand(xMin, xMax)

            local isAbove = (math.random(2) == 1)
            local clipY   = isAbove and (barCY + barH * S.CIRCLE_CLIP_OFFSET)
                                     or (barCY - barH * S.CIRCLE_CLIP_OFFSET)

            local scale    = rand(S.CIRCLE_SCALE_MIN, S.CIRCLE_SCALE_MAX)
            local diameter = barH * S.CIRCLE_SIZE_FACTOR * scale
            local angle    = rand(0, S.pi2)
            local rotSpeed = rand(S.CIRCLE_ROT_SPEED_MIN, S.CIRCLE_ROT_SPEED_MAX)

            p.active   = true
            p.life     = 0
            p.maxLife  = rand(S.CIRCLE_LIFE_MIN, S.CIRCLE_LIFE_MAX)
            p.isAbove  = isAbove
            p.x        = x + S.CIRCLE_OFFSET_X
            p.y        = isAbove and (clipY + S.CIRCLE_OFFSET_Y) or (clipY - S.CIRCLE_OFFSET_Y)
            p.clipY    = clipY
            p.diameter = diameter
            p.radius   = diameter * 0.5
            p.stretchW = diameter * S.CIRCLE_STRETCH_X   -- wider than tall
            p.angle    = angle
            p.rotSpeed = rotSpeed

            p.tex:SetAlpha(0)
            p.visible = LayoutCircleSlice(p)
            if p.visible then RotateCircleSlice(p) end
            return
        end
    end
end

local function UpdateCircle(p, dt, alphaMax)
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then
        p.active = false
        p.tex:SetAlpha(0)
        return
    end
    if not p.visible then return end
    p.angle = p.angle + p.rotSpeed * p.rotDir * dt
    RotateCircleSlice(p)
    -- Fade in over the first 30%, hold, then fade over the final 30%.
    local env
    if     t < 0.30 then env = t / 0.30
    elseif t < 0.70 then env = 1
    else             env = (1 - t) / 0.30 end
    p.tex:SetAlpha(math.max(0, env) * (alphaMax or S.CIRCLE_ALPHA_MAX))
end

-- Effect lifecycle and texture-pool construction.

function FX.Init(container, bar)
    local school = SCB.Schools.data["water"]
    if not school then return end

    -- Build the blue glow pool.
    local partTex = SCB.TEX_PATH .. "frost\\Particle_Frost_01"
    S.glowParts = {}
    for i = 1, S.GLOW_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(partTex)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.WATER_R, S.WATER_G, S.WATER_B)
        tex:SetAlpha(0)
        S.glowParts[i] = { tex=tex, active=false, life=0, maxLife=0,
                         x=0, y=0, vy=0, phase=0 }
    end

    -- Build the blue droplet pool.
    S.emberParts = {}
    for i = 1, S.EMBER_COUNT do
        local typeIdx = ((i - 1) % 3) + 1
        local ptype   = S.emberTypes[typeIdx]
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(partTex)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.WATER_R, S.WATER_G, S.WATER_B)
        tex:SetAlpha(0)
        S.emberParts[i] = {
            tex=tex, ptype=ptype, typeIdx=typeIdx,
            active=false, life=0, maxLife=0,
            x=0, y=0, vx=0, vy=0, drift=0,
        }
    end

    -- Background circles, on the host drawn below the bar background.
    local _underlay = SCB.Bar and SCB.Bar.bgUnderlayHost or bar
    local circleTex = school.circle
    S.circleParts = {}
    for i = 1, S.CIRCLE_COUNT do
        local tex = _underlay:CreateTexture(nil, "BACKGROUND")
        if circleTex then
            tex:SetTexture(circleTex)
        end
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.WATER_R, S.WATER_G, S.WATER_B)
        tex:SetAlpha(0)
        S.circleParts[i] = {
            tex=tex, active=false, visible=false, life=0, maxLife=0,
            x=0, y=0, clipY=0, isAbove=true, vTop=0, vBottom=1,
            diameter=0, radius=0, angle=0, rotSpeed=0,
            rotDir=(i % 2 == 1) and 1 or -1,
        }
    end

    -- Build overlay circles at half the background opacity.
    S.circleFGParts = {}
    for i = 1, S.CIRCLE_COUNT do
        local tex = _underlay:CreateTexture(nil, "OVERLAY")
        if circleTex then
            tex:SetTexture(circleTex)
        end
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(S.WATER_R, S.WATER_G, S.WATER_B)
        tex:SetAlpha(0)
        S.circleFGParts[i] = {
            tex=tex, active=false, visible=false, life=0, maxLife=0,
            x=0, y=0, clipY=0, isAbove=true, vTop=0, vBottom=1,
            diameter=0, radius=0, angle=0, rotSpeed=0,
            rotDir=(i % 2 == 1) and -1 or 1,
        }
    end
end

function FX.Start(duration)
    S.castDuration  = duration or 5
    S.isActive      = true
    S.partsFading   = false
    S.glowSpawnAcc  = 0
    S.emberSpawnAcc = 0
    S.circleAcc     = 0
    S.circleNext    = rand(S.CIRCLE_SPAWN_MIN, S.CIRCLE_SPAWN_MAX)
    S.circleFGAcc   = 0
    S.circleFGNext  = rand(S.CIRCLE_SPAWN_MIN, S.CIRCLE_SPAWN_MAX)
    for _, p in ipairs(S.glowParts)     do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.emberParts)    do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.circleParts)   do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.circleFGParts) do p.active = false ; p.tex:SetAlpha(0) end
end

function FX.Stop()
    S.isActive      = false
    S.partsFading   = true
    S.partsFadeT    = 0
    S.glowSpawnAcc  = 0
    S.emberSpawnAcc = 0
end

function FX.UpdateFade(dt)
    if not S.partsFading then return end
    S.partsFadeT = S.partsFadeT + dt
    -- Particles keep their alpha: the bar's own fade dims them.
    for _, p in ipairs(S.glowParts)     do if p.active then UpdateGlow(p, dt) end end
    for _, p in ipairs(S.emberParts)    do if p.active then UpdateEmber(p, dt) end end
    for _, p in ipairs(S.circleParts)   do if p.active then UpdateCircle(p, dt) end end
    for _, p in ipairs(S.circleFGParts) do if p.active then UpdateCircle(p, dt, S.CIRCLE_FG_ALPHA_MAX) end end
    if S.partsFadeT >= SCB.FX_LINGER then
        S.partsFading = false
        for _, p in ipairs(S.glowParts)     do p.active = false ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.emberParts)    do p.active = false ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.circleParts)   do p.active = false ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.circleFGParts) do p.active = false ; p.tex:SetAlpha(0) end
    end
end

function FX.Reset()
    S.isActive = false ; S.partsFading = false
    for _, p in ipairs(S.glowParts)     do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.emberParts)    do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.circleParts)   do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.circleFGParts) do p.active = false ; p.tex:SetAlpha(0) end
end

function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    if not S.isActive then return end

    -- Glow at the fill front.
    for _, p in ipairs(S.glowParts) do if p.active then UpdateGlow(p, dt) end end
    if SCB.Particles.emitProgress < S.GLOW_STOP_AT then
        S.glowSpawnAcc = S.glowSpawnAcc + dt
        if S.glowSpawnAcc >= S.GLOW_SPAWN_RATE then
            S.glowSpawnAcc = 0
            for _ = 1, math.random(2, 4) do
                SpawnGlow(frontX, cy, barH)
            end
        end
    end

    -- Droplets at the fill front.
    for _, p in ipairs(S.emberParts) do if p.active then UpdateEmber(p, dt) end end
    S.emberSpawnAcc = S.emberSpawnAcc + dt
    if S.emberSpawnAcc >= S.EMBER_SPAWN then
        S.emberSpawnAcc = 0
        for _ = 1, math.random(2, 4) do
            SpawnEmber(frontX, cy)
        end
    end

    -- Circles across the whole fill region, whatever the progress.
    for _, p in ipairs(S.circleParts)   do if p.active then UpdateCircle(p, dt) end end
    for _, p in ipairs(S.circleFGParts) do if p.active then UpdateCircle(p, dt, S.CIRCLE_FG_ALPHA_MAX) end end
    S.circleAcc = S.circleAcc + dt
    if S.circleAcc >= S.circleNext then
        S.circleAcc  = 0
        S.circleNext = rand(S.CIRCLE_SPAWN_MIN, S.CIRCLE_SPAWN_MAX)
        SpawnCircle(S.circleParts, fillLX, fillW, cy, barH)
    end
    S.circleFGAcc = S.circleFGAcc + dt
    if S.circleFGAcc >= S.circleFGNext then
        S.circleFGAcc  = 0
        S.circleFGNext = rand(S.CIRCLE_SPAWN_MIN, S.CIRCLE_SPAWN_MAX)
        SpawnCircle(S.circleFGParts, fillLX, fillW, cy, barH)
    end
end
