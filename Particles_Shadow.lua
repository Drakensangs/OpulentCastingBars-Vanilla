-- ============================================================
--  Opulent Casting Bars -- Particles_Shadow.lua
--  Violet contour flames, rotating end circles, infalling motes and rising ash.
-- ============================================================

local S = {}  -- Shared effect state and tuning.
local FX = {}
SCB.FX        = SCB.FX or {}
SCB.FX["shadow"] = FX

local function rand(a, b) return a + math.random() * (b - a) end

-- Contour flame timing and opacity.

S.SHADOW_CONTOUR_BASE = { 1, 2, 3, 4, 5 }
S.SHADOW_SLOT_CYCLE = 0.65
S.SHADOW_SLOT_FADE = 0.13
S.SHADOW_SLOT_COUNT = 3
S.SHADOW_GHOST_COUNT = 2
S.SHADOW_GHOST_ALPHA = 0.5 * 0.40  -- Ghost slots use half the main opacity.
S.SHADOW_MAX_ALPHA = 0.40  -- Main slot opacity.

S.SHADOW_BONUS_IDX = 1
S.SHADOW_BONUS_HOLD_MIN = 1.5
S.SHADOW_BONUS_HOLD_MAX = 3.5
S.SHADOW_BONUS_FADE = 0.35
S.SHADOW_BONUS_GAP_MIN = 2.0
S.SHADOW_BONUS_GAP_MAX = 5.0

-- End-circle size, rotation and pulse.

S.CIRCLE_SIZE_START = 18
S.CIRCLE_SIZE_MAX = 60
S.CIRCLE_ROT_SPEED = 1.6  -- Clockwise angular speed (rad/s).
S.CIRCLE_PULSE_SPEED = 2.0
S.CIRCLE_PULSE_AMP = 0.07
S.CIRCLE_ALPHA = 0.95
S.CIRCLE_OFFSET_Y = 7
S.CIRCLE_OFFSET_X = -49  -- Negative values move the circles inward.

-- Infalling orbit particles.

S.ORB_PER_CIRCLE = 20  -- Particle capacity per circle.
S.ORB_R_MIN = 22  -- Minimum spawn radius (px).
S.ORB_R_MAX = 48  -- Maximum spawn radius (px).
S.ORB_INFALL_SPEED = 20  -- Radial infall speed (px/s).
S.ORB_ORBIT_SPEED = 2.6  -- Angular speed (rad/s).
S.ORB_SPAWN_RATE = 0.09  -- Spawn interval per circle (s).
S.ORB_ALPHA = 0.90
S.ORB_SIZE_MIN = 4
S.ORB_SIZE_MAX = 9

-- Fill-front particle tuning.

S.PART_COUNT = 50
S.PART_SPAWN_RATE = 0.035
S.PART_STOP_AT = 0.87
S.PART_ALPHA = 1.0
-- Match the dark violet contour tint.
S.PART_R = 0.35 ; S.PART_G = 0.15 ; S.PART_B = 0.45

-- Ash particle tuning.

S.ASH_COUNT = 60
S.ASH_SPAWN_RATE = 0.05
S.ASH_ALPHA = 0.95
S.ASH_SIZE_MIN = 3
S.ASH_SIZE_MAX = 8

-- Pools, timers and circle fade state.

S.shadowSlots = {}
S.shadowBonus = { phase = "wait", timer = 0, duration = 0 }
S.circles = {}
S.orbPools = { {}, {} }  -- Separate orbit pool for each circle.
S.orbSpawnAccs = { 0, 0 }
S.parts = {}
S.ashes = {}
S.spawnAcc = 0
S.ashSpawnAcc = 0
S.circlesFading = false
S.circlesFadeT = 0
S.CIRCLE_FADE_DUR = 0.55
S.circlesLastProg = 0

-- Contour flame animation.

-- Reuse the opacity scratch buffer across updates.
S.shadowAlphas = {}

local function UpdateShadowFlames(dt, progress)
    local bar = SCB.Bar
    if not bar.texContoursFire then return end
    if bar.maskFrameRed and bar.frameInner then
        -- Same frame-art reveal as the other styles (Fire's red frame and
        -- contours): linear with the cast, over the configured bar width.
        local bW = (SCB.Config and SCB.Config:Get("barWidth")) or bar.frameInner:GetWidth() or 400
        local p  = math.max(0, math.min(progress or 0, 1))
        SCB.LayoutArtworkRevealMask(bar.maskFrameRed, bar.frameInner, math.max(1, bW * p), p)
    end

    local alphas = S.shadowAlphas
    for i = 1, #bar.texContoursFire do alphas[i] = 0 end

    for _, slot in ipairs(S.shadowSlots) do
        slot.timer = slot.timer + dt
        if slot.timer >= S.SHADOW_SLOT_CYCLE then
            slot.timer   = slot.timer - S.SHADOW_SLOT_CYCLE
            slot.basePos = (slot.basePos % #S.SHADOW_CONTOUR_BASE) + 1
        end
        local t     = slot.timer / S.SHADOW_SLOT_CYCLE
        local fadeT = S.SHADOW_SLOT_FADE / S.SHADOW_SLOT_CYCLE
        local alpha
        if t < fadeT then
            alpha = t / fadeT
        elseif t < 1 - fadeT then
            alpha = 1
        else
            alpha = (1 - t) / fadeT
        end
        local maxAlpha = slot.isGhost and S.SHADOW_GHOST_ALPHA or S.SHADOW_MAX_ALPHA
        local texIdx   = S.SHADOW_CONTOUR_BASE[slot.basePos]
        alphas[texIdx] = math.max(alphas[texIdx], math.max(0, alpha) * maxAlpha)
    end

-- Occasional extra contour layer.
    S.shadowBonus.timer = S.shadowBonus.timer + dt
    if S.shadowBonus.phase == "wait" then
        if S.shadowBonus.timer >= S.shadowBonus.duration then
            S.shadowBonus.phase    = "fadein"
            S.shadowBonus.timer    = 0
            S.shadowBonus.duration = rand(S.SHADOW_BONUS_HOLD_MIN, S.SHADOW_BONUS_HOLD_MAX)
        end
    elseif S.shadowBonus.phase == "fadein" then
        local a = math.min(S.shadowBonus.timer / S.SHADOW_BONUS_FADE, 1) * S.SHADOW_MAX_ALPHA
        alphas[S.SHADOW_BONUS_IDX] = math.max(alphas[S.SHADOW_BONUS_IDX], a)
        if S.shadowBonus.timer >= S.SHADOW_BONUS_FADE then
            S.shadowBonus.phase = "hold" ; S.shadowBonus.timer = 0
        end
    elseif S.shadowBonus.phase == "hold" then
        alphas[S.SHADOW_BONUS_IDX] = math.max(alphas[S.SHADOW_BONUS_IDX], S.SHADOW_MAX_ALPHA)
        if S.shadowBonus.timer >= S.shadowBonus.duration then
            S.shadowBonus.phase = "fadeout" ; S.shadowBonus.timer = 0
        end
    elseif S.shadowBonus.phase == "fadeout" then
        local a = math.max(0, 1 - S.shadowBonus.timer / S.SHADOW_BONUS_FADE) * S.SHADOW_MAX_ALPHA
        alphas[S.SHADOW_BONUS_IDX] = math.max(alphas[S.SHADOW_BONUS_IDX], a)
        if S.shadowBonus.timer >= S.SHADOW_BONUS_FADE then
            S.shadowBonus.phase    = "wait"
            S.shadowBonus.timer    = 0
            S.shadowBonus.duration = rand(S.SHADOW_BONUS_GAP_MIN, S.SHADOW_BONUS_GAP_MAX)
        end
    end

-- Contours are tinted dark violet once per cast (ResetShadowFlames).
    for i, t in ipairs(bar.texContoursFire) do
        local a = alphas[i] or 0
        if a > 0 then t:SetAlpha(a) ; t:Show() else t:SetAlpha(0) ; t:Hide() end
    end
end

local function ResetShadowFlames()
    local bar = SCB.Bar
    if bar.maskFrameRed then bar.maskFrameRed:SetWidth(1) end
    if bar.texContoursFire then
        for _, t in ipairs(bar.texContoursFire) do
            t:SetAlpha(0)
            t:Hide()
            -- Dark violet tint for the whole cast; FX.Reset restores white.
            t:SetVertexColor(0.35, 0.15, 0.45)
        end
    end
    local gi = 0
    for s, slot in ipairs(S.shadowSlots) do
        if slot.isGhost then
            gi = gi + 1
            slot.timer   = (gi - 0.5) * (S.SHADOW_SLOT_CYCLE / S.SHADOW_SLOT_COUNT)
            slot.basePos = (gi + 1) % #S.SHADOW_CONTOUR_BASE + 1
        else
            slot.timer   = (s - 1) * (S.SHADOW_SLOT_CYCLE / S.SHADOW_SLOT_COUNT)
            slot.basePos = s
        end
    end
    S.shadowBonus.phase    = "wait"
    S.shadowBonus.timer    = 0
    S.shadowBonus.duration = rand(S.SHADOW_BONUS_GAP_MIN, S.SHADOW_BONUS_GAP_MAX)
end

-- Fill-front particles and rising ash.

local function SpawnParticle(frontX, cy)
    for _, p in ipairs(S.parts) do
        if not p.active then
            local angle = math.rad(rand(50, 130))
            local speed = rand(40, 110)
            p.active  = true
            p.life    = 0
            p.maxLife = rand(0.4, 0.9)
            p.x       = frontX + rand(-3, 3)
            p.y       = cy + rand(-8, 8)
            p.vx      = math.cos(angle) * speed
            p.vy      = math.sin(angle) * speed
            local size = rand(6, 14)
            p.tex:SetSize(size, size)
            p.tex:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
            p.tex:SetVertexColor(S.PART_R, S.PART_G, S.PART_B)
            p.tex:SetAlpha(S.PART_ALPHA)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            return
        end
    end
end

local function UpdateParticle(p, dt)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end

    p.vy = p.vy - 120 * dt
    p.x  = p.x  + p.vx * dt
    p.y  = p.y  + p.vy * dt
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)

    local alpha = t < 0.6 and 1 or math.max(0, (1 - t) / 0.4)
    p.tex:SetAlpha(alpha * S.PART_ALPHA)
end

local function SpawnAsh(barLX, barRX, barCY, barH)
    for _, a in ipairs(S.ashes) do
        if not a.active then
-- Spawn across the bar near its upper or lower edge.
            local x    = rand(barLX, barRX)
            local edge = (math.random(2) == 1) and 1 or -1  -- Choose the upper or lower edge.
            local y    = barCY + edge * (barH * 0.5) * rand(0.3, 0.9)

-- Upward launch with random lateral drift.
            local vx = rand(-18, 18)
            local vy = rand(12, 35)

            a.active  = true
            a.life    = 0
            a.maxLife = rand(0.8, 2.2)
            a.x, a.y  = x, y
            a.vx, a.vy = vx, vy
            a.drift   = rand(-8, 8)  -- Horizontal wave amplitude.
            a.phase   = rand(0, math.pi * 2)

            local size = rand(S.ASH_SIZE_MIN, S.ASH_SIZE_MAX)
            a.tex:SetSize(size, size)
            a.tex:SetVertexColor(S.PART_R, S.PART_G, S.PART_B)
            a.tex:SetAlpha(S.ASH_ALPHA)
            a.tex:ClearAllPoints()
            a.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
            return
        end
    end
end

local function UpdateAsh(a, dt)
    if not a.active then return end
    a.life = a.life + dt
    local t = a.life / a.maxLife
    if t >= 1 then a.active = false ; a.tex:SetAlpha(0) ; return end

-- Apply weak downward acceleration while the ash drifts.
    a.vy = a.vy - 4 * dt  -- Downward acceleration (px/s squared).
    a.x  = a.x + a.vx * dt + math.sin(a.life * 2.5 + a.phase) * a.drift * dt
    a.y  = a.y + a.vy * dt
    a.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", a.x, a.y)

-- Fade in over the first 15% and out over the final 35%.
    local alpha
    if t < 0.15 then
        alpha = t / 0.15
    elseif t < 0.65 then
        alpha = 1
    else
        alpha = math.max(0, (1 - t) / 0.35)
    end
    a.tex:SetAlpha(alpha * S.ASH_ALPHA)
end

-- Orbit particle spawning and motion.

local function SpawnOrb(pool, cx, cy)
    for _, o in ipairs(pool) do
        if not o.active then
            local angle = math.random() * math.pi * 2
            local r     = rand(S.ORB_R_MIN, S.ORB_R_MAX)
            o.active  = true
            o.r       = r
            o.angle   = angle
            o.life    = 0
            o.maxLife = r / S.ORB_INFALL_SPEED
            local size = rand(S.ORB_SIZE_MIN, S.ORB_SIZE_MAX)
            o.tex:SetSize(size, size)
            o.tex:SetVertexColor(S.PART_R, S.PART_G, S.PART_B)
            o.tex:SetAlpha(S.ORB_ALPHA)
            o.tex:ClearAllPoints()
            o.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
                cx + math.cos(angle) * r, cy + math.sin(angle) * r)
            return
        end
    end
end

local function UpdateOrb(o, dt, cx, cy)
    if not o.active then return end
    o.life  = o.life + dt

-- Increase angular speed as the orbit contracts.
    local omega = S.ORB_ORBIT_SPEED * (S.ORB_R_MIN / math.max(o.r, 4))
    o.angle = o.angle + omega * dt
    o.r     = o.r - S.ORB_INFALL_SPEED * dt

    if o.r <= 2 then
        o.active = false
        o.tex:SetAlpha(0)
        return
    end

    local x = cx + math.cos(o.angle) * o.r
    local y = cy + math.sin(o.angle) * o.r
    o.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)

-- Fade over the final 30% of particle life.
    local t = o.life / o.maxLife
    local alpha = t > 0.7 and math.max(0, (1 - t) / 0.3) or 1
    o.tex:SetAlpha(alpha * S.ORB_ALPHA)
end

-- End-circle animation and fade.

local function UpdateCircles(dt, progress, barLX, barRX, barCY)
    local leftX, rightX = barLX - S.CIRCLE_OFFSET_X, barRX + S.CIRCLE_OFFSET_X

    local currentProg, currentAlpha

    if S.circlesFading then
        S.circlesFadeT = S.circlesFadeT + dt
        local t = math.min(S.circlesFadeT / S.CIRCLE_FADE_DUR, 1)
-- Keep the opacity reached during the cast (the bar fade hides the
-- circles together with everything else) ...
        currentAlpha = math.max(0, S.CIRCLE_ALPHA * math.min(S.circlesLastProg * 6, 1))
-- ... and shrink from the last cast progress toward the starting size.
        currentProg  = S.circlesLastProg * (1 - t)
    else
        S.circlesLastProg = progress
        currentProg  = progress
        currentAlpha = math.max(0, S.CIRCLE_ALPHA * math.min(progress * 6, 1))
    end

    for i, c in ipairs(S.circles) do
        c.angle  = c.angle  - S.CIRCLE_ROT_SPEED * dt
        c.pulseT = c.pulseT + dt

        local size  = S.CIRCLE_SIZE_START + (S.CIRCLE_SIZE_MAX - S.CIRCLE_SIZE_START) * currentProg
        local pulse = 1 + math.sin(c.pulseT * S.CIRCLE_PULSE_SPEED) * S.CIRCLE_PULSE_AMP
        c.tex:SetSize(size * pulse, size * pulse)
        c.tex:SetRotation(c.angle)
        c.tex:SetAlpha(currentAlpha)
        c.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
            (i == 1 and leftX or rightX), barCY + S.CIRCLE_OFFSET_Y)
    end
end

local function ResetCircles()
    for _, c in ipairs(S.circles) do
        c.tex:SetAlpha(0)
        c.angle  = math.random() * math.pi * 2
        c.pulseT = math.random() * math.pi
    end
end

-- Effect lifecycle and particle-pool construction.

function FX.Init(container, bar)
    local school = SCB.Schools.data["shadow"]
    if not school then return end

-- ApplySchool supplies the contour textures; initialize only their animation slots.

    S.shadowSlots = {}
    local gi = 0
    for s = 1, S.SHADOW_SLOT_COUNT + S.SHADOW_GHOST_COUNT do
        local isGhost = (s > S.SHADOW_SLOT_COUNT)
        if isGhost then gi = gi + 1 end
        S.shadowSlots[s] = {
            isGhost  = isGhost,
            timer    = isGhost
                and (gi - 0.5) * (S.SHADOW_SLOT_CYCLE / S.SHADOW_SLOT_COUNT)
                or  (s  - 1)  * (S.SHADOW_SLOT_CYCLE / S.SHADOW_SLOT_COUNT),
            basePos  = isGhost and ((gi + 1) % #S.SHADOW_CONTOUR_BASE + 1) or s,
        }
    end

    S.shadowBonus = {
        phase    = "wait",
        timer    = 0,
        duration = rand(S.SHADOW_BONUS_GAP_MIN, S.SHADOW_BONUS_GAP_MAX),
    }

-- Use Earth debris textures for the particle pools.
    local earthSchool = SCB.Schools.data["earth"]
    local miscTexs = {}
    if earthSchool then
        for _, t in ipairs(earthSchool.rocks   or {}) do miscTexs[#miscTexs+1] = t end
        for _, t in ipairs(earthSchool.debris  or {}) do miscTexs[#miscTexs+1] = t end
    end
    local function getMisc(i)
        if #miscTexs == 0 then return school.contours[1] end
        return miscTexs[((i-1) % #miscTexs) + 1]
    end

-- Build the orbit particle pools.
    S.orbPools = { {}, {} }
    for ci = 1, 2 do
        for i = 1, S.ORB_PER_CIRCLE do
            local tex = container:CreateTexture(nil, "OVERLAY")
            tex:SetTexture(getMisc(i))
            tex:SetBlendMode("ADD")
            tex:SetAlpha(0)
            S.orbPools[ci][i] = {
                tex = tex, active = false,
                r = 0, angle = 0, life = 0, maxLife = 0,
            }
        end
    end

-- Build the fill-front particle pool.
    S.parts = {}
    for i = 1, S.PART_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(getMisc(i))
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)
        S.parts[i] = {
            tex = tex, active = false,
            life = 0, maxLife = 0,
            x = 0, y = 0, vx = 0, vy = 0,
        }
    end

-- Build the contour ash pool.
    S.ashes = {}
    for i = 1, S.ASH_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(getMisc(i))
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)
        S.ashes[i] = {
            tex = tex, active = false,
            life = 0, maxLife = 0,
            x = 0, y = 0, vx = 0, vy = 0,
            drift = 0, phase = 0,
        }
    end
    for i = 1, 2 do
        local deco = SCB.Bar and SCB.Bar.decoHost or bar
        local tex = deco:CreateTexture(nil, "OVERLAY", nil, 3)
        tex:SetTexture(school.circle)
        tex:SetBlendMode("BLEND")
        tex:SetSize(S.CIRCLE_SIZE_START, S.CIRCLE_SIZE_START)
        tex:SetAlpha(0)
        S.circles[i] = {
            tex    = tex,
            angle  = math.random() * math.pi * 2,
            pulseT = math.random() * math.pi,
        }
    end
end

function FX.Start(duration)
    S.spawnAcc        = 0
    S.ashSpawnAcc     = 0
    S.orbSpawnAccs    = { 0, 0 }
    S.circlesFading   = false
    S.circlesFadeT    = 0
    S.circlesLastProg = 0
    ResetShadowFlames()
    ResetCircles()
    for _, p in ipairs(S.parts)  do p.active = false ; p.tex:SetAlpha(0) end
    for _, a in ipairs(S.ashes)  do a.active = false ; a.tex:SetAlpha(0) end
    for ci = 1, 2 do
        for _, o in ipairs(S.orbPools[ci]) do o.active = false ; o.tex:SetAlpha(0) end
    end
end

function FX.Stop()
-- Continue the circle shrink through UpdateCircles. Particles, ashes and
-- orbs keep moving (without new spawns) and fade out with the bar.
    S.circlesFading = true
    S.circlesFadeT  = 0
end

function FX.Reset()
    S.circlesFading = false
    -- Restore the contour tint.
    if SCB.Bar.maskFrameRed then SCB.Bar.maskFrameRed:SetWidth(1) end
    if SCB.Bar.texContoursFire then
        for _, t in ipairs(SCB.Bar.texContoursFire) do
            t:SetAlpha(0)
            t:Hide()
            t:SetVertexColor(1, 1, 1)
            t:SetTexCoord(0, 1, 0, 1)
        end
    end
    for _, c in ipairs(S.circles) do c.tex:SetAlpha(0) end
    for _, p in ipairs(S.parts)  do p.active = false ; p.tex:SetAlpha(0) end
    for ci = 1, 2 do
        for _, o in ipairs(S.orbPools[ci]) do o.active = false ; o.tex:SetAlpha(0) end
    end
    for _, a in ipairs(S.ashes)  do a.active = false ; a.tex:SetAlpha(0) end
end

function FX.UpdateCirclesFade(dt)
    if not S.circlesFading then return end
    local f = SCB.Bar.frameInner
    local cx, barCY = f:GetCenter()
    if not cx then return end
    local barW = SCB.Bar.frame:GetWidth()
    local barLX = cx - barW * 0.5
    local barRX = cx + barW * 0.5
    UpdateCircles(dt, 0, barLX, barRX, barCY)
    for _, p in ipairs(S.parts) do UpdateParticle(p, dt) end
    for _, a in ipairs(S.ashes) do UpdateAsh(a, dt) end
    local leftX, rightX = barLX - S.CIRCLE_OFFSET_X, barRX + S.CIRCLE_OFFSET_X
    for ci = 1, 2 do
        local pcx = ci == 1 and leftX or rightX
        for _, o in ipairs(S.orbPools[ci]) do UpdateOrb(o, dt, pcx, barCY + S.CIRCLE_OFFSET_Y) end
    end
end

function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    if SCB.Bar.currentSchoolKey ~= "shadow" then return end

    local f = SCB.Bar.frameInner
    local cx, barCY = f:GetCenter()
    if not cx then return end

    local barLX = cx - barW * 0.5
    local barRX = cx + barW * 0.5

    UpdateShadowFlames(dt, progress)
    UpdateCircles(dt, progress, barLX, barRX, barCY)

-- Spawn fill-front particles.
    for _, p in ipairs(S.parts) do UpdateParticle(p, dt) end
    if progress < S.PART_STOP_AT then
        S.spawnAcc = S.spawnAcc + dt
        if S.spawnAcc >= S.PART_SPAWN_RATE then
            S.spawnAcc = 0
            SpawnParticle(frontX, barCY)
        end
    end

-- Spawn ash over the filled region.
    for _, a in ipairs(S.ashes) do UpdateAsh(a, dt) end
    S.ashSpawnAcc = S.ashSpawnAcc + dt
    if S.ashSpawnAcc >= S.ASH_SPAWN_RATE then
        S.ashSpawnAcc = 0
        SpawnAsh(barLX, barRX, barCY, barH)
    end

-- Update and replenish the two orbit pools.
    local leftX, rightX = barLX - S.CIRCLE_OFFSET_X, barRX + S.CIRCLE_OFFSET_X
    for ci = 1, 2 do
        local pcx = ci == 1 and leftX or rightX
        local pcy = barCY + S.CIRCLE_OFFSET_Y
        for _, o in ipairs(S.orbPools[ci]) do UpdateOrb(o, dt, pcx, pcy) end
        S.orbSpawnAccs[ci] = S.orbSpawnAccs[ci] + dt
        if S.orbSpawnAccs[ci] >= S.ORB_SPAWN_RATE then
            S.orbSpawnAccs[ci] = 0
            SpawnOrb(S.orbPools[ci], pcx, pcy)
        end
    end
end
