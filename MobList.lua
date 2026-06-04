-- MobList.lua  (Bestiary: searchable, sortable mob database with live 3D models)
--
-- Left half is the classic virtual-scroll kill table. Right half is a "trophy
-- pedestal": hover any mob and its actual in-game model spins on a pedestal,
-- with a per-mob bestiary rank and a progress bar toward your next kill
-- milestone. Drag the model to rotate it, mouse-wheel to zoom.
local _, NCE = ...

local NUM_ROWS = 24
local ROW_H    = 18
local FRAME_W  = 824
local FRAME_H  = 560

-- Right edge of the table area (x offset from the frame's left). Everything to
-- the right of this is the model/preview pedestal.
local LIST_RIGHT = 540

local COLS = {
    { key='id',    label='NPC ID', w=58,  j='LEFT'  },
    { key='name',  label='Name',   w=250, j='LEFT'  },
    { key='char',  label='Char',   w=78,  j='RIGHT' },
    { key='total', label='Total',  w=78,  j='RIGHT' },
}

local COL_START_X = 10
local HDR_Y       = -54
local ROWS_Y      = -72

-- Per-mob bestiary rank by total kills — pure flavour, but it gives each
-- creature a sense of progression as you farm it.
local RANKS = {
    { 0,     'Unranked'    },
    { 1,     'Acquainted'  },
    { 50,    'Hunter'      },
    { 250,   'Slayer'      },
    { 1000,  'Nemesis'     },
    { 5000,  'Executioner' },
    { 10000, 'Annihilator' },
    { 25000, 'Worldbane'   },
}
local function rankFor(total)
    local r = RANKS[1][2]
    for _, e in ipairs(RANKS) do
        if total >= e[1] then r = e[2] else break end
    end
    return r
end

-- ── Build ─────────────────────────────────────────────────────────────────────
function NCE:InitMobList()
    local f = CreateFrame('Frame', 'NCEListFrame', UIParent, 'BasicFrameTemplateWithInset')
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint('CENTER')
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag('LeftButton')
    f:SetScript('OnDragStart', f.StartMoving)
    f:SetScript('OnDragStop',  f.StopMovingOrSizing)
    f:SetFrameStrata('HIGH')
    f:Hide()
    f.TitleText:SetText('nocat — Bestiary')

    f.sortKey = 'total'
    f.sortAsc = false
    f.data    = {}

    local search = CreateFrame('EditBox', 'NCEListSearch', f, 'SearchBoxTemplate')
    search:SetSize(200, 24)
    search:SetPoint('TOPLEFT', f, 'TOPLEFT', 10, -28)
    search:SetScript('OnTextChanged', function() NCE:UpdateList() end)
    f.search = search

    local countLbl = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    countLbl:SetPoint('LEFT', search, 'RIGHT', 12, 0)
    f.countLbl = countLbl

    local sessLbl = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    sessLbl:SetPoint('TOPRIGHT', f, 'TOPLEFT', LIST_RIGHT, -32)
    sessLbl:SetJustifyH('RIGHT')
    f.sessLbl = sessLbl

    local sep = f:CreateTexture(nil, 'BACKGROUND')
    sep:SetHeight(1)
    sep:SetPoint('TOPLEFT',  f, 'TOPLEFT', 6, -50)
    sep:SetPoint('TOPRIGHT', f, 'TOPLEFT', LIST_RIGHT, -50)
    sep:SetColorTexture(0.35, 0.35, 0.35, 0.9)

    -- Column header buttons
    local x = COL_START_X
    for _, col in ipairs(COLS) do
        local btn = CreateFrame('Button', nil, f)
        btn:SetSize(col.w, 16)
        btn:SetPoint('TOPLEFT', f, 'TOPLEFT', x, HDR_Y)
        btn:SetNormalFontObject('GameFontNormalSmall')
        btn:SetHighlightFontObject('GameFontHighlightSmall')
        btn:SetText(col.label)
        btn:GetFontString():SetJustifyH('LEFT')
        local key = col.key
        btn:SetScript('OnClick', function()
            if f.sortKey == key then f.sortAsc = not f.sortAsc
            else f.sortKey = key; f.sortAsc = (key == 'name' or key == 'id') end
            NCE:UpdateList(true)
        end)
        x = x + col.w + 4
    end

    -- Rows
    local rows = {}
    for i = 1, NUM_ROWS do
        local row = CreateFrame('Button', nil, f)
        row:SetHeight(ROW_H)
        row:SetPoint('TOPLEFT',  f, 'TOPLEFT', COL_START_X - 2, ROWS_Y + -(i - 1) * ROW_H)
        row:SetPoint('TOPRIGHT', f, 'TOPLEFT', LIST_RIGHT,      ROWS_Y + -(i - 1) * ROW_H)
        row:Hide()

        local bg = row:CreateTexture(nil, 'BACKGROUND')
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
        row.bg = bg

        local cx = 2
        for _, col in ipairs(COLS) do
            local lbl = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
            lbl:SetPoint('LEFT', row, 'LEFT', cx, 0)
            lbl:SetWidth(col.w)
            lbl:SetJustifyH(col.j)
            row[col.key .. 'Lbl'] = lbl
            cx = cx + col.w + 4
        end

        row:SetScript('OnEnter', function(self)
            self.bg:SetColorTexture(0.25, 0.55, 1, 0.18)
            if self.rowData then NCE:PreviewMob(self.rowData) end
        end)
        row:SetScript('OnLeave', function(self)
            self.bg:SetColorTexture(1, 1, 1, self.altRow and 0.03 or 0)
        end)
        row:SetScript('OnClick', function(self)
            if self.rowData then
                NCE:PreviewMob(self.rowData)
                f.pinnedID = self.rowData.id
            end
        end)

        row.altRow = (i % 2 == 0)
        rows[i] = row
    end
    f.rows = rows

    local sf = CreateFrame('ScrollFrame', 'NCEListScroll', f, 'FauxScrollFrameTemplate')
    sf:SetPoint('TOPLEFT',     f, 'TOPLEFT', COL_START_X - 2, ROWS_Y)
    sf:SetPoint('BOTTOMRIGHT', f, 'BOTTOMLEFT', LIST_RIGHT, 56)
    sf:SetScript('OnVerticalScroll', function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, function()
            NCE:RefreshRows()
        end)
    end)
    f.scrollFrame = sf

    -- Mouse-wheel scrolling. FauxScrollFrameTemplate gives us a draggable bar
    -- but no wheel handler — and the row buttons are children of `f`, not of
    -- the scroll frame, so they also eat wheel events when hovered. Wire wheel
    -- on the scroll frame AND every row, all routing through the same helper.
    local WHEEL_STEP = 3
    local function wheelScroll(_, delta)
        local n      = #(f.data or {})
        local maxOff = math.max(0, n - NUM_ROWS)
        local cur    = FauxScrollFrame_GetOffset(sf) or 0
        local new    = math.max(0, math.min(maxOff, cur - delta * WHEEL_STEP))
        if new == cur then return end
        FauxScrollFrame_SetOffset(sf, new)
        if sf.ScrollBar and sf.ScrollBar.SetValue then
            sf.ScrollBar:SetValue(new * ROW_H)
        end
        NCE:RefreshRows()
    end
    sf:EnableMouseWheel(true)
    sf:SetScript('OnMouseWheel', wheelScroll)
    for _, r in ipairs(rows) do
        r:EnableMouseWheel(true)
        r:SetScript('OnMouseWheel', wheelScroll)
    end

    -- Pre-register the frame so OpenList() works even if the 3D pedestal below
    -- fails to build on some client. Without this, an early throw inside the
    -- preview block would leave self.listFrame nil → /nocat list silent.
    self.listFrame = f

    -- ── Right pedestal / preview ───────────────────────────────────────────────
    -- Wrapped in pcall: if anything in the PlayerModel + decorations chain throws
    -- (frame type unavailable, font template missing, etc.), the searchable
    -- table half still works and we record the error for /nocat debug.
    local _pedOk, _pedErr = pcall(function()
    local vSep = f:CreateTexture(nil, 'ARTWORK')
    vSep:SetWidth(1)
    vSep:SetPoint('TOP',    f, 'TOPLEFT', LIST_RIGHT + 7, -28)
    vSep:SetPoint('BOTTOM', f, 'BOTTOMLEFT', LIST_RIGHT + 7, 30)
    vSep:SetColorTexture(0.3, 0.3, 0.3, 0.9)

    local panelX = LIST_RIGHT + 16
    local preview = CreateFrame('Frame', nil, f)
    preview:SetPoint('TOPLEFT',     f, 'TOPLEFT',     panelX, -28)
    preview:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -12,    30)
    f.preview = preview

    local MODEL_H = 286

    -- Pedestal backdrop behind the model
    local mbg = preview:CreateTexture(nil, 'BACKGROUND')
    mbg:SetPoint('TOPLEFT', preview, 'TOPLEFT', 0, 0)
    mbg:SetPoint('TOPRIGHT', preview, 'TOPRIGHT', 0, 0)
    mbg:SetHeight(MODEL_H)
    mbg:SetColorTexture(0.04, 0.04, 0.06, 0.92)

    local mborder = preview:CreateTexture(nil, 'BORDER')
    mborder:SetPoint('TOPLEFT', mbg, 'BOTTOMLEFT', 0, 0)
    mborder:SetPoint('TOPRIGHT', mbg, 'BOTTOMRIGHT', 0, 0)
    mborder:SetHeight(2)
    mborder:SetColorTexture(1, 0.82, 0, 0.5)

    local model = CreateFrame('PlayerModel', nil, preview)
    model:SetPoint('TOPLEFT',  preview, 'TOPLEFT',  1, -1)
    model:SetPoint('TOPRIGHT', preview, 'TOPRIGHT', -1, -1)
    model:SetHeight(MODEL_H - 2)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model.facing  = 0.6
    model.autospin = true
    model.cam     = 1.0
    f.model = model

    -- Drag to rotate; wheel to zoom; gentle auto-spin when idle.
    model:SetScript('OnMouseDown', function(self)
        self.dragging   = true
        self.autospin   = false
        self.dragStartX = ({ GetCursorPosition() })[1]
        self.dragFacing = self.facing or 0
    end)
    model:SetScript('OnMouseUp', function(self) self.dragging = false end)
    model:SetScript('OnHide',    function(self) self.dragging = false end)
    model:SetScript('OnMouseWheel', function(self, delta)
        self.cam = math.max(0.5, math.min(3.0, (self.cam or 1.0) - delta * 0.12))
        pcall(self.SetCamDistanceScale, self, self.cam)
    end)
    model:SetScript('OnUpdate', function(self, elapsed)
        if self.dragging then
            local x = ({ GetCursorPosition() })[1]
            local scale = self:GetEffectiveScale()
            if scale and scale > 0 then
                self.facing = (self.dragFacing or 0) + ((x - self.dragStartX) / scale) * 0.012
                pcall(self.SetFacing, self, self.facing)
            end
        elseif self.autospin then
            self.facing = (self.facing or 0) + elapsed * 0.45
            pcall(self.SetFacing, self, self.facing)
        end
    end)

    -- Empty-state hint shown over the pedestal before anything is selected
    local empty = preview:CreateFontString(nil, 'OVERLAY', 'GameFontDisableLarge')
    empty:SetPoint('TOP', preview, 'TOP', 0, -(MODEL_H / 2) + 16)
    empty:SetWidth(220)
    empty:SetText('Hover a mob\nto inspect it')
    f.modelEmpty = empty

    -- Auto-spin toggle (top-right of the pedestal)
    local spinBtn = CreateFrame('Button', nil, preview)
    spinBtn:SetSize(22, 22)
    spinBtn:SetPoint('TOPRIGHT', preview, 'TOPRIGHT', -4, -4)
    spinBtn:SetNormalFontObject('GameFontNormalLarge')
    spinBtn:SetHighlightFontObject('GameFontHighlightLarge')
    spinBtn:SetText('|cffffd700o|r')
    spinBtn:SetScript('OnClick', function()
        model.autospin = not model.autospin
    end)
    spinBtn:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
        GameTooltip:SetText('Toggle auto-spin', 1, 1, 1)
        GameTooltip:AddLine('Drag the model to rotate, mouse-wheel to zoom.', 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    spinBtn:SetScript('OnLeave', function() GameTooltip:Hide() end)

    -- Text block beneath the pedestal
    local function fs(template, y, justify)
        local t = preview:CreateFontString(nil, 'OVERLAY', template)
        t:SetPoint('TOPLEFT',  preview, 'TOPLEFT',  4, y)
        t:SetPoint('TOPRIGHT', preview, 'TOPRIGHT', -4, y)
        t:SetJustifyH(justify or 'LEFT')
        return t
    end

    local yName = -(MODEL_H + 8)
    f.pvName = fs('GameFontNormalLarge', yName, 'CENTER')
    f.pvName:SetTextColor(1, 0.82, 0)
    f.pvRank = fs('GameFontHighlight', yName - 24, 'CENTER')
    f.pvId   = fs('GameFontDisableSmall', yName - 42, 'CENTER')

    local tdiv = preview:CreateTexture(nil, 'ARTWORK')
    tdiv:SetHeight(1)
    tdiv:SetPoint('TOPLEFT',  preview, 'TOPLEFT',  10, yName - 56)
    tdiv:SetPoint('TOPRIGHT', preview, 'TOPRIGHT', -10, yName - 56)
    tdiv:SetColorTexture(0.4, 0.4, 0.4, 0.4)

    f.pvChar  = fs('GameFontHighlight', yName - 66)
    f.pvTotal = fs('GameFontHighlight', yName - 84)
    f.pvXp    = fs('GameFontHighlight', yName - 102)

    -- Milestone progress bar
    f.pvBarLbl = fs('GameFontDisableSmall', yName - 128)
    local bar = CreateFrame('StatusBar', nil, preview)
    bar:SetHeight(12)
    bar:SetPoint('TOPLEFT',  preview, 'TOPLEFT',  4, yName - 144)
    bar:SetPoint('TOPRIGHT', preview, 'TOPRIGHT', -4, yName - 144)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarTexture('Interface\\TargetingFrame\\UI-StatusBar')
    bar:SetStatusBarColor(0.2, 0.7, 1)
    local barBg = bar:CreateTexture(nil, 'BACKGROUND')
    barBg:SetAllPoints()
    barBg:SetColorTexture(0, 0, 0, 0.5)
    f.pvBar = bar
    f.pvBarTxt = bar:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    f.pvBarTxt:SetPoint('CENTER', bar, 'CENTER', 0, 0)

    -- Controls hint at the very bottom of the pedestal
    local hint = preview:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    hint:SetPoint('BOTTOM', preview, 'BOTTOM', 0, 2)
    hint:SetText('drag: rotate   •   wheel: zoom   •   o: spin')

    NCE:ClearPreview()
    end)  -- end pedestal pcall
    if not _pedOk then
        NCE._initErrors = NCE._initErrors or {}
        NCE._initErrors['MobList/pedestal'] = tostring(_pedErr)
        -- Best-effort: stub out preview methods so any later caller is a no-op.
        f.preview = nil
        f.model   = nil
    end

    -- ── Bottom-left action buttons ─────────────────────────────────────────────
    local bottomLbl = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    bottomLbl:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 10, 34)
    f.bottomLbl = bottomLbl

    local purgeBtn = CreateFrame('Button', nil, f, 'UIPanelButtonTemplate')
    purgeBtn:SetSize(70, 22)
    purgeBtn:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 10, 8)
    purgeBtn:SetText('Purge')
    purgeBtn:SetScript('OnClick', function() NCE:SlashPurge(2); NCE:UpdateList(true) end)

    local clearXpBtn = CreateFrame('Button', nil, f, 'UIPanelButtonTemplate')
    clearXpBtn:SetSize(80, 22)
    clearXpBtn:SetPoint('LEFT', purgeBtn, 'RIGHT', 4, 0)
    clearXpBtn:SetText('Clear XP')
    clearXpBtn:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_TOP')
        GameTooltip:SetText('Wipe all stored XP/kill values.\nKill counts are not affected.', nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    clearXpBtn:SetScript('OnLeave', function() GameTooltip:Hide() end)
    clearXpBtn:SetScript('OnClick', function()
        StaticPopupDialogs['NCE_CLEAR_XP'] = {
            text         = 'Clear all stored XP/kill data?',
            button1      = 'Clear',
            button2      = 'Cancel',
            OnAccept     = function()
                wipe(NCE.db.global.tracker.exp or {})
                NCE:Msg('XP data cleared.')
                NCE:UpdateList(true)
            end,
            timeout      = 0,
            whileDead    = true,
            hideOnEscape = true,
        }
        StaticPopup_Show('NCE_CLEAR_XP')
    end)

    local resetBtn = CreateFrame('Button', nil, f, 'UIPanelButtonTemplate')
    resetBtn:SetSize(80, 22)
    resetBtn:SetPoint('LEFT', clearXpBtn, 'RIGHT', 4, 0)
    resetBtn:SetText('Reset All')
    resetBtn:SetScript('OnClick', function()
        StaticPopupDialogs['NCE_RESET'] = {
            text         = 'Reset ALL nocat kill data? This cannot be undone.',
            button1      = 'Reset',
            button2      = 'Cancel',
            OnAccept     = function() NCE:SlashReset(); NCE:UpdateList() end,
            timeout      = 0,
            whileDead    = true,
            hideOnEscape = true,
        }
        StaticPopup_Show('NCE_RESET')
    end)

    f:SetScript('OnShow', function() NCE:UpdateList() end)
    self.listFrame = f

    self:AddKillCallback(function()
        if NCE.listFrame and NCE.listFrame:IsShown() then
            NCE:UpdateList(true)
        end
    end)
end

-- ── Preview pedestal ────────────────────────────────────────────────────────
function NCE:ClearPreview()
    local f = self.listFrame
    if not f then return end
    f.previewID = nil
    f.modelID   = nil
    if f.model then pcall(f.model.ClearModel, f.model); f.model:Hide() end
    if f.modelEmpty then f.modelEmpty:Show() end
    for _, w in ipairs({ f.pvName, f.pvRank, f.pvId, f.pvChar, f.pvTotal, f.pvXp, f.pvBarLbl }) do
        if w then w:SetText('') end
    end
    if f.pvBar then f.pvBar:Hide(); f.pvBarTxt:SetText('') end
end

-- Light refresh of just the numbers (no model reload) — used when kill counts
-- tick up while the panel is open.
function NCE:RefreshPreviewStats(e)
    local f = self.listFrame
    if not f or not e then return end
    -- Pedestal may have failed to build (model frame type unavailable on this
    -- client, font template missing, etc.). f.pvName is the canary — if it
    -- wasn't created, every other pv* field is also nil. Bail silently so the
    -- searchable table still updates.
    if not f.pvName then return end

    f.pvName:SetText(e.name)
    f.pvRank:SetText('Bestiary rank: |cffffffff' .. rankFor(e.total) .. '|r')
    f.pvId:SetText('NPC #' .. e.id)
    f.pvChar:SetText('This character: |cffffffff'  .. self:commas(e.char)  .. '|r')
    f.pvTotal:SetText('All characters: |cffffffff' .. self:commas(e.total) .. '|r')

    local xv = self:GetExp(e.id)
    if xv and xv > 0 then
        f.pvXp:SetText('XP per kill: |cffffffff' .. self:commas(xv) .. '|r')
        f.pvXp:Show()
    else
        f.pvXp:SetText('')
    end

    local thr = self.db.global.tracker.threshold or 0
    if thr and thr > 0 then
        local into = e.total % thr
        local nextMs = (math.floor(e.total / thr) + 1) * thr
        f.pvBar:SetMinMaxValues(0, thr)
        f.pvBar:SetValue(into)
        f.pvBarLbl:SetText('Next milestone')
        f.pvBarTxt:SetText(self:commas(e.total) .. ' / ' .. self:commas(nextMs))
        f.pvBar:Show()
    else
        f.pvBar:Hide()
        f.pvBarLbl:SetText('')
        f.pvBarTxt:SetText('')
    end
end

-- Full preview: load the creature model (only when the mob actually changes to
-- avoid reloading the model on every kill tick) and refresh the stats.
function NCE:PreviewMob(e)
    local f = self.listFrame
    if not f or not e then return end
    -- Pedestal-failed bailout (see RefreshPreviewStats for rationale).
    if not f.pvName then return end
    if f.modelEmpty then f.modelEmpty:Hide() end

    if f.modelID ~= e.id then
        f.modelID = e.id
        local m = f.model
        m.facing   = 0.6
        m.autospin = true
        m:Show()
        pcall(m.ClearModel, m)
        pcall(m.SetCreature, m, e.id)
        pcall(m.SetPortraitZoom, m, 0)
        pcall(m.SetCamDistanceScale, m, m.cam or 1.0)
        pcall(m.SetPosition, m, 0, 0, 0)
        pcall(m.SetFacing, m, m.facing)
    end
    f.previewID = e.id
    self:RefreshPreviewStats(e)
end

-- ── Data ────────────────────────────────────────────────────────────────────
function NCE:UpdateList(preserveScroll)
    local f = self.listFrame
    if not f then return end

    local filter = (f.search:GetText() or ''):lower()
    local t  = self.db.global.tracker
    local ch = self.db.char.tracker
    local data = {}

    for id, total in pairs(t.killCount or {}) do
        if id ~= 0 then
            local name = (t.mobNames and t.mobNames[id]) or ('NPC #' .. id)
            local char = (ch.killCount and ch.killCount[id]) or 0
            if filter == '' or
               name:lower():find(filter, 1, true) or
               tostring(id):find(filter, 1, true)
            then
                data[#data + 1] = { id = id, name = name, char = char, total = total }
            end
        end
    end

    local sk, asc = f.sortKey, f.sortAsc
    table.sort(data, function(a, b)
        local va, vb = a[sk], b[sk]
        if type(va) == 'string' or type(vb) == 'string' then
            va = tostring(va or ''):lower(); vb = tostring(vb or ''):lower()
        else
            va = va or 0; vb = vb or 0
        end
        -- Must be a strict weak ordering: return false for equal values, and
        -- never have comp(a,b) and comp(b,a) both true. The old one-liner
        -- `asc and va<vb or va>vb` did exactly that on ascending sorts → Lua's
        -- "invalid order function for sorting".
        if va == vb then return false end
        if asc then return va < vb end
        return va > vb
    end)

    f.data = data
    f.countLbl:SetText(string.format('%d mobs', #data))
    f.sessLbl:SetText(string.format('Session: %s kills  %.1f KPM',
        self:commas(self.session.kills), self:SessionKPM()))

    if not preserveScroll then
        FauxScrollFrame_SetOffset(f.scrollFrame, 0)
        if f.scrollFrame.ScrollBar then f.scrollFrame.ScrollBar:SetValue(0) end
    end
    self:RefreshRows()

    -- Keep the pedestal in sync: prefer the pinned/hovered mob, else the top of
    -- the current list. Update stats only (no model reload) when it's unchanged.
    local cur
    local want = f.previewID or f.pinnedID
    if want then
        for _, e in ipairs(data) do if e.id == want then cur = e; break end end
    end
    cur = cur or data[1]
    if cur then
        if f.modelID == cur.id then self:RefreshPreviewStats(cur)
        else self:PreviewMob(cur) end
    else
        self:ClearPreview()
    end
end

function NCE:RefreshRows()
    local f = self.listFrame
    if not f then return end
    local data   = f.data
    local offset = FauxScrollFrame_GetOffset(f.scrollFrame)
    FauxScrollFrame_Update(f.scrollFrame, #data, NUM_ROWS, ROW_H)
    for i = 1, NUM_ROWS do
        local idx = i + offset
        local row = f.rows[i]
        if idx <= #data then
            local e = data[idx]
            row.rowData = e
            row.idLbl:SetText(e.id)
            row.nameLbl:SetText(e.name)
            row.charLbl:SetText(self:commas(e.char))
            row.totalLbl:SetText(self:commas(e.total))
            row:Show()
        else
            row.rowData = nil
            row:Hide()
        end
    end
    local showing = math.min(#data, NUM_ROWS + offset)
    f.bottomLbl:SetText(string.format('Showing %d of %d entries', showing, #data))
end

function NCE:OpenList()
    local f = self.listFrame
    if not f then return end
    if f:IsShown() then f:Hide()
    else self:UpdateList(); f:Show() end
end
