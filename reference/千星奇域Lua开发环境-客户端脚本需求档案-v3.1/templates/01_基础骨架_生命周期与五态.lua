-- 01 基础骨架：先确认脚本挂载，再用 script.object 找到真实宿主。
-- 依据：docs/客户端控件API文档.md §1、§2、§3、§5、§13。

local CONFIG = {
    EXPECTED_SCRIPT_NAME = nil, -- 可选：填写后才检查脚本路径
    TARGET_PREFAB_INDEX = nil,  -- 可选：要查找的子控件模板索引；不需要就保留 nil
}

local STATE = { NEW = "NEW", STARTING = "STARTING", RUNNING = "RUNNING", FAILED = "FAILED", DESTROYED = "DESTROYED" }
local state = STATE.NEW
local host = nil
local target = nil
local attempts = 0
local callbackToken = 0

local function normalizeName(value)
    if type(value) ~= "string" then return nil end
    local text = value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\\", "/")
    local last = nil
    for part in text:gmatch("[^/]+") do last = part end
    if last == nil then return nil end
    if last:sub(-4) == ".lua" then last = last:sub(1, -5) end
    return last
end

local function validPositiveInteger(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

local function setUpdate(enabled)
    local ok, err = pcall(function() script:EnableUpdate(enabled == true) end)
    if not ok then printerr("[01] EnableUpdate 失败：" .. tostring(err)) end
    return ok
end

local function fail(message)
    if state == STATE.FAILED or state == STATE.DESTROYED then return end
    state = STATE.FAILED
    callbackToken = callbackToken + 1
    setUpdate(false)
    printerr("[01][FAILED] " .. tostring(message))
end

local function findChildByPrefabIndex(parent, prefabIndex)
    if parent == nil or not parent.alive or not validPositiveInteger(prefabIndex) then return nil end
    local ok, children = pcall(function() return parent:GetChildren() end)
    if not ok or type(children) ~= "table" then return nil end
    for i = 1, #children do
        local child = children[i]
        if child ~= nil and child.alive then
            if child.prefabIndex == prefabIndex then return child end -- 模板索引，不是运行时 id
            local nested = findChildByPrefabIndex(child, prefabIndex)
            if nested ~= nil then return nested end
        end
    end
    return nil
end

local function validateConfig()
    -- EXPECTED_SCRIPT_NAME 留空时不做脚本名门槛；全局挂载设置决定入口。
    if CONFIG.TARGET_PREFAB_INDEX ~= nil and not validPositiveInteger(CONFIG.TARGET_PREFAB_INDEX) then
        return false, "TARGET_PREFAB_INDEX 必须是正整数，或设为 nil"
    end
    return true
end

local function tryStart()
    if state ~= STATE.STARTING then return end
    if CONFIG.EXPECTED_SCRIPT_NAME ~= nil then
        local actual = normalizeName(script.path)
        local expected = normalizeName(CONFIG.EXPECTED_SCRIPT_NAME)
        if actual == nil then return end -- 脚本上下文尚未就绪，留给下一帧
        if actual ~= expected then
            fail("挂载脚本名不匹配：期望 " .. tostring(expected) .. "，实际 " .. tostring(actual))
            return
        end
    end

    local ok, object = pcall(function() return script.object end)
    if not ok or object == nil or not object.alive then return end
    host = object

    if CONFIG.TARGET_PREFAB_INDEX ~= nil then
        target = findChildByPrefabIndex(host, CONFIG.TARGET_PREFAB_INDEX)
        if target == nil then
            fail("找不到 prefabIndex=" .. tostring(CONFIG.TARGET_PREFAB_INDEX) .. " 的子控件")
            return
        end
    end

    state = STATE.RUNNING
    setUpdate(false) -- 本示例没有持续玩法；保留回调结构供后续模板使用
    print("[01] RUNNING | host=" .. tostring(typeof(host)) .. " | prefabIndex=" .. tostring(CONFIG.TARGET_PREFAB_INDEX))
end

function OnInit()
    if state ~= STATE.NEW then return end
    local ok, message = validateConfig()
    if not ok then fail(message) return end
    state = STATE.STARTING
    attempts = 0
    setUpdate(true)
end

function OnStart()
    tryStart()
end

function OnEnable()
    if state == STATE.STARTING then setUpdate(true) end
    if state == STATE.RUNNING then setUpdate(false) end
end

function OnDisable()
    callbackToken = callbackToken + 1
    setUpdate(false)
end

function OnUpdate(dt)
    if state ~= STATE.STARTING then return end
    attempts = attempts + 1
    tryStart()
    if state == STATE.STARTING and attempts >= 30 then
        fail("script.object 在 30 次启动检查内仍未就绪")
    end
end

function OnLevelUpdate(dt)
    -- 本骨架没有关卡时停相关逻辑。
end

function OnDestroy()
    if state == STATE.DESTROYED then return end
    callbackToken = callbackToken + 1
    state = STATE.DESTROYED
    setUpdate(false)
    target, host = nil, nil
end

