-- BossLootTracker - Main Logic and Event Handlers
-- WoW for version 12.0.1 (Midnight)
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
end

-- Handle encounter loot received event
-- NOTE: ENCOUNTER_LOOT_RECEIVED fires ONCE per item drop
-- Event params: encounterID, itemID, itemLink, quantity, playerName, classFileName
-- NO encounterName or lootMethod in this event!
local function OnEncounterLootReceived(event, encounterID, itemID, itemLink, quantity, playerName, classFileName)
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

    -- Filter by item class - only record equipment and crafting reagents
    -- Skip consumables, quest items, containers, trade goods (non-reagent), misc
    local _, _, _, _, _, _, _, _, itemEquipLoc, _, _, itemClassID, itemSubClassID = GetItemInfo(itemID)
    if itemClassID then
        -- 0=Armor, 1=Weapon, 2=Gem (cata+), 3=Container (skip), 4=Consumable (skip)
        -- 5=Trade Goods, 6=Gem (classic), 7=Glyph, 8=Quest (skip), 9=Misc
        -- 10=Recipe, 11=Reagent (cata+)
        if itemClassID == 3 or itemClassID == 4 or itemClassID == 8 then
            -- Container, Consumable, Quest item - skip
            if BLT_DebugMode then
                print("|cffFFD700[BLT Debug]|r Filtered itemClassID=" .. itemClassID .. " item=" .. tostring(itemID))
            end
            return
        end
    end

    -- Validate playerName - must have a valid receiver
    if not playerName or playerName == "" then
        return
    end

    -- Get boss name from BOSS_KILL tracking or EJ_GetEncounterInfo
    local bossName = "Unknown"
    if CurrentEncounter and CurrentEncounter.id == encounterID then
        bossName = CurrentEncounter.name or "Unknown"
    else
        -- Try to get from Encounter Journal
        local name = EJ_GetEncounterInfo(encounterID)
        if name then
            bossName = name
        end
    end

    -- Get raid instance info from CurrentEncounter or GetInstanceInfo
    local raidName, difficulty
    if CurrentEncounter then
        raidName = CurrentEncounter.raidName
        difficulty = CurrentEncounter.difficulty
    end
    if not raidName then
        raidName, difficulty = GetRaidInstanceInfo()
    end

    -- Fix classFileName - default to UNKNOWN when nil
    local classFile = classFileName
    if not classFile or classFile == "" then
        classFile = "UNKNOWN"
    end

    -- Handle itemLink - preserve color codes for tooltip display
    local cleanItemLink = itemLink
    if not itemLink then
        cleanItemLink = "item:" .. tostring(itemID)
    end

    -- Validate quantity
    local qty = quantity or 1
    if type(qty) ~= "number" or qty < 1 then
        qty = 1
    end

    -- Dedup: mark this item as recorded
    local dedupKey = tostring(encounterID) .. "_" .. tostring(itemID) .. "_" .. playerName
    PendingLootItems[dedupKey] = true

    -- Create loot record
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
        distributionMethod = DistributionMethods.UNKNOWN
    }

    -- Add to database
    table.insert(BLT.DB.lootRecords, record)

    -- Print to chat
    print("|cff00FF00[BossLootTracker]|r 记录：" .. playerName .. " 获得了 " .. (cleanItemLink or "item:"..tostring(itemID)))
end

-- Handle CHAT_MSG_LOOT for raid loot detection
-- In raids, loot is often distributed via ML/PL and shows up as chat messages
-- Pattern: "[Player] 获得了物品：[ItemLink]" or "[Player]收到了物品：[ItemLink]xN"
local function OnChatMsgLoot(event, msg, ...)
    -- Debug: log CHAT_MSG_LOOT in raids
    if BLT_DebugMode and IsInRaid() then
        print("|cffFFD700[BLT Debug]|r CHAT_MSG_LOOT: " .. msg)
    end
    
    -- Only process if we're in a raid (party loot is handled by ENCOUNTER_LOOT_RECEIVED)
    local inRaid = IsInRaid()
    if not inRaid then return end

    -- Only process if we have a current encounter (inside a boss fight or just killed)
    if not CurrentEncounter then return end

    -- Check if we already recorded this from ENCOUNTER_LOOT_RECEIVED
    -- to avoid duplicates. We use a simple dedup based on itemLink + playerName

    -- Pattern 1: "玩家名获得了物品：|Hitem:xxx|h[name]|h"
    -- Pattern 2: "玩家名收到了物品：|Hitem:xxx|h[name]|h|x3"
    local playerName, itemLink = msg:match("^(.+)获得了物品：(.+)$")
    if not playerName then
        playerName, itemLink = msg:match("^(.+)收到了物品：(.+)$")
    end

    -- Also try English patterns
    if not playerName then
        playerName, itemLink = msg:match("^(.+) receives loot: (.+)$")
    end
    if not playerName then
        playerName, itemLink = msg:match("^(.+) gets loot: (.+)$")
    end

    if not playerName or not itemLink then return end

    -- Extract quantity from itemLink suffix like x2
    local quantity = 1
    local qtyMatch = itemLink:match("|h%x(%d+)")
    if qtyMatch then
        quantity = tonumber(qtyMatch) or 1
    end

    -- Extract itemID from itemLink: |Hitem:12345:...
    local itemID = itemLink:match("item:(%d+)")
    if not itemID then return end
    itemID = tonumber(itemID)

    -- Clean playerName (remove server suffix if present)
    playerName = playerName:match("^(.-)%-") or playerName

    -- Dedup check: skip if we already have this exact record
    local dedupKey = tostring(CurrentEncounter.id) .. "_" .. tostring(itemID) .. "_" .. playerName
    if PendingLootItems[dedupKey] then return end
    PendingLootItems[dedupKey] = true

    -- Get player's class
    local classFile = "UNKNOWN"
    if playerName then
        -- Try to get class from raid roster
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, _, _, _, _, _, class = GetRaidRosterInfo(i)
            if name then
                local shortName = name:match("^(.-)%-") or name
                if shortName == playerName then
                    classFile = class or "UNKNOWN"
                    break
                end
            end
        end
    end

    -- Get raid info
    local raidName = CurrentEncounter.raidName
    local difficulty = CurrentEncounter.difficulty
    if not raidName then
        raidName, difficulty = GetRaidInstanceInfo()
    end

    local record = {
        id = #BLT.DB.lootRecords + 1,
        timestamp = time(),
        encounterID = CurrentEncounter.id,
        bossName = CurrentEncounter.name or "Unknown",
        raidName = raidName or "Unknown",
        difficulty = difficulty or "Unknown",
        itemID = itemID,
        itemLink = itemLink,
        quantity = quantity,
        playerName = playerName,
        classFileName = classFile,
        distributionMethod = DistributionMethods.UNKNOWN
    }

    table.insert(BLT.DB.lootRecords, record)
    print("|cff00FF00[BossLootTracker]|r 记录：" .. playerName .. " 获得了 " .. (itemLink or "item:"..tostring(itemID)))
end

-- Debug mode flag
local BLT_DebugMode = false

-- Handle LOOT_OPENED for raid loot mode detection
-- In raids, ENCOUNTER_LOOT_RECEIVED may not fire depending on loot method
-- We track all non-personal loot methods via CHAT_MSG_LOOT and CHAT_MSG_SYSTEM
local function OnLootOpened(event)
    -- Only track in raids
    if not IsInRaid() then return end
    
    local lootMethod = GetLootMethod()
    -- Debug logging
    if BLT_DebugMode then
        print("|cffFFD700[BLT Debug]|r LOOT_OPENED, lootMethod=" .. tostring(lootMethod))
    end
    
    -- Track all raid loot methods except personalloot
    -- Because with personal loot ENCOUNTER_LOOT_RECEIVED already works
    if lootMethod and lootMethod ~= "personalloot" then
        IsRaidLootOpen = true
    end
end

-- Handle LOOT_CLOSED to reset raid loot tracking
local function OnLootClosed(event)
    IsRaidLootOpen = false
end

-- Handle CHAT_MSG_SYSTEM for raid loot distribution messages
-- This covers both Master Looter and Group Loot (ILvL system with need/greed/transmog roll)
local function OnChatMsgSystem(event, msg, ...)
    -- Only process in raids with active encounter
    if not IsInRaid() or not CurrentEncounter then return end
    
    -- Debug: log all CHAT_MSG_SYSTEM in raids that contain item links
    if BLT_DebugMode and msg:find("|Hitem:") then
        print("|cffFFD700[BLT Debug]|r CHAT_MSG_SYSTEM: " .. msg)
    end
    
    -- Only process messages containing item links
    if not msg:find("|Hitem:") then return end
    
    local distributor, itemLink, recipient
    
    -- ML pattern 1: "XXX 指定了 |Hitem:...|h[...] |h 给 玩家名"
    distributor, itemLink, recipient = msg:match("^(.+)%s 指定了 (.+)%s 给%s(.+)$")
    
    -- ML pattern 2: "XXX 将 |Hitem:...|h[...] |h 分配给了 玩家名"
    if not itemLink then
        distributor, itemLink, recipient = msg:match("^(.+)%s 将 (.+)%s 分配给了%s(.+)$")
    end
    
    -- ML pattern 3: "XXX 分配了 |Hitem:...|h[...] |h 给 玩家名"
    if not itemLink then
        distributor, itemLink, recipient = msg:match("^(.+)%s 分配了 (.+)%s 给%s(.+)$")
    end
    
    -- Group Loot pattern: "玩家名 赢得了 |Hitem:...|h[...] |h 的掷骰"
    if not itemLink then
        recipient, itemLink = msg:match("^(.+)%s 赢得了 (.+)%s 的掷骰$")
    end
    
    -- Group Loot pattern: "玩家名 通过需求获得了 |Hitem:...|h[...] |h"
    if not itemLink then
        recipient, itemLink = msg:match("^(.+)%s 通过需求获得了 (.+)$")
    end
    
    -- Group Loot pattern: "玩家名 通过贪婪获得了 |Hitem:...|h[...] |h"
    if not itemLink then
        recipient, itemLink = msg:match("^(.+)%s 通过贪婪获得了 (.+)$")
    end
    
    -- Group Loot pattern: "玩家名 通过幻化获得了 |Hitem:...|h[...] |h"
    if not itemLink then
        recipient, itemLink = msg:match("^(.+)%s 通过幻化获得了 (.+)$")
    end
    
    -- Group Loot pattern: "玩家名 已经获得了 |Hitem:...|h[...] |h" (auto-awarded)
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
    
    if not itemLink or not recipient then return end
    
    -- Extract itemID from itemLink
    local itemID = itemLink:match("item:(%d+)")
    if not itemID then return end
    itemID = tonumber(itemID)
    
    -- Clean recipient name (remove server suffix)
    recipient = recipient:match("^(.-)%-") or recipient
    recipient = recipient:gsub("%s+$", "")  -- Trim trailing spaces
    
    -- Dedup check
    local dedupKey = tostring(CurrentEncounter.id) .. "_" .. tostring(itemID) .. "_" .. recipient
    if PendingLootItems[dedupKey] then return end
    PendingLootItems[dedupKey] = true
    
    -- Get recipient's class from raid roster
    local classFile = "UNKNOWN"
    for i = 1, GetNumGroupMembers() do
        local name, _, _, _, _, _, _, _, _, _, class = GetRaidRosterInfo(i)
        if name then
            local shortName = name:match("^(.-)%-") or name
            if shortName == recipient then
                classFile = class or "UNKNOWN"
                break
            end
        end
    end
    
    -- Get raid info
    local raidName = CurrentEncounter.raidName
    local difficulty = CurrentEncounter.difficulty
    if not raidName then
        raidName, difficulty = GetRaidInstanceInfo()
    end
    
    -- Create loot record
    local record = {
        id = #BLT.DB.lootRecords + 1,
        timestamp = time(),
        encounterID = CurrentEncounter.id,
        bossName = CurrentEncounter.name or "Unknown",
        raidName = raidName or "Unknown",
        difficulty = difficulty or "Unknown",
        itemID = itemID,
        itemLink = itemLink,
        quantity = 1,
        playerName = recipient,
        classFileName = classFile,
        distributionMethod = DistributionMethods.UNKNOWN
    }
    
    table.insert(BLT.DB.lootRecords, record)
    print("|cff00FF00[BossLootTracker]|r 记录：" .. recipient .. " 获得了 " .. (itemLink or "item:"..tostring(itemID)))
end

-- Event frame
local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("BOSS_KILL")
EventFrame:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
EventFrame:RegisterEvent("CHAT_MSG_LOOT")
EventFrame:RegisterEvent("LOOT_OPENED")
EventFrame:RegisterEvent("LOOT_CLOSED")
EventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
EventFrame:SetScript("OnEvent", function(self, event, ...)
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
    elseif event == "ENCOUNTER_LOOT_RECEIVED" then
        -- Event params: encounterID, itemID, itemLink, quantity, playerName, classFileName
        local encounterID, itemID, itemLink, quantity, playerName, classFileName = ...
        OnEncounterLootReceived(event, encounterID, itemID, itemLink, quantity, playerName, classFileName)
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
        -- Clear all records
        StaticPopup_Show("BOSSLOOTTRACKER_CLEAR_CONFIRM")
    elseif msg == "export" then
        -- Show export dialog
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
            -- Save changes handled by UI module
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
