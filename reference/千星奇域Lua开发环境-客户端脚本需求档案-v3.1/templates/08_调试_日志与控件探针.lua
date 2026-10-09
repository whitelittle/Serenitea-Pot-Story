-- 08 调试探针：先确认脚本上下文，再按 prefabIndex 检查控件。
-- 依据：docs/客户端控件API文档.md §1、§2、§3、§5、§13。
-- 说明：探针用于静态和运行时观察，不等于真机验收；问题定位后可删除本文件。

local CONFIG = {
    EXPECTED_SCRIPT_NAME = nil, -- 可选：填写后才检查脚本路径
    TARGET_PREFAB_INDEX = nil, -- 可选：要探针的控件模板索引
    DUMP_TREE_ON_START = true,
    HEARTBEAT_EVERY_FRAMES = 120, -- 0 = 启动完成后关闭逐帧
    LOG_FIRST_FRAMES = 3,
}

local state = "NEW"
local host = nil
local frame = 0
local startAttempts = 0
local seen = {}

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
local function logOnce(message)
    if seen[message] then return end
    seen[message] = true
    print("[08] " .. message)
end
local function field(control, key)
    local ok, value = pcall(function() return control[key] end)
    return ok and value or "<读取失败>"
end
local function safe(tag, fn)
    local ok, err = pcall(fn)
    if not ok then printerr("[08] " .. tostring(tag) .. " 失败：" .. tostring(err)) end
    return ok
end
local function setUpdate(enabled)
    local ok, err = pcall(function() script:EnableUpdate(enabled == true) end)
    if not ok then printerr("[08] EnableUpdate 失败：" .. tostring(err)) end
    return ok
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
local function dumpTree(control, depth)
    if control == nil or depth > 5 then return end
    local indent = string.rep("  ", depth)
    print("[08] " .. indent .. tostring(field(control, "name"))
        .. " prefabIndex=" .. tostring(field(control, "prefabIndex"))
        .. " id=" .. tostring(field(control, "id"))
        .. " alive=" .. tostring(field(control, "alive")))
    local ok, children = pcall(function() return control:GetChildren() end)
    if not ok or type(children) ~= "table" then return end
    for i = 1, #children do dumpTree(children[i], depth + 1) end
end
local function probe(control)
    if control == nil then print("[08] 目标控件=nil"); return end
    print("[08] --- 控件探针 ---")
    print("[08] typeof=" .. tostring(typeof(control)) .. " alive=" .. tostring(field(control, "alive")))
    print("[08] prefabIndex=" .. tostring(field(control, "prefabIndex")) .. " id=" .. tostring(field(control, "id")))
    print("[08] name=" .. tostring(field(control, "name")) .. " active=" .. tostring(field(control, "active"))
        .. " visible=" .. tostring(field(control, "visible")))
    safe("GetAnchoredPosition", function()
        local x, y = control:GetAnchoredPosition(); print("[08] position=" .. tostring(x) .. "," .. tostring(y))
    end)
    safe("GetLocalScale", function()
        local x, y, z = control:GetLocalScale(); print("[08] scale=" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z))
    end)
    safe("GetLocalRotation", function()
        local x, y, z = control:GetLocalRotation(); print("[08] rotation=" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z))
    end)
end
local function printContext()
    print("[08] script.path=" .. tostring(script.path))
    print("[08] script.alive=" .. tostring(script.alive) .. " enabled=" .. tostring(script.enabled))
    print("[08] scriptMappingId=" .. tostring(script.scriptMappingId))
    print("[08] script.object=" .. tostring(script.object) .. " typeof=" .. tostring(script.object and typeof(script.object)))
end
local function buildProbe()
    printContext()
    if CONFIG.DUMP_TREE_ON_START then
        safe("game.PrintClientUITree", function() game.PrintClientUITree() end)
        if host then dumpTree(host, 0) end
    end
    if CONFIG.TARGET_PREFAB_INDEX ~= nil then
        local target = findChild(host, CONFIG.TARGET_PREFAB_INDEX)
        probe(target)
    end
end
local function fail(message)
    if state == "FAILED" or state == "DESTROYED" then return end
    state = "FAILED"; setUpdate(false); printerr("[08][FAILED] " .. tostring(message))
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
    if CONFIG.TARGET_PREFAB_INDEX ~= nil and not validIndex(CONFIG.TARGET_PREFAB_INDEX) then fail("TARGET_PREFAB_INDEX 必须是正整数或 nil") return end
    buildProbe(); state = "RUNNING"; setUpdate(CONFIG.HEARTBEAT_EVERY_FRAMES > 0)
end
function OnInit()
    if state ~= "NEW" then return end
    -- EXPECTED_SCRIPT_NAME 可留空，不作为脚本入口门槛。
    state = "STARTING"; setUpdate(true)
end
function OnStart() tryStart() end
function OnEnable()
    if state == "STARTING" then setUpdate(true) end
    if state == "RUNNING" then setUpdate(CONFIG.HEARTBEAT_EVERY_FRAMES > 0) end
end
function OnDisable() setUpdate(false) end
function OnUpdate(dt)
    if state == "STARTING" then
        startAttempts = startAttempts + 1; tryStart()
        if state == "STARTING" and startAttempts >= 30 then fail("启动依赖未就绪") end
        return
    end
    if state ~= "RUNNING" then return end
    frame = frame + 1
    if frame <= CONFIG.LOG_FIRST_FRAMES then logOnce("前置帧 " .. tostring(frame) .. " dt=" .. tostring(dt)) end
    if CONFIG.HEARTBEAT_EVERY_FRAMES > 0 and frame % CONFIG.HEARTBEAT_EVERY_FRAMES == 0 then
        print("[08] 心跳 frame=" .. tostring(frame) .. " alive=" .. tostring(script.alive))
    end
end
function OnLevelUpdate(dt) end
function OnDestroy()
    if state == "DESTROYED" then return end
    state = "DESTROYED"; setUpdate(false); host = nil
end
