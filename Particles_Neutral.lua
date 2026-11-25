-- ============================================================
--  Opulent Casting Bars -- Particles_Neutral.lua
--  Cyan motes emitted at the fill front (Neutral, Alliance).
--  Styles with a `gems` texture (Alliance) also light their frame
--  gems one by one as the fill reaches them.
-- ============================================================

-- Effect tuning: counts, timing, geometry, and colors.
local FX = {}
SCB.FX = SCB.FX or {}
SCB.FX["neutral"]  = FX
SCB.FX["alliance"] = FX

-- Sample a uniform value within the given range.
local function rand(a, b) return a + math.random() * (b - a) end

local NEUTRAL_COUNT      = 60
local NEUTRAL_SPAWN_RATE = 0.02
local NEUTRAL_COLOR_R    = 0x31 / 255
local NEUTRAL_COLOR_G    = 0xf4 / 255
local NEUTRAL_COLOR_B    = 0xfe / 255
local NEUTRAL_ALPHA      = 0.50
local NEUTRAL_STOP_AT    = 0.87

-- Gems: pixel rectangles in the 1024x512 gem atlas, which shares the frame
-- artwork's canvas. `core` is the lit gem at its exact frame position;
-- `bloom` is a glowing copy stored elsewhere in the atlas, drawn over the
-- core rect grown by GEM_PAD on every side. on0..on1 is the progress
-- window over which the gem lights up.
local GEM_TEX_W, GEM_TEX_H = 1024, 512
local GEM_PAD = 18
local GEMS = {
    { core = {  43, 226,  85, 251 }, bloom = {  16, 404,  94, 465 }, on0 = 0.00, on1 = 0.07 },  -- left
    { core = { 491, 294, 526, 352 }, bloom = { 170, 404, 241, 498 }, on0 = 0.46, on1 = 0.54 },  -- centre
    { core = { 939, 226, 982, 250 }, bloom = { 320, 404, 399, 464 }, on0 = 0.93, on1 = 1.00 },  -- right
}
local GEM_BLOOM_TIME  = 0.55   -- ignition flare duration (s)
local GEM_HALO_SCALE  = 0.70   -- extra size the halo grows by during the flare
local GEM_GLOW_BASE   = 0.22   -- steady additive glow once lit
local GEM_GLOW_PULSE  = 0.10   -- breathing amplitude of that glow
local GEM_PULSE_SPEED = 2.4    -- breathing speed (rad/s)

-- Particle pools and cast lifecycle state.
local host      -- own frame, so Neutral and Alliance share one pool
local barFrame
local parts     = {}
local spawnAcc  = 0
local gems      = {}
local gemsOn    = false
local gemTime   = 0
local gemW, gemH = 0, 0   -- bar size the gems were last laid out for
local lastProgress = 0

-- Activate an available particle particle and initialize its motion.
local function SpawnParticle(frontX, cy, barH)
    for _, p in ipairs(parts) do
        if not p.active then
            local spread = math.min(barH * 0.25, 10)
            p.active  = true
            p.life    = 0
            p.maxLife = rand(0.40, 0.70)
            p.x       = frontX + rand(0, 3)
            p.y       = cy + rand(-spread, spread)
            p.vx      = 0
            p.vy      = rand(-5, 5)
            p.phase   = math.random() * math.pi * 2

            local size = rand(3, 6)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
            p.tex:SetSize(size, size)
            p.tex:SetAlpha(0)
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

    p.vy = p.vy * (0.90 ^ (dt * 60))
    p.y  = p.y + p.vy * dt + math.sin(p.life * 10 + p.phase) * 0.3 * (dt * 60)
    p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)

    local alpha
    if t < 0.2 then alpha = t / 0.2
    elseif t < 0.8 then alpha = 1
    else alpha = (1 - t) / 0.2 end
    p.tex:SetAlpha(math.max(0, alpha) * NEUTRAL_ALPHA)
end

-- ============================================================
--  GEMS
-- ============================================================

local function Smooth(a, b, x)
    if x <= a then return 0 end
    if x >= b then return 1 end
    local t = (x - a) / (b - a)
    return t * t * (3 - 2 * t)
end

local function SetCrop(tex, r)
    tex:SetTexCoord(r[1] / GEM_TEX_W, r[3] / GEM_TEX_W, r[2] / GEM_TEX_H, r[4] / GEM_TEX_H)
end

-- Gem layers: the lit gem, an additive glow on it, and an additive halo
-- that swells and fades when the gem ignites.
local function CreateGems()
    for i, d in ipairs(GEMS) do
        local lit  = host:CreateTexture(nil, "ARTWORK")
        local glow = host:CreateTexture(nil, "OVERLAY", nil, 1)
        local halo = host:CreateTexture(nil, "OVERLAY", nil, 2)
        SetCrop(lit,  d.core)
        SetCrop(glow, d.bloom)
        SetCrop(halo, d.bloom)
        for _, tex in ipairs({ lit, glow, halo }) do
            tex:SetAlpha(0)
            tex:Hide()
        end
        gems[i] = {
            def = d, lit = lit, glow = glow, halo = halo,
            level = 0, armed = true, bloom = -1, bloomPeak = 1,
            phase = (i - 1) * 2.1,
            cx = 0, cy = 0, hw = 0, hh = 0,   -- bloom rect centre / half size
        }
    end
end

-- Anchor a glow/halo texture over the gem's bloom rect, `grow` times its
-- size around the gem centre. Two-corner anchors keep it mapped exactly
-- like the frame artwork, which spans the whole bar.
local function PlaceRect(tex, g, grow)
    local hw, hh = g.hw * grow, g.hh * grow
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT",     barFrame, "TOPLEFT", g.cx - hw, g.cy + hh)
    tex:SetPoint("BOTTOMRIGHT", barFrame, "TOPLEFT", g.cx + hw, g.cy - hh)
end

-- Place the gems over the frame artwork for a w x h bar. Uses the size the
-- bar was given (wrapper), not the anchored inner frame, whose measured
-- size can lag behind a resize.
local function LayoutGems(w, h)
    if not w or w <= 0 or not h or h <= 0 then return end
    gemW, gemH = w, h
    local sx, sy = w / GEM_TEX_W, h / GEM_TEX_H
    for _, g in ipairs(gems) do
        local c = g.def.core
        g.lit:ClearAllPoints()
        g.lit:SetPoint("TOPLEFT",     barFrame, "TOPLEFT", c[1] * sx, -c[2] * sy)
        g.lit:SetPoint("BOTTOMRIGHT", barFrame, "TOPLEFT", c[3] * sx, -c[4] * sy)
        g.cx =  (c[1] + c[3]) * 0.5 * sx
        g.cy = -(c[2] + c[4]) * 0.5 * sy
        g.hw =  ((c[3] - c[1]) * 0.5 + GEM_PAD) * sx
        g.hh =  ((c[4] - c[2]) * 0.5 + GEM_PAD) * sy
        PlaceRect(g.glow, g, 1)
        PlaceRect(g.halo, g, 1)
    end
end

local function BarSize()
    local f = SCB.Bar.frame
    local w, h = f and f:GetWidth(), f and f:GetHeight()
    if not w or w <= 0 then w = SCB.Config:Get("barWidth") or 400 end
    if not h or h <= 0 then h = SCB.Config:Get("barHeight") or 200 end
    return w, h
end

local function SetGemsShown(show)
    for _, g in ipairs(gems) do
        if show then
            g.lit:Show() ; g.glow:Show() ; g.halo:Show()
        else
            g.lit:Hide() ; g.glow:Hide() ; g.halo:Hide()
        end
        g.level, g.armed, g.bloom = 0, true, -1
        g.lit:SetAlpha(0) ; g.glow:SetAlpha(0) ; g.halo:SetAlpha(0)
    end
end

local function Ignite(g, peak)
    g.bloom     = 0
    g.bloomPeak = peak or 1
end

-- Draw each gem for its current light level and flare.
local function UpdateGems(dt)
    gemTime = gemTime + dt
    for _, g in ipairs(gems) do
        local flare = 0
        if g.bloom >= 0 then
            g.bloom = g.bloom + dt
            local k = g.bloom / GEM_BLOOM_TIME
            if k >= 1 then
                g.bloom = -1
                PlaceRect(g.halo, g, 1)
            else
                flare = (1 - k) * (1 - k) * g.bloomPeak
                PlaceRect(g.halo, g, 1 + GEM_HALO_SCALE * k)
            end
        end
        local pulse = GEM_GLOW_BASE + GEM_GLOW_PULSE * math.sin(gemTime * GEM_PULSE_SPEED + g.phase)
        g.lit:SetAlpha(g.level)
        g.glow:SetAlpha(math.min(1, g.level * pulse + flare * 0.8))
        g.halo:SetAlpha(flare * 0.65)
    end
end

-- Light each gem as the fill front reaches it; channels dim them as
-- the bar drains. A gem flares again only after it has gone mostly dark.
local function SetGemProgress(progress)
    for _, g in ipairs(gems) do
        local d = g.def
        g.level = Smooth(d.on0, d.on1, progress)
        if g.armed and g.level >= 0.9 then
            g.armed = false
            Ignite(g, 1)
        elseif not g.armed and g.level < 0.3 then
            g.armed = true
        end
    end
end

-- ============================================================
--  FX CONTRACT
-- ============================================================

-- Create textures and initialize the particle pools. Neutral and
-- Alliance share this module, so build everything once on its own host.
function FX.Init(container, bar)
    if host then return end
    barFrame = bar
    host = CreateFrame("Frame", nil, container:GetParent())
    host:SetAllPoints(container)
    host:Hide()

    local texPath = SCB.TEX_PATH .. "frost\\Particle_Frost_01"
    for i = 1, NEUTRAL_COUNT do
        local tex = host:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(texPath)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(NEUTRAL_COLOR_R, NEUTRAL_COLOR_G, NEUTRAL_COLOR_B)
        tex:SetAlpha(0)
        parts[i] = {
            tex=tex, active=false, life=0, maxLife=0,
            x=0, y=0, vx=0, vy=0, phase=0,
        }
    end
    CreateGems()
end

-- Begin a cast and reset existing particles.
function FX.Start(duration)
    spawnAcc = 0
    for _, p in ipairs(parts) do p.active = false ; p.tex:SetAlpha(0) end

    local school   = SCB.Bar.currentSchool
    local gemPath  = school and school.gems
    gemsOn = gemPath ~= nil
    if gemsOn then
        for _, g in ipairs(gems) do
            g.lit:SetTexture(gemPath)
            g.glow:SetTexture(gemPath)
            g.halo:SetTexture(gemPath)
            -- SetTexture can reset the blend mode; re-apply it.
            g.lit:SetBlendMode("BLEND")
            g.glow:SetBlendMode("ADD")
            g.halo:SetBlendMode("ADD")
        end
        LayoutGems(BarSize())
    end
    SetGemsShown(gemsOn)
    lastProgress = 0
    if host then host:Show() end
end

-- End emission; a completed cast lights and flares every gem together
-- with the end-of-cast flash.
function FX.Stop(success)
    if gemsOn and success and lastProgress > 0.5 then
        for _, g in ipairs(gems) do
            g.level = 1
            g.armed = false
            Ignite(g, g.bloom >= 0 and 1 or 0.7)
        end
    end
end

-- Advance surviving motes and gem flares without spawning.
function FX.UpdateFade(dt)
    for _, p in ipairs(parts) do UpdateParticle(p, dt) end
    if gemsOn then UpdateGems(dt) end
end

-- Hide effect textures and clear particle activity.
function FX.Reset()
    for _, p in ipairs(parts) do p.active = false ; p.tex:SetAlpha(0) end
    SetGemsShown(false)
    gemsOn = false
    if host then host:Hide() end
end

-- Advance the active cast effect and emit new particles.
function FX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW)
    for _, p in ipairs(parts) do UpdateParticle(p, dt) end

    if gemsOn then
        if barW ~= gemW or barH ~= gemH then LayoutGems(barW, barH) end
        lastProgress = progress
        SetGemProgress(progress)
        UpdateGems(dt)
    end

    if SCB.Particles.emitProgress < NEUTRAL_STOP_AT then
        spawnAcc = spawnAcc + dt
        if spawnAcc >= NEUTRAL_SPAWN_RATE then
            spawnAcc = 0
            local count = math.random(2, 4)
            for _ = 1, count do SpawnParticle(frontX, cy, barH) end
        end
    end
end
