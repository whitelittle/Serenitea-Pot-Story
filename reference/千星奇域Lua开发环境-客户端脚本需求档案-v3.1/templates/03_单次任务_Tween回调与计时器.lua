-- 03 单次任务：Tween 完成回调 + 一个只触发一次的计时器。
-- 依据：docs/客户端控件API文档.md §1、§2、§5、§6、§7、§13、§15。

local CONFIG = {
    EXPECTED_SCRIPT_NAME = nil, -- 可选：填写后才检查脚本路径
    IMAGE_PREFAB_INDEX = nil,   -- 必填：图片控件模板索引
    TEXTBOX_PREFAB_INDEX = nil, -- 可选：文本框模板索引
    MOVE_DISTANCE = 120,
    MOVE_SECONDS = 0.35,
    TIMER_SECONDS = 1.0,
}

local state = "NEW"
local host, image, textbox = nil, nil, nil
local tween = nil
local runToken = 0
local elapsed = 0
local timerDone, tweenDone, running = false, false, false
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
    if not ok then printerr("[03] EnableUpdate 失败：" .. tostring(err)) end
    return ok
end

local function stopTween()
    if tween ~= nil then pcall(function() tween:Kill(false) end) end
    tween = nil
end

local function fail(message)
    if state == "FAILED" or state == "DESTROYED" then return end
    state = "FAILED"
    runToken = runToken + 1
    running = false
    stopTween()
    setUpdate(false)
    printerr("[03][FAILED] " .. tostring(message))
end

local function validConfig()
    -- EXPECTED_SCRIPT_NAME 留空时不做脚本名门槛；全局挂载设置决定入口。
    if not validIndex(CONFIG.IMAGE_PREFAB_INDEX) then return false, "IMAGE_PREFAB_INDEX 必须是正整数" end
    if CONFIG.TEXTBOX_PREFAB_INDEX ~= nil and not validIndex(CONFIG.TEXTBOX_PREFAB_INDEX) then
        return false, "TEXTBOX_PREFAB_INDEX 必须是正整数或 nil"
    end
    if type(CONFIG.MOVE_DISTANCE) ~= "number" or type(CONFIG.MOVE_SECONDS) ~= "number" or CONFIG.MOVE_SECONDS <= 0 then
        return false, "MOVE_DISTANCE/MOVE_SECONDS 参数无效"
    end
    if type(CONFIG.TIMER_SECONDS) ~= "number" or CONFIG.TIMER_SECONDS <= 0 then return false, "TIMER_SECONDS 必须大于 0" end
    return true
end

local function startDemo()
    if state ~= "RUNNING" or image == nil or not image.alive then return end
    runToken = runToken + 1
    local token = runToken
    stopTween()
    elapsed, timerDone, tweenDone, running = 0, false, false, true

    local ok, x, y = pcall(function() return image:GetAnchoredPosition() end)
    if not ok then fail("无法读取图片位置") return end
    local targetX = x + CONFIG.MOVE_DISTANCE
    local okTween, created = pcall(function()
        local t = game.Tween(image, { anchoredPositionX = targetX }, CONFIG.MOVE_SECONDS)
        t:SetEase(Enum.EaseType.OutCubic)
        t:SetOnComplete(function()
            if state ~= "RUNNING" or token ~= runToken or not image.alive then return end
            tweenDone = true
            if timerDone then running = false; setUpdate(false) end
        end)
        return t
    end)
    if not okTween or created == nil then fail("创建 Tween 失败") return end
    tween = created
    if textbox and textbox.alive then textbox.text = "单次 Tween 播放中" end
    tween:Play()
    setUpdate(true) -- 计时器需要逐帧；Tween 自己不依赖逐帧
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
    startDemo()
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
    if state == "RUNNING" then startDemo() end
end
function OnDisable()
    runToken = runToken + 1
    running = false
    stopTween()
    setUpdate(false)
end
function OnUpdate(dt)
    if state == "STARTING" then
        startAttempts = startAttempts + 1
        tryStart()
        if state == "STARTING" and startAttempts >= 30 then fail("启动依赖未就绪") end
        return
    end
    if state ~= "RUNNING" or not running then return end
    elapsed = elapsed + finiteDt(dt)
    if not timerDone and elapsed >= CONFIG.TIMER_SECONDS then
        timerDone = true
        if textbox and textbox.alive then textbox.text = "计时器只触发一次" end
        if tweenDone then running = false; setUpdate(false) end
    end
end
function OnLevelUpdate(dt) end
function OnDestroy()
    if state == "DESTROYED" then return end
    runToken = runToken + 1
    stopTween()
    state = "DESTROYED"
    setUpdate(false)
    image, textbox, host = nil, nil, nil
end

