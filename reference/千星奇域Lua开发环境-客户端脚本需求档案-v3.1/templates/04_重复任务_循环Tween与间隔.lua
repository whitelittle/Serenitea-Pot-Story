-- 04 重复任务：一个无限旋转 Tween + 一个固定间隔计时器。
-- 两个时间来源作用于不同目标；不要让同一表现同时由 Tween 和计时器驱动。
-- 依据：docs/客户端控件API文档.md §1、§2、§5、§6、§7、§8、§13。

local CONFIG = {
    EXPECTED_SCRIPT_NAME = nil, -- 可选：填写后才检查脚本路径
    IMAGE_PREFAB_INDEX = nil,   -- 必填：图片控件模板索引
    TEXTBOX_PREFAB_INDEX = nil, -- 可选：文本框模板索引
    ROTATE_DEGREES = 360,
    ROTATE_SECONDS = 2.0,
    INTERVAL_SECONDS = 1.0,
}

local state = "NEW"
local host, image, textbox = nil, nil, nil
local rotateTween = nil
local intervalElapsed, intervalCount = 0, 0
local token = 0
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
local function finiteDt(value)
    if type(value) ~= "number" or math.isnan(value) or math.isinf(value) or value <= 0 then return 0 end
    return value
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
    if not ok then printerr("[04] EnableUpdate 失败：" .. tostring(err)) end
    return ok
end
local function stopRotation()
    if rotateTween then pcall(function() rotateTween:Kill(false) end) end
    rotateTween = nil
end
local function fail(message)
    if state == "FAILED" or state == "DESTROYED" then return end
    state = "FAILED"
    token = token + 1
    stopRotation()
    setUpdate(false)
    printerr("[04][FAILED] " .. tostring(message))
end
local function validConfig()
    -- EXPECTED_SCRIPT_NAME 留空时不做脚本名门槛；全局挂载设置决定入口。
    if not validIndex(CONFIG.IMAGE_PREFAB_INDEX) then return false, "IMAGE_PREFAB_INDEX 必须是正整数" end
    if CONFIG.TEXTBOX_PREFAB_INDEX ~= nil and not validIndex(CONFIG.TEXTBOX_PREFAB_INDEX) then
        return false, "TEXTBOX_PREFAB_INDEX 必须是正整数或 nil"
    end
    if type(CONFIG.ROTATE_DEGREES) ~= "number" or type(CONFIG.ROTATE_SECONDS) ~= "number" or CONFIG.ROTATE_SECONDS <= 0 then
        return false, "旋转参数无效"
    end
    if type(CONFIG.INTERVAL_SECONDS) ~= "number" or CONFIG.INTERVAL_SECONDS <= 0 then return false, "INTERVAL_SECONDS 必须大于 0" end
    return true
end
local function startRepeat()
    if state ~= "RUNNING" or image == nil or not image.alive then return end
    token = token + 1
    intervalElapsed, intervalCount = 0, 0
    stopRotation()
    local ok, created = pcall(function()
        local t = game.Tween(image, { localRotationZ = CONFIG.ROTATE_DEGREES }, CONFIG.ROTATE_SECONDS)
        t:SetEase(Enum.EaseType.Linear)
        t:SetRelative(true)
        t:SetLoops(-1)
        return t
    end)
    if not ok or created == nil then fail("创建循环 Tween 失败") return end
    rotateTween = created
    rotateTween:Play()
    if textbox and textbox.alive then textbox.text = "循环旋转已开始" end
    setUpdate(true) -- 只负责固定间隔任务
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
    startRepeat()
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
    if state == "RUNNING" then startRepeat() end
end
function OnDisable()
    token = token + 1
    stopRotation()
    setUpdate(false)
end
function OnUpdate(dt)
    if state == "STARTING" then
        startAttempts = startAttempts + 1
        tryStart()
        if state == "STARTING" and startAttempts >= 30 then fail("启动依赖未就绪") end
        return
    end
    if state ~= "RUNNING" or rotateTween == nil then return end
    intervalElapsed = intervalElapsed + finiteDt(dt)
    while intervalElapsed >= CONFIG.INTERVAL_SECONDS do
        intervalElapsed = intervalElapsed - CONFIG.INTERVAL_SECONDS
        intervalCount = intervalCount + 1
        if textbox and textbox.alive then textbox.text = "间隔次数：" .. tostring(intervalCount) end
    end
end
function OnLevelUpdate(dt) end
function OnDestroy()
    if state == "DESTROYED" then return end
    token = token + 1
    stopRotation()
    state = "DESTROYED"
    setUpdate(false)
    image, textbox, host = nil, nil, nil
end

