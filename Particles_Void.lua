-- ============================================================
--  Opulent Casting Bars -- Particles_Void.lua
--  Rotating vortices, inward-spiraling stones, and violet/cyan particles.
-- ============================================================

local S = {}
local FX = {}
SCB.FX         = SCB.FX or {}
SCB.FX["void"] = FX

-- Local math helpers.
local function rand(a, b)    return a + math.random() * (b - a) end
local function rad(deg)      return deg * math.pi / 180 end
local function lerp(a, b, t) return a + (b - a) * math.max(0, math.min(t, 1)) end

-- Set texture dimensions.
local function SetTexSize(tex, w, h)
    tex:SetSize(w, h)
end

-- Rotate texture coordinates around the image center.
local function SetTexRot(tex, angle)
    local c, s = math.cos(angle), math.sin(angle)
    tex:SetTexCoord(
        0.5+(-0.5)*c-(-0.5)*s, 0.5+(-0.5)*s+(-0.5)*c,
        0.5+(-0.5)*c-( 0.5)*s, 0.5+(-0.5)*s+( 0.5)*c,
        0.5+( 0.5)*c-(-0.5)*s, 0.5+( 0.5)*s+(-0.5)*c,
        0.5+( 0.5)*c-( 0.5)*s, 0.5+( 0.5)*s+( 0.5)*c
    )
end

-- Ember palette.
S.EMBER_COLORS = {
    { 0.62, 0.30, 1.00 },
    { 0.42, 0.18, 0.98 },
    { 0.22, 0.72, 1.00 },
}

S.SPARK_COLORS = {
    { 0.50, 0.85, 1.00, 1.00 },
    { 0.65, 0.78, 1.00, 0.90 },
    { 0.70, 0.35, 1.00, 0.82 },
    { 0.38, 0.64, 1.00, 0.72 },
    { 0.82, 0.48, 1.00, 0.58 },
}

-- Vortex geometry and animation tuning.
S.VORTEX_SIZE = 38
S.VORTEX_OFFSET_Y = 36
S.VORTEX_OFFSET_X = -5
S.VORTEX_ROT_SPEED = 1.10
S.VORTEX_ALPHA = 1.00
S.SHOW_BACKGROUND_VORTEX = true
S.SHOW_FILL_VORTEX = true
S.VORTEX_TEX = SCB.TEX_PATH .. "void\\Vortex"
S.VORTEX_SMALL_TEX = S.VORTEX_TEX
S.VORTEX_FILL_SIZE = 256

S.VORTEX_FILL_MASK_TOP = 200 / 512
S.VORTEX_FILL_MASK_BOTTOM = 300 / 512

S.STONE_COUNT = 28
S.STONE_SPAWN_RATE = 0.18
S.STONE_SIZE_MIN = 4
S.STONE_SIZE_MAX = 10
S.STONE_SIZE_SCALE = 1.5
S.STONE_RADIUS_MIN = 28
S.STONE_RADIUS_MAX = 55
S.STONE_LIFE_MIN = 1.2
S.STONE_LIFE_MAX = 2.4
S.STONE_ROT_MIN = 2.5
S.STONE_ROT_MAX = 5.0

-- Front ember pool and emission tuning.
S.EMBER_COUNT = 90
S.EMBER_SPAWN = 0.02

S.emberTypes = {
    { sizeMin=6,  sizeMax=14, speedMin=20, speedMax=50,  lifeMin=0.9, lifeMax=1.8, gravity=-8,  spread=150, driftX=0.4 },
    { sizeMin=3,  sizeMax=7,  speedMin=60, speedMax=130, lifeMin=0.3, lifeMax=0.7, gravity=-10, spread=90,  driftX=0.0 },
    { sizeMin=4,  sizeMax=10, speedMin=30, speedMax=70,  lifeMin=0.7, lifeMax=1.3, gravity=-14, spread=110, driftX=0.2 },
}

-- Pixel spark pool and motion tuning.
S.SPARK_COUNT = 50
S.SPARK_SPAWN = 0.035
S.SPARK_SIZE_MIN = 2
S.SPARK_SIZE_MAX = 6
S.SPARK_LIFE_MIN = 0.4
S.SPARK_LIFE_MAX = 1.1
S.SPARK_SPEED_MIN = 25
S.SPARK_SPEED_MAX = 80
S.SPARK_GRAVITY = -20

-- Ambient pool and emission tuning.
S.AMB_COUNT = 40
S.AMB_SPAWN = 0.07

S.castDuration = 5

-- Cast and particle state.
S.isActive = false
S.partsFading = false
S.partsFadeT = 0
S.emberParts = {}
S.sparkParts = {}
S.ambParts = {}
S.emberSpawnAcc = 0
S.sparkSpawnAcc = 0
S.ambSpawnAcc = 0
S.castProgress = 0

S.texVortex = nil
S.vortexAngle = 0
S.vortexBar = nil
S.vortexFillAngle = 0
S.texLight = nil
S.maskLight = nil
S.lightBar = nil

S.vortCX = 0 ; S.vortCY = 0

S.stoneParts = {}
S.stoneSpawnAcc = 0

-- Lay out vortex.
local function LayoutVortex()
    if not S.texVortex or not S.vortexBar then return end

    local barW = S.vortexBar:GetWidth()
    local barH = S.vortexBar:GetHeight()
    if not barW or barW <= 0 or not barH or barH <= 0 then return end

    SetTexSize(S.texVortex, S.VORTEX_SIZE, S.VORTEX_SIZE)
    S.texVortex:ClearAllPoints()
    S.texVortex:SetPoint("CENTER", S.vortexBar, "CENTER",
        S.VORTEX_OFFSET_X, S.VORTEX_OFFSET_Y)
    -- Fixed size, anchored to the bar: it follows moves and resizes, so it
    -- only has to be laid out once.
    S.vortexLaidOut = true
end

-- Initialize vortex.
local function InitVortex(container, bar)
    if not S.SHOW_BACKGROUND_VORTEX then
        S.texVortex = nil
        S.vortexBar = nil
        S.vortexAngle = 0
        return
    end

    S.vortexBar = bar

    local host = (SCB.Bar and SCB.Bar.overlayHost) or bar
    S.texVortex = host:CreateTexture(nil, "ARTWORK")
    S.texVortex:SetTexture(S.VORTEX_SMALL_TEX)
    S.texVortex:SetBlendMode("BLEND")
    S.texVortex:SetTexCoord(0, 1, 0, 1)
    LayoutVortex()
    S.texVortex:SetAlpha(S.VORTEX_ALPHA)
    S.texVortex:Hide()
    S.vortexAngle = 0
end

-- Advance vortex.
local function UpdateVortex(dt, globalFade)
    if not S.texVortex then return end
    -- Retried until the bar has a size (it can still be 0 on the first tick).
    if not S.vortexLaidOut then LayoutVortex() end
    S.vortexAngle = (S.vortexAngle + S.VORTEX_ROT_SPEED * (dt or 0)) % (math.pi * 2)
    S.texVortex:SetRotation(S.vortexAngle)
    S.texVortex:SetAlpha(S.VORTEX_ALPHA * (globalFade or 1))
    S.texVortex:Show()
end

S.vortexFill2Angle = 0

-- The fill vortices draw on their own layer, above the fill artwork.
S.VORTEX_FILL_LAYER = "OVERLAY"
S.vfLayers = {}
S.vfAnchor = nil
S._vfBar = nil ; S._vfL = 0 ; S._vfW = 0 ; S._vfY = 0 ; S._vfH = 0 ; S._vfProg = 0
S._vfLayout = {}

-- Visit fill vortex.
local function ForEachFillVortex(fn)
    for _, L in ipairs(S.vfLayers) do
        fn(L.t1, 1) ; fn(L.t2, 2)
    end
end

-- Create fill vortex tex.
local function NewFillVortexTex(host, anchor, mask, size)
    local t = host:CreateTexture(nil, S.VORTEX_FILL_LAYER)
    t:SetBlendMode("BLEND")
    t:SetTexture(S.VORTEX_TEX)
    SetTexSize(t, size, size)
    t:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    SCB.AttachMask(t, mask)
    t:SetAlpha(0)
    t:Hide()
    return t
end

-- Place vortex pairs above each fill texture and below the border.
local function InitVortexFill(bar)
    S.vfLayers = {}
    S._vfLayout = {}
    S.vortexFillAngle, S.vortexFill2Angle = 0, 0
    if not S.SHOW_FILL_VORTEX then return end

    local size = S.VORTEX_FILL_SIZE

    S.vfAnchor = CreateFrame("Frame", nil, bar)
    S.vfAnchor:SetPoint("LEFT", bar, "LEFT", 0, 0)
    S.vfAnchor:SetWidth(1) ; S.vfAnchor:SetHeight(1)

    local B = SCB.Bar or {}
    local hosts, seen = {}, {}
    for _, h in ipairs({ B.fillHost, B.fillPlainHost }) do
        if h and not seen[h] then seen[h] = true ; hosts[#hosts+1] = h end
    end
    if #hosts == 0 then hosts[1] = bar end

    for _, host in ipairs(hosts) do
        local mask = SCB.NewRevealMask(host)
        mask:SetPoint("LEFT", bar, "LEFT", 0, 0)
        mask:SetWidth(1) ; mask:SetHeight(1)
        local t1 = NewFillVortexTex(host, S.vfAnchor, mask, size)
        local t2 = NewFillVortexTex(host, S.vfAnchor, mask, size)
        S.vfLayers[#S.vfLayers+1] = { host = host, mask = mask, t1 = t1, t2 = t2 }
    end
end

-- Lay out vortex fill.
local function LayoutVortexFill()
    local bar = S._vfBar
    if not bar or not S.vfAnchor then return end
    local fillW = math.max(1, S._vfW or 1)
    local fillH = math.max(1, S._vfH or 1)
    local frac  = math.max(0, math.min(S._vfProg or 0, 1))
    local L, Y  = S._vfL or 0, S._vfY or 0
    local c = S._vfLayout
    if c.bar ~= bar or c.w ~= fillW or c.h ~= fillH or c.l ~= L or c.y ~= Y then
        S.vfAnchor:ClearAllPoints()
        S.vfAnchor:SetPoint("LEFT", bar, "LEFT", L, Y)
        S.vfAnchor:SetWidth(fillW) ; S.vfAnchor:SetHeight(fillH)
        for _, layer in ipairs(S.vfLayers) do
            layer.mask:ClearAllPoints()
            layer.mask:SetPoint("LEFT", bar, "LEFT", L, Y)
            layer.mask:SetHeight(fillH)
        end
        c.bar, c.w, c.h, c.l, c.y = bar, fillW, fillH, L, Y
    end
    local revealW = math.max(1, fillW * frac)
    for _, layer in ipairs(S.vfLayers) do
        layer.mask:SetWidth(revealW)
        SCB.SetRevealMaskProgress(layer.mask, frac)
    end
end

-- Rotate both fill vortices at different speeds under the reveal masks.
local function UpdateVortexFill(dt, globalFade)
    if #S.vfLayers == 0 then return end
    LayoutVortexFill()

    S.vortexFillAngle  = (S.vortexFillAngle  + S.VORTEX_ROT_SPEED * 0.7 * (dt or 0)) % (math.pi * 2)
    S.vortexFill2Angle = (S.vortexFill2Angle + S.VORTEX_ROT_SPEED * 1.3 * (dt or 0)) % (math.pi * 2)
    local g = globalFade or 1
    for _, L in ipairs(S.vfLayers) do
        SetTexRot(L.t1, S.vortexFillAngle)  ; L.t1:SetAlpha(0.85 * g) ; L.t1:Show()
        SetTexRot(L.t2, S.vortexFill2Angle) ; L.t2:SetAlpha(0.55 * g) ; L.t2:Show()
    end
end

-- Refresh vortex and reveal-mask texture bindings for each cast.
local function RebindFillVortex()
    for _, L in ipairs(S.vfLayers) do
        L.mask:SetTexture(nil)
        L.mask:SetTexture(SCB.REVEAL_MASK_FULL)
        local edge = L.mask._scbEdge
        if edge then
            edge:SetTexture(nil)
            edge:SetTexture(SCB.REVEAL_MASK_EDGE)
        end
        for _, t in ipairs({ L.t1, L.t2 }) do
            if t.RemoveMaskTexture then
                t:RemoveMaskTexture(L.mask)
                if edge then t:RemoveMaskTexture(edge) end
            end
            t:SetTexture(nil)
            t:SetTexture(S.VORTEX_TEX)
            t:SetBlendMode("BLEND")
            SetTexSize(t, S.VORTEX_FILL_SIZE, S.VORTEX_FILL_SIZE)
            SCB.AttachMask(t, L.mask)
        end
    end
    S._vfLayout = {}
end

-- Hide vortex fill.
local function HideVortexFill()
    ForEachFillVortex(function(t) t:SetAlpha(0) ; t:Hide() end)
end

-- Orbiting stone textures.
S.STONE_TEXS = {
    SCB.TEX_PATH .. "mining\\Stone_01",
    SCB.TEX_PATH .. "mining\\Stone_02",
    SCB.TEX_PATH .. "mining\\Stone_03",
    SCB.TEX_PATH .. "mining\\Stone_04",
    SCB.TEX_PATH .. "mining\\Stone_05",
    SCB.TEX_PATH .. "mining\\Stone_06",
}

S.VOID_STONE_COLORS = {
    { 0.50, 0.15, 1.0 },
    { 0.35, 0.08, 0.9 },
    { 0.20, 0.50, 1.0 },
    { 0.60, 0.25, 1.0 },
}

-- Initialize stones.
local function InitStones(container)
    S.stoneParts = {}
    for i = 1, S.STONE_COUNT do
        local tex = container:CreateTexture(nil, "ARTWORK")
        tex:SetBlendMode("BLEND")
        tex:SetTexture(S.STONE_TEXS[((i-1) % 6) + 1])
        tex:SetAlpha(0)
        tex:Hide()
        S.stoneParts[i] = {
            tex=tex, active=false,
            angle=0, baseRadius=0, radius=0, angVel0=0,
            life=0, maxLife=0, baseSize=0,
            pertAmp=0, pertFreq=0, pertPhase=0,
            cr=0, cg=0, cb=0,
        }
    end
end

-- Spawn stone.
local function SpawnStone(cx, cy)
    for _, p in ipairs(S.stoneParts) do
        if not p.active then
            local col       = S.VOID_STONE_COLORS[math.random(#S.VOID_STONE_COLORS)]
            p.active        = true
            p.life          = 0
            p.maxLife       = rand(S.STONE_LIFE_MIN, S.STONE_LIFE_MAX)
            p.angle         = rand(0, math.pi * 2)
            p.baseRadius    = rand(S.STONE_RADIUS_MIN, S.STONE_RADIUS_MAX)
            p.radius        = p.baseRadius
            p.angVel0       = rand(S.STONE_ROT_MIN, S.STONE_ROT_MAX)
                              * (math.random() < 0.5 and 1 or -1)
            p.baseSize      = rand(S.STONE_SIZE_MIN, S.STONE_SIZE_MAX) * S.STONE_SIZE_SCALE
            p.pertAmp       = rand(3, 10)
            p.pertFreq      = rand(0.8, 2.8)
            p.pertPhase     = rand(0, math.pi * 2)
            p.cr, p.cg, p.cb = col[1], col[2], col[3]
            p.tex:SetSize(p.baseSize, p.baseSize)
            p.tex:SetVertexColor(p.cr, p.cg, p.cb)
            p.tex:SetAlpha(0)
            p.tex:Show()
            return
        end
    end
end

-- Pull stones inward while accelerating, shrinking, and darkening them.
local function UpdateStones(dt, cx, cy, globalFade)
    for _, p in ipairs(S.stoneParts) do
        if p.active then
            p.life = p.life + dt
            local t = p.life / p.maxLife
            if t >= 1 then
                p.active = false
                p.tex:SetAlpha(0)
                p.tex:Hide()
            else
                local eased   = t * t * t
                p.radius      = p.baseRadius * (1 - eased)

                local rSafe   = math.max(p.radius, 1.0)
                local angVel  = p.angVel0 * (p.baseRadius / rSafe)
                local maxAng  = S.STONE_ROT_MAX * 8
                angVel = math.max(-maxAng, math.min(maxAng, angVel))
                p.angle = p.angle + angVel * dt

                local perturb = math.sin(p.pertPhase + p.life * p.pertFreq * math.pi * 2)
                                * p.pertAmp * (1 - eased)

                local px = cx + math.cos(p.angle) * (p.radius + perturb)
                local py = cy + math.sin(p.angle) * (p.radius + perturb * 0.55)

                p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", px, py)

                local sz = math.max(1, p.baseSize * (1 - eased * 0.80))
                p.tex:SetSize(sz, sz)

                local bright = 1 - eased * 0.90
                p.tex:SetVertexColor(p.cr * bright, p.cg * bright, p.cb * bright)

                local alpha
                if t < 0.12 then
                    alpha = t / 0.12
                elseif t < 0.82 then
                    alpha = 1.0
                else
                    alpha = (1 - t) / 0.18
                end
                p.tex:SetAlpha(math.max(0, alpha) * 1.0 * (globalFade or 1))
            end
        end
    end
end

-- Revealed frame-light opacity.
S.LIGHT_ALPHA = 0.55

-- Initialize light.
local function InitLight(container, bar)
    local school = SCB.Schools.data["void"]
    if school and school.frameLight then
        S.lightBar  = bar
        S.texLight  = nil
        S.maskLight = nil
        return
    end

    S.lightBar = bar
    S.texLight = (SCB.Bar and SCB.Bar.decoHost or bar):CreateTexture(nil, "ARTWORK", nil, 4)
    S.texLight:SetBlendMode("BLEND")
    S.texLight:SetTexture((school and school.light) or (SCB.TEX_PATH .. "void\\Frame_Void_Light"))
    S.texLight:SetAllPoints(bar)
    S.texLight:SetAlpha(0)
    S.texLight:Hide()

    S.maskLight = bar:CreateMaskTexture()
    S.maskLight:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    S.maskLight:SetPoint("TOPLEFT",    bar, "TOPLEFT",    0, 0)
    S.maskLight:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    S.maskLight:SetWidth(1)
    SCB.AttachMask(S.texLight, S.maskLight)
end

-- Advance light.
local function UpdateLight(progress, globalFade)
    if not S.texLight or not S.maskLight then return end
    S.texLight:Show()
    S.texLight:SetAlpha(S.LIGHT_ALPHA * (globalFade or 1))
    local bW = (S.lightBar and S.lightBar:GetWidth()) or S.texLight:GetWidth()
    local visW = math.max(1, bW * progress)
    S.maskLight:SetWidth(visW)
    S.maskLight:SetPoint("TOPLEFT",    S.lightBar or S.texLight, "TOPLEFT",    0, 0)
    S.maskLight:SetPoint("BOTTOMLEFT", S.lightBar or S.texLight, "BOTTOMLEFT", 0, 0)
end

-- Spawn ember.
local function SpawnEmber(wx, wy)
    local roll    = math.random(10)
    local typeIdx = roll <= 4 and 1 or (roll <= 7 and 3 or 2)
    local ptype   = S.emberTypes[typeIdx]
    local col     = S.EMBER_COLORS[math.random(#S.EMBER_COLORS)]

    for _, p in ipairs(S.emberParts) do
        if not p.active and p.typeIdx == typeIdx then
            local tCast = math.max(0, math.min((S.castDuration - 2) / 3, 1))
            local speed = rand(lerp(ptype.speedMax * 0.5, ptype.speedMin, tCast),
                               lerp(ptype.speedMax, ptype.speedMax * 0.8, tCast))
            local angle = rad(90 + rand(-ptype.spread * 0.5, ptype.spread * 0.5))
            local size  = rand(ptype.sizeMin, ptype.sizeMax)
            p.active  = true ; p.life = 0
            p.maxLife = rand(ptype.lifeMin, ptype.lifeMax)
            p.x       = wx + rand(-6, 6)
            p.y       = wy + rand(-8, 8)
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

-- Advance ember.
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
    p.tex:SetAlpha(alpha * 0.9 * (globalFade or 1))
end

-- Spawn spark.
local function SpawnSpark(wx, wy)
    local col = S.SPARK_COLORS[math.random(#S.SPARK_COLORS)]
    for _, p in ipairs(S.sparkParts) do
        if not p.active then
            local angle = rad(rand(30, 150))
            local speed = rand(S.SPARK_SPEED_MIN, S.SPARK_SPEED_MAX)
            p.active    = true ; p.life = 0
            p.maxLife   = rand(S.SPARK_LIFE_MIN, S.SPARK_LIFE_MAX)
            p.x         = wx + rand(-4, 4)
            p.y         = wy + rand(-6, 6)
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

-- Advance spark.
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
    p.tex:SetAlpha(math.max(0, env) * p.baseAlpha * (globalFade or 1))
end

-- Spawn an ambient particle within the revealed bar.
local function SpawnAmb(progress)
    local f = SCB.Bar.frame
    local cx, cy = f:GetCenter()
    if not cx then return end
    local barW, barH = f:GetWidth(), f:GetHeight()

    for _, p in ipairs(S.ambParts) do
        if not p.active then
            local xOffset = rand(-barW * 0.5, barW * progress - barW * 0.5)
            local yOffset = rand(-barH * 0.35, barH * 0.35)
            local wx, wy  = cx + xOffset, cy + yOffset
            local dirX    = xOffset > 0 and 1 or -1
            local angle   = rad(rand(60, 120)) * (yOffset > 0 and 1 or -1)
            local speed   = rand(15, 45)
            local col     = S.EMBER_COLORS[math.random(#S.EMBER_COLORS)]

            p.active  = true ; p.life = 0
            p.maxLife = rand(1.0, 2.2)
            p.x       = wx ; p.y = wy
            p.vx      = dirX * rand(5, 20)
            p.vy      = math.sin(angle) * speed
            p.tex:SetVertexColor(col[1], col[2], col[3])
            local size = rand(4, 10)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(0)
            return
        end
    end
end

-- Advance amb.
local function UpdateAmb(p, dt, globalFade)
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
    p.tex:SetAlpha(math.max(0, alpha) * 0.55 * (globalFade or 1))
end

-- Create texture hosts, animation slots, and particle pools.
function FX.Init(container, bar)
    InitVortex(container, bar)
    InitVortexFill(bar)
    InitLight(container, bar)
    InitStones(container)

    local voidSchool = SCB.Schools.data["void"]
    local miscTexs = {}

    if voidSchool then
        for _, t in ipairs(voidSchool.misc or {}) do miscTexs[#miscTexs+1] = t end
    end

    if #miscTexs == 0 then
        local earthSchool = SCB.Schools.data["earth"]
        if earthSchool then
            for _, t in ipairs(earthSchool.rocks  or {}) do miscTexs[#miscTexs+1] = t end
            for _, t in ipairs(earthSchool.debris or {}) do miscTexs[#miscTexs+1] = t end
        end
    end

    local function getMisc(i)
        if #miscTexs == 0 then return SCB.TEX_PATH .. "frost\\Particle_Frost_01" end
        return miscTexs[((i-1) % #miscTexs) + 1]
    end

    S.emberParts = {}
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
    end

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

    S.ambParts = {}
    for i = 1, S.AMB_COUNT do
        local tex = container:CreateTexture(nil, "BACKGROUND")
        tex:SetTexture(getMisc(i))
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)
        S.ambParts[i] = {
            tex=tex, active=false, life=0, maxLife=0,
            x=0, y=0, vx=0, vy=0,
        }
    end
end

-- Start a cast and reset effect timing.
function FX.Start(duration)
    S.castDuration  = duration or 5
    S.isActive      = true
    S.partsFading   = false
    S.castProgress  = 0
    S.emberSpawnAcc = 0
    S.sparkSpawnAcc = 0
    S.ambSpawnAcc   = 0
    S.stoneSpawnAcc = 0
    for _, p in ipairs(S.emberParts) do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.sparkParts) do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.ambParts)   do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.stoneParts) do p.active = false ; p.tex:SetAlpha(0) ; p.tex:Hide() end
    LayoutVortex()
    if S.texVortex      then S.texVortex:Show()      end
    RebindFillVortex()
    ForEachFillVortex(function(t) t:Show() end)
    if S.texLight       then S.texLight:Show()       end
end

-- Stop emission and begin the completion fade.
function FX.Stop()
    S.isActive      = false
    S.partsFading   = true
    S.partsFadeT    = 0
    S.emberSpawnAcc = 0
    S.sparkSpawnAcc = 0
    S.ambSpawnAcc   = 0
end

-- Advance existing effects during the stop fade.
function FX.UpdateFade(dt)
    if not S.partsFading then return end
    S.partsFadeT = S.partsFadeT + dt
    local gFade = 1
    UpdateVortex(dt, gFade)
    UpdateVortexFill(dt, gFade)
    UpdateLight(S.castProgress, gFade)
    UpdateStones(dt, S.vortCX, S.vortCY, gFade)
    for _, p in ipairs(S.emberParts) do UpdateEmber(p, dt, gFade) end
    for _, p in ipairs(S.sparkParts) do UpdateSpark(p, dt, gFade) end
    for _, p in ipairs(S.ambParts)   do UpdateAmb(p,   dt, gFade) end
    if S.partsFadeT >= SCB.FX_LINGER then
        S.partsFading = false
        if S.texVortex      then S.texVortex:SetAlpha(0)      ; S.texVortex:Hide()      end
        HideVortexFill()
        if S.texLight       then S.texLight:SetAlpha(0)       ; S.texLight:Hide()       end
        for _, p in ipairs(S.stoneParts) do p.active = false ; p.tex:SetAlpha(0) ; p.tex:Hide() end
        for _, p in ipairs(S.emberParts) do p.active = false ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.sparkParts) do p.active = false ; p.tex:SetAlpha(0) end
        for _, p in ipairs(S.ambParts)   do p.active = false ; p.tex:SetAlpha(0) end
    end
end

-- Clear visible effects and pending fade state.
function FX.Reset()
    S.isActive    = false
    S.partsFading = false
    if S.texVortex      then S.texVortex:SetAlpha(0)      ; S.texVortex:Hide()      end
    HideVortexFill()
    if S.texLight       then S.texLight:SetAlpha(0)       ; S.texLight:Hide()       end
    for _, p in ipairs(S.stoneParts) do p.active = false ; p.tex:SetAlpha(0) ; p.tex:Hide() end
    for _, p in ipairs(S.emberParts) do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.sparkParts) do p.active = false ; p.tex:SetAlpha(0) end
    for _, p in ipairs(S.ambParts)   do p.active = false ; p.tex:SetAlpha(0) end
end

-- Advance active-cast effects and emission.
function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    if not S.isActive then return end
    S.castProgress = progress or 0

    local f = SCB.Bar.frameInner
    local barCX, barCY = f:GetCenter()
    if not barCY then return end

    S.vortCX = barCX + S.VORTEX_OFFSET_X
    S.vortCY = barCY + S.VORTEX_OFFSET_Y

    local vs = SCB.Schools.data["void"]
    S._vfBar  = f
    S._vfL    = (vs and vs.fillMarginL or 0) * barW + (vs and vs.fillMarginLPx or 0)
    S._vfW    = fillW or barW
    local fullH = barH or f:GetHeight()
    S._vfY    = fullH * (0.5 - (S.VORTEX_FILL_MASK_TOP + S.VORTEX_FILL_MASK_BOTTOM) * 0.5)
    S._vfH    = math.max(1, fullH * (S.VORTEX_FILL_MASK_BOTTOM - S.VORTEX_FILL_MASK_TOP))
    S._vfProg = S.castProgress

    UpdateVortex(dt, 1)
    UpdateVortexFill(dt, 1)
    UpdateLight(S.castProgress, 1)

    UpdateStones(dt, S.vortCX, S.vortCY, 1)
    S.stoneSpawnAcc = S.stoneSpawnAcc + dt
    if S.stoneSpawnAcc >= S.STONE_SPAWN_RATE then
        S.stoneSpawnAcc = 0
        SpawnStone(S.vortCX, S.vortCY)
    end

    for _, p in ipairs(S.emberParts) do UpdateEmber(p, dt, 1) end
    S.emberSpawnAcc = S.emberSpawnAcc + dt
    if S.emberSpawnAcc >= S.EMBER_SPAWN then
        S.emberSpawnAcc = 0
        local count = math.random(3, 6)
        for _ = 1, count do SpawnEmber(frontX, barCY) end
    end

    for _, p in ipairs(S.sparkParts) do UpdateSpark(p, dt, 1) end
    S.sparkSpawnAcc = S.sparkSpawnAcc + dt
    if S.sparkSpawnAcc >= S.SPARK_SPAWN then
        S.sparkSpawnAcc = 0
        local count = math.random(2, 4)
        for _ = 1, count do SpawnSpark(frontX, barCY) end
    end

    for _, p in ipairs(S.ambParts) do UpdateAmb(p, dt, 1) end
    S.ambSpawnAcc = S.ambSpawnAcc + dt
    if S.ambSpawnAcc >= S.AMB_SPAWN then
        S.ambSpawnAcc = 0
        SpawnAmb(S.castProgress)
    end
end
