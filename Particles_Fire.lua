-- ============================================================
--  Opulent Casting Bars -- Particles_Fire.lua
--  Revealed flame layers and contours with front and ambient embers.
-- ============================================================

local FX = {}
SCB.FX = SCB.FX or {}
SCB.FX["fire"] = FX

-- Local math helpers.
local function rand(a, b) return a + math.random() * (b - a) end
local function rad(deg)   return deg * math.pi / 180 end
local function lerp(a, b, t) return a + (b - a) * math.max(0, math.min(t, 1)) end

-- Front particle pool and emission tuning.
local FIRE_PART_COUNT = 60
local FIRE_PART_SPAWN = 0.03

local firePartTypes = {
    { sizeMin=8,  sizeMax=14, speedMin=25, speedMax=60,  lifeMin=0.8, lifeMax=1.6, gravity=8,  spread=140, driftX=0.4  },
    { sizeMin=4,  sizeMax=8,  speedMin=80, speedMax=160, lifeMin=0.3, lifeMax=0.7, gravity=15, spread=80,  driftX=0.0  },
    { sizeMin=6,  sizeMax=12, speedMin=40, speedMax=90,  lifeMin=0.6, lifeMax=1.2, gravity=20, spread=100, driftX=0.2  },
}

local FIRE_AMB_COUNT = 40
local FIRE_AMB_SPAWN = 0.08

-- Flame and contour animation timing.
local FIRE_EFFECT_BASE  = { 1, 2, 3, 4, 5, 6 }
local FIRE_EFFECT_CYCLE = 0.6
local FIRE_EFFECT_FADE  = 0.12
local FIRE_EFFECT_COUNT = 3

local FIRE_CONTOUR_BASE  = { 1, 3, 4, 5 }
local FIRE_CONTOUR_BONUS = 2

local FIRE_SLOT_CYCLE = 0.6
local FIRE_SLOT_FADE  = 0.12
local FIRE_SLOT_COUNT = 3
local FIRE_GHOST_COUNT = 2
local FIRE_GHOST_ALPHA = 0.5

local FIRE_BONUS_HOLD_MIN = 1.5
local FIRE_BONUS_HOLD_MAX = 3.5
local FIRE_BONUS_FADE     = 0.35
local FIRE_BONUS_GAP_MIN  = 2.0
local FIRE_BONUS_GAP_MAX  = 5.0

-- Particle pools and animation state.
local fireParts      = {}
local fireSpawnAcc   = 0
local fireAmbParts   = {}
local fireAmbSpawnAcc = 0
local castDuration   = 5

local fireEffectSlots = {}
local fireSlots       = {}
local fireBonus       = { phase="wait", timer=0, duration=0 }

local fireEffectAlphas  = {}
local fireContourAlphas = {}

local contourClips = {}
local contourInnerTexes = {}
local contourMask = nil
local contourBarW = nil

-- Reveal contours using the cast width, including during completion.
local function UpdateContourReveal(progress, barW)
    local f = SCB.Bar and SCB.Bar.frameInner
    if not f then return end
    if barW and barW > 0 then contourBarW = barW end
    local bW = barW or contourBarW or f:GetWidth() or 400
    local revealW = math.max(1, bW * progress)
    SCB.LayoutArtworkRevealMask(contourMask, f, revealW, progress)
    for i, host in ipairs(contourClips) do
        host:SetWidth(revealW)
        local tex = contourInnerTexes[i]
        tex:SetWidth(revealW)
        tex:SetTexCoord(0, revealW / math.max(bW, 1), 0, 1)
    end
end

local fillEffectClips     = {}
local fillEffectInnerTexes = {}

local bgRedClip   = nil
local bgRedTex    = nil
local frameRedClip = nil
local frameRedTex  = nil
local frameRedMask = nil   -- soft reveal edge on Frame_Fire_Red

-- Spawn fire particle.
local function SpawnFireParticle(wx, wy)
    local roll = math.random(10)
    local typeIdx = roll <= 4 and 1 or (roll <= 7 and 3 or 2)
    local ptype = firePartTypes[typeIdx]

    for _, p in ipairs(fireParts) do
        if not p.active and p.typeIdx == typeIdx then
            local tCast = math.max(0, math.min((castDuration - 2) / 3, 1))
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

-- Advance fire particle.
local function UpdateFireParticle(p, dt)
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
    p.tex:SetAlpha(alpha * 0.85)
end

-- Spawn fire ambient.
local function SpawnFireAmbient(progress)
    local f = SCB.Bar.frame
    local cx, cy = f:GetCenter()
    if not cx then return end
    local barW, barH = f:GetWidth(), f:GetHeight()

    for _, p in ipairs(fireAmbParts) do
        if not p.active then
            local xOffset = rand(-barW * 0.5, barW * progress - barW * 0.5)
            local yOffset = rand(-barH * 0.35, barH * 0.35)
            local wx, wy  = cx + xOffset, cy + yOffset
            local dirX    = xOffset > 0 and 1 or -1
            local angle   = rad(rand(60, 120)) * (yOffset > 0 and 1 or -1)
            local speed   = rand(15, 45)

            p.active  = true ; p.life = 0
            p.maxLife = rand(1.0, 2.2)
            p.x       = wx ; p.y = wy
            p.vx      = dirX * rand(5, 20)
            p.vy      = math.sin(angle) * speed

            local size = rand(6, 14)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(0)
            return
        end
    end
end

-- Advance fire ambient.
local function UpdateFireAmbient(p, dt)
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
    p.tex:SetAlpha(math.max(0, alpha) * 0.55)
end

-- Advance fire layers.
local function UpdateFireLayers(dt, progress, barW, barH)
    local bar = SCB.Bar
    if not bar.currentSchool or not bar.currentSchool.fillEffects then return end

    local effectAlphas = fireEffectAlphas
    for i = 1, #fillEffectInnerTexes do effectAlphas[i] = 0 end
    for _, slot in ipairs(fireEffectSlots) do
        slot.timer = slot.timer + dt
        if slot.timer >= FIRE_EFFECT_CYCLE then
            slot.timer   = slot.timer - FIRE_EFFECT_CYCLE
            slot.basePos = (slot.basePos % #FIRE_EFFECT_BASE) + 1
        end
        local t     = slot.timer / FIRE_EFFECT_CYCLE
        local fadeT = FIRE_EFFECT_FADE / FIRE_EFFECT_CYCLE
        local alpha
        if t < fadeT then alpha = t / fadeT
        elseif t < 1 - fadeT then alpha = 1
        else alpha = (1 - t) / fadeT end
        local texIdx = FIRE_EFFECT_BASE[slot.basePos]
        if texIdx and texIdx <= #fillEffectInnerTexes then
            effectAlphas[texIdx] = math.max(effectAlphas[texIdx], math.max(0, alpha) * 0.45)
        end
    end

    local alphas = fireContourAlphas
    for i = 1, #bar.texContoursFire do alphas[i] = 0 end
    for _, slot in ipairs(fireSlots) do
        slot.timer = slot.timer + dt
        if slot.timer >= FIRE_SLOT_CYCLE then
            slot.timer   = slot.timer - FIRE_SLOT_CYCLE
            slot.basePos = (slot.basePos % #FIRE_CONTOUR_BASE) + 1
        end
        local t     = slot.timer / FIRE_SLOT_CYCLE
        local fadeT = FIRE_SLOT_FADE / FIRE_SLOT_CYCLE
        local alpha
        if t < fadeT then alpha = t / fadeT
        elseif t < 1 - fadeT then alpha = 1
        else alpha = (1 - t) / fadeT end
        local maxAlpha = slot.isGhost and FIRE_GHOST_ALPHA or 1.0
        local texIdx = FIRE_CONTOUR_BASE[slot.basePos]
        alphas[texIdx] = math.max(alphas[texIdx], math.max(0, alpha) * maxAlpha)
    end

    fireBonus.timer = fireBonus.timer + dt
    if fireBonus.phase == "wait" then
        if fireBonus.timer >= fireBonus.duration then
            fireBonus.phase = "fadein" ; fireBonus.timer = 0
            fireBonus.duration = rand(FIRE_BONUS_HOLD_MIN, FIRE_BONUS_HOLD_MAX)
        end
    elseif fireBonus.phase == "fadein" then
        local a = math.min(fireBonus.timer / FIRE_BONUS_FADE, 1)
        alphas[FIRE_CONTOUR_BONUS] = math.max(alphas[FIRE_CONTOUR_BONUS], a)
        if fireBonus.timer >= FIRE_BONUS_FADE then
            fireBonus.phase = "hold" ; fireBonus.timer = 0
        end
    elseif fireBonus.phase == "hold" then
        alphas[FIRE_CONTOUR_BONUS] = math.max(alphas[FIRE_CONTOUR_BONUS], 1)
        if fireBonus.timer >= fireBonus.duration then
            fireBonus.phase = "fadeout" ; fireBonus.timer = 0
        end
    elseif fireBonus.phase == "fadeout" then
        local a = math.max(0, 1 - fireBonus.timer / FIRE_BONUS_FADE)
        alphas[FIRE_CONTOUR_BONUS] = math.max(alphas[FIRE_CONTOUR_BONUS], a)
        if fireBonus.timer >= FIRE_BONUS_FADE then
            fireBonus.phase = "wait" ; fireBonus.timer = 0
            fireBonus.duration = rand(FIRE_BONUS_GAP_MIN, FIRE_BONUS_GAP_MAX)
        end
    end

    local f2 = bar.frameInner
    if f2 then
        local bW = barW or f2:GetWidth() or (SCB.Config and SCB.Config:Get("barWidth")) or 400
        local bH = barH or f2:GetHeight() or (SCB.Config and SCB.Config:Get("barHeight")) or 52
        local school = bar.currentSchool
        local mL = ((school and school.fillMarginL or 0) * bW) + (school and school.fillMarginLPx or 0)
        local mR = ((school and school.fillMarginR or 0) * bW) + (school and school.fillMarginRPx or 0)
        local fW = bW - mL - mR
        if bgRedClip    then bgRedClip:Layout(f2, mL, fW, 0, bH, progress) ; bgRedTex:SetAlpha(1) end
        local frameRevealW = math.max(1, bW * progress)
        if frameRedClip and frameRedTex then
            frameRedClip:SetWidth(frameRevealW)
            frameRedTex:SetWidth(frameRevealW)
            frameRedTex:SetTexCoord(0, frameRevealW / math.max(bW, 1), 0, 1)
            SCB.LayoutArtworkRevealMask(frameRedMask, f2, frameRevealW, progress)
            frameRedTex:SetAlpha(1)
            frameRedClip:Show()
        end
        local fillProgress = (fW > 0) and math.min((mL + fW * progress) / bW, 1) or 0
        for i, clip in ipairs(fillEffectClips) do
            clip:Layout(f2, 0, bW, 0, bH, fillProgress)
            fillEffectInnerTexes[i]:SetAlpha(effectAlphas[i] or 0)
        end
        UpdateContourReveal(progress, bW)
        for i, host in ipairs(contourClips) do
            local tex = contourInnerTexes[i]
            tex:SetAlpha(alphas[i] or 0)
            host:Show()
        end
    end
end

-- Reset fire layers.
local function ResetFireLayers()
    local bar = SCB.Bar
    if bar.texBGRed    then bar.texBGRed:SetAlpha(0)    ; bar.texBGRed:Hide()    end
    if bar.texFrameRed then bar.texFrameRed:SetAlpha(0) ; bar.texFrameRed:Hide() end
    if bar.maskBGRed    then bar.maskBGRed:SetWidth(1)    end
    if bar.maskFrameRed then bar.maskFrameRed:SetWidth(1) end
    if bar.texFillEffects then
        for _, t in ipairs(bar.texFillEffects) do
            t:SetAlpha(0)
            t:SetVertexColor(1, 1, 1)
            t:SetTexCoord(0, 1, 0, 1)
            t:SetBlendMode("BLEND")
            t:Hide()
        end
    end
    if bar.texContoursFire then
        for _, t in ipairs(bar.texContoursFire) do
            t:SetAlpha(0)
            t:SetVertexColor(1, 1, 1)
            t:SetTexCoord(0, 1, 0, 1)
            t:SetBlendMode("BLEND")
            t:Hide()
        end
    end
    for s = 1, FIRE_EFFECT_COUNT do
        fireEffectSlots[s].timer   = (s - 1) * (FIRE_EFFECT_CYCLE / FIRE_EFFECT_COUNT)
        fireEffectSlots[s].basePos = s
    end
    for s, slot in ipairs(fireSlots) do
        if slot.isGhost then
            local gi = s - FIRE_SLOT_COUNT
            slot.timer   = (gi - 0.5) * (FIRE_SLOT_CYCLE / FIRE_SLOT_COUNT)
            slot.basePos = (gi + 1) % #FIRE_CONTOUR_BASE + 1
        else
            slot.timer   = (s - 1) * (FIRE_SLOT_CYCLE / FIRE_SLOT_COUNT)
            slot.basePos = s
        end
    end
    fireBonus.phase = "wait" ; fireBonus.timer = 0
    fireBonus.duration = rand(FIRE_BONUS_GAP_MIN, FIRE_BONUS_GAP_MAX)
end

-- Create texture hosts, animation slots, and particle pools.
function FX.Init(container, bar)
    local school  = SCB.Schools.data["fire"]

    local earthSchool = SCB.Schools.data["earth"]
    local miscTexs = {}
    if earthSchool then
        for _, t in ipairs(earthSchool.rocks  or {}) do miscTexs[#miscTexs+1] = t end
        for _, t in ipairs(earthSchool.debris or {}) do miscTexs[#miscTexs+1] = t end
    end
    local function getMisc(i)
        if #miscTexs == 0 then return (school and school.particles and school.particles[1]) end
        return miscTexs[((i-1) % #miscTexs) + 1]
    end

    for i = 1, FIRE_PART_COUNT do
        local typeIdx = ((i - 1) % 3) + 1
        local ptype   = firePartTypes[typeIdx]
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(getMisc(i))
        tex:SetAlpha(0) ; tex:SetBlendMode("ADD")
        fireParts[i] = {
            tex=tex, ptype=ptype, typeIdx=typeIdx,
            active=false, life=0, maxLife=0,
            x=0, y=0, vx=0, vy=0, drift=0,
        }
    end

    for i = 1, FIRE_AMB_COUNT do
        local tex = container:CreateTexture(nil, "BACKGROUND")
        tex:SetTexture(getMisc(i))
        tex:SetAlpha(0) ; tex:SetBlendMode("ADD")
        tex:SetVertexColor(1, 0.45, 0.05)
        fireAmbParts[i] = {
            tex=tex, active=false,
            life=0, maxLife=0, x=0, y=0, vx=0, vy=0,
        }
    end

    for s = 1, FIRE_EFFECT_COUNT do
        fireEffectSlots[s] = {
            timer   = (s - 1) * (FIRE_EFFECT_CYCLE / FIRE_EFFECT_COUNT),
            basePos = s,
        }
    end

    for s = 1, FIRE_SLOT_COUNT do
        fireSlots[s] = {
            timer   = (s - 1) * (FIRE_SLOT_CYCLE / FIRE_SLOT_COUNT),
            basePos = s, isGhost = false,
        }
    end
    for s = 1, FIRE_GHOST_COUNT do
        fireSlots[FIRE_SLOT_COUNT + s] = {
            timer   = (s - 0.5) * (FIRE_SLOT_CYCLE / FIRE_SLOT_COUNT),
            basePos = (s + 1) % #FIRE_CONTOUR_BASE + 1,
            isGhost = true,
        }
    end

    fireBonus.duration = rand(FIRE_BONUS_GAP_MIN, FIRE_BONUS_GAP_MAX)

    local f4 = SCB.Bar and SCB.Bar.frameInner
    local school4 = SCB.Schools.data["fire"]
    if f4 and school4 and school4.fillEffects then
        if SCB.Bar.texFillEffects then
            for _, t in ipairs(SCB.Bar.texFillEffects) do t:SetAlpha(0) ; t:Hide() end
        end
        for i, texPath in ipairs(school4.fillEffects) do
            local clip  = SCB.Clip:New(f4)
            clip:SetFrameLevel(2)
            local child = clip:GetChild()
            local tex   = child:CreateTexture(nil, "OVERLAY", nil, 1)
            tex:SetAllPoints(child)
            tex:SetTexture(texPath)
            tex:SetBlendMode("BLEND")
            tex:SetAlpha(0)
            fillEffectClips[i]      = clip
            fillEffectInnerTexes[i] = tex
        end
    end

    local school3 = SCB.Schools.data["fire"]
    local f3 = SCB.Bar and SCB.Bar.frameInner
    if f3 then
        if SCB.Bar.texBGRed then SCB.Bar.texBGRed:SetAlpha(0) ; SCB.Bar.texBGRed:Hide() end
        if school3 and school3.bgRed then
            local bgHost = SCB.Bar.bgUnderlayHost or f3
            bgRedClip = SCB.Clip:New(bgHost)
            local child = bgRedClip:GetChild()
            bgRedTex = child:CreateTexture(nil, "BACKGROUND", nil, 0)
            bgRedTex:SetAllPoints(child)
            bgRedTex:SetTexture(school3.bgRed)
            bgRedTex:SetBlendMode("BLEND")
            bgRedTex:SetAlpha(0)
        end
        if SCB.Bar.texFrameRed then SCB.Bar.texFrameRed:SetAlpha(0) ; SCB.Bar.texFrameRed:Hide() end
        if school3 and school3.frameRed then
            local host = CreateFrame("Frame", nil, f3)
            host:SetPoint("TOPLEFT",    f3, "TOPLEFT",    0, 0)
            host:SetPoint("BOTTOMLEFT", f3, "BOTTOMLEFT", 0, 0)
            host:SetWidth(1)
            host:SetFrameLevel(4)
            host:Hide()
            frameRedTex = host:CreateTexture(nil, "OVERLAY", nil, 3)
            frameRedTex:SetPoint("TOPLEFT",    host, "TOPLEFT")
            frameRedTex:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT")
            frameRedTex:SetWidth(1)
            frameRedTex:SetTexture(school3.frameRed)
            frameRedTex:SetBlendMode("BLEND")
            frameRedTex:SetAlpha(0)
            frameRedMask = SCB.NewRevealMask(f3)
            SCB.AttachMask(frameRedTex, frameRedMask)
            frameRedClip = host
        end
    end

    local f = SCB.Bar and SCB.Bar.frameInner
    if f and SCB.Bar.texContoursFire then
        local school2 = SCB.Schools.data["fire"]
        contourMask = SCB.NewRevealMask(f)
        for i, orig in ipairs(SCB.Bar.texContoursFire) do
            orig:SetAlpha(0) ; orig:Hide()
            local host = CreateFrame("Frame", nil, f)
            host:SetPoint("TOPLEFT",    f, "TOPLEFT",    0, 0)
            host:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
            host:SetWidth(1)
            host:SetFrameLevel(2)
            host:Hide()
            local tex = host:CreateTexture(nil, "OVERLAY", nil, 2)
            SCB.AttachMask(tex, contourMask)
            tex:SetPoint("TOPLEFT",    host, "TOPLEFT")
            tex:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT")
            tex:SetWidth(1)
            tex:SetBlendMode("BLEND")
            tex:SetAlpha(0)
            if school2 and school2.contours then
                tex:SetTexture(school2.contours[i] or school2.contours[1])
            end
            contourClips[i]      = host
            contourInnerTexes[i] = tex
        end
    end
end

-- Start a cast and reset effect timing.
function FX.Start(duration)
    castDuration  = duration or 5
    fireSpawnAcc  = 0
    fireAmbSpawnAcc = 0
    UpdateContourReveal(0)
    ResetFireLayers()

    local bar = SCB.Bar
    if bar.texBGRed    then bar.texBGRed:SetAlpha(0)    ; bar.texBGRed:Hide()    end
    if bar.texFrameRed then bar.texFrameRed:SetAlpha(0) ; bar.texFrameRed:Hide() end
    if bgRedClip    then bgRedClip:Hide()    ; bgRedTex:SetAlpha(0)    end
    if frameRedClip then frameRedClip:Hide() ; frameRedTex:SetAlpha(0) end
    for i, clip in ipairs(fillEffectClips) do clip:Hide() ; fillEffectInnerTexes[i]:SetAlpha(0) end
    local bar2 = SCB.Bar
    if bar2.texFillEffects then for _, t in ipairs(bar2.texFillEffects) do t:SetAlpha(0) ; t:Hide() end end

    for _, p in ipairs(fireParts)    do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(fireAmbParts) do p.active = false ; p.tex:SetAlpha(0) end
end

-- Stop emission and begin the completion fade.
function FX.Stop(success)
    if success and not SCB.Bar.isChannel then UpdateContourReveal(1) end
end

-- Clear visible effects and pending fade state.
function FX.Reset()
    ResetFireLayers()
    if bgRedClip    then bgRedClip:Hide()    ; bgRedTex:SetAlpha(0)    end
    if frameRedClip then frameRedClip:Hide() ; frameRedTex:SetAlpha(0) end
    for i, clip in ipairs(fillEffectClips) do clip:Hide() ; fillEffectInnerTexes[i]:SetAlpha(0) end
    for i, clip in ipairs(contourClips) do
        clip:Hide()
        contourInnerTexes[i]:SetAlpha(0)
    end
    for _, p in ipairs(fireParts)    do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(fireAmbParts) do p.active = false ; p.tex:SetAlpha(0) end
end

-- Advance active-cast effects and emission.
function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    for _, p in ipairs(fireParts)    do UpdateFireParticle(p, dt) end
    for _, p in ipairs(fireAmbParts) do UpdateFireAmbient(p, dt) end

    UpdateFireLayers(dt, progress, barW, barH)

    fireSpawnAcc = fireSpawnAcc + dt
    if fireSpawnAcc >= FIRE_PART_SPAWN then
        fireSpawnAcc = 0
        local count = math.random(2, 4)
        for _ = 1, count do SpawnFireParticle(frontX, cy) end
    end

    fireAmbSpawnAcc = fireAmbSpawnAcc + dt
    if fireAmbSpawnAcc >= FIRE_AMB_SPAWN then
        fireAmbSpawnAcc = 0
        SpawnFireAmbient(progress)
    end
end
