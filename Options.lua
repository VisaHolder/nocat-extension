-- Options.lua  (settings panel — Narcissus-style left nav with section dividers)
local _, NCE = ...

local cbCount = 0

local GOLD = { 1, 0.82, 0, 1 }
local GREY = { 0.62, 0.62, 0.62, 1 }
local DIM  = { 0.78, 0.78, 0.78, 1 }

-- ── Widget helpers ────────────────────────────────────────────────────────────

local function setColor(fs, c)
    fs:SetTextColor(c[1], c[2], c[3], c[4])
end

-- Page title bar: large gold caps + thick gold divider beneath
local function pageHeader(parent, text)
    local fs = parent:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    fs:SetPoint('TOPLEFT', 0, 0)
    fs:SetText(text:upper())
    setColor(fs, GOLD)

    local line = parent:CreateTexture(nil, 'ARTWORK')
    line:SetHeight(2)
    line:SetPoint('TOPLEFT', 0, -26)
    line:SetPoint('TOPRIGHT', 0, -26)
    line:SetColorTexture(1, 0.82, 0, 0.55)

    local glow = parent:CreateTexture(nil, 'BACKGROUND')
    glow:SetHeight(6)
    glow:SetPoint('TOPLEFT', 0, -28)
    glow:SetPoint('TOPRIGHT', 0, -28)
    glow:SetColorTexture(1, 0.82, 0, 0.10)
    return fs
end

-- Sub-section: small grey label with a horizontal rule extending to the right edge
local function section(parent, text, y)
    local fs = parent:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    fs:SetPoint('TOPLEFT', 0, y)
    fs:SetText(text)
    setColor(fs, GREY)

    local line = parent:CreateTexture(nil, 'ARTWORK')
    line:SetHeight(1)
    line:SetPoint('LEFT',  fs, 'RIGHT', 8, 0)
    line:SetPoint('RIGHT', parent, 'RIGHT', -4, 0)
    line:SetColorTexture(0.45, 0.45, 0.45, 0.45)
    return fs
end

local function makeCheck(parent, label, tip, getter, setter, x, y)
    cbCount = cbCount + 1
    local name = 'NCEOpt_CB_' .. cbCount
    local f = CreateFrame('CheckButton', name, parent, 'InterfaceOptionsCheckButtonTemplate')
    f:SetPoint('TOPLEFT', x, y)

    local lbl = _G[name .. 'Text']
    if lbl then lbl:SetText(label) end

    -- InterfaceOptionsCheckButtonTemplate technically respects tooltipText/
    -- tooltipRequirement, but only when shown from the Settings panel — when
    -- the checkbox lives in our own custom frame the template's OnEnter never
    -- fires. Wire it up explicitly so hover always works.
    if tip then
        f.tooltipText        = label
        f.tooltipRequirement = tip
        f:HookScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tip, 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        f:HookScript('OnLeave', function() GameTooltip:Hide() end)
    end

    f:SetScript('OnShow',  function(self) self:SetChecked(getter()) end)
    f:SetScript('OnClick', function(self) setter(self:GetChecked() and true or false) end)
    return f
end

local function makeNum(parent, label, tip, getter, setter, x, y, allW)
    local lbl = parent:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    lbl:SetPoint('TOPLEFT', x, y)
    lbl:SetText(label)
    local eb = CreateFrame('EditBox', nil, parent, 'InputBoxTemplate')
    eb:SetSize(60, 20)
    eb:SetPoint('LEFT', lbl, 'RIGHT', 8, 0)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    if tip then
        eb:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
            GameTooltip:SetText(tip, 0.85, 0.85, 0.85, 1, true)
            GameTooltip:Show()
        end)
        eb:SetScript('OnLeave', function() GameTooltip:Hide() end)
    end
    eb:SetScript('OnShow',            function(s) s:SetText(tostring(getter() or 0)) end)
    eb:SetScript('OnEditFocusGained', function(s) s:HighlightText() end)
    eb:SetScript('OnEnterPressed',    function(s) setter(tonumber(s:GetText())); s:ClearFocus() end)
    eb:SetScript('OnEscapePressed',   function(s) s:SetText(tostring(getter() or 0)); s:ClearFocus() end)
    if allW then allW[#allW+1] = eb end
    return eb
end

local function makeText(parent, label, tip, getter, setter, x, y, w, allW)
    local lbl = parent:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    lbl:SetPoint('TOPLEFT', x, y)
    lbl:SetText(label)
    local eb = CreateFrame('EditBox', nil, parent, 'InputBoxTemplate')
    eb:SetSize(w or 200, 20)
    eb:SetPoint('TOPLEFT', lbl, 'BOTTOMLEFT', 2, -6)
    eb:SetAutoFocus(false)
    if tip then
        eb:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
            GameTooltip:SetText(tip, 0.85, 0.85, 0.85, 1, true)
            GameTooltip:Show()
        end)
        eb:SetScript('OnLeave', function() GameTooltip:Hide() end)
    end
    eb:SetScript('OnShow',            function(s) s:SetText(getter() or '') end)
    eb:SetScript('OnEditFocusGained', function(s) s:HighlightText() end)
    eb:SetScript('OnEnterPressed',    function(s)
        local v = s:GetText(); setter(v == '' and nil or v); s:ClearFocus()
    end)
    eb:SetScript('OnEscapePressed',   function(s) s:SetText(getter() or ''); s:ClearFocus() end)
    if allW then allW[#allW+1] = eb end
end

-- Button that opens a context menu. `buildMenu` is a function(root, refresh)
-- that populates the menu using the TWW Menu API (MenuUtil/rootDescription).
-- `getLabel` returns the current label text shown on the button.
local function makeMenuBtn(parent, getLabel, w, x, y, buildMenu, tip)
    local b = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
    b:SetSize(w, 22)
    b:SetPoint('TOPLEFT', x, y)
    local refresh = function() b:SetText(getLabel() or '') end
    refresh()
    b.Refresh = refresh
    if tip then
        b:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_TOPRIGHT')
            GameTooltip:SetText(tip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        b:SetScript('OnLeave', function() GameTooltip:Hide() end)
    end
    b:SetScript('OnClick', function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                buildMenu(root, refresh)
            end)
        end
    end)
    b:SetScript('OnShow', refresh)
    return b
end

local function makeBtn(parent, label, tip, w, x, y, fn)
    local b = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
    b:SetSize(w, 22)
    b:SetPoint('TOPLEFT', x, y)
    b:SetText(label)
    if tip then
        b:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_TOPRIGHT')
            GameTooltip:SetText(tip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        b:SetScript('OnLeave', function() GameTooltip:Hide() end)
    end
    b:SetScript('OnClick', fn)
    return b
end

-- ── Build panel ───────────────────────────────────────────────────────────────
function NCE:InitOptions()
    local NAV_W   = 156
    local SEP_X   = NAV_W + 4
    local CONT_OX = SEP_X + 24    -- content left-offset
    local CONT_TY = -56           -- content top-offset (below title bar)

    local panel = CreateFrame('Frame', 'NCEOptionsPanel', UIParent, 'BackdropTemplate')
    panel:SetSize(720, 600)
    panel:SetPoint('CENTER')
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag('LeftButton')
    panel:SetScript('OnDragStart', panel.StartMoving)
    panel:SetScript('OnDragStop',  panel.StopMovingOrSizing)
    panel:SetBackdrop({
        bgFile   = 'Interface\\DialogFrame\\UI-DialogBox-Background',
        edgeFile = 'Interface\\DialogFrame\\UI-DialogBox-Border',
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    panel:SetToplevel(true)
    panel:Hide()

    -- Close button
    local closeBtn = CreateFrame('Button', nil, panel, 'UIPanelCloseButton')
    closeBtn:SetPoint('TOPRIGHT', panel, 'TOPRIGHT', -4, -4)
    closeBtn:SetScript('OnClick', function() panel:Hide() end)

    local title = panel:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    title:SetPoint('TOPLEFT', 18, -16)
    title:SetText('nocat')

    local sub = panel:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    sub:SetPoint('TOPLEFT', title, 'BOTTOMLEFT', 0, -2)
    sub:SetText('Type |cffffd700/nocat help|r for the full command list.')

    -- Header divider line spanning full width
    local hdrLine = panel:CreateTexture(nil, 'ARTWORK')
    hdrLine:SetHeight(1)
    hdrLine:SetPoint('TOPLEFT',  0, -48)
    hdrLine:SetPoint('TOPRIGHT', 0, -48)
    hdrLine:SetColorTexture(1, 0.82, 0, 0.25)

    -- Nav background (subtle dark column)
    local navBg = panel:CreateTexture(nil, 'BACKGROUND')
    navBg:SetPoint('TOPLEFT', 0, -49)
    navBg:SetPoint('BOTTOMLEFT', 0, 0)
    navBg:SetWidth(NAV_W)
    navBg:SetColorTexture(0, 0, 0, 0.28)

    -- Vertical separator between nav and content
    local vSep = panel:CreateTexture(nil, 'ARTWORK')
    vSep:SetWidth(1)
    vSep:SetPoint('TOP',    panel, 'TOPLEFT',    SEP_X, -49)
    vSep:SetPoint('BOTTOM', panel, 'BOTTOMLEFT', SEP_X,   0)
    vSep:SetColorTexture(0.3, 0.3, 0.3, 0.9)

    -- ── Page factory ─────────────────────────────────────────────────────────
    local function makePage()
        local f = CreateFrame('Frame', nil, panel)
        f:SetPoint('TOPLEFT',     CONT_OX, CONT_TY)
        f:SetPoint('BOTTOMRIGHT', -16, 14)
        f:Hide()
        return f
    end

    local allChecks  = {}
    local allEditBox = {}

    -- ── PAGE: Kill Tracker ────────────────────────────────────────────────────
    local pgT = makePage()
    pageHeader(pgT, 'Kill Tracker')

    section(pgT, 'Tracking', -48)
    allChecks[#allChecks+1] = makeCheck(pgT,
        'Count kills made by party and raid members',
        'Credits group member kills as your own.',
        function() return NCE.db.global.tracker.countmode end,
        function(v) NCE.db.global.tracker.countmode = v end,
        4, -66)
    allChecks[#allChecks+1] = makeCheck(pgT,
        'Disable tracking in dungeons',
        'Pauses kill recording inside 5-man instances.',
        function() return NCE.db.global.tracker.disableDungeons end,
        function(v) NCE.db.global.tracker.disableDungeons = v end,
        4, -90)
    allChecks[#allChecks+1] = makeCheck(pgT,
        'Disable tracking in raids',
        'Pauses kill recording inside raid instances.',
        function() return NCE.db.global.tracker.disableRaids end,
        function(v) NCE.db.global.tracker.disableRaids = v end,
        4, -114)

    section(pgT, 'Display', -148)
    allChecks[#allChecks+1] = makeCheck(pgT,
        'Show kill count in mob tooltip',
        'Adds a kill count line when hovering over an enemy.',
        function() return NCE.db.global.tracker.tooltip end,
        function(v) NCE.db.global.tracker.tooltip = v end,
        4, -166)
    allChecks[#allChecks+1] = makeCheck(pgT,
        'Show XP per kill in tooltip',
        'Estimates XP/kill and kills needed to reach your next level.',
        function() return NCE.db.global.tracker.showexp end,
        function(v) NCE.db.global.tracker.showexp = v end,
        4, -190)
    allChecks[#allChecks+1] = makeCheck(pgT,
        'Print every kill to chat',
        'Posts a message after each kill.',
        function() return NCE.db.global.tracker.print end,
        function(v) NCE.db.global.tracker.print = v end,
        4, -214)
    allChecks[#allChecks+1] = makeCheck(pgT,
        'Print new mob discoveries to chat',
        'One-time message the first time you kill a mob you have never killed before.',
        function() return NCE.db.global.tracker.printnew end,
        function(v) NCE.db.global.tracker.printnew = v end,
        4, -238)

    section(pgT, 'Thresholds', -272)
    makeNum(pgT,
        'Milestone alert every N kills  (0 = off):',
        'Shows a big on-screen popup when your kill count hits a multiple of N.',
        function() return NCE.db.global.tracker.threshold end,
        function(v) NCE.db.global.tracker.threshold = v or 1000 end,
        4, -292, allEditBox)
    makeNum(pgT,
        'Instant counter alert every N kills  (0 = off):',
        'Plays a sound and raid warning when the floating counter hits a multiple of N.',
        function() return NCE.db.global.tracker.immThreshold end,
        function(v) NCE.db.global.tracker.immThreshold = v or 0 end,
        4, -318, allEditBox)
    makeText(pgT,
        'Instant counter name filter  (blank = all mobs):',
        'Only mobs whose names contain this text are counted by the instant counter.',
        function() return NCE.db.global.tracker.immFilter end,
        function(v) NCE.db.global.tracker.immFilter = v end,
        4, -346, 220, allEditBox)

    section(pgT, 'Quick Actions', -396)
    makeBtn(pgT, 'Mob List',     'Open the full kill database.',                    100, 4,   -416, function() NCE:OpenList() end)
    makeBtn(pgT, 'Kill Counter', 'Show/hide the floating instant kill counter.',    110, 110, -416, function() NCE:OpenImmediate() end)
    makeBtn(pgT, 'Announce',     'Post session kill stats to chat.',                90,  226, -416, function() NCE:SlashAnnounce('') end)
    makeBtn(pgT, 'Target Kills', 'Show kill count for your current target.',        100, 4,   -442,
        function()
            if not UnitExists('target') or UnitIsPlayer('target') then
                NCE:Msg('No valid target.')
            else
                local id = NCE:npcFromGUID(UnitGUID('target'))
                if id then NCE:PrintKills(id)
                else NCE:Msg('Target is not a creature.') end
            end
        end)
    makeBtn(pgT, 'Purge Junk', 'Remove all mobs with fewer than 2 global kills.',  100, 110, -442, function() NCE:SlashPurge(2) end)
    makeBtn(pgT, 'Reset All',  'Permanently wipe all kill records.',                90,  226, -442,
        function()
            StaticPopupDialogs['NCE_RESET'] = {
                text='Reset ALL nocat kill data? This cannot be undone.',
                button1='Reset', button2='Cancel',
                OnAccept=function() NCE:SlashReset() end,
                timeout=0, whileDead=true, hideOnEscape=true,
            }
            StaticPopup_Show('NCE_RESET')
        end)

    -- ── PAGE: Pet Companion ───────────────────────────────────────────────────
    local pgP = makePage()
    pageHeader(pgP, 'Pet Companion')
    section(pgP, 'Behavior', -48)
    allChecks[#allChecks+1] = makeCheck(pgP,
        'Automatically summon a companion pet',
        'Summons a pet whenever you become eligible\n(out of combat, not mounted, not stealthed, etc.).',
        function() return NCE.db.global.pet.enabled end,
        function(v) NCE.db.global.pet.enabled = v end,
        4, -66)

    section(pgP, 'Selection', -100)
    local petLbl = pgP:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    petLbl:SetPoint('TOPLEFT', 4, -120)
    petLbl:SetText('Pet to summon:')

    local function petLabel()
        local sel = NCE.db.global.pet.selected
        if not sel then return 'Random from favorites' end
        return NCE:GetSelectedPetName() or 'Unknown pet'
    end

    local function buildPetMenu(root, refresh)
        root:CreateButton('Random from favorites', function()
            NCE.db.global.pet.selected = nil
            refresh()
            NCE:TryAutoSummonNow()
            return MenuResponse and MenuResponse.CloseAll
        end)
        local pets = NCE:GetFavoritePets()
        if #pets == 0 then
            root:CreateTitle('|cffff5555No favorited pets found|r')
            root:CreateTitle('Favorite some in the Pet Journal first.')
        else
            for _, p in ipairs(pets) do
                root:CreateButton(p.name, function()
                    NCE.db.global.pet.selected = p.guid
                    refresh()
                    NCE:SummonPet(p.guid)
                    return MenuResponse and MenuResponse.CloseAll
                end)
            end
        end
    end

    -- Prefer the modern WowStyle1Dropdown template (TWW) — it's a real
    -- dropdown that draws an arrow and handles menu lifecycle properly.
    -- pcall the CreateFrame call: XML template availability isn't observable
    -- as a global, so we try to create it and fall back to our generic
    -- menu-button helper if the template doesn't exist on this client.
    local petPicker
    local ok, dropdown = pcall(CreateFrame, 'DropdownButton', nil, pgP, 'WowStyle1DropdownTemplate')
    if ok and dropdown and dropdown.SetupMenu then
        petPicker = dropdown
        petPicker:SetSize(260, 30)
        petPicker:SetPoint('TOPLEFT', 130, -114)

        local function refresh()
            local text = petLabel()
            if petPicker.SetDefaultText then petPicker:SetDefaultText(text) end
            if petPicker.OverrideText   then petPicker:OverrideText(text)   end
        end

        petPicker:SetupMenu(function(_, root) buildPetMenu(root, refresh) end)
        refresh()
        pgP:HookScript('OnShow', refresh)

        petPicker:HookScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
            GameTooltip:SetText('Pet to summon', 1, 1, 1)
            GameTooltip:AddLine('Choose a specific pet, or "Random from favorites" to rotate through your favorited pets.',
                0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        petPicker:HookScript('OnLeave', function() GameTooltip:Hide() end)
    else
        petPicker = makeMenuBtn(pgP, petLabel, 260, 130, -118, buildPetMenu,
            'Choose which pet to summon. Pick "Random from favorites" to rotate through favorited pets.')
    end

    makeBtn(pgP, 'Summon Now',
        'Force-summon the currently selected pet (or a random favorite).',
        110, 396, -118,
        function() NCE:TryAutoSummonNow() end)

    -- ── PAGE: Map Zoom ────────────────────────────────────────────────────────
    local pgM = makePage()
    pageHeader(pgM, 'Map Zoom')
    section(pgM, 'Behavior', -48)
    allChecks[#allChecks+1] = makeCheck(pgM,
        'Follow player on the map',
        'Keeps the world map centred on your character as you move.',
        function() return NCE.db.global.zoom.follow end,
        function(v) NCE.db.global.zoom.follow = v; NCE:ApplyFollowState() end,
        4, -66)

    -- ── PAGE: Weapon Unsheathe ────────────────────────────────────────────────
    local pgW = makePage()
    pageHeader(pgW, 'Weapon Unsheathe')
    section(pgW, 'Behavior', -48)
    allChecks[#allChecks+1] = makeCheck(pgW,
        'Keep weapon unsheathed',
        'Automatically re-unsheathes your weapon whenever it gets put away.',
        function() return NCE.db.global.unsheathe.enabled end,
        function(v) NCE.db.global.unsheathe.enabled = v end,
        4, -66)
    allChecks[#allChecks+1] = makeCheck(pgW,
        'Stay unsheathed in cities',
        'Also keeps weapon drawn while resting in cities and inns.',
        function() return NCE.db.global.unsheathe.inCities end,
        function(v) NCE.db.global.unsheathe.inCities = v end,
        4, -90)

    section(pgW, 'Specialization', -120)
    makeBtn(pgW, 'Toggle Current Spec',
        'Enable or disable unsheathe for your active specialization.',
        160, 4, -140,
        function() NCE:UnsheatheToggleSpec() end)

    -- ── PAGE: Transmog (controls the embedded CanIMogIt) ─────────────────────
    local pgX = makePage()
    pageHeader(pgX, 'Transmog')

    -- Settings here read/write directly into the embedded CanIMogIt's own
    -- SavedVariable table (CanIMogItOptions). The embedded copy of the addon
    -- is the actual engine; this page is the UI for it inside /nocat.
    local function cimGet(var)
        if not _G.CanIMogItOptions then return false end
        return _G.CanIMogItOptions[var]
    end
    local function cimSet(var, value)
        if not _G.CanIMogItOptions then return end
        _G.CanIMogItOptions[var] = value
        if _G.CanIMogIt and _G.CanIMogIt.ResetCache  then _G.CanIMogIt:ResetCache()  end
        if _G.CanIMogIt and _G.CanIMogIt.SendMessage then _G.CanIMogIt:SendMessage('OptionUpdate') end
    end

    local cimBanner = pgX:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    cimBanner:SetPoint('TOPLEFT', 4, -34)
    cimBanner:SetPoint('TOPRIGHT', 0, -34)
    cimBanner:SetJustifyH('LEFT')

    local function refreshBanner()
        if _G.CanIMogIt and _G.CanIMogItOptions then
            cimBanner:SetText('|cff55ff55Transmog engine active.|r Tooltip overlays will show on items.')
        else
            cimBanner:SetText('|cffff5555Transmog engine failed to load.|r Make sure the standalone CanIMogIt addon is disabled or removed, then /reload.')
        end
    end
    refreshBanner()
    pgX:SetScript('OnShow', refreshBanner)

    section(pgX, 'Filters', -58)
    local function cimCheck(label, tip, var, x, y)
        local f = makeCheck(pgX, label, tip,
            function() return cimGet(var) end,
            function(v) cimSet(var, v) end,
            x, y)
        allChecks[#allChecks+1] = f
        return f
    end

    cimCheck('Equippable items only',
        'Only show the icon/tooltip on items that can be equipped.',
        'showEquippableOnly', 4, -78)
    cimCheck('Transmoggable items only',
        'Only show on items that can be transmogged.',
        'showTransmoggableOnly', 4, -102)
    cimCheck('Unknown items only',
        "Only show on items you haven't learned the appearance for.",
        'showUnknownOnly', 4, -126)
    cimCheck('Show transmog set info',
        'Show set summary lines in the tooltip and appearance UI.',
        'showSetInfo', 4, -150)

    section(pgX, 'Display', -184)
    cimCheck('Show bag overlay icons',
        'Render the small status icon directly on items in your bags.',
        'showItemIconOverlay', 4, -204)
    cimCheck('Verbose tooltip text',
        'Show longer, more detailed tooltip lines.',
        'showVerboseText', 4, -228)
    cimCheck('Show source location',
        "Show where an appearance drops from (quest, vendor, world drop, etc.).",
        'showSourceLocationTooltip', 4, -252)

    section(pgX, 'Item Types', -286)
    cimCheck('Toys',      'Show on toy items.',          'showToyItems',         4,   -306)
    cimCheck('Pets',      'Show on pet items.',          'showPetItems',         220, -306)
    cimCheck('Mounts',    'Show on mount items.',        'showMountItems',       4,   -330)
    cimCheck('Catalyst',  'Show on catalyzable items.',  'showCatalizableItems', 220, -330)
    cimCheck('Ensembles', 'Show on ensemble items.',     'showEnsembleItems',    4,   -354)
    cimCheck('Decor',     'Show on decor items.',        'showDecorItems',       220, -354)

    section(pgX, 'Bag Addon Integrations', -388)
    local bagStatus = pgX:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    bagStatus:SetPoint('TOPLEFT', 4, -408)
    bagStatus:SetJustifyH('LEFT')

    local function refreshBagStatus()
        if not _G.Baganator then
            bagStatus:SetText('Baganator: |cffaaaaaanot installed|r')
        elseif NCE:IsBaganatorBridgeActive() then
            bagStatus:SetText('Baganator: |cff55ff55connected|r — overlay icons enabled in your bags.')
        else
            bagStatus:SetText('Baganator: |cffff5555detected but bridge not active|r — /reload to retry.')
        end
    end
    refreshBagStatus()
    pgX:HookScript('OnShow', refreshBagStatus)

    -- ── PAGE: General ─────────────────────────────────────────────────────────
    local pgG = makePage()
    pageHeader(pgG, 'General')
    section(pgG, 'Startup', -48)
    allChecks[#allChecks+1] = makeCheck(pgG,
        'Show "Loaded" message on login',
        'Prints a brief confirmation in chat when the addon finishes loading.',
        function() return NCE.db.global.loadmessage end,
        function(v) NCE.db.global.loadmessage = v end,
        4, -66)

    -- ── Nav categories ────────────────────────────────────────────────────────
    local CATS = {
        { label = 'Kill Tracker',     page = pgT },
        { label = 'Pet Companion',    page = pgP },
        { label = 'Map Zoom',         page = pgM },
        { label = 'Weapon',           page = pgW },
        { label = 'Transmog',         page = pgX },
        { label = 'General',          page = pgG },
    }

    local activeCat = nil

    local function showCat(idx)
        for i, cat in ipairs(CATS) do
            cat.page:SetShown(i == idx)
            if cat.labelFS then
                if i == idx then
                    setColor(cat.labelFS, GOLD)
                else
                    setColor(cat.labelFS, DIM)
                end
            end
            if cat.selBar    then cat.selBar:SetShown(i == idx)    end
            if cat.selBg     then cat.selBg:SetShown(i == idx)     end
            if cat.arrow     then cat.arrow:SetShown(i == idx)     end
        end
        for _, eb in ipairs(allEditBox) do
            if eb:IsVisible() then
                local s = eb:GetScript('OnShow')
                if s then s(eb) end
            end
        end
        activeCat = idx
    end

    for i, cat in ipairs(CATS) do
        local btn = CreateFrame('Button', nil, panel)
        btn:SetSize(NAV_W - 2, 30)
        btn:SetPoint('TOPLEFT', 2, -60 - (i - 1) * 32)

        -- Selected background tint
        local bg = btn:CreateTexture(nil, 'BACKGROUND')
        bg:SetPoint('TOPLEFT', 3, 0)
        bg:SetPoint('BOTTOMRIGHT', 0, 0)
        bg:SetColorTexture(1, 0.82, 0, 0.08)
        bg:Hide()
        cat.selBg = bg

        -- Gold left bar for active state
        local bar = btn:CreateTexture(nil, 'ARTWORK')
        bar:SetWidth(3)
        bar:SetPoint('TOPLEFT', 0, 0)
        bar:SetPoint('BOTTOMLEFT', 0, 0)
        bar:SetColorTexture(1, 0.82, 0, 1)
        bar:Hide()
        cat.selBar = bar

        -- Hover effect
        local hl = btn:CreateTexture(nil, 'HIGHLIGHT')
        hl:SetPoint('TOPLEFT', 3, 0)
        hl:SetPoint('BOTTOMRIGHT', 0, 0)
        hl:SetColorTexture(1, 1, 1, 0.06)

        -- Label
        local fs = btn:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        fs:SetPoint('LEFT', btn, 'LEFT', 16, 0)
        fs:SetJustifyH('LEFT')
        fs:SetText(cat.label)
        setColor(fs, DIM)
        cat.labelFS = fs

        btn:SetScript('OnClick', function() showCat(i) end)
    end

    -- ── Footer (left nav bottom) ──────────────────────────────────────────────
    local footerLine = panel:CreateTexture(nil, 'ARTWORK')
    footerLine:SetHeight(1)
    footerLine:SetPoint('BOTTOMLEFT',  2,           34)
    footerLine:SetPoint('BOTTOMRIGHT', panel, 'BOTTOMLEFT', NAV_W - 2, 34)
    footerLine:SetColorTexture(0.4, 0.4, 0.4, 0.4)

    local ver = panel:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    ver:SetPoint('BOTTOMLEFT', 14, 12)
    ver:SetText('v1.0.0')

    -- Sync state on open
    panel:SetScript('OnShow', function()
        for _, cb in ipairs(allChecks) do
            local s = cb:GetScript('OnShow')
            if s then s(cb) end
        end
        showCat(activeCat or 1)
    end)

    self.optionsPanel = panel
end

function NCE:OpenOptions()
    local p = self.optionsPanel
    if not p then return end
    if p:IsShown() then p:Hide() else p:Show() end
end
