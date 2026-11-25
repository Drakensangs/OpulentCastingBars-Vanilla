-- ============================================================
--  Opulent Casting Bars -- Precache.lua
--
--  Renders the addon's textures once on a hidden, near-invisible
--  1x1 warmer, a few per frame, so their first load is paid up
--  front instead of on the first real cast.
--
--  Start()            : "Pre-warm textures on login" option.
--                       Warms every style, default style first.
--                       The default style's textures stay referenced
--                       (held on hidden regions) so they remain loaded;
--                       the rest are warmed once and then released,
--                       which mostly helps the disk/file cache.
--  StartSchool(key,n) : warms one style, n textures per frame (used for
--                       Inferno and Void at login).
-- ============================================================

SCB.Precache = {}

local BATCH_PER_FRAME = 3

-- Every unique texture path under `base` found anywhere in `root`
-- (style definitions are walked recursively, whatever the field name).
local function CollectPaths(root, base)
    local seen, list = {}, {}
    local function collect(v)
        local t = type(v)
        if t == "string" then
            if not seen[v] and v:find(base, 1, true) then
                seen[v] = true
                list[#list + 1] = v
            end
        elseif t == "table" then
            for _, vv in pairs(v) do collect(vv) end
        end
    end
    collect(root)
    return list
end

-- Show `batch` textures per frame on an almost invisible 1x1 frame.
-- keep(path) -> true gives that texture its own region so it stays loaded.
local function Warm(list, batch, keep, onDone)
    local warmer = CreateFrame("Frame", nil, UIParent)
    warmer:SetFrameStrata("BACKGROUND")
    warmer:SetSize(1, 1)
    warmer:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    warmer:SetAlpha(0.004)   -- > 0 so children truly render, but imperceptible

    local function NewTex()
        local tex = warmer:CreateTexture(nil, "ARTWORK")
        tex:SetSize(1, 1)
        tex:SetPoint("BOTTOMLEFT", warmer, "BOTTOMLEFT", 0, 0)
        tex:Hide()
        return tex
    end
    local pool = {}
    for i = 1, batch do pool[i] = NewTex() end

    local idx, shown = 0, {}
    warmer:SetScript("OnUpdate", function(self)
        -- Hide last frame's batch, then show the next one.
        for i = 1, #shown do shown[i]:Hide(); shown[i] = nil end
        if idx >= #list then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            -- Release the pooled textures (they are only needed while warming).
            for i = 1, #pool do pool[i]:SetTexture(nil) end
            if onDone then onDone() end
            return
        end
        for i = 1, batch do
            if idx >= #list then break end
            idx = idx + 1
            local path = list[idx]
            local tex = (keep and keep(path)) and NewTex() or pool[i]
            tex:SetTexture(path)
            tex:Show()
            shown[#shown + 1] = tex
        end
    end)
end

function SCB.Precache:Start()
    if self._started then return end
    self._started = true
    local base = SCB.TEX_PATH
    if not (base and SCB.Schools and SCB.Schools.data) then return end

    local list = CollectPaths(SCB.Schools.data, base)
    if #list == 0 then return end

    -- Default school first, and kept loaded: it is the most likely first cast.
    local ds = SCB.Config and SCB.Config:Get("defaultSchool")
    local keepSet = {}
    if ds and SCB.Schools.data[ds] then
        for _, p in ipairs(CollectPaths(SCB.Schools.data[ds], base)) do keepSet[p] = true end
    end
    table.sort(list, function(a, b)
        local pa, pb = keepSet[a] and 0 or 1, keepSet[b] and 0 or 1
        if pa ~= pb then return pa < pb end
        return a < b
    end)

    Warm(list, BATCH_PER_FRAME, function(p) return keepSet[p] end,
        function() SCB.Precache._done = true end)
end

-- Warm one style's textures (once per session; deferred out of combat).
function SCB.Precache:StartSchool(schoolKey, batchPerFrame)
    if not schoolKey or self._done then return end
    self._schoolStarted = self._schoolStarted or {}
    if self._schoolStarted[schoolKey] then return end

    if InCombatLockdown() then
        C_Timer.After(5, function() SCB.Precache:StartSchool(schoolKey, batchPerFrame) end)
        return
    end

    local base = SCB.TEX_PATH
    if not (base and SCB.Schools and SCB.Schools.data and SCB.Schools.data[schoolKey]) then return end
    local list = CollectPaths(SCB.Schools.data[schoolKey], base)
    if #list == 0 then return end
    table.sort(list)
    self._schoolStarted[schoolKey] = true

    Warm(list, math.max(1, tonumber(batchPerFrame) or 1), nil, nil)
end
