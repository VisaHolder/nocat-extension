-- ExpTracker.lua  (correlate XP gains with last killed mob)
local _, NCE = ...

local XP_WINDOW = 3  -- seconds after kill to attribute XP

function NCE:InitExpTracker()
    self.prevXP = UnitXP('player') or 0
    self:RegisterEvent('PLAYER_XP_UPDATE', function()
        NCE:OnXPUpdate()
    end)
end

function NCE:OnXPUpdate()
    local cur   = UnitXP('player') or 0
    local delta = cur - self.prevXP
    self.prevXP = cur

    if delta <= 0 then return end
    if not self.lastKilledID then return end

    local age = GetTime() - (self.lastKillTime or 0)
    if age > XP_WINDOW then return end

    local id   = self.lastKilledID
    local prev = self.db.global.tracker.exp[id] or 0
    self.db.global.tracker.exp[id] = prev == 0 and delta or math.floor(prev * 0.75 + delta * 0.25)
end
