-- 05 按键输入：用 Down/Up 控制一个图片控件移动。
-- 依据：docs/客户端控件API文档.md §1、§2、§5、§13。
-- 说明：按键回调只记录方向，真正移动放在 OnUpdate；停用时必须注销原回调。

local CONFIG = {
    EXPECTED_SCRIPT_NAME = nil, -- 可选：填写后才检查脚本路径
    IMAGE_PREFAB_INDEX = nil,   -- 必填：图片控件模板索引
    TEXTBOX_PREFAB_INDEX = nil, -- 可选：文本框模板索引
    MOVE_SPEED = 240,           -- 每秒移动的 UI 单位
}

local state = "NEW"
local host, image, textbox = nil, nil, nil
local direction = { forward = false, backward = false, left = false, right = false }
local bindings = {}
local token = 0
local startAttempts = 0

local function normalizeName(value)
    if type(value) ~= "string" then return nil end
    local text = value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\\", "/")
    local last
    for part in text:gmatch("[^/]+") do last = part end
    if last and last:sub(-4) == ".lua" then last = last:sub(1, -5) end
    return last
end
local function validIndex(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end
local function validDt(value)
    return type(value) == "number" and not math.isnan(value) and not math.isinf(value) and value > 0 and value or 0
end
local function findChild(parent, index)
    if parent == nil or not parent.alive or not validIndex(index) then return nil end
    local ok, children = pcall(function() return parent:GetChildren() end)
    if not ok or type(children) ~= "table" then return nil end
    for i = 1, #children do
        local child = children[i]
        if child and child.alive then
            if child.prefabIndex == index then return child end
            local nested = findChild(child, index)
            if nested then return nested end
        end
    end
    return nil
end
local function setUpdate(enabled)
    local ok, err = pcall(function() script:EnableUpdate(enabled == true) end)
    if not ok then printerr("[05] EnableUpdate 失败：" .. tostring(err)) end
    return ok
end
local function clearDirection()
    for key in pairs(direction) do direction[key] = false end
end
local function unbindKeys()
    for i = #bindings, 1, -1 do
        local item = bindings[i]
        bindings[i] = nil
        if host and host.alive then
            pcall(function() host:RemoveKeyEventListener(item.eventType, item.callback) end)
        end
    end
end
local function fail(message)
    if state == "FAILED" or state == "DESTROYED" then return end
    state = "FAILED"
    token = token + 1
    clearDirection()
    unbindKeys()
    setUpdate(false)
    printerr("[05][FAILED] " .. tostring(message))
end
local function validConfig()
    -- EXPECTED_SCRIPT_NAME 留空时不做脚本名门槛；全局挂载设置决定入口。
    if not validIndex(CONFIG.IMAGE_PREFAB_INDEX) then return false, "IMAGE_PREFAB_INDEX 必须是正整数" end
    if CONFIG.TEXTBOX_PREFAB_INDEX ~= nil and not validIndex(CONFIG.TEXTBOX_PREFAB_INDEX) then
        return false, "TEXTBOX_PREFAB_INDEX 必须是正整数或 nil"
    end
    if type(CONFIG.MOVE_SPEED) ~= "number" or math.isnan(CONFIG.MOVE_SPEED) or math.isinf(CONFIG.MOVE_SPEED) or CONFIG.MOVE_SPEED <= 0 then
        return false, "MOVE_SPEED 必须是大于 0 的数字"
    end
    return true
end
local function addKey(eventType, field)
    local expectedToken = token
    local callback = function()
        if state ~= "RUNNING" or expectedToken ~= token then return true end
        direction[field] = true
        return true
    end
    host:AddKeyEventListener(eventType, callback)
    bindings[#bindings + 1] = { eventType = eventType, callback = callback }
end
local function addKeyUp(eventType, field)
    local expectedToken = token
    local callback = function()
        if state ~= "RUNNING" or expectedToken ~= token then return true end
        direction[field] = false
        return true
    end
    host:AddKeyEventListener(eventType, callback)
    bindings[#bindings + 1] = { eventType = eventType, callback = callback }
end
local function bindKeys()
    unbindKeys()
    token = token + 1
    addKey(Enum.KeyEventType.KeyboardMoveForwardKeyDown, "forward")
    addKeyUp(Enum.KeyEventType.KeyboardMoveForwardKeyUp, "forward")
    addKey(Enum.KeyEventType.KeyboardMoveBackwardKeyDown, "backward")
    addKeyUp(Enum.KeyEventType.KeyboardMoveBackwardKeyUp, "backward")
    addKey(Enum.KeyEventType.KeyboardMoveLeftKeyDown, "left")
    addKeyUp(Enum.KeyEventType.KeyboardMoveLeftKeyUp, "left")
    addKey(Enum.KeyEventType.KeyboardMoveRightKeyDown, "right")
    addKeyUp(Enum.KeyEventType.KeyboardMoveRightKeyUp, "right")
end
local function tryStart()
    if state ~= "STARTING" then return end
    if CONFIG.EXPECTED_SCRIPT_NAME ~= nil then
        local actual = normalizeName(script.path)
        if actual == nil or actual ~= normalizeName(CONFIG.EXPECTED_SCRIPT_NAME) then fail("挂载脚本名不匹配") return end
    end
    local ok, object = pcall(function() return script.object end)
    if not ok or object == nil or not object.alive then return end
    host = object
    image = findChild(host, CONFIG.IMAGE_PREFAB_INDEX)
    if image == nil then fail("找不到图片 prefabIndex=" .. tostring(CONFIG.IMAGE_PREFAB_INDEX)) return end
    if CONFIG.TEXTBOX_PREFAB_INDEX ~= nil then
        textbox = findChild(host, CONFIG.TEXTBOX_PREFAB_INDEX)
        if textbox == nil then fail("找不到文本框 prefabIndex=" .. tostring(CONFIG.TEXTBOX_PREFAB_INDEX)) return end
    end
    state = "RUNNING"
    bindKeys()
    setUpdate(true)
    if textbox and textbox.alive then textbox.text = "WASD 移动" end
end
function OnInit()
    if state ~= "NEW" then return end
    local ok, message = validConfig()
    if not ok then fail(message) return end
    state = "STARTING"
    setUpdate(true)
end
function OnStart() tryStart() end
function OnEnable()
    if state == "STARTING" then setUpdate(true) end
    if state == "RUNNING" then bindKeys(); setUpdate(true) end
end
function OnDisable()
    token = token + 1
    clearDirection()
    unbindKeys()
    setUpdate(false)
end
function OnUpdate(dt)
    if state == "STARTING" then
        startAttempts = startAttempts + 1
        tryStart()
        if state == "STARTING" and startAttempts >= 30 then fail("启动依赖未就绪") end
        return
    end
    if state ~= "RUNNING" or image == nil or not image.alive then return end
    local dx = (direction.right and 1 or 0) - (direction.left and 1 or 0)
    local dy = (direction.forward and 1 or 0) - (direction.backward and 1 or 0)
    if dx == 0 and dy == 0 then return end
    local ok, x, y = pcall(function() return image:GetAnchoredPosition() end)
    if not ok then return end
    local step = CONFIG.MOVE_SPEED * validDt(dt)
    image:SetAnchoredPosition(x + dx * step, y + dy * step)
end
function OnLevelUpdate(dt) end
function OnDestroy()
    if state == "DESTROYED" then return end
    token = token + 1
    clearDirection()
    unbindKeys()
    state = "DESTROYED"
    setUpdate(false)
    image, textbox, host = nil, nil, nil
end
