-- MinimapButton.lua  (LibDBIcon-1.0 backed minimap button)
--
-- Same mechanism RareScanner / DBM / many other addons use. LibDBIcon handles
-- shape detection (round vs square via GetMinimapShape), Leatrix Plus /
-- ElvUI / MoveAny compatibility, drag-to-reposition, hide/show, and per-DB
-- position persistence. No custom math from us — we just hand it a data
-- object describing icon + click behaviour + tooltip.
local _, NCE = ...

-- fileID 132115 = Ability_Druid_CatForm — the iconic dark cat-face silhouette.
-- Numeric fileIDs survive patch icon-atlas reorgs in TWW; paths broke, IDs didn't.
local CAT_ICON = 132115

function NCE:InitMinimapButton()
    local LDB  = LibStub and LibStub('LibDataBroker-1.1', true)
    local LDBI = LibStub and LibStub('LibDBIcon-1.0',     true)
    if not (LDB and LDBI) then
        -- Libs failed to load. Bail rather than half-init.
        self:Msg('|cffff5555Minimap button:|r LibDBIcon-1.0 unavailable.')
        return
    end

    -- Reuse an existing LDB dataobject if some prior code path already
    -- registered one (defensive; usually nil on first load).
    local dataobj = LDB:GetDataObjectByName('nocat.extension')
        or LDB:NewDataObject('nocat.extension', {
            type = 'launcher',
            text = 'nocat',
            icon = CAT_ICON,
            OnClick = function(_, button)
                if button == 'LeftButton' then
                    NCE:OpenOptions()
                elseif button == 'RightButton' then
                    NCE:OpenList()
                end
            end,
            OnTooltipShow = function(tt)
                tt:AddLine('nocat', 1, 0.82, 0, 1)
                tt:AddLine('Left-click: Open settings',  0.8, 0.8, 0.8, 1)
                tt:AddLine('Right-click: Mob database',  0.8, 0.8, 0.8, 1)
                tt:AddLine('Drag: Reposition',           0.6, 0.6, 0.6, 1)
            end,
        })

    -- LDBI writes position state (hide, minimapPos angle, lock, etc.) into
    -- this table. Keep it on the global DB so it persists across reloads.
    self.db.global.minimapLDBI = self.db.global.minimapLDBI or { hide = false }

    -- Migrate the legacy `minimapHidden` flag into LDBI's `hide` field so
    -- existing users keep their show/hide preference across the rewrite.
    if self.db.global.minimapHidden and not self.db.global.minimapLDBI.hide then
        self.db.global.minimapLDBI.hide = true
    end

    LDBI:Register('nocat.extension', dataobj, self.db.global.minimapLDBI)
    self.minimapLDBI = LDBI
end

function NCE:ToggleMinimapButton()
    if not self.minimapLDBI then return end
    local hidden = not self.db.global.minimapLDBI.hide
    self.db.global.minimapLDBI.hide = hidden
    self.db.global.minimapHidden    = hidden  -- keep legacy flag in sync
    if hidden then
        self.minimapLDBI:Hide('nocat.extension')
    else
        self.minimapLDBI:Show('nocat.extension')
    end
    self:Msg('Minimap button: ' .. (hidden and 'hidden' or 'shown'))
end

function NCE:ResetMinimapPos()
    if not self.minimapLDBI then return end
    -- LDBI stores position as an angle (minimapPos) in the table we passed
    -- to Register. Nil it out so the lib falls back to its default placement.
    self.db.global.minimapLDBI.minimapPos = nil
    self.db.global.minimapLDBI.radius     = nil
    self.minimapLDBI:Refresh('nocat.extension', self.db.global.minimapLDBI)
    self:Msg('Minimap button position reset to default.')
end
