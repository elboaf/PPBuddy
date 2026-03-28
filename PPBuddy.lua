-- PPBuddy.lua
-- Mini buff status bar for non-Paladins using PallyPowerTW data.
-- Shows which blessings are assigned to your class, highlights have/missing,
-- lets you click a missing buff to whisper the assigned paladin,
-- and lets you ban (auto-remove) any buff via a checkbox.

-- ============================================================
-- Config / saved vars
-- ============================================================
PPBuddy_Config = {
    banned = {},    -- [blessingID] = true if banned
    posX   = nil,
    posY   = nil,
}

-- ============================================================
-- Internal state
-- ============================================================
local ADDON_NAME    = "PPBuddy"
local UPDATE_FREQ   = 2          -- seconds between UI refreshes
local timeSince     = 0

-- Blessing name table (mirrors PallyPower_BlessingID from PallyPowerTW)
-- Index matches PallyPower_Assignments[pallyName][classID] values (0-5)
local BlessingNames = {
    [0] = "Wisdom",
    [1] = "Might",
    [2] = "Salvation",
    [3] = "Light",
    [4] = "Kings",
    [5] = "Sanctuary",
}

-- Blessing buff texture fragments used by PallyPowerTW (Greater Blessing icons)
-- These match the BuffIcon[] table in PallyPower.lua (indexed 0-5 by blessing ID)
local BlessingTextures = {
    [0] = "Spell_Holy_GreaterBlessingofWisdom",
    [1] = "Spell_Holy_GreaterBlessingofKings",    -- Might uses Kings icon slot 1
    [2] = "Spell_Holy_GreaterBlessingofSalvation",
    [3] = "Spell_Holy_GreaterBlessingofLight",
    [4] = "Spell_Magic_GreaterBlessingofKings",   -- Kings
    [5] = "Spell_Holy_GreaterBlessingofSanctuary",
}

-- Regular blessing texture fragments (BuffIconSmall[] in PallyPower.lua)
local BlessingTexturesSmall = {
    [0] = "Spell_Holy_SealOfWisdom",
    [1] = "Spell_Holy_FistOfJustice",
    [2] = "Spell_Holy_SealOfSalvation",
    [3] = "Spell_Holy_PrayerOfHealing02",
    [4] = "Spell_Magic_MageArmor",
    [5] = "Spell_Nature_LightningShield",
}

-- Full interface paths for icons (matching what PallyPowerTW uses)
local ICON_PREFIX = "Interface\\AddOns\\PallyPowerTW\\Icons\\"

local BlessingIcons = {
    [0] = ICON_PREFIX .. "Spell_Holy_GreaterBlessingofWisdom",
    [1] = ICON_PREFIX .. "Spell_Holy_GreaterBlessingofKings",
    [2] = ICON_PREFIX .. "Spell_Holy_GreaterBlessingofSalvation",
    [3] = ICON_PREFIX .. "Spell_Holy_GreaterBlessingofLight",
    [4] = ICON_PREFIX .. "Spell_Magic_GreaterBlessingofKings",
    [5] = ICON_PREFIX .. "Spell_Holy_GreaterBlessingofSanctuary",
}

-- PallyPower class IDs (mirrors PallyPower_ClassID from localization)
-- Key: the TOKEN returned by UnitClass() second arg (always English in 1.12)
-- Value: the numeric class slot PallyPower uses in Assignments[pallyName][classID]
local ClassTokenToID = {
    WARRIOR  = 0,
    ROGUE    = 1,
    PRIEST   = 2,
    DRUID    = 3,
    PALADIN  = 4,
    HUNTER   = 5,
    MAGE     = 6,
    WARLOCK  = 7,
    SHAMAN   = 8,
    -- class 9 = Hunter Pets (shares slot 0/Warriors in PP logic)
}

-- ============================================================
-- Helpers
-- ============================================================

local function PPB_Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00PPBuddy:|r " .. tostring(msg))
end

-- Get PallyPower class ID for the local player.
-- UnitClass() in 1.12 returns (localizedName, token) — token is always English uppercase.
local function PPB_GetMyClassID()
    local _, token = UnitClass("player")
    if not token then return nil end
    return ClassTokenToID[token]
end

--- Check whether the player currently has a specific blessing buff.
-- UnitBuff in 1.12 returns the texture path string (or nil when done).
local function PPB_HasBuff(blessingID)
    local fragGreat = BlessingTextures[blessingID]
    local fragSmall = BlessingTexturesSmall[blessingID]
    local i = 1
    while true do
        local tex = UnitBuff("player", i)
        if not tex then break end
        if fragGreat and string.find(tex, fragGreat) then return true end
        if fragSmall and string.find(tex, fragSmall) then return true end
        i = i + 1
    end
    return false
end

--- Cancel a buff by texture fragment match (same approach as LazyPig / PallyPowerTW).
local function PPB_CancelBuff(blessingID)
    local fragGreat = BlessingTextures[blessingID]
    local fragSmall = BlessingTexturesSmall[blessingID]
    local counter = 0
    while GetPlayerBuff(counter) >= 0 do
        local index, untilCancelled = GetPlayerBuff(counter)
        if untilCancelled ~= 1 then  -- skip permanent/until-cancelled buffs
            local tex = GetPlayerBuffTexture(index)
            if tex then
                if (fragGreat and string.find(tex, fragGreat)) or
                   (fragSmall and string.find(tex, fragSmall)) then
                    CancelPlayerBuff(index)
                    UIErrorsFrame:Clear()
                    UIErrorsFrame:AddMessage("PPBuddy: Removed " .. (BlessingNames[blessingID] or "?"))
                    return
                end
            end
        end
        counter = counter + 1
    end
end

--- Return list of {blessingID, pallyName} for all blessings assigned to my class.
-- PallyPower_Assignments is keyed [pallyName][classID (0-9)] = blessingID (0-5) or -1
-- In WoW 1.12 Lua 5.0, "for k,v in table" iterates via next() — works on mixed tables.
local function PPB_GetMyAssignments()
    local myClassID = PPB_GetMyClassID()
    if myClassID == nil then return {} end

    local results = {}
    if not PallyPower_Assignments then return results end

    -- seen[blessingID] = pallyName — one entry per unique blessing, first pally wins
    local seen = {}

    -- WoW 1.12 Lua 5.0: generic for with next() works on all table types
    for pallyName, assignments in next, PallyPower_Assignments do
        if type(assignments) == "table" then
            -- assignments is keyed 0-9 (numeric), iterate with next
            local bid = assignments[myClassID]
            -- bid is a number (0-5) when assigned, -1 or nil when unassigned
            if bid and type(bid) == "number" and bid >= 0 and bid <= 5 then
                if not seen[bid] then
                    seen[bid] = pallyName
                end
            end
        end
    end

    -- Build ordered result list (blessing IDs 0-5 in order)
    for bid = 0, 5 do
        if seen[bid] then
            table.insert(results, { blessingID = bid, pallyName = seen[bid] })
        end
    end
    return results
end

-- ============================================================
-- Frame construction
-- ============================================================
-- Layout: a single horizontal strip of square icon-buttons.
-- Each button is ICON_SIZE x ICON_SIZE with a coloured border.
-- A small ban-X overlay sits in the bottom-right corner.
-- All text lives in tooltips only.

local PPBFrame   -- main container
local PPBBtns = {}  -- array of icon buttons, one per blessing
local PPB_UpdateUI  -- forward declaration (defined below PPB_GetOrCreateBtn)

local ICON_SIZE  = 24   -- icon button size
local PAD        = 3    -- gap between icons
local BORDER     = 2    -- frame edge padding
local BAN_SIZE   = 10   -- ban-X overlay size

local function PPB_CreateFrame()
    PPBFrame = CreateFrame("Frame", "PPBuddyFrame", UIParent)
    PPBFrame:SetHeight(ICON_SIZE + BORDER * 2)
    PPBFrame:SetWidth(ICON_SIZE + BORDER * 2)  -- resized dynamically
    PPBFrame:SetFrameStrata("MEDIUM")
    PPBFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile     = true,
        tileSize = 8,
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    PPBFrame:SetBackdropColor(0, 0, 0, 0.6)
    PPBFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    PPBFrame:SetMovable(true)
    PPBFrame:EnableMouse(true)
    PPBFrame:RegisterForDrag("LeftButton")
    PPBFrame:SetScript("OnDragStart", function() this:StartMoving() end)
    PPBFrame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        PPBuddy_Config.posX = this:GetLeft()
        PPBuddy_Config.posY = this:GetTop()
    end)
    PPBFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
        PPBuddy_Config.posX or 20,
        PPBuddy_Config.posY or 400)
end

local function PPB_GetOrCreateBtn(i)
    if PPBBtns[i] then return PPBBtns[i] end

    local btn = CreateFrame("Button", "PPBuddyBtn" .. i, PPBFrame)
    btn:SetWidth(ICON_SIZE)
    btn:SetHeight(ICON_SIZE)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Coloured border texture (sits behind icon)
    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\WHITE8x8")
    border:SetVertexColor(0, 0, 0, 0)
    btn.border = border

    -- The blessing icon
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn.icon = icon

    -- Desaturation overlay for banned state (grey tint via vertex color)
    -- We'll just desaturate the icon texture directly

    -- Ban indicator: small red X in bottom-right corner
    local banMark = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    banMark:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    banMark:SetText("")
    btn.banMark = banMark

    -- Tooltip
    btn:SetScript("OnEnter", function()
        local b = this
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOMLEFT")
        local nameStr = BlessingNames[b.blessingID] or "?"
        local pallyStr = b.pallyName or "?"
        if b.banned then
            GameTooltip:SetText(nameStr, 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Banned — auto-removed", 1, 0.4, 0.4)
            GameTooltip:AddLine("Right-click to unban", 0.6, 0.6, 0.6)
        elseif b.hasIt then
            GameTooltip:SetText(nameStr, 0.4, 1, 0.4)
            GameTooltip:AddLine("Assigned: " .. pallyStr, 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Right-click to ban", 0.6, 0.6, 0.6)
        else
            GameTooltip:SetText(nameStr, 1, 0.4, 0.4)
            GameTooltip:AddLine("Missing!", 1, 0.5, 0.5)
            GameTooltip:AddLine("Assigned: " .. pallyStr, 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Left-click to whisper " .. pallyStr, 1, 1, 0)
            GameTooltip:AddLine("Right-click to ban", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function()
        local b = this
        if arg1 == "RightButton" then
            -- Toggle ban
            local capturedBid = b.blessingID
            if PPBuddy_Config.banned[capturedBid] then
                PPBuddy_Config.banned[capturedBid] = nil
                PPB_Print(BlessingNames[capturedBid] .. " ban removed.")
            else
                PPBuddy_Config.banned[capturedBid] = true
                PPB_Print(BlessingNames[capturedBid] .. " banned — will auto-remove.")
                PPB_CancelBuff(capturedBid)
            end
            PPB_UpdateUI()
        elseif arg1 == "LeftButton" then
            -- Whisper paladin if missing
            if not b.hasIt and not b.banned and b.pallyName then
                local whisper = "Hey " .. b.pallyName .. ", could I please get "
                    .. (BlessingNames[b.blessingID] or "a blessing") .. "? Thank you! :)"
                SendChatMessage(whisper, "WHISPER", nil, b.pallyName)
                PPB_Print("Whispered " .. b.pallyName .. " for " .. (BlessingNames[b.blessingID] or "?"))
            end
        end
    end)

    PPBBtns[i] = btn
    return btn
end

-- ============================================================
-- UI update
-- ============================================================

PPB_UpdateUI = function()
    if not PPBFrame then return end

    local myClassID = PPB_GetMyClassID()
    if myClassID == nil then
        PPBFrame:Hide()
        return
    end

    local assignments = PPB_GetMyAssignments()
    local count = table.getn(assignments)

    if count == 0 then
        PPBFrame:Hide()
        return
    end

    -- Resize frame to fit icons horizontally
    local totalW = BORDER * 2 + count * ICON_SIZE + (count - 1) * PAD
    PPBFrame:SetWidth(totalW)
    PPBFrame:SetHeight(ICON_SIZE + BORDER * 2)

    for i, info in ipairs(assignments) do
        local btn = PPB_GetOrCreateBtn(i)
        local bid = info.blessingID
        local hasIt = PPB_HasBuff(bid)
        local banned = PPBuddy_Config.banned[bid]

        btn.blessingID = bid
        btn.pallyName  = info.pallyName
        btn.hasIt      = hasIt
        btn.banned     = banned

        -- Position
        btn:SetPoint("TOPLEFT", PPBFrame, "TOPLEFT",
            BORDER + (i - 1) * (ICON_SIZE + PAD),
            -BORDER)

        -- Icon texture
        btn.icon:SetTexture(BlessingIcons[bid])

        -- Colour the border/background to show state
        if banned then
            btn.border:SetVertexColor(0.25, 0.25, 0.25, 0.9)
            btn.icon:SetVertexColor(0.4, 0.4, 0.4)   -- desaturate
            btn.banMark:SetText("|cffff3333x|r")
        elseif hasIt then
            btn.border:SetVertexColor(0, 0.7, 0, 0.8)
            btn.icon:SetVertexColor(1, 1, 1)
            btn.banMark:SetText("")
        else
            btn.border:SetVertexColor(0.8, 0, 0, 0.8)
            btn.icon:SetVertexColor(1, 1, 1)
            btn.banMark:SetText("")
        end

        btn:Show()
    end

    -- Hide any leftover buttons from a previous larger assignment set
    for i = count + 1, table.getn(PPBBtns) do
        PPBBtns[i]:Hide()
    end

    PPBFrame:Show()
end

-- ============================================================
-- Auto-remove banned buffs on PLAYER_AURAS_CHANGED
-- ============================================================

local function PPB_EnforceBans()
    for bid, _ in next, PPBuddy_Config.banned do
        if PPB_HasBuff(bid) then
            PPB_CancelBuff(bid)
        end
    end
end

-- ============================================================
-- Main event frame
-- ============================================================

local PPBEventFrame = CreateFrame("Frame", "PPBuddyEventFrame", UIParent)

PPBEventFrame:RegisterEvent("PLAYER_LOGIN")
PPBEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
PPBEventFrame:RegisterEvent("PLAYER_AURAS_CHANGED")
PPBEventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
PPBEventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
PPBEventFrame:RegisterEvent("ADDON_LOADED")

PPBEventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 ~= ADDON_NAME then return end

    if event == "PLAYER_AURAS_CHANGED" then
        PPB_EnforceBans()
        timeSince = UPDATE_FREQ  -- force immediate UI refresh on next OnUpdate
        return
    end

    -- For all other events: rebuild UI after a short delay
    timeSince = UPDATE_FREQ
end)

PPBEventFrame:SetScript("OnUpdate", function()
    timeSince = (timeSince or 0) + arg1
    if timeSince >= UPDATE_FREQ then
        timeSince = 0
        if PPBFrame then
            PPB_UpdateUI()
        end
    end
end)

-- ============================================================
-- Slash commands
-- ============================================================

SlashCmdList["PPBUDDY"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "show" then
        if not PPBFrame then PPB_Init() end
        PPBFrame:Show()
        PPB_UpdateUI()
    elseif msg == "hide" then
        if PPBFrame then PPBFrame:Hide() end
    elseif msg == "reset" then
        if PPBFrame then
            PPBFrame:ClearAllPoints()
            PPBFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 20, 400)
            PPBuddy_Config.posX = 20
            PPBuddy_Config.posY = 400
        end
    elseif msg == "bans" then
        PPB_Print("Banned blessings:")
        local any = false
        for bid, _ in next, PPBuddy_Config.banned do
            PPB_Print("  - " .. (BlessingNames[bid] or tostring(bid)))
            any = true
        end
        if not any then PPB_Print("  (none)") end
    elseif msg == "clearbans" then
        PPBuddy_Config.banned = {}
        PPB_Print("All bans cleared.")
        PPB_UpdateUI()
    elseif msg == "debug" then
        -- Dump raw PallyPower data to chat so you can verify what PP sees
        local _, token = UnitClass("player")
        local myID = ClassTokenToID[token]
        PPB_Print("=== PPBuddy Debug ===")
        PPB_Print("Class token: " .. tostring(token) .. "  -> PP classID: " .. tostring(myID))
        if not PallyPower_Assignments then
            PPB_Print("PallyPower_Assignments is NIL (PallyPowerTW not loaded yet?)")
            return
        end
        local count = 0
        for pallyName, assignments in next, PallyPower_Assignments do
            count = count + 1
            local line = "  Pally: " .. tostring(pallyName) .. " -> "
            if type(assignments) == "table" then
                for classID = 0, 9 do
                    local bid = assignments[classID]
                    if bid and bid ~= -1 then
                        line = line .. "[class" .. classID .. "=" .. tostring(bid) .. " (" .. (BlessingNames[bid] or "?") .. ")] "
                    end
                end
            else
                line = line .. tostring(assignments)
            end
            PPB_Print(line)
        end
        if count == 0 then
            PPB_Print("  PallyPower_Assignments is EMPTY (no pallies seen yet?)")
        end
        PPB_Print("My assignments found:")
        local found = PPB_GetMyAssignments()
        if table.getn(found) == 0 then
            PPB_Print("  (none for classID " .. tostring(myID) .. ")")
        else
            for i, info in ipairs(found) do
                PPB_Print("  " .. BlessingNames[info.blessingID] .. " from " .. info.pallyName)
            end
        end
    else
        PPB_Print("Commands: /ppb show | hide | reset | bans | clearbans | debug")
    end
end
SLASH_PPBUDDY1 = "/ppb"
SLASH_PPBUDDY2 = "/ppbuddy"

-- ============================================================
-- Init (called on PLAYER_LOGIN after PallyPowerTW has loaded)
-- ============================================================

local initDone = false
local function PPB_Init()
    if initDone then return end
    initDone = true

    -- Ensure saved var table has all keys
    if not PPBuddy_Config then PPBuddy_Config = {} end
    if not PPBuddy_Config.banned then PPBuddy_Config.banned = {} end

    PPB_CreateFrame()
    PPB_UpdateUI()
end

-- Hook into PLAYER_LOGIN (guaranteed after all ADDON_LOADED events)
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    PPB_Init()
end)