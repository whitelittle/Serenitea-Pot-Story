-- 14 预设按钮：四态引用检查与点击
--
-- 编辑器前提：
-- 1. 宿主是一个已激活的“容器节点”。
-- 2. 宿主的直接子控件有一个“预设按钮”。
-- 3. 预设按钮的直接子控件中有四个“模板引用控件”，并已在按钮设置中
--    分别绑定到“默认状态节点、悬停状态节点、按下状态节点、不可用状态节点”。
-- 4. 每个状态槽位只放一个模板引用控件；每个引用只填写一个模板索引。
--    被引用模板在模板库中独立保存，模板内部才可以包含多个图片、文本框等子控件。
-- 5. 按键样式、可被光标射线检测、按钮是否可用和音效在编辑器中配置。
--
-- 四个名称只是本例的 CONFIG 值，不是编辑器默认名。若四个引用都叫
-- “模板引用控件”，请先在编辑器中重命名，再把实际名字填入 CONFIG。
-- 不要在 Lua 中写 referencedPrefabIndex；它是只读诊断字段。

local CONFIG = {
    BUTTON_NAME = "预设按钮",
    STATE_REF_NAMES = {
        default = "模板引用控件_默认",
        hover = "模板引用控件_悬停",
        pressed = "模板引用控件_按下",
        disabled = "模板引用控件_禁用",
    },
}

local ROLES = { "default", "hover", "pressed", "disabled" }
local host, button = nil, nil
local refs = {}
local clickCallback = nil
local previousShowCursor = nil
local enabled = false
local started = false

local function clearRefs()
    refs = {}
end

local function unbind()
    enabled = false
    if button and button.alive and clickCallback then
        button:RemoveCursorEventListener(Enum.CursorEventType.CursorClick, clickCallback)
    end
    clickCallback = nil
    if host and host.alive and previousShowCursor ~= nil then
        host.showCursor = previousShowCursor
    end
    previousShowCursor = nil
end

local function prepare()
    host = script.object
    if host == nil or not host.alive then return false end

    previousShowCursor = host.showCursor
    host.showCursor = true
    button = host:GetChild(CONFIG.BUTTON_NAME)
    if button == nil or not button.alive then return false end

    clearRefs()
    for _, role in ipairs(ROLES) do
        local name = CONFIG.STATE_REF_NAMES[role]
        local reference = button:GetChild(name)
        if reference == nil or not reference.alive then
            printerr("[14] 缺少四态模板引用控件：" .. tostring(role)
                .. "；请检查按钮直接子级和 CONFIG 名称")
            clearRefs()
            return false
        end
        refs[role] = reference
    end

    -- 不覆盖编辑器的 raycastTarget/interactable 设置，尤其保留不可用态测试。
    return true
end

local function bind()
    if not prepare() then return false end
    clickCallback = function(eventData)
        if not enabled then return end
        print("[14] 预设按钮点击")
        -- 在这里调用玩法函数或发送信号；状态样式由编辑器管理。
    end
    button:AddCursorEventListener(Enum.CursorEventType.CursorClick, clickCallback)
    enabled = true
    return true
end

function OnStart()
    if started then return end
    started = true
    script:EnableUpdate(false) -- 本例只用事件，不需要逐帧更新
    if not bind() then
        started = false
        unbind()
        printerr("[14] 请先完成预设按钮四态模板引用和按键样式配置")
    end
end

function OnEnable()
    if not started then
        OnStart()
    elseif clickCallback == nil then
        bind()
    end
end

function OnDisable()
    unbind()
end

function OnDestroy()
    unbind()
    clearRefs()
    button, host = nil, nil
    started = false
end
