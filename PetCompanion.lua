-- PetCompanion.lua  (auto-summon companion pet)
local _, NCE = ...

-- State-change events that commonly leave you without a companion out. We
-- deliberately avoid per-step events (PLAYER_STARTED_MOVING/STOPPED) — they
-- fire several times a second and each tick would touch C_PetJournal, which is
-- needless churn. These cover the real "my pet vanished" moments instead.
local PET_EVENTS = {
    'PLAYER_REGEN_ENABLED',   -- combat ended (SummonPetByGUID is #nocombat, so we retry here)
    'UPDATE_STEALTH',         -- left stealth
    'UNIT_EXITED_VEHICLE',    -- left a vehicle
    'ZONE_CHANGED_NEW_AREA',  -- new zone — pet often despawns crossing borders
    'PLAYER_ENTERING_WORLD',  -- login / reload / loading screen
    'PET_BATTLE_CLOSE',       -- a pet battle dismisses your companion
    'PLAYER_UNGHOST',         -- released and ran back / soulstone
    'PLAYER_ALIVE',           -- resurrected (spirit healer / rez)
}

local INVIS_AURAS = { 199483, 32612, 110960 }  -- Camouflage, Invisibility, Greater Invisibility

-- Blizzard frames that, when shown, put the player in a "restricted UI" state
-- where calling C_PetJournal.SummonPetByGUID from a non-hardware event can fire
-- ADDON_ACTION_BLOCKED.
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

-- Single source of truth for "may we summon right now?". Returns nil when we
-- can summon, or a short human-readable reason string when we can't — the
-- summon loop only cares whether it's nil, while /nocat pet debug prints it.
local function summonBlocker()
    if not (NCE.db and NCE.db.global.pet) then return 'db not ready' end
    if not NCE.db.global.pet.enabled                            then return 'disabled (turn it on in /nocat options)' end
    if not (C_PetJournal and C_PetJournal.GetNumPets)           then return 'pet journal API unavailable' end
    if UnitAffectingCombat('player')                            then return 'in combat' end
    if UnitHasVehicleUI('player')                               then return 'vehicle UI' end
    if UnitIsControlling and UnitIsControlling('player') and UnitChannelInfo('player') then return 'controlling another unit' end
    if UnitIsGhost('player')                                    then return 'dead / ghost' end
    if inRestrictedUI()                                         then return 'NPC / Blizzard frame open' end
    -- Don't blow the player's cover: stealth / invisibility still block the summon
    -- (a companion would reveal you). Everything else is open now — flying, resting,
    -- cities, etc. all summon fine; only combat / vehicle / dead / secure-frame /
    -- stealth / invis / already-out gate it.
    if IsStealthed()                                            then return 'stealthed' end
    local getAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    for _, id in ipairs(INVIS_AURAS) do
        if getAura and getAura(id)                              then return 'invisibility aura active' end
    end
    if C_PetJournal.GetSummonedPetGUID() ~= nil                 then return 'a pet is already out' end
    return nil
end

local function CanSummon()
    return summonBlocker() == nil
end

-- ── Pet-journal filter manipulation ──────────────────────────────────────────
-- GetPetInfoByIndex returns pets AFTER the player's journal filters are applied.
-- If the user filtered out "collected" pets in their journal UI, a raw scan
-- would return zero favorites even though they have plenty — the classic
-- "auto-summon does nothing but the button works" bug. We save the current
-- filter state, force "show collected", scan, then restore.
local function petFilterIndex(name)
    if Enum and Enum.PetJournalFilter and Enum.PetJournalFilter[name] then
        return Enum.PetJournalFilter[name]
    end
    if name == 'Collected'    then return _G.LE_PET_JOURNAL_FILTER_COLLECTED     end
    if name == 'NotCollected' then return _G.LE_PET_JOURNAL_FILTER_NOT_COLLECTED end
end

local function withForcedFilters(fn)
    local FC = petFilterIndex('Collected')
    local FN = petFilterIndex('NotCollected')
    local can = FC and FN and C_PetJournal and C_PetJournal.SetFilterChecked and C_PetJournal.IsFilterChecked

    local prevFC, prevFN
    if can then
        prevFC = C_PetJournal.IsFilterChecked(FC)
        prevFN = C_PetJournal.IsFilterChecked(FN)
        pcall(C_PetJournal.SetFilterChecked, FC, true)
        pcall(C_PetJournal.SetFilterChecked, FN, false)
    end

    local ok, result = pcall(fn)

    if can then
        pcall(C_PetJournal.SetFilterChecked, FC, prevFC)
        pcall(C_PetJournal.SetFilterChecked, FN, prevFN)
    end

    if not ok then return {} end
    return result
end

-- ── Public helpers (used by Options.lua / Command.lua) ───────────────────────

-- Returns list of {guid=, name=, icon=} for every favorited pet the player owns.
function NCE:GetFavoritePets()
    if not C_PetJournal or not C_PetJournal.GetNumPets then return {} end

    return withForcedFilters(function()
        local result = {}
        local numPets = C_PetJournal.GetNumPets()
        for i = 1, numPets do
            local petID, _, owned, customName, _, favorite, _, name, icon =
                C_PetJournal.GetPetInfoByIndex(i)
            if owned and favorite and petID then
                local display = (customName and customName ~= '' and customName) or name or 'Unknown'
                result[#result+1] = { guid = tostring(petID), name = display, icon = icon }
            end
        end
        table.sort(result, function(a, b) return a.name < b.name end)
        return result
    end)
end

function NCE:GetSelectedPetName()
    local guid = self.db and self.db.global.pet.selected
    if not guid then return nil end
    if not C_PetJournal or not C_PetJournal.GetPetInfoByPetID then return guid end
    local _, customName, _, _, _, _, _, name = C_PetJournal.GetPetInfoByPetID(guid)
    return (customName and customName ~= '' and customName) or name or guid
end

-- True if a saved pet GUID still resolves to an owned pet. A caged/released pet
-- leaves a stale GUID behind, and SummonPetByGUID silently no-ops on those —
-- one of the "selected a pet, now nothing summons" failure modes.
local function petGuidIsValid(guid)
    if not guid or not (C_PetJournal and C_PetJournal.GetPetInfoByPetID) then return false end
    local ok, speciesID = pcall(C_PetJournal.GetPetInfoByPetID, guid)
    return ok and speciesID ~= nil
end

-- Core summon routine. Honours the selected pet, validates it, and falls back
-- to a random favourite. Returns true if a summon was actually issued.
-- Callers gate on CanSummon()/combat first; the pcall here is only a guard
-- against the rare combat-starts-mid-timer race.
local function doSummon()
    local sel = NCE.db.global.pet.selected
    if sel then
        if petGuidIsValid(sel) then
            pcall(C_PetJournal.SummonPetByGUID, sel)
            return true
        end
        -- Stale selection (pet was caged/released) — clear it so we stop
        -- silently failing and fall through to a random favourite.
        NCE.db.global.pet.selected = nil
    end

    -- Random favourite. SummonRandomPet(true) is the built-in, filter-immune
    -- path made for exactly this; prefer it. The manual scan is only a fallback
    -- for clients/versions where the API is absent.
    if C_PetJournal.SummonRandomPet then
        pcall(C_PetJournal.SummonRandomPet, true)
        return true
    end
    local favs = NCE:GetFavoritePets()
    if #favs == 0 then return false end
    pcall(C_PetJournal.SummonPetByGUID, favs[math.random(#favs)].guid)
    return true
end

-- Called from the options panel / "Summon Now" — an explicit, hardware-driven
-- request, so it bypasses CanSummon()'s "a pet is already out" guard (the user
-- wants to (re)roll one) but still respects combat.
function NCE:SummonPet(guid)
    if not (C_PetJournal and C_PetJournal.SummonPetByGUID) then return end
    if not guid then return end
    if UnitAffectingCombat('player') then self:Msg('Cannot summon a pet in combat.'); return end
    pcall(C_PetJournal.SummonPetByGUID, guid)
end

function NCE:TryAutoSummonNow()
    if not (self.db and self.db.global.pet) then return end
    if UnitAffectingCombat('player') then self:Msg('Cannot summon a pet in combat.'); return end

    local sel = self.db.global.pet.selected
    if sel and petGuidIsValid(sel) then
        pcall(C_PetJournal.SummonPetByGUID, sel)
        return
    elseif sel then
        self.db.global.pet.selected = nil  -- stale
    end

    if C_PetJournal.SummonRandomPet then
        pcall(C_PetJournal.SummonRandomPet, true)
        return
    end
    local favorites = self:GetFavoritePets()
    if #favorites == 0 then
        self:Msg('No favorited pets — favorite some in the Pet Journal first.')
        return
    end
    pcall(C_PetJournal.SummonPetByGUID, favorites[math.random(#favorites)].guid)
end

-- ── Auto-summon loop ─────────────────────────────────────────────────────────
local function autoSummon()
    if not CanSummon() then return end
    doSummon()
end

-- A short, self-cancelling burst of attempts after a loading screen. At login /
-- reload the pet journal is frequently not populated yet when PLAYER_ENTERING_
-- WORLD fires, so a single shot misses and you get the "only summons sometimes
-- after logging in" behaviour. We retry once a second for a few seconds and
-- stop the instant a pet is up (or summoning becomes impossible).
function NCE:PetRetryBurst()
    if self._petBurst then self._petBurst:Cancel() end
    self._petBurst = C_Timer.NewTicker(1, function()
        if not (NCE.db and NCE.db.global.pet and NCE.db.global.pet.enabled) then
            if NCE._petBurst then NCE._petBurst:Cancel(); NCE._petBurst = nil end
            return
        end
        if C_PetJournal and C_PetJournal.GetSummonedPetGUID and C_PetJournal.GetSummonedPetGUID() ~= nil then
            if NCE._petBurst then NCE._petBurst:Cancel(); NCE._petBurst = nil end
            return
        end
        autoSummon()
    end, 10)  -- up to 10 attempts over ~10s
end

function NCE:InitPetCompanion()
    local f = CreateFrame('Frame')
    -- pcall-guarded so a deprecated/unknown event name can't throw and abort init.
    for _, event in ipairs(PET_EVENTS) do
        pcall(f.RegisterEvent, f, event)
    end
    f:SetScript('OnEvent', function(_, event, unit)
        if event == 'UNIT_EXITED_VEHICLE' and unit ~= 'player' then return end
        -- Loading-screen events: the journal may still be loading and the pet
        -- usually despawned, so use the retry burst rather than one shot.
        if event == 'PLAYER_ENTERING_WORLD' or event == 'ZONE_CHANGED_NEW_AREA' then
            NCE:PetRetryBurst()
        else
            C_Timer.After(0.5, autoSummon)
        end
    end)

    -- Periodic safety net for the despawn cases that fire no event at all: the
    -- pet dies to area damage, gets dropped by a taxi, or simply wanders off.
    -- autoSummon() is idempotent and CanSummon() returns instantly once a pet
    -- is out, so the overwhelming majority of ticks do nothing.
    self.petSafetyTicker = C_Timer.NewTicker(5, autoSummon)
end

-- ── Diagnostics (/nocat pet debug) ───────────────────────────────────────────
function NCE:PetDiag()
    self:Msg('── pet companion ──')
    local p = self.db.global.pet
    self:Msg('enabled: ' .. (p.enabled and '|cff55ff55yes|r' or '|cffff5555no|r'))

    local blk = summonBlocker()
    self:Msg('can summon now: ' .. (blk and ('|cffff5555no|r — ' .. blk) or '|cff55ff55yes|r'))

    if C_PetJournal and C_PetJournal.GetNumPets then
        local rawFav, n = 0, C_PetJournal.GetNumPets()
        for i = 1, n do
            local _, _, owned, _, _, fav = C_PetJournal.GetPetInfoByIndex(i)
            if owned and fav then rawFav = rawFav + 1 end
        end
        local forced = #self:GetFavoritePets()
        self:Msg(string.format('favorites — journal scan: %d   filter-forced: %d', rawFav, forced))
        if rawFav == 0 and forced > 0 then
            self:Msg('|cffffd700note:|r a Pet Journal filter is hiding your favorites; auto-summon now forces past it.')
        elseif forced == 0 then
            self:Msg('|cffff5555note:|r no favorited pets found — star some in the Pet Journal.')
        end
        self:Msg('summoned right now: ' .. tostring(C_PetJournal.GetSummonedPetGUID()))
    end

    local sel = p.selected
    if sel then
        self:Msg('selected pet: ' .. tostring(self:GetSelectedPetName())
            .. (petGuidIsValid(sel) and ' |cff55ff55(valid)|r' or ' |cffff5555(STALE → will use random)|r'))
    else
        self:Msg('selected pet: random from favorites')
    end
end
