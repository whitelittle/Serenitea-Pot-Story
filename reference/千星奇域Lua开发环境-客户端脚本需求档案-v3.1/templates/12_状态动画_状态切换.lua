-- 12 状态动画：Idle -> Action -> Idle；逻辑状态与控件可见性分开管理。
-- API：docs/客户端控件API文档.md §1、§2、§13、§26。
-- 前提：宿主下创建两个“容器节点”，各自命名并填写 CONFIG 的两个 NAME，二者及父级已激活。
-- 例如可自定义名称“待机组”“动作组”；它们不是编辑器默认名称，本例不猜自动编号。
-- 两个状态控件可各自包含图片或色块；本例只借用 visible，不销毁控件。
-- 同脚本玩法调用 PlayAction()，或按 E 练习；动作中重复触发会被忽略。

local CONFIG = {
    IDLE_NAME = nil,
    ACTION_NAME = nil,
    ACTION_SECONDS = 0.6,
    TRIGGER_KEY = Enum.KeyEventType.KeyboardCharacterSkill1KeyDown,
}

local host, idle, action = nil, nil, nil
local originalIdleVisible, originalActionVisible = nil, nil
local ready, enabled, bound = false, false, false
local currentState, elapsed = "IDLE", 0

local function restoreVisible()
    if idle and idle.alive and originalIdleVisible ~= nil then
        idle:SetVisible(originalIdleVisible)
    end
    if action and action.alive and originalActionVisible ~= nil then
        action:SetVisible(originalActionVisible)
    end
end

local function showState(nextState)
    if not idle.alive or not action.alive then
        printerr("[12] 借用的状态控件已失效，停止动作")
        ready = false
        OnDisable() -- 同时注销按键监听，避免失效后仍保留回调
        return false
    end
    currentState = nextState
    elapsed = 0
    idle:SetVisible(nextState == "IDLE")
    action:SetVisible(nextState == "ACTION")
    script:EnableUpdate(nextState == "ACTION")
    return true
end

function PlayAction()
    if not ready or not enabled or currentState ~= "IDLE" then
        return false
    end
    return showState("ACTION")
end

-- 必须保存同一个回调引用，停用时才能只移除本脚本注册的监听。
local function onTrigger()
    return PlayAction()
end

local function unbind()
    if bound and host and host.alive then
        host:RemoveKeyEventListener(CONFIG.TRIGGER_KEY, onTrigger)
    end
    bound = false
end

local function resume()
    if not ready then return end
    enabled = true
    if not showState("IDLE") then return end
    if not bound then
        host:AddKeyEventListener(CONFIG.TRIGGER_KEY, onTrigger)
        bound = true
    end
end

function OnStart()
    script:EnableUpdate(false)
    if type(CONFIG.IDLE_NAME) ~= "string" or CONFIG.IDLE_NAME == ""
        or type(CONFIG.ACTION_NAME) ~= "string" or CONFIG.ACTION_NAME == ""
        or CONFIG.IDLE_NAME == CONFIG.ACTION_NAME then
        printerr("[12] 请为两个容器节点分别命名，再填写不同的 IDLE_NAME 与 ACTION_NAME")
        return
    end
    if type(CONFIG.ACTION_SECONDS) ~= "number" or math.isnan(CONFIG.ACTION_SECONDS)
        or math.isinf(CONFIG.ACTION_SECONDS) or CONFIG.ACTION_SECONDS <= 0 then
        printerr("[12] ACTION_SECONDS 必须是大于 0 的有限数")
        return
    end
    host = script.object
    if host == nil or not host.alive then
        printerr("[12] 请把脚本挂载到客户端控件")
        return
    end
    idle = host:GetChild(CONFIG.IDLE_NAME)
    action = host:GetChild(CONFIG.ACTION_NAME)
    if idle == nil or action == nil or not idle.alive or not action.alive or idle == action then
        printerr("[12] 找不到配置的两个直接子控件，请核对 IDLE_NAME 与 ACTION_NAME")
        return
    end
    if not idle.activeInHierarchy or not action.activeInHierarchy then
        printerr("[12] 请在编辑器中激活两个状态控件及其父级")
        return
    end
    originalIdleVisible, originalActionVisible = idle.visible, action.visible
    ready = true
    resume()
end

function OnEnable()
    resume()
end

function OnUpdate(dt)
    if not enabled or not ready or currentState ~= "ACTION" then return end
    if type(dt) ~= "number" or math.isnan(dt) or math.isinf(dt) or dt < 0 then
        printerr("[12] dt 无效，本次动作回到 IDLE")
        showState("IDLE")
        return
    end
    elapsed = elapsed + dt
    if elapsed >= CONFIG.ACTION_SECONDS then
        showState("IDLE")
    end
end

function OnDisable()
    enabled = false
    unbind()
    elapsed, currentState = 0, "IDLE"
    script:EnableUpdate(false)
    restoreVisible()
end

function OnDestroy()
    OnDisable()
    ready = false
    host, idle, action = nil, nil, nil
end
