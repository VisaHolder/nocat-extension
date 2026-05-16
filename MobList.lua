-- MobList.lua  (searchable, sortable virtual-scroll mob database)
local _, NCE = ...

local NUM_ROWS = 26
local ROW_H    = 18
local FRAME_W  = 630
local FRAME_H  = 560

local COLS = {
    { key='id',    label='NPC ID', w=70,  j='LEFT'  },
    { key='name',  label='Name',   w=310, j='LEFT'  },
    { key='char',  label='Char',   w=90,  j='RIGHT' },
    { key='total', label='Total',  w=90,  j='RIGHT' },
}

local COL_START_X = 8
local HDR_Y       = -54
local ROWS_Y      = -72

function NCE:InitMobList()
    local f = CreateFrame('Frame', 'NCEListFrame', UIParent, 'BasicFrameTemplateWithInset')
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint('CENTER')
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag('LeftButton')
    f:SetScript('OnDragStart', f.StartMoving)
    f:SetScript('OnDragStop',  f.StopMovingOrSizing)
    f:Hide()
    f.TitleText:SetText('nocat — Mob Database')

    f.sortKey = 'total'
    f.sortAsc = false
    f.data    = {}

    local search = CreateFrame('EditBox', 'NCEListSearch', f, 'SearchBoxTemplate')
    search:SetSize(220, 24)
    search:SetPoint('TOPLEFT', f, 'TOPLEFT', 8, -28)
    search:SetScript('OnTextChanged', function() NCE:UpdateList() end)
    f.search = search

    local countLbl = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    countLbl:SetPoint('LEFT', search, 'RIGHT', 12, 0)
    f.countLbl = countLbl

    local sessLbl = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    sessLbl:SetPoint('RIGHT', f, 'TOPRIGHT', -26, -32)
    sessLbl:SetJustifyH('RIGHT')
    f.sessLbl = sessLbl

    local sep = f:CreateTexture(nil, 'BACKGROUND')
    sep:SetHeight(1)
    sep:SetPoint('TOPLEFT',  f, 'TOPLEFT',  4, -50)
    sep:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -24, -50)
    sep:SetColorTexture(0.35, 0.35, 0.35, 0.9)

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
            NCE:UpdateList()
        end)
        x = x + col.w + 4
    end

    local rows = {}
    for i = 1, NUM_ROWS do
        local row = CreateFrame('Button', nil, f)
        row:SetHeight(ROW_H)
        row:SetPoint('TOPLEFT',  f, 'TOPLEFT',  COL_START_X - 2, ROWS_Y + -(i - 1) * ROW_H)
        row:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -26,              ROWS_Y + -(i - 1) * ROW_H)
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
            if self.rowData then
                GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
                GameTooltip:ClearLines()
                GameTooltip:AddLine(self.rowData.name, 1, 1, 1)
                GameTooltip:AddDoubleLine('NPC ID',      tostring(self.rowData.id),      .7,.7,.7,1,1,1)
                GameTooltip:AddDoubleLine('Char kills',  NCE:commas(self.rowData.char),  .7,.7,.7,1,1,1)
                GameTooltip:AddDoubleLine('Total kills', NCE:commas(self.rowData.total), .7,.7,.7,1,1,1)
                local xv = NCE:GetExp(self.rowData.id)
                if xv > 0 then
                    GameTooltip:AddDoubleLine('XP per kill', NCE:commas(xv), .7,.7,.7,1,1,1)
                end
                GameTooltip:Show()
            end
        end)
        row:SetScript('OnLeave', function(self)
            self.bg:SetColorTexture(1, 1, 1, self.altRow and 0.03 or 0)
            GameTooltip:Hide()
        end)
        row:SetScript('OnClick', function(self)
            if self.rowData then
                NCE:Msg(string.format('|cff00ccff%s|r (ID %d) — Char: %s  Total: %s',
                    self.rowData.name, self.rowData.id,
                    NCE:commas(self.rowData.char), NCE:commas(self.rowData.total)))
            end
        end)

        row.altRow = (i % 2 == 0)
        rows[i] = row
    end
    f.rows = rows

    local sf = CreateFrame('ScrollFrame', 'NCEListScroll', f, 'FauxScrollFrameTemplate')
    sf:SetPoint('TOPLEFT',     f, 'TOPLEFT',     COL_START_X - 2, ROWS_Y)
    sf:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -24, 32)
    sf:SetScript('OnVerticalScroll', function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, function()
            NCE:RefreshRows()
        end)
    end)
    f.scrollFrame = sf

    local bottomLbl = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    bottomLbl:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 8, 10)
    f.bottomLbl = bottomLbl

    local purgeBtn = CreateFrame('Button', nil, f, 'UIPanelButtonTemplate')
    purgeBtn:SetSize(70, 22)
    purgeBtn:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -26, 8)
    purgeBtn:SetText('Purge')
    purgeBtn:SetScript('OnClick', function() NCE:SlashPurge(2) end)

    local resetBtn = CreateFrame('Button', nil, f, 'UIPanelButtonTemplate')
    resetBtn:SetSize(80, 22)
    resetBtn:SetPoint('RIGHT', purgeBtn, 'LEFT', -4, 0)
    resetBtn:SetText('Reset All')
    resetBtn:SetScript('OnClick', function() NCE:SlashReset() end)

    f:SetScript('OnShow', function() NCE:UpdateList() end)
    self.listFrame = f

    self:AddKillCallback(function()
        if NCE.listFrame and NCE.listFrame:IsShown() then
            NCE:UpdateList(true)
        end
    end)
end

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
        if type(va) == 'string' then va = va:lower(); vb = (vb or ''):lower() end
        va = va or 0; vb = vb or 0
        return asc and va < vb or va > vb
    end)

    f.data = data
    f.countLbl:SetText(string.format('%d mobs', #data))
    f.sessLbl:SetText(string.format('Session: %s kills  %.1f KPM',
        self:commas(self.session.kills), self:SessionKPM()))

    if not preserveScroll then
        FauxScrollFrame_SetOffset(f.scrollFrame, 0)
        f.scrollFrame.ScrollBar:SetValue(0)
    end
    self:RefreshRows()
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
