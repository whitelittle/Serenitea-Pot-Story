-- 02 信号：把客户端按钮动作和服务器信号监听分开。
-- 依据：docs/客户端控件API文档.md §5、§6、§9、§11。

local CONFIG = {
    EXPECTED_SCRIPT_NAME = nil, -- 可选：填写后才检查脚本路径
    BUTTON_PREFAB_INDEX = nil,  -- 可选；填控件模板索引，不是运行时 id
    UP_SIGNAL_NAME = nil,       -- 例如 "CardPlayed"，必须与服务器约定一致
    DOWN_SIGNAL_NAME = nil,     -- 例如 "RoundStart"
    WATCH_VARIABLE_NAME = nil,  -- 可选；自定义变量名
    WATCH_ENTITY_TYPE = nil,    -- 例如 Enum.CustomVariableEntityType.Level
}

local state = "NEW"
local host = nil
local button = nil
local signalCallback = nil
local variableCallback = nil
local buttonCallback = nil
local callbackToken = 0
local startAttempts = 0

local function normalizeName(value)
    if type(value) ~= "string" then return nil end
    local text = value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\\", "/")
    local last = nil
    for part in text:gmatch("[^/]+") do last = part end
    if last and last:sub(-4) == ".lua" then last = last:sub(1, -5) end
    return last
end

local function validIndex(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

local function findChild(parent, prefabIndex)
    if parent == nil or not parent.alive or not validIndex(prefabIndex) then return nil end
    local ok, children = pcall(function() return parent:GetChildren() end)
    if not ok or type(children) ~= "table" then return nil end
    for i = 1, #children do
        local child = children[i]
        if child and child.alive then
            if child.prefabIndex == prefabIndex then return child end
            local nested = findChild(child, prefabIndex)
            if nested then return nested end
        end
    end
    return nil
end

local function setUpdate(enabled)
    local ok, err = pcall(function() script:EnableUpdate(enabled == true) end)
    if not ok then printerr("[02] EnableUpdate 失败：" .. tostring(err)) end
    return ok
end

local function fail(message)
    if state == "FAILED" or state == "DESTROYED" then return end
    state = "FAILED"
    callbackToken = callbackToken + 1
    setUpdate(false)
    printerr("[02][FAILED] " .. tostring(message))
end

local function validConfig()
    -- EXPECTED_SCRIPT_NAME 留空时不做脚本名门槛；全局挂载设置决定入口。
    if CONFIG.BUTTON_PREFAB_INDEX ~= nil and not validIndex(CONFIG.BUTTON_PREFAB_INDEX) then
        return false, "BUTTON_PREFAB_INDEX 必须是正整数或 nil"
    end
    if type(CONFIG.UP_SIGNAL_NAME) ~= "string" or CONFIG.UP_SIGNAL_NAME == "" then
        return false, "UP_SIGNAL_NAME 未填写"
    end
    if type(CONFIG.DOWN_SIGNAL_NAME) ~= "string" or CONFIG.DOWN_SIGNAL_NAME == "" then
        return false, "DOWN_SIGNAL_NAME 未填写"
    end
    if CONFIG.WATCH_VARIABLE_NAME ~= nil then
        if type(CONFIG.WATCH_VARIABLE_NAME) ~= "string" or CONFIG.WATCH_VARIABLE_NAME == "" then
            return false, "WATCH_VARIABLE_NAME 必须是非空字符串或 nil"
        end
        if CONFIG.WATCH_ENTITY_TYPE == nil then
            return false, "填写 WATCH_VARIABLE_NAME 时还要填写 WATCH_ENTITY_TYPE"
        end
    end
    return true
end

local function unbind()
    if button and button.alive and buttonCallback then
        pcall(function() button:RemoveCursorEventListener(Enum.CursorEventType.CursorClick, buttonCallback) end)
    end
    if signalCallback then
        pcall(function() script:UnregisterServerSignalHandler(CONFIG.DOWN_SIGNAL_NAME) end)
    end
    if variableCallback then
        pcall(function() script:UnregisterCustomVariableChangedHandler(CONFIG.WATCH_ENTITY_TYPE, CONFIG.WATCH_VARIABLE_NAME) end)
    end
    signalCallback, variableCallback, buttonCallback = nil, nil, nil
end

local function sendReady()
    if state ~= "RUNNING" then return end
    local ok, signal = pcall(function() return game.ServerSignal(CONFIG.UP_SIGNAL_NAME) end)
    if not ok or signal == nil then
        printerr("[02] 创建上行信号失败")
        return
    end
    signal:AddInt(1) -- 参数顺序必须按服务器节点图契约修改
    signal:SendSignal()
end

local function bind()
    callbackToken = callbackToken + 1
    local token = callbackToken
    signalCallback = function(signalName, signalParams)
        if state ~= "RUNNING" or token ~= callbackToken then return end
        local first = type(signalParams) == "table" and signalParams[1] or nil
        print("[02] 收到 " .. tostring(signalName) .. "，第一个参数=" .. tostring(first))
    end
    script:RegisterServerSignalHandler(CONFIG.DOWN_SIGNAL_NAME, signalCallback)

    if CONFIG.WATCH_VARIABLE_NAME ~= nil then
        variableCallback = function(entityType, variableName)
            if state ~= "RUNNING" or token ~= callbackToken then return end
            local ok, value = pcall(function()
                return game.GetGlobalCustomVariableValue(entityType, variableName)
            end)
            if ok then print("[02] 变量变化 " .. tostring(variableName) .. "=" .. tostring(value)) end
        end
        script:RegisterCustomVariableChangedHandler(CONFIG.WATCH_ENTITY_TYPE, CONFIG.WATCH_VARIABLE_NAME, variableCallback)
    end

    if button ~= nil and button.alive then
        buttonCallback = function()
            if state ~= "RUNNING" or token ~= callbackToken then return end
            sendReady()
            return true
        end
        button:AddCursorEventListener(Enum.CursorEventType.CursorClick, buttonCallback)
    end
end

local function tryStart()
    if state ~= "STARTING" then return end
    if CONFIG.EXPECTED_SCRIPT_NAME ~= nil then
        local actual = normalizeName(script.path)
        if actual == nil or actual ~= normalizeName(CONFIG.EXPECTED_SCRIPT_NAME) then
            fail("挂载脚本名不匹配")
            return
        end
    end
    local ok, object = pcall(function() return script.object end)
    if not ok or object == nil or not object.alive then return end
    host = object
    if CONFIG.BUTTON_PREFAB_INDEX ~= nil then
        button = findChild(host, CONFIG.BUTTON_PREFAB_INDEX)
        if button == nil then fail("找不到按钮 prefabIndex=" .. tostring(CONFIG.BUTTON_PREFAB_INDEX)) return end
    end
    bind()
    state = "RUNNING"
    setUpdate(false)
    print("[02] RUNNING：信号监听已注册")
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
    if state == "RUNNING" then unbind(); bind() end
end
function OnDisable()
    callbackToken = callbackToken + 1
    unbind()
    setUpdate(false)
end
function OnUpdate(dt)
    if state ~= "STARTING" then return end
    startAttempts = startAttempts + 1
    tryStart()
    if state == "STARTING" and startAttempts >= 30 then fail("启动依赖未就绪") end
end
function OnLevelUpdate(dt) end
function OnDestroy()
    if state == "DESTROYED" then return end
    callbackToken = callbackToken + 1
    unbind()
    state = "DESTROYED"
    setUpdate(false)
    button, host = nil, nil
end


