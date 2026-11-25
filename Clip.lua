-- ============================================================
--  Opulent Casting Bars -- Clip.lua  (vanilla 1.12.1 / ClassicAPI)
--
--  Progressive left-to-right reveal for animated FX overlays.
--  Every texture created on the strip's child frame is automatically
--  masked by a reveal mask (SCB.NewRevealMask) whose width follows cast
--  progress. Overlays keep their own texcoord / rotation animation
--  (masks ignore SetTexCoord) and the edge moves sub-pixel smoothly.
--
--  API: New / GetChild / Layout / SetFixed / SetFrameLevel / Show / Hide.
-- ============================================================

SCB.Clip = SCB.Clip or {}
local ClipMT = { __index = SCB.Clip }

-- Create a clip strip. `parent` is the frame it lives in (draw order
-- follows the parent's frame level). Returns a strip object.
function SCB.Clip:New(parent)
    parent = parent or UIParent
    local host  = CreateFrame("Frame", nil, parent)
    host:SetAllPoints(parent)
    local child = CreateFrame("Frame", nil, host)
    child:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    child:SetWidth(1) ; child:SetHeight(1)

    local mask = SCB.NewRevealMask(host)
    mask:SetPoint("LEFT", parent, "LEFT", 0, 0)
    mask:SetWidth(1) ; mask:SetHeight(1)

    -- Wrap CreateTexture so every texture made on the child gets the mask.
    local FrameBase = { CreateTexture = child.CreateTexture }
    child.CreateTexture = function(self, a1, a2, a3, a4)
        local t = FrameBase.CreateTexture(self, a1, a2, a3, a4)
        SCB.AttachMask(t, mask)
        return t
    end

    host:Hide()
    return setmetatable({ host = host, child = child, mask = mask, _w = 0, _h = 0 }, ClipMT)
end

-- Frame to create overlay textures on. It spans the whole fill region,
-- so anchor overlays to it (e.g. CENTER for a swirl) for stable coordinates.
function SCB.Clip:GetChild() return self.child end

-- Place the strip over the bar's fill region and reveal `revealFrac`
-- (0..1) of it, left to right. All values are relative to `bar`.
--   fillLeftPx : left edge of the fill, in bar-local px from bar's LEFT
--   fillW      : fill region width in px
--   yOff       : vertical offset from bar's vertical centre (px)
--   fillH      : clip height in px
function SCB.Clip:Layout(bar, fillLeftPx, fillW, yOff, fillH, revealFrac)
    fillW = math.max(1, fillW or 1)
    fillH = math.max(1, fillH or 1)
    revealFrac = math.max(0, math.min(revealFrac or 0, 1))
    local revealW = math.max(1, fillW * revealFrac)

    -- The child spans the full fill region; the mask clips it to
    -- [0, revealW]. Anchors are only rebuilt when the geometry changes.
    if self._w ~= fillW or self._h ~= fillH or self._bar ~= bar
       or self._l ~= fillLeftPx or self._y ~= yOff then
        self.child:ClearAllPoints()
        self.child:SetPoint("LEFT", bar, "LEFT", fillLeftPx or 0, yOff or 0)
        self.child:SetWidth(fillW) ; self.child:SetHeight(fillH)
        self.mask:ClearAllPoints()
        self.mask:SetPoint("LEFT", bar, "LEFT", fillLeftPx or 0, yOff or 0)
        self.mask:SetHeight(fillH)
        self._w, self._h, self._bar, self._l, self._y = fillW, fillH, bar, fillLeftPx, yOff
    end
    self.mask:SetWidth(revealW)
    SCB.SetRevealMaskProgress(self.mask, revealFrac)
    if not self._shown then self:Show() end
end

-- Let this strip's own progress control feather narrowing and completion,
-- even when the cast bar is emptying.
function SCB.Clip:SetFixed() SCB.SetRevealMaskFixed(self.mask) end

function SCB.Clip:SetFrameLevel(lvl)
    -- 1.12 does not propagate frame levels to existing children, so the
    -- textured child must be set explicitly or it keeps its creation level.
    self.host:SetFrameLevel(lvl)
    self.child:SetFrameLevel(lvl)
end
-- The host is only shown or hidden through these two, so _shown is exact.
function SCB.Clip:Show() self._shown = true  ; self.host:Show() end
function SCB.Clip:Hide() self._shown = false ; self.host:Hide() end
