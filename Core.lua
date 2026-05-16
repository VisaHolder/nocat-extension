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
        -- Map Zoom
        zoom = {
            follow = false,
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
            countmode     = false,
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
        },
        loadmessage   = false,
        firstLoad     = true,
        minimapAngle  = nil,
        minimapHidden = false,
    },
    char = {
        tracker = {
            killCount = {},
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
    local t, _, _, _, _, id = strsplit('-', guid)
    if t == 'Creature' or t == 'Vehicle' then return tonumber(id) end
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

-- ── Init ──────────────────────────────────────────────────────────────────────
function NCE:OnInitialize()
    self.db             = LibStub('AceDB-3.0'):New('NocatExtensionDB', DB_DEFAULTS)
    self.mobHitCache    = {}
    self.session        = { kills = 0, start = GetTime() }
    self.lastKilledID   = nil
    self.lastKilledName = nil
    self.lastKillTime   = 0
    self.trackingEnabled = true
    self.playerGUID     = UnitGUID('player')
    self._diag          = { events = 0, hits = 0, deaths = 0, kills = 0, partyKillEvents = 0, lastEvent = '', lastDst = '', lastError = nil }
    self._lastCleuTime  = 0

    -- COMBAT_LOG_EVENT_UNFILTERED via AceEvent. On this user's client, CLEU
    -- registration silently fails (verified: AceEvent.frame:IsEventRegistered
    -- returned false despite our self:RegisterEvent call, and a custom-frame
    -- attempt failed 18 retries in a row). Cause unknown — possibly another
    -- addon hooking RegisterEvent, possibly client-side. We keep this
    -- registration in place because it's free and works on most clients;
    -- when it doesn't, the PARTY_KILL handler below picks up the slack.
    self:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED', function()
        if NCE._diag then NCE._diag.events = NCE._diag.events + 1 end
        NCE._lastCleuTime = GetTime()
        local ok, err = pcall(NCE.OnCombatLog, NCE, CombatLogGetCurrentEventInfo())
        if not ok and NCE._diag then NCE._diag.lastError = tostring(err) end
    end)

    -- PARTY_KILL fallback. Fires on every kill the player (or their pet)
    -- delivers the killing blow on, with the victim's GUID right in the
    -- args — no hit cache needed. Despite the name it's primarily a
    -- player-credit event in retail.
    --
    -- Dedup against CLEU: if CLEU is active (any event in the last 5s),
    -- skip — CLEU's UNIT_DIED + mobHitCache path will record the kill.
    -- Only when CLEU is genuinely silent does PARTY_KILL record directly.
    self:RegisterEvent('PARTY_KILL', function(_, killerGUID, killedGUID)
        if NCE._diag then NCE._diag.partyKillEvents = (NCE._diag.partyKillEvents or 0) + 1 end
        if not NCE.trackingEnabled then return end
        if not killedGUID then return end
        if GetTime() - (NCE._lastCleuTime or 0) < 5 then return end
        local id = NCE:npcFromGUID(killedGUID)
        if not id then return end
        local name = NCE.db.global.tracker.mobNames and NCE.db.global.tracker.mobNames[id]
        NCE:RecordKill(id, name)
    end)

    -- Only wipe hitcache on actual world transitions, not subzone changes
    -- (ZONE_CHANGED_NEW_AREA fires for subzone borders and would drop mid-combat hits)
    self:RegisterEvent('PLAYER_ENTERING_WORLD', function()
        NCE.playerGUID  = UnitGUID('player')
        NCE.mobHitCache = {}
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
            NCE.mobHitCache = {}
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

    -- CanIMogIt is bundled inside nocat. If the user also has the standalone
    -- addon enabled the global `CanIMogIt` is taken and our embedded copy
    -- errors out. Print a chat warning — we intentionally avoid StaticPopup
    -- and AddonList:Show() here: both are well-known sources of UI taint in
    -- TWW (the latter calls Show on a secure-protected frame from addon code,
    -- which contaminates the Communities/Social UI's call stack and breaks
    -- secure dialogs like INVITE_COMMUNITY_MEMBER_WITH_INVITE_LINK).
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded('CanIMogIt') then
        self:Msg('|cffff5555Conflict:|r the standalone "Can I Mog It?" addon is enabled.')
        self:Msg('  nocat includes CanIMogIt internally — open the game menu → AddOns,')
        self:Msg('  uncheck "Can I Mog It?", and /reload.')
    end

    -- Strip CanIMogIt's slash commands. The embedded engine registers `/cimi`
    -- and `/canimogit` via AceConsole — we want users to drive everything from
    -- `/nocat` instead, so unregister those commands now that registration is
    -- complete (it ran during file load, well before OnEnable).
    if _G.CanIMogIt and _G.CanIMogIt.UnregisterChatCommand then
        pcall(_G.CanIMogIt.UnregisterChatCommand, _G.CanIMogIt, 'cimi')
        pcall(_G.CanIMogIt.UnregisterChatCommand, _G.CanIMogIt, 'canimogit')
    end

    -- Baganator embeds a CanIMogIt corner-widget registration that only fires
    -- when the standalone CanIMogIt addon emits ADDON_LOADED. Since we ship
    -- CanIMogIt's files inside nocat, that event never fires — so we replay
    -- the registration ourselves with Baganator's public API.
    if NCE.InitBaganatorBridge then NCE:InitBaganatorBridge() end

    if NCE.InitWeapon         then NCE:InitWeapon()          end
    if NCE.InitPetCompanion   then NCE:InitPetCompanion()   end
    if NCE.InitMapZoom        then NCE:InitMapZoom()         end
    if NCE.InitMobList        then NCE:InitMobList()         end
    if NCE.InitTimer          then NCE:InitTimer()           end
    if NCE.InitImmediate      then NCE:InitImmediate()       end
    if NCE.InitExpTracker     then NCE:InitExpTracker()      end
    if NCE.InitOptions        then NCE:InitOptions()         end
    if NCE.InitMinimapButton  then NCE:InitMinimapButton()   end

    if self.db.global.loadmessage then
        self:Msg('Loaded. Type /nocat to open settings, /nocat help for commands.')
    end

    if self.db.global.firstLoad then
        self.db.global.firstLoad = false
    end
end

-- Lookup table: O(1) vs 4 regex calls per combat event
local HIT_EVENTS = {
    SWING_DAMAGE          = true, RANGE_DAMAGE            = true,
    SPELL_DAMAGE          = true, SPELL_PERIODIC_DAMAGE   = true,
    ENVIRONMENTAL_DAMAGE  = true, SPELL_INSTAKILL         = true,
    SPELL_DRAIN           = true, SPELL_LEECH             = true,
    DAMAGE_SHIELD         = true, -- mob attacks player, dies from thorns/shield reflection
}

-- ── Combat log ────────────────────────────────────────────────────────────────
-- Combat log object flag bits used to detect player-controlled sources without
-- depending on GUID equality (GUID can drift across reloads/login races).
local OBJ_AFFIL_MINE  = 0x00000001  -- COMBATLOG_OBJECT_AFFILIATION_MINE
local OBJ_AFFIL_PARTY = 0x00000002
local OBJ_AFFIL_RAID  = 0x00000004

function NCE:OnCombatLog(ts, event, _, srcGUID, srcName, srcFlags, _,
                          dstGUID, dstName)
    local d = self._diag
    if d then d.lastEvent = event or '?' end

    if not self.trackingEnabled then return end
    if not self.playerGUID then self.playerGUID = UnitGUID('player') end

    local isDeath = (event == 'UNIT_DIED' or event == 'PARTY_KILL')
    if not isDeath and not HIT_EVENTS[event] then return end  -- skip irrelevant events early

    if not dstGUID then return end
    if d then d.lastDst = dstName or '?' end

    if isDeath then
        if d then d.deaths = d.deaths + 1 end
        if self.mobHitCache[dstGUID] then
            local id = self:npcFromGUID(dstGUID)
            if id then
                self.mobHitCache[dstGUID] = nil
                if d then d.kills = d.kills + 1 end
                self:RecordKill(id, dstName)
            end
        end
        return
    end

    -- hit event — only parse GUID and check source if we care about this dst
    local id = self:npcFromGUID(dstGUID)
    if not id then return end

    -- Player-controlled source detection: trust combat log flags first (most
    -- reliable, works even if our cached playerGUID is stale), GUID compare second.
    local mine = srcFlags and bit.band(srcFlags, OBJ_AFFIL_MINE) ~= 0
    local isPlayer = mine or srcGUID == self.playerGUID or srcGUID == UnitGUID('pet')

    if not isPlayer and self.db.global.tracker.countmode then
        local groupBit = srcFlags and bit.band(srcFlags, OBJ_AFFIL_PARTY + OBJ_AFFIL_RAID) ~= 0
        isPlayer = groupBit or (IsGuidInGroup and srcGUID and IsGuidInGroup(srcGUID)) or false
        if not isPlayer and srcName then
            isPlayer = (UnitInRaid(srcName) ~= nil) or (UnitInParty(srcName) and true or false)
        end
    end

    if isPlayer then
        if d then d.hits = d.hits + 1 end
        self.mobHitCache[dstGUID] = true
    end
end

-- ── Kill recording ────────────────────────────────────────────────────────────
function NCE:RecordKill(id, name)
    local t  = self.db.global.tracker
    local ch = self.db.char.tracker

    local isNew = not (t.killCount and t.killCount[id])

    t.killCount[id]  = (t.killCount[id]  or 0) + 1
    ch.killCount[id] = (ch.killCount[id] or 0) + 1
    t.killCount[0]   = (t.killCount[0]   or 0) + 1
    ch.killCount[0]  = (ch.killCount[0]  or 0) + 1

    if name and name ~= '' then t.mobNames[id] = name end

    self.session.kills  = self.session.kills + 1
    self.lastKilledID   = id
    self.lastKilledName = name
    self.lastKillTime   = GetTime()

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
    if char > 0 or total > 0 or (_okAttack and canAttack) then
        tt:AddLine(string.format('Killed %s (%s) times.',
            self:commas(char), self:commas(total)), 1, 1, 1)
        if self.db.global.tracker.showexp then
            local xv = self:GetExp(id)
            if xv > 0 then
                local needed = math.ceil((UnitXPMax('player') - UnitXP('player')) / xv)
                tt:AddLine(string.format('XP/kill: %s  (%s to level)',
                    self:commas(xv), self:commas(needed)), 1, 1, 1)
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
