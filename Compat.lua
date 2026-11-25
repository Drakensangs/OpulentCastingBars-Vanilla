-- ============================================================
--  Opulent Casting Bars -- Compat.lua  (vanilla 1.12.1 / ClassicAPI)
--
--  Reveal-mask helpers shared by the bar and the FX modules.
--  Mask textures, C_Timer, SetShown etc. come from ClassicAPI (a hard
--  dependency), so no fallback shims are needed.
-- ============================================================

-- ------------------------------------------------------------
--  Reveal masks
--
--  Outside its own rectangle a ClassicAPI mask repeats its EDGE alpha,
--  so a mask with an opaque edge (e.g. WHITE8X8) clips nothing.
--
--  A reveal mask is two masks used together (masks intersect):
--   * the mask itself, RevealMaskFull: white with a transparent 1-texel
--     border, laid out by its owner over the revealed rectangle. It clips
--     the left, top and bottom (and, at its right edge, the far side).
--   * its edge companion (m._scbEdge), RevealMaskEdge: a 64x4 ramp, opaque
--     on its left quarter and transparent on its right quarter. Outside its
--     rectangle it repeats those columns, so it shows everything behind the
--     front and hides everything past it, with a smooth feather of any
--     width between. It follows the mask's leading edge.
--  The feather width is set in px, independent of the mask's size: during
--  a cast it is FEATHER of the revealed width (the look of the original
--  feathered RevealMask, whose profile RevealMaskEdge reproduces), and over
--  the last 15% of the cast it narrows smoothly to FEATHER_END of the width,
--  so the front stays soft (never a hard moving edge) up to the end. When
--  the bar completes, the narrow tip fills in over REVEAL_SETTLE_SECONDS and
--  the completed bar is shown in full.
--  Masks are sampled sub-pixel, so the edge moves smoothly.
--  Textures must take both masks: use SCB.AttachMask(t, m).
-- ------------------------------------------------------------
local REVEAL_MASK_PATH = "Interface\\AddOns\\OpulentCastingBars\\textures\\masks\\RevealMask"
SCB.REVEAL_MASK_FULL = REVEAL_MASK_PATH .. "Full"
SCB.REVEAL_MASK_EDGE = REVEAL_MASK_PATH .. "Edge"

-- Feather geometry, as shares of the mask's width: the original feather
-- ran from texel 209.5 to 253.5 of the 256-px RevealMask.
local FEATHER_START = 209.5 / 256   -- feather start, during the cast
local FEATHER_STOP  = 253.5 / 256   -- feather end (fully hidden), during the cast
local FEATHER_END   = 0.035         -- feather width near completion
local FEATHER_MIN   = 3             -- px; keeps the 64-px ramp off its last 2 mips
-- Middle of the cast feather (half-visible point), as a share of the mask
-- width: where the soft edge of an emptying bar visually sits.
SCB.REVEAL_FEATHER_MID = (FEATHER_START + FEATHER_STOP) * 0.5

local revealMasks = {}               -- every mask that has used the helpers below
local revealDriver = CreateFrame("Frame")
revealDriver:Hide()
local REVEAL_SETTLE_SECONDS = 0.18   -- time to ease across a jump of the blend target
local REVEAL_JUMP = 0.1              -- larger target changes (pushback, a new state) are eased

-- Place m's edge companion for the mask's width and blend (0 = cast
-- feather, 1 = completion feather). Only re-anchored when it changes.
local function LayoutRevealEdge(m)
    local e = m._scbEdge
    if not e then return end
    local w = m._scbRevealW or 1
    local b = math.max(0, math.min(1, m._scbRevealBlend or 0))
    local c = math.max(0, math.min(1, m._scbRevealDone or 0))
    c = c * c * (3 - 2 * c)
    -- The feather ends at the front (the mask's end once b = 1) ...
    local width = w * ((FEATHER_STOP - FEATHER_START) * (1 - b) + FEATHER_END * b)
    local stop  = w * (FEATHER_STOP + (1 - FEATHER_STOP) * b)
    width = math.max(FEATHER_MIN, width)
    -- ... and once the bar is complete it slides past the end (c = 1), where
    -- the mask itself clips it: the front stays put and its soft tip fills
    -- in, so a completed bar is shown in full, as before.
    stop = stop + c * width
    -- The ramp spans the middle half of the edge mask: its rectangle runs
    -- from stop - 1.5 * width to stop + 0.5 * width (from the anchor side).
    local x = stop + 0.5 * width - w
    local mirror = m._scbRevealMirror and true or false
    if e._x and math.abs(e._x - x) < 0.01 and math.abs(e._w - width) < 0.01
       and e._mirror == mirror then return end
    -- SetPoint replaces an anchor of the same name: clear the anchors only
    -- when the side changes, and skip the calls whose value is unchanged.
    if e._mirror ~= mirror then
        e:ClearAllPoints()
        e._x = nil
    end
    e._mirror = mirror
    if e._x ~= x then
        e._x = x
        if mirror then
            e:SetPoint("TOPLEFT",    m, "TOPLEFT",    -x, 0)
            e:SetPoint("BOTTOMLEFT", m, "BOTTOMLEFT", -x, 0)
        else
            e:SetPoint("TOPRIGHT",    m, "TOPRIGHT",    x, 0)
            e:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", x, 0)
        end
    end
    if e._w ~= width then
        e._w = width
        e:SetWidth(2 * width)
    end
end

local function ApplyRevealBlend(m, blend)
    m._scbRevealBlend = math.max(0, math.min(1, blend))
    LayoutRevealEdge(m)
end

-- Drive a mask's feather from cast progress: the cast feather until 85%,
-- then easing to the completion feather by 100%, so a filling bar ends
-- full with only a narrow soft front.
-- An emptying bar (channels, reverse fills: SCB.Bar.fillEmptying) starts
-- full and its leading edge moves away from 100%, so it keeps the cast
-- feather the whole time; masks marked with SCB.SetRevealMaskFixed (flash
-- copies, artwork revealed by its own fraction) keep the normal ramp.
-- The feather follows steady progress exactly; jumps of the target are
-- eased over REVEAL_SETTLE_SECONDS by revealDriver.
function SCB.SetRevealMaskProgress(m, progress)
    if not m or not m.SetTexture then return end
    if not m._scbRevealRegistered then
        m._scbRevealRegistered = true
        revealMasks[#revealMasks + 1] = m
    end
    progress = math.max(0, math.min(1, progress or 0))
    local target = 0
    if m._scbRevealFixed or not (SCB.Bar and SCB.Bar.fillEmptying) then
        local t = math.max(0, math.min(1, (progress - 0.85) / 0.15))
        target = t * t * (3 - 2 * t)
    end
    local previous = m._scbRevealProgress
    m._scbRevealProgress = progress
    -- At full progress, settle the tip unless this is a non-fixed emptying mask.
    local done = (progress >= 1 and (m._scbRevealFixed or not (SCB.Bar and SCB.Bar.fillEmptying))) and 1 or 0
    if done == 0 then
        if (m._scbRevealDone or 0) ~= 0 then
            m._scbRevealDone = 0
            LayoutRevealEdge(m)
        end
    elseif (m._scbRevealDone or 0) < 1 then
        revealDriver:Show()
    end
    m._scbRevealDoneTarget = done
    if m._scbRevealBlendSet == nil or (progress == 0 and previous ~= 0) then
        -- A new cast must start feathered, not inherit its predecessor.
        m._scbRevealBlendSet = true
        m._scbRevealTarget = target
        m._scbRevealElapsed = REVEAL_SETTLE_SECONDS
        ApplyRevealBlend(m, target)
        return
    end
    if m._scbRevealTarget == target then return end
    m._scbRevealTarget = target
    if (m._scbRevealElapsed or REVEAL_SETTLE_SECONDS) < REVEAL_SETTLE_SECONDS then
        return   -- easing: the driver eases toward the moving target
    end
    if math.abs(target - (m._scbRevealBlend or 0)) <= REVEAL_JUMP then
        ApplyRevealBlend(m, target)   -- continuous cast progress: follow it exactly
    else
        m._scbRevealFrom = m._scbRevealBlend
        m._scbRevealElapsed = 0
        revealDriver:Show()
    end
end

-- Eases masks toward their target blend, including after the cast has
-- stopped and the mask no longer receives progress updates. Hides itself
-- when nothing is settling, so it costs nothing between casts.
revealDriver:SetScript("OnUpdate", function(self, elapsed)
    elapsed = math.max(0, elapsed or 0)
    local busy = false
    for _, m in ipairs(revealMasks) do
        if m._scbRevealDoneTarget == 1 and (m._scbRevealDone or 0) < 1 then
            busy = true
            m._scbRevealDone = math.min(1, (m._scbRevealDone or 0) + elapsed / REVEAL_SETTLE_SECONDS)
            LayoutRevealEdge(m)
        end
        if (m._scbRevealElapsed or REVEAL_SETTLE_SECONDS) < REVEAL_SETTLE_SECONDS then
            busy = true
            m._scbRevealElapsed = math.min(REVEAL_SETTLE_SECONDS, m._scbRevealElapsed + elapsed)
            local t = m._scbRevealElapsed / REVEAL_SETTLE_SECONDS
            local ease = t * t * (3 - 2 * t)
            ApplyRevealBlend(m, m._scbRevealFrom + (m._scbRevealTarget - m._scbRevealFrom) * ease)
        end
    end
    if not busy then revealDriver:Hide() end
end)

-- Exempt a mask from the emptying-bar rule above: its feather always
-- follows its own progress (e.g. a flash copy shown at progress 1).
function SCB.SetRevealMaskFixed(m)
    if m then m._scbRevealFixed = true end
end

-- Put a mask on `blend` (0 = feathered, 1 = unfeathered) at once, with no
-- easing. Used for copies that must not inherit an in-between state, e.g.
-- the completion flash after a partial (cancelled-cast) flash.
function SCB.SetRevealMaskBlendNow(m, blend, progress)
    if not m or not m.SetTexture then return end
    if not m._scbRevealRegistered then
        m._scbRevealRegistered = true
        revealMasks[#revealMasks + 1] = m
    end
    blend = math.max(0, math.min(1, blend or 0))
    m._scbRevealProgress = progress or m._scbRevealProgress or 1
    -- unfeathered at full progress: the whole region, at once
    local done = (blend >= 1 and m._scbRevealProgress >= 1) and 1 or 0
    m._scbRevealDone, m._scbRevealDoneTarget = done, done
    m._scbRevealBlendSet = true
    m._scbRevealFrom     = blend
    m._scbRevealTarget   = blend
    m._scbRevealElapsed  = REVEAL_SETTLE_SECONDS
    ApplyRevealBlend(m, blend)
end

-- Give `dst` exactly the feather state of `src`, including an easing in
-- progress, so the driver keeps both identical from then on. Used to make
-- a flash copy match the visible fill's front.
function SCB.MatchRevealMask(dst, src)
    if not dst or not src or not dst.SetTexture then return end
    if not dst._scbRevealRegistered then
        dst._scbRevealRegistered = true
        revealMasks[#revealMasks + 1] = dst
    end
    local blend = src._scbRevealBlend or 0
    dst._scbRevealProgress = src._scbRevealProgress
    dst._scbRevealDone       = src._scbRevealDone
    dst._scbRevealDoneTarget = src._scbRevealDoneTarget
    dst._scbRevealBlendSet = true
    dst._scbRevealFrom     = src._scbRevealFrom or blend
    dst._scbRevealTarget   = src._scbRevealTarget or blend
    dst._scbRevealElapsed  = src._scbRevealElapsed or REVEAL_SETTLE_SECONDS
    ApplyRevealBlend(dst, blend)
    if (dst._scbRevealElapsed or REVEAL_SETTLE_SECONDS) < REVEAL_SETTLE_SECONDS
       or (dst._scbRevealDoneTarget == 1 and (dst._scbRevealDone or 0) < 1) then
        revealDriver:Show()
    end
end

-- Create a feathered reveal mask (and its edge companion) on parent.
-- The mask's width is the revealed width (its owner sets it with
-- SetWidth); the companion follows the mask's leading edge.
function SCB.NewRevealMask(parent)
    local m = parent:CreateMaskTexture()
    m:SetTexture(SCB.REVEAL_MASK_FULL)
    local e = parent:CreateMaskTexture()
    e:SetTexture(SCB.REVEAL_MASK_EDGE)
    m._scbEdge = e
    local SetWidth = m.SetWidth
    m.SetWidth = function(self, w)
        w = math.max(1, w or 1)
        -- Most callers set the width every tick: skip the call when it is
        -- unchanged (the edge still re-checks, it may have a newer feather).
        if w ~= self._scbRevealW then
            SetWidth(self, w)
            self._scbRevealW = w
        end
        LayoutRevealEdge(self)
    end
    -- _scbRevealW stays nil (read as 1) so the owner's first SetWidth applies.
    SCB.SetRevealMaskProgress(m, 0)
    return m
end

-- Clip texture t with mask m, and with m's edge companion if m is a
-- reveal mask. Use this instead of t:AddMaskTexture(m) for every mask.
function SCB.AttachMask(t, m)
    if not t or not m then return end
    t:AddMaskTexture(m)
    if m._scbEdge then t:AddMaskTexture(m._scbEdge) end
end

-- Put the feather on the left edge, for fills that grow right to left
-- (the mask must then be anchored by its right side). The full mask is
-- symmetric, so a 180-degree rotation turns the edge ramp only.
function SCB.SetRevealMaskMirrored(m, mirrored)
    if not m then return end
    m._scbRevealMirror = mirrored and true or nil
    if m._scbEdge then
        m._scbEdge:SetRotation(mirrored and math.pi or 0)
        LayoutRevealEdge(m)
    else
        m:SetRotation(mirrored and math.pi or 0)
    end
end

-- Reveal full-size artwork on frame from the left, revealW px wide.
-- A two-texel pad (of the 256-px mask) keeps the mask's transparent border
-- just outside the artwork on the left, top, bottom and, when complete, right.
function SCB.LayoutArtworkRevealMask(mask, frame, revealW, progress)
    if not mask or not frame then return end
    revealW = math.max(1, revealW or 1)
    local padX = revealW * 2 / 252
    local padY = frame:GetHeight() * 2 / 252
    mask:ClearAllPoints()
    mask:SetPoint("TOPLEFT", frame, "TOPLEFT", -padX, padY)
    mask:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -padX, -padY)
    mask:SetWidth(revealW + 2 * padX)
    SCB.SetRevealMaskProgress(mask, progress)
end
