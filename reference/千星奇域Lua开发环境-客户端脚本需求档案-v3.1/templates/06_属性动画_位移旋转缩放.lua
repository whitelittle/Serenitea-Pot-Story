-- 06 属性动画：一次按键同时演示位移、旋转、缩放和颜色 Tween。
-- 依据：docs/客户端控件API文档.md §1、§5、§6、§7、§13、§14。
-- 说明：每次触发先停止上一次 Tween；同一字段不要同时交给逐帧代码和 Tween。

local CONFIG = {
    EXPECTED_SCRIPT_NAME = nil, -- 可选：填写后才检查脚本路径
    IMAGE_PREFAB_INDEX = nil, -- 必填：图片控件模板索引
    TRIGGER_KEY = Enum.KeyEventType.KeyboardJumpKeyDown,
    MOVE_X = 120,
    MOVE_Y = 0,
    MOVE_SECONDS = 0.4,
    ROTATE_DEGREES = 90,
    ROTATE_SECONDS = 0.5,
    SCALE_MULTIPLIER = 1.25,
    SCALE_SECONDS = 0.3,
    COLOR_SECONDS = 0.25,
}

local state = "NEW"
local host, image = nil, nil
local bindings = {}
local tweens = {}
local token = 0
local bindingToken = 0
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
local function finitePositive(value)
    return type(value) == "number" and not math.isnan(value) and not math.isinf(value) and value > 0
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
    if not ok then printerr("[06] EnableUpdate 失败：" .. tostring(err)) end
    return ok
end
local function stopTweens()
    for i = #tweens, 1, -1 do
        local tween = tweens[i]
        tweens[i] = nil
        if tween then pcall(function() tween:Kill(false) end) end
    end
end
local function unbind()
    for i = #bindings, 1, -1 do
        local item = bindings[i]
        bindings[i] = nil
        if host and host.alive then pcall(function() host:RemoveKeyEventListener(item.eventType, item.callback) end) end
    end
end
local function fail(message)
    if state == "FAILED" or state == "DESTROYED" then return end
    state = "FAILED"
    token = token + 1
    bindingToken = bindingToken + 1
    stopTweens(); unbind(); setUpdate(false)
    printerr("[06][FAILED] " .. tostring(message))
end
local function validConfig()
    -- EXPECTED_SCRIPT_NAME 留空时不做脚本名门槛；全局挂载设置决定入口。
    if not validIndex(CONFIG.IMAGE_PREFAB_INDEX) then return false, "IMAGE_PREFAB_INDEX 必须是正整数" end
    if not finitePositive(CONFIG.MOVE_SECONDS) or not finitePositive(CONFIG.ROTATE_SECONDS)
        or not finitePositive(CONFIG.SCALE_SECONDS) or not finitePositive(CONFIG.COLOR_SECONDS) then
        return false, "动画时长必须是大于 0 的数字"
    end
    if type(CONFIG.SCALE_MULTIPLIER) ~= "number" or CONFIG.SCALE_MULTIPLIER <= 0 then
        return false, "SCALE_MULTIPLIER 必须大于 0"
    end
    return true
end
local function bind()
    unbind()
    bindingToken = bindingToken + 1
    local expectedToken = bindingToken
    local callback = function()
        if state ~= "RUNNING" or expectedToken ~= bindingToken then return true end
        local ok, err = pcall(function()
            token = token + 1
            local runToken = token
            stopTweens()
            local x, y = image:GetAnchoredPosition()
            local sx, sy, sz = image:GetLocalScale()
            local originalColor = image.imageColor
            local move = game.Tween(image, { anchoredPositionX = x + CONFIG.MOVE_X, anchoredPositionY = y + CONFIG.MOVE_Y }, CONFIG.MOVE_SECONDS)
            local rotate = game.Tween(image, { localRotationZ = CONFIG.ROTATE_DEGREES }, CONFIG.ROTATE_SECONDS)
            rotate:SetRelative(true)
            local scale = game.Tween(image, { localScaleX = sx * CONFIG.SCALE_MULTIPLIER, localScaleY = sy * CONFIG.SCALE_MULTIPLIER }, CONFIG.SCALE_SECONDS)
            local color = game.Tween(image, { imageColor = Color.FromRGBA(255, 90, 90, 255) }, CONFIG.COLOR_SECONDS)
            color:SetOnComplete(function()
                if state == "RUNNING" and runToken == token and image.alive then image.imageColor = originalColor end
            end)
            move:SetEase(Enum.EaseType.OutCubic); rotate:SetEase(Enum.EaseType.OutCubic)
            scale:SetEase(Enum.EaseType.OutBack); color:SetEase(Enum.EaseType.OutQuad)
            tweens = { move, rotate, scale, color }
            for i = 1, #tweens do tweens[i]:Play() end
            print("[06] 属性动画已触发")
        end)
        if not ok then printerr("[06] 创建动画失败：" .. tostring(err)) end
        return true
    end
    host:AddKeyEventListener(CONFIG.TRIGGER_KEY, callback)
    bindings[#bindings + 1] = { eventType = CONFIG.TRIGGER_KEY, callback = callback }
end
local function tryStart()
    if state ~= "STARTING" then return end
    if CONFIG.EXPECTED_SCRIPT_NAME ~= nil then
        local actual = normalizeName(script.path)
        if actual == nil or actual ~= normalizeName(CONFIG.EXPECTED_SCRIPT_NAME) then fail("挂载脚本名不匹配") return end
    end
    local ok, object = pcall(function() return script.object end)
    if not ok or object == nil or not object.alive then return end
    host = object; image = findChild(host, CONFIG.IMAGE_PREFAB_INDEX)
    if image == nil then fail("找不到图片 prefabIndex=" .. tostring(CONFIG.IMAGE_PREFAB_INDEX)) return end
    state = "RUNNING"; bind(); setUpdate(false)
end
function OnInit()
    if state ~= "NEW" then return end
    local ok, message = validConfig()
    if not ok then fail(message) return end
    state = "STARTING"; setUpdate(true)
end
function OnStart() tryStart() end
function OnEnable()
    if state == "STARTING" then setUpdate(true) end
    if state == "RUNNING" then bind() end
end
function OnDisable()
    token = token + 1; bindingToken = bindingToken + 1; stopTweens(); unbind(); setUpdate(false)
end
function OnUpdate(dt)
    if state ~= "STARTING" then return end
    startAttempts = startAttempts + 1; tryStart()
    if state == "STARTING" and startAttempts >= 30 then fail("启动依赖未就绪") end
end
function OnLevelUpdate(dt) end
function OnDestroy()
    if state == "DESTROYED" then return end
    token = token + 1; bindingToken = bindingToken + 1; stopTweens(); unbind(); state = "DESTROYED"; setUpdate(false)
    image, host = nil, nil
end







