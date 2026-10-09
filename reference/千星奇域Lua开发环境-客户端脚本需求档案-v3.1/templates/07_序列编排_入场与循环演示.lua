-- 07 序列编排：用 TweenSequence 组织入场、停顿、并行动画和回调。
-- 依据：docs/客户端控件API文档.md §1、§2、§6、§7、§8、§13、§14。
-- 说明：位移使用绝对目标；循环时不要让位置用 SetRelative 累加。

local CONFIG = {
    EXPECTED_SCRIPT_NAME = nil, -- 可选：填写后才检查脚本路径
    IMAGE_PREFAB_INDEX = nil, -- 必填：图片控件模板索引
    ENABLE_LOOP = true,
    OFFSET_X = 240,
    SLIDE_SECONDS = 0.45,
    HOLD_SECONDS = 0.2,
    COLOR_SECONDS = 0.18,
    GAP_SECONDS = 0.5,
}

local state = "NEW"
local host, image = nil, nil
local sequence = nil
local homeX, homeY, homeRotation, homeColor = nil, nil, nil, nil
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
local function positive(value)
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
    if not ok then printerr("[07] EnableUpdate 失败：" .. tostring(err)) end
    return ok
end
local function stopSequence()
    if sequence then pcall(function() sequence:Kill(false) end) end
    sequence = nil
end
local function fail(message)
    if state == "FAILED" or state == "DESTROYED" then return end
    state = "FAILED"; token = token + 1; stopSequence(); setUpdate(false)
    printerr("[07][FAILED] " .. tostring(message))
end
local function validConfig()
    -- EXPECTED_SCRIPT_NAME 留空时不做脚本名门槛；全局挂载设置决定入口。
    if not validIndex(CONFIG.IMAGE_PREFAB_INDEX) then return false, "IMAGE_PREFAB_INDEX 必须是正整数" end
    if CONFIG.ENABLE_LOOP ~= true and CONFIG.ENABLE_LOOP ~= false then return false, "ENABLE_LOOP 必须是 boolean" end
    if not positive(CONFIG.SLIDE_SECONDS) or not positive(CONFIG.HOLD_SECONDS)
        or not positive(CONFIG.COLOR_SECONDS) or not positive(CONFIG.GAP_SECONDS) then
        return false, "时间参数必须是大于 0 的数字"
    end
    if type(CONFIG.OFFSET_X) ~= "number" or math.isnan(CONFIG.OFFSET_X) or math.isinf(CONFIG.OFFSET_X) then
        return false, "OFFSET_X 必须是数字"
    end
    return true
end
local function readBaseline()
    local ok, x, y = pcall(function() return image:GetAnchoredPosition() end)
    if not ok then return false end
    local okRotation, _, _, rz = pcall(function() return image:GetLocalRotation() end)
    if not okRotation then return false end
    homeX, homeY, homeRotation, homeColor = x, y, rz, image.imageColor
    return true
end
local function startSequence()
    if state ~= "RUNNING" or image == nil or not image.alive then return end
    stopSequence(); token = token + 1
    local runToken = token
    image:SetAnchoredPosition(homeX + CONFIG.OFFSET_X, homeY)

    local slideIn = game.Tween(image, { anchoredPositionX = homeX, anchoredPositionY = homeY }, CONFIG.SLIDE_SECONDS)
    local turn = game.Tween(image, { localRotationZ = homeRotation + 360 }, CONFIG.SLIDE_SECONDS)
    local flashOn = game.Tween(image, { imageColor = Color.FromRGBA(255, 255, 255, 255) }, CONFIG.COLOR_SECONDS)
    local flashOff = game.Tween(image, { imageColor = homeColor }, CONFIG.COLOR_SECONDS)
    local slideOut = game.Tween(image, { anchoredPositionX = homeX + CONFIG.OFFSET_X }, CONFIG.SLIDE_SECONDS)
    local slideBack = game.Tween(image, { anchoredPositionX = homeX, anchoredPositionY = homeY }, CONFIG.SLIDE_SECONDS)
    slideIn:SetEase(Enum.EaseType.OutCubic); turn:SetEase(Enum.EaseType.OutCubic)
    slideOut:SetEase(Enum.EaseType.InCubic); slideBack:SetEase(Enum.EaseType.InOutSine)

    sequence = game.TweenSequence()
    sequence:Append(slideIn)
    sequence:Join(turn) -- 与当前队尾并行，整步取较长时长
    sequence:AppendInterval(CONFIG.HOLD_SECONDS)
    sequence:Append(flashOn)
    sequence:Append(flashOff)
    sequence:AppendCallback(function()
        if state == "RUNNING" and runToken == token then print("[07] 闪光步骤完成") end
    end)
    sequence:Append(slideOut)
    sequence:AppendInterval(CONFIG.GAP_SECONDS)
    sequence:Append(slideBack)
    sequence:InsertCallback(CONFIG.SLIDE_SECONDS + 0.05, function()
        if state == "RUNNING" and runToken == token then print("[07] InsertCallback：入场刚结束") end
    end)
    if CONFIG.ENABLE_LOOP then
        sequence:SetLoops(-1)
    else
        sequence:SetOnComplete(function()
            if state == "RUNNING" and runToken == token then print("[07] 单轮序列完成") end
        end)
    end
    sequence:Play()
    print("[07] 序列已播放 | loop=" .. tostring(CONFIG.ENABLE_LOOP))
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
    if not readBaseline() then fail("无法读取图片初始位置或旋转") return end
    state = "RUNNING"; startSequence(); setUpdate(false)
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
    if state == "RUNNING" then startSequence() end
end
function OnDisable()
    token = token + 1; stopSequence(); setUpdate(false)
end
function OnUpdate(dt)
    if state ~= "STARTING" then return end
    startAttempts = startAttempts + 1; tryStart()
    if state == "STARTING" and startAttempts >= 30 then fail("启动依赖未就绪") end
end
function OnLevelUpdate(dt) end
function OnDestroy()
    if state == "DESTROYED" then return end
    token = token + 1; stopSequence(); state = "DESTROYED"; setUpdate(false); image, host = nil, nil
end
