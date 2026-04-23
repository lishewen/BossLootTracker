-- BossLootTracker - Main Logic and Event Handlers
-- WoW for version 12.0.5 (Midnight)
-- Author: lishewen
-- License: MIT
-- https://github.com/lishewen/BossLootTracker

-- Addon namespace
local AddonName, BLT = ...
BLT.DB = BLT or {}

-- Version info
local Version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(AddonName, "Version") or "1.0.0"

-- Class colors for text display
local ClassColors = {
    DEATHKNIGHT = "|cffC41F3B",
    DEMONHUNTER = "|cffA330C9",
    DRUID = "|cffFF7D0A",
    EVOKER = "|cff33937F",
    HUNTER = "|cffABD473",
    MAGE = "|cff69CCF0",
    MONK = "|cff00FF96",
    PALADIN = "|cffF58CBA",
    PRIEST = "|cffFFFFFF",
    ROGUE = "|cffFFF569",
    SHAMAN = "|cff0070DE",
    WARLOCK = "|cff9482C9",
    WARRIOR = "|cffC79C6E"
}

-- Distribution method enum
local DistributionMethods = {
    NEED = "需求",
    GREED = "贪婪",
    TRANSMOG = "幻化",
    PERSONAL = "个人拾取",
    BOSS_DROP = "Boss掉落",
    UNKNOWN = "未知"
}

-- Current encounter tracking
local CurrentEncounter = nil

-- Track pending loot items (ENCOUNTER_LOOT_RECEIVED fires multiple times per boss)
local PendingLootItems = {}
local PendingLootEncounterID = nil

-- Double-click detection for edit mode
local LastClickTime = 0
local LastClickRecord = nil

-- Raid loot tracking (Master Looter / Party Loot mode)
local IsRaidLootOpen = false  -- 标记当前是否在团本拾取状态

-- Debug mode flag
local BLT_DebugMode = false

-- Initialize database
local function InitializeDB()
    if not BossLootTrackerDB then
        BossLootTrackerDB = {
            version = Version,
            lootRecords = {},
            settings = {
                minimap = {
                    shown = true,
                    position = 45
                }
            }
        }
    end

    -- Initialize records table if it doesn't exist
    if not BossLootTrackerDB.lootRecords then
        BossLootTrackerDB.lootRecords = {}
    end

    -- Initialize settings if they don't exist
    if not BossLootTrackerDB.settings then
        BossLootTrackerDB.settings = {
            minimap = {
                shown = true,
                position = 45
            }
        }
    end

    BLT.DB = BossLootTrackerDB
end

-- Get formatted class name with color
function BLT.GetClassColor(classFileName)
    return ClassColors[classFileName] or "|cffFFFFFF"
end

-- Format timestamp to readable date/time
function BLT.FormatTimestamp(timestamp)
    if not timestamp then return "Unknown" end
    local dateStr = date("%Y-%m-%d %H:%M:%S", timestamp)
    return dateStr
end

-- Get raid instance info
local function GetRaidInstanceInfo()
    local info = {GetInstanceInfo()}
    if info then
        return info[1], info[3]  -- name, difficultyName
    end
    return nil, nil
end

-- Track encounter phase - set on ENCOUNTER_START, clear after all loot is distributed
-- This ensures CurrentEncounter is available for CHAT_MSG_LOOT/SYSTEM processing
local EncounterTimeout = nil
local ENCOUNTER_TRACK_DURATION = 600 -- 10 minutes after boss kill to keep tracking loot (Roll can be slow)

-- Handle encounter end - don't clear immediately, loot happens after
local function OnEncounterEnd(event, encounterID, encounterName, difficultyID, groupSize)
    if BLT_DebugMode then
        print("|cffFFD700[BLT Debug]|r ENCOUNTER_END: " .. tostring(encounterID) .. " " .. tostring(encounterName))
    end
    -- Don't clear CurrentEncounter - loot distribution happens after boss death
    -- It will be overwritten when ENCOUNTER_START fires for the next boss
end

-- Handle boss kill event
local function OnBossKill(event, encounterID, encounterName)
    local raidName, difficulty = GetRaidInstanceInfo()

    CurrentEncounter = {
        id = encounterID,
        name = encounterName,
        raidName = raidName,
        difficulty = difficulty,
        timestamp = time()
    }

    -- Reset pending loot tracking for new encounter
    PendingLootItems = {}
    PendingLootEncounterID = encounterID

    -- Set timeout to clear encounter tracking after loot is done
    if EncounterTimeout then
        EncounterTimeout:Cancel()
    end
    EncounterTimeout = C_Timer.NewTimer(ENCOUNTER_TRACK_DURATION, function()
        if BLT_DebugMode then
            print("|cffFFD700[BLT Debug]|r Encounter tracking timed out for: " .. tostring(encounterName))
        end
        PendingLootItems = {}
        -- Don't clear CurrentEncounter if a new one was set
    end)
end

-- Handle ENCOUNTER_START to track encounter name even before kill
local function OnEncounterStart(event, encounterID, encounterName, difficultyID, groupSize)
    local raidName, difficulty = GetRaidInstanceInfo()

    if not CurrentEncounter or CurrentEncounter.id ~= encounterID then
        CurrentEncounter = {
            id = encounterID,
            name = encounterName,
            raidName = raidName,
            difficulty = difficulty,
            timestamp = time()
        }
        PendingLootItems = {}
        PendingLootEncounterID = encounterID

        if BLT_DebugMode then
            print("|cffFFD700[BLT Debug]|r ENCOUNTER_START: " .. tostring(encounterID) .. " " .. tostring(encounterName))
        end
    end
end

-- Extract item quality from itemLink's |cnIQx: prefix (works even when GetItemInfo is not cached)
-- Returns: quality number (0-7), or nil if not parseable
-- NOTE: 必须在使用此函数的所有调用者之前定义（Lua 5.1 的 local function 不会被前向声明）
local function GetQualityFromItemLink(itemLink)
    if not itemLink or type(itemLink) ~= "string" then return nil end
    local qualityStr = itemLink:match("|cnIQ(%d+):")
    if qualityStr then return tonumber(qualityStr) end
    return nil
end

-- v2.1.0: Safe wrapper for GetItemInfo to handle 12.0.5 potential secret value returns
-- Returns the same values as GetItemInfo, but protects against type errors
local function SafeGetItemInfo(itemID)
    if not itemID or type(itemID) ~= "number" then return nil end
    local ok, result = pcall(GetItemInfo, itemID)
    if not ok then return nil end
    return result
end

-- Handle encounter loot received event
-- NOTE: ENCOUNTER_LOOT_RECEIVED fires ONCE per item drop
-- Event params: encounterID, itemID, itemLink, quantity, playerName, classFileName
-- NO encounterName or lootMethod in this event!
-- v2.1.0: Added pcall wrap for 12.0.5 secret value protection
local function OnEncounterLootReceived(event, encounterID, itemID, itemLink, quantity, playerName, classFileName)
    -- v2.1.0: Validate param types — 12.0.5 may inject secret values that aren't expected types
    if type(encounterID) ~= "number" or type(itemID) ~= "number" then
        if BLT_DebugMode then
            print("|cffFFD700[BLT Debug]|r ENCOUNTER_LOOT_RECEIVED: invalid param types, enc=" .. type(encounterID) .. " item=" .. type(itemID))
        end
        return
    end
    -- v2.1.0: Protect against secret value strings in playerName/classFileName
    if playerName ~= nil and type(playerName) ~= "string" then
        playerName = tostring(playerName)
    end
    if classFileName ~= nil and type(classFileName) ~= "string" then
        classFileName = "UNKNOWN"
    end
    if itemLink ~= nil and type(itemLink) ~= "string" then
        itemLink = nil  -- Will be reconstructed from itemID
    end
    -- Debug logging
    if BLT_DebugMode then
        print("|cffFFD700[BLT Debug]|r ENCOUNTER_LOOT_RECEIVED: enc=" .. tostring(encounterID) .. " item=" .. tostring(itemID) .. " player=" .. tostring(playerName))
    end

    -- Validate required fields
    if not encounterID or not itemID then
        return
    end

    -- Filter out non-boss loot:
    -- encounterID == 0 means the loot came from mining, rare elites, or other non-boss sources
    -- Only record loot from actual boss encounters (encounterID > 0)
    if encounterID == 0 then
        return
    end

    -- Filter by item quality - only record Rare (blue) and above
    -- This skips gray (trash), white (common materials), green (crafting materials like 锐锋犬齿/白银叶/充裕钢筋)
    -- Boss装备至少蓝色品质，绿色品质全是材料/杂物
    -- v2.0.7 修复：物品未缓存时宁可放行也不漏记，用 qualityUnconfirmed 标记
    local _, _, itemRarity, _, _, _, _, _, itemEquipLoc, _, _, itemClassID, itemSubClassID = SafeGetItemInfo(itemID)
    local qualityUnconfirmed = false
    if itemRarity then
        if itemRarity < 3 then  -- 0=Poor(gray), 1=Common(white), 2=Uncommon(green materials) → skip
            if BLT_DebugMode then
                print("|cffFFD700[BLT Debug]|r Filtered quality=" .. itemRarity .. " item=" .. tostring(itemID))
            end
            return
        end
    else
        -- GetItemInfo not cached yet — fallback to itemLink quality code
        if itemLink then
            local linkQuality = GetQualityFromItemLink(itemLink)
            if linkQuality and linkQuality < 3 then
                if BLT_DebugMode then
                    print("|cffFFD700[BLT Debug]|r Filtered (link) quality=" .. linkQuality .. " item=" .. tostring(itemID))
                end
                return
            end
        end
        -- v2.0.7 修复：物品未缓存且无法确定品质时，放行处理，标记 qualityUnconfirmed
        -- 宁可多记一个可疑物品，也不能漏掉真正的新 Boss 装备掉落
        qualityUnconfirmed = true
        if BLT_DebugMode then
            print("|cffFFD700[BLT Debug]|r Item quality unconfirmed, allowing through: itemID=" .. tostring(itemID))
        end
    end
    -- Also filter by item class - only keep Weapons(2) and Armor(4)
    -- Bug 2 修复：只记录武器和护甲，排除通货/材料/图纸等非装备掉落
    -- itemClassID 定义：0=消耗品, 1=容器, 2=武器, 3=宝石, 4=护甲, 5=试剂,
    --                  6=投射物, 7=交易品, 8=任务物品, 9=杂项, ...
    -- v2.0.7 修复：itemClassID 为 nil（未缓存）时不过滤，放行处理
    if itemClassID then
        if itemClassID ~= 2 and itemClassID ~= 4 then
            if BLT_DebugMode then
                print("|cffFFD700[BLT Debug]|r Filtered non-equip itemClassID=" .. itemClassID .. " item=" .. tostring(itemID))
            end
            return
        end
    else
        -- itemClassID 为 nil 说明物品未缓存，放行处理
        qualityUnconfirmed = true
    end

    -- Validate playerName - must have a valid receiver
    -- Bug 3 额外保护：过滤掉 "你"（系统消息自称，不是真实玩家名）
    if not playerName or playerName == "" or playerName == "你" then
        return
    end
    local shortPlayerName = playerName:match("^(.-)%-") or playerName
    if shortPlayerName == "你" then
        return
    end

    -- Get boss name from BOSS_KILL tracking or EJ_GetEncounterInfo
    local bossName = "Unknown"
    if CurrentEncounter and CurrentEncounter.id == encounterID then
        bossName = CurrentEncounter.name or "Unknown"
    else
        local name = EJ_GetEncounterInfo(encounterID)
        if name then
            bossName = name
        end
    end

    -- Get raid instance info
    local raidName, difficulty
    if CurrentEncounter then
        raidName = CurrentEncounter.raidName
        difficulty = CurrentEncounter.difficulty
    end
    if not raidName then
        raidName, difficulty = GetRaidInstanceInfo()
    end

    local classFile = classFileName
    if not classFile or classFile == "" then
        classFile = "UNKNOWN"
    end

    local cleanItemLink = itemLink
    if not itemLink then
        cleanItemLink = "item:" .. tostring(itemID)
    else
        -- 清洗 itemLink 末尾可能附带的标点符号（中文句号、英文句号、逗号等）
        -- 这些标点来自聊天消息解析时误带的消息结尾字符
        cleanItemLink = itemLink:gsub("[。.,，]+$", "")
    end

    local qty = quantity or 1
    if type(qty) ~= "number" or qty < 1 then
        qty = 1
    end

    -- Boss 战利品（encounterID > 0）直接标记为 Boss掉落
    -- GetLootMethod() 在 ENCOUNTER_LOOT_RECEIVED 触发时不可靠，
    -- 因为事件时机是 Boss 死后自动分配，此时 API 返回值可能为 nil 或不准确
    local distributionMethod = DistributionMethods.BOSS_DROP

    -- Dedup: mark this item as recorded
    -- 去掉playerName的服务器后缀，确保与CHAT_MSG_LOOT的去重key一致
    local dedupKey = tostring(encounterID) .. "_" .. tostring(itemID) .. "_" .. shortPlayerName

    -- Bug 1 修复：二次去重——检查 lootRecords 中是否已有相同记录
    -- WoW 的 ENCOUNTER_LOOT_RECEIVED 对同一物品可能触发两次（掉落时+拾取时）
    local now = time()
    for i = #BLT.DB.lootRecords, 1, -1 do
        local r = BLT.DB.lootRecords[i]
        if r.encounterID == encounterID and r.itemID == itemID then
            local rShortName = r.playerName:match("^(.-)%-") or r.playerName
            if rShortName == shortPlayerName and math.abs(r.timestamp - now) < 5 then
                if BLT_DebugMode then
                    print("|cffFFD700[BLT Debug]|r Dedup: skipped duplicate lootRecords entry for " .. shortPlayerName)
                end
                return
            end
        end
    end

    PendingLootItems[dedupKey] = true

    local record = {
        id = #BLT.DB.lootRecords + 1,
        timestamp = time(),
        encounterID = encounterID,
        bossName = bossName,
        raidName = raidName or "Unknown",
        difficulty = difficulty or "Unknown",
        itemID = itemID,
        itemLink = cleanItemLink,
        quantity = qty,
        playerName = playerName,
        classFileName = classFile,
        distributionMethod = distributionMethod
    }
    if qualityUnconfirmed then
        record.qualityUnconfirmed = true
    end

    table.insert(BLT.DB.lootRecords, record)
    print("|cff00FF00[BossLootTracker]|r 记录：" .. playerName .. " 获得了 " .. (cleanItemLink or "item:"..tostring(itemID)))
end

--------------------------------------------------------------------------------
-- Shared helpers for CHAT_MSG_LOOT / CHAT_MSG_SYSTEM parsing
--------------------------------------------------------------------------------

-- Extract item info from new-format loot bracket like [256-锁甲手:无拘狂暴者的护手]
-- Returns: itemID (number or nil), itemLink (string or nil)
local function ParseLootBracket(text)
    local bracketContent = text:match("%[(.+)%]") or text
    -- Extract itemID from the beginning of bracket (before the first dash)
    local bracketItemID = tonumber(bracketContent:match("^(%d+)%-"))
    -- Item name is after the last colon inside brackets
    local itemName = bracketContent:match(":([^%]:]+)$")
    if not itemName then
        itemName = bracketContent:match("%-(.+)$") or bracketContent
    end
    itemName = itemName:gsub("[%s%]]+$", ""):gsub("^%s+", "")
    if not itemName or itemName == "" then return nil, nil end

    -- Try to get full item link from client cache
    local giiName, giiLink = GetItemInfo(itemName)
    if giiLink then
        local id = giiLink:match("item:(%d+)")
        if id then return tonumber(id), giiLink end
    end

    -- Item not in cache yet — request it, but DON'T fall back to itemID=0
    -- Use the itemID parsed from the bracket text itself (e.g. 276 from [276-锁甲头:xxx])
    C_Item.RequestLoadItemDataByName(itemName)

    -- Fallback: use the bracket-extracted itemID and the original bracket text as the display link
    -- This ensures the record is never lost just because the client cache is cold
    local finalItemID = bracketItemID or 0
    local fallbackLink = "|cffffff00|Hitem:" .. finalItemID .. "::::::::90:::::|h[" .. itemName .. "]|h|r"
    return finalItemID, fallbackLink
end

-- Find player class from raid roster by short name (without server suffix)
local function FindPlayerClass(searchName)
    if not searchName then return "UNKNOWN" end
    for i = 1, GetNumGroupMembers() do
        local name, _, _, _, _, _, _, _, _, _, class = GetRaidRosterInfo(i)
        if name then
            local shortName = name:match("^(.-)%-") or name
            if shortName == searchName then
                return class or "UNKNOWN"
            end
        end
    end
    return "UNKNOWN"
end

-- Record a loot item with dedup check. Returns true if recorded.
local function RecordLootItem(encounterID, recipient, itemID, itemLink, distributionMethod)
    if not encounterID or not recipient or not itemID then return false end

    -- Bug 3 额外保护：过滤掉 "你"（系统消息自称）
    local shortRecipientCheck = recipient:match("^(.-)%-") or recipient
    if shortRecipientCheck == "你" then return false end

    -- 清洗 itemLink 末尾可能附带的标点符号
    if itemLink then
        itemLink = itemLink:gsub("[。.,，]+$", "")
    end

    -- Secondary quality filter: only record Rare (blue) and above
    -- v2.0.7 修复：物品未缓存时放行，标记 qualityUnconfirmed
    local qualityUnconfirmed = false
    if itemLink then
        local quality = GetQualityFromItemLink(itemLink)
        if quality and quality < 3 then
            if BLT_DebugMode then
                print("|cffFFD700[BLT Debug]|r RecordLootItem filtered quality=" .. quality .. " item=" .. tostring(itemID))
            end
            return false
        elseif not quality then
            -- itemLink 中也没有品质信息，可能是未缓存物品，放行处理
            qualityUnconfirmed = true
            if BLT_DebugMode then
                print("|cffFFD700[BLT Debug]|r RecordLootItem quality unconfirmed, allowing: itemID=" .. tostring(itemID))
            end
        end
    else
        -- 没有 itemLink，也无法判断品质，放行处理
        qualityUnconfirmed = true
    end
    -- 去掉recipient的服务器后缀，确保去重key一致
    local shortRecipient = recipient:match("^(.-)%-") or recipient
    local dedupKey = tostring(encounterID) .. "_" .. tostring(itemID) .. "_" .. shortRecipient

    -- Bug 1 修复：二次去重——检查 lootRecords 中是否已有相同记录（5秒内）
    local now = time()
    for i = #BLT.DB.lootRecords, 1, -1 do
        local r = BLT.DB.lootRecords[i]
        if r.encounterID == encounterID and r.itemID == itemID then
            local rShortName = r.playerName:match("^(.-)%-") or r.playerName
            if rShortName == shortRecipient and math.abs(r.timestamp - now) < 5 then
                if BLT_DebugMode then
                    print("|cffFFD700[BLT Debug]|r RecordLootItem dedup: skipped duplicate for " .. shortRecipient)
                end
                -- Still update distributionMethod if this entry provides a better one
                if distributionMethod and distributionMethod ~= DistributionMethods.UNKNOWN then
                    r.distributionMethod = distributionMethod
                end
                return false
            end
        end
    end

    if PendingLootItems[dedupKey] then
        -- Already recorded by ENCOUNTER_LOOT_RECEIVED; update distributionMethod if CHAT_MSG_LOOT provides it
        if distributionMethod and distributionMethod ~= DistributionMethods.UNKNOWN then
            for i = #BLT.DB.lootRecords, 1, -1 do
                local r = BLT.DB.lootRecords[i]
                local rShortName = r.playerName:match("^(.-)%-") or r.playerName
                if r.encounterID == encounterID and r.itemID == itemID and rShortName == shortRecipient then
                    r.distributionMethod = distributionMethod
                    if BLT_DebugMode then
                        print("|cffFFD700[BLT Debug]|r Updated distributionMethod for " .. recipient .. " -> " .. tostring(distributionMethod))
                    end
                    break
                end
            end
        end
        return false
    end
    PendingLootItems[dedupKey] = true

    -- 如果distributionMethod是UNKNOWN且当前在Boss战中，自动标记为Boss掉落
    if distributionMethod == DistributionMethods.UNKNOWN and CurrentEncounter and CurrentEncounter.id == encounterID then
        distributionMethod = DistributionMethods.BOSS_DROP
    end

    local classFile = FindPlayerClass(recipient)
    local raidName, difficulty
    if CurrentEncounter then
        raidName = CurrentEncounter.raidName
        difficulty = CurrentEncounter.difficulty
    end
    if not raidName then
        raidName, difficulty = GetRaidInstanceInfo()
    end

    local record = {
        id = #BLT.DB.lootRecords + 1,
        timestamp = time(),
        encounterID = encounterID,
        bossName = (CurrentEncounter and CurrentEncounter.name) or "Unknown",
        raidName = raidName or "Unknown",
        difficulty = difficulty or "Unknown",
        itemID = itemID,
        itemLink = itemLink,
        quantity = 1,
        playerName = recipient,
        classFileName = classFile,
        distributionMethod = distributionMethod or DistributionMethods.UNKNOWN
    }
    if qualityUnconfirmed then
        record.qualityUnconfirmed = true
    end

    table.insert(BLT.DB.lootRecords, record)
    print("|cff00FF00[BossLootTracker]|r 记录：" .. recipient .. " 获得了 " .. (itemLink or "item:"..tostring(itemID)))
    return true
end

--------------------------------------------------------------------------------
-- CHAT_MSG_LOOT handler
--------------------------------------------------------------------------------
-- Format A: "[战利品]：玩家名(需求 - N，主专精)赢得了： [ilevel-type:name]"
-- Format B: "玩家名-服务器获得了战利品： [ilevel-type:name]"
-- Format C: "玩家名获得了物品：|Hitem:xxx|h[name]|h" (old style)
local function OnChatMsgLoot(event, msg, ...)
    if BLT_DebugMode and IsInRaid() then
        print("|cffFFD700[BLT Debug]|r CHAT_MSG_LOOT: " .. msg)
    end

    local inRaid = IsInRaid()
    if not inRaid then return end
    if not CurrentEncounter then return end

    local recipient = nil
    local itemID = nil
    local itemLink = nil
    local distributionMethod = DistributionMethods.UNKNOWN

    -- Format A: [战利品]：玩家名(需求/贪婪/幻化 - N，主专精)赢得了： [ilevel-type:name]
    -- Also: [战利品]: 玩家名(幻化 - 58) 赢得： [ilevel-type:name]
    do
        local winnerAll = msg:match("%[战利品%]%s*[：:]%s*(.+?)%s*[赢获]得")
        if winnerAll then
            recipient = winnerAll:match("^(.-)%s*%(")
            if recipient then recipient = recipient:gsub("%s+$", "") end
            if not recipient or recipient == "" then
                recipient = winnerAll:gsub("%s+$", "")
            end
            -- Distribution method
            local methodStr = winnerAll:match("%((.-)%)") or ""
            if methodStr:find("需求") then
                distributionMethod = DistributionMethods.NEED
            elseif methodStr:find("贪婪") then
                distributionMethod = DistributionMethods.GREED
            elseif methodStr:find("幻化") then
                distributionMethod = DistributionMethods.TRANSMOG
            end
            -- Item from after 赢得了：
            local lootPart = msg:match("赢得了[：:]%s*(.+)$")
            if lootPart then
                itemID, itemLink = ParseLootBracket(lootPart)
            end
            if BLT_DebugMode then
                print("|cffFFD700[BLT Debug]|r FormatA: recipient=" .. tostring(recipient) .. " itemID=" .. tostring(itemID) .. " method=" .. tostring(distributionMethod))
            end
        end
    end

    -- Format B: 玩家名-服务器获得了战利品： [ilevel-type:name]
    if not recipient then
        local newLootPlayer, newLootItem = msg:match("^(.+)获得了战利品[：:]%s*(.+)$")
        if newLootPlayer and newLootItem then
            recipient = newLootPlayer:match("^(.-)%-") or newLootPlayer
            recipient = recipient:gsub("%s+$", "")
            itemID, itemLink = ParseLootBracket(newLootItem)
            if BLT_DebugMode then
                print("|cffFFD700[BLT Debug]|r FormatB: recipient=" .. tostring(recipient) .. " itemID=" .. tostring(itemID))
            end
        end
    end

    -- If we found a valid item from new formats, record it
    -- Bug 3 额外保护：过滤掉 "你"（系统消息自称）
    if recipient and (recipient == "你" or recipient == "你 ") then return end
    if recipient and itemID and itemLink then
        RecordLootItem(CurrentEncounter.id, recipient, itemID, itemLink, distributionMethod)
        return
    end

    -- Format C: old-style "玩家名获得了物品：|Hitem:xxx|h[name]|h"
    local playerName, oldItemLink = msg:match("^(.+)获得了物品：(.+)$")
    if not playerName then
        playerName, oldItemLink = msg:match("^(.+)收到了物品：(.+)$")
    end
    if not playerName then
        playerName, oldItemLink = msg:match("^(.+) receives loot: (.+)$")
    end
    if not playerName then
        playerName, oldItemLink = msg:match("^(.+) gets loot: (.+)$")
    end

    if not playerName or not oldItemLink then return end

    local extractedItemID = oldItemLink:match("item:(%d+)")
    if not extractedItemID then return end
    extractedItemID = tonumber(extractedItemID)

    playerName = playerName:match("^(.-)%-") or playerName
    playerName = playerName:gsub("%s+$", "")

    RecordLootItem(CurrentEncounter.id, playerName, extractedItemID, oldItemLink, DistributionMethods.UNKNOWN)
end

-- Handle LOOT_OPENED for raid loot mode detection
local function OnLootOpened(event)
    if not IsInRaid() then return end
    local lootMethod = GetLootMethod()
    if BLT_DebugMode then
        print("|cffFFD700[BLT Debug]|r LOOT_OPENED, lootMethod=" .. tostring(lootMethod))
    end
    if lootMethod and lootMethod ~= "personalloot" then
        IsRaidLootOpen = true
    end
end

-- Handle LOOT_CLOSED to reset raid loot tracking
local function OnLootClosed(event)
    IsRaidLootOpen = false
end

--------------------------------------------------------------------------------
-- CHAT_MSG_SYSTEM handler
--------------------------------------------------------------------------------
-- Handles Master Looter and Group Loot distribution messages
local function OnChatMsgSystem(event, msg, ...)
    if not IsInRaid() or not CurrentEncounter then return end

    if BLT_DebugMode and (msg:find("|Hitem:") or msg:find("战利品")) then
        print("|cffFFD700[BLT Debug]|r CHAT_MSG_SYSTEM: " .. msg)
    end

    local hasItemLink = msg:find("|Hitem:")
    local hasLootBracket = msg:find("%[%d+%-.-%]") or msg:find("战利品")
    if not hasItemLink and not hasLootBracket then return end

    local distributor, itemLink, recipient
    local itemID = nil
    local distributionMethod = DistributionMethods.UNKNOWN

    -- ML pattern 1: "XXX 指定了 |Hitem:...|h[...] |h 给 玩家名"
    distributor, itemLink, recipient = msg:match("^(.+)%s 指定了 (.+)%s 给%s(.+)$")
    if not itemLink then
        distributor, itemLink, recipient = msg:match("^(.+)%s 将 (.+)%s 分配给了%s(.+)$")
    end
    if not itemLink then
        distributor, itemLink, recipient = msg:match("^(.+)%s 分配了 (.+)%s 给%s(.+)$")
    end

    -- Group Loot patterns
    if not itemLink then
        recipient, itemLink = msg:match("^(.+)%s 赢得了 (.+)%s 的掷骰$")
    end
    if not itemLink then
        recipient, itemLink = msg:match("^(.+)%s 通过需求获得了 (.+)$")
        if recipient then distributionMethod = DistributionMethods.NEED end
    end
    if not itemLink then
        recipient, itemLink = msg:match("^(.+)%s 通过贪婪获得了 (.+)$")
        if recipient then distributionMethod = DistributionMethods.GREED end
    end
    if not itemLink then
        recipient, itemLink = msg:match("^(.+)%s 通过幻化获得了 (.+)$")
        if recipient then distributionMethod = DistributionMethods.TRANSMOG end
    end
    if not itemLink then
        recipient, itemLink = msg:match("^(.+)%s 已经获得了 (.+)$")
    end

    -- English fallback patterns
    if not itemLink then
        distributor, itemLink, recipient = msg:match("^(.+)%s distributed (.+)%s to%s(.+)$")
    end
    if not itemLink then
        recipient, itemLink = msg:match("^(.+)%s won (.+)%s with a roll of")
    end
    if not itemLink then
        recipient, itemLink = msg:match("^(.+)%s won (.+)$")
    end

    -- New-format [战利品] patterns in system messages
    if not itemLink then
        local winnerAll = msg:match("%[战利品%]%s*[：:]%s*(.+?)%s*[赢获]得")
        if winnerAll then
            recipient = winnerAll:match("^(.-)%s*%(")
            if recipient then recipient = recipient:gsub("%s+$", "") end
            if not recipient or recipient == "" then
                recipient = winnerAll:gsub("%s+$", "")
            end
            local methodStr = winnerAll:match("%((.-)%)") or ""
            if methodStr:find("需求") then
                distributionMethod = DistributionMethods.NEED
            elseif methodStr:find("贪婪") then
                distributionMethod = DistributionMethods.GREED
            elseif methodStr:find("幻化") then
                distributionMethod = DistributionMethods.TRANSMOG
            end
            local lootPart = msg:match("赢得了[：:]%s*(.+)$")
            if lootPart then
                itemID, itemLink = ParseLootBracket(lootPart)
            end
        end
    end

    if not itemLink or not recipient then return end

    -- Extract itemID from itemLink if not already set
    if not itemID then
        local extractedID = itemLink:match("item:(%d+)")
        if extractedID then
            itemID = tonumber(extractedID)
        end
    end
    if not itemID then return end

    -- Clean recipient name
    recipient = recipient:match("^(.-)%-") or recipient
    recipient = recipient:gsub("%s+$", "")

    -- Bug 3 额外保护：过滤掉 "你"
    if recipient == "你" then return end

    RecordLootItem(CurrentEncounter.id, recipient, itemID, itemLink, distributionMethod)
end

-- Event frame
local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("BOSS_KILL")
EventFrame:RegisterEvent("ENCOUNTER_START")
EventFrame:RegisterEvent("ENCOUNTER_END")
EventFrame:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
EventFrame:RegisterEvent("CHAT_MSG_LOOT")
EventFrame:RegisterEvent("LOOT_OPENED")
EventFrame:RegisterEvent("LOOT_CLOSED")
EventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
EventFrame:RegisterEvent("CHAT_MSG_RAID")
EventFrame:RegisterEvent("CHAT_MSG_RAID_WARNING")
EventFrame:SetScript("OnEvent", function(self, event, ...)
    -- Debug: log loot-related events
    if BLT_DebugMode then
        local args = {...}
        local msg = args[1] or ""
        if type(msg) == "string" and (msg:find("战利品") or msg:find("loot") or msg:find("Loot") or msg:find("赢得了") or msg:find("掷骰") or msg:find("roll")) then
            print("|cffFFD700[BLT Debug]|r Event=" .. event .. " msg=" .. msg:sub(1, 120))
        end
    end
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == AddonName then
            InitializeDB()
            print("|cff00FF00[BossLootTracker]|r 已加载 - 版本 " .. Version)
            print("|cff00FF00[BossLootTracker]|r 使用 /blt 打开主窗口")
        end
    elseif event == "BOSS_KILL" then
        local encounterID, encounterName = ...
        OnBossKill(event, encounterID, encounterName)
    elseif event == "ENCOUNTER_START" then
        local encounterID, encounterName, difficultyID, groupSize = ...
        OnEncounterStart(event, encounterID, encounterName, difficultyID, groupSize)
    elseif event == "ENCOUNTER_END" then
        local encounterID, encounterName, difficultyID, groupSize = ...
        OnEncounterEnd(event, encounterID, encounterName, difficultyID, groupSize)
    elseif event == "ENCOUNTER_LOOT_RECEIVED" then
        -- v2.1.0: capture args first (Lua 5.1 anonymous functions can't use ...)
        local elr_encounterID, elr_itemID, elr_itemLink, elr_quantity, elr_playerName, elr_classFileName = ...
        local ok, err = pcall(OnEncounterLootReceived, event, elr_encounterID, elr_itemID, elr_itemLink, elr_quantity, elr_playerName, elr_classFileName)
        if not ok and BLT_DebugMode then
            print("|cffFFD700[BLT Debug]|r ENCOUNTER_LOOT_RECEIVED error: " .. tostring(err))
        end
    elseif event == "CHAT_MSG_LOOT" then
        OnChatMsgLoot(event, ...)
    elseif event == "LOOT_OPENED" then
        OnLootOpened(event)
    elseif event == "LOOT_CLOSED" then
        OnLootClosed(event)
    elseif event == "CHAT_MSG_SYSTEM" then
        OnChatMsgSystem(event, ...)
    end
end)

-- Slash command handler
SLASH_BOSSLOOTTRACKER1 = "/blt"
SlashCmdList["BOSSLOOTTRACKER"] = function(msg)
    msg = msg:lower()
    if msg == "toggle" or msg == "" then
        if BLT.UI and BLT.UI.Toggle then
            BLT.UI.Toggle()
        end
    elseif msg == "show" then
        if BLT.UI and BLT.UI.Show then
            BLT.UI.Show()
        end
    elseif msg == "hide" then
        if BLT.UI and BLT.UI.Hide then
            BLT.UI.Hide()
        end
    elseif msg == "clear" then
        StaticPopup_Show("BOSSLOOTTRACKER_CLEAR_CONFIRM")
    elseif msg == "export" then
        if BLT.Export and BLT.Export.ShowDialog then
            BLT.Export.ShowDialog()
        end
    elseif msg == "debug" then
        BLT_DebugMode = not BLT_DebugMode
        print("|cffFFD700[BossLootTracker]|r 调试模式: " .. (BLT_DebugMode and "开启" or "关闭"))
        if BLT_DebugMode then
            print("|cffFFD700[BossLootTracker]|r 将记录所有拾取相关事件和消息")
        end
    else
        print("|cff00FF00[BossLootTracker]|r 命令:")
        print("  /blt - 切换主窗口")
        print("  /blt show - 显示主窗口")
        print("  /blt hide - 隐藏主窗口")
        print("  /blt clear - 清空所有记录")
        print("  /blt export - 导出数据")
        print("  /blt debug - 切换调试模式")
    end
end

-- Create clear confirmation dialog
local function CreateClearDialog()
    StaticPopupDialogs["BOSSLOOTTRACKER_CLEAR_CONFIRM"] = {
        text = "确定要清空所有战利品记录吗？此操作不可撤销。",
        button1 = "确定",
        button2 = "取消",
        OnAccept = function()
            BLT.DB.lootRecords = {}
            print("|cff00FF00[BossLootTracker]|r 已清空所有记录")
            if BLT.UI and BLT.UI.Refresh then
                BLT.UI.Refresh()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3
    }
end

-- Create edit confirmation dialog
local function CreateEditDialog()
    StaticPopupDialogs["BOSSLOOTTRACKER_EDIT_CONFIRM"] = {
        text = "编辑此记录？",
        button1 = "保存",
        button2 = "取消",
        OnAccept = function()
            if BLT.UI and BLT.UI.SaveEdit then
                BLT.UI.SaveEdit()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        hasEditBox = false,
        preferredIndex = 3
    }
end

-- Initialize dialogs
CreateClearDialog()
CreateEditDialog()

-- Export functions for other modules
BLT.GetClassColor = BLT.GetClassColor
BLT.FormatTimestamp = BLT.FormatTimestamp
BLT.ClassColors = ClassColors
BLT.DistributionMethods = DistributionMethods
BLT.Version = Version
