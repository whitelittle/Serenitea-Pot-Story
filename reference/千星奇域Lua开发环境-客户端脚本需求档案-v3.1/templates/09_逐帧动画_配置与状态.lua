-- 09 配置驱动逐帧动画；按“状态 + 帧列表”抽象为独立教学例子。
-- API 依据：docs/客户端控件API文档.md §1、§2、§5、§13。
-- 在宿主下准备“容器节点”作为帧总组，再创建两个容器节点并各自命名后填写 path。
-- 例如可自定义为“待机组”“动作组”；这些是创作者自己的名称，不是编辑器默认名。
-- 每组默认列出一个“图片”控件；制作多帧时，为图片分别命名后把实际名称填入 frames。
-- 帧可用图片或装有多个色块的容器；父组和帧须在编辑器中激活，父组须可见。
-- 此脚本借用帧控件，只管理可见性，不创建或销毁它们。

local CONFIG = {
    FRAME_GROUP_PATH = "容器节点", -- 改成宿主下实际的相对路径
    INITIAL_STATE = "idle",
    MAX_STEPS = 4, -- 一次更新最多推进 4 帧；超出部分丢弃，避免长时间追帧
    STATES = {
        idle = { path = nil, frames = { "图片" }, interval = 0.15, loop = true },
        action = { path = nil, frames = { "图片" },
            interval = 0.1, loop = false, nextState = "idle" },
    },
}

local animations, borrowed = {}, {}
local current, frameIndex, elapsed = nil, 1, 0
local ready, enabled = false, false

local function finite(value)
    return type(value) == "number" and not math.isnan(value) and not math.isinf(value)
end

local function hideFrames()
    for control in pairs(borrowed) do
        if control.alive then control:SetVisible(false) end
    end
end

-- 停止后隐藏所有帧；再次 PlayFrameState 可从第一帧播放。
function StopFrameAnimation()
    current, frameIndex, elapsed = nil, 1, 0
    hideFrames()
    script:EnableUpdate(false)
end

local function find(parent, path)
    if type(path) ~= "string" or path == "" then return nil end
    local ok, child = pcall(function() return parent:FindChild(path) end)
    return ok and child or nil
end

local function loadAnimations(host)
    local group = find(host, CONFIG.FRAME_GROUP_PATH)
    if group == nil or not group.alive then return false, "找不到帧总组：" .. tostring(CONFIG.FRAME_GROUP_PATH) end
    if not finite(CONFIG.MAX_STEPS) or CONFIG.MAX_STEPS < 1 or CONFIG.MAX_STEPS % 1 ~= 0 then
        return false, "MAX_STEPS 必须是正整数"
    end
    if type(CONFIG.STATES) ~= "table" then return false, "STATES 必须是状态表" end
    for name, config in pairs(CONFIG.STATES) do
        if type(name) ~= "string" then return false, "状态名须为字符串" end
        if type(config) ~= "table" or not finite(config.interval) or config.interval <= 0 then
            return false, name .. ".interval 必须大于 0"
        end
        if config.loop ~= true and config.loop ~= false then return false, name .. ".loop 必须是 boolean" end
        if type(config.path) ~= "string" or config.path == "" then return false, name .. ".path 请填实际容器名称或路径" end
        if type(config.frames) ~= "table" or #config.frames == 0 then return false, name .. ".frames 不能为空" end
        local stateGroup = find(group, config.path)
        if stateGroup == nil or not stateGroup.alive then return false, "找不到状态组：" .. name end
        local animation = { frames = {}, interval = config.interval, loop = config.loop, nextState = config.nextState }
        for i, path in ipairs(config.frames) do
            local frame = find(stateGroup, path)
            if frame == nil or not frame.alive then return false, name .. " 找不到第 " .. i .. " 帧：" .. tostring(path) end
            if not frame.activeInHierarchy then return false, name .. " 第 " .. i .. " 帧或其父级未激活" end
            if borrowed[frame] ~= nil then return false, "帧路径重复：" .. name .. "/" .. path end
            borrowed[frame] = { visible = frame.visible }
            animation.frames[i] = frame
        end
        animations[name] = animation
    end
    if animations[CONFIG.INITIAL_STATE] == nil then return false, "INITIAL_STATE 未配置" end
    for name, animation in pairs(animations) do
        if not animation.loop and animation.nextState ~= nil and animations[animation.nextState] == nil then
            return false, name .. ".nextState 指向不存在的状态"
        end
    end
    return true
end

-- 例：同一脚本的事件逻辑中调用 PlayFrameState("action")。
-- 从其他脚本调用时，按 API 的 Script:Invoke("PlayFrameState", "action") 传递。
function PlayFrameState(name)
    if not ready or not enabled then return false end
    local animation = animations[name]
    if animation == nil then printerr("[09] 未配置动画状态：" .. tostring(name)); return false end
    hideFrames()
    current, frameIndex, elapsed = animation, 1, 0
    local first = current.frames[1]
    if not first.alive then StopFrameAnimation(); printerr("[09] 第一帧已被外部销毁"); return false end
    first:SetVisible(true)
    script:EnableUpdate(true)
    return true
end

function OnStart()
    script:EnableUpdate(false) -- 配置失败时也不留下空转的逐帧调用
    local host = script.object
    if host == nil or not host.alive then printerr("[09] 请挂载到存活的客户端控件"); return end
    local ok, message = loadAnimations(host)
    if not ok then printerr("[09] " .. message); return end
    ready, enabled = true, true
    PlayFrameState(CONFIG.INITIAL_STATE)
end

function OnEnable()
    enabled = true
    if ready then PlayFrameState(CONFIG.INITIAL_STATE) end
end

function OnUpdate(dt)
    if not enabled or current == nil then return end
    if not finite(dt) or dt < 0 then
        printerr("[09] dt 无效，停止播放"); StopFrameAnimation(); return
    end
    elapsed = math.min(elapsed + dt, current.interval * CONFIG.MAX_STEPS)
    for _ = 1, CONFIG.MAX_STEPS do
        if elapsed < current.interval then break end
        elapsed = elapsed - current.interval
        local previous = current.frames[frameIndex]
        if previous.alive then previous:SetVisible(false) end
        frameIndex = frameIndex + 1
        if frameIndex > #current.frames then
            if current.loop then
                frameIndex = 1
            elseif current.nextState ~= nil then
                PlayFrameState(current.nextState); return
            else
                StopFrameAnimation(); return
            end
        end
        local frame = current.frames[frameIndex]
        if not frame.alive then printerr("[09] 帧控件已被外部销毁"); StopFrameAnimation(); return end
        frame:SetVisible(true)
    end
end

function OnDisable()
    enabled = false
    StopFrameAnimation()
end

function OnDestroy()
    enabled, ready = false, false
    StopFrameAnimation()
    for control, original in pairs(borrowed) do
        if control.alive then control:SetVisible(original.visible) end
    end
    animations, borrowed = {}, {}
end
