-- Weapon.lua  (keep weapon unsheathed)
local _, NCE = ...

local SHEATHED = 1  -- GetSheathState(): 1 = stowed, 2 = melee drawn, 3 = ranged drawn

-- Sound IDs an old "mute sheathe sounds" option used to mute. The list was
-- wrong — it included file IDs that play during normal attacks — so unmute
-- them once at load to undo any persistent mute from before that fix.
local OLD_SHEATHE_SOUND_IDS = { 567473, 567498, 567456, 567430 }

-- Buffs/toys that behave like vehicles but don't set the vehicle flag.
local PSEUDO_VEHICLES = {
    [196768] = true, [109076] = true, [294384] = true, [294383] = true,
    [278499] = true, [186530] = true, [148773] = true, [125883] = true,
    [221883] = true, [254471] = true, [254472] = true, [254473] = true,
    [254474] = true, [221887] = true, [363608] = true, [276111] = true,
    [276112] = true, [453804] = true, [221886] = true, [221885] = true,
    [444347] = true, [445163] = true, [121183] = true, [318452] = true,
    [172027] = true, [172052] = true, [172047] = true, [172049] = true,
    [172053] = true, [455494] = true, [50493]  = true, [196783] = true,
    [1214519] = true,[346012] = true, [128150] = true, [399041] = true,
    [392700] = true, [1251423] = true,[1281667] = true,[1280855] = true,
    [1280854] = true,[1281702] = true,[1280853] = true,
}

local function inPseudoVehicle()
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not get then return false end
    for spellID in pairs(PSEUDO_VEHICLES) do
        if get(spellID) then return true end
    end
    return false
end

-- ToggleSheath can be blocked while a secure Blizzard frame is shown, fired as
-- ADDON_ACTION_BLOCKED. Same list the pet module uses.
local RESTRICTED_FRAMES = {
    'TaxiFrame', 'FlightMapFrame', 'GossipFrame', 'QuestFrame',
    'MerchantFrame', 'MailFrame', 'AuctionHouseFrame', 'TradeFrame',
    'BankFrame', 'GuildBankFrame', 'VoidStorageFrame',
    'PlayerChoiceFrame', 'BarberShopFrame',
}

local function inRestrictedUI()
    for _, name in ipairs(RESTRICTED_FRAMES) do
        local f = _G[name]
        if f and f.IsShown and f:IsShown() then return true end
    end
    return false
end

-- Single source of truth for "may we draw the weapon now?". Returns nil when we
-- Post-init window during which the resting-in-cities check is bypassed. After
-- /reload the player almost always wants their weapon out immediately, even in
-- a city — the "stay drawn in cities" option then governs what happens once
-- they next sheathe (e.g. via an NPC interaction). Set in InitWeapon.
local restingBypassUntil = 0

-- may, or a short reason string when we may not (printed by /nocat unsheathe
-- debug). Keeping it as one ordered list means the debug output names the exact
-- thing standing in the way — no more guessing why it "isn't working".
local function unsheatheBlocker()
    local u = NCE.db.global.unsheathe
    if not u.enabled                                 then return "disabled (turn it on in /nocat options)" end
    if InCombatLockdown()                            then return 'in combat' end
    if UnitInVehicle('player')                       then return 'in a vehicle' end
    if IsMounted()                                   then return 'mounted' end
    if IsSwimming() and GetUnitSpeed('player') > 0   then return 'swimming' end
    -- Draw anywhere it's technically possible: resting / being in a city no longer
    -- blocks (a drawn weapon is perfectly valid there). Only the states where the
    -- weapon genuinely can't show drawn gate it (combat, mounted, swim-moving,
    -- vehicle, pseudo-vehicle, secure frames). The 'cities' toggle is now a no-op.
    if inPseudoVehicle()                             then return 'pseudo-vehicle / toy aura' end
    if inRestrictedUI()                              then return 'an NPC / Blizzard frame is open' end
    local ch   = NCE.db.char.unsheathe
    local spec = GetSpecialization and GetSpecialization()
    if spec and ch.specs and ch.specs[spec] and not ch.specs[spec].enabled then
        return 'disabled for this spec'
    end
    return nil
end

local function canUnsheathe()
    return unsheatheBlocker() == nil
end

-- Debounce: stacked-up events (LOOT_CLOSED + MERCHANT_CLOSED + the ticker, etc.)
-- can all hit tryUnsheathe in the same instant, and if something keeps
-- re-sheathing (a chair, a toy) uncapped retries cause a visible draw/stow
-- flicker. Cap ToggleSheath to once every TOGGLE_COOLDOWN seconds.
local TOGGLE_COOLDOWN = 1.5
local lastToggle = 0

-- Force-sheathed backoff: when a torch toy / held quest item / channeled cast
-- keeps the weapon stowed, the 1.5s cooldown isn't enough — every ticker we
-- redraw, the game restows, and the player sees a flicker. After a ToggleSheath
-- that doesn't actually draw the weapon, we suppress further toggles for an
-- exponentially growing window. Resets on success or on any event firing.
local BACKOFF_STEPS = { 5, 15, 60, 300 }
local backoffStep   = 0
local backoffUntil  = 0
local function resetBackoff() backoffStep = 0; backoffUntil = 0 end

-- Enforces the configured stance. Named tryUnsheathe for back-compat with all
-- the event/ticker call sites; it now keeps the weapon DRAWN or SHEATHED per
-- db.global.unsheathe.stance. (Note: drawn = melee OR ranged — which one the
-- game shows isn't addon-controllable; there is no SetSheathState API.)
local function tryUnsheathe()
    local u = NCE.db.global.unsheathe
    local now = GetTime()
    if now - lastToggle < TOGGLE_COOLDOWN then return end

    if u.stance == 'sheathed' then
        -- Keep weapon put away. Only act when it's currently drawn (2/3).
        if GetSheathState() == SHEATHED then return end          -- already sheathed
        if not u.enabled then return end
        if InCombatLockdown() then return end                     -- never fight the engine in combat
        -- Respect the per-spec toggle; ignore the draw-only guards (resting /
        -- mounted / etc.) since sheathing is always safe and always wanted here.
        local ch = NCE.db.char.unsheathe
        local spec = GetSpecialization and GetSpecialization()
        if spec and ch.specs and ch.specs[spec] and not ch.specs[spec].enabled then return end
        lastToggle = now
        pcall(ToggleSheath)
        return
    end

    -- Default 'drawn': keep weapon out. Only act when it's currently sheathed.
    if GetSheathState() ~= SHEATHED then resetBackoff(); return end -- already drawn (or no weapon)
    if now < backoffUntil then return end                          -- something is forcing sheathed; chill
    if not canUnsheathe() then return end
    lastToggle = now
    -- pcall: ToggleSheath isn't a protected function, but if a secure frame is
    -- racing it open the engine can still object — swallow that quietly.
    pcall(ToggleSheath)
    -- Verify the toggle actually drew the weapon. If it didn't, a torch/held
    -- item/cast is forcing sheathed — back off so we stop fighting it.
    C_Timer.After(0.4, function()
        if GetSheathState() == SHEATHED then
            backoffStep  = math.min(backoffStep + 1, #BACKOFF_STEPS)
            backoffUntil = GetTime() + BACKOFF_STEPS[backoffStep]
        else
            resetBackoff()
        end
    end)
end

local function unmuteOldSheatheSounds()
    if not UnmuteSoundFile then return end
    for _, id in ipairs(OLD_SHEATHE_SOUND_IDS) do
        UnmuteSoundFile(id)
    end
end

local function initSpecs(ch)
    ch.specs = {}
    if not GetNumSpecializations then return end
    local n = GetNumSpecializations(false, false)
    for i = 1, n do
        local _, name, _, icon = GetSpecializationInfo(i)
        ch.specs[i] = { name = name, icon = icon, enabled = true }
    end
end

-- Events that either stow the weapon (so we re-draw afterwards) or close a frame
-- that was blocking us. Frame-close events fire BEFORE the frame actually hides,
-- so the handler defers briefly before re-checking.
local EVENTS = {
    'PLAYER_ENTERING_WORLD',
    'PLAYER_REGEN_ENABLED',         -- combat ended
    'PLAYER_MOUNT_DISPLAY_CHANGED', -- mounted/dismounted — reliable re-draw on dismount
    'PLAYER_UNGHOST',               -- ran back / soulstone
    'PLAYER_ALIVE',                 -- resurrected
    'LOOT_CLOSED',
    'AUCTION_HOUSE_CLOSED',
    'UNIT_EXITED_VEHICLE',
    'BARBER_SHOP_CLOSE',
    'MERCHANT_CLOSED',
    'QUEST_FINISHED',
    -- NPC/UI interactions stow the weapon when the frame OPENS; RESTRICTED_FRAMES
    -- blocks us while they're shown, so we re-check on the matching CLOSE.
    'GOSSIP_CLOSED',
    'MAIL_CLOSED',
    'BANKFRAME_CLOSED',
    'GUILDBANKFRAME_CLOSED',
    'TRADE_CLOSED',
    'PLAYER_CHOICE_CLOSE',
    -- ── Newly added safeguards ──────────────────────────────────────────────
    -- Spell casts / channels (toys, escort items, etc.) lock the weapon down
    -- while active. None of the close-frame events fire when a cast ends, so
    -- without these the weapon stayed stowed until the next lucky trigger.
    'UNIT_SPELLCAST_STOP',
    'UNIT_SPELLCAST_FAILED',
    'UNIT_SPELLCAST_INTERRUPTED',
    'UNIT_SPELLCAST_SUCCEEDED',
    'UNIT_SPELLCAST_CHANNEL_STOP',
    -- Player-side aura changes — when a torch/banner/quest-item aura drops,
    -- the weapon is free again. Filtered to unit=='player' inside the handler.
    'UNIT_AURA',
    -- Weapon swap or item change — sheath state can reset, and the backoff
    -- needs to clear so a swap-then-toggle isn't blocked by stale state.
    'PLAYER_EQUIPMENT_CHANGED',
    'UNIT_INVENTORY_CHANGED',
    -- Shapeshift in/out of a form (druids, monks, shaman ghost wolf, etc.)
    'UPDATE_SHAPESHIFT_FORM',
    -- Pet battle ends — the engine puts your weapon away during the battle.
    'PET_BATTLE_CLOSE',
    -- Resting flag flipping (entering/leaving inns) often coincides with a
    -- silent re-sheathe; cheap to recheck.
    'PLAYER_UPDATE_RESTING',
}

function NCE:InitWeapon()
    local ch = self.db.char.unsheathe
    -- Spec init works on /reload, but on a fresh login GetNumSpecializations()
    -- returns 0 at OnInitialize time (character data not ready yet), so we also
    -- retry on PLAYER_ENTERING_WORLD below.
    if not ch.specs or #ch.specs == 0 then
        initSpecs(ch)
    end

    unmuteOldSheatheSounds()

    local f = CreateFrame('Frame')
    -- pcall each registration: an event name that's unknown on this client/patch
    -- (e.g. a deprecated one like VOID_STORAGE_CLOSE) throws, and an unguarded
    -- throw here would abort InitWeapon — taking the OnEvent handler + ticker
    -- down with it, and (since this is the first module to init) cascading into
    -- the rest of the addon failing to load.
    for _, e in ipairs(EVENTS) do pcall(f.RegisterEvent, f, e) end

    f:SetScript('OnEvent', function(_, event, arg1)
        -- Filter unit-scoped events to the player only — without this we spend
        -- effort on every party/raid member's auras, casts, gear changes, etc.
        if (event == 'UNIT_EXITED_VEHICLE'
            or event == 'UNIT_AURA'
            or event == 'UNIT_SPELLCAST_STOP'
            or event == 'UNIT_SPELLCAST_FAILED'
            or event == 'UNIT_SPELLCAST_INTERRUPTED'
            or event == 'UNIT_SPELLCAST_SUCCEEDED'
            or event == 'UNIT_SPELLCAST_CHANNEL_STOP'
            or event == 'UNIT_INVENTORY_CHANGED')
            and arg1 ~= 'player' then return end

        if event == 'PLAYER_ENTERING_WORLD' then
            local ch = NCE.db.char.unsheathe
            if not ch.specs or #ch.specs == 0 then initSpecs(ch) end
        end
        -- Any meaningful state change resets the force-sheathed backoff: ending
        -- combat, dismounting, closing a frame, a toy wearing off — all imply
        -- whatever was holding the weapon down may be gone, so retry immediately.
        resetBackoff()
        -- Defer: frame-close events fire BEFORE Blizzard hides the frame, so
        -- inRestrictedUI() would still see :IsShown() == true. A short delay
        -- lets the frame actually hide before we re-check.
        C_Timer.After(0.15, tryUnsheathe)
        -- A second check ~1s later catches the case where a toy / cast / channel
        -- only finishes resolving (and the sheath state actually flips) slightly
        -- after the event fires. The cooldown + early-return makes this cheap.
        C_Timer.After(1.0, tryUnsheathe)
    end)

    -- Post-init bypass: for the next 5s, IsResting() doesn't block the draw.
    -- This is the /reload-in-a-city case — the user just reloaded, the weapon
    -- is stowed, every event handler + ticker is about to fire — let one of
    -- them actually draw it instead of being blocked by the resting guard.
    restingBypassUntil = GetTime() + 5

    -- Stagger a few one-shot draws shortly after login. PLAYER_ENTERING_WORLD
    -- already fires tryUnsheathe via OnEvent, but character/equipment/spec data
    -- can take a beat to settle on fresh login, so multiple cheap attempts
    -- maximize the chance one lands cleanly.
    C_Timer.After(0.5, tryUnsheathe)
    C_Timer.After(1.5, tryUnsheathe)
    C_Timer.After(3.0, tryUnsheathe)

    -- Periodic safety net. A lot of re-sheath triggers fire no event at all:
    -- finishing a cast, sitting in a chair, entering water, a toy wearing off.
    -- ToggleSheath isn't protected, so this just keeps the weapon out. The call
    -- is debounced and returns instantly when the weapon is already drawn or
    -- canUnsheathe() says no, so nearly every tick is a cheap no-op.
    -- 1s tick (was 2s) — tighter recovery from edge cases the events miss.
    self.unsheatheTimer = C_Timer.NewTicker(1, tryUnsheathe)
end

-- ── Helpers called from Command / Options ────────────────────────────────────
function NCE:UnsheatheToggleSpec()
    local ch   = self.db.char.unsheathe
    local spec = GetSpecialization and GetSpecialization()
    if not spec or not ch.specs or #ch.specs == 0 then
        self:Msg('Specialization not available.'); return
    end
    ch.specs[spec].enabled = not ch.specs[spec].enabled
    self:Msg(string.format('Unsheathe for |cffffd700%s|r: %s',
        ch.specs[spec].name,
        ch.specs[spec].enabled and '|cff55ff55ON|r' or '|cffff5555OFF|r'))
    if ch.specs[spec].enabled then resetBackoff(); C_Timer.After(0.1, tryUnsheathe) end
end

-- Choose the enforced stance: 'drawn' (weapon out) or 'sheathed' (weapon away).
-- No argument cycles between the two. Melee-vs-ranged is not selectable (no API).
function NCE:SetStance(which)
    local u = self.db.global.unsheathe
    which = which and tostring(which):lower() or nil
    if which == 'draw' or which == 'drawn' or which == 'out' or which == 'unsheathed' then
        u.stance = 'drawn'
    elseif which == 'sheath' or which == 'sheathed' or which == 'away' or which == 'stow' or which == 'stowed' then
        u.stance = 'sheathed'
    elseif which == nil or which == '' then
        u.stance = (u.stance == 'sheathed') and 'drawn' or 'sheathed'  -- cycle
    else
        self:Msg('Usage: /nocat unsheathe pose <drawn|sheathed>'); return
    end
    self:Msg('Weapon stance: |cffffd700' .. (u.stance == 'sheathed' and 'always sheathed' or 'always drawn') .. '|r')
    resetBackoff()
    if C_Timer and C_Timer.After then C_Timer.After(0.1, tryUnsheathe) end
end

function NCE:UnsheatheStatus()
    local u  = self.db.global.unsheathe
    local ch = self.db.char.unsheathe
    self:Msg('Unsheathe: ' .. (u.enabled and '|cff55ff55ON|r' or '|cffff5555OFF|r')
        .. '  Stance: |cffffd700' .. (u.stance == 'sheathed' and 'sheathed' or 'drawn') .. '|r'
        .. '  Cities: ' .. (u.inCities and '|cff55ff55ON|r' or '|cffff5555OFF|r'))
    if ch.specs and #ch.specs > 0 then
        for i, s in ipairs(ch.specs) do
            self:Msg(string.format('  Spec %d |cffffd700%s|r: %s',
                i, s.name, s.enabled and '|cff55ff55ON|r' or '|cffff5555OFF|r'))
        end
    end
end

-- ── Diagnostics (/nocat unsheathe debug) ─────────────────────────────────────
function NCE:UnsheatheDiag()
    self:Msg('── weapon unsheathe ──')
    local u = self.db.global.unsheathe
    self:Msg('enabled: ' .. (u.enabled and '|cff55ff55yes|r' or '|cffff5555no|r')
        .. '   stance: |cffffd700' .. (u.stance == 'sheathed' and 'sheathed' or 'drawn') .. '|r'
        .. '   cities: ' .. (u.inCities and 'yes' or 'no'))

    local st = GetSheathState()
    local stName = (st == 1 and 'sheathed (stowed)')
                or (st == 2 and 'melee drawn')
                or (st == 3 and 'ranged drawn')
                or ('unknown (' .. tostring(st) .. ')')
    self:Msg('sheath state: ' .. stName)

    local blk = unsheatheBlocker()
    self:Msg('can draw now: ' .. (blk and ('|cffff5555no|r — ' .. blk) or '|cff55ff55yes|r'))

    -- Live proof: if we're stowed and nothing is blocking us, actually call
    -- ToggleSheath and report whether it took effect. This is the definitive
    -- test of whether the call works in the player's current context.
    if st == SHEATHED and not blk then
        self:Msg('running live ToggleSheath test…')
        lastToggle = 0
        resetBackoff()
        pcall(ToggleSheath)
        C_Timer.After(0.4, function()
            local s2 = GetSheathState()
            if s2 ~= SHEATHED then
                NCE:Msg('|cff55ff55ToggleSheath works|r — weapon is now drawn.')
            else
                NCE:Msg('|cffff5555ToggleSheath had no visible effect|r — likely no weapon equipped in a drawable slot.')
            end
        end)
    elseif st ~= SHEATHED then
        self:Msg('|cff55ff55weapon is already drawn|r — nothing to do.')
    end
end
