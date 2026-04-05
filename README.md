# BossLootTracker

一个魔兽世界插件，自动记录副本 BOSS 的战利品掉落，支持 5 人本和团本。

## 功能

- **自动记录** — 击杀 BOSS 后自动记录所有掉落物品和获得者
- **5人本 + 团本** — 同时支持 ENCOUNTER_LOOT_RECEIVED 和 CHAT_MSG_LOOT 事件，覆盖所有副本场景
- **去重机制** — 双事件源自动去重，不会重复记录同一条掉落
- **筛选排序** — 按副本、BOSS、玩家筛选，点击列头排序
- **物品 Tooltip** — 鼠标悬停物品列显示物品详情
- **记录编辑** — 每行编辑按钮，可修改玩家姓名和分配方式
- **数据导出** — 支持 CSV / JSON / Lua Table 三种格式导出
- **小地图按钮** — 左键打开主窗口，右键弹出菜单

## 安装

1. 下载最新 Release 或克隆本仓库
2. 将 `BossLootTracker` 文件夹复制到 `Interface\AddOns\` 目录
3. 重启游戏或 `/reload`

## 使用

| 命令 | 说明 |
|------|------|
| `/blt` | 打开/关闭主窗口 |
| `/blt show` | 显示主窗口 |
| `/blt hide` | 隐藏主窗口 |
| `/blt clear` | 清空所有记录 |
| `/blt export` | 导出数据 |

### 编辑记录

点击每行末尾的「编辑」按钮，可修改玩家姓名和分配方式（需求/贪婪/幻化/未知）。

### 导出数据

支持三种导出格式：
- **CSV** — 推荐用于 Excel 分析
- **JSON** — 通用数据交换格式
- **Lua Table** — 可直接用于 WoW 插件导入

导出窗口中全选文本后 Ctrl+C 复制即可。

## 技术细节

### 事件监听

| 事件 | 用途 |
|------|------|
| `BOSS_KILL` | 捕获 BOSS 击杀，记录 encounterID 和名称 |
| `ENCOUNTER_LOOT_RECEIVED` | 记录 5 人本和部分团本的掉落 |
| `CHAT_MSG_LOOT` | 记录团本中通过 ML/PL 分配的掉落 |

团本使用「大师分配」或「个人战利品」模式时，掉落信息通过聊天频道消息获取。插件同时监听两个事件，用 `encounterID + itemID + playerName` 组合键去重。

### 数据结构

每条记录包含以下字段：

```lua
{
    id = 1,                    -- 记录序号
    timestamp = 1712300000,    -- Unix 时间戳
    encounterID = 2521,        -- BOSS 遭遇战 ID
    bossName = "乌鲁洛克",      -- BOSS 名称
    raidName = "奥妮克希亚巢穴", -- 副本名称
    difficulty = "英雄",        -- 难度
    itemID = 19019,            -- 物品 ID
    itemLink = "|cffa335ee|H...", -- 物品链接（含颜色码）
    quantity = 1,              -- 数量
    playerName = "算神",        -- 获得者
    classFileName = "WARRIOR", -- 职业
    distributionMethod = "需求" -- 分配方式
}
```

## 版本历史

### 2.0.0 (2026-04-05)

- 新增 CHAT_MSG_LOOT 监听，支持团本掉落记录
- 双事件源去重机制
- 编辑按钮替代双击方案
- 编辑/导出窗口 DIALOG 层级，不被主窗口遮挡
- 行高亮 + 物品 Tooltip
- 移除职业列，界面更紧凑

### 1.0.0

- 初始版本
- 5 人本掉落记录
- CSV/JSON/Lua 导出

## 兼容性

- World of Warcraft: Midnight (12.0.1)
- Interface版本: 120001

## 许可证

MIT License
