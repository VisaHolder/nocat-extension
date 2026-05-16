-- ImmediateFrame.lua  (floating kill counter with threshold alerts + name filter)
local _, NCE = ...

function NCE:InitImmediate()
    local f = CreateFrame('Frame', 'NCEImmFrame', UIParent, 'BackdropTemplate')
    f:SetSize(240, 30)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag('LeftButton')
    f:SetScript('OnDragStart', f.StartMoving)
    f:SetScript('OnDragStop', function(self)
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        local pos = NCE.db.global.tracker.immPosition
        pos.point = point; pos.relative = relative; pos.x = x; pos.y = y
    end)
    f:SetBackdrop({
        bgFile   = 'Interface\\DialogFrame\\UI-DialogBox-Background',
        edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 2.5, right = 2.5, top = 2.5, bottom = 2.5 },
    })
    f:Hide()

    local pos = self.db.global.tracker.immPosition
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relative, pos.x, pos.y)
    else
        f:SetPoint('CENTER')
    end

    local killLbl = f:CreateFontString(nil, 'OVERLAY')
    killLbl:SetFont('Fonts\\FRIZQT__.TTF', 14)
    killLbl:SetPoint('LEFT', f, 'LEFT', 8, 0)
    killLbl:SetText('Kills so far:')

    local killCount = f:CreateFontString(nil, 'OVERLAY')
    killCount:SetFont('Fonts\\FRIZQT__.TTF', 14)
    killCount:SetPoint('RIGHT', f, 'RIGHT', -68, 0)
    killCount:SetJustifyH('RIGHT')
    killCount:SetText('0')
    f.killCount = killCount

    local closeBtn = CreateFrame('Button', nil, f, 'UIPanelButtonTemplate')
    closeBtn:SetSize(60, 22)
    closeBtn:SetPoint('RIGHT', f, 'RIGHT', -3, 0)
    closeBtn:SetText('Close')
    closeBtn:SetScript('OnClick', function() NCE:HideImmediate() end)

    f.kills  = 0
    f.active = false
    self.immFrame = f

    -- Restore lowercased filter cache from saved DB value
    local saved = self.db.global.tracker.immFilter
    self.immFilterLower = saved and saved:lower() or nil

    self:AddKillCallback(function(id, name)
        NCE:ImmediateOnKill(name)
    end)
end

function NCE:ShowImmediate()
    local f = self.immFrame
    if not f then return end
    f.kills  = 0
    f.active = true
    f.killCount:SetText('0')
    f:Show()
end

function NCE:HideImmediate()
    local f = self.immFrame
    if not f then return end
    f.kills  = 0
    f.active = false
    f.killCount:SetText('0')
    f:Hide()
end

function NCE:OpenImmediate()
    local f = self.immFrame
    if not f then return end
    if f:IsShown() then self:HideImmediate()
    else self:ShowImmediate() end
end

function NCE:ImmediateOnKill(name)
    local f = self.immFrame
    if not f or not f.active then return end

    local filter = self.immFilterLower  -- pre-lowercased, updated in SetImmediateFilter/Clear
    if filter then
        if not (name and name:lower():find(filter, 1, true)) then return end
    end

    f.kills = f.kills + 1
    f.killCount:SetText(tostring(f.kills))

    local thresh = self.db.global.tracker.immThreshold or 0
    if thresh > 0 and f.kills % thresh == 0 then
        PlaySound(SOUNDKIT.RAID_WARNING)
        PlaySound(SOUNDKIT.PVP_THROUGH_QUEUE)
        RaidNotice_AddMessage(RaidWarningFrame,
            string.format('%d KILLS!', f.kills), ChatTypeInfo['SYSTEM'])
    end
end

function NCE:SetImmediateThreshold(n)
    self.db.global.tracker.immThreshold = n
    self:Msg(n > 0 and string.format('Immediate threshold: %d', n) or 'Immediate threshold disabled.')
end

function NCE:SetImmediateFilter(filter)
    self.db.global.tracker.immFilter = filter
    self.immFilterLower = filter and filter:lower() or nil
    self:Msg('Immediate filter: ' .. filter)
end

function NCE:ClearImmediateFilter()
    self.db.global.tracker.immFilter = nil
    self.immFilterLower = nil
    self:Msg('Immediate filter cleared.')
end
