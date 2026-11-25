-- ============================================================
--  Opulent Casting Bars -- Bar.lua
--  Bar frame construction, cast start/stop, the throttled
--  per-frame tick and the text layout.
-- ============================================================

SCB.Bar = {}

local UPDATE_RATE = 0.016  -- minimum seconds between ticks (~60 per second)

-- Shorten a spell name to 30 characters ("..." included) when the option is
-- on. Counts UTF-8 characters, not bytes, so a cut never splits a
-- multi-byte character (Korean / Chinese / accented names).
local function TruncateSpellName(text)
    if type(text) ~= "string" then return "" end
    if not (SCB and SCB.Config and SCB.Config.Get and SCB.Config:Get("textNameTruncate")) then
        return text
    end
    local maxChars = 30
    if #text <= maxChars then return text end   -- fewer bytes => fewer chars
    local chars, cut = 0, #text
    for pos = 1, #text do
        local b = string.byte(text, pos)
        if b < 128 or b >= 192 then             -- first byte of a character
            chars = chars + 1
            if chars == maxChars - 2 then cut = pos - 1 end
        end
    end
    if chars <= maxChars then return text end
    return text:sub(1, cut) .. "..."
end

local function Clamp01(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

-- A style's fillPlainOffsetX (px on a 400 px wide bar) at the current
-- width: the fill art stretches with the bar, so its shift does too.
local function FillPlainShift(school)
    local px = school and school.fillPlainOffsetX
    if not px or px == 0 then return 0 end
    local barW = tonumber(SCB.Config:Get("barWidth")) or 400
    return px * barW / 400
end

-- Bar size in px: configured (or given) size times the style's barScale.
local function ResolveBarDimensions(school, rawW, rawH)
    local cfg = SCB.Config
    local defaultW = (cfg.defaults and cfg.defaults.barWidth) or 400
    local defaultH = (cfg.defaults and cfg.defaults.barHeight) or 200
    local configuredW = tonumber(rawW) or tonumber(cfg:Get("barWidth")) or defaultW
    local configuredH = tonumber(rawH) or tonumber(cfg:Get("barHeight")) or defaultH
    local barScale = tonumber(school and school.barScale) or 1

    return math.floor(configuredW * barScale + 0.5),
           math.floor(configuredH * barScale + 0.5)
end

-- ============================================================
--  CREATION
-- ============================================================

-- Frame levels inside the bar (higher draws on top):
--   0 bgUnderlayHost  FX backgrounds drawn under the bar BG
--   1 bgLight hosts   BG glow layers
--   2 fill hosts      texFill / texFillPlain / Aim right fill
--   3 overlayHost     frame border, fill-ending flash
--   4 decoHost        decorations above the border, school contour
--   5 textHost        spell name and timer
--   f+8 / f+10       frame-light clip / particle container
function SCB.Bar:Create()
    local cfg = SCB.Config
    local w   = cfg:Get("barWidth")
    local h   = cfg:Get("barHeight")

    -- ---- Wrapper (self.frame): position, scale, alpha, drag --------
    -- Fades act on the wrapper; the inner frame f stays shown so its
    -- OnUpdate keeps ticking during the fade-out.
    local wrapper = CreateFrame("Frame", "OpulentCastingBarsWrapper", UIParent)
    wrapper:SetSize(w, h)
    wrapper:SetFrameStrata(SCB.Config:Get("barStrata") or "MEDIUM")
    wrapper:SetMovable(true)
    wrapper:SetClampedToScreen(true)
    wrapper:EnableMouse(false)
    -- Let clicks pass through to the world (targeting etc.) while still
    -- allowing a drag when the bar is unlocked.
    wrapper:SetPropagateMouseClicks(true)  -- ClassicAPI
    -- The position is saved in our own settings; keep the client from also
    -- writing this named, movable frame to layout-cache.txt.
    wrapper:SetDontSavePosition(true)      -- ClassicAPI
    wrapper:Hide()

    wrapper:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" and not SCB.Config:Get("locked") then
            wrapper.isMoving = true
            wrapper:StartMoving()
        end
    end)
    wrapper:SetScript("OnMouseUp", function()
        if not wrapper.isMoving then return end
        wrapper.isMoving = nil
        wrapper:StopMovingOrSizing()
        -- 1.12 re-anchors a moved frame to the screen's top-left corner.
        -- Save it as an offset from the screen centre instead: the form
        -- the Position X/Y sliders use, and what login restores.
        local cx, cy = wrapper:GetCenter()
        local px, py = UIParent:GetCenter()
        if not (cx and px) then return end
        local s = UIParent:GetEffectiveScale() / wrapper:GetEffectiveScale()
        local x = math.floor((cx - px * s) + 0.5)
        local y = math.floor((cy - py * s) + 0.5)
        wrapper:ClearAllPoints()
        wrapper:SetPoint("CENTER", UIParent, "CENTER", x, y)
        SCB.Config:Set("anchor", "CENTER")
        SCB.Config:Set("x", x)
        SCB.Config:Set("y", y)
        if SCB.Options and SCB.Options.created then
            SCB.UI.NotifyUpdate("OCB_X")
            SCB.UI.NotifyUpdate("OCB_Y")
        end
    end)

    -- ---- Inner frame (self.frameInner): hosts every layer and the tick ----
    local f = CreateFrame("Frame", "OpulentCastingBarsFrame", wrapper)
    f:SetAllPoints(wrapper)
    f:SetFrameStrata(SCB.Config:Get("barStrata") or "MEDIUM")

    -- ---- bgUnderlayHost: FX background textures that must render BELOW
    -- the bar's own background (frame level 0 < f's level 1).
    local bgUnderlayHost = CreateFrame("Frame", nil, wrapper)
    bgUnderlayHost:SetAllPoints(f)
    bgUnderlayHost:SetFrameLevel(0)

    -- ---- Background glow (school.bgLight) ----------------------------
    -- The glow spans the bar and bgLightFullMask reveals it left to right
    -- with the cast (plain reveal, or the padded artwork reveal for
    -- bgLightArtworkReveal styles).
    local bgLightFullHost = CreateFrame("Frame", nil, f)
    bgLightFullHost:SetPoint("TOPLEFT",    f, "TOPLEFT",    0, 0)
    bgLightFullHost:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    bgLightFullHost:SetWidth(w)
    bgLightFullHost:SetFrameLevel(1)
    bgLightFullHost:Hide()
    local texBGLightFull = bgLightFullHost:CreateTexture(nil, "ARTWORK")
    texBGLightFull:SetAllPoints(bgLightFullHost)
    texBGLightFull:SetAlpha(0)
    texBGLightFull:SetBlendMode("ADD")
    local bgLightFullMask = SCB.NewRevealMask(f)
    bgLightFullMask:SetPoint("TOPLEFT",    bgLightFullHost, "TOPLEFT")
    bgLightFullMask:SetPoint("BOTTOMLEFT", bgLightFullHost, "BOTTOMLEFT")
    bgLightFullMask:SetWidth(1)
    SCB.AttachMask(texBGLightFull, bgLightFullMask)

    -- ---- Bar background -----------------------------------------------
    local texBG = f:CreateTexture(nil, "BACKGROUND")
    texBG:SetAllPoints(f)

    -- ---- Background flash (end-of-cast flash of emptying bars) ----------
    -- Channels and reverse fills end with an empty fill, so their completion
    -- flash lights up the background instead of the fill (see Animations.lua).
    -- Two additive layers, above texBG (BORDER > BACKGROUND on the same
    -- frame) and below the fill hosts, both shaped like the background:
    --   texFlashBG      a copy of the background artwork (keeps its detail);
    --   texFlashBGGlow  a solid color clipped to the background's alpha by
    --                   flashBGMask, so dark backgrounds (Metal, Shadow, ...)
    --                   light up visibly too.
    -- Textures are set by ApplySchool; hidden while idle.
    local texFlashBG = f:CreateTexture(nil, "BORDER", nil, 0)
    texFlashBG:SetAllPoints(f)
    texFlashBG:SetBlendMode("ADD")
    texFlashBG:SetAlpha(0)
    texFlashBG:Hide()
    local texFlashBGGlow = f:CreateTexture(nil, "BORDER", nil, 1)
    texFlashBGGlow:SetAllPoints(f)
    texFlashBGGlow:SetColorTexture(1, 1, 1, 1)  -- ClassicAPI
    texFlashBGGlow:SetBlendMode("ADD")
    texFlashBGGlow:SetAlpha(0)
    texFlashBGGlow:Hide()
    local flashBGMask = f:CreateMaskTexture()
    flashBGMask:SetAllPoints(f)
    SCB.AttachMask(texFlashBGGlow, flashBGMask)

    -- ---- Fill, revealed left to right by texMask -----------------------
    -- texFill (fillMask styles, whose fill is drawn by their FX module, keep
    -- it at alpha 0) and texFillPlain (every other style) span the bar at
    -- their natural size; texMask, a reveal mask, clips them to the part
    -- of the fill region that the cast has reached.
    local fillHost = CreateFrame("Frame", nil, f)
    fillHost:SetAllPoints(f)
    fillHost:SetFrameLevel(2)  -- above BG (1), below frame border (3) and text (5)

    local texFill = fillHost:CreateTexture(nil, "ARTWORK")
    texFill:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    texFill:SetWidth(w) ; texFill:SetHeight(h)

    -- Plain fill, which also supports the style's fillPlainOffsetX shift.
    local fillPlainHost = CreateFrame("Frame", nil, f)
    fillPlainHost:SetAllPoints(f)
    fillPlainHost:SetFrameLevel(2)
    fillPlainHost:Hide()
    local texFillPlain = fillPlainHost:CreateTexture(nil, "ARTWORK")
    texFillPlain:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    texFillPlain:SetWidth(w) ; texFillPlain:SetHeight(h)
    -- Fill art that the frame hides at full opacity is transparent in the
    -- fill textures themselves, so it cannot show through the frame while
    -- the bar fades: the plain fill is always one quad. (fillStrips keeps
    -- the list form other code iterates.)
    local fillStrips = { texFillPlain }
    -- Additive copy of the fill for the end-of-cast flash of bars that end
    -- full, shared by every style (see Animations.lua). It has its own mask
    -- covering the whole fill region. Bars that end empty (channels, reverse
    -- fills) flash the background instead (texFlashBG). Laid out by
    -- LayoutFlash; hidden while idle. OVERLAY layer: above the fill, below
    -- the frame border (higher frame level).
    local texFlash = fillPlainHost:CreateTexture(nil, "OVERLAY")
    texFlash:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    texFlash:SetWidth(w) ; texFlash:SetHeight(h)
    texFlash:SetBlendMode("ADD")
    texFlash:SetAlpha(0)
    texFlash:Hide()
    local flashMask = SCB.NewRevealMask(f)
    SCB.SetRevealMaskFixed(flashMask)
    SCB.SetRevealMaskProgress(flashMask, 1)   -- no feather: full region
    SCB.AttachMask(texFlash, flashMask)
    local _useTexCoordFill = false   -- true = texFillPlain is the visible fill

    -- Fill / mask geometry, applied by LayoutFill()
    local _fillRev  = false   -- true = fill grows right to left (reverseDir)
    local _fillBarH = 40
    local _fillW    = 1   -- full bar width (barW)
    local _fillAncX = 0   -- left margin in pixels (offsetL)
    local _fillOffY = 0   -- vertical offset from top of f
    local _fillPlainOffsetX = 0
    local _maskW    = 1   -- revealed width in px

    local texMask = SCB.NewRevealMask(f)

    -- Lay out the plain fill at (x, -y) from f's top left, fw x hh px.
    local function LayoutFillPlain(x, y, fw, hh)
        texFillPlain:ClearAllPoints()
        texFillPlain:SetTexCoord(0, 1, 0, 1)
        texFillPlain:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
        texFillPlain:SetWidth(fw) ; texFillPlain:SetHeight(hh)
        texFillPlain:Show()
    end

    -- Keep the real mask methods; the instance overrides below replace them.
    local MaskBase = {
        ClearAllPoints = texMask.ClearAllPoints,
        SetPoint       = texMask.SetPoint,
        SetWidth       = texMask.SetWidth,
        SetHeight      = texMask.SetHeight,
    }

    local function LayoutFill()
        local hh = math.max(1, _fillBarH)
        local fw = math.max(1, _fillW)
        local shift = _useTexCoordFill and _fillPlainOffsetX or 0
        texFill:ClearAllPoints()
        if _fillRev then
            texFill:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -_fillOffY)
        else
            texFill:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -_fillOffY)
        end
        texFill:SetWidth(fw) ; texFill:SetHeight(hh)
        LayoutFillPlain(_fillPlainOffsetX, _fillOffY, fw, hh)
        MaskBase.ClearAllPoints(texMask)
        if _fillRev then
            MaskBase.SetPoint(texMask, "TOPRIGHT", f, "TOPRIGHT", -_fillAncX, -_fillOffY)
        else
            MaskBase.SetPoint(texMask, "TOPLEFT",  f, "TOPLEFT",  _fillAncX + shift, -_fillOffY)
        end
        MaskBase.SetWidth(texMask, _maskW)
        MaskBase.SetHeight(texMask, hh)
    end

    -- Instance overrides give texMask a small layout API (SetWidth = revealed
    -- px, SetPoint = anchor side + margin, SetBarH / SetFillW / SetOffY,
    -- SetUseTexCoord, Show / Hide) while it stays a real mask, so any
    -- texture can still use SCB.AttachMask(t, SCB.Bar.texMask).
    texMask.SetWidth = function(self, mw)
        _maskW = math.max(1, mw or 1)
        MaskBase.SetWidth(texMask, _maskW)
    end
    texMask.ClearAllPoints = function() end
    texMask.SetPoint = function(self, point, _, relPoint, x, y)
        if point == "TOPLEFT" then
            _fillRev, _fillAncX = false, x or 0
            LayoutFill()
        elseif point == "TOPRIGHT" then
            _fillRev, _fillAncX = true, x or 0
            LayoutFill()
        end
    end
    texMask.SetUseTexCoord = function(self, enabled, fullW, offsetX)
        _useTexCoordFill  = enabled and true or false
        _fillPlainOffsetX = offsetX or 0
        if enabled then
            fillHost:Hide()
            fillPlainHost:Show()
        else
            fillPlainHost:Hide()
            fillHost:Show()
        end
        LayoutFill()
    end
    texMask.Hide     = function() fillHost:Hide() end
    texMask.Show     = function() fillHost:Show() end
    texMask.SetBarH  = function(self, bh) if bh ~= _fillBarH then _fillBarH = bh ; LayoutFill() end end
    texMask.SetFillW = function(self, fw) if fw ~= _fillW    then _fillW    = fw ; LayoutFill() end end
    texMask.SetOffY  = function(self, oy) if oy ~= _fillOffY then _fillOffY = oy ; LayoutFill() end end
    texMask.Relayout = function() LayoutFill() end
    -- Current reveal rectangle of the fill: right-anchored?, x offset from
    -- that side, y offset from the top, revealed width, height (px). Read by
    -- LayoutFlash to flash exactly the revealed part of a cancelled cast.
    texMask.GetRevealLayout = function()
        local shift = _useTexCoordFill and _fillPlainOffsetX or 0
        local x = _fillRev and _fillAncX or (_fillAncX + shift)
        return _fillRev, x, _fillOffY, _maskW, math.max(1, _fillBarH)
    end
    LayoutFill()
    SCB.AttachMask(texFill, texMask)
    SCB.AttachMask(texFillPlain, texMask)

    -- ---- overlayHost: frame border and overlays, above the fill ----
    local overlayHost = CreateFrame("Frame", nil, f)
    overlayHost:SetAllPoints(f)
    overlayHost:SetFrameLevel(3)  -- above fillHost (2), below decoHost (4)

    -- ---- decoHost: decoration textures above the frame border (e.g. Shadow voids). ----
    local decoHost = CreateFrame("Frame", nil, f)
    decoHost:SetAllPoints(f)
    decoHost:SetFrameLevel(4)

    -- ---- Frame border ---------------------------------------------------
    local texFrame = overlayHost:CreateTexture(nil, "OVERLAY")
    texFrame:SetAllPoints(overlayHost)

    -- Frame light (school.frameLight): full-size artwork revealed with the
    -- cast by frameLightMask; fades out with the bar.
    local frameLightClip = CreateFrame("Frame", nil, f)
    frameLightClip:SetAllPoints(f)
    frameLightClip:SetFrameLevel((f:GetFrameLevel() or 0) + 8)
    local frameLightMask = SCB.NewRevealMask(f)
    frameLightMask:SetPoint("TOPLEFT",    frameLightClip, "TOPLEFT")
    frameLightMask:SetPoint("BOTTOMLEFT", frameLightClip, "BOTTOMLEFT")
    frameLightMask:SetWidth(1)
    local texFrameLightClip = frameLightClip:CreateTexture(nil, "ARTWORK")
    texFrameLightClip:SetAllPoints(frameLightClip)
    texFrameLightClip:SetAlpha(0)
    texFrameLightClip:SetBlendMode("ADD")
    SCB.AttachMask(texFrameLightClip, frameLightMask)
    -- Optional additive second pass (school.frameLightAdd, e.g. Sacred/Paladin)
    local texFrameLightAdd = frameLightClip:CreateTexture(nil, "OVERLAY")
    texFrameLightAdd:SetAllPoints(frameLightClip)
    texFrameLightAdd:SetAlpha(0)
    texFrameLightAdd:SetBlendMode("ADD")
    SCB.AttachMask(texFrameLightAdd, frameLightMask)
    texFrameLightAdd:Hide()
    frameLightClip:Hide()

    -- ---- Static school contour (school.contour), on top of the border ----
    local texContour = decoHost:CreateTexture(nil, "OVERLAY", nil, 1)
    texContour:SetAllPoints(decoHost)

    -- ---- Spell name -------------------------------------------------------
    -- textHost is parented to the wrapper so text is never clipped by f;
    -- the font strings are still anchored to f. Position, font and color
    -- are (re)applied by ApplyTextPrefs.
    local textHost = CreateFrame("Frame", nil, wrapper)
    textHost:SetAllPoints(f)
    textHost:SetFrameLevel(5)  -- above the bar layers

    local spellNameFS = textHost:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    spellNameFS:SetPoint("LEFT", f, "LEFT", 66, 6)
    spellNameFS:SetJustifyH("LEFT")
    spellNameFS:SetTextColor(1, 1, 1, 1)
    spellNameFS:SetShadowOffset(1, -1)
    spellNameFS:SetFont(spellNameFS:GetFont(), 11)

    -- ---- Timer ----------------------------------------------------------
    local castTimerFS = textHost:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    castTimerFS:SetPoint("RIGHT", f, "RIGHT", -60, 6)
    castTimerFS:SetJustifyH("RIGHT")
    castTimerFS:SetTextColor(1, 1, 1, 0.9)
    castTimerFS:SetShadowOffset(1, -1)
    castTimerFS:SetFont(castTimerFS:GetFont(), 11)

    -- ---- Extra layers for styles with school.bgRed (Fire); hidden otherwise ----
    -- Red background, revealed with the cast by its own mask.
    local texBGRed = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    texBGRed:SetAllPoints(f)
    texBGRed:SetAlpha(0)
    local maskBGRed = SCB.NewRevealMask(f)
    maskBGRed:SetPoint("TOPLEFT",    f, "TOPLEFT")
    maskBGRed:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
    maskBGRed:SetWidth(1)
    SCB.AttachMask(texBGRed, maskBGRed)

    -- Red frame, revealed with the cast above the normal frame.
    local texFrameRed = f:CreateTexture(nil, "OVERLAY", nil, 1)
    texFrameRed:SetAllPoints(f)
    texFrameRed:SetAlpha(0)
    texFrameRed:SetBlendMode("BLEND")
    local maskFrameRed = SCB.NewRevealMask(f)
    maskFrameRed:SetPoint("TOPLEFT",    f, "TOPLEFT")
    maskFrameRed:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
    maskFrameRed:SetWidth(1)
    SCB.AttachMask(texFrameRed, maskFrameRed)

    -- 6 fill effect frames above the fill, cycled by the FX module.
    local texFillEffects = {}
    for i = 1, 6 do
        local t = f:CreateTexture(nil, "ARTWORK", nil, 1)
        t:SetAllPoints(f)
        t:SetAlpha(0)
        t:SetBlendMode("BLEND")
        texFillEffects[i] = t
    end

    -- 6 animated contour frames on top, replacing texContour (Fire, Shadow).
    local texContoursFire = {}
    for i = 1, 6 do
        local t = f:CreateTexture(nil, "OVERLAY", nil, 2)
        t:SetAllPoints(f)
        t:SetAlpha(0)
        t:SetBlendMode("BLEND")
        texContoursFire[i] = t
    end

    -- ---- Frostfire frost overlay ("givre") -----------------------------
    -- Revealed with the cast by its own mask, so it can fade out on its own
    -- after the cast. Lives above overlayHost so it covers the fire effects.
    local givreHost = CreateFrame("Frame", nil, overlayHost)
    givreHost:SetPoint("TOPLEFT",    f, "TOPLEFT",    0, 0)
    givreHost:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    givreHost:SetWidth(w)
    -- Must be strictly above overlayHost (which holds the frame): with equal
    -- levels, 1.12's sibling draw order is undefined and varies per login.
    givreHost:SetFrameLevel(overlayHost:GetFrameLevel() + 1)
    givreHost:Hide()

    local texGivreFrostfire = givreHost:CreateTexture(nil, "OVERLAY", nil, 2)
    texGivreFrostfire:SetAllPoints(givreHost)
    texGivreFrostfire:SetAlpha(1)

    local maskGivreFrostfire = SCB.NewRevealMask(f)
    maskGivreFrostfire:SetPoint("TOPLEFT",    givreHost, "TOPLEFT")
    maskGivreFrostfire:SetPoint("BOTTOMLEFT", givreHost, "BOTTOMLEFT")
    maskGivreFrostfire:SetWidth(1)
    SCB.AttachMask(texGivreFrostfire, maskGivreFrostfire)

    -- 5 Frostfire flame frames, clipped by texMask.
    local texFillEffectsFrostfire = {}
    for i = 1, 5 do
        local t = f:CreateTexture(nil, "ARTWORK", nil, 1)
        t:SetAllPoints(f)
        t:SetAlpha(0)
        texFillEffectsFrostfire[i] = t
    end

    -- ---- Bronze sand (school.sable) ----------------------------------
    -- The artwork is a full-bar texture with a small opaque area, so it is
    -- sized from the current bar. LayoutSable moves it down as the cast
    -- progresses.
    local sableFrame = CreateFrame("Frame", nil, f)
    sableFrame:SetSize(w, h)
    sableFrame:SetPoint("CENTER", f, "CENTER", 0, 0)
    sableFrame:SetFrameLevel(f:GetFrameLevel())
    sableFrame:Hide()
    local texSabre = sableFrame:CreateTexture(nil, "BACKGROUND", nil, -2)
    texSabre:SetAllPoints(sableFrame)
    texSabre:SetAlpha(0)
    texSabre:SetBlendMode("BLEND")
    texSabre:Hide()

    -- ---- Aim (splitFill): two fills that meet in the middle ----------
    -- The left half is texFillPlain, revealed by texMask. The right half is
    -- texFillRight, anchored by its right edge and revealed right to left
    -- by maskFillRight, which grows from the right edge of the fill region
    -- toward the center.
    local fillRightHost = CreateFrame("Frame", nil, f)
    fillRightHost:SetAllPoints(f)
    fillRightHost:SetFrameLevel(2)
    fillRightHost:Hide()

    local texFillRight = fillRightHost:CreateTexture(nil, "ARTWORK")
    texFillRight:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    texFillRight:SetWidth(w) ; texFillRight:SetHeight(h)

    local _fillRightBarH = 40
    local _fillRightW    = 1
    local _fillRightOffY = 0
    local _fillRightAnchorFrame = f
    local _fillRightAnchorX     = 0   -- offset from TOPRIGHT of anchor frame
    local _fillRightMaskW       = 1

    local maskFillRight = SCB.NewRevealMask(f)
    -- Grows right to left: mirror the mask so the feather is on its leading
    -- (left) edge and the hard border on its starting (right) edge.
    SCB.SetRevealMaskMirrored(maskFillRight, true)
    local RMaskBase = {
        ClearAllPoints = maskFillRight.ClearAllPoints,
        SetPoint       = maskFillRight.SetPoint,
        SetWidth       = maskFillRight.SetWidth,
        SetHeight      = maskFillRight.SetHeight,
    }

    local function LayoutFillRight()
        local fh = math.max(1, _fillRightBarH)
        texFillRight:ClearAllPoints()
        texFillRight:SetPoint("TOPRIGHT", _fillRightAnchorFrame, "TOPRIGHT", 0, -_fillRightOffY)
        texFillRight:SetWidth(math.max(1, _fillRightW)) ; texFillRight:SetHeight(fh)
        RMaskBase.ClearAllPoints(maskFillRight)
        RMaskBase.SetPoint(maskFillRight, "TOPRIGHT", _fillRightAnchorFrame, "TOPRIGHT",
            _fillRightAnchorX, -_fillRightOffY)
        RMaskBase.SetWidth(maskFillRight, _fillRightMaskW)
        RMaskBase.SetHeight(maskFillRight, fh)
    end

    -- Same kind of layout API as texMask (see above).
    maskFillRight.SetWidth = function(self, mw)
        _fillRightMaskW = math.max(1, mw or 1)
        RMaskBase.SetWidth(maskFillRight, _fillRightMaskW)
    end
    maskFillRight.ClearAllPoints = function() end
    maskFillRight.SetPoint = function(self, point, relFrame, relPoint, x, y)
        _fillRightAnchorFrame = relFrame or f
        _fillRightAnchorX     = tonumber(x) or 0
        LayoutFillRight()
    end
    maskFillRight.SetFillW = function(self, fw) if fw ~= _fillRightW    then _fillRightW    = fw ; LayoutFillRight() end end
    maskFillRight.SetFillH = function(self, fh) if fh ~= _fillRightBarH then _fillRightBarH = fh ; LayoutFillRight() end end
    maskFillRight.SetOffY  = function(self, oy) if oy ~= _fillRightOffY then _fillRightOffY = oy ; LayoutFillRight() end end
    maskFillRight.Hide = function() fillRightHost:Hide() end
    maskFillRight.Show = function() fillRightHost:Show() end
    LayoutFillRight()
    SCB.AttachMask(texFillRight, maskFillRight)

    -- Right-half flash copy for splitFill (Aim), same idea as texFlash.
    local texFlashRight = fillRightHost:CreateTexture(nil, "OVERLAY")
    texFlashRight:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    texFlashRight:SetWidth(w) ; texFlashRight:SetHeight(h)
    texFlashRight:SetBlendMode("ADD")
    texFlashRight:SetAlpha(0)
    texFlashRight:Hide()
    local flashMaskRight = SCB.NewRevealMask(f)
    SCB.SetRevealMaskMirrored(flashMaskRight, true)
    SCB.SetRevealMaskFixed(flashMaskRight)
    SCB.SetRevealMaskProgress(flashMaskRight, 1)
    SCB.AttachMask(texFlashRight, flashMaskRight)

    -- Aim end-of-cast flash (pulses from 97% progress). On overlayHost so
    -- it renders above both fill hosts.
    local texFillEnding = overlayHost:CreateTexture(nil, "ARTWORK", nil, 2)
    texFillEnding:SetAllPoints(f)
    texFillEnding:SetAlpha(0)
    texFillEnding:SetBlendMode("ADD")

    -- ---- Aim orb portrait --------------------------------------------
    -- 2D portrait (SetPortraitTexture) of the cast's likely target. At frame
    -- level 1, so the opaque ring of the Aim frame (level 3) hides its edges.
    -- No mask: in 1.12 a mask tints the portrait.
    local orbPortraitFrame = CreateFrame("Frame", nil, f)
    orbPortraitFrame:SetFrameLevel(1)
    orbPortraitFrame:SetSize(36, 36)
    orbPortraitFrame:SetPoint("CENTER", f, "TOPLEFT", w * 0.503, -(h * 0.236))
    orbPortraitFrame:Hide()

    local orbPortrait = orbPortraitFrame:CreateTexture(nil, "ARTWORK")
    orbPortrait:SetAllPoints(orbPortraitFrame)

    local function OrbLoadTarget()
        -- Best guess at the spell's target: target, else mouseover, else self.
        local unit
        if UnitExists("target") then
            unit = "target"
        elseif UnitExists("mouseover") then
            unit = "mouseover"
        else
            unit = "player"
        end
        SetPortraitTexture(orbPortrait, unit)
        orbPortraitFrame:Show()
    end

    local particleContainer = CreateFrame("Frame", "SCBParticleContainer", f)
    particleContainer:SetPoint("CENTER", f, "CENTER")
    particleContainer:SetSize(w + 120, h + 120)
    particleContainer:SetFrameLevel(f:GetFrameLevel() + 10)

    -- ---- Throttled tick --------------------------------------------------
    -- Runs while the bar is shown; _Tick receives the time accumulated since
    -- the last tick. _accum lives on self so StartCast can reset it.
    self._accum = 0
    f:SetScript("OnUpdate", function(_, dt)
        self._accum = self._accum + dt
        if self._accum < UPDATE_RATE then return end
        SCB.Bar:_Tick(self._accum)
        self._accum = 0
    end)

    -- ---- References ------------------------------------------------------
    self.frame             = wrapper   -- position / scale / alpha / show-hide
    self.frameInner        = f         -- layout reference for every layer
    self.bgUnderlayHost    = bgUnderlayHost
    self.decoHost          = decoHost
    self.overlayHost       = overlayHost
    self.bgLightFullHost    = bgLightFullHost
    self.texBGLightFull     = texBGLightFull
    self.bgLightFullMask    = bgLightFullMask
    self.frameLightMask     = frameLightMask
    self.fillHost           = fillHost
    self.fillRightHost      = fillRightHost
    self.texBG             = texBG
    self.texFlashBG        = texFlashBG
    self.texFlashBGGlow    = texFlashBGGlow
    self.flashBGMask       = flashBGMask
    self.texFill           = texFill
    self.fillPlainHost     = fillPlainHost
    self.texFillPlain      = texFillPlain
    self.fillStrips        = fillStrips
    self.texFlash          = texFlash
    self.flashMask         = flashMask
    self.texMask           = texMask
    self.texFrame          = texFrame
    self.frameLightClip    = frameLightClip
    self.texFrameLightClip = texFrameLightClip
    self.texFrameLightAdd  = texFrameLightAdd
    self.texContour        = texContour
    self.textHost          = textHost
    self.spellNameText     = spellNameFS
    self.castTimerText     = castTimerFS
    self.particleContainer = particleContainer

    self.texBGRed        = texBGRed
    self.maskBGRed       = maskBGRed
    self.texFrameRed     = texFrameRed
    self.maskFrameRed    = maskFrameRed
    self.texFillEffects  = texFillEffects
    self.texContoursFire = texContoursFire

    self.givreHost                = givreHost
    self.texGivreFrostfire        = texGivreFrostfire
    self.maskGivreFrostfire       = maskGivreFrostfire
    self.texFillEffectsFrostfire  = texFillEffectsFrostfire
    self.texSabre                 = texSabre
    self.sableFrame               = sableFrame

    self.orbPortraitFrame = orbPortraitFrame
    self.OrbLoadTarget    = OrbLoadTarget
    self.texFillRight   = texFillRight
    self.maskFillRight  = maskFillRight
    self.texFlashRight  = texFlashRight
    self.flashMaskRight = flashMaskRight
    self.texFillEnding  = texFillEnding

    -- Layers that follow the fill progress share texMask. (The Frostfire
    -- frost overlay has its own mask so it can fade out independently.)
    for _, t in ipairs(texFillEffects) do
        SCB.AttachMask(t, texMask)
    end
    for _, t in ipairs(texFillEffectsFrostfire) do
        SCB.AttachMask(t, texMask)
    end

    -- State
    self.isActive   = false   -- a cast is running
    self.isFading   = false   -- end-of-cast animation running; blocks StopCast
    self.castStart  = 0
    self.castEnd    = 0
    self.currentSchool = nil

    -- Start from a clean animation state, before any FX touches the bar.
    if SCB.Animations and SCB.Animations.Reset then
        SCB.Animations:Reset()
    end

    -- Needs the bar frames created above.
    SCB.Particles:Init()
end

-- How far (px) the sand drops over a full cast, scaled with bar height.
function SCB.Bar:GetSableDrop()
    local school = self.currentSchool
    local baseDrop = (school and school.sableDropPx) or 23
    local h = SCB.Config:Get("barHeight") or 200
    local defaultH = (SCB.Config.defaults and SCB.Config.defaults.barHeight) or 200
    if not defaultH or defaultH <= 0 then defaultH = 200 end
    return baseDrop * (h / defaultH)
end

-- Place the sand for `progress`; anchors are only rebuilt on change.
function SCB.Bar:LayoutSable(progress, force)
    if not (self.sableFrame and self.texSabre and self.frameInner) then return end

    local w = SCB.Config:Get("barWidth") or 400
    local h = SCB.Config:Get("barHeight") or 200
    if not w or w <= 0 or not h or h <= 0 then return end

    local drop = self:GetSableDrop()
    local y = -drop * Clamp01(progress)

    -- The size only changes with the bar; during a cast only y moves (the
    -- single CENTER anchor is replaced in place, no ClearAllPoints needed).
    if force or self._sabreLayoutW ~= w or self._sabreLayoutH ~= h then
        self.sableFrame:SetSize(w, h)
        self.sableFrame:ClearAllPoints()
        self.sableFrame:SetPoint("CENTER", self.frameInner, "CENTER", 0, y)
        self._sabreLayoutW = w
        self._sabreLayoutH = h
        self._sabreLayoutY = y
    elseif self._sabreLayoutY ~= y then
        self.sableFrame:SetPoint("CENTER", self.frameInner, "CENTER", 0, y)
        self._sabreLayoutY = y
    end
end

-- Sand progress (0..1) from its own timeline (re-based on pushback).
function SCB.Bar:GetSableProgress()
    local now = GetTime()
    local startTime = self._sabreStartTime or now
    local endTime = self._sabreEndTime or self.castEnd or now
    return Clamp01((now - startTime) / math.max(endTime - startTime, 0.001))
end

function SCB.Bar:ResetSable()
    self._sabreActive = false
    self._sabreStartTime = nil
    self._sabreEndTime = nil
    self._sabreLayoutW = nil
    self._sabreLayoutH = nil
    self._sabreLayoutY = nil
    self:LayoutSable(0, true)
    if self.texSabre then
        self.texSabre:SetAlpha(0)
        self.texSabre:Hide()
    end
    if self.sableFrame then
        self.sableFrame:Hide()
    end
end

function SCB.Bar:StartSable()
    local school = self.currentSchool
    if not (school and school.sable and self.sableFrame and self.texSabre) then
        self:ResetSable()
        return
    end

    self.texSabre:SetTexture(school.sable)
    self:LayoutSable(0, true)
    self.sableFrame:Show()
    self.texSabre:SetAlpha(1)
    self.texSabre:Show()
    self._sabreActive = true

    local now = GetTime()
    self._sabreStartTime = now
    self._sabreEndTime = self.castEnd or (now + 5)
end

function SCB.Bar:FreezeSableAtProgress(progress)
    if not self._sabreActive then return end
    self:LayoutSable(progress, true)
end

-- Re-base the sand timeline so it continues from `progress` and still
-- ends at _sabreEndTime (used after pushback and resizes).
function SCB.Bar:PlaySableFromProgress(progress)
    if not self._sabreActive then return end
    progress = Clamp01(progress)
    local now = GetTime()
    local endTime = self._sabreEndTime or self.castEnd or now
    if progress < 1 and endTime > now then
        local total = (endTime - now) / math.max(1 - progress, 0.001)
        self._sabreStartTime = now - total * progress
        self._sabreEndTime = endTime
    end
    self:LayoutSable(progress, true)
end

-- Lay out the flash copies for the current style (both halves for
-- splitFill). Mirrors the geometry used by _Tick.
--   partial = false: over the whole fill region (completed cast), unfeathered.
--   partial = true : over exactly the part of the fill that is revealed
--                    right now, with the same soft front (cancelled or
--                    interrupted cast), so only that part flashes.
function SCB.Bar:LayoutFlash(partial)
    local school, f = self.currentSchool, self.frameInner
    if not (school and f and self.texFlash) then return end
    local barW  = SCB.Config:Get("barWidth")  or 400
    local barH  = SCB.Config:Get("barHeight") or 200
    local mL    = barW * (school.fillMarginL or 0) + (school.fillMarginLPx or 0)
    local mR    = barW * (school.fillMarginR or 0) + (school.fillMarginRPx or 0)
    local fillW = math.max(1, barW - mL - mR)
    local fillH = math.max(1, school.fillHeight or barH)
    local offY  = school.fillOffsetY or 0
    local shift = FillPlainShift(school)

    self.texFlash:ClearAllPoints()
    self.texFlash:SetPoint("TOPLEFT", f, "TOPLEFT", shift, -offY)
    self.texFlash:SetWidth(barW) ; self.texFlash:SetHeight(fillH)
    self.flashMask:ClearAllPoints()
    if partial and self.texMask.GetRevealLayout then
        -- Same rectangle and feather as the fill's own reveal mask.
        local rev, x, y, mw, mh = self.texMask.GetRevealLayout()
        if rev then
            self.flashMask:SetPoint("TOPRIGHT", f, "TOPRIGHT", -x, -y)
        else
            self.flashMask:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
        end
        self.flashMask:SetWidth(mw)
        self.flashMask:SetHeight(mh)
        SCB.MatchRevealMask(self.flashMask, self.texMask)
    else
        if school.reverseDir then
            self.flashMask:SetPoint("TOPRIGHT", f, "TOPRIGHT", -mR, -offY)
        else
            self.flashMask:SetPoint("TOPLEFT", f, "TOPLEFT", mL + shift, -offY)
        end
        self.flashMask:SetWidth(school.splitFill and math.max(1, fillW * 0.5) or fillW)
        self.flashMask:SetHeight(fillH)
        -- A previous partial flash may have left a feather on this mask.
        SCB.SetRevealMaskBlendNow(self.flashMask, 1, 1)
    end

    if school.splitFill and self.texFlashRight then
        local mLR = school.fillMarginLRight or (school.fillMarginL or 0)
        local mRR = school.fillMarginRRight or (school.fillMarginR or 0)
        local fillWRight = barW * (1 - mLR - mRR) - (school.fillMarginLRightPx or 0) - (school.fillMarginRRightPx or 0)
        local offsetRRight = barW * mRR + (school.fillMarginRRightPx or 0)
        self.texFlashRight:ClearAllPoints()
        self.texFlashRight:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -offY)
        self.texFlashRight:SetWidth(barW) ; self.texFlashRight:SetHeight(fillH)
        self.flashMaskRight:ClearAllPoints()
        self.flashMaskRight:SetPoint("TOPRIGHT", f, "TOPRIGHT", -offsetRRight, -offY)
        if partial then
            self.flashMaskRight:SetWidth(math.max(1, self._maskRightW or 1))
            SCB.MatchRevealMask(self.flashMaskRight, self.maskFillRight)
        else
            self.flashMaskRight:SetWidth(math.max(1, fillWRight * 0.5))
            SCB.SetRevealMaskBlendNow(self.flashMaskRight, 1, 1)
        end
        self.flashMaskRight:SetHeight(fillH)
    end
end

-- Fraction (0..1) of the fill region that is revealed right now.
function SCB.Bar:GetRevealedFraction()
    return self._lastFillProgress or 0
end

-- ============================================================
--  FADE HELPERS
--  During the end-of-cast fade every layer turns translucent on its
--  own, so art that one layer hides under another shows through. The
--  helpers below remove such hidden art up front, using only the
--  addon's existing textures (texture coordinates and masks).
-- ============================================================

-- Frame light that replaces the frame (school.frameLightMatchesFrame).
-- Mossy Stone's light artwork is its frame artwork with a glow painted
-- along the opening. It is revealed over the fill region only, so after
-- a completed cast the stone there is covered by two layers (frame and
-- light) and by one elsewhere. Opaque, both look the same, but once they
-- fade the doubled part stays denser and a vertical seam appears where
-- the light starts (next to the icon) and ends. While the completion
-- flash plays, the light spreads over the whole bar (s: 0 -> 1, driven by
-- Animations.lua): outside the fill region the light artwork is the
-- frame artwork (plus the tail of the glow next to the fill), so the
-- look barely changes, and every part of the frame then has the same
-- layers and fades as one.
function SCB.Bar:SpreadFrameLight(s)
    local school = self.currentSchool
    if not (school and school.frameLightMatchesFrame and self._frameLightClipActive) then return end
    s = Clamp01(s)
    local w  = SCB.Config:Get("barWidth") or 400
    local mL = (school.fillMarginL or 0) * w + (school.fillMarginLPx or 0)
    local mR = (school.fillMarginR or 0) * w + (school.fillMarginRPx or 0)
    local x0, x1 = mL, w - mR                       -- light at the end of the cast
    -- 2 px beyond each side: the mask's transparent border stays off the art.
    local left  = x0 + (-2 - x0) * s
    local right = x1 + (w + 2 - x1) * s
    local m, clip = self.frameLightMask, self.frameLightClip
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT",    clip, "TOPLEFT",    left, 0)
    m:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", left, 0)
    m:SetWidth(math.max(1, right - left))
    -- The mask keeps easing its soft right edge away on its own (it was
    -- given progress 1 when the cast completed), exactly as before.
    self._frameLightX0 = false           -- next cast re-anchors the mask
    clip:Show()
end

-- Alpha multiplier (0..1) of the frame light, used to let the light of
-- a cancelled cast die out during the cancel flash (Animations.lua).
function SCB.Bar:SetFrameLightFade(k)
    local school = self.currentSchool
    if not (self._frameLightClipActive and school and school.frameLightMatchesFrame) then return end
    k = Clamp01(k)
    self.texFrameLightClip:SetAlpha((self._frameLightAlpha or 1) * k)
    if self._frameLightAddAlpha and self.texFrameLightAdd then
        self.texFrameLightAdd:SetAlpha(self._frameLightAddAlpha * k)
    end
end

-- ---- Spell icons ----------------------------------------------------
-- Every icon style ships an icon mask made from its own artwork
-- (textures/<style>/Mask_Icon_<Style>, 256x256, applied with
-- texture:SetMask). It is opaque wherever the art in front of the icon
-- (frame, ring, gear, porthole) lets the icon be seen, and transparent
-- wherever that art is opaque. So the icon fills its socket with no gap,
-- and no part of it lies under opaque art, where it would show through
-- that art while the bar fades. Art that turns (Viking's ring, the
-- Gears gear) is measured at every angle.
-- The bar background is never cut: the socket art behind the icon
-- (Viking's stone disc, Honey's medallion, the Metal plate, ...) stays
-- whole and shows through the icon as it fades.
-- The mask spans the rectangle `rect` = { x0, y0, x1, y1 }, in the
-- style's 1024x512 artwork px. The artwork stretches with the bar
-- (W/1024 across, H/512 down) and so does the rectangle; with
-- rect.uniform (art that keeps its aspect, like Viking's turning ring)
-- it scales uniformly about its centre instead.
-- A SetMask mask does not count toward ClassicAPI's 3 masks per texture,
-- and needs no layout of its own: it always covers its texture exactly.
local ICON_TC_CROP = 0.08    -- the icon's own bevel, cut off each side
local ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Artwork px -> bar px factors at the current bar size.
function SCB.Bar:GetArtScale()
    local W = self._appliedW or (SCB.Config:Get("barWidth") or 400)
    local H = self._appliedH or (SCB.Config:Get("barHeight") or 200)
    return W / 1024, H / 512
end

local SpellIcon = {}
SpellIcon.__index = SpellIcon

-- Create a spell icon on `parent` (layer, sublevel) in rectangle `rect`,
-- with the mask named by the style definition `school` (iconMask).
function SCB.Bar:NewSpellIcon(parent, layer, sublevel, rect, school)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    t:SetAlpha(0)
    local icon = setmetatable({
        rect = rect, tex = t, alpha = 0,
        maskPath = school.iconMask,
    }, SpellIcon)
    t:SetMask(icon.maskPath)
    return icon
end

function SpellIcon:SetTexture(file)
    self.tex:SetTexture(file or ICON_FALLBACK)
    self.tex:SetMask(self.maskPath)   -- re-applied: the mask must survive any texture change
end

function SpellIcon:SetAlpha(a)
    self.alpha = a
    self.tex:SetAlpha(a)
end

function SpellIcon:GetAlpha() return self.alpha end

-- Lay the icon out at the current bar size.
function SpellIcon:Layout()
    local bar = SCB.Bar
    local f = bar.frameInner
    if not f then return end
    local sx, sy = bar:GetArtScale()
    local r = self.rect
    local x0, y0, x1, y1
    if r.uniform then
        local s = math.sqrt(sx * sy)
        local cx, cy = (r.x0 + r.x1) * 0.5 * sx, (r.y0 + r.y1) * 0.5 * sy
        local hw, hh = (r.x1 - r.x0) * 0.5 * s, (r.y1 - r.y0) * 0.5 * s
        x0, y0, x1, y1 = cx - hw, cy - hh, cx + hw, cy + hh
    else
        x0, y0, x1, y1 = r.x0 * sx, r.y0 * sy, r.x1 * sx, r.y1 * sy
    end
    local t = self.tex
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT",     f, "TOPLEFT", x0, -y0)
    t:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", x1, -y1)
    -- Crop the icon art to the rectangle's aspect, so it is never stretched.
    local w, h = x1 - x0, y1 - y0
    local cu, cv = 1 - 2 * ICON_TC_CROP, 1 - 2 * ICON_TC_CROP
    if w > h then cv = cv * h / w else cu = cu * w / h end
    t:SetTexCoord(0.5 - cu * 0.5, 0.5 + cu * 0.5, 0.5 - cv * 0.5, 0.5 + cv * 0.5)
end

-- Update the feather of the bar masks the current style uses (never their
-- size or anchors). The list is built by ApplySchool; a mask that joins it
-- later is reset by the progress-0 call of the next StartCast.
function SCB.Bar:SetRevealMaskProgress(progress)
    local masks = self._activeMasks
    if not masks then return end
    for i = 1, masks.n do
        SCB.SetRevealMaskProgress(masks[i], progress)
    end
end

-- Bar masks driven by cast progress for `school` (texMask always).
function SCB.Bar:BuildActiveMasks(school)
    local list = self._activeMasks or {}
    local n = 1
    list[1] = self.texMask
    local function add(m) n = n + 1 ; list[n] = m end
    if school.splitFill         then add(self.maskFillRight)      end
    if school.bgLight           then add(self.bgLightFullMask)    end
    if school.frameLight        then add(self.frameLightMask)     end
    if school.frostfireEffects  then add(self.maskGivreFrostfire) end
    if school.bgRed             then add(self.maskBGRed)          end
    if school.bgRed or school.contours then add(self.maskFrameRed) end
    for i = n + 1, #list do list[i] = nil end
    list.n = n
    self._activeMasks = list
end

-- Reveal the background glow and the frame light for `progress`.
function SCB.Bar:UpdateGenericLightClips(progress)
    local f = self.frameInner
    if not f then return end

    local w = SCB.Config:Get("barWidth") or 400
    local h = SCB.Config:Get("barHeight") or 200
    if not w or w <= 0 or not h or h <= 0 then return end

    progress = Clamp01(progress)

    -- Background glow: full-width artwork revealed by its mask.
    local bgSchool = self.currentSchool
    if bgSchool and bgSchool.bgLight then
        local revealW = math.max(1, w * progress)
        local alpha = progress > 0 and 1 or 0
        if self._bgLightAlpha ~= alpha then
            self._bgLightAlpha = alpha
            self.texBGLightFull:SetAlpha(alpha)
        end
        -- Host width and visibility only change with the bar size or the
        -- style (both clear _bgLightHostW), never during a cast.
        if self._bgLightHostW ~= w then
            self._bgLightHostW = w
            self.bgLightFullHost:SetWidth(w)
            self.bgLightFullHost:Show()
        end
        if bgSchool.bgLightArtworkReveal then
            -- Padded full-artwork reveal (ignores the fill margins). Its pad
            -- depends on revealW, so the anchors move every tick.
            SCB.LayoutArtworkRevealMask(self.bgLightFullMask, self.bgLightFullHost, revealW, progress)
        else
            -- Plain anchors (also undoes the padded layout of another style).
            -- They never change during a cast: set them once (reset by
            -- ApplySchool), then only the width follows progress.
            if not self._bgLightMaskLaidOut then
                self._bgLightMaskLaidOut = true
                self.bgLightFullMask:ClearAllPoints()
                self.bgLightFullMask:SetPoint("TOPLEFT", self.bgLightFullHost, "TOPLEFT")
                self.bgLightFullMask:SetPoint("BOTTOMLEFT", self.bgLightFullHost, "BOTTOMLEFT")
            end
            self.bgLightFullMask:SetWidth(revealW)
        end
    end

    -- Frame light: revealed over the whole bar, or over the fill region
    -- only for frameLightFollowsFill styles.
    if self._frameLightClipActive then
        local school  = self.currentSchool
        local mL      = school and ((school.fillMarginL or 0) * w + (school.fillMarginLPx or 0)) or 0
        local mR      = school and ((school.fillMarginR or 0) * w + (school.fillMarginRPx or 0)) or 0
        local fillW   = math.max(1, w - mL - mR)
        local followsFill = school and school.frameLightFollowsFill
        local revealW = math.max(1, followsFill and fillW * progress or w * progress)
        local x0      = followsFill and mL or 0
        -- Re-anchor only when the left edge moves (style change or resize);
        -- the cast itself only changes the width.
        if self._frameLightX0 ~= x0 then
            self._frameLightX0 = x0
            self.frameLightMask:ClearAllPoints()
            self.frameLightMask:SetPoint("TOPLEFT",    self.frameLightClip, "TOPLEFT",    x0, 0)
            self.frameLightMask:SetPoint("BOTTOMLEFT", self.frameLightClip, "BOTTOMLEFT", x0, 0)
        end
        self.frameLightMask:SetWidth(revealW)
        -- Alpha and visibility are restored once per cast: the end-of-cast
        -- animations (SetFrameLightFade, SpreadFrameLight) change them, and
        -- StartCast clears _frameLightShown.
        if not self._frameLightShown then
            self._frameLightShown = true
            self.texFrameLightClip:SetAlpha(self._frameLightAlpha or 1)
            if self._frameLightAddAlpha and self.texFrameLightAdd then
                self.texFrameLightAdd:SetAlpha(self._frameLightAddAlpha)
            end
            self.frameLightClip:Show()
        end
    end
    -- Styles without a frame light: ApplySchool already hid its layer.
end

-- ============================================================
--  APPLYING A STYLE
-- ============================================================

-- Configure every bar layer for a style (textures, layers to show/hide,
-- margins, text offsets). Called at the start of each cast.
function SCB.Bar:ApplySchool(schoolKey)
    local school = SCB.Schools:Get(schoolKey)
    if not school then return end

    local appliedW, appliedH = ResolveBarDimensions(school)
    self:ApplyDimensions(appliedW, appliedH)

    self.texBG:SetTexture(school.bg)
    -- Background flash (emptying bars): same artwork and shape as texBG.
    self.texFlashBG:SetTexture(school.bg)
    self.texFlashBG:SetBlendMode("ADD")
    self.texFlashBG:SetAlpha(0)
    self.texFlashBG:Hide()
    self.flashBGMask:SetTexture(school.bg)
    self.texFlashBGGlow:SetAlpha(0)
    self.texFlashBGGlow:Hide()
    -- Background glow: full-width artwork revealed by bgLightFullMask
    -- (laid out every tick by UpdateGenericLightClips).
    self._bgLightMaskLaidOut = nil
    self._bgLightHostW = nil
    self._bgLightAlpha = nil
    self._frameLightShown = nil
    self:BuildActiveMasks(school)
    if school.bgLight then
        local bW = SCB.Config:Get("barWidth")  or 400
        local oY = school.fillOffsetY or 0
        self.texBGLightFull:SetTexture(school.bgLight)
        self.texBGLightFull:SetBlendMode(school.bgLightBlend or "ADD")
        self.texBGLightFull:SetAlpha(0)
        self.bgLightFullHost:ClearAllPoints()
        self.bgLightFullHost:SetPoint("TOPLEFT",    self.frameInner, "TOPLEFT",    0, -oY)
        self.bgLightFullHost:SetPoint("BOTTOMLEFT", self.frameInner, "BOTTOMLEFT", 0,  oY)
        self.bgLightFullHost:SetWidth(bW)
        self.bgLightFullMask:SetWidth(1)
    else
        self.bgLightFullHost:Hide()
        self.texBGLightFull:SetAlpha(0)
    end
    -- Frame light: full-size artwork revealed by frameLightMask.
    self._frameLightX0 = nil
    if school.frameLight then
        self._frameLightAlpha = school.frameLightAlpha or 1
        self.texFrameLightClip:SetTexture(school.frameLight)
        self.texFrameLightClip:SetBlendMode(school.frameLightBlend or "ADD")
        self.texFrameLightClip:SetAlpha(self._frameLightAlpha)
        self._frameLightAddAlpha = school.frameLightAdd
        if self._frameLightAddAlpha then
            self.texFrameLightAdd:SetTexture(school.frameLight)
            self.texFrameLightAdd:SetAlpha(self._frameLightAddAlpha)
            self.texFrameLightAdd:Show()
        else
            self.texFrameLightAdd:Hide()
        end
        self._frameLightClipActive = true
    else
        self._frameLightAlpha    = nil
        self._frameLightAddAlpha = nil
        self.frameLightClip:Hide()
        self.texFrameLightClip:SetAlpha(0)
        self.texFrameLightAdd:Hide()
        self._frameLightClipActive = false
    end

    self.texFill:SetTexture(school.fill)
    -- fillMask styles (Arcane, Lumber) draw their own fill in the FX module.
    -- For splitFill (Aim), texFillPlain + texMask form the left half.
    if school.fillMask then
        self.texFill:SetAlpha(0)
    else
        self.texFill:SetAlpha(1)
    end
    -- Every style except fillMask ones shows its fill through texFillPlain.
    local isStaticFill = not school.fillMask
    if self.texMask.SetUseTexCoord then
        local bW = SCB.Config:Get("barWidth") or 400
        local mL = bW * (school.fillMarginL or 0) + (school.fillMarginLPx or 0)
        local mR = bW * (school.fillMarginR or 0) + (school.fillMarginRPx or 0)
        local fillW = math.max(1, bW - mL - mR)
        if self.texFlash then
            self.texFlash:SetTexture(isStaticFill and school.fill or nil)
            -- Re-apply the blend after SetTexture, like the other layers.
            self.texFlash:SetBlendMode("ADD")
            self.texFlash:SetAlpha(0)
            self.texFlash:Hide()
        end
        if self.texFlashRight then
            self.texFlashRight:SetTexture(school.splitFill and school.fillRight or nil)
            self.texFlashRight:SetBlendMode("ADD")
            self.texFlashRight:SetAlpha(0)
            self.texFlashRight:Hide()
        end
        self.texMask:SetUseTexCoord(isStaticFill, fillW, FillPlainShift(school))
        for _, strip in ipairs(self.fillStrips) do
            strip:SetTexture(school.fill)
            strip:SetBlendMode("BLEND")
            strip:SetVertexColor(1, 1, 1)
            strip:SetAlpha(isStaticFill and 1 or 0)
        end
    end
    if school.frames then
        self.texFrame:SetTexture(school.frames[1])
        self.texFrame:SetAlpha(1)
    else
        self.texFrame:SetTexture(school.frame)
        self.texFrame:SetAlpha(1)
    end
    self.texBG:SetAlpha(1)

    -- Reset the Fire layers. Hide() (not just alpha 0) keeps these large
    -- full-bar quads out of rendering while unused.
    self.texBGRed:SetAlpha(0)
    self.texBGRed:SetVertexColor(1, 1, 1)
    self.texBGRed:SetTexCoord(0, 1, 0, 1)
    self.texBGRed:Hide()
    self.maskBGRed:SetWidth(1)
    self.texFrameRed:SetAlpha(0)
    self.texFrameRed:SetVertexColor(1, 1, 1)
    self.texFrameRed:SetTexCoord(0, 1, 0, 1)
    self.texFrameRed:SetBlendMode("BLEND")
    self.texFrameRed:Hide()
    self.maskFrameRed:SetWidth(1)
    for _, t in ipairs(self.texFillEffects) do
        t:SetAlpha(0)
        t:SetVertexColor(1, 1, 1)
        t:SetTexCoord(0, 1, 0, 1)
        t:SetBlendMode("BLEND")
        t:Hide()
    end
    for _, t in ipairs(self.texContoursFire) do
        t:SetAlpha(0)
        t:SetVertexColor(1, 1, 1)
        t:SetTexCoord(0, 1, 0, 1)
        t:SetBlendMode("BLEND")
        t:Hide()
    end

    -- Reset the Frostfire layers.
    if self.givreHost then self.givreHost:Hide() end
    self.maskGivreFrostfire:SetWidth(1)
    for _, t in ipairs(self.texFillEffectsFrostfire) do t:Hide() end

    -- Reset the Aim layers.
    self.texFillRight:SetAlpha(0)
    self.texFillEnding:SetAlpha(0)
    self.maskFillRight:SetWidth(1)
    self.maskFillRight:Hide()
    self._aimEndingFired = false
    self._aimEndingT     = 0
    self:ResetSable()

    if school.bgRed then
        -- Fire: red BG + red frame, fill effects and animated contours.
        self.texBGRed:SetTexture(school.bgRed)
        self.texBGRed:SetVertexColor(1, 1, 1)
        self.texBGRed:SetTexCoord(0, 1, 0, 1)
        self.texBGRed:SetAlpha(1) ; self.texBGRed:Show()
        self.texFrameRed:SetTexture(school.frameRed)
        self.texFrameRed:SetVertexColor(1, 1, 1)
        self.texFrameRed:SetTexCoord(0, 1, 0, 1)
        self.texFrameRed:SetBlendMode("BLEND")
        self.texFrameRed:SetAlpha(1) ; self.texFrameRed:Show()
        -- The animated contours replace the static one.
        self.texContour:Hide()
        if school.fillEffects then
            for i, t in ipairs(self.texFillEffects) do
                t:SetTexture(school.fillEffects[i] or school.fillEffects[1])
                t:SetVertexColor(1, 1, 1)
                t:SetTexCoord(0, 1, 0, 1)
                t:SetBlendMode("BLEND")
            end
        end
        if school.contours then
            for i, t in ipairs(self.texContoursFire) do
                t:SetTexture(school.contours[i] or school.contours[1])
                t:SetVertexColor(1, 1, 1)
                t:SetTexCoord(0, 1, 0, 1)
                t:SetBlendMode("BLEND")
            end
        end
    elseif school.frostfireEffects then
        -- Frostfire: frost overlay + flame effects, revealed with the cast.
        self.texContour:Hide()
        self.texGivreFrostfire:SetTexture(school.frostfireGivre)
        -- The overlay spans the full bar width from the left edge.
        local oY = school.fillOffsetY or 0
        if self.givreHost then
            self.givreHost:ClearAllPoints()
            self.givreHost:SetPoint("TOPLEFT",    self.frameInner, "TOPLEFT",    0, -oY)
            self.givreHost:SetPoint("BOTTOMLEFT", self.frameInner, "BOTTOMLEFT", 0,  oY)
            -- Re-assert the level on every show: 1.12 can renormalize child levels.
            self.givreHost:SetFrameLevel(self.overlayHost:GetFrameLevel() + 1)
            self.givreHost:Show()
        end
        for i, t in ipairs(self.texFillEffectsFrostfire) do
            t:SetTexture(school.frostfireEffects[i] or school.frostfireEffects[1])
        end
    elseif school.contours then
        -- Animated contours only (Shadow); their alphas are driven by the FX module.
        self.texContour:Hide()
        for i, t in ipairs(self.texContoursFire) do
            t:SetTexture(school.contours[i] or school.contours[1])
            t:SetVertexColor(1, 1, 1)
            t:SetTexCoord(0, 1, 0, 1)
            t:SetBlendMode("BLEND")
        end
    else
        -- Static contour, if the style has one.
        if school.contour then
            self.texContour:SetTexture(school.contour)
            self.texContour:SetAlpha(1) ; self.texContour:Show()
        else
            self.texContour:Hide()
        end
    end

    -- splitFill (Aim): set up the right half (left edge -> center is the
    -- texFillPlain + texMask; right edge -> center is texFillRight).
    if school.splitFill then
        if school.fillRight then
            self.texFillRight:SetTexture(school.fillRight)
            self.texFillRight:SetAlpha(1)
        end
        if school.fillEnding then
            self.texFillEnding:SetTexture(school.fillEnding)
        end
        -- Right-fill geometry; its anchor offset is refreshed by _Tick.
        local bW    = SCB.Config:Get("barWidth")  or 400
        local bH    = SCB.Config:Get("barHeight") or 200
        local fillW = bW * (1 - (school.fillMarginL or 0) - (school.fillMarginR or 0))
        local fillH = school.fillHeight or bH
        local offY  = school.fillOffsetY or 0
        self.maskFillRight:SetFillW(math.max(1, fillW))
        self.maskFillRight:SetFillH(math.max(1, fillH))
        self.maskFillRight:SetOffY(offY)
        self.maskFillRight:SetPoint("TOPRIGHT", self.frameInner, "TOPRIGHT", 0, 0)
        self.maskFillRight:Show()
        self.maskFillRight:SetWidth(1)
    end

    self.currentSchool    = school
    self.currentSchoolKey = schoolKey

    if school.sable then
        self:StartSable()
    end

    -- Text position, font and color (with this style's text offsets) are
    -- applied by ApplyTextPrefs, which StartCast runs right after this.

    -- Fill margins; clearing the cached offsets makes _Tick re-anchor the masks.
    self.fillMarginL  = school.fillMarginL or 0
    self.fillMarginR  = school.fillMarginR or 0
    self._maskOffsetL   = nil
    self._maskOffsetR   = nil
    self._maskReverseDir = nil
    self._maskOffsetRRight = nil
end

-- ============================================================
--  CAST CONTROL
-- ============================================================

-- Show the bar for a new cast. startMS/endMS (server timestamps) are used
-- when given; otherwise the cast runs from now for `duration` seconds.
function SCB.Bar:StartCast(spellName, duration, schoolKey, isChannel, spellIcon, startMS, endMS)
    if not self.frame then return end
    if duration <= 0 then return end

    self.castGeneration = (self.castGeneration or 0) + 1

    SCB.Animations:Cancel(self.frame)
    self.isFading          = false
    self.isActive          = true
    self.isChannel         = isChannel or false
    -- Server timestamps keep the bar exact (a channel's start is already in
    -- the past when its event fires).
    if startMS and endMS then
        self.castStart = startMS / 1000
        self.castEnd   = endMS   / 1000
    else
        self.castStart = GetTime()
        self.castEnd   = GetTime() + duration
    end
    self._accum     = 0
    self.currentSpellIcon = spellIcon
    self.currentSpellName = spellName or ""

    -- Dynamic Blizzard-bar mode: this cast is ours, so hide Blizzard's bar.
    if SCB._blizzardDynamic then
        SCB.HideBlizzardBarFrames(true)
    end

    self.frame:SetScale(SCB.Config:Get("scale") or 0.8)

    self:ApplySchool(schoolKey or "frost")

    -- Orb portrait: only for Aim (splitFill) school
    if self.currentSchool and self.currentSchool.splitFill then
        self:OrbLoadTarget()
    else
        if self.orbPortraitFrame then self.orbPortraitFrame:Hide() end
    end

    -- ApplyTextPrefs also sets the spell name text.
    if SCB.Config:Get("showCastTime") then
        self._timerTenth = nil
        self.castTimerText:SetText(string.format("%.1f", duration))
    else
        self.castTimerText:SetText("")
    end

    self:ApplyTextPrefs()

    self:SetRevealMaskProgress(0)  -- every cast starts feathered
    self.texMask:SetWidth(1)       -- and empty

    -- Show the bar before the (lazy) FX init: mask/clip layers created on
    -- first use must be created against a visible bar.
    self.frame:SetAlpha(1)
    self.frame:Show()
    if not SCB.Config:Get("locked") then self.frame:EnableMouse(true) end

    SCB.Particles:Start(duration)
    self:_Tick(UPDATE_RATE)
    -- No flash when this cast replaces a bar that was still visible: the
    -- flash covers the whole fill region, so over the new (empty) fill it
    -- would show as a ghost of the previous cast's full bar.
end

-- End the cast: success plays the completion animation, otherwise the
-- failure shake. The bar hides itself once the animation is done.
function SCB.Bar:StopCast(success)
    if not self.isActive then return end
    if self.isFading then return end

    self.isActive = false
    self.isFading = true

    if self._sabreActive then
        self:FreezeSableAtProgress(self:GetSableProgress())
    end

    local gen = self.castGeneration

    SCB.Particles:Stop(success)

    if success then
        -- Snap the fill to complete so the fade-out shows a full bar.
        if self.currentSchool and self.currentSchool.splitFill then
            -- Aim: both halves meet in the center.
            local barW  = SCB.Config:Get("barWidth") or 400
            local fillW = barW * (1 - (self.fillMarginL or 0) - (self.fillMarginR or 0))
            local halfFillW = fillW * 0.5
            self.texMask:SetWidth(halfFillW)
            self.maskFillRight:SetWidth(halfFillW)
            self:UpdateGenericLightClips(1)
            self:SetRevealMaskProgress(1)
            -- The ending flash stays at full alpha and fades with the bar.
            self.texFillEnding:SetAlpha(1)
        elseif not self.fillEmptying then
            -- Every bar that fills (normal casts, and channels of noReverse
            -- styles such as Lumber); channels and reverse fills end empty.
            local bW2 = SCB.Config:Get("barWidth") or 400
            local mL2 = self.fillMarginL or 0
            local mR2 = self.fillMarginR or 0
            local lPx2 = (self.currentSchool and self.currentSchool.fillMarginLPx) or 0
            local rPx2 = (self.currentSchool and self.currentSchool.fillMarginRPx) or 0
            local fillW2 = bW2 * (1 - mL2 - mR2) - lPx2 - rPx2
            self.texMask:SetWidth(math.max(fillW2, 1))
            self._lastFillProgress = 1
            self:UpdateGenericLightClips(1)
            self:SetRevealMaskProgress(1)
        end
        SCB.Animations:PlayComplete(self.frame, gen, function()
            self.isFading = false
            self:ResetSable()
            SCB.Particles:ResetAll()
            if self.orbPortraitFrame then self.orbPortraitFrame:Hide() end
            if not self.isActive then
                if not SCB.Config:Get("locked") then self.frame:StopMovingOrSizing() end
                self.frame:EnableMouse(false)
                -- The bar is fully transparent now: hide it so its OnUpdate
                -- (and every child) stops running between casts.
                self.frame:Hide()
            end
        end)
    else
        SCB.Animations:PlayFail(self.frame, gen, function()
            self.isFading = false
            self:ResetSable()
            SCB.Particles:ResetAll()
            if self.orbPortraitFrame then self.orbPortraitFrame:Hide() end
            if not self.isActive then
                if not SCB.Config:Get("locked") then self.frame:StopMovingOrSizing() end
                self.frame:EnableMouse(false)
                -- The bar is fully transparent now: hide it so its OnUpdate
                -- (and every child) stops running between casts.
                self.frame:Hide()
            end
        end)
    end
end

-- ============================================================
--  PUSHBACK
-- ============================================================

-- Cast delayed / channel shortened: adopt the new timing and flash.
function SCB.Bar:ApplyPushback(newStartSec, newEndSec)
    if not self.isActive then return end
    local sableProgress = self._sabreActive and self:GetSableProgress() or nil
    self.castStart = newStartSec
    self.castEnd   = newEndSec
    if sableProgress then
        self._sabreEndTime = newEndSec
        self:PlaySableFromProgress(sableProgress)
    end
    SCB.Animations:PlayPushback()
end

-- ============================================================
--  TICK
-- ============================================================

function SCB.Bar:_Tick(elapsed)
    -- Fading out: only the FX run (their layers fade with the bar).
    if self.isFading and not self.isActive then
        SCB.Particles:UpdateCirclesFade(elapsed)
        return
    end

    if not self.isActive then return end

    local now       = GetTime()
    -- Guard against a zero/negative span (pushback or stale timestamps)
    -- which would otherwise produce inf/NaN widths for every mask.
    local total     = math.max(self.castEnd - self.castStart, 0.001)
    local progress  = math.max(0, math.min((now - self.castStart) / total, 1))
    local remaining = math.max(self.castEnd - now, 0)

    -- Channels (and reverseFill styles) empty the bar instead of filling it,
    -- except Aim (splitFill) and noReverse styles, which always fill.
    local isAim     = self.currentSchool and self.currentSchool.splitFill
    local noReverse = self.currentSchool and self.currentSchool.noReverse
    local reverseFill = (not isAim) and (not noReverse) and (self.isChannel or (self.currentSchool and self.currentSchool.reverseFill))
    local fillProgress = reverseFill and (1 - progress) or progress
    -- Read by SCB.SetRevealMaskProgress: an emptying bar keeps its feather.
    self.fillEmptying = reverseFill and true or false

    -- Use the configured size: GetWidth/GetHeight can still be 0 before the
    -- first render.
    local barW = SCB.Config:Get("barWidth") or 400
    local barH = SCB.Config:Get("barHeight") or 200
    local mL   = self.fillMarginL or 0
    local mR   = self.fillMarginR or 0
    local fillMarginLPx = (self.currentSchool and self.currentSchool.fillMarginLPx) or 0
    local fillMarginRPx = (self.currentSchool and self.currentSchool.fillMarginRPx) or 0
    local fillW = barW * (1 - mL - mR) - fillMarginLPx - fillMarginRPx
    local offsetL = barW * mL + fillMarginLPx
    local offsetR = barW * mR + fillMarginRPx
    local reverseDir = self.currentSchool and self.currentSchool.reverseDir
    if self._sabreActive then
        self:LayoutSable(self:GetSableProgress())
    end

    -- Re-anchor the fill mask only when its offsets or direction change.
    if (not self._maskOffsetL) or (self._maskOffsetL ~= offsetL) or
       (not self._maskOffsetR) or (self._maskOffsetR ~= offsetR) or
       (self._maskReverseDir ~= reverseDir) then
        self._maskOffsetL = offsetL
        self._maskOffsetR = offsetR
        self._maskReverseDir = reverseDir
        self.texMask:ClearAllPoints()
        if reverseDir then
            self.texMask:SetPoint("TOPRIGHT",    self.frameInner, "TOPRIGHT",    -offsetR, 0)
            self.texMask:SetPoint("BOTTOMRIGHT", self.frameInner, "BOTTOMRIGHT", -offsetR, 0)
        else
            self.texMask:SetPoint("TOPLEFT",    self.frameInner, "TOPLEFT",    offsetL, 0)
            self.texMask:SetPoint("BOTTOMLEFT", self.frameInner, "BOTTOMLEFT", offsetL, 0)
        end
    end
    -- Fill size / vertical offset (the setters ignore unchanged values).
    local fillOffY = (self.currentSchool and self.currentSchool.fillOffsetY) or 0
    local fillH = (self.currentSchool and self.currentSchool.fillHeight) or barH
    if self.texMask.SetBarH then self.texMask:SetBarH(math.max(1, fillH)) end
    if self.texMask.SetFillW then self.texMask:SetFillW(math.max(1, barW)) end
    if self.texMask.SetOffY  then self.texMask:SetOffY(fillOffY) end

    -- For splitFill, texMask is the left half and stops at the center.
    if self.currentSchool and self.currentSchool.splitFill then
        self.texMask:SetWidth(math.max(fillW * 0.5 * fillProgress, 1))
        self:UpdateGenericLightClips(fillProgress)
    else
        self.texMask:SetWidth(math.max(fillW * fillProgress, 1))
        self:UpdateGenericLightClips(fillProgress)
    end
    -- Revealed part of the fill, for the cancel flash (LayoutFlash).
    self._lastFillProgress = fillProgress

    -- splitFill (Aim): right half, with its own optional margins.
    if self.currentSchool and self.currentSchool.splitFill then
        local mLR  = self.currentSchool.fillMarginLRight or mL
        local mRR  = self.currentSchool.fillMarginRRight or mR
        local fillMarginLRightPx = (self.currentSchool.fillMarginLRightPx) or 0
        local fillMarginRRightPx = (self.currentSchool.fillMarginRRightPx) or 0
        local fillWRight = barW * (1 - mLR - mRR) - fillMarginLRightPx - fillMarginRRightPx
        local offsetRRight = barW * mRR + fillMarginRRightPx

        -- Re-anchor only when the offset changes (cache cleared by
        -- ApplySchool and Resize).
        if self._maskOffsetRRight ~= offsetRRight then
            self._maskOffsetRRight = offsetRRight
            self.maskFillRight:SetPoint("TOPRIGHT", self.frameInner, "TOPRIGHT", -offsetRRight, 0)
        end

        local halfFillWRight = fillWRight * 0.5
        self.maskFillRight:SetFillW(math.max(1, barW))
        self.maskFillRight:SetFillH(math.max(1, fillH))
        self.maskFillRight:SetWidth(math.max(halfFillWRight * fillProgress, 1))
        self._maskRightW = math.max(halfFillWRight * fillProgress, 1)

        -- End flash: pulses once the halves are 97% closed.
        if fillProgress >= 0.97 then
            if not self._aimEndingFired then
                self._aimEndingFired = true
                self._aimEndingT     = 0
            end
        end
        if self._aimEndingFired then
            self._aimEndingT = (self._aimEndingT or 0) + elapsed
            local flashAlpha = math.abs(math.sin(self._aimEndingT * math.pi / 0.6)) * 0.90
            self.texFillEnding:SetAlpha(flashAlpha)
        end
    end

    SCB.Particles:Update(elapsed, fillProgress)
    self:SetRevealMaskProgress(fillProgress)

    if SCB.Config:Get("showCastTime") then
        -- Only reformat/redraw when the displayed tenth actually changes
        -- (avoids ~50 string.format allocations per second during a cast).
        local tenth = math.floor(remaining * 10 + 0.5)
        if tenth ~= self._timerTenth then
            self._timerTenth = tenth
            self.castTimerText:SetText(string.format("%.1f", tenth * 0.1))
        end
    end

    if progress >= 1 then
        self:StopCast(true)
    end
end

-- ============================================================
--  RESIZE
-- ============================================================

-- Save a new configured size and re-layout everything that depends on it.
function SCB.Bar:Resize(w, h)
    SCB.Config:Set("barWidth", w)
    SCB.Config:Set("barHeight", h)
    local appliedW, appliedH = ResolveBarDimensions(self.currentSchool, w, h)
    self:ApplyDimensions(appliedW, appliedH)
    self._maskOffsetL = nil
    self._maskOffsetR = nil
    self._maskReverseDir = nil
    self._maskOffsetRRight = nil
    if self.spellNameText and self.castTimerText then
        self:ApplyTextPrefs()
    end
    if SCB.Particles and SCB.Particles.RefreshLayout then
        SCB.Particles:RefreshLayout()
    end
    if self._sabreActive then
        self:PlaySableFromProgress(self:GetSableProgress())
    else
        self:LayoutSable(0, true)
    end
    if self.isActive then
        self:_Tick(UPDATE_RATE)
    end
end

-- Apply an actual pixel size to the bar and its size-dependent children.
function SCB.Bar:ApplyDimensions(w, h)
    self._appliedW, self._appliedH = w, h
    if self.frame then
        self.frame:SetSize(w, h)
    end
    if self.particleContainer then
        self.particleContainer:SetSize(w + 120, h + 120)
    end
    if self.orbPortraitFrame then
        self.orbPortraitFrame:ClearAllPoints()
        self.orbPortraitFrame:SetPoint("CENTER", self.frame, "TOPLEFT", w * 0.503, -(h * 0.236))
    end
    -- The Frostfire frost overlay host spans the bar width; without this it
    -- kept the login-time width after the bar was resized.
    if self.givreHost then
        self.givreHost:SetWidth(w)
    end
    if SCB.Particles and SCB.Particles.LayoutFrames then
        SCB.Particles:LayoutFrames()
    end
end

-- ============================================================
--  TEXT PREFERENCES
-- ============================================================

-- Font name (fontFace setting) -> file. The bundled fonts only cover Latin
-- characters; "Friz Quadrata TT" uses the client's standard font, which
-- also renders Korean and Chinese on those clients.
local FONT_PATH = "Interface\\AddOns\\OpulentCastingBars\\fonts\\"
local FONT_DEFAULT  = FONT_PATH .. "KenyanCoffee.ttf"
local FONT_BLIZZARD = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local BUNDLED_FONT_MAP = {
    ["Kenyan Coffee"]     = FONT_PATH .. "KenyanCoffee.ttf",
    ["Gaegu"]             = FONT_PATH .. "Gaegu-Bold.ttf",
    ["Teko"]              = FONT_PATH .. "Teko-Bold.ttf",
    ["Titan One"]         = FONT_PATH .. "TitanOne-Regular.ttf",
    ["Yanone Kaffeesatz"] = FONT_PATH .. "YanoneKaffeesatz-Bold.ttf",
    ["Expressway"]        = FONT_PATH .. "expressway.ttf",
    ["Nexa"]              = FONT_PATH .. "Nexa-Heavy.ttf",
    ["Casual Memories"]   = FONT_PATH .. "CasualMemoriesBold.ttf",
    ["Alte Haas Grotesk"] = FONT_PATH .. "AlteHaasGroteskBold.ttf",
    ["Steelfish"]         = FONT_PATH .. "Steelfish.ttf",
    ["Friz Quadrata TT"]  = FONT_BLIZZARD,
    -- Other fonts shipped with the 1.12.1 Latin-alphabet clients.
    ["Arial Narrow"]      = "Fonts\\ARIALN.TTF",
    ["Morpheus"]          = "Fonts\\MORPHEUS.TTF",
    ["Skurri"]            = "Fonts\\skurri.ttf",
}

-- Sets a font, falling back to the client's standard font if the file
-- could not be loaded (e.g. a game font missing on Asian clients), so the
-- text never goes blank.
local function SafeSetFont(fs, path, size, outline)
    fs:SetFont(path, size, outline)
    if path ~= FONT_BLIZZARD and not fs:GetFont() then
        fs:SetFont(FONT_BLIZZARD, size, outline)
    end
end

local function ResolveFontFace(fontKey)
    if fontKey == "DEFAULT" then return FONT_DEFAULT end
    if fontKey == "BLIZZARD" then return FONT_BLIZZARD end
    if fontKey == "GAME_CHINESE" then
        local locale = GetLocale()
        return (locale == "zhTW") and "Fonts\\ARKai_T.ttf" or "Fonts\\ARKai_C.ttf"
    end
    local mapped = BUNDLED_FONT_MAP[fontKey]
    if mapped then return mapped end
    -- Old saved settings stored a bare font file name.
    if type(fontKey) == "string" and fontKey:find("%.[a-zA-Z]") then
        return FONT_PATH .. fontKey
    end
    return FONT_DEFAULT
end

-- Text color setting -> RGBA. The options window writes "white" or "custom";
-- "yellow" and "school" can still come from older saved settings.
local TEXT_COLORS = {
    white  = { 1.0, 1.0, 1.0, 1.0 },
    yellow = { 1.0, 0.85, 0.0, 1.0 },
}

-- Per-style colors for the "school" color setting.
local SCHOOL_COLORS = {
    fire      = { 1.0, 0.4,  0.1,  1.0 },
    frost     = { 0.5, 0.85, 1.0,  1.0 },
    arctic    = { 0.62, 0.90, 1.0,  1.0 },
    arcane    = { 0.7, 0.4,  1.0,  1.0 },
    arcaneum  = { 0.62, 0.40, 1.0,  1.0 },
    shadow    = { 0.7, 0.2,  0.9,  1.0 },
    nature    = { 0.3, 0.9,  0.3,  1.0 },
    holy      = { 1.0, 0.9,  0.5,  1.0 },
    frostfire = { 0.4, 0.8,  1.0,  1.0 },
    thunder   = { 0.6, 0.7,  1.0,  1.0 },
    aim       = { 1.0, 0.25, 0.05, 1.0 },
    neutral   = { 1.0, 1.0,  1.0,  1.0 },
    lumber    = { 0.72, 0.50, 0.22, 1.0 },
    metal     = { 0.95, 0.82, 0.58, 1.0 },
    metal_icon= { 0.95, 0.82, 0.58, 1.0 },
    gears     = { 0.95, 0.82, 0.58, 1.0 },
    alliance  = { 0.3, 0.6,  1.0,  1.0 },
    horde     = { 1.0, 0.2,  0.1,  1.0 },
}

-- Apply font, size, color, visibility and position of both texts.
function SCB.Bar:ApplyTextPrefs()
    local cfg = SCB.Config
    local school = self.currentSchoolKey or "neutral"
    local school_data = SCB.Schools:Get(school)
    -- Style X offsets (not used by the centered/CENTER layouts, by design)
    local schoolNameOffX  = (school_data and school_data.textNameOffX)  or 0
    local schoolTimerOffX = (school_data and school_data.textTimerOffX) or 0
    local schoolOffY      = (school_data and school_data.textOffY)      or 0
    -- User offsets
    local userNamePosX  = cfg:Get("textNamePosX")  or 0
    local userTimerPosX = cfg:Get("textTimerPosX") or 0
    -- Style + user offsets, for the LEFT / RIGHT alignments
    local nameOffX  = schoolNameOffX  + userNamePosX
    local timerOffX = schoolTimerOffX + userTimerPosX
    local nameOffY  = schoolOffY + (cfg:Get("textNamePosY")  or 0)
    local timerOffY = schoolOffY + (cfg:Get("textTimerPosY") or 0)
    local defaultW  = (SCB.Config.defaults and SCB.Config.defaults.barWidth) or 400
    local barW      = cfg:Get("barWidth") or defaultW
    if defaultW <= 0 then defaultW = 400 end
    if not barW or barW <= 0 then barW = defaultW end
    -- Text insets scale with the bar width.
    local widthScale = barW / defaultW
    local leftInset  = 66 * widthScale
    local rightInset = 60 * widthScale

    local fontKey   = cfg:Get("fontFace") or "DEFAULT"
    local outline   = cfg:Get("textOutline") and "OUTLINE" or ""

    -- Centered layout: name ends just left of the center, timer starts just
    -- right of it; the individual alignment settings are ignored.
    local centered  = cfg:Get("textCentered")

    local function resolveColor(colorKey)
        if colorKey == "custom" then
            local col = cfg:Get("textCustomColor") or {r=1,g=1,b=1}
            return col.r, col.g, col.b, 1
        elseif colorKey == "school" then
            return unpack(SCHOOL_COLORS[school] or TEXT_COLORS.white)
        end
        return unpack(TEXT_COLORS[colorKey] or TEXT_COLORS.white)
    end

    -- ---- Spell name ----
    local nameFS       = self.spellNameText
    local nameSize     = cfg:Get("textNameSize")  or 11
    local nameAlign    = cfg:Get("textNameAlign") or "LEFT"
    local nr, ng, nb, na = resolveColor(cfg:Get("textNameColor") or "white")

    SafeSetFont(nameFS, ResolveFontFace(fontKey), nameSize, outline)
    nameFS:SetTextColor(nr, ng, nb, na)
    if cfg:Get("showSpellName") then
        nameFS:SetText(TruncateSpellName(self.currentSpellName or ""))
    else
        nameFS:SetText("")
    end

    nameFS:ClearAllPoints()
    if centered then
        nameFS:SetJustifyH("RIGHT")
        nameFS:SetWidth(barW * 0.42)
        nameFS:SetPoint("RIGHT", self.frameInner, "CENTER", 6 + userNamePosX, 4 + nameOffY)
    elseif nameAlign == "CENTER" then
        nameFS:SetJustifyH("CENTER")
        nameFS:SetWidth(barW * 0.6)
        nameFS:SetPoint("CENTER", self.frameInner, "CENTER", userNamePosX, 4 + nameOffY)
    elseif nameAlign == "RIGHT" then
        nameFS:SetJustifyH("RIGHT")
        nameFS:SetWidth(barW - leftInset - rightInset)
        nameFS:SetPoint("RIGHT", self.frameInner, "RIGHT", -rightInset + nameOffX, 4 + nameOffY)
    else
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWidth(barW - leftInset - rightInset)
        nameFS:SetPoint("LEFT", self.frameInner, "LEFT", leftInset + nameOffX, 4 + nameOffY)
    end

    -- ---- Timer ----
    local timerFS      = self.castTimerText
    local timerSize    = cfg:Get("textTimerSize")  or 11
    local timerAlign   = cfg:Get("textTimerAlign") or "RIGHT"
    local tr, tg, tb, ta = resolveColor(cfg:Get("textTimerColor") or "white")

    SafeSetFont(timerFS, ResolveFontFace(fontKey), timerSize, outline)
    timerFS:SetTextColor(tr, tg, tb, ta)

    timerFS:ClearAllPoints()
    if centered then
        timerFS:SetJustifyH("LEFT")
        timerFS:SetWidth(barW * 0.25)
        timerFS:SetPoint("LEFT", self.frameInner, "CENTER", 14 + userTimerPosX, 4 + timerOffY)
    elseif timerAlign == "CENTER" then
        timerFS:SetJustifyH("CENTER")
        timerFS:SetWidth(barW * 0.3)
        timerFS:SetPoint("CENTER", self.frameInner, "CENTER", userTimerPosX, 4 + timerOffY)
    elseif timerAlign == "LEFT" then
        timerFS:SetJustifyH("LEFT")
        timerFS:SetWidth(barW - leftInset - rightInset)
        timerFS:SetPoint("LEFT", self.frameInner, "LEFT", leftInset + timerOffX, 4 + timerOffY)
    else
        timerFS:SetJustifyH("RIGHT")
        timerFS:SetWidth(barW - leftInset - rightInset)
        timerFS:SetPoint("RIGHT", self.frameInner, "RIGHT", -rightInset + timerOffX, 4 + timerOffY)
    end
end
