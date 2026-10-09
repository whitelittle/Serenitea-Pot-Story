-- 16 网格背包：列表项回调、每项光标事件、拖拽幽灵和滚动位置。
-- 先读 docs/16_网格背包动态列表与拖拽配方.md，再把 CONFIG 换成当前工程值。
-- 这是可手写的练习模板；日志中的索引和图片 ID 不能直接复制。

local CONFIG = {
    GRID_NAME = "网格视窗",          -- 简体中文预设正式名；改名后只改这里
    ROOT_NAME = "容器节点",
    ITEM_PREFAB_INDEX = nil,       -- 已保存的列表项父模板索引
    DRAG_GHOST_PREFAB_INDEX = nil, -- 已保存的拖拽预览模板索引；没有就留 nil
    ITEM_IMAGE_NAME = "图片",
    ITEM_TEXT_NAME = "文本框",
    ITEM_AREA_NAME = "光标检测区域",
    IMAGE_SOURCE = Enum.ImageSource.Item,
    IMAGE_ID = nil,
    TEST_IMAGE_IDS = {},           -- 可选：填写多个已确认资产 ID，Q 会轮换选择
    CAPACITY = 12,
    MAX_CAPACITY = 48,
    CAPACITY_STEP = 4,
    REQUEST_SIGNAL_NAME = nil,     -- 有服务器节点图契约时填写
    USE_SIGNAL_NAME = nil,         -- 点击使用道具时的可选信号
    ENABLE_TEST_KEYS = true,       -- E=使用、Q=随机道具、R=扩容、T=重置
}

local state = "NEW"
local root, grid = nil, nil
local ghost = nil
local capacity = CONFIG.CAPACITY
local slots = {}
local selectedIndex = nil
local drag = nil
local savedScrollProgress = 0
local callbacksByControl = {}
local startupFrames = 0
local refreshSerial = 0

local testKeyCallbacks = {}
local testItemSerial = 0

local function alive(control)
    return control ~= nil and control.alive == true
end

local function log(message)
    print("[16][网格背包] " .. tostring(message))
end

local function fail(message)
    state = "FAILED"
    printerr("[16][网格背包] " .. tostring(message))
    pcall(function() script:EnableUpdate(false) end)
end

local function findRootAndGrid()
    local ok, foundRoot = pcall(function() return game.FindClientUIRoot(CONFIG.ROOT_NAME) end)
    if not ok or not alive(foundRoot) then return false end
    local okGrid, foundGrid = pcall(function() return foundRoot:GetChild(CONFIG.GRID_NAME) end)
    if not okGrid or not alive(foundGrid) then return false end
    root, grid = foundRoot, foundGrid
    return true
end

local function clearControlListeners(control)
    local old = callbacksByControl[control]
    if old == nil then return end
    if alive(old.area) then
        for i = 1, #old do
            pcall(function() old.area:RemoveCursorEventListener(old[i].eventType, old[i].callback) end)
        end
    end
    callbacksByControl[control] = nil
end

local function destroyGhost()
    if alive(ghost) then
        pcall(function() game.DestroyClientUIControl(ghost) end)
    end
    ghost, drag = nil, nil
end

local function sendRequest(sourceIndex, targetIndex)
    if CONFIG.REQUEST_SIGNAL_NAME == nil then return end
    local ok, signal = pcall(function() return game.ServerSignal(CONFIG.REQUEST_SIGNAL_NAME) end)
    if not ok or signal == nil then
        printerr("[16][网格背包] 无法创建服务器信号：" .. tostring(CONFIG.REQUEST_SIGNAL_NAME))
        return
    end
    local sent, err = pcall(function()
        signal:AddInt(sourceIndex)
        signal:AddInt(targetIndex)
        signal:SendSignal()
    end)
    if not sent then
        printerr("[16][网格背包] 发送信号失败：" .. tostring(err))
        return
    end
    log("已发送信号=" .. tostring(CONFIG.REQUEST_SIGNAL_NAME) .. " source=" .. tostring(sourceIndex) .. " target=" .. tostring(targetIndex))
end

local function sendUseRequest(index)
    if CONFIG.USE_SIGNAL_NAME == nil then return end
    local ok, signal = pcall(function() return game.ServerSignal(CONFIG.USE_SIGNAL_NAME) end)
    if not ok or signal == nil then return end
    local sent = pcall(function() signal:AddInt(index); signal:SendSignal() end)
    if sent then log("已发送使用信号=" .. tostring(CONFIG.USE_SIGNAL_NAME) .. " index=" .. tostring(index)) end
end

local function beginDrag(item, index, data)
    if CONFIG.DRAG_GHOST_PREFAB_INDEX == nil then return end
    if slots[index + 1] == nil then
        log("空槽位不创建拖拽预览；槽位=" .. tostring(index + 1))
        return
    end
    destroyGhost()
    local ok, created = pcall(function()
        return game.InstantiateClientUIControl(CONFIG.DRAG_GHOST_PREFAB_INDEX, root)
    end)
    if not ok or not alive(created) then
        printerr("[16][网格背包] 拖拽预览创建失败；请检查模板索引")
        return
    end
    ghost = created
    local sourceImage = item:GetChild(CONFIG.ITEM_IMAGE_NAME)
    local ghostImage = ghost
    if alive(ghost) and typeof(ghost) ~= "ClientUIImageControl" then
        ghostImage = ghost:GetChild(CONFIG.ITEM_IMAGE_NAME)
    end
    if alive(sourceImage) and alive(ghostImage) then
        pcall(function() ghostImage:SetImage(sourceImage.imageSource, sourceImage.imageId) end)
    end
    local ghostArea = alive(ghost) and ghost:GetChild(CONFIG.ITEM_AREA_NAME) or nil
    if alive(ghostArea) then ghostArea.raycastTarget = false end
    if data ~= nil and alive(ghost) then
        local x, y = data:GetUIPos()
        ghost:SetAnchoredPosition(x, y)
    end
    drag = { sourceIndex = index }
end

local function updateDrag(data)
    if not alive(ghost) or data == nil then return end
    local x, y = data:GetUIPos()
    ghost:SetAnchoredPosition(x, y)
end

local function finishDrag()
    if drag == nil then return end
    local sourceIndex, targetIndex = drag.sourceIndex, drag.targetIndex
    local shouldSwap = targetIndex ~= nil and targetIndex ~= sourceIndex
    drag.finished = true
    destroyGhost()
    if shouldSwap then
        slots[sourceIndex + 1], slots[targetIndex + 1] = slots[targetIndex + 1], slots[sourceIndex + 1]
        sendRequest(sourceIndex, targetIndex)
        refreshInventory(true)
    end
end

local function bindItem(item, callbackIndex)
    if not alive(item) then return 0 end
    clearControlListeners(item)
    local area = item:GetChild(CONFIG.ITEM_AREA_NAME)
    if not alive(area) then
        printerr("[16][网格背包] 列表项缺少直接子级：" .. CONFIG.ITEM_AREA_NAME)
        return 0
    end
    area.raycastTarget = true
    local okIndex, runtimeIndex = pcall(function() return grid:GetItemIndex(item) end)
    if not okIndex then runtimeIndex = callbackIndex end
    local records = {}
    local function add(eventType, callback)
        area:AddCursorEventListener(eventType, callback)
        records[#records + 1] = { eventType = eventType, callback = callback }
    end
    add(Enum.CursorEventType.CursorEnter, function()
        if drag ~= nil and drag.sourceIndex ~= runtimeIndex then drag.targetIndex = runtimeIndex end
        log("CursorEnter 槽位=" .. tostring(runtimeIndex + 1))
    end)
    add(Enum.CursorEventType.CursorExit, function()
        if drag ~= nil and drag.targetIndex == runtimeIndex then drag.targetIndex = nil end
        log("CursorExit 槽位=" .. tostring(runtimeIndex + 1))
    end)
    add(Enum.CursorEventType.CursorDown, function() selectedIndex = runtimeIndex end)
    add(Enum.CursorEventType.CursorUp, function() finishDrag() end)
    add(Enum.CursorEventType.CursorClick, function()
        selectedIndex = runtimeIndex
        sendUseRequest(runtimeIndex)
        log("CursorClick 槽位=" .. tostring(runtimeIndex + 1))
    end)
    add(Enum.CursorEventType.CursorBeginDrag, function(data) beginDrag(item, runtimeIndex, data) end)
    add(Enum.CursorEventType.CursorDrag, function(data) updateDrag(data) end)
    add(Enum.CursorEventType.CursorEndDrag, function() finishDrag() end)
    callbacksByControl[item] = { area = area }
    for i = 1, #records do callbacksByControl[item][i] = records[i] end
    local image = item:GetChild(CONFIG.ITEM_IMAGE_NAME)
    local text = item:GetChild(CONFIG.ITEM_TEXT_NAME)
    local slotImageId = slots[runtimeIndex + 1]
    if alive(image) then
        if slotImageId ~= nil then
            image:SetImage(CONFIG.IMAGE_SOURCE, slotImageId)
            image:SetVisible(true)
        else
            image:SetVisible(false)
        end
    end
    if alive(text) then text.text = "槽位 " .. tostring(runtimeIndex + 1) .. (slotImageId ~= nil and " / 有道具" or " / 空") end
    return #records
end

function refreshInventory(keepScroll)
    if state ~= "RUNNING" or not alive(grid) then return end
    if keepScroll then
        local ok, progress = pcall(function() return grid.scrollProgress end)
        if ok and type(progress) == "number" then savedScrollProgress = math.max(0, math.min(1, progress)) end
    end
    refreshSerial = refreshSerial + 1
    local serial = refreshSerial
    grid:RefreshItems(capacity, function(item, callbackIndex)
        if state ~= "RUNNING" or serial ~= refreshSerial then return end
        local count = bindItem(item, callbackIndex)
        log("列表项事件已注册；回调索引=" .. tostring(callbackIndex) .. " 注册数=" .. tostring(count))
    end)
    -- 若目标版本的 RefreshItems 回调异步完成，
    -- 应把下面的恢复移动到“本轮回调完成”分支，并继续检查 serial。
    if keepScroll and serial == refreshSerial then
        local ok, err = pcall(function() grid.scrollProgress = savedScrollProgress end)
        if ok then
            local readOk, readBack = pcall(function() return grid.scrollProgress end)
            log("刷新后恢复滚动进度；期望=" .. tostring(savedScrollProgress) .. " 读回=" .. tostring(readOk and readBack or "<读取失败>"))
        else
            printerr("[16][网格背包] 恢复滚动进度失败：" .. tostring(err))
        end
    end
end

local function addRandomItem()
    local emptyIndex = nil
    for i = 1, capacity do
        if slots[i] == nil then emptyIndex = i; break end
    end
    if emptyIndex == nil then
        log("随机道具测试：容量已满，请先按 R 扩容")
        return
    end
    testItemSerial = testItemSerial + 1
    local imageId = CONFIG.IMAGE_ID
    if type(CONFIG.TEST_IMAGE_IDS) == "table" and #CONFIG.TEST_IMAGE_IDS > 0 then
        imageId = CONFIG.TEST_IMAGE_IDS[((testItemSerial - 1) % #CONFIG.TEST_IMAGE_IDS) + 1]
    end
    if imageId == nil then
        printerr("[16][网格背包] 随机道具测试未配置 IMAGE_ID 或 TEST_IMAGE_IDS")
        return
    end
    slots[emptyIndex] = imageId
    log("随机道具测试：槽位=" .. tostring(emptyIndex) .. " imageId=" .. tostring(imageId))
    refreshInventory(true)
end

local function expandCapacity()
    if capacity >= CONFIG.MAX_CAPACITY then return end
    capacity = math.min(CONFIG.MAX_CAPACITY, capacity + CONFIG.CAPACITY_STEP)
    refreshInventory(true)
end

local function resetTestData()
    capacity = CONFIG.CAPACITY
    slots = {}
    testItemSerial = 0
    refreshInventory(false)
end

local function bindTestKeys()
    if not CONFIG.ENABLE_TEST_KEYS or not alive(root) then return end
    testKeyCallbacks[Enum.KeyEventType.KeyboardCharacterSkill1KeyDown] = function()
        if selectedIndex ~= nil then sendUseRequest(selectedIndex) end
        return true
    end
    testKeyCallbacks[Enum.KeyEventType.KeyboardCharacterSkill2KeyDown] = function() addRandomItem(); return true end
    testKeyCallbacks[Enum.KeyEventType.KeyboardCharacterSkill3KeyDown] = function() expandCapacity(); return true end
    testKeyCallbacks[Enum.KeyEventType.KeyboardCharacterSkill4KeyDown] = function() resetTestData(); return true end
    for eventType, callback in pairs(testKeyCallbacks) do root:AddKeyEventListener(eventType, callback) end
    log("测试按键已注册；E=使用 Q=随机道具 R=扩容 T=重置")
end

local function unbindTestKeys()
    if not alive(root) then return end
    for eventType, callback in pairs(testKeyCallbacks) do
        pcall(function() root:RemoveKeyEventListener(eventType, callback) end)
    end
    testKeyCallbacks = {}
end

function OnInit()
    if state ~= "NEW" then return end
    state = "WAITING"
    script:EnableUpdate(true)
end

function OnStart() end

function OnUpdate()
    if state == "WAITING" then
        startupFrames = startupFrames + 1
        if findRootAndGrid() then
            if type(CONFIG.ITEM_PREFAB_INDEX) ~= "number" then
                fail("ITEM_PREFAB_INDEX 未填写；请使用界面控件组管理中保存的列表项父模板索引")
                return
            end
            root.showCursor = true
            grid.itemPrefabIndex = CONFIG.ITEM_PREFAB_INDEX
            grid.raycastTarget = true
            grid.interactable = true
            state = "RUNNING"
            script:EnableUpdate(false)
            bindTestKeys()
            refreshInventory(false)
            log("网格已就绪；capacity=" .. tostring(capacity))
        elseif startupFrames >= 120 then
            fail("UI 控件在等待窗口内未就绪")
        end
    end
end

function OnEnable()
    if state == "RUNNING" then refreshInventory(true) end
end

function OnDisable()
    destroyGhost()
    unbindTestKeys()
    local controls = {}
    for control in pairs(callbacksByControl) do controls[#controls + 1] = control end
    for i = 1, #controls do clearControlListeners(controls[i]) end
    pcall(function() script:EnableUpdate(false) end)
end

function OnDestroy()
    OnDisable()
    state = "DESTROYED"
    root, grid = nil, nil
end

-- 可由测试按键或其他脚本调用：
function AddRandomTestItem() addRandomItem() end
function ExpandCapacityTest() expandCapacity() end


