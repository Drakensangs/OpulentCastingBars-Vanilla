-- ============================================================
--  Opulent Casting Bars -- Particles.lua
--
--  Dispatcher for the per-style visual effects. Each
--  Particles_<Style>.lua registers SCB.FX["<style>"] = FX with:
--    FX.Init(container, frameInner)  once, on first use (lazy)
--    FX.Start(duration)              cast begins
--    FX.Update(dt, progress, frontX, cy, barW, barH,
--              fillLX, fillW, fillLXRight, fillWRight)  every tick
--    FX.Stop(success)                cast ends; the fade-out begins
--    FX.Reset()                      hide and clear everything
--  Optional: FX.UpdateFade(dt) / FX.UpdateCirclesFade(dt) during the
--  fade-out, and FX.Resize() when the bar size changes.
--
--  Also drives two bar-level layers: the Frost background reveal
--  (FrostBG) and the Frostfire frost overlay.
-- ============================================================

SCB.Particles = {}
-- Elapsed share of the cast (0 at start, 1 at end), whatever the fill
-- direction. FX modules gate their emission on it, so a channel (whose
-- fill starts at 1 and empties) emits from its very first frame instead of
-- waiting for the fill to drop below the styles' *_STOP_AT thresholds.
SCB.Particles.emitProgress = 0
SCB.FX        = SCB.FX or {}

-- ============================================================
--  HELPERS
-- ============================================================

-- Bar center (screen coordinates) and size. The size is the one the bar
-- was given (Bar:ApplyDimensions), so it needs no GetWidth/GetHeight call.
local function GetBarDimensions()
    local bar = SCB.Bar
    local cx, cy = bar.frame:GetCenter()
    if not cx then return nil end
    local w, h = bar._appliedW, bar._appliedH
    if not w or w <= 0 then w = (SCB.Config and SCB.Config:Get("barWidth"))  or 400 end
    if not h or h <= 0 then h = (SCB.Config and SCB.Config:Get("barHeight")) or 200 end
    return cx, cy, w, h
end

-- FrostBG (created by Particles_Frost Init) is revealed left to right by
-- cropping its width and texcoords. Only changed values are re-applied.
function SCB.Particles:UpdateFrostBG(schoolKey, progress)
    if schoolKey ~= "frost" then self:ResetFrostBG() ; return end
    if not self.frostBGHost or not self.frostBGTex then return end
    progress = tonumber(progress) or 0
    if progress ~= progress then progress = 0 end   -- NaN guard
    progress = math.max(0, math.min(progress, 1))
    local barW = math.max(1, SCB.Config:Get("barWidth") or 400)
    local revealW = math.max(1, barW * progress)
    if self._frostBGRevealW ~= revealW or self._frostBGBarW ~= barW then
        self.frostBGHost:SetWidth(revealW)
        self.frostBGTex:SetWidth(revealW)
        self.frostBGTex:SetTexCoord(0, revealW / barW, 0, 1)
        self._frostBGRevealW, self._frostBGBarW = revealW, barW
    end
    local alpha = progress > 0 and 1 or 0
    if self._frostBGAlpha ~= alpha then
        self.frostBGTex:SetAlpha(alpha)
        self._frostBGAlpha = alpha
    end
    if not self._frostBGShown then
        self.frostBGHost:Show()
        self._frostBGShown = true
    end
end

function SCB.Particles:ResetFrostBG()
    if self.frostBGHost then self.frostBGHost:Hide() end
    if self.frostBGTex then self.frostBGTex:SetAlpha(0) end
    self._frostBGRevealW, self._frostBGBarW = nil, nil
    self._frostBGAlpha, self._frostBGShown = nil, nil
end

-- ============================================================
--  FROSTFIRE -- frost overlay revealed with progress
-- ============================================================

function SCB.Particles:UpdateFrostfireLayers(schoolKey, progress)
    local bar = SCB.Bar
    if schoolKey ~= "frostfire" then
        if bar.maskGivreFrostfire then bar.maskGivreFrostfire:SetWidth(1) end
        if bar.givreHost then bar.givreHost:Hide() end
        return
    end
    if bar.maskGivreFrostfire then
        -- Texture_Givre_Frostfire spans the full bar; reveal width is barW * progress.
        local barW = (SCB.Config and SCB.Config:Get("barWidth")) or 400
        bar.maskGivreFrostfire:SetWidth(math.max(barW * progress, 1))
    end
end

function SCB.Particles:ResetFrostfireLayers()
    local bar = SCB.Bar
    if bar.maskGivreFrostfire then bar.maskGivreFrostfire:SetWidth(1) end
    if bar.givreHost          then bar.givreHost:Hide() end
end

-- ============================================================
--  STATE
-- ============================================================

local isRunning    = false
local castDuration = 5
local currentFX    = nil   -- FX module of the style being shown

-- ============================================================
--  INIT
-- ============================================================

function SCB.Particles:Init()
    -- FX modules are initialized lazily on first use (EnsureFX). Building
    -- them all at login would create thousands of textures and cause a
    -- long hitch.
    self.fxFrames = {}
    self.fxInitialized = {}
    -- Styles whose FX may still show something (started since their last
    -- Reset). ResetAll resets only these, not every style used this session.
    self.fxDirty = {}

    -- Animated contours are frame art, so reveal them across the full bar
    -- rather than the inset fill area.
    local contourMask = SCB.Bar.maskFrameRed or SCB.Bar.texMask
    if contourMask then
        for _, t in ipairs(SCB.Bar.texContoursFire) do
            SCB.AttachMask(t, contourMask)
        end
    end
end

-- Keep every FX sub-frame on the particle container after a resize.
function SCB.Particles:LayoutFrames()
    local container = SCB.Bar and SCB.Bar.particleContainer
    if not container or not self.fxFrames then return end

    for _, sub in pairs(self.fxFrames) do
        if sub then
            sub:ClearAllPoints()
            sub:SetAllPoints(container)
        end
    end
end

-- Bar size changed: re-layout and restart the running effect.
function SCB.Particles:RefreshLayout()
    self:LayoutFrames()
    self:ResetFrostBG()
    if not currentFX then return end
    if currentFX.Resize then
        currentFX.Resize()
    end
    if isRunning then
        if currentFX.Reset then currentFX.Reset() end
        if currentFX.Start then currentFX.Start(castDuration) end
    end
end

-- Particle textures: most particles hold the same alpha for part of their
-- life (and every idle one sits at 0), so their SetAlpha skips values that
-- are already set. Exact: nothing else changes these textures' alpha (no
-- animation groups), and an identical number gives an identical result.
local NativeSetAlpha
local function CachedSetAlpha(self, a)
    if self._ocbAlpha ~= a then
        self._ocbAlpha = a
        NativeSetAlpha(self, a)
    end
end

-- Give every texture created on an FX sub-frame the cached SetAlpha.
local function WrapParticleTextures(sub)
    local CreateTexture = sub.CreateTexture
    sub.CreateTexture = function(self, name, layer, template, subLevel)
        local t = CreateTexture(self, name, layer, template, subLevel)
        NativeSetAlpha = NativeSetAlpha or t.SetAlpha
        t._ocbAlpha = t:GetAlpha()
        t.SetAlpha = CachedSetAlpha
        return t
    end
end

-- Sub-frame and FX module for a style, creating/initializing them once.
function SCB.Particles:EnsureFX(schoolKey)
    if not schoolKey then return nil end

    local fx = SCB.FX and SCB.FX[schoolKey]
    if not fx then return nil end

    self.fxFrames = self.fxFrames or {}
    self.fxInitialized = self.fxInitialized or {}

    local sub = self.fxFrames[schoolKey]
    if not sub then
        sub = CreateFrame("Frame", nil, SCB.Bar.particleContainer)
        sub:SetAllPoints(SCB.Bar.particleContainer)
        sub:Hide()
        WrapParticleTextures(sub)
        self.fxFrames[schoolKey] = sub
    end

    if not self.fxInitialized[schoolKey] and fx.Init then
        fx.Init(sub, SCB.Bar.frameInner)
        self.fxInitialized[schoolKey] = true
    end

    return sub, fx
end

-- Initialize a style's FX ahead of its first cast (retried out of combat).
function SCB.Particles:PrewarmFX(schoolKey)
    if not schoolKey then return end
    if self.fxInitialized and self.fxInitialized[schoolKey] then return end

    if InCombatLockdown() then
        C_Timer.After(5, function()
            if SCB.Particles and SCB.Particles.PrewarmFX then
                SCB.Particles:PrewarmFX(schoolKey)
            end
        end)
        return
    end

    local sub, fx = self:EnsureFX(schoolKey)
    if sub then sub:Hide() end
    if fx and fx.Reset then fx.Reset() end
end

-- ============================================================
--  START / STOP
-- ============================================================

function SCB.Particles:Start(duration)
    isRunning    = true
    castDuration = duration or 5
    self:ResetFrostBG()

    if currentFX and currentFX.Reset then
        currentFX.Reset()
    end

    local schoolKey = SCB.Bar.currentSchoolKey or "neutral"
    local sub
    sub, currentFX = self:EnsureFX(schoolKey)
    if currentFX and self.fxDirty then self.fxDirty[schoolKey] = true end

    -- Draw ONLY the active school's particle sub-frame.
    if self.fxFrames then
        for _, other in pairs(self.fxFrames) do
            if other ~= sub then other:Hide() end
        end
    end
    if sub then sub:Show() end

    if currentFX and currentFX.Start then
        currentFX.Start(castDuration)
    end
end

function SCB.Particles:Stop(success)
    isRunning = false
    self:ResetFrostBG()
    -- Do not reset the Frostfire layers here: the frost overlay keeps its
    -- width and alpha while the bar fades, and Frostfire's UpdateFade hides
    -- it when its linger time ends.

    if currentFX and currentFX.Stop then
        currentFX.Stop(success)
    end
end

-- Called once the fade-out has finished: reset every FX that ran since
-- its last reset (normally just the current style).
function SCB.Particles:ResetAll()
    local dirty = self.fxDirty
    if dirty then
        for key in pairs(dirty) do
            local fx = SCB.FX and SCB.FX[key]
            if fx and fx.Reset then fx.Reset() end
            dirty[key] = nil
        end
    end
    self:ResetFrostBG()
    self:ResetFrostfireLayers()
    -- Hide every school's particle sub-frame once the cast is fully done.
    if self.fxFrames then
        for _, sub in pairs(self.fxFrames) do sub:Hide() end
    end
end

-- ============================================================
--  UPDATE
-- ============================================================

-- Called every tick while the bar fades out.
function SCB.Particles:UpdateCirclesFade(dt)
    if currentFX then
        if currentFX.UpdateCirclesFade then currentFX.UpdateCirclesFade(dt) end
        if currentFX.UpdateFade        then currentFX.UpdateFade(dt) end
    end
end

function SCB.Particles:Update(dt, progress)
    local schoolKey = SCB.Bar.currentSchoolKey
    -- Other styles never show these layers (ApplySchool and ResetAll hide them).
    if schoolKey == "frost" then self:UpdateFrostBG(schoolKey, progress) end
    if schoolKey == "frostfire" then self:UpdateFrostfireLayers(schoolKey, progress) end

    if not currentFX then return end

    local cx, cy, barW, barH = GetBarDimensions()
    if not cx then return end

    -- Fill region in screen coordinates (style margins applied), and the
    -- x of the fill's leading edge.
    local school = SCB.Bar.currentSchool
    local mL = (school and school.fillMarginL or 0) * barW + (school and school.fillMarginLPx or 0)
    local mR = (school and school.fillMarginR or 0) * barW + (school and school.fillMarginRPx or 0)
    local fillW   = barW - mL - mR
    local fillLX  = cx - barW * 0.5 + mL
    -- Emission gate: elapsed time, not fill (they differ on emptying bars).
    local emptying = SCB.Bar.fillEmptying
    SCB.Particles.emitProgress = emptying and (1 - progress) or progress

    -- An emptying bar keeps the full cast feather, so its visible edge sits
    -- inside the mask, at the middle of the soft ramp, not at the mask's
    -- end; put the front there so particles ride the edge the player sees.
    -- Filling bars keep the mask end (their feather narrows to it).
    local edgeProgress = progress
    if emptying then edgeProgress = progress * (SCB.REVEAL_FEATHER_MID or 1) end
    local frontProgress = edgeProgress
    if school and school.reverseDir then
        frontProgress = 1 - edgeProgress
    end
    local frontX = fillLX + fillW * frontProgress

    -- splitFill (Aim): the right half may use its own margins, so pass its
    -- region too and let the FX module derive both tip positions.
    local fillLXRight, fillWRight
    if school and school.splitFill then
        local mLR = (school.fillMarginLRight or (school.fillMarginL or 0)) * barW
                  + (school.fillMarginLRightPx or 0)
        local mRR = (school.fillMarginRRight or (school.fillMarginR or 0)) * barW
                  + (school.fillMarginRRightPx or 0)
        fillWRight  = barW - mLR - mRR
        fillLXRight = cx - barW * 0.5 + mLR
    end

    currentFX.Update(dt, progress, frontX, cy, barW, barH, fillLX, fillW, fillLXRight, fillWRight)
end