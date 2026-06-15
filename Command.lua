-- Command.lua  (/nocat slash command handler)
local _, NCE = ...

-- ── Purge ─────────────────────────────────────────────────────────────────────
function NCE:SlashPurge(rest)
    local threshold = tonumber(rest) or 1
    local t  = self.db.global.tracker
    local ch = self.db.char.tracker
    local removed = 0
    for id, count in pairs(t.killCount or {}) do
        if id ~= 0 and count < threshold then
            t.killCount[id]  = nil
            if t.mobNames      then t.mobNames[id]      = nil end
            if t.exp           then t.exp[id]            = nil end
            if t.thresholdHits then t.thresholdHits[id]  = nil end
            if ch.killCount    then ch.killCount[id]      = nil end
            removed = removed + 1
        end
    end
    self:Msg(string.format('Purged %d mob(s) with fewer than %d kill(s).', removed, threshold))
end

-- ── Reset ─────────────────────────────────────────────────────────────────────
function NCE:SlashReset()
    local t  = self.db.global.tracker
    local ch = self.db.char.tracker
    wipe(t.killCount     or {})
    wipe(t.mobNames      or {})
    wipe(t.exp           or {})
    wipe(t.thresholdHits or {})
    wipe(ch.killCount    or {})
    t.pvpKills  = 0
    ch.pvpKills = 0
    wipe(t.pvpByName  or {})
    wipe(ch.pvpByName or {})
    self.session = { kills = 0, pvpKills = 0, start = GetTime() }
    self:Msg('All kill data has been reset.')
end

-- ── Announce ──────────────────────────────────────────────────────────────────
function NCE:SlashAnnounce(channel)
    local target = channel and channel:upper()
    if not target or target == '' then
        target = (IsInRaid() and 'RAID') or (IsInGroup() and 'PARTY') or 'SAY'
    end
    local kpm     = self:SessionKPM()
    local elapsed = GetTime() - self.session.start
    local m = math.floor(elapsed / 60)
    local s = math.floor(elapsed % 60)
    SendChatMessage(string.format('[nocat] Session: %dm%ds  Kills: %s  KPM: %.2f',
        m, s, self:commas(self.session.kills), kpm), target)
end

-- ── Slash help ────────────────────────────────────────────────────────────────
function NCE:SlashHelp()
    local lines = {
        self:cc('ffffd700', '/nocat') .. ' commands:',
        '  (no args)                — open settings panel',
        '  help / ?                 — show this command list',
        '  options                  — open settings panel',
        '  pet                      — toggle auto pet summon',
        '  pet now                  — force-summon the selected pet now',
        '  pet debug                — diagnose why auto pet summon is blocked',
        '  list                     — open mob database',
        '  timer <dur>              — start kill timer  (5m / 3m30s / 90)',
        '  stop                     — stop timer',
        '  hud                      — toggle the live grind HUD (kills/XP/gold per hour)',
        '  goal <count> [mob]       — set a farm goal (omit mob to use your target)',
        '  goal clear               — cancel the farm goal',
        '  imm                      — toggle instant kill counter',
        '  imm threshold <N>        — alert every N kills',
        '  imm filter <pattern>     — only count matching mob names',
        '  imm clearfilter          — remove filter',
        '  target                   — show kills for current target',
        '  lookup <name|id>         — look up a mob',
        '  set <id> <nm> <g> <c>    — manually set kill counts',
        '  delete <id>              — delete mob entry',
        '  top [N]                  — print top N most-killed mobs (default 5)',
        '  announce [channel]       — post session stats to chat',
        '  purge [N]                — remove mobs with < N kills',
        '  reset                    — wipe all kill data',
        '  print                    — toggle per-kill chat output',
        '  printnew                 — toggle new-mob announcements',
        '  tooltip                  — toggle kill count in tooltips',
        '  showexp / xp             — toggle XP/kill in tooltips',
        '  threshold [N]            — milestone kill threshold',
        '  minimap                  — show/hide the minimap button',
        '  mmreset                  — reset minimap button to default position',
        '  loadmessage              — toggle addon load message',
        '  dungeons                 — toggle disable in dungeons',
        '  raids                    — toggle disable in raids',
        '  data                     — print session stats',
        '  unsheathe                — toggle weapon unsheathe',
        '  unsheathe city           — toggle unsheathe in cities',
        '  unsheathe pose <d|s>     — stance: drawn or sheathed',
        '  unsheathe spec           — toggle for current spec',
        '  unsheathe status         — show unsheathe settings',
        '  unsheathe debug          — diagnose why the weapon will not draw',
    }
    for _, l in ipairs(lines) do print(l) end
end

-- ── Data ──────────────────────────────────────────────────────────────────────
function NCE:SlashData()
    local t   = self.db.global.tracker
    local ch  = self.db.char.tracker
    local tot  = t.killCount  and t.killCount[0]  or 0
    local ctot = ch.killCount and ch.killCount[0] or 0
    local kpm  = self:SessionKPM()
    self:Msg(string.format(
        'Total: %s  |  Char: %s  |  Session: %s kills  KPM: %.2f  KPH: %.1f',
        self:commas(tot), self:commas(ctot),
        self:commas(self.session.kills), kpm, kpm * 60))
    if (t.pvpKills or 0) > 0 or (self.session.pvpKills or 0) > 0 then
        self:Msg(string.format('PvP kills: %s total  |  Char: %s  |  Session: %s',
            self:commas(t.pvpKills or 0),
            self:commas(ch.pvpKills or 0),
            self:commas(self.session.pvpKills or 0)))
    end
end

-- ── Top N ─────────────────────────────────────────────────────────────────────
function NCE:SlashTop(rest)
    local n = math.max(1, math.min(tonumber(rest) or 5, 25))
    local t = self.db.global.tracker
    local list = {}
    for id, count in pairs(t.killCount or {}) do
        if id ~= 0 then
            list[#list+1] = { name = self:GetMobName(id), count = count }
        end
    end
    if #list == 0 then self:Msg('No kill data yet.'); return end
    table.sort(list, function(a, b) return a.count > b.count end)
    local cap = math.min(n, #list)
    self:Msg(string.format('Top %d mobs:', cap))
    for i = 1, cap do
        self:Msg(string.format('  %d. %s — %s', i, list[i].name, self:commas(list[i].count)))
    end
end

-- ── Dispatch ──────────────────────────────────────────────────────────────────
local function split(str)
    local t = {}
    for w in str:gmatch('%S+') do t[#t+1] = w end
    return t
end

local function dispatch(input)
    input = (input or ''):match('^%s*(.-)%s*$')
    local args = split(input)
    local cmd  = (args[1] or ''):lower()
    table.remove(args, 1)
    local rest = table.concat(args, ' ')

    if cmd == '' or cmd == 'options' or cmd == 'opt' or cmd == 'config' then
        NCE:OpenOptions()

    elseif cmd == 'help' or cmd == '?' then
        NCE:SlashHelp()

    elseif cmd == 'pet' then
        local sub = (args[1] or ''):lower()
        if sub == 'now' then
            NCE:TryAutoSummonNow()
        elseif sub == 'debug' or sub == 'status' or sub == 'diag' then
            NCE:PetDiag()
        else
            NCE.db.global.pet.enabled = not NCE.db.global.pet.enabled
            NCE:Msg('Pet companion: ' .. (NCE.db.global.pet.enabled and 'ON' or 'OFF'))
            -- Turning it on should do something visible right away.
            if NCE.db.global.pet.enabled then NCE:TryAutoSummonNow() end
        end

    elseif cmd == 'list' then
        NCE:OpenList()

    elseif cmd == 'timer' or cmd == 'time' then
        if rest == '' then
            NCE:Msg('Usage: /nocat timer <dur>  e.g. 5m  3m30s  90')
        else
            local secs = NCE:ParseTimerArgs(rest)
            if secs > 0 then NCE:StartTimer(secs)
            else NCE:Msg('Could not parse duration: ' .. rest) end
        end

    elseif cmd == 'stop' then
        NCE:StopTimer()

    elseif cmd == 'hud' or cmd == 'grind' then
        NCE:ToggleGrindHUD()

    elseif cmd == 'goal' or cmd == 'farm' then
        local sub = (args[1] or ''):lower()
        if sub == 'clear' or sub == 'off' or sub == 'cancel' or sub == 'stop' then
            NCE:ClearGoal()
        elseif sub == '' then
            NCE:Msg('Usage: /nocat goal <count> [mob name or id]   (omit the mob to use your target)')
            NCE:Msg('       /nocat goal clear   to cancel')
        else
            local count = tonumber(args[1])
            local who   = table.concat(args, ' ', 2)   -- mob name/id after the count; '' = use current target
            NCE:SetGoal(count, who ~= '' and who or nil)
        end

    elseif cmd == 'imm' or cmd == 'immediate' or cmd == 'i' then
        if #args == 0 then
            NCE:OpenImmediate()
        else
            local sub = args[1]:lower()
            if sub:match('^t') then
                local n = tonumber(args[2])
                if not n then
                    NCE:Msg('Usage: /nocat imm threshold <N>')
                else
                    NCE:SetImmediateThreshold(n)
                end
            elseif sub:match('^f') then
                if #args < 2 then
                    local cur = NCE.db.global.tracker.immFilter
                    NCE:Msg('Current filter: ' .. (cur and cur or '<none>'))
                else
                    NCE:SetImmediateFilter(args[2])
                end
            elseif sub:match('^c') then
                NCE:ClearImmediateFilter()
            else
                NCE:Msg('Unknown imm subcommand: ' .. args[1])
            end
        end

    elseif cmd == 'target' or cmd == 't' or cmd == 'tar' then
        if not UnitExists('target') or UnitIsPlayer('target') then
            NCE:Msg('No valid target.')
        else
            local id = NCE:npcFromGUID(UnitGUID('target'))
            if id then NCE:PrintKills(id)
            else NCE:Msg('Target is not a creature.') end
        end

    elseif cmd == 'lookup' or cmd == 'lo' or cmd == 'check' then
        if rest == '' then NCE:Msg('Usage: /nocat lookup <name or NPC ID>')
        else NCE:PrintKills(rest) end

    elseif cmd == 'set' or cmd == 'edit' then
        local id, name, glob, char = args[1], args[2], args[3], args[4]
        if not (id and name and glob and char) then
            NCE:Msg('Usage: /nocat set <id> <name> <global> <char>')
        else
            NCE:SetKills(id, name, glob, char)
        end

    elseif cmd == 'delete' or cmd == 'del' or cmd == 'remove' then
        if rest == '' then
            NCE:Msg('Usage: /nocat delete <NPC ID>')
        else
            local id = tonumber(rest)
            if not id then NCE:Msg('ID must be a number.'); return end
            StaticPopupDialogs['NCE_DELETE'] = {
                text         = string.format('Delete "%s" (ID %d)?', NCE:GetMobName(id), id),
                button1      = 'Delete',
                button2      = 'Cancel',
                OnAccept     = function() NCE:DeleteMob(id) end,
                timeout      = 0,
                whileDead    = true,
                hideOnEscape = true,
            }
            StaticPopup_Show('NCE_DELETE')
        end

    elseif cmd == 'announce' or cmd == 'ann' then
        NCE:SlashAnnounce(rest)

    elseif cmd == 'purge' then
        NCE:SlashPurge(rest)

    elseif cmd == 'reset' or cmd == 'r' then
        StaticPopupDialogs['NCE_RESET'] = {
            text         = 'Reset ALL nocat kill data? This cannot be undone.',
            button1      = 'Reset',
            button2      = 'Cancel',
            OnAccept     = function() NCE:SlashReset() end,
            timeout      = 0,
            whileDead    = true,
            hideOnEscape = true,
        }
        StaticPopup_Show('NCE_RESET')

    elseif cmd == 'print' or cmd == 'p' then
        NCE.db.global.tracker.print = not NCE.db.global.tracker.print
        NCE:Msg('Print every kill: ' .. (NCE.db.global.tracker.print and 'ON' or 'OFF'))

    elseif cmd == 'printnew' or cmd == 'pn' then
        NCE.db.global.tracker.printnew = not NCE.db.global.tracker.printnew
        NCE:Msg('Print new mobs: ' .. (NCE.db.global.tracker.printnew and 'ON' or 'OFF'))

    elseif cmd == 'tooltip' or cmd == 'tt' then
        NCE.db.global.tracker.tooltip = not NCE.db.global.tracker.tooltip
        NCE:Msg('Tooltip: ' .. (NCE.db.global.tracker.tooltip and 'ON' or 'OFF'))

    elseif cmd == 'showexp' or cmd == 'exp' or cmd == 'xp' then
        NCE.db.global.tracker.showexp = not NCE.db.global.tracker.showexp
        NCE:Msg('Show XP in tooltip: ' .. (NCE.db.global.tracker.showexp and 'ON' or 'OFF'))

    elseif cmd == 'threshold' then
        local n = tonumber(rest)
        if n and n >= 0 then
            NCE.db.global.tracker.threshold = n
            NCE:Msg('Kill milestone threshold: ' .. NCE:commas(n))
        else
            NCE:Msg('Current threshold: ' .. NCE:commas(NCE.db.global.tracker.threshold or 0))
            NCE:Msg('Usage: /nocat threshold <N>')
        end

    elseif cmd == 'minimap' or cmd == 'mm' then
        NCE:ToggleMinimapButton()

    elseif cmd == 'mmreset' then
        NCE:ResetMinimapPos()

    elseif cmd == 'loadmessage' or cmd == 'lm' then
        NCE.db.global.loadmessage = not NCE.db.global.loadmessage
        NCE:Msg('Load message: ' .. (NCE.db.global.loadmessage and 'ON' or 'OFF'))

    elseif cmd == 'dungeons' then
        NCE.db.global.tracker.disableDungeons = not NCE.db.global.tracker.disableDungeons
        NCE:Msg('Disable in dungeons: ' .. (NCE.db.global.tracker.disableDungeons and 'ON' or 'OFF'))

    elseif cmd == 'raids' then
        NCE.db.global.tracker.disableRaids = not NCE.db.global.tracker.disableRaids
        NCE:Msg('Disable in raids: ' .. (NCE.db.global.tracker.disableRaids and 'ON' or 'OFF'))

    elseif cmd == 'top' then
        NCE:SlashTop(rest)

    elseif cmd == 'data' or cmd == 'stats' then
        NCE:SlashData()

    elseif cmd == 'debug' then
        local d = NCE._diag or {}
        NCE:Msg('── nocat debug ──')
        -- Surface any init-time errors first: if a module threw during
        -- OnInitialize, every later module was skipped (no minimap button,
        -- /nocat silently no-ops, etc.). Names match the _runInit() labels.
        local ie = NCE._initErrors or {}
        local hadInitErr = false
        for mod, err in pairs(ie) do
            hadInitErr = true
            NCE:Msg('|cffff5555INIT FAILED|r [' .. mod .. ']: ' .. tostring(err))
        end
        if not hadInitErr then NCE:Msg('init: |cff55ff55all modules loaded|r') end
        NCE:Msg('playerGUID: ' .. tostring(NCE.playerGUID))
        NCE:Msg('UnitGUID("player"): ' .. tostring(UnitGUID('player')))
        NCE:Msg('trackingEnabled: ' .. tostring(NCE.trackingEnabled))
        -- AceEvent embed doesn't expose IsEventRegistered, so query its
        -- underlying frame directly.
        local ace = LibStub and LibStub('AceEvent-3.0', true)
        local af  = ace and ace.frame
        local cleuOnFrame = af and af:IsEventRegistered('COMBAT_LOG_EVENT_UNFILTERED') or false
        local pkOnFrame   = af and af:IsEventRegistered('PARTY_KILL')                  or false
        NCE:Msg('CLEU on AceEvent.frame: ' .. tostring(cleuOnFrame)
            .. '   PARTY_KILL on frame: ' .. tostring(pkOnFrame))
        NCE:Msg('CLEU events seen: ' .. tostring(d.events or 0)
            .. '   PARTY_KILL events seen: ' .. tostring(d.partyKillEvents or 0))
        NCE:Msg('deaths in CLEU: ' .. tostring(d.deaths or 0) .. '   kills recorded: ' .. tostring(d.kills or 0))
        NCE:Msg('last event: ' .. tostring(d.lastEvent) .. '   last dst: ' .. tostring(d.lastDst))
        local recentN = 0
        for _ in pairs(NCE.recentKills or {}) do recentN = recentN + 1 end
        NCE:Msg('recentKills dedup entries: ' .. recentN)
        NCE:Msg('DB total kills: ' .. tostring((NCE.db.global.tracker.killCount or {})[0] or 0))
        if d.lastError then NCE:Msg('|cffff5555LAST ERROR:|r ' .. tostring(d.lastError)) end
        if UnitExists('target') and not UnitIsPlayer('target') then
            local g = UnitGUID('target')
            NCE:Msg('target GUID: ' .. tostring(g))
            NCE:Msg('target NPC id: ' .. tostring(NCE:npcFromGUID(g)))
        end

    elseif cmd == 'unsheathe' or cmd == 'us' then
        local sub = (args[1] or ''):lower()
        if sub == '' then
            NCE.db.global.unsheathe.enabled = not NCE.db.global.unsheathe.enabled
            NCE:Msg('Weapon unsheathe: ' .. (NCE.db.global.unsheathe.enabled and 'ON' or 'OFF'))
        elseif sub == 'city' or sub == 'cities' then
            NCE.db.global.unsheathe.inCities = not NCE.db.global.unsheathe.inCities
            NCE:Msg('Unsheathe in cities: ' .. (NCE.db.global.unsheathe.inCities and 'ON' or 'OFF'))
        elseif sub == 'spec' then
            NCE:UnsheatheToggleSpec()
        elseif sub == 'pose' or sub == 'stance' then
            NCE:SetStance(args[2])
        elseif sub == 'status' or sub == 'info' then
            NCE:UnsheatheStatus()
        elseif sub == 'debug' or sub == 'diag' then
            NCE:UnsheatheDiag()
        else
            NCE:Msg('Usage: /nocat unsheathe [city|spec|pose <drawn|sheathed>|status|debug]')
        end

    else
        NCE:Msg('Unknown command: ' .. cmd .. '  — type /nocat for help')
    end
end

SLASH_NOCATEXTENSION1 = '/nocat'
SLASH_NOCATEXTENSION2 = '/nce'
SlashCmdList['NOCATEXTENSION'] = dispatch
