-- BossLootTracker - UI Module
-- Creates and manages the main window UI

local AddonName, BLT = ...

-- UI namespace
BLT.UI = {}

local UI = BLT.UI
local DB

-- Initialize HeaderButtons table
UI.HeaderButtons = {}

-- Current filter and sort state
local currentFilters = {
    raidInstance = "全部",
    boss = "全部",
    player = "全部",
    date = "全部"
}

local currentSort = {
    column = "timestamp",
    ascending = false
}

-- Filtered and sorted data
local filteredRecords = {}

-- Edit mode state
local editMode = {
    active = false,
    recordId = nil,
    originalData = nil
}

-- Minimap button state
local minimapButton = nil

-- Create main frame
local function CreateMainFrame()
    local frame = CreateFrame("Frame", "BossLootTrackerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(900, 600)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Set backdrop (dark WoW-style panel)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetSize(878, 30)
    titleBar:SetPoint("TOP", frame, "TOP", 0, -5)
    titleBar:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "",
        tile = true,
        tileSize = 32,
        edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })

    -- Title text
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    titleText:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    titleText:SetText("BossLootTracker")

    -- Close button
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- Store reference
    UI.MainFrame = frame

    return frame
end

-- Create filter buttons
local function CreateFilters(frame)
    local filterFrame = CreateFrame("Frame", nil, frame)
    filterFrame:SetSize(878, 30)
    filterFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 11, -45)

    -- Raid instance filter
    local raidLabel = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    raidLabel:SetPoint("LEFT", filterFrame, "LEFT", 0, 0)
    raidLabel:SetText("团队副本:")

    local raidButton = CreateFrame("Button", nil, filterFrame, "UIDropDownMenuTemplate")
    raidButton:SetPoint("LEFT", raidLabel, "RIGHT", 5, 0)
    raidButton:SetSize(150, 30)
    UIDropDownMenu_SetWidth(raidButton, 140)
    UIDropDownMenu_Initialize(raidButton, function()
        local raids = UI.GetUniqueRaids()
        UIDropDownMenu_AddButton({ text = "全部", value = "全部", func = function()
            UIDropDownMenu_SetSelectedValue(raidButton, "全部")
            currentFilters.raidInstance = "全部"
            UI.Refresh()
        end })
        for _, raid in ipairs(raids) do
            UIDropDownMenu_AddButton({ text = raid, value = raid, func = function()
                UIDropDownMenu_SetSelectedValue(raidButton, raid)
                currentFilters.raidInstance = raid
                UI.Refresh()
            end })
        end
    end)
    UIDropDownMenu_SetSelectedValue(raidButton, "全部")
    UI.RaidFilterButton = raidButton

    -- Boss filter
    local bossLabel = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bossLabel:SetPoint("LEFT", raidButton, "RIGHT", 20, 0)
    bossLabel:SetText("BOSS:")

    local bossButton = CreateFrame("Button", nil, filterFrame, "UIDropDownMenuTemplate")
    bossButton:SetPoint("LEFT", bossLabel, "RIGHT", 5, 0)
    bossButton:SetSize(150, 30)
    UIDropDownMenu_SetWidth(bossButton, 140)
    UIDropDownMenu_Initialize(bossButton, function()
        local bosses = UI.GetUniqueBosses()
        UIDropDownMenu_AddButton({ text = "全部", value = "全部", func = function()
            UIDropDownMenu_SetSelectedValue(bossButton, "全部")
            currentFilters.boss = "全部"
            UI.Refresh()
        end })
        for _, boss in ipairs(bosses) do
            UIDropDownMenu_AddButton({ text = boss, value = boss, func = function()
                UIDropDownMenu_SetSelectedValue(bossButton, boss)
                currentFilters.boss = boss
                UI.Refresh()
            end })
        end
    end)
    UIDropDownMenu_SetSelectedValue(bossButton, "全部")
    UI.BossFilterButton = bossButton

    -- Player filter
    local playerLabel = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playerLabel:SetPoint("LEFT", bossButton, "RIGHT", 20, 0)
    playerLabel:SetText("玩家:")

    local playerButton = CreateFrame("Button", nil, filterFrame, "UIDropDownMenuTemplate")
    playerButton:SetPoint("LEFT", playerLabel, "RIGHT", 5, 0)
    playerButton:SetSize(150, 30)
    UIDropDownMenu_SetWidth(playerButton, 140)
    UIDropDownMenu_Initialize(playerButton, function()
        local players = UI.GetUniquePlayers()
        UIDropDownMenu_AddButton({ text = "全部", value = "全部", func = function()
            UIDropDownMenu_SetSelectedValue(playerButton, "全部")
            currentFilters.player = "全部"
            UI.Refresh()
        end })
        for _, player in ipairs(players) do
            UIDropDownMenu_AddButton({ text = player, value = player, func = function()
                UIDropDownMenu_SetSelectedValue(playerButton, player)
                currentFilters.player = player
                UI.Refresh()
            end })
        end
    end)
    UIDropDownMenu_SetSelectedValue(playerButton, "全部")
    UI.PlayerFilterButton = playerButton

    -- Clear filters button
    local clearButton = CreateFrame("Button", nil, filterFrame, "UIPanelButtonTemplate")
    clearButton:SetPoint("RIGHT", filterFrame, "RIGHT", 0, 0)
    clearButton:SetSize(80, 25)
    clearButton:SetText("清除筛选")
    clearButton:SetScript("OnClick", function()
        currentFilters = {
            raidInstance = "全部",
            boss = "全部",
            player = "全部",
            date = "全部"
        }
        UIDropDownMenu_SetSelectedValue(UI.RaidFilterButton, "全部")
        UIDropDownMenu_SetSelectedValue(UI.BossFilterButton, "全部")
        UIDropDownMenu_SetSelectedValue(UI.PlayerFilterButton, "全部")
        UI.Refresh()
    end)

    UI.FilterFrame = filterFrame
end

-- Create data table
local function CreateDataTable(frame)
    local tableFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    tableFrame:SetSize(878, 480)
    tableFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 11, -80)

    -- Table background
    tableFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    tableFrame:SetBackdropColor(0, 0, 0, 0.8)
    tableFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, tableFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", tableFrame, "TOPLEFT", 5, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", tableFrame, "BOTTOMRIGHT", -25, 5)

    -- Content frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(850, 1)
    scrollFrame:SetScrollChild(content)
    UI.TableContent = content

    -- Column headers
    local headers = {
        { text = "#", width = 40, column = "id" },
        { text = "BOSS", width = 150, column = "bossName" },
        { text = "物品", width = 200, column = "itemLink" },
        { text = "玩家", width = 150, column = "playerName" },
        { text = "职业", width = 80, column = "classFileName" },
        { text = "方式", width = 80, column = "distributionMethod" },
        { text = "时间", width = 150, column = "timestamp" }
    }

    local xOffset = 5
    for _, header in ipairs(headers) do
        local headerButton = CreateFrame("Button", nil, tableFrame)
        headerButton:SetSize(header.width, 25)
        headerButton:SetPoint("TOPLEFT", tableFrame, "TOPLEFT", xOffset, -5)
        headerButton.column = header.column
        headerButton.baseText = header.text
        headerButton:SetScript("OnClick", function()
            if currentSort.column == header.column then
                currentSort.ascending = not currentSort.ascending
            else
                currentSort.column = header.column
                currentSort.ascending = true
            end
            UI.Refresh()
        end)

        local headerText = headerButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerText:SetPoint("CENTER", headerButton, "CENTER", 0, 0)
        headerText:SetText(header.text)
        headerButton.text = headerText

        local headerHighlight = headerButton:CreateTexture(nil, "HIGHLIGHT")
        headerHighlight:SetAllPoints(headerButton)
        headerHighlight:SetColorTexture(0.2, 0.2, 0.2, 0.5)

        table.insert(UI.HeaderButtons, headerButton)
        xOffset = xOffset + header.width
    end

    UI.TableFrame = tableFrame
    UI.ScrollFrame = scrollFrame
end

-- Create action buttons
local function CreateActionButtons(frame)
    local buttonFrame = CreateFrame("Frame", nil, frame)
    buttonFrame:SetSize(878, 35)
    buttonFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 11, 10)

    -- Export button
    local exportButton = CreateFrame("Button", nil, buttonFrame, "UIPanelButtonTemplate")
    exportButton:SetPoint("LEFT", buttonFrame, "LEFT", 0, 0)
    exportButton:SetSize(120, 30)
    exportButton:SetText("导出数据")
    exportButton:SetScript("OnClick", function()
        if BLT.Export and BLT.Export.ShowDialog then
            BLT.Export.ShowDialog()
        end
    end)

    -- Refresh button
    local refreshButton = CreateFrame("Button", nil, buttonFrame, "UIPanelButtonTemplate")
    refreshButton:SetPoint("LEFT", exportButton, "RIGHT", 10, 0)
    refreshButton:SetSize(120, 30)
    refreshButton:SetText("刷新")
    refreshButton:SetScript("OnClick", function()
        UI.Refresh()
    end)

    -- Clear button
    local clearButton = CreateFrame("Button", nil, buttonFrame, "UIPanelButtonTemplate")
    clearButton:SetPoint("RIGHT", buttonFrame, "RIGHT", 0, 0)
    clearButton:SetSize(120, 30)
    clearButton:SetText("清空记录")
    clearButton:SetScript("OnClick", function()
        StaticPopup_Show("BOSSLOOTTRACKER_CLEAR_CONFIRM")
    end)

    -- Status text
    local statusText = buttonFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("CENTER", buttonFrame, "CENTER", 0, 0)
    UI.StatusText = statusText

    UI.ButtonFrame = buttonFrame
end

-- Create edit mode UI
local function CreateEditModeUI()
    local editFrame = CreateFrame("Frame", "BossLootTrackerEditFrame", UIParent, "BackdropTemplate")
    editFrame:SetSize(400, 200)
    editFrame:SetClampedToScreen(true)
    editFrame:SetMovable(true)
    editFrame:EnableMouse(true)
    editFrame:RegisterForDrag("LeftButton")
    editFrame:SetScript("OnDragStart", editFrame.StartMoving)
    editFrame:SetScript("OnDragStop", editFrame.StopMovingOrSizing)
    editFrame:Hide()

    editFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    -- Title
    local title = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", editFrame, "TOP", 0, -15)
    title:SetText("编辑记录")

    -- Player name field
    local playerLabel = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playerLabel:SetPoint("TOPLEFT", editFrame, "TOPLEFT", 20, -50)
    playerLabel:SetText("玩家姓名:")

    local playerEdit = CreateFrame("EditBox", nil, editFrame, "InputBoxTemplate")
    playerEdit:SetSize(200, 30)
    playerEdit:SetPoint("TOPLEFT", playerLabel, "BOTTOMLEFT", 0, -5)
    playerEdit:SetAutoFocus(false)
    UI.PlayerEdit = playerEdit

    -- Distribution method dropdown
    local methodLabel = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    methodLabel:SetPoint("TOPLEFT", playerEdit, "BOTTOMLEFT", 0, -20)
    methodLabel:SetText("分配方式:")

    local methodButton = CreateFrame("Button", nil, editFrame, "UIDropDownMenuTemplate")
    methodButton:SetPoint("TOPLEFT", methodLabel, "BOTTOMLEFT", 0, 0)
    methodButton:SetSize(150, 30)
    UIDropDownMenu_SetWidth(methodButton, 140)
    UIDropDownMenu_Initialize(methodButton, function()
        local methods = { "需求", "贪婪", "幻化", "未知" }
        for _, method in ipairs(methods) do
            UIDropDownMenu_AddButton({ text = method, value = method, func = function()
                UIDropDownMenu_SetSelectedValue(methodButton, method)
            end })
        end
    end)
    UIDropDownMenu_SetSelectedValue(methodButton, "需求")
    UI.MethodButton = methodButton

    -- Save button
    local saveButton = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
    saveButton:SetPoint("BOTTOMLEFT", editFrame, "BOTTOMLEFT", 30, 20)
    saveButton:SetSize(120, 30)
    saveButton:SetText("保存")
    saveButton:SetScript("OnClick", function()
        UI.SaveEdit()
    end)

    -- Cancel button
    local cancelButton = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
    cancelButton:SetPoint("BOTTOMRIGHT", editFrame, "BOTTOMRIGHT", -30, 20)
    cancelButton:SetSize(120, 30)
    cancelButton:SetText("取消")
    cancelButton:SetScript("OnClick", function()
        editFrame:Hide()
        editMode.active = false
    end)

    UI.EditFrame = editFrame
end

-- Helper: Get unique raid instances
function UI.GetUniqueRaids()
    local raids = {}
    local seen = {}

    for _, record in ipairs(BLT.DB.lootRecords) do
        if not seen[record.raidName] then
            table.insert(raids, record.raidName)
            seen[record.raidName] = true
        end
    end

    table.sort(raids)
    return raids
end

-- Helper: Get unique bosses
function UI.GetUniqueBosses()
    local bosses = {}
    local seen = {}

    for _, record in ipairs(BLT.DB.lootRecords) do
        if not seen[record.bossName] then
            table.insert(bosses, record.bossName)
            seen[record.bossName] = true
        end
    end

    table.sort(bosses)
    return bosses
end

-- Helper: Get unique players
function UI.GetUniquePlayers()
    local players = {}
    local seen = {}

    for _, record in ipairs(BLT.DB.lootRecords) do
        if not seen[record.playerName] then
            table.insert(players, record.playerName)
            seen[record.playerName] = true
        end
    end

    table.sort(players)
    return players
end

-- Filter and sort records
function UI.FilterAndSortRecords()
    filteredRecords = {}

    for _, record in ipairs(BLT.DB.lootRecords) do
        -- Apply filters
        local skip = false
        if currentFilters.raidInstance ~= "全部" and record.raidName ~= currentFilters.raidInstance then
            skip = true
        elseif currentFilters.boss ~= "全部" and record.bossName ~= currentFilters.boss then
            skip = true
        elseif currentFilters.player ~= "全部" and record.playerName ~= currentFilters.player then
            skip = true
        end

        if not skip then
            table.insert(filteredRecords, record)
        end
    end

    -- Sort records
    table.sort(filteredRecords, function(a, b)
        local aValue = a[currentSort.column]
        local bValue = b[currentSort.column]

        if currentSort.ascending then
            return aValue < bValue
        else
            return aValue > bValue
        end
    end)
end

-- Create table row
local function CreateTableRow(index, record)
    local row = CreateFrame("Button", nil, UI.TableContent, "BackdropTemplate")
    row:SetSize(850, 25)
    row:SetPoint("TOPLEFT", UI.TableContent, "TOPLEFT", 0, -(index - 1) * 25)

    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    end)

    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
    end)

    row:SetScript("OnDoubleClick", function()
        UI.StartEdit(record)
    end)

    row:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "",
        tile = true,
        tileSize = 0,
        edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    row:SetBackdropColor(0, 0, 0, 0)

    -- Row data
    local columns = {
        { text = tostring(index), width = 40, align = "CENTER" },
        { text = record.bossName, width = 150, align = "LEFT" },
        { text = record.itemLink or "item:" .. record.itemID, width = 200, align = "LEFT", isLink = true },
        { text = record.playerName, width = 150, align = "LEFT" },
        { text = BLT.GetClassColor(record.classFileName) .. record.classFileName .. "|r", width = 80, align = "CENTER" },
        { text = record.distributionMethod, width = 80, align = "CENTER" },
        { text = BLT.FormatTimestamp(record.timestamp), width = 150, align = "LEFT" }
    }

    local xOffset = 5
    for _, col in ipairs(columns) do
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("TOPLEFT", row, "TOPLEFT", xOffset, 0)

        if col.align == "CENTER" then
            text:SetPoint("CENTER", row, "TOPLEFT", xOffset + col.width / 2, 0)
        end

        if col.isLink and record.itemLink then
            -- Make item link clickable
            local itemButton = CreateFrame("Button", nil, row)
            itemButton:SetSize(col.width, 25)
            itemButton:SetPoint("TOPLEFT", row, "TOPLEFT", xOffset, 0)
            itemButton:SetScript("OnEnter", function()
                GameTooltip:SetOwner(itemButton, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(record.itemLink)
                GameTooltip:Show()
            end)
            itemButton:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            itemButton:SetScript("OnClick", function()
                if IsShiftKeyDown() then
                    ChatEdit_InsertLink(record.itemLink)
                end
            end)

            local highlight = itemButton:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints(itemButton)
            highlight:SetColorTexture(1, 1, 1, 0.2)
        end

        text:SetText(col.text)
        xOffset = xOffset + col.width
    end

    return row
end

-- Refresh the table
function UI.Refresh()
    UI.FilterAndSortRecords()

    -- Clear existing rows
    for _, child in pairs({ UI.TableContent:GetChildren() }) do
        child:Hide()
    end

    -- Update filter dropdowns
    UI.UpdateFilterDropdowns()

    -- Update header sorting indicators
    for _, headerButton in ipairs(UI.HeaderButtons) do
        local text = headerButton.baseText
        if currentSort.column == headerButton.column then
            text = text .. (currentSort.ascending and " ▲" or " ▼")
        end
        headerButton.text:SetText(text)
    end

    -- Create new rows
    for i, record in ipairs(filteredRecords) do
        CreateTableRow(i, record)
    end

    -- Update status text
    UI.StatusText:SetText(string.format("共 %d 条记录", #filteredRecords))

    -- Adjust content height
    UI.TableContent:SetHeight(math.max(1, #filteredRecords * 25))
end

-- Update filter dropdowns
function UI.UpdateFilterDropdowns()
    -- These will be regenerated on next open
end

-- Start editing a record
function UI.StartEdit(record)
    editMode.active = true
    editMode.recordId = record.id
    editMode.originalData = record

    UI.PlayerEdit:SetText(record.playerName)
    UIDropDownMenu_SetSelectedValue(UI.MethodButton, record.distributionMethod)

    UI.EditFrame:Show()
end

-- Save edit
function UI.SaveEdit()
    if not editMode.active then
        return
    end

    local playerName = UI.PlayerEdit:GetText()
    local method = UIDropDownMenu_GetSelectedValue(UI.MethodButton)

    if playerName and playerName ~= "" then
        -- Find and update the record
        for _, record in ipairs(BLT.DB.lootRecords) do
            if record.id == editMode.recordId then
                record.playerName = playerName
                record.distributionMethod = method
                break
            end
        end

        UI.Refresh()
        UI.EditFrame:Hide()
        editMode.active = false
    else
        print("|cffFF0000[BossLootTracker]|r 玩家姓名不能为空")
    end
end

-- Show the main window
function UI.Show()
    print("BLT Show called, MainFrame=" .. tostring(UI.MainFrame ~= nil) .. " shown=" .. tostring(UI.MainFrame and UI.MainFrame:IsShown()))
    if not UI.MainFrame then
        UI.Initialize()
    end

    UI.MainFrame:Show()
    UI.Refresh()
end

-- Hide the main window
function UI.Hide()
    if UI.MainFrame then
        UI.MainFrame:Hide()
    end
end

-- Toggle the main window
function UI.Toggle()
    if UI.MainFrame and UI.MainFrame:IsShown() then
        UI.Hide()
    else
        UI.Show()
    end
end

-- Create minimap button (must be defined before UI.Initialize calls it)
local function CreateMinimapButton()
    local button = CreateFrame("Button", "BossLootTrackerMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)

    -- Create icon
    local icon = button:CreateTexture()
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01") -- Using a simple coin icon as placeholder

    -- Create highlight
    local highlight = button:CreateTexture()
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Minimap\\MiniMap-ButtonBorder")
    highlight:Hide()

    button:SetHighlightTexture(highlight)

    -- Position the button
    local function UpdatePosition()
        local angle = BossLootTrackerDB.settings.minimap.position
        local radius = 78
        local x = math.cos(angle) * radius
        local y = math.sin(angle) * radius
        button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    -- Make draggable - Buttons need RegisterForDrag to be draggable
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Calculate new position angle
        local mx, my = Minimap:GetCenter()
        local bx, by = self:GetCenter()
        local angle = math.atan2(by - my, bx - mx)
        BossLootTrackerDB.settings.minimap.position = angle
        UpdatePosition()
    end)

    -- Left click to toggle main window (OnClick still works for clicks)
    button:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            UI.Toggle()
        elseif button == "RightButton" then
            -- Show dropdown menu
            EasyMenu({
                { text = "导出数据", func = function()
                    if BLT.Export and BLT.Export.ShowDialog then
                        BLT.Export.ShowDialog()
                    end
                end },
                { text = "清空记录", func = function()
                    StaticPopup_Show("BOSSLOOTTRACKER_CLEAR_CONFIRM")
                end },
                { text = "关闭", func = function()
                    UI.Hide()
                end }
            }, self, 0, 0, "MENU", 2)
        end
    end)

    -- Tooltip on hover
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("BossLootTracker")
        GameTooltip:AddLine("左键: 打开/关闭主窗口", 1, 1, 1, true)
        GameTooltip:AddLine("右键: 显示菜单", 1, 1, 1, true)
        GameTooltip:AddLine("拖动: 调整小地图位置", 1, 1, 1, true)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Set initial position
    UpdatePosition()

    minimapButton = button
    UI.MinimapButton = button
end

-- Initialize UI
function UI.Initialize()
    DB = BossLootTrackerDB

    if not UI.MainFrame then
        local ok, err = pcall(CreateMainFrame)
        if not ok then print("BLT Error CreateMainFrame: " .. tostring(err)) end
        ok, err = pcall(function() CreateFilters(UI.MainFrame) end)
        if not ok then print("BLT Error CreateFilters: " .. tostring(err)) end
        ok, err = pcall(function() CreateDataTable(UI.MainFrame) end)
        if not ok then print("BLT Error CreateDataTable: " .. tostring(err)) end
        ok, err = pcall(function() CreateActionButtons(UI.MainFrame) end)
        if not ok then print("BLT Error CreateActionButtons: " .. tostring(err)) end
        ok, err = pcall(CreateEditModeUI)
        if not ok then print("BLT Error CreateEditModeUI: " .. tostring(err)) end
        ok, err = pcall(CreateMinimapButton)
        if not ok then print("BLT Error CreateMinimapButton: " .. tostring(err)) end
        print("|cff00FF00[BossLootTracker]|r UI initialized, MainFrame=" .. tostring(UI.MainFrame ~= nil))
    end
end

-- Slash command is registered in main lua file via SlashCmdList
-- UI.Initialize is called from there
