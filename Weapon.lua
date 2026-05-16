-- Weapon.lua  (keep weapon unsheathed — improved StayUnsheathed)
local _, NCE = ...

local SHEATHED = 1

-- Sound IDs we used to mute for "mute sheathe sounds". The list was wrong —
-- it included file IDs that play during normal attacks, which killed all
-- combat audio when the option was on. Unmute them at every load to undo
-- any persistent mute from a previous session before this fix.
local OLD_SHEATHE_SOUND_IDS = { 567473, 567498, 567456, 567430 }

-- Buffs/toys that behave like vehicles but don't set the vehicle flag
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

-- See PetCompanion.lua — same restricted-UI list: ToggleSheath can also be
-- blocked while these frames are shown, depending on engine version.
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

local function canUnsheathe()
    local u = NCE.db.global.unsheathe
    if not u.enabled                                    then return false end
    if InCombatLockdown()                               then return false end
    if UnitInVehicle('player')                          then return false end
    if IsSwimming() and GetUnitSpeed('player') > 0     then return false end
    if IsResting() and not u.inCities                  then return false end
    if inPseudoVehicle()                               then return false end
    if inRestrictedUI()                                 then return false end
    -- Per-spec check
    local ch   = NCE.db.char.unsheathe
    local spec = GetSpecialization()
    if spec and ch.specs and ch.specs[spec] and not ch.specs[spec].enabled then
        return false
    end
    return true
end

local function tryUnsheathe()
    if GetSheathState() == SHEATHED and canUnsheathe() then
        -- pcall: ToggleSheath can trigger a taint dialog in some TWW execution contexts
        pcall(ToggleSheath)
    end
end

-- Undo any sound mutes left over from the removed "Mute sheathe sounds"
-- feature. The IDs we'd been muting included combat audio, so leaving them
-- muted would silence attack sounds.
local function unmuteOldSheatheSounds()
    if not UnmuteSoundFile then return end
    for _, id in ipairs(OLD_SHEATHE_SOUND_IDS) do
        UnmuteSoundFile(id)
    end
end

local function initSpecs(ch)
    ch.specs = {}
    local n = GetNumSpecializations(false, false)
    for i = 1, n do
        local _, name, _, icon = GetSpecializationInfo(i)
        ch.specs[i] = { name = name, icon = icon, enabled = true }
    end
end

-- Events where the game definitely sheathes your weapon
local EVENTS = {
    'PLAYER_ENTERING_WORLD',
    'PLAYER_REGEN_ENABLED',
    'LOOT_CLOSED',
    'AUCTION_HOUSE_CLOSED',
    'UNIT_EXITED_VEHICLE',
    'BARBER_SHOP_CLOSE',
    'MERCHANT_CLOSED',
    'QUEST_FINISHED',
}

function NCE:InitWeapon()
    local ch = self.db.char.unsheathe
    if not ch.specs or #ch.specs == 0 then
        initSpecs(ch)
    end

    -- Clear any leftover mutes from the now-removed "mute sheathe sounds" option.
    unmuteOldSheatheSounds()

    local f = CreateFrame('Frame')
    for _, e in ipairs(EVENTS) do f:RegisterEvent(e) end
    f:RegisterEvent('UNIT_AURA')

    local wasMounted = IsMounted()

    f:SetScript('OnEvent', function(_, event, arg1)
        -- UNIT_AURA: only care about player, use it to detect dismount
        if event == 'UNIT_AURA' then
            if arg1 ~= 'player' then return end
            local nowMounted = IsMounted()
            if wasMounted and not nowMounted then
                -- just dismounted — short delay for state to settle
                C_Timer.After(0.5, tryUnsheathe)
            end
            wasMounted = nowMounted
            return
        end
        -- Defer: events like MERCHANT_CLOSED / QUEST_FINISHED fire BEFORE
        -- Blizzard's handler hides the frame, so inRestrictedUI() would
        -- still see :IsShown() == true and block the unsheathe. A short
        -- delay lets the frame actually hide first.
        C_Timer.After(0.15, tryUnsheathe)
    end)

    -- Fallback ticker: catches edge cases (swimming stops, toy wears off, etc.)
    -- 1s interval; stops itself when disabled
    self.unsheatheTimer = C_Timer.NewTicker(1, function()
        if NCE.db.global.unsheathe.enabled then tryUnsheathe() end
    end)

    C_Timer.After(1, tryUnsheathe)
end

-- ── Helpers called from Command / Options ────────────────────────────────────
function NCE:UnsheatheToggleSpec()
    local ch   = self.db.char.unsheathe
    local spec = GetSpecialization()
    if not spec or not ch.specs or #ch.specs == 0 then
        self:Msg('Specialization not available.'); return
    end
    ch.specs[spec].enabled = not ch.specs[spec].enabled
    self:Msg(string.format('Unsheathe for |cffffd700%s|r: %s',
        ch.specs[spec].name,
        ch.specs[spec].enabled and '|cff55ff55ON|r' or '|cffff5555OFF|r'))
end

function NCE:UnsheatheStatus()
    local u  = self.db.global.unsheathe
    local ch = self.db.char.unsheathe
    self:Msg('Unsheathe: ' .. (u.enabled and '|cff55ff55ON|r' or '|cffff5555OFF|r')
        .. '  Cities: ' .. (u.inCities and '|cff55ff55ON|r' or '|cffff5555OFF|r'))
    if ch.specs and #ch.specs > 0 then
        for i, s in ipairs(ch.specs) do
            self:Msg(string.format('  Spec %d |cffffd700%s|r: %s',
                i, s.name, s.enabled and '|cff55ff55ON|r' or '|cffff5555OFF|r'))
        end
    end
end
