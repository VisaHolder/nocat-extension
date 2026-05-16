-- MapZoom.lua  (follow player on the world map)
local _, NCE = ...

local followPoll = nil
local hookedMap  = false

-- Canvas method references cached at hook time
local fnSetH, fnSetV
local fnGetW, fnGetH2, fnGetHRange, fnGetVRange

-- Last scroll value we wrote — used to skip redundant updates that
-- would otherwise force a map re-render every tick and stutter the
-- camera when flying.
local lastSx, lastSy = nil, nil

-- Minimum scroll delta before we bother updating. Below this the visible
-- change is sub-pixel and the re-render cost isn't worth it — without
-- this gate the map re-renders 4x/sec while you fly and feels laggy.
local SCROLL_EPSILON = 0.0015

local function zoom() return NCE.db and NCE.db.global.zoom end

local function currentMapID()
    return WorldMapFrame and WorldMapFrame:GetMapID()
end

local function playerPosOnMap(mapID)
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, 'player')
    if not ok or not pos then return nil end
    local x, y = pos:GetXY()
    if not x or not y or (x == 0 and y == 0) then return nil end
    return x, y
end

-- Runs every 0.25s while map is open AND follow is enabled.
local function followTick()
    local z = zoom()
    if not z or not z.follow then return end
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end

    local mapID = currentMapID()
    if not mapID then return end

    local px, py = playerPosOnMap(mapID)
    if not px then return end

    local vw = fnGetW  and fnGetW()  or 0
    local vh = fnGetH2 and fnGetH2() or 0
    if vw <= 0 or vh <= 0 then return end

    local hRange = fnGetHRange and fnGetHRange() or 0
    local vRange = fnGetVRange and fnGetVRange() or 0

    -- Convert normalised map position (0-1) → normalised scroll value (0-1)
    local sx, sy = 0.5, 0.5
    if hRange > 0 then
        sx = math.max(0, math.min(1, (px * (hRange + vw) - vw * 0.5) / hRange))
    end
    if vRange > 0 then
        sy = math.max(0, math.min(1, (py * (vRange + vh) - vh * 0.5) / vRange))
    end

    if lastSx and lastSy
       and math.abs(sx - lastSx) < SCROLL_EPSILON
       and math.abs(sy - lastSy) < SCROLL_EPSILON then
        return
    end

    if hRange > 0 and fnSetH then fnSetH(sx); lastSx = sx end
    if vRange > 0 and fnSetV then fnSetV(sy); lastSy = sy end
end

local function startFollow()
    if followPoll then return end
    lastSx, lastSy = nil, nil
    followPoll = C_Timer.NewTicker(0.25, followTick)
    followTick()
end

local function stopFollow()
    if followPoll then followPoll:Cancel(); followPoll = nil end
    lastSx, lastSy = nil, nil
end

function NCE:ApplyFollowState()
    local z = zoom()
    if not z then return end
    if WorldMapFrame and WorldMapFrame:IsShown() then
        if z.follow then startFollow() else stopFollow() end
    end
end

local function hookMap()
    if hookedMap then return end
    local c = WorldMapFrame and WorldMapFrame.ScrollContainer
    if not c then return end
    hookedMap = true

    if c.SetNormalizedHorizontalScroll then fnSetH      = function(v) c:SetNormalizedHorizontalScroll(v)       end end
    if c.SetNormalizedVerticalScroll   then fnSetV      = function(v) c:SetNormalizedVerticalScroll(v)         end end
    if c.GetWidth                      then fnGetW      = function()  return c:GetWidth()                      end end
    if c.GetHeight                     then fnGetH2     = function()  return c:GetHeight()                     end end
    if c.GetHorizontalScrollRange      then fnGetHRange = function()  return c:GetHorizontalScrollRange()      end end
    if c.GetVerticalScrollRange        then fnGetVRange = function()  return c:GetVerticalScrollRange()        end end

    hooksecurefunc(WorldMapFrame, 'SetMapID', function()
        lastSx, lastSy = nil, nil
        local z = zoom()
        if z and z.follow then followTick() end
    end)

    WorldMapFrame:HookScript('OnShow', function()
        local z = zoom()
        if z and z.follow then startFollow() end
    end)

    WorldMapFrame:HookScript('OnHide', function()
        stopFollow()
    end)
end

function NCE:InitMapZoom()
    local loader = CreateFrame('Frame')
    loader:RegisterEvent('ADDON_LOADED')
    loader:RegisterEvent('PLAYER_LOGIN')
    loader:SetScript('OnEvent', function(self, event, arg1)
        if event == 'ADDON_LOADED' and arg1 == 'Blizzard_WorldMap' then
            hookMap()
            self:UnregisterEvent('ADDON_LOADED')
        elseif event == 'PLAYER_LOGIN' then
            self:UnregisterEvent('PLAYER_LOGIN')
            if C_AddOns and C_AddOns.IsAddOnLoaded('Blizzard_WorldMap') then
                hookMap()
            end
        end
    end)
end
