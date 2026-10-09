-- 11 遮罩转场与画面抖动；按通用 TweenSequence 结构独立编写。
-- API：§5 Script、§7 Tween、§8 TweenSequence、§13 控件基类。
-- 宿主下创建两个“图片”和一个“容器节点”，均已激活。
-- 为它们分别设置自定义名称，再填写 CONFIG 的三个 NAME；本例不猜同类实例的自动名称。
-- 例如可自行命名为“上遮罩”“下遮罩”“抖动画面”，这不是编辑器默认名称。
-- 编辑器中的遮罩位置应是合拢位置，宽高足以覆盖目标区域。
-- 用于抖动的容器节点只承载画面；两个遮罩放在它外面，避免一起抖动。
-- 脚本独占这三个控件的位移/遮罩可见性，不销毁借用控件。

local CONFIG = {
    TOP_MASK_NAME = nil,
    BOTTOM_MASK_NAME = nil,
    WORLD_SHAKE_NAME = nil,
    OPEN_DISTANCE = 500, -- UI 单位：遮罩从合拢点向上下各移开的距离
    MOVE_SECONDS = 0.35,
    HOLD_SECONDS = 0.15,
    SHAKE_SECONDS = 0.04,
    PLAY_ON_START = true,
}
local top, bottom, world
local original = {}
local sequence, shakeSequence
local ready, enabled, destroyed = false, false, false
local token = 0
local offsets = { {-12, 8}, {10, -6}, {-7, -4}, {4, 3}, {0, 0} }

local function positive(n)
    return type(n) == "number" and not math.isnan(n) and not math.isinf(n) and n > 0
end

local function kill(tween)
    if tween == nil then return end
    local ok, err = pcall(function() tween:Kill(false) end)
    if not ok then printerr("[11] 清理失败：" .. tostring(err)) end
end

local function remember(control)
    local x, y = control:GetAnchoredPosition()
    original[control] = { x = x, y = y, visible = control.visible }
end

local function putAtBaseline(control)
    if control and control.alive and original[control] then
        local pose = original[control]
        control:SetAnchoredPosition(pose.x, pose.y)
    end
end

-- 取消不执行“遮住时”的业务；也不能遗留半路的抖动偏移。
function StopPresentation()
    token = token + 1
    kill(sequence)
    kill(shakeSequence)
    sequence, shakeSequence = nil, nil
    putAtBaseline(world)
    if top and top.alive and original[top] then top:SetVisible(false) end
    if bottom and bottom.alive and original[bottom] then bottom:SetVisible(false) end
end

local function available()
    return ready and enabled and not destroyed
        and top.alive and bottom.alive and world.alive
end

local function move(control, x, y, seconds, ease)
    local tween = game.Tween(control, { anchoredPositionX = x, anchoredPositionY = y }, seconds)
    tween:SetRelative(false)
    tween:SetEase(ease)
    return tween
end

-- 同一脚本的按键/按钮回调中调用 PlayShake()；这里没有三维相机 API。
function PlayShake()
    if not available() then return false end
    kill(shakeSequence)
    putAtBaseline(world)
    local base = original[world]
    shakeSequence = game.TweenSequence()
    for _, offset in ipairs(offsets) do
        local step = move(world, base.x + offset[1], base.y + offset[2],
            CONFIG.SHAKE_SECONDS, Enum.EaseType.Linear)
        shakeSequence:Append(step)
    end
    shakeSequence:Play()
    return true
end

local function whenCovered()
    -- 在此更换自己的页面内容；保持为普通本地 Lua 逻辑。
    print("[11] 遮罩已合拢，可更新被遮住的页面")
    PlayShake()
end

-- 只把 Tween 放入 Append/Join；不要把另一个 Sequence 当 Tween 嵌套。
function PlayTransition()
    if not available() then return false end
    StopPresentation()
    local thisRun = token
    local a, b = original[top], original[bottom]
    top:SetAnchoredPosition(a.x, a.y + CONFIG.OPEN_DISTANCE)
    bottom:SetAnchoredPosition(b.x, b.y - CONFIG.OPEN_DISTANCE)
    top:SetVisible(true)
    bottom:SetVisible(true)

    sequence = game.TweenSequence()
    sequence:Append(move(top, a.x, a.y, CONFIG.MOVE_SECONDS, Enum.EaseType.OutCubic))
    sequence:Join(move(bottom, b.x, b.y, CONFIG.MOVE_SECONDS, Enum.EaseType.OutCubic))
    sequence:AppendCallback(function()
        if thisRun == token and available() then whenCovered() end
    end)
    sequence:AppendInterval(CONFIG.HOLD_SECONDS)
    sequence:Append(move(top, a.x, a.y + CONFIG.OPEN_DISTANCE,
        CONFIG.MOVE_SECONDS, Enum.EaseType.InCubic))
    sequence:Join(move(bottom, b.x, b.y - CONFIG.OPEN_DISTANCE,
        CONFIG.MOVE_SECONDS, Enum.EaseType.InCubic))
    sequence:SetOnComplete(function()
        if thisRun ~= token or not available() then return end
        top:SetVisible(false)
        bottom:SetVisible(false)
    end)
    sequence:Play()
    return true
end

function OnStart()
    script:EnableUpdate(false) -- 初始化失败时也不保留逐帧调用
    if ready or destroyed then return end
    for _, key in ipairs({ "TOP_MASK_NAME", "BOTTOM_MASK_NAME", "WORLD_SHAKE_NAME" }) do
        if type(CONFIG[key]) ~= "string" or CONFIG[key] == "" then
            printerr("[11] 请填写 " .. key .. " 对应的实际控件名称")
            return
        end
    end
    if CONFIG.TOP_MASK_NAME == CONFIG.BOTTOM_MASK_NAME or CONFIG.TOP_MASK_NAME == CONFIG.WORLD_SHAKE_NAME
        or CONFIG.BOTTOM_MASK_NAME == CONFIG.WORLD_SHAKE_NAME then
        printerr("[11] 三个借用控件必须分别命名")
        return
    end
    if not positive(CONFIG.OPEN_DISTANCE) or not positive(CONFIG.MOVE_SECONDS)
        or not positive(CONFIG.HOLD_SECONDS) or not positive(CONFIG.SHAKE_SECONDS) then
        printerr("[11] 距离和时间须为有限正数")
        return
    end
    local host = script.object
    if host == nil or not host.alive then printerr("[11] 宿主不存在"); return end
    top = host:GetChild(CONFIG.TOP_MASK_NAME)
    bottom = host:GetChild(CONFIG.BOTTOM_MASK_NAME)
    world = host:GetChild(CONFIG.WORLD_SHAKE_NAME)
    if top == nil or bottom == nil or world == nil then
        printerr("[11] 找不到配置的三个直接子控件，请核对 NAME 与实际名称")
        return
    end
    for _, control in ipairs({top, bottom, world}) do
        if not control.alive or not control.activeInHierarchy then
            printerr("[11] 目标控件或其父级未激活")
            return
        end
    end
    remember(top)
    remember(bottom)
    remember(world)
    ready, enabled = true, true
    script:EnableUpdate(false) -- 全部动画由 Tween 推进，不需要逐帧。
    StopPresentation()
    if CONFIG.PLAY_ON_START then PlayTransition() end
end

function OnEnable()
    if destroyed then return end
    enabled = true -- 再启用不自动重播；事件逻辑可调用 PlayTransition()。
end

function OnDisable()
    enabled = false
    StopPresentation()
end

function OnDestroy()
    enabled, destroyed = false, true
    StopPresentation()
    for control, pose in pairs(original) do
        if control.alive then
            control:SetAnchoredPosition(pose.x, pose.y)
            control:SetVisible(pose.visible)
        end
    end
    original = {}
    ready = false
end
