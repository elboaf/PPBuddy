-- PPBuddy.lua
-- Compact blessing status bar for any class.
-- Works standalone: listens to PallyPower's PLPWR addon messages directly.
-- Also reads PallyPowerTW globals if PP is installed locally (no conflict).
-- No dependency on PallyPowerTW.

-- ============================================================
-- Saved variables (populated by WoW from disk before PLAYER_LOGIN)
-- ============================================================
-- PPBuddy_Config is declared in the TOC as SavedVariables.
-- Do NOT initialise it here — that would overwrite the loaded data.
-- Defaults are applied in PPB_Init() after the saved data is available.

-- ============================================================
-- Constants
-- ============================================================
local PP_PREFIX   = "PLPWR"
local UPDATE_FREQ = 2

-- PallyPower class IDs — mirrors PallyPower_ClassID in PP localization.
-- Key: UnitClass() token (always English uppercase in 1.12).
local ClassTokenToID = {
    WARRIOR = 0,
    ROGUE   = 1,
    PRIEST  = 2,
    DRUID   = 3,
    PALADIN = 4,
    HUNTER  = 5,
    MAGE    = 6,
    WARLOCK = 7,
    SHAMAN  = 8,
    -- 9 = hunter pets, shares Warriors slot in PP
}

local BlessingNames = {
    [0] = "Wisdom",
    [1] = "Might",
    [2] = "Salvation",
    [3] = "Light",
    [4] = "Kings",
    [5] = "Sanctuary",
}

-- Texture fragments for buff detection (Greater Blessing variants)
local BlessingTextures = {
    [0] = "Spell_Holy_GreaterBlessingofWisdom",
    [1] = "Spell_Holy_GreaterBlessingofKings",
    [2] = "Spell_Holy_GreaterBlessingofSalvation",
    [3] = "Spell_Holy_GreaterBlessingofLight",
    [4] = "Spell_Magic_GreaterBlessingofKings",
    [5] = "Spell_Holy_GreaterBlessingofSanctuary",
}

-- Texture fragments for regular (10-min) blessing variants
local BlessingTexturesSmall = {
    [0] = "Spell_Holy_SealOfWisdom",
    [1] = "Spell_Holy_FistOfJustice",
    [2] = "Spell_Holy_SealOfSalvation",
    [3] = "Spell_Holy_PrayerOfHealing02",
    [4] = "Spell_Magic_MageArmor",
    [5] = "Spell_Nature_LightningShield",
}

local ICON_PREFIX = "Interface\\Icons\\"

local BlessingIcons = {
    [0] = ICON_PREFIX .. "Spell_Holy_GreaterBlessingofWisdom",
    [1] = ICON_PREFIX .. "Spell_Holy_GreaterBlessingofKings",
    [2] = ICON_PREFIX .. "Spell_Holy_GreaterBlessingofSalvation",
    [3] = ICON_PREFIX .. "Spell_Holy_GreaterBlessingofLight",
    [4] = ICON_PREFIX .. "Spell_Magic_GreaterBlessingofKings",
    [5] = ICON_PREFIX .. "Spell_Holy_GreaterBlessingofSanctuary",
}

-- ============================================================
-- Own assignment table
-- PPB_Assignments[pallyName][classID (0-9)] = blessingID (0-5) or -1
-- Built from PLPWR messages and/or PP globals.
-- ============================================================
local PPB_Assignments = {}

-- ============================================================
-- Helpers
-- ============================================================

local function PPB_Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00PPBuddy:|r " .. tostring(msg))
end

local function PPB_GetMyClassID()
    local _, token = UnitClass("player")
    if not token then return nil end
    return ClassTokenToID[token]
end

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

local function PPB_CancelBuff(blessingID)
    local fragGreat = BlessingTextures[blessingID]
    local fragSmall = BlessingTexturesSmall[blessingID]
    local counter = 0
    while GetPlayerBuff(counter) >= 0 do
        local index, untilCancelled = GetPlayerBuff(counter)
        if untilCancelled ~= 1 then
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

-- If PallyPowerTW is installed locally, sync its globals into our own table.
-- Called on login and periodically so local PP data is always reflected.
local function PPB_SyncFromPP()
    if not PallyPower_Assignments then return end
    for pallyName, assignments in next, PallyPower_Assignments do
        if type(assignments) == "table" then
            if not PPB_Assignments[pallyName] then
                PPB_Assignments[pallyName] = {}
            end
            for classID = 0, 9 do
                local bid = assignments[classID]
                if bid and type(bid) == "number" then
                    PPB_Assignments[pallyName][classID] = bid
                end
            end
        end
    end
end

-- Parse a SELF message: "SELF <12-char ranks>@<10-char assignments>"
-- assign = 10 chars: 1 char per class slot (blessingID digit or "n")
local function PPB_ParseSelf(sender, msg)
    local _, _, numbers, assign = string.find(msg, "SELF ([0-9n]*)@?([0-9n]*)")
    if not numbers then return end
    if not PPB_Assignments[sender] then
        PPB_Assignments[sender] = {}
    end
    if assign and assign ~= "" then
        for classID = 0, 9 do
            local ch = string.sub(assign, classID + 1, classID + 1)
            if ch == "n" or ch == "" then
                PPB_Assignments[sender][classID] = -1
            else
                PPB_Assignments[sender][classID] = tonumber(ch) or -1
            end
        end
    end
end

-- Parse "ASSIGN <pallyName> <classID> <blessingID>"
local function PPB_ParseAssign(msg)
    local _, _, name, classID, bid = string.find(msg, "ASSIGN (.*) (.*) (.*)")
    if not name then return end
    classID = tonumber(classID)
    bid     = tonumber(bid)
    if not classID or not bid then return end
    if not PPB_Assignments[name] then PPB_Assignments[name] = {} end
    PPB_Assignments[name][classID] = bid
end

-- Parse "MASSIGN <pallyName> <blessingID>"  (same blessing for all classes)
local function PPB_ParseMassign(msg)
    local _, _, name, bid = string.find(msg, "MASSIGN (.*) (.*)")
    if not name then return end
    bid = tonumber(bid)
    if not bid then return end
    if not PPB_Assignments[name] then PPB_Assignments[name] = {} end
    for classID = 0, 9 do
        PPB_Assignments[name][classID] = bid
    end
end

-- Wipe a sender's assignments on CLEAR
local function PPB_ParseClear(sender)
    PPB_Assignments[sender] = nil
end

-- Drop assignments for paladins no longer in the group
local function PPB_PruneAssignments()
    local present = {}
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name = GetRaidRosterInfo(i)
            if name then present[name] = true end
        end
    else
        present[UnitName("player")] = true
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party" .. i)
            if name then present[name] = true end
        end
    end
    for name in next, PPB_Assignments do
        if not present[name] then
            PPB_Assignments[name] = nil
        end
    end
end

-- Return list of {blessingID, pallyName} for blessings assigned to my class.
local function PPB_GetMyAssignments()
    local myClassID = PPB_GetMyClassID()
    if myClassID == nil then return {} end

    local seen = {}
    for pallyName, assignments in next, PPB_Assignments do
        if type(assignments) == "table" then
            local bid = assignments[myClassID]
            if bid and type(bid) == "number" and bid >= 0 and bid <= 5 then
                if not seen[bid] then
                    seen[bid] = pallyName
                end
            end
        end
    end

    local results = {}
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

local PPBFrame = nil
local PPBBtns  = {}
local PPB_UpdateUI  -- forward declaration

local ICON_SIZE = 24
local PAD       = 3
local BORDER    = 2

local function PPB_CreateFrame()
    PPBFrame = CreateFrame("Frame", "PPBuddyFrame", UIParent)
    PPBFrame:SetHeight(ICON_SIZE + BORDER * 2)
    PPBFrame:SetWidth(ICON_SIZE + BORDER * 2)
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
        -- Store as TOPLEFT-relative coords so SetPoint can restore exactly
        PPBuddy_Config.posX = this:GetLeft()
        PPBuddy_Config.posY = this:GetTop() - UIParent:GetHeight()
    end)
    -- Restore saved position. GetLeft()/GetTop() are TOPLEFT screen coords,
    -- so we anchor to TOPLEFT of UIParent and use them directly.
    local x = PPBuddy_Config.posX or 20
    local y = PPBuddy_Config.posY or -200   -- sensible default near top of screen
    PPBFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
end

local function PPB_GetOrCreateBtn(i)
    if PPBBtns[i] then return PPBBtns[i] end

    local btn = CreateFrame("Button", "PPBuddyBtn" .. i, PPBFrame)
    btn:SetWidth(ICON_SIZE)
    btn:SetHeight(ICON_SIZE)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\WHITE8x8")
    border:SetVertexColor(0, 0, 0, 0)
    btn.border = border

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT",     btn, "TOPLEFT",     1, -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn.icon = icon

    local banMark = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    banMark:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    banMark:SetText("")
    btn.banMark = banMark

    btn:SetScript("OnEnter", function()
        local b = this
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOMLEFT")
        local nameStr  = BlessingNames[b.blessingID] or "?"
        local pallyStr = b.pallyName or "?"
        if b.banned then
            GameTooltip:SetText(nameStr, 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Banned - auto-removed", 1, 0.4, 0.4)
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
            local capturedBid = b.blessingID
            if PPBuddy_Config.banned[capturedBid] then
                PPBuddy_Config.banned[capturedBid] = nil
                PPB_Print(BlessingNames[capturedBid] .. " ban removed.")
            else
                PPBuddy_Config.banned[capturedBid] = true
                PPB_Print(BlessingNames[capturedBid] .. " banned - will auto-remove.")
                PPB_CancelBuff(capturedBid)
            end
            PPB_UpdateUI()
        elseif arg1 == "LeftButton" then
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

    local assignments = PPB_GetMyAssignments()
    local count = table.getn(assignments)

    if count == 0 then
        PPBFrame:Hide()
        return
    end

    local totalW = BORDER * 2 + count * ICON_SIZE + (count - 1) * PAD
    PPBFrame:SetWidth(totalW)
    PPBFrame:SetHeight(ICON_SIZE + BORDER * 2)

    for i, info in ipairs(assignments) do
        local btn    = PPB_GetOrCreateBtn(i)
        local bid    = info.blessingID
        local hasIt  = PPB_HasBuff(bid)
        local banned = PPBuddy_Config.banned[bid]

        btn.blessingID = bid
        btn.pallyName  = info.pallyName
        btn.hasIt      = hasIt
        btn.banned     = banned

        btn:SetPoint("TOPLEFT", PPBFrame, "TOPLEFT",
            BORDER + (i - 1) * (ICON_SIZE + PAD), -BORDER)

        btn.icon:SetTexture(BlessingIcons[bid])

        if banned then
            btn.border:SetVertexColor(0.25, 0.25, 0.25, 0.9)
            btn.icon:SetVertexColor(0.4, 0.4, 0.4)
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

    for i = count + 1, table.getn(PPBBtns) do
        PPBBtns[i]:Hide()
    end

    PPBFrame:Show()
end

-- ============================================================
-- Auto-remove banned buffs
-- ============================================================

local function PPB_EnforceBans()
    for bid, _ in next, PPBuddy_Config.banned do
        if PPB_HasBuff(bid) then
            PPB_CancelBuff(bid)
        end
    end
end

-- ============================================================
-- Event handler
-- ============================================================

local timeSince = 0
local uiDirty   = false

local PPBEventFrame = CreateFrame("Frame", "PPBuddyEventFrame", UIParent)
PPBEventFrame:RegisterEvent("PLAYER_LOGIN")
PPBEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
PPBEventFrame:RegisterEvent("PLAYER_AURAS_CHANGED")
PPBEventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
PPBEventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
PPBEventFrame:RegisterEvent("CHAT_MSG_ADDON")

PPBEventFrame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" and arg1 == PP_PREFIX then
        local msg    = arg2
        local sender = arg4

        if string.find(msg, "^SELF") then
            PPB_ParseSelf(sender, msg)
            uiDirty = true

        elseif string.find(msg, "^MASSIGN") then
            PPB_ParseMassign(msg)
            uiDirty = true

        elseif string.find(msg, "^ASSIGN") then
            -- catches ASSIGN but not MASSIGN/AASSIGN/SASSIGN
            if not string.find(msg, "^[AMS]ASSIGN") then
                PPB_ParseAssign(msg)
                uiDirty = true
            end

        elseif string.find(msg, "^CLEAR") then
            PPB_ParseClear(sender)
            uiDirty = true
        end
        return
    end

    if event == "PLAYER_AURAS_CHANGED" then
        PPB_EnforceBans()
        uiDirty = true
        return
    end

    if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        PPB_PruneAssignments()
        PPB_SyncFromPP()
        uiDirty = true
        return
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" then
        PPB_SyncFromPP()
        uiDirty = true
        return
    end
end)

PPBEventFrame:SetScript("OnUpdate", function()
    timeSince = (timeSince or 0) + arg1
    if timeSince >= UPDATE_FREQ then
        timeSince = 0
        PPB_SyncFromPP()
        if uiDirty and PPBFrame then
            uiDirty = false
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
        PPB_SyncFromPP()
        PPB_UpdateUI()
        if PPBFrame then PPBFrame:Show() end
    elseif msg == "hide" then
        if PPBFrame then PPBFrame:Hide() end
    elseif msg == "reset" then
        if PPBFrame then
            PPBFrame:ClearAllPoints()
            PPBFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -200)
            PPBuddy_Config.posX = 20
            PPBuddy_Config.posY = -200
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
        local _, token = UnitClass("player")
        local myID = ClassTokenToID[token]
        PPB_Print("=== PPBuddy Debug ===")
        PPB_Print("Class: " .. tostring(token) .. " -> PP classID: " .. tostring(myID))
        PPB_Print("PP globals present: " .. (PallyPower_Assignments and "YES" or "NO"))
        local count = 0
        for pallyName, assignments in next, PPB_Assignments do
            count = count + 1
            local line = "  " .. tostring(pallyName) .. ": "
            if type(assignments) == "table" then
                for classID = 0, 9 do
                    local bid = assignments[classID]
                    if bid and bid ~= -1 then
                        line = line .. "[c" .. classID .. "=" .. (BlessingNames[bid] or tostring(bid)) .. "] "
                    end
                end
            end
            PPB_Print(line)
        end
        if count == 0 then PPB_Print("  No assignments known yet.") end
        local found = PPB_GetMyAssignments()
        PPB_Print("My buffs (" .. table.getn(found) .. "):")
        for _, info in ipairs(found) do
            PPB_Print("  " .. BlessingNames[info.blessingID] .. " from " .. info.pallyName)
        end
    else
        PPB_Print("Commands: /ppb show | hide | reset | bans | clearbans | debug")
    end
end
SLASH_PPBUDDY1 = "/ppb"
SLASH_PPBUDDY2 = "/ppbuddy"

-- ============================================================
-- Init
-- ============================================================

local initDone = false
function PPB_Init()
    if initDone then return end
    initDone = true

    -- Apply defaults only for keys not already restored from disk
    if not PPBuddy_Config        then PPBuddy_Config         = {} end
    if not PPBuddy_Config.banned then PPBuddy_Config.banned  = {} end
    -- posX/posY intentionally left nil if not saved — CreateFrame uses fallback

    PPB_CreateFrame()
    PPB_SyncFromPP()
    PPB_UpdateUI()
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function() PPB_Init() end)
