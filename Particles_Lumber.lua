-- ============================================================
--  Opulent Casting Bars -- Particles_Lumber.lua
--  Five chopping stages with shakes and chips; successful casts split the log.
--  Uses ClassicAPI sizing, timers, texture sublevels and rotation.
-- ============================================================

local FX = {}
SCB.FX            = SCB.FX or {}
SCB.FX["lumber"]  = FX

local TEX = SCB.TEX_PATH .. "lumber\\"

local function rand(a, b) return a + math.random() * (b - a) end
local pi2 = math.pi * 2

-- Log artwork and progress thresholds.
local STAGES = {
    TEX .. "Lumber_01",
    TEX .. "Lumber_02",
    TEX .. "Lumber_03",
    TEX .. "Lumber_04",
    TEX .. "Lumber_05",
}

local STAGE_THRESHOLDS = { 0.00, 0.20, 0.40, 0.60, 0.80 }

-- Wood chip texture variants.
local MISC_TEX = {
    TEX .. "Lumber_Misc_01",
    TEX .. "Lumber_Misc_02",
    TEX .. "Lumber_Misc_03",
    TEX .. "Lumber_Misc_04",
    TEX .. "Lumber_Misc_05",
}

-- Chip pool, burst size, launch motion, gravity, and fading.
local CHIP_COUNT     = 52
local CHIP_PER_STAGE = 9
local CHIP_SPEED_MIN = 45
local CHIP_SPEED_MAX = 135
local CHIP_GRAVITY   = 210
local CHIP_LIFE_MIN  = 0.38
local CHIP_LIFE_MAX  = 0.90
local CHIP_SIZE_MIN  = 8
local CHIP_SIZE_MAX  = 24
local CHIP_ALPHA     = 0.92

-- Final split launch motion, rotation, gravity, and scale.
local SPLIT_GRAVITY     = 170
local SPLIT_VX_MIN      = 90
local SPLIT_VX_MAX      = 150
local SPLIT_VY_MIN      = 35
local SPLIT_VY_MAX      = 80
local SPLIT_ROT_MIN     = 1.2
local SPLIT_ROT_MAX     = 2.8
local SPLIT_SIZE_FACTOR = 0.85

-- Shake amplitude, timer interval, and number of offsets.
local SHAKE_AMOUNT   = 5
local SHAKE_INTERVAL = 0.028
local SHAKE_COUNT    = 5

-- Cast, fade, stage, and particle state.
local isActive     = false
local isFading     = false
local fadeT        = 0
local currentStage = 0
local chips        = {}

-- Log artwork sits beneath the OVERLAY labels.
local stageTex  = nil

-- Split textures and their independent motion state.
local splitActive  = false
local leftTex      = nil
local rightTex     = nil
local leftX,  leftY,  leftVX,  leftVY,  leftRot,  leftRotSpeed  = 0,0,0,0,0,0
local rightX, rightY, rightVX, rightVY, rightRot, rightRotSpeed = 0,0,0,0,0,0

local savedCX, savedCY, savedBarH = 0, 0, 0

-- Emit a bounded burst of rotating wood chips.
local function SpawnChip(cx, cy, barH)
    local spread  = math.min(barH * 0.22, 14)
    local spawned = 0
    for _, p in ipairs(chips) do
        if not p.active then
            local angle = rand(0, pi2)
            local speed = rand(CHIP_SPEED_MIN, CHIP_SPEED_MAX)
            p.active   = true
            p.life     = 0
            p.maxLife  = rand(CHIP_LIFE_MIN, CHIP_LIFE_MAX)
            p.x        = cx + rand(-10, 10)
            p.y        = cy + rand(-spread, spread)
            p.vx       = math.cos(angle) * speed
            p.vy       = math.sin(angle) * speed + rand(8, 28)
            p.rot      = rand(0, pi2)
            p.rotSpeed = rand(2.0, 5.5) * (math.random(2) == 1 and 1 or -1)
            local sz   = rand(CHIP_SIZE_MIN, CHIP_SIZE_MAX)
            p.tex:SetSize(sz, sz)
            p.tex:SetAlpha(0)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            spawned = spawned + 1
            if spawned >= CHIP_PER_STAGE then return end
        end
    end
end

-- Integrate chip gravity and rotation with a short fade envelope.
local function UpdateChip(p, dt, gf)
    if not p.active then return end
    p.life = p.life + dt
    local t = p.life / p.maxLife
    if t >= 1 then p.active = false ; p.tex:SetAlpha(0) ; return end
    p.vy  = p.vy  - CHIP_GRAVITY * dt
    p.x   = p.x   + p.vx * dt
    p.y   = p.y   + p.vy * dt
    p.rot = p.rot + p.rotSpeed * dt
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    p.tex:SetRotation(p.rot)
    local env = t < 0.14 and (t / 0.14) or (t < 0.68 and 1 or math.max(0, (1 - t) / 0.32))
    p.tex:SetAlpha(env * CHIP_ALPHA * (gf or 1))
end

local shakeGeneration = 0

-- Restore the configured bar anchor after a shake.
local function RestoreBarPosition()
    local frame = SCB.Bar and SCB.Bar.frame
    local anchor = SCB.Config:Get("anchor")
    if frame and anchor then
        frame:ClearAllPoints()
        frame:SetPoint(anchor, UIParent, anchor, SCB.Config:Get("x"), SCB.Config:Get("y"))
    end
end

-- Alternate short timer-driven offsets, rejecting obsolete shake callbacks.
local function TriggerShake()
    local frame = SCB.Bar and SCB.Bar.frame
    if not frame then return end
    local anchor = SCB.Config:Get("anchor")
    local origX  = SCB.Config:Get("x")
    local origY  = SCB.Config:Get("y")
    if not anchor then return end
    shakeGeneration = shakeGeneration + 1
    -- Only the latest shake and cast may continue moving the bar.
    local generation     = shakeGeneration
    local castGeneration = SCB.Bar.castGeneration
    local count = 0

    local function doShake()

        if generation ~= shakeGeneration or castGeneration ~= SCB.Bar.castGeneration then return end
        if not SCB.Bar.isActive and not SCB.Bar.isFading then RestoreBarPosition() ; return end
        count = count + 1
        if count > SHAKE_COUNT then
            frame:ClearAllPoints()
            frame:SetPoint(anchor, UIParent, anchor, origX, origY)
            return
        end
        local ox = (count % 2 == 0) and SHAKE_AMOUNT or -SHAKE_AMOUNT
        local oy = (count % 2 == 0) and -2 or 2
        frame:ClearAllPoints()
        frame:SetPoint(anchor, UIParent, anchor, origX + ox, origY + oy)
        C_Timer.After(SHAKE_INTERVAL, doShake)
    end

    doShake()
end

-- Hide the log and labels, then launch two rotating halves.
local function TriggerSplit()
    local cx   = savedCX
    local cy   = savedCY
    local barH = savedBarH
    if cx == 0 and cy == 0 then return end

    if stageTex then stageTex:SetAlpha(0) end
    if SCB.Bar then
        if SCB.Bar.texBG        then SCB.Bar.texBG:SetAlpha(0)        end
        if SCB.Bar.spellNameText then SCB.Bar.spellNameText:SetAlpha(0) end
        if SCB.Bar.castTimerText  then SCB.Bar.castTimerText:SetAlpha(0)  end
    end

    local texSz = math.max(barH, 40) * SPLIT_SIZE_FACTOR
    local halfOff = barH * 0.08

    leftX        = cx - halfOff
    leftY        = cy
    leftVX       = -rand(SPLIT_VX_MIN, SPLIT_VX_MAX)
    leftVY       =  rand(SPLIT_VY_MIN, SPLIT_VY_MAX)
    leftRot      =  0
    leftRotSpeed = -rand(SPLIT_ROT_MIN, SPLIT_ROT_MAX)

    rightX        = cx + halfOff
    rightY        = cy
    rightVX       =  rand(SPLIT_VX_MIN, SPLIT_VX_MAX)
    rightVY       =  rand(SPLIT_VY_MIN, SPLIT_VY_MAX)
    rightRot      =  0
    rightRotSpeed =  rand(SPLIT_ROT_MIN, SPLIT_ROT_MAX)

    splitActive = true

    if leftTex then
        leftTex:SetSize(texSz, texSz)
        leftTex:SetAlpha(1)
        leftTex:SetRotation(0)
        leftTex:ClearAllPoints()
        leftTex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", leftX, leftY)
    end
    if rightTex then
        rightTex:SetSize(texSz, texSz)
        rightTex:SetAlpha(1)
        rightTex:SetRotation(0)
        rightTex:ClearAllPoints()
        rightTex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", rightX, rightY)
    end
end

-- Integrate both log halves in the same coordinates as the chips.
local function UpdateSplit(dt)
    if not splitActive then return end

    leftVY   = leftVY  - SPLIT_GRAVITY * dt
    rightVY  = rightVY - SPLIT_GRAVITY * dt
    leftX    = leftX   + leftVX  * dt
    leftY    = leftY   + leftVY  * dt
    rightX   = rightX  + rightVX * dt
    rightY   = rightY  + rightVY * dt
    leftRot  = leftRot  + leftRotSpeed  * dt
    rightRot = rightRot + rightRotSpeed * dt

    if leftTex then
        leftTex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", leftX, leftY)
        leftTex:SetRotation(leftRot)
    end
    if rightTex then
        rightTex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", rightX, rightY)
        rightTex:SetRotation(rightRot)
    end
end

-- Create artwork and reusable texture pools.
function FX.Init(container, frameInner)

    stageTex = frameInner:CreateTexture(nil, "ARTWORK", nil, 2)
    stageTex:SetAllPoints(frameInner)
    stageTex:SetTexture(STAGES[1])
    stageTex:SetBlendMode("BLEND")
    stageTex:SetAlpha(0)

    local nMisc = #MISC_TEX
    chips = {}
    for i = 1, CHIP_COUNT do
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(MISC_TEX[((i - 1) % nMisc) + 1])
        tex:SetBlendMode("BLEND")
        tex:SetAlpha(0)
        chips[i] = {
            tex=tex, active=false,
            life=0, maxLife=0,
            x=0, y=0, vx=0, vy=0,
            rot=0, rotSpeed=0,
        }
    end

    leftTex = container:CreateTexture(nil, "OVERLAY")
    leftTex:SetTexture(TEX .. "Lumber_Left")
    leftTex:SetBlendMode("BLEND")
    leftTex:SetAlpha(0)

    rightTex = container:CreateTexture(nil, "OVERLAY")
    rightTex:SetTexture(TEX .. "Lumber_Right")
    rightTex:SetBlendMode("BLEND")
    rightTex:SetAlpha(0)

    -- Warm artwork with tiny, nearly transparent UIParent textures.
    local function preload(path)
        local t = UIParent:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(path) ; t:SetSize(1,1) ; t:SetAlpha(0.0001)
        t:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    end
    for _, p in ipairs(MISC_TEX) do preload(p) end
    for _, p in ipairs(STAGES)   do preload(p) end
    preload(TEX .. "Lumber_Left")
    preload(TEX .. "Lumber_Right")
end

-- Initialize a new cast and clear leftover particles.
function FX.Start(dur)
    isActive     = true
    isFading     = false
    fadeT        = 0
    currentStage = 0
    splitActive  = false

    if stageTex then
        stageTex:SetTexture(STAGES[1])
        stageTex:SetAlpha(1)
        stageTex:SetTexCoord(0, 1, 0, 1)
    end

    if SCB.Bar then
        if SCB.Bar.spellNameText then SCB.Bar.spellNameText:SetAlpha(1) end
        if SCB.Bar.castTimerText  then SCB.Bar.castTimerText:SetAlpha(1)  end
    end

    for _, p in ipairs(chips) do p.active = false ; p.tex:SetAlpha(0) end
    if leftTex  then leftTex:SetAlpha(0)  end
    if rightTex then rightTex:SetAlpha(0) end
end

-- Stop emission and begin the style's end-of-cast behavior.
function FX.Stop(success)
    isActive = false
    isFading = true
    fadeT    = 0

    if SCB.Bar and SCB.Bar.frame then
        local f = SCB.Bar.frame
        local cx, cy = f:GetCenter()
        if cx then

            savedCX   = cx
            savedCY   = cy
            savedBarH = f:GetHeight()
        end
    end

    if success then
        TriggerSplit()
    end
end

-- Advance residual motion and opacity after the cast ends.
function FX.UpdateFade(dt)
    if not isFading then return end
    fadeT = fadeT + dt

    -- Keep hidden layers suppressed while the wrapper fade runs.
    if splitActive then
        if stageTex then stageTex:SetAlpha(0) end
        if SCB.Bar then
            if SCB.Bar.texBG   then SCB.Bar.texBG:SetAlpha(0)   end
            if SCB.Bar.texFill then SCB.Bar.texFill:SetAlpha(0) end
        end
    end

    UpdateSplit(dt)
    local gf = 1
    for _, p in ipairs(chips) do UpdateChip(p, dt, gf) end
end

-- Clear residual effects and restore owned artwork.
function FX.Reset()
    if shakeGeneration > 0 then shakeGeneration = shakeGeneration + 1 ; RestoreBarPosition() end
    isActive     = false
    isFading     = false
    fadeT        = 0
    splitActive  = false
    currentStage = 0

    if stageTex then stageTex:SetAlpha(0) end

    if SCB.Bar then
        if SCB.Bar.texBG         then SCB.Bar.texBG:SetAlpha(1)         end
        if SCB.Bar.spellNameText then SCB.Bar.spellNameText:SetAlpha(1) end
        if SCB.Bar.castTimerText  then SCB.Bar.castTimerText:SetAlpha(1)  end
    end

    for _, p in ipairs(chips) do p.active = false ; p.tex:SetAlpha(0) end
    if leftTex  then leftTex:SetAlpha(0)  ; leftTex:SetRotation(0)  end
    if rightTex then rightTex:SetAlpha(0) ; rightTex:SetRotation(0) end
end

-- Advance active-cast animation and particle emission.
function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    if not isActive then return end

    local newStage = 1
    for i = #STAGE_THRESHOLDS, 1, -1 do
        if progress >= STAGE_THRESHOLDS[i] then
            newStage = i
            break
        end
    end

    if newStage ~= currentStage then
        currentStage = newStage
        if stageTex then
            stageTex:SetTexture(STAGES[newStage])
            stageTex:SetTexCoord(0, 1, 0, 1)
        end
        TriggerShake()
        local cx = fillLX + fillW * 0.5
        SpawnChip(cx, cy, barH)
    end

    for _, p in ipairs(chips) do UpdateChip(p, dt, 1) end
end
