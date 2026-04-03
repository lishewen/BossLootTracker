-- BossLootTracker - Main Logic and Event Handlers
-- WoW Addon for version 12.0.1 (Midnight)

-- Addon namespace
local AddonName, BLT = ...
BLT.DB = BLT or {}

-- Version info
local Version = GetAddOnMetadata(AddonName, "Version") or "1.0.0"

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
    local date = date("%Y-%m-%d %H:%M:%S", timestamp)
    return date
end

-- Get raid instance info
local function GetRaidInstanceInfo()
    local name, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceMapID, instanceGroupSize = GetInstanceInfo()
    return name, difficultyName
end

-- Handle boss kill event
local function OnBossKill(event, encounterID, encounterName)
    CurrentEncounter = {
        id = encounterID,
        name = encounterName,
        timestamp = time()
    }

    -- Get raid instance info
    local raidName, difficulty = GetRaidInstanceInfo()

    if CurrentEncounter then
        CurrentEncounter.raidName = raidName
        CurrentEncounter.difficulty = difficulty
    end
end

-- Handle encounter loot received event
local function OnEncounterLootReceived(event, encounterID, encounterName, itemID, itemLink, quantity, playerName, classFileName, lootMethod)
    if not encounterID or not itemID or not playerName then
        return
    end

    -- Get raid instance info
    local raidName, difficulty = GetRaidInstanceInfo()

    -- Determine distribution method
    local distributionMethod = DistributionMethods.UNKNOWN
    if lootMethod == 1 then
        distributionMethod = DistributionMethods.NEED
    elseif lootMethod == 2 then
        distributionMethod = DistributionMethods.GREED
    elseif lootMethod == 3 then
        distributionMethod = DistributionMethods.TRANSMOG
    end

    -- Create loot record
    local record = {
        id = #BLT.DB.lootRecords + 1,
        timestamp = time(),
        encounterID = encounterID,
        bossName = encounterName or "Unknown",
        raidName = raidName or "Unknown",
        difficulty = difficulty or "Unknown",
        itemID = itemID,
        itemLink = itemLink,
        quantity = quantity or 1,
        playerName = playerName,
        classFileName = classFileName or "UNKNOWN",
        distributionMethod = distributionMethod
    }

    -- Add to database
    table.insert(BLT.DB.lootRecords, record)

    -- Debug print
    print("|cff00FF00[BossLootTracker]|r 记录: " .. playerName .. " 获得了 " .. (itemLink or "item:"..itemID))
end

-- Event frame
local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("BOSS_KILL")
EventFrame:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
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
        local encounterID, encounterName, itemID, itemLink, quantity, playerName, classFileName, lootMethod = ...
        OnEncounterLootReceived(event, encounterID, encounterName, itemID, itemLink, quantity, playerName, classFileName, lootMethod)
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
    else
        print("|cff00FF00[BossLootTracker]|r 命令:")
        print("  /blt - 切换主窗口")
        print("  /blt show - 显示主窗口")
        print("  /blt hide - 隐藏主窗口")
        print("  /blt clear - 清空所有记录")
        print("  /blt export - 导出数据")
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
