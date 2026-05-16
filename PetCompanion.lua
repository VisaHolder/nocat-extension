-- PetCompanion.lua  (auto-summon companion pet)
local _, NCE = ...

local PET_EVENTS = {
    'PLAYER_STARTED_MOVING',
    'PLAYER_STOPPED_MOVING',
    'PLAYER_REGEN_ENABLED',
    'UPDATE_STEALTH',
    'UNIT_EXITED_VEHICLE',
    'ZONE_CHANGED_NEW_AREA',
    'PLAYER_ENTERING_WORLD',
}

local INVIS_AURAS = { 199483, 32612, 110960 }  -- Camouflage, Invisibility, Greater Invisibility

-- Blizzard frames that, when shown, put the player in a "restricted UI" state
-- where calling C_PetJournal.SummonPetByGUID from a non-hardware event fires
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

local function CanSummon()
    if UnitAffectingCombat('player')                             then return false end
    if IsFlying() or UnitHasVehicleUI('player')                  then return false end
    if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE and IsMounted()    then return false end
    if UnitIsControlling('player') and UnitChannelInfo('player') then return false end
    if IsStealthed() or UnitIsGhost('player')                    then return false end
    if inRestrictedUI()                                          then return false end
    for _, id in ipairs(INVIS_AURAS) do
        if C_UnitAuras.GetPlayerAuraBySpellID(id) then return false end
    end
    if C_PetJournal.GetSummonedPetGUID() ~= nil then return false end
    return true
end

-- ── Pet-journal filter manipulation ──────────────────────────────────────────
-- GetPetInfoByIndex returns pets AFTER the player's journal filters are applied.
-- If the user filtered out "collected" pets in their journal UI, our scan would
-- return zero favorites even though they have plenty. To avoid that, we save
-- the current filter state, force "show collected", scan, then restore.
--
-- Filter index constants moved across WoW versions: the old global
-- LE_PET_JOURNAL_FILTER_COLLECTED was retired and replaced by
-- Enum.PetJournalFilter.Collected (and on some clients lives elsewhere).
-- Resolve both, prefer Enum, fall back to LE, otherwise skip the dance.
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
        -- pcall: SetFilterChecked may be removed on some clients despite existing
        -- as a function reference. Bail silently if it errors.
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

-- Called from the options panel when the user picks a specific pet. The click
-- itself IS a hardware event, so SummonPetByGUID is allowed here. We dismiss
-- any currently summoned pet first so the swap is visible immediately.
function NCE:SummonPet(guid)
    if not C_PetJournal or not C_PetJournal.SummonPetByGUID then return end
    if not guid then return end
    pcall(C_PetJournal.SummonPetByGUID, guid)
end

-- "Summon now" — re-evaluate which pet to summon (specific or random) and do it.
function NCE:TryAutoSummonNow()
    if not NCE.db or not NCE.db.global.pet then return end
    local selected = NCE.db.global.pet.selected
    if selected then
        self:SummonPet(selected)
        return
    end
    local favorites = self:GetFavoritePets()
    if #favorites == 0 then
        self:Msg('No favorited pets — favorite some in the Pet Journal first.')
        return
    end
    self:SummonPet(favorites[math.random(#favorites)].guid)
end

-- ── Auto-summon loop ─────────────────────────────────────────────────────────
-- Note: deliberately NOT using NCE:GetFavoritePets() here. That helper does a
-- filter save/clear/restore dance which is fine for one-shot UI calls but
-- would mutate journal state every time the event loop fires (e.g. on every
-- PLAYER_STARTED_MOVING). We iterate inline and trust the user's filter; if
-- it hides all favorites the auto-summon will skip, and the user can fix it.

local function autoSummon()
    if not NCE.db or not NCE.db.global.pet.enabled then return end
    if not CanSummon() then return end

    local selected = NCE.db.global.pet.selected
    if selected then
        pcall(C_PetJournal.SummonPetByGUID, selected)
        return
    end

    local numPets = C_PetJournal.GetNumPets()
    local favorites = {}
    for i = 1, numPets do
        local petID, _, owned, _, _, favorite = C_PetJournal.GetPetInfoByIndex(i)
        if owned and favorite and petID then
            favorites[#favorites + 1] = tostring(petID)
        end
    end
    if #favorites == 0 then return end
    pcall(C_PetJournal.SummonPetByGUID, favorites[math.random(#favorites)])
end

function NCE:InitPetCompanion()
    local f = CreateFrame('Frame')
    for _, event in ipairs(PET_EVENTS) do
        f:RegisterEvent(event)
    end
    f:SetScript('OnEvent', function(_, event, unit)
        if event == 'UNIT_EXITED_VEHICLE' and unit ~= 'player' then return end
        local delay = (event == 'ZONE_CHANGED_NEW_AREA' or event == 'PLAYER_ENTERING_WORLD') and 2 or 0.5
        C_Timer.After(delay, autoSummon)
    end)
end
