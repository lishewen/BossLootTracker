-- BossLootTracker - Export Module
-- Handles data export functionality (JSON / CSV / Lua Table)

local AddonName, BLT = ...

-- Export namespace
BLT.Export = {}

local Export = BLT.Export

---------------------------------------------------------------------------
-- Export dialog
---------------------------------------------------------------------------

local function CreateExportDialog()
    local frame = CreateFrame("Frame", "BossLootTrackerExportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(750, 520)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", frame, "TOP", 0, -15)
    title:SetText("导出数据")

    -- Format selector
    local formatLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    formatLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 25, -45)
    formatLabel:SetText("导出格式:")

    local formatDropdown = CreateFrame("Button", nil, frame, "UIDropDownMenuTemplate")
    formatDropdown:SetPoint("LEFT", formatLabel, "RIGHT", -15, 0)
    UIDropDownMenu_SetWidth(formatDropdown, 130)
    UIDropDownMenu_Initialize(formatDropdown, function()
        local formats = {
            { text = "CSV (推荐)", value = "csv" },
            { text = "JSON",       value = "json" },
            { text = "Lua Table",  value = "lua" },
        }
        for _, f in ipairs(formats) do
            UIDropDownMenu_AddButton({
                text = f.text,
                value = f.value,
                func = function()
                    UIDropDownMenu_SetSelectedValue(formatDropdown, f.value)
                    -- Regenerate on format change
                    Export._RefreshContent(formatDropdown)
                end,
            })
        end
    end)
    UIDropDownMenu_SetSelectedValue(formatDropdown, "csv")
    Export._FormatDropdown = formatDropdown

    -- Description
    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", frame, "TOPLEFT", 25, -72)
    desc:SetText("全选文本后 Ctrl+C 复制，或点击下方按钮重新生成。")

    -- Scroll frame + EditBox
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -90)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -35, 60)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetSize(680, 360)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("GameFontNormalSmall")
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    scrollFrame:SetScrollChild(editBox)
    Export._EditBox = editBox

    -- Select All button
    local selectBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 20)
    selectBtn:SetSize(130, 30)
    selectBtn:SetText("全选并复制")
    selectBtn:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
        print("|cff00FF00[BossLootTracker]|r 文本已全选，请按 Ctrl+C 复制")
    end)

    -- Regenerate button
    local regenBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    regenBtn:SetPoint("LEFT", selectBtn, "RIGHT", 10, 0)
    regenBtn:SetSize(100, 30)
    regenBtn:SetText("重新生成")
    regenBtn:SetScript("OnClick", function()
        Export._RefreshContent(formatDropdown)
    end)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 20)
    closeBtn:SetSize(100, 30)
    closeBtn:SetText("关闭")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- X button
    local closeX = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    closeX:SetScript("OnClick", function() frame:Hide() end)

    BLT.UI.ExportFrame = frame
end

---------------------------------------------------------------------------
-- Internal: refresh export content based on selected format
---------------------------------------------------------------------------

function Export._RefreshContent(dropdown)
    local format = UIDropDownMenu_GetSelectedValue(dropdown) or "csv"
    local text
    if format == "json" then
        text = Export.GenerateJSON()
    elseif format == "lua" then
        text = Export.GenerateLua()
    else
        text = Export.GenerateCSV()
    end
    Export._EditBox:SetText(text)
end

---------------------------------------------------------------------------
-- CSV export
---------------------------------------------------------------------------

function Export.GenerateCSV()
    local lines = {}
    table.insert(lines, "序号,BOSS,团队副本,难度,物品ID,物品,数量,玩家,职业,分配方式,时间")

    for i, r in ipairs(BLT.DB.lootRecords) do
        -- Strip color codes from itemLink for CSV
        local cleanName = r.itemLink or ("item:" .. tostring(r.itemID))
        cleanName = cleanName:gsub("|c%x%x%x%x%x%x%x%x", "")
        cleanName = cleanName:gsub("|r", "")
        cleanName = cleanName:gsub("|H.-|h", "")
        cleanName = cleanName:gsub("|h", "")

        local line = string.format('%d,"%s","%s","%s",%d,"%s",%d,"%s","%s","%s","%s"',
            i,
            r.bossName or "",
            r.raidName or "",
            r.difficulty or "",
            r.itemID or 0,
            cleanName,
            r.quantity or 1,
            r.playerName or "",
            r.classFileName or "",
            r.distributionMethod or "",
            BLT.FormatTimestamp(r.timestamp)
        )
        table.insert(lines, line)
    end

    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- JSON export (plain text, NOT base64)
---------------------------------------------------------------------------

function Export.GenerateJSON()
    local parts = {}
    table.insert(parts, '{')
    table.insert(parts, '  "version": "' .. (BLT.Version or "1.0.0") .. '",')
    table.insert(parts, '  "exportDate": "' .. date("%Y-%m-%d %H:%M:%S") .. '",')
    table.insert(parts, '  "totalRecords": ' .. #BLT.DB.lootRecords .. ',')
    table.insert(parts, '  "records": [')

    for i, r in ipairs(BLT.DB.lootRecords) do
        local comma = i < #BLT.DB.lootRecords and "," or ""
        local cleanLink = (r.itemLink or ""):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
        local line = string.format(
            '    {"id":%d,"bossName":"%s","raidName":"%s","difficulty":"%s","itemID":%d,"itemLink":"%s","quantity":%d,"playerName":"%s","classFileName":"%s","distributionMethod":"%s","timestamp":"%s"}%s',
            i,
            r.bossName or "",
            r.raidName or "",
            r.difficulty or "",
            r.itemID or 0,
            cleanLink,
            r.quantity or 1,
            r.playerName or "",
            r.classFileName or "",
            r.distributionMethod or "",
            BLT.FormatTimestamp(r.timestamp),
            comma
        )
        table.insert(parts, line)
    end

    table.insert(parts, '  ]')
    table.insert(parts, '}')

    return table.concat(parts, "\n")
end

---------------------------------------------------------------------------
-- Lua table export
---------------------------------------------------------------------------

function Export.GenerateLua()
    local lines = {}
    table.insert(lines, "-- BossLootTracker Export")
    table.insert(lines, "-- " .. date("%Y-%m-%d %H:%M:%S"))
    table.insert(lines, "BossLootTrackerDB_Import = {")
    table.insert(lines, "  lootRecords = {")

    for i, r in ipairs(BLT.DB.lootRecords) do
        local cleanLink = (r.itemLink or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
        local line = string.format(
            '    {id=%d, bossName=[[%s]], raidName=[[%s]], difficulty=[[%s]], itemID=%d, itemLink=[[%s]], quantity=%d, playerName=[[%s]], classFileName=[[%s]], distributionMethod=[[%s]], timestamp=%d},',
            i,
            r.bossName or "",
            r.raidName or "",
            r.difficulty or "",
            r.itemID or 0,
            cleanLink,
            r.quantity or 1,
            r.playerName or "",
            r.classFileName or "",
            r.distributionMethod or "",
            r.timestamp or 0
        )
        table.insert(lines, line)
    end

    table.insert(lines, "  },")
    table.insert(lines, "}")

    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Show dialog (called by main UI / slash command)
---------------------------------------------------------------------------

function Export.ShowDialog()
    if not BLT.UI.ExportFrame then
        CreateExportDialog()
    end

    -- Generate content based on current format selection
    Export._RefreshContent(Export._FormatDropdown)

    BLT.UI.ExportFrame:Show()
    Export._EditBox:SetFocus()
    Export._EditBox:HighlightText()
end

---------------------------------------------------------------------------
-- Legacy / backward compat
---------------------------------------------------------------------------

-- Keep GenerateExportData as JSON for anything that still calls it
function Export.GenerateExportData()
    return Export.GenerateJSON()
end

function Export.TableToJson(tbl)
    -- Minimal serializer kept for backward compat
    local function ser(val)
        local t = type(val)
        if t == "table" then
            local items = {}
            for k, v in pairs(val) do
                local key = type(k) == "string" and '"' .. k .. '"' or tostring(k)
                table.insert(items, key .. ":" .. ser(v))
            end
            return "{" .. table.concat(items, ",") .. "}"
        elseif t == "string" then
            local s = val:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
            return '"' .. s .. '"'
        elseif t == "number" or t == "boolean" then
            return tostring(val)
        else
            return "null"
        end
    end
    return ser(tbl)
end
