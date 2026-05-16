-- Baganator.lua  (bridge: tell Baganator about the embedded CanIMogIt)
--
-- Baganator's API/ItemButton.lua already contains a CanIMogIt corner-widget
-- registration, but it lives inside
--     addonTable.Utilities.OnAddonLoaded("CanIMogIt", function() ... end)
-- which only fires when ADDON_LOADED is emitted for an addon named
-- "CanIMogIt". We bundled CanIMogIt's source files inside nocat.extension,
-- so that event never happens and Baganator's built-in hook stays dormant.
--
-- This file replays the same registration using Baganator's public API once
-- both Baganator and our embedded CanIMogIt are ready.
local _, NCE = ...

local function canRun()
    return _G.Baganator
       and _G.Baganator.API
       and _G.Baganator.API.RegisterCornerWidget
       and _G.CanIMogIt
       and _G.CIMI_AddToFrame
       and _G.CIMI_SetIcon
       and _G.CIMI_CheckOverlayIconEnabled
end

local function isPet(itemID)
    if not itemID then return false end
    local classID, subClassID = select(6, C_Item.GetItemInfoInstant(itemID))
    return classID == Enum.ItemClass.Battlepet
        or (classID == Enum.ItemClass.Miscellaneous and subClassID == Enum.ItemMiscellaneousSubclass.CompanionPet)
end

local registered = false
local function register()
    if registered then return end
    if not canRun() then return end
    registered = true

    -- Syndicator ships alongside Baganator and provides shared utilities.
    local IsEquipment = _G.Syndicator and _G.Syndicator.Utilities and _G.Syndicator.Utilities.IsEquipment
    local API = _G.Baganator.API

    API.RegisterCornerWidget('Can I Mog It', 'can_i_mog_it',
        -- Update callback: fires each time the item button re-renders.
        function(CIMIOverlay, details)
            local bagID  = details.itemLocation and details.itemLocation.bagID
            local slotID = details.itemLocation and details.itemLocation.slotIndex

            local function CIMI_Update(self)
                if not self or not self:GetParent() then return end
                if not CIMI_CheckOverlayIconEnabled(self) then
                    if self.CIMIIconTexture then self.CIMIIconTexture:SetShown(false) end
                    self:SetScript('OnUpdate', nil)
                    return
                end
                CIMI_SetIcon(self, CIMI_Update,
                    CanIMogIt:GetTooltipText(details.itemLink, bagID, slotID))
            end

            CIMI_SetIcon(CIMIOverlay, CIMI_Update,
                CanIMogIt:GetTooltipText(details.itemLink, bagID, slotID))

            -- Decide whether to render the overlay for this item class.
            return (IsEquipment and IsEquipment(details.itemLink))
                or (C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(details.itemID) ~= nil)
                or isPet(details.itemID)
                or (C_MountJournal and C_MountJournal.GetMountFromItem and C_MountJournal.GetMountFromItem(details.itemID) ~= nil)
                or (C_Item.IsDecorItem and C_Item.IsDecorItem(details.itemID))
                or (CanIMogIt.IsItemEnsemble and CanIMogIt:IsItemEnsemble(details.itemLink))
        end,
        -- Init callback: builds the texture frame attached to each item button.
        function(itemButton)
            CIMI_AddToFrame(itemButton, function() end)
            if itemButton.CanIMogItOverlay then
                itemButton.CanIMogItOverlay:SetSize(13, 13)
                if itemButton.CanIMogItOverlay.CIMIIconTexture then
                    itemButton.CanIMogItOverlay.CIMIIconTexture:SetPoint('TOPRIGHT')
                end
            end
            return itemButton.CanIMogItOverlay
        end,
        { corner = 'top_right', priority = 1 })

    -- Refresh hook: when the player learns a new appearance, toy, mount, etc.,
    -- ask Baganator to re-render its item buttons so the new state is shown.
    local function refresh()
        if API.IsCornerWidgetActive and API.IsCornerWidgetActive('can_i_mog_it') then
            if API.RequestItemButtonsRefresh and _G.Baganator.Constants then
                API.RequestItemButtonsRefresh({ _G.Baganator.Constants.RefreshReason.ItemWidgets })
            end
        end
    end

    if CanIMogIt.RegisterMessage then
        CanIMogIt:RegisterMessage('OptionUpdate', function() pcall(refresh) end)
    end

    local f = CreateFrame('Frame')
    f:RegisterEvent('TRANSMOG_COLLECTION_SOURCE_ADDED')
    f:RegisterEvent('NEW_PET_ADDED')
    f:RegisterEvent('NEW_TOY_ADDED')
    f:RegisterEvent('NEW_MOUNT_ADDED')
    if C_EventUtils and C_EventUtils.IsEventValid then
        if C_EventUtils.IsEventValid('PET_JOURNAL_PET_DELETED')   then f:RegisterEvent('PET_JOURNAL_PET_DELETED')   end
        if C_EventUtils.IsEventValid('HOUSE_DECOR_ADDED_TO_CHEST') then f:RegisterEvent('HOUSE_DECOR_ADDED_TO_CHEST') end
    end
    f:SetScript('OnEvent', refresh)
end

function NCE:InitBaganatorBridge()
    -- Public flag the options page can read.
    NCE._baganatorBridgeReady = false

    -- Try immediately in case both addons are already loaded.
    if canRun() then
        register()
        NCE._baganatorBridgeReady = registered
        return
    end

    -- Otherwise wait for PLAYER_LOGIN — by then Baganator and our embedded
    -- CanIMogIt should both be fully initialized.
    local frame = CreateFrame('Frame')
    frame:RegisterEvent('PLAYER_LOGIN')
    frame:RegisterEvent('PLAYER_ENTERING_WORLD')
    frame:SetScript('OnEvent', function(self)
        register()
        NCE._baganatorBridgeReady = registered
        if registered then self:UnregisterAllEvents() end
    end)
end

function NCE:IsBaganatorBridgeActive()
    return self._baganatorBridgeReady == true
end
