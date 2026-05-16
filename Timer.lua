-- Timer.lua  (kill timer with progress bar)
local _, NCE = ...

function NCE:InitTimer()
    local f = CreateFrame('Frame', 'NCETimerFrame', UIParent, 'BasicFrameTemplateWithInset')
    f:SetSize(230, 125)
    f:SetPoint('TOP', UIParent, 'TOP', 0, -250)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag('LeftButton')
    f:SetScript('OnDragStart', f.StartMoving)
    f:SetScript('OnDragStop',  f.StopMovingOrSizing)
    f:Hide()
    f.TitleText:SetText('Kill Timer')

    f.active    = false
    f.kills     = 0
    f.duration  = 0
    f.remaining = 0

    local function line(yOff)
        local l = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
        l:SetPoint('LEFT', f, 'TOPLEFT', 10, yOff)
        l:SetWidth(210); l:SetJustifyH('LEFT')
        return l
    end
    f.killsLbl = line(-30)
    f.timeLbl  = line(-46)
    f.kpmLbl   = line(-62)
    f.kpsLbl   = line(-78)

    local bar = CreateFrame('StatusBar', nil, f)
    bar:SetSize(210, 10)
    bar:SetPoint('TOPLEFT', f, 'TOPLEFT', 10, -95)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:SetStatusBarTexture('Interface\\TargetingFrame\\UI-StatusBar')
    bar:SetStatusBarColor(0.2, 0.8, 0.2)
    local barBg = bar:CreateTexture(nil, 'BACKGROUND')
    barBg:SetAllPoints()
    barBg:SetColorTexture(0, 0, 0, 0.5)
    f.bar = bar

    local stopBtn = CreateFrame('Button', nil, f, 'UIPanelButtonTemplate')
    stopBtn:SetSize(60, 20)
    stopBtn:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -8, 8)
    stopBtn:SetText('Stop')
    stopBtn:SetScript('OnClick', function() NCE:StopTimer() end)

    -- OnUpdate is only set while the timer is actively running (never idles every frame)
    f.onUpdate = function(self, elapsed)
        self.remaining = self.remaining - elapsed
        if self.remaining <= 0 then
            self.remaining = 0
            self.active = false
            self:SetScript('OnUpdate', nil)
            NCE:OnTimerEnd()
        end
        NCE:UpdateTimerDisplay()
    end

    self.timerFrame = f

    self:AddKillCallback(function()
        if NCE.timerFrame and NCE.timerFrame.active then
            NCE.timerFrame.kills = NCE.timerFrame.kills + 1
        end
    end)
end

function NCE:StartTimer(seconds)
    local f = self.timerFrame
    if not f then return end
    f.duration  = seconds
    f.remaining = seconds
    f.kills     = 0
    f.active    = true
    f:SetScript('OnUpdate', f.onUpdate)
    f:Show()
    self:UpdateTimerDisplay()
    self:Msg('Kill timer started: ' .. self:TimerFmt(seconds))
end

function NCE:StopTimer()
    local f = self.timerFrame
    if not f then return end
    f.active = false
    f:SetScript('OnUpdate', nil)
    f:Hide()
    self:Msg('Timer stopped.')
end

function NCE:OnTimerEnd()
    local f   = self.timerFrame
    local dur = f.duration
    local kpm = dur > 0 and f.kills / dur * 60 or 0
    local kps = dur > 0 and f.kills / dur      or 0
    self:Msg(string.format('Timer ended!  Kills: %s   KPM: %.2f   KPS: %.3f',
        self:commas(f.kills), kpm, kps))
    self:UpdateTimerDisplay()
    C_Timer.After(8, function()
        if NCE.timerFrame and not NCE.timerFrame.active then
            NCE.timerFrame:Hide()
        end
    end)
end

function NCE:UpdateTimerDisplay()
    local f = self.timerFrame
    if not f then return end
    local elapsed = f.duration - f.remaining
    local kpm = elapsed > 0 and f.kills / elapsed * 60 or 0
    local kps = elapsed > 0 and f.kills / elapsed      or 0
    local pct = f.duration > 0 and f.remaining / f.duration or 0
    local S   = 'ffc7c7cf'

    f.killsLbl:SetText(self:cc(S, 'Kills:') .. '  ' .. self:commas(f.kills))
    f.timeLbl:SetText( self:cc(S, 'Time:')  .. '  ' .. self:TimerFmt(math.max(0, f.remaining)))
    f.kpmLbl:SetText(  self:cc(S, 'KPM:')   .. '  ' .. string.format('%.2f', kpm))
    f.kpsLbl:SetText(  self:cc(S, 'KPS:')   .. '  ' .. string.format('%.3f', kps))

    f.bar:SetValue(pct)
    if     pct > 0.5  then f.bar:SetStatusBarColor(0.2, 0.8, 0.2)
    elseif pct > 0.25 then f.bar:SetStatusBarColor(0.9, 0.8, 0.1)
    else                    f.bar:SetStatusBarColor(0.9, 0.2, 0.2) end
end

function NCE:TimerFmt(s)
    s = math.floor(s)
    local h  = math.floor(s / 3600)
    local m  = math.floor(s % 3600 / 60)
    local sc = s % 60
    return h > 0 and string.format('%d:%02d:%02d', h, m, sc)
                  or string.format('%d:%02d', m, sc)
end

function NCE:ParseTimerArgs(args)
    local total = 0
    if args:match('[smhSMH]') then
        for num, unit in args:gmatch('(%d+)([smhSMH])') do
            num  = tonumber(num)
            unit = unit:lower()
            if     unit == 's' then total = total + num
            elseif unit == 'm' then total = total + num * 60
            elseif unit == 'h' then total = total + num * 3600 end
        end
    else
        local p = {}
        for n in args:gmatch('%d+') do p[#p+1] = tonumber(n) end
        total = (p[1] or 0) + (p[2] or 0)*60 + (p[3] or 0)*3600
    end
    return total
end
