-- ExpTracker.lua  (correlate XP gains with the last killed mob)
--
-- Caveats worth knowing about the number this records:
--   * It is the BASE kill XP after subtracting the rested bonus (see below).
--     Without that correction, every kill made while rested records ~2x.
--   * It is still relative to YOUR level at the time of the kill — a mob killed
--     at level 20 and the same mob killed at level 70 give very different XP, so
--     values captured across a leveling journey are inherently inconsistent.
--   * War Mode / heirloom / buff bonuses still inflate it; those aren't cleanly
--     separable from a plain UnitXP delta. Treat the number as an estimate.
local _, NCE = ...

local XP_WINDOW = 0.5  -- seconds after a kill to attribute an XP gain to it

function NCE:InitExpTracker()
    self.prevXP     = UnitXP('player') or 0
    self.prevRested = GetXPExhaustion() or 0   -- rested XP pool, for bonus subtraction
    self:RegisterEvent('PLAYER_XP_UPDATE', function()
        NCE:OnXPUpdate()
    end)
end

function NCE:OnXPUpdate()
    local cur       = UnitXP('player') or 0
    local curRested = GetXPExhaustion() or 0
    local delta         = cur - self.prevXP
    local restedDrained = (self.prevRested or 0) - curRested
    self.prevXP     = cur
    self.prevRested = curRested

    if delta <= 0 then return end            -- level-up (cur resets low) or no gain
    if not self.lastKilledID then return end

    local age = GetTime() - (self.lastKillTime or 0)
    if age > XP_WINDOW then return end        -- this XP gain wasn't from the last kill

    -- Rested gives 2x kill XP, and the bonus half is drained from your rested
    -- pool. So the base mob XP = total gained minus the rested amount consumed.
    -- This is locale-independent (no chat-message parsing) and removes the
    -- single biggest source of bogus values.
    if restedDrained > 0 then delta = delta - restedDrained end
    if delta <= 0 then return end

    local id   = self.lastKilledID
    local prev = self.db.global.tracker.exp[id] or 0
    -- Exponential moving average so a one-off outlier doesn't dominate, but a
    -- fresh entry takes the first clean reading directly.
    self.db.global.tracker.exp[id] = prev == 0 and delta or math.floor(prev * 0.75 + delta * 0.25)
end
