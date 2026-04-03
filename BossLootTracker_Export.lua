-- BossLootTracker - Export Module
-- Handles data export functionality

local AddonName, BLT = ...

-- Export namespace
BLT.Export = {}

local Export = BLT.Export

-- Create export dialog
local function CreateExportDialog()
    local frame = CreateFrame("Frame", "BossLootTrackerExportFrame", UIParent)
    frame:SetSize(700, 500)
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

    -- Description
    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOP", frame, "TOP", 0, -45)
    desc:SetText("下面的Base64编码字符串包含了所有战利品记录数据。|n您可以复制并保存此数据用于备份或分享。")

    -- Scroll frame for export text
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -75)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -35, 60)

    -- Edit box for export data
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetSize(645, 350)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("GameFontNormalSmall")
    editBox:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    scrollFrame:SetScrollChild(editBox)
    BLT.UI.ExportEditBox = editBox

    -- Copy button
    local copyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    copyButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 20)
    copyButton:SetSize(120, 30)
    copyButton:SetText("复制到剪贴板")
    copyButton:SetScript("OnClick", function()
        local text = editBox:GetText()
        if text and text ~= "" then
            -- Try to copy to clipboard
            if C_Clipboard then
                C_Clipboard.SetClipboardText(text)
                print("|cff00FF00[BossLootTracker]|r 已复制到剪贴板")
            else
                -- Fallback: select all text so user can manually copy
                editBox:HighlightText()
                print("|cff00FF00[BossLootTracker]|r 请使用 Ctrl+C 手动复制")
            end
        end
    end)

    -- Close button
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 20)
    closeButton:SetSize(120, 30)
    closeButton:SetText("关闭")
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- Close button (X)
    local closeX = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    closeX:SetScript("OnClick", function()
        frame:Hide()
    end)

    BLT.UI.ExportFrame = frame
end

-- Encode data to Base64 (standard implementation)
local function Base64Encode(data)
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local result = {}

    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local triplet = 0

        if a then triplet = triplet + a * 65536 end
        if b then triplet = triplet + b * 256 end
        if c then triplet = triplet + c end

        local index1 = (triplet >> 18) & 0x3F
        local index2 = (triplet >> 12) & 0x3F
        local index3 = (triplet >> 6) & 0x3F
        local index4 = triplet & 0x3F

        table.insert(result, b64chars:sub(index1 + 1, index1 + 1))
        table.insert(result, b64chars:sub(index2 + 1, index2 + 1))

        if b then
            table.insert(result, b64chars:sub(index3 + 1, index3 + 1))
        else
            table.insert(result, "=")
        end

        if c then
            table.insert(result, b64chars:sub(index4 + 1, index4 + 1))
        else
            table.insert(result, "=")
        end
    end

    return table.concat(result)
end

-- Generate export data
function Export.GenerateExportData()
    local exportData = {
        version = BLT.Version or "1.0.0",
        exportDate = date("%Y-%m-%d %H:%M:%S"),
        serverRegion = GetCurrentRegion() or "Unknown",
        serverRealm = GetRealmName() or "Unknown",
        totalRecords = #BLT.DB.lootRecords,
        records = BLT.DB.lootRecords
    }

    -- Convert to JSON string (simple implementation)
    local jsonString = Export.TableToJson(exportData)

    -- Encode to Base64
    local base64String = Base64Encode(jsonString)

    return base64String
end

-- Simple table to JSON converter
function Export.TableToJson(tbl)
    local result = {}

    local function serialize(val)
        local t = type(val)
        if t == "table" then
            local items = {}
            for k, v in pairs(val) do
                local key = type(k) == "string" and '"' .. k .. '"' or tostring(k)
                table.insert(items, key .. ":" .. serialize(v))
            end
            return "{" .. table.concat(items, ",") .. "}"
        elseif t == "string" then
            return '"' .. val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
        elseif t == "number" or t == "boolean" then
            return tostring(val)
        else
            return "null"
        end
    end

    return serialize(tbl)
end

-- Show export dialog
function Export.ShowDialog()
    if not BLT.UI.ExportFrame then
        CreateExportDialog()
    end

    -- Generate export data
    local exportString = Export.GenerateExportData()
    BLT.UI.ExportEditBox:SetText(exportString)

    -- Show the dialog
    BLT.UI.ExportFrame:Show()
end

-- Import data (for future use)
function Export.ImportData(base64String)
    -- Base64 decode
    local jsonString = Export.Base64Decode(base64String)

    -- Parse JSON (would need a JSON parser)
    -- For now, just return the string
    return jsonString
end

-- Base64 decode (standard implementation)
local function Base64Decode(data)
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local charMap = {}
    for i = 1, #b64chars do
        charMap[b64chars:sub(i, i)] = i - 1
    end

    -- Remove any characters that aren't valid Base64
    data = data:gsub('[^'..b64chars..'=]', '')

    local result = {}
    local paddingCount = 0

    -- Count padding characters
    for i = #data, 1, -1 do
        if data:sub(i, i) == '=' then
            paddingCount = paddingCount + 1
        else
            break
        end
    end

    for i = 1, #data, 4 do
        local chars = { data:byte(i, i + 3) }

        local indices = {}
        for j = 1, 4 do
            local char = data:sub(i + j - 1, i + j - 1)
            if char ~= '=' then
                indices[j] = charMap[char]
            else
                indices[j] = 0
            end
        end

        local triplet = (indices[1] << 18) + (indices[2] << 12) + (indices[3] << 6) + indices[4]

        local byte1 = (triplet >> 16) & 0xFF
        local byte2 = (triplet >> 8) & 0xFF
        local byte3 = triplet & 0xFF

        table.insert(result, string.char(byte1))

        if paddingCount < 2 then
            table.insert(result, string.char(byte2))
        end

        if paddingCount < 1 then
            table.insert(result, string.char(byte3))
        end
    end

    return table.concat(result)
end

Export.Base64Decode = Base64Decode

-- Export to file (for future use)
function Export.ExportToFile(filename)
    local exportData = Export.GenerateExportData()

    -- This would require file system access which WoW doesn't provide directly
    -- Users would need to copy the data and save it manually
    print("|cff00FF00[BossLootTracker]|r 请使用导出对话框复制数据并手动保存到文件")
end

-- Initialize export module
function Export.Initialize()
    -- Initialization if needed
end
