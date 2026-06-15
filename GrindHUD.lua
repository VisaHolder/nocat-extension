-- GrindHUD.lua  (live grind-efficiency HUD: kills/hr, XP/hr, gold/hr, ETA + XP bar)
--
-- Samples UnitXP/GetMoney on a throttled OnUpdate that is ONLY set while the HUD
-- is shown (never idles every frame). It deliberately does NOT register
-- PLAYER_XP_UPDATE: ExpTracker already owns that event through AceEvent, which
-- keeps a single handler per event — re-registering here would clobber it.
-- Polling at REFRESH is cheap and keeps the two modules fully decoupled. Kills
-- are fed by the shared kill callback (event-accurate); everything else is
-- sampled on the tick.
local _, NCE = ...

local REFRESH = 0.5            -- seconds between HUD samples (only while shown)

-- 1234 -> "1,234"; 12345 -> "12.3k"; 1234567 -> "1.23M"  (compact, for rates)
local function shortNum(n)
    n = n or 0
    if n >= 1e6 then return string.format('%.2fM', n / 1e6) end
    if n >= 1e4 then return string.format('%.1fk', n / 1e3) end
    return NCE:commas(n)
end

local function goldStr(copper)
    return NCE:commas(math.floor((copper or 0) / 10000)) .. 'g'
end

-- seconds -> "45s" / "8m" / "1h20m"
local function etaStr(sec)
    if not sec or sec <= 0 or sec ~= sec or sec == math.huge then return '—' end
    sec = math.floor(sec)
    local h = math.floor(sec / 3600)
    local m = math.floor(sec % 3600 / 60)
    if h > 0 then return string.format('%dh%02dm', h, m) end
    if m > 0 then return string.format('%dm', m) end
    return string.format('%ds', sec)
end

-- "Arcane Surge" bar look: white-tinted fill carrying a vertical gloss gradient
-- (light top → deep bottom), a top sheen, and an additive SPARK glow riding the
-- fill's leading edge. topC/botC = {r,g,b} (0-1). Call bar.applyGradient() after
-- SetValue (some clients drop the gradient on a value change). Spark is bar.spark
-- (hide it at 0/full). Set the bar's size BEFORE calling.
local function styleBar(bar, topC, botC)
    bar:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8')
    bar:SetStatusBarColor(1, 1, 1)
    bar.applyGradient = function()
        local tx = bar:GetStatusBarTexture()
        if tx and tx.SetGradient and CreateColor then
            -- 12.0 signature: SetGradient(orientation, minColor, maxColor); for
            -- VERTICAL, min = bottom edge, max = top edge.
            pcall(tx.SetGradient, tx, 'VERTICAL',
                CreateColor(botC[1], botC[2], botC[3], 1),
                CreateColor(topC[1], topC[2], topC[3], 1))
        end
    end
    bar.applyGradient()

    local tex = bar:GetStatusBarTexture()
    local h   = bar:GetHeight() or 9

    -- dark track behind the fill
    local trk = bar:CreateTexture(nil, 'BACKGROUND')
    trk:SetAllPoints(bar)
    trk:SetColorTexture(1, 1, 1, 0.06)

    -- glossy sheen across the top half of the FILL (anchored to the fill, so it
    -- shrinks/grows with the value)
    local sheen = bar:CreateTexture(nil, 'ARTWORK')
    sheen:SetTexture('Interface\\Buttons\\WHITE8X8')   -- gradient below supplies the alpha fade
    sheen:SetPoint('TOPLEFT',  tex, 'TOPLEFT',  0, 0)
    sheen:SetPoint('TOPRIGHT', tex, 'TOPRIGHT', 0, 0)
    sheen:SetHeight(math.max(2, h * 0.5))
    if sheen.SetGradient and CreateColor then
        pcall(sheen.SetGradient, sheen, 'VERTICAL', CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.38))
    end

    -- additive leading-edge spark; pinned to the fill's right edge so it follows
    local spark = bar:CreateTexture(nil, 'OVERLAY')
    -- Maintained atlas first (TWW reorganized many Interface\ path strings; prefer
    -- atlas/fileID per the addon's texture rule), raw casting-bar spark as fallback.
    if not pcall(spark.SetAtlas, spark, 'UI-CastingBar-Spark', false) then
        spark:SetTexture('Interface\\CastingBar\\UI-CastingBar-Spark')
    end
    spark:SetBlendMode('ADD')
    spark:SetSize(16, h * 2.2)
    spark:SetPoint('CENTER', tex, 'RIGHT', 0, 0)
    bar.spark = spark
end

-- Total free slots across all carried bags (backpack 0 .. reagent bag). Returns
-- nil if the container API is unavailable (don't render a bogus 0).
local function bagFreeSlots()
    local cc = C_Container
    if not cc or not cc.GetContainerNumFreeSlots then return nil end
    local maxBag = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
    local free = 0
    for bag = 0, maxBag do
        local n = cc.GetContainerNumFreeSlots(bag)
        if n then free = free + n end
    end
    return free
end

function NCE:InitGrindHUD()
    local f = CreateFrame('Frame', 'NCEGrindHUD', UIParent, 'BackdropTemplate')
    f:SetSize(196, 150)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag('LeftButton')
    f:SetScript('OnDragStart', f.StartMoving)
    f:SetScript('OnDragStop', function(self)
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        local pos = NCE.db.global.hud.position
        pos.point = point; pos.relative = relative; pos.x = x; pos.y = y
    end)
    -- Clean flat dark panel + thin accent border (no parchment texture).
    f:SetBackdrop({
        bgFile   = 'Interface\\Buttons\\WHITE8X8',
        edgeFile = 'Interface\\Buttons\\WHITE8X8',
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
    f:SetBackdropBorderColor(0.45, 0.32, 0.70, 0.9)
    f:Hide()

    local pos = self.db.global.hud.position
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relative, pos.x, pos.y)
    else
        f:SetPoint('CENTER', UIParent, 'CENTER', 300, 0)
    end

    local title = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    title:SetPoint('TOPLEFT', f, 'TOPLEFT', 12, -10)
    title:SetText(NCE:cc('ffffd700', 'nocat.'))

    -- thin separator under the title
    local sep = f:CreateTexture(nil, 'ARTWORK')
    sep:SetHeight(1)
    sep:SetPoint('TOPLEFT', f, 'TOPLEFT', 10, -28)
    sep:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -10, -28)
    sep:SetColorTexture(1, 1, 1, 0.09)

    -- minimal × close (no chunky red button)
    local closeBtn = CreateFrame('Button', nil, f)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -6, -6)
    local cx = closeBtn:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    cx:SetPoint('CENTER')
    cx:SetText('×')
    cx:SetTextColor(0.55, 0.55, 0.62)
    closeBtn:SetScript('OnEnter', function() cx:SetTextColor(0.95, 0.4, 0.4) end)
    closeBtn:SetScript('OnLeave', function() cx:SetTextColor(0.55, 0.55, 0.62) end)
    closeBtn:SetScript('OnClick', function() NCE:HideGrindHUD() end)

    -- Stat rows: muted label (left) + bright value (right)
    local function row(yOff)
        local l = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
        l:SetPoint('TOPLEFT', f, 'TOPLEFT', 12, yOff)
        l:SetTextColor(0.60, 0.60, 0.68)
        local v = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        v:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -12, yOff)
        v:SetJustifyH('RIGHT')
        return l, v
    end
    f.timeL, f.timeV = row(-38)
    f.killL, f.killV = row(-57)
    f.xpL,   f.xpV   = row(-76)
    f.goldL, f.goldV = row(-95)
    f.bagL,  f.bagV  = row(-114)
    f.timeL:SetText('Time')
    f.killL:SetText('Kills')
    f.xpL:SetText('XP/hr')
    f.goldL:SetText('Gold/hr')
    f.bagL:SetText('Bags')

    -- XP-to-next-level bar (Arcane Surge purple). Position is set by LayoutGrindHUD.
    local bar = CreateFrame('StatusBar', nil, f)
    bar:SetSize(172, 9)
    bar:SetPoint('TOPLEFT', f, 'TOPLEFT', 12, -132)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    styleBar(bar, { 0.725, 0.549, 0.941 }, { 0.353, 0.184, 0.620 })   -- Arcane Surge: #b98cf0 top → #5a2f9e bottom
    f.bar = bar

    f.barText = f:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    f.barText:SetPoint('TOP', bar, 'BOTTOM', 0, -5)

    -- Farm-goal section (Arcane Surge GOLD bar). Hidden until a goal is set; the
    -- label, bar, and caption are re-anchored each layout pass by LayoutGrindHUD.
    f.goalLabel = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    f.goalLabel:SetPoint('TOPLEFT', f, 'TOPLEFT', 12, -160)
    f.goalLabel:SetTextColor(0.85, 0.69, 0.30)

    local gbar = CreateFrame('StatusBar', nil, f)
    gbar:SetSize(172, 9)
    gbar:SetPoint('TOPLEFT', f, 'TOPLEFT', 12, -176)
    gbar:SetMinMaxValues(0, 1)
    gbar:SetValue(0)
    styleBar(gbar, { 0.953, 0.831, 0.525 }, { 0.604, 0.431, 0.071 })  -- gold: #f3d486 top → #9a6e12 bottom
    f.goalBar = gbar

    f.goalText = f:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    f.goalText:SetPoint('TOP', gbar, 'BOTTOM', 0, -5)

    f.goalLabel:Hide(); f.goalBar:Hide(); f.goalText:Hide()

    -- OnUpdate sampler — only ever set while the HUD is shown.
    f.onUpdate = function(self, elapsed)
        self.acc = (self.acc or 0) + elapsed
        if self.acc < REFRESH then return end
        self.acc = 0
        NCE:SampleGrindHUD()
        NCE:UpdateGrindHUD()
    end

    f.active = false
    f.kills  = 0
    self.hudFrame = f

    -- Kills are event-accurate via the shared callback (RecordKill), not polled.
    self:AddKillCallback(function(id, name)
        local h = NCE.hudFrame
        if h and h.active then h.kills = h.kills + 1 end
        NCE:GoalOnKill(id, name)
    end)
end

-- (Re)start a fresh grind session and begin sampling.
function NCE:ShowGrindHUD()
    local f = self.hudFrame
    if not f then return end
    f.kills     = 0
    f.startTime = GetTime()
    f.startGold = GetMoney() or 0
    f.lastXP    = UnitXP('player') or 0
    f.lastXPMax = UnitXPMax('player') or 0
    f.xpGained  = 0
    f.acc       = 0
    f.active    = true
    -- Anchor the goal ETA clock to this session's start so its rate is "kills
    -- since the HUD opened", not lifetime.
    local g = self.db.global.hud and self.db.global.hud.goal
    if g then self.goalAnchor = { got = g.got or 0, t = GetTime() } end
    f:SetScript('OnUpdate', f.onUpdate)
    f:Show()
    self:UpdateGrindHUD()
end

function NCE:HideGrindHUD()
    local f = self.hudFrame
    if not f then return end
    f.active = false
    f:SetScript('OnUpdate', nil)
    f:Hide()
end

function NCE:ToggleGrindHUD()
    local f = self.hudFrame
    if not f then return end
    if f:IsShown() then self:HideGrindHUD() else self:ShowGrindHUD() end
end

-- Accumulate XP across level-ups: UnitXP resets to 0 when you ding, so a
-- negative delta means we finished the previous level (lastXPMax - lastXP) and
-- carried progress into the new one (cur).
function NCE:SampleGrindHUD()
    local f = self.hudFrame
    if not f then return end
    local cur = UnitXP('player') or 0
    local max = UnitXPMax('player') or 0
    if cur >= (f.lastXP or 0) then
        f.xpGained = (f.xpGained or 0) + (cur - (f.lastXP or 0))
    else
        f.xpGained = (f.xpGained or 0) + ((f.lastXPMax or 0) - (f.lastXP or 0)) + cur
    end
    f.lastXP    = cur
    f.lastXPMax = max
end

function NCE:UpdateGrindHUD()
    local f = self.hudFrame
    if not f then return end
    local elapsed = math.max(GetTime() - (f.startTime or GetTime()), 0.001)
    local hrs     = elapsed / 3600

    f.timeV:SetText(self:TimerFmt(math.floor(elapsed)))
    f.killV:SetText(string.format('%s  ·  %s/hr', self:commas(f.kills), shortNum(f.kills / hrs)))

    -- Bags: free slots, reddened when nearly full.
    local free = bagFreeSlots()
    if free then
        f.bagV:SetText(free .. ' free')
        if free <= 5 then f.bagV:SetTextColor(0.96, 0.36, 0.36)
        else f.bagV:SetTextColor(0.93, 0.93, 0.96) end
    else
        f.bagV:SetText('—')
    end

    local cur   = UnitXP('player') or 0
    local max   = UnitXPMax('player') or 0
    local atMax = (max <= 0) or (IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel())

    f.xpV:SetText(atMax and '—' or shortNum((f.xpGained or 0) / hrs))
    f.goldV:SetText(goldStr(((GetMoney() or 0) - (f.startGold or 0)) / hrs))

    if not atMax then
        f.bar:SetMinMaxValues(0, max)
        f.bar:SetValue(cur)
        if f.bar.applyGradient then f.bar.applyGradient() end
        if f.bar.spark then f.bar.spark:SetShown(cur > 0 and cur < max) end
        local xpHr    = (f.xpGained or 0) / hrs
        local eta     = xpHr > 0 and ((max - cur) / xpHr * 3600) or nil
        local nextLvl = (UnitLevel('player') or 0) + 1
        -- "XP" labels the counter (bare numbers read ambiguously — could be gold),
        -- and "Lv 71 in ~14m" spells out the target level + ETA (was cryptic "to 71").
        -- Drop the time clause until a rate exists, so it never shows "in ~—".
        local tail = eta and string.format('Lv %d in ~%s', nextLvl, etaStr(eta))
                          or string.format('Lv %d', nextLvl)
        f.barText:SetText(string.format('XP %s / %s  ·  %s', self:commas(cur), self:commas(max), tail))
    end

    -- Farm goal: progress + ETA from kills of the target mob this session.
    local g = self.db.global.hud and self.db.global.hud.goal
    if g then
        local got = math.min(g.got or 0, g.target)
        f.goalBar:SetMinMaxValues(0, math.max(g.target, 1))
        f.goalBar:SetValue(got)
        if f.goalBar.applyGradient then f.goalBar.applyGradient() end
        if f.goalBar.spark then f.goalBar.spark:SetShown(got > 0 and got < g.target) end
        f.goalLabel:SetText('Goal · ' .. (g.name or '?'))

        local eta
        local a = self.goalAnchor
        if a and (g.got or 0) > a.got then
            local rate = ((g.got or 0) - a.got) / math.max(GetTime() - a.t, 0.001)   -- per second
            if rate > 0 then eta = (g.target - (g.got or 0)) / rate end
        end
        local tail = ((g.got or 0) >= g.target) and 'done' or (etaStr(eta) .. ' left')
        f.goalText:SetText(string.format('%s / %s  ·  %s', self:commas(got), self:commas(g.target), tail))
    end

    self:LayoutGrindHUD(atMax, g ~= nil)
end

-- Show/hide + stack the XP bar and goal section, then crop the frame height so
-- there's never an empty region. atMax hides the XP bar; hasGoal shows the gold
-- section beneath it.
function NCE:LayoutGrindHUD(atMax, hasGoal)
    local f = self.hudFrame
    if not f then return end
    local y = -132            -- first stackable row, just below the Bags line (-114)

    if atMax then
        f.bar:Hide(); f.barText:Hide()
    else
        f.bar:Show(); f.barText:Show()
        f.bar:ClearAllPoints()
        f.bar:SetPoint('TOPLEFT', f, 'TOPLEFT', 12, y)
        y = y - 27            -- bar (9) + caption (~18)
    end

    if hasGoal then
        f.goalLabel:Show(); f.goalBar:Show(); f.goalText:Show()
        f.goalLabel:ClearAllPoints()
        f.goalLabel:SetPoint('TOPLEFT', f, 'TOPLEFT', 12, y - 2)
        f.goalBar:ClearAllPoints()
        f.goalBar:SetPoint('TOPLEFT', f, 'TOPLEFT', 12, y - 18)
        y = y - 45            -- label (~16) + bar (9) + caption (~18) + gaps
    else
        f.goalLabel:Hide(); f.goalBar:Hide(); f.goalText:Hide()
    end

    f:SetHeight(math.max(120, -y + 6))
end

-- Set a farm goal: count kills of a specific mob from now until `target` is hit.
-- idOrName: a numeric NPC id, a mob name string, or nil to use the current target.
function NCE:SetGoal(target, idOrName)
    target = tonumber(target)
    if not target or target <= 0 then
        self:Msg('Usage: /nocat goal <count> [mob name or npc id]  (omit the name to use your target)')
        return
    end

    local id, name
    if idOrName == nil or idOrName == '' then
        if UnitExists('target') and not UnitIsPlayer('target') then
            id   = self:npcFromGUID(UnitGUID('target'))
            name = UnitName('target')
        else
            self:Msg('No mob targeted — target one, or pass a name: /nocat goal ' .. target .. ' Murloc')
            return
        end
    elseif tonumber(idOrName) then
        id = tonumber(idOrName)
    else
        name = idOrName
    end

    self.db.global.hud.goal = { id = id, name = name or ('NPC #' .. tostring(id)), target = target, got = 0 }
    self.goalAnchor = { got = 0, t = GetTime() }
    self:Msg(self:cc('ffffd700', 'Farm goal set: ') .. self:commas(target) .. ' × ' .. (name or ('NPC #' .. tostring(id))))
    if self.hudFrame and not self.hudFrame:IsShown() then self:ShowGrindHUD() else self:UpdateGrindHUD() end
end

function NCE:ClearGoal()
    if not (self.db.global.hud and self.db.global.hud.goal) then
        self:Msg('No farm goal set.')
        return
    end
    self.db.global.hud.goal = nil
    self.goalAnchor = nil
    self:Msg('Farm goal cleared.')
    self:UpdateGrindHUD()
end

-- Increment the active goal when a matching mob dies (by NPC id if known, else by
-- name). Counts even while the HUD is hidden, and caps at the target.
function NCE:GoalOnKill(id, name)
    local g = self.db.global.hud and self.db.global.hud.goal
    if not g or (g.got or 0) >= g.target then return end
    local match
    if g.id then
        match = (id == g.id)
    elseif g.name and name then
        match = (string.lower(name) == string.lower(g.name))
    end
    if not match then return end
    g.got = (g.got or 0) + 1
    if g.got >= g.target then
        self:Msg(self:cc('ffffd700', 'Farm goal complete! ') .. self:commas(g.target) .. ' × ' .. (g.name or '?'))
        if RaidNotice_AddMessage and RaidBossEmoteFrame then
            RaidNotice_AddMessage(RaidBossEmoteFrame, 'Farm goal complete: ' .. (g.name or '?') .. '!', ChatTypeInfo and ChatTypeInfo['SYSTEM'])
        end
    end
end
