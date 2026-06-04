-- Core.lua
local addonName, NCE = ...
LibStub('AceAddon-3.0'):NewAddon(NCE, addonName, 'AceEvent-3.0')

local GOLD = 'ffffd700'

local DB_DEFAULTS = {
    global = {
        -- Pet Companion
        pet = {
            enabled  = false,
            -- nil = pick a random favorite each time (legacy behavior).
            -- Otherwise this is a specific pet GUID (string) to always summon.
            selected = nil,
        },
        -- Kill Tracker
        tracker = {
            killCount     = {},
            mobNames      = {},
            exp           = {},
            thresholdHits = {},
            threshold     = 1000,
            print         = false,
            printnew      = false,
            pvp           = false,
            pvpKills      = 0,
            pvpByName     = {},
            tooltip       = false,
            showexp       = false,
            disableDungeons = false,
            disableRaids    = false,
            immThreshold  = 0,
            immFilter     = nil,
            immPosition   = {},
        },
        -- Weapon Unsheathe
        unsheathe = {
            enabled  = false,
            inCities = false,
            -- Which stance the addon enforces: 'drawn' (keep weapon out) or
            -- 'sheathed' (keep weapon put away). Melee-vs-ranged pose is NOT
            -- selectable — the WoW API has no SetSheathState; ToggleSheath only
            -- flips drawn/sheathed and the game picks the weapon.
            stance   = 'drawn',
        },
        loadmessage   = false,
        firstLoad     = true,
        minimapAngle  = nil,
        minimapHidden = false,
    },
    char = {
        tracker = {
            killCount = {},
            pvpKills  = 0,
            pvpByName = {},
        },
        unsheathe = {
            specs = {},
        },
    },
}

NCE.killCallbacks = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────
function NCE:cc(hex, s)
    return string.format('|c%s%s|r', hex, s)
end

function NCE:Msg(msg)
    print(self:cc(GOLD, '[nocat]') .. ' ' .. tostring(msg))
end

function NCE:commas(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    return s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
end

function NCE:npcFromGUID(guid)
    if not guid then return nil end
    local ok, t, _, _, _, _, id = pcall(strsplit, '-', guid)
    if not ok then return nil end
    if t == 'Creature' or t == 'Vehicle' or t == 'Pet' then return tonumber(id) end
end

-- Resolve an NPC name from a GUID by scanning unit tokens that might still
-- hold the unit. Used as a fallback when PARTY_KILL fires for an unseen mob
-- and CLEU UNIT_DIED (which carries dstName) doesn't fire on this client.
local NAME_TOKENS = { 'target', 'mouseover', 'targettarget', 'focus', 'softenemy' }
function NCE:resolveNpcName(guid)
    if not guid then return nil end
    for _, tok in ipairs(NAME_TOKENS) do
        local ok1, g = pcall(UnitGUID, tok)
        if ok1 and g == guid then
            local ok2, n = pcall(UnitName, tok)
            if ok2 and n and n ~= '' then return n end
        end
    end
    for i = 1, 10 do
        local tok = 'nameplate' .. i
        local ok1, g = pcall(UnitGUID, tok)
        if ok1 and g == guid then
            local ok2, n = pcall(UnitName, tok)
            if ok2 and n and n ~= '' then return n end
        end
    end
    return nil
end

function NCE:GetGlobalCount(id)
    return (self.db.global.tracker.killCount and self.db.global.tracker.killCount[id]) or 0
end

function NCE:GetCharCount(id)
    return (self.db.char.tracker.killCount and self.db.char.tracker.killCount[id]) or 0
end

function NCE:GetMobName(id)
    return (self.db.global.tracker.mobNames and self.db.global.tracker.mobNames[id]) or ('NPC #' .. tostring(id))
end

function NCE:GetExp(id)
    return (self.db.global.tracker.exp and self.db.global.tracker.exp[id]) or 0
end

function NCE:AddKillCallback(fn)
    table.insert(self.killCallbacks, fn)
end

function NCE:SessionKPM()
    local e = GetTime() - self.session.start
    return e > 0 and self.session.kills / e * 60 or 0
end

-- Returns true if this GUID is a fresh kill (not seen in the last 1s) and
-- records it in the dedup table. Returns false if it's a duplicate.
-- Every 64 fresh kills, sweeps entries older than 5s out of the table so
-- it stays bounded across long farming sessions.
function NCE:dedupKill(guid, now)
    local recent = self.recentKills
    local prev = recent[guid]
    if prev and (now - prev) < 1 then return false end
    recent[guid] = now

    self._dedupCount = (self._dedupCount or 0) + 1
    if self._dedupCount >= 64 then
        self._dedupCount = 0
        local cutoff = now - 5
        for g, t in pairs(recent) do
            if t < cutoff then recent[g] = nil end
        end
    end
    return true
end

-- ── Init ──────────────────────────────────────────────────────────────────────
function NCE:OnInitialize()
    self.db             = LibStub('AceDB-3.0'):New('NocatExtensionDB', DB_DEFAULTS)
    self.recentKills    = {}   -- guid → timestamp, dedup across CLEU + PARTY_KILL
    self.session        = { kills = 0, pvpKills = 0, start = GetTime() }
    self.lastKilledID   = nil
    self.lastKilledName = nil
    self.lastKillTime   = 0
    self.trackingEnabled = true
    self.playerGUID     = UnitGUID('player')
    self._diag          = { events = 0, deaths = 0, kills = 0, partyKillEvents = 0, lastEvent = '', lastDst = '', lastError = nil }

    -- COMBAT_LOG_EVENT_UNFILTERED via AceEvent. On this user's client, CLEU
    -- registration silently fails (verified: AceEvent.frame:IsEventRegistered
    -- returned false despite our self:RegisterEvent call, and a custom-frame
    -- attempt failed 18 retries in a row). Cause unknown — possibly another
    -- addon hooking RegisterEvent, possibly client-side. We keep this
    -- registration in place because it's free and works on most clients;
    -- when it doesn't, the PARTY_KILL handler below picks up the slack.
    self:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED', function()
        if NCE._diag then NCE._diag.events = NCE._diag.events + 1 end
        local ok, err = pcall(NCE.OnCombatLog, NCE, CombatLogGetCurrentEventInfo())
        if not ok and NCE._diag then NCE._diag.lastError = tostring(err) end
    end)

    -- PARTY_KILL fires for every kill the player or party/raid gets credit for,
    -- including PvP kills. Always active — dedup per-GUID against CLEU so kills
    -- aren't double-counted when both paths fire for the same victim.
    self:RegisterEvent('PARTY_KILL', function(_, killerGUID, killedGUID)
        if NCE._diag then NCE._diag.partyKillEvents = (NCE._diag.partyKillEvents or 0) + 1 end
        if not NCE.trackingEnabled then return end
        if not killedGUID then return end
        local now = GetTime()
        local id = NCE:npcFromGUID(killedGUID)
        if id then
            local name = (NCE.db.global.tracker.mobNames and NCE.db.global.tracker.mobNames[id])
                or NCE:resolveNpcName(killedGUID)
            -- Update credit BEFORE dedup so a CLEU PARTY_KILL subevent race
            -- that already counted this kill can't suppress credit attribution.
            NCE.lastKilledID   = id
            NCE.lastKilledName = name
            NCE.lastKillTime   = now
            if NCE:dedupKill(killedGUID, now) then
                NCE:RecordKill(id, name)
            end
            return
        end
        -- PvP fallback: PARTY_KILL gives credited player kills even when CLEU
        -- silently fails on this client. Resolve the victim's name via GUID
        -- since PARTY_KILL doesn't pass a name argument.
        if not NCE.db.global.tracker.pvp then return end
        local ok, t = pcall(strsplit, '-', killedGUID)
        if not ok or t ~= 'Player' then return end
        if not NCE:dedupKill(killedGUID, now) then return end
        local pOk, _, _, _, _, _, pname = pcall(GetPlayerInfoByGUID, killedGUID)
        NCE:RecordPvPKill((pOk and pname) or nil)
    end)

    -- Only wipe hitcache on actual world transitions, not subzone changes
    -- (ZONE_CHANGED_NEW_AREA fires for subzone borders and would drop mid-combat hits)
    self:RegisterEvent('PLAYER_ENTERING_WORLD', function()
        NCE.playerGUID  = UnitGUID('player')
        NCE.recentKills = {}
    end)
    self:RegisterEvent('ENCOUNTER_START', function(_, _, _, _, size)
        local t = NCE.db.global.tracker
        if (t.disableDungeons and size <= 5) or (t.disableRaids and size > 5) then
            NCE.trackingEnabled = false
        end
    end)
    self:RegisterEvent('ENCOUNTER_END', function(_, _, _, _, size)
        local t = NCE.db.global.tracker
        if (t.disableDungeons and size <= 5) or (t.disableRaids and size > 5) then
            NCE.trackingEnabled = true
            NCE.recentKills = {}
        end
    end)

    if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
            NCE:OnTooltip(tt)
        end)
    else
        GameTooltip:HookScript('OnTooltipSetUnit', function(tt)
            NCE:OnTooltip(tt)
        end)
    end

    -- Defense-in-depth: if any of our protected calls (SummonPetByGUID,
    -- ToggleSheath in secure contexts, etc.) ever slip past the guards in
    -- PetCompanion / Weapon, the engine fires ADDON_ACTION_BLOCKED and shows a
    -- modal popup that interrupts gameplay. We silently dismiss that popup
    -- for our own addon name — pcall already swallowed the Lua error, the
    -- action just didn't happen, no user-visible alert is warranted.
    local blocker = CreateFrame('Frame')
    blocker:RegisterEvent('ADDON_ACTION_BLOCKED')
    blocker:RegisterEvent('ADDON_ACTION_FORBIDDEN')
    blocker:SetScript('OnEvent', function(_, _, who)
        if who == addonName then
            StaticPopup_Hide('ADDON_ACTION_BLOCKED')
            StaticPopup_Hide('ADDON_ACTION_FORBIDDEN')
            if UIErrorsFrame and UIErrorsFrame.Clear then UIErrorsFrame:Clear() end
        end
    end)

    -- Per-init pcall guards: a single init throwing must not skip the rest.
    -- Errors are captured into NCE._initErrors so /nocat debug can show them
    -- (otherwise a silent failure here cascades into "minimap gone, slash dead,
    -- panel won't open" with no on-screen sign of what broke).
    NCE._initErrors = {}
    local function _runInit(name, fn)
        if not fn then return end
        local ok, err = pcall(fn, NCE)
        if not ok then NCE._initErrors[name] = tostring(err) end
    end
    _runInit('Weapon',        NCE.InitWeapon)
    _runInit('PetCompanion',  NCE.InitPetCompanion)
    _runInit('MobList',       NCE.InitMobList)
    _runInit('Timer',         NCE.InitTimer)
    _runInit('Immediate',     NCE.InitImmediate)
    _runInit('ExpTracker',    NCE.InitExpTracker)
    _runInit('Options',       NCE.InitOptions)
    _runInit('MinimapButton', NCE.InitMinimapButton)

    if self.db.global.loadmessage then
        self:Msg('Loaded. Type /nocat to open settings, /nocat help for commands.')
    end

    if self.db.global.firstLoad then
        self.db.global.firstLoad = false
    end
end

-- ── Combat log ────────────────────────────────────────────────────────────────
function NCE:OnCombatLog(_, event, _, _, _, _, _, dstGUID, dstName)
    local d = self._diag
    if d then d.lastEvent = event or '?' end

    if not self.trackingEnabled then return end

    if event ~= 'UNIT_DIED' and event ~= 'UNIT_DESTROYED' and event ~= 'PARTY_KILL' then return end

    if not dstGUID then return end
    if d then d.lastDst = dstName or '?'; d.deaths = (d.deaths or 0) + 1 end

    local now = GetTime()
    local id = self:npcFromGUID(dstGUID)
    if not id then
        if not self.db.global.tracker.pvp then return end
        local ok, t = pcall(strsplit, '-', dstGUID)
        if not ok or t ~= 'Player' then return end
        if not self:dedupKill(dstGUID, now) then return end
        self:RecordPvPKill(dstName)
        return
    end

    -- CLEU PARTY_KILL subevent indicates the player/party got credit. Update
    -- credit BEFORE dedup so a PARTY_KILL game event race can't suppress it.
    -- UNIT_DIED/UNIT_DESTROYED are uncredited (could be critters, ambient mobs)
    -- and intentionally don't update lastKilledID, so XP attribution stays
    -- pinned to the last actually-credited kill.
    if event == 'PARTY_KILL' then
        self.lastKilledID   = id
        self.lastKilledName = dstName or (self.db.global.tracker.mobNames and self.db.global.tracker.mobNames[id])
        self.lastKillTime   = now
    end

    if not self:dedupKill(dstGUID, now) then return end
    if d then d.kills = (d.kills or 0) + 1 end
    self:RecordKill(id, dstName)
end

-- ── PvP kill recording ────────────────────────────────────────────────────────
function NCE:RecordPvPKill(name)
    local t  = self.db.global.tracker
    local ch = self.db.char.tracker
    name = name or 'Unknown'
    t.pvpKills               = (t.pvpKills  or 0) + 1
    ch.pvpKills              = (ch.pvpKills or 0) + 1
    t.pvpByName[name]        = (t.pvpByName[name]  or 0) + 1
    ch.pvpByName[name]       = (ch.pvpByName[name] or 0) + 1
    self.session.pvpKills    = (self.session.pvpKills or 0) + 1
    if t.print then
        self:Msg(string.format('PvP kill: %s  (total: %s)', name, self:commas(t.pvpKills)))
    end
end

-- ── Kill recording ────────────────────────────────────────────────────────────
-- Credit (lastKilledID / lastKillTime for XP attribution) is updated by the
-- callers (PARTY_KILL game event + CLEU PARTY_KILL subevent) BEFORE the dedup
-- check, so neither side of the race can suppress credit. RecordKill itself
-- only handles counting and notifications.
function NCE:RecordKill(id, name)
    local t  = self.db.global.tracker
    local ch = self.db.char.tracker

    local isNew = not (t.killCount and t.killCount[id])

    t.killCount[id]  = (t.killCount[id]  or 0) + 1
    ch.killCount[id] = (ch.killCount[id] or 0) + 1
    t.killCount[0]   = (t.killCount[0]   or 0) + 1
    ch.killCount[0]  = (ch.killCount[0]  or 0) + 1

    if name and name ~= '' then t.mobNames[id] = name end

    self.session.kills = self.session.kills + 1

    local total   = t.killCount[id]
    local char    = ch.killCount[id]
    local display = name or t.mobNames[id] or ('NPC #' .. id)

    if t.print then
        self:Msg(string.format('%s — kills: %s  (char: %s)',
            display, self:commas(total), self:commas(char)))
    elseif t.printnew and isNew then
        self:Msg('New mob: ' .. display)
    end

    local thresh = t.threshold or 1000
    if thresh > 0 then
        local milestone = math.floor(total / thresh)
        local prev      = t.thresholdHits[id] or 0
        if milestone > prev then
            t.thresholdHits[id] = milestone
            self:KillAlert(display, total)
        end
    end

    for _, fn in ipairs(self.killCallbacks) do
        pcall(fn, id, name, char, total)
    end
end

function NCE:KillAlert(name, kills)
    local text = string.format('%s kills on %s!', self:commas(kills), name)
    RaidNotice_AddMessage(RaidBossEmoteFrame, text, ChatTypeInfo['SYSTEM'])
    self:Msg(self:cc(GOLD, 'Kill Record!') .. ' ' .. text)
end

-- ── Tooltip ───────────────────────────────────────────────────────────────────
function NCE:OnTooltip(tt)
    if not self.db.global.tracker.tooltip then return end
    local _, unit = tt:GetUnit()
    if not unit then return end

    -- TWW taint: when the tooltip fires for the world cursor (SetWorldCursor →
    -- TooltipDataHandler), the `unit` token GetUnit hands back is a "secret"
    -- value that the engine refuses to accept from tainted code. Calling
    -- UnitIsPlayer/UnitGUID/etc. with it raises the error this guards against.
    -- pcall the unit interrogation; if any call rejects the token, bail.
    local ok, isPlayer = pcall(UnitIsPlayer, unit)
    if not ok or isPlayer then return end
    local _ok2, guid = pcall(UnitGUID, unit)
    if not _ok2 or not guid then return end
    local id = self:npcFromGUID(guid)
    if not id then return end

    local _, uName = pcall(UnitName, unit)
    if uName and uName ~= '' then self.db.global.tracker.mobNames[id] = uName end

    local char  = self:GetCharCount(id)
    local total = self:GetGlobalCount(id)

    local _okAttack, canAttack = pcall(UnitCanAttack, 'player', unit)
    local _okDead, isDead = pcall(UnitIsDead, unit)
    if char > 0 or total > 0 or (_okAttack and canAttack) or (_okDead and isDead) then
        tt:AddLine(string.format('Killed %s (%s) times.',
            self:commas(char), self:commas(total)), 1, 1, 1)
        if self.db.global.tracker.showexp then
            local xv = self:GetExp(id)
            if xv > 0 then
                -- "X to level" only makes sense while leveling. At max level
                -- there's no XP bar, so show just the stored per-kill estimate.
                local xpMax = UnitXPMax('player') or 0
                local atMax = (xpMax <= 0) or (IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel())
                if atMax then
                    tt:AddLine(string.format('XP/kill: ~%s', self:commas(xv)), 1, 1, 1)
                else
                    local needed = math.ceil((xpMax - (UnitXP('player') or 0)) / xv)
                    tt:AddLine(string.format('XP/kill: ~%s  (%s to level)',
                        self:commas(xv), self:commas(needed)), 1, 1, 1)
                end
            end
        end
        tt:Show()
    end
end

-- ── Mob helpers ───────────────────────────────────────────────────────────────
function NCE:DeleteMob(id)
    id = tonumber(id)
    if not id then self:Msg('Invalid ID.'); return end
    local t  = self.db.global.tracker
    local ch = self.db.char.tracker
    local name = (t.mobNames and t.mobNames[id]) or ('NPC #' .. id)
    if not (t.killCount and t.killCount[id]) then
        self:Msg(string.format('ID %d not found.', id)); return
    end
    t.killCount[id]  = nil
    if t.mobNames      then t.mobNames[id]      = nil end
    if t.exp           then t.exp[id]            = nil end
    if t.thresholdHits then t.thresholdHits[id]  = nil end
    if ch.killCount    then ch.killCount[id]      = nil end
    self:Msg(string.format('Deleted %s (ID %d).', name, id))
end

function NCE:SetKills(id, name, globalCount, charCount)
    id = tonumber(id); globalCount = tonumber(globalCount); charCount = tonumber(charCount)
    if not id or not globalCount or not charCount then
        self:Msg('Usage: /nocat set <id> <name> <global> <char>'); return
    end
    local t  = self.db.global.tracker
    local ch = self.db.char.tracker
    t.killCount[id]  = globalCount
    ch.killCount[id] = charCount
    if name and name ~= '' then t.mobNames[id] = name end
    self:Msg(string.format('Set %s (ID %d) — global: %s  char: %s',
        name or self:GetMobName(id), id, self:commas(globalCount), self:commas(charCount)))
end

function NCE:PrintKills(identifier)
    local t  = self.db.global.tracker
    local ch = self.db.char.tracker
    identifier = tostring(identifier or ''):lower()
    local found = false
    for id, count in pairs(t.killCount or {}) do
        if id ~= 0 then
            local name   = (t.mobNames and t.mobNames[id]) or ('NPC #' .. id)
            local cKills = (ch.killCount and ch.killCount[id]) or 0
            if tostring(id) == identifier or name:lower() == identifier then
                self:Msg(string.format('"%s" (ID %d) — Global: %s  Char: %s',
                    name, id, self:commas(count), self:commas(cKills)))
                found = true
            end
        end
    end
    if not found then
        self:Msg(string.format('No entry found for "%s".', identifier))
    end
end
