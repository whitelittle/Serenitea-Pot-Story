-- 15 界面动效：播放与停止
-- API 依据：docs/客户端控件API文档.md §1、§2、§5、§13、§22
--
-- 编辑器前提：
-- 1. 宿主是一个已激活的“容器节点”。
-- 2. 宿主下有一个“界面动效”控件，并且已在编辑器里选好动效、设好播放入口。
-- 3. 动效资源由编辑器提供，Lua 只负责播放与停止；不要在 Lua 里猜动效 ID。
--
-- 动态按钮 / 动效 / Tween 的分工见 docs/13_界面动效与全屏界面动效.md。

local CONFIG = {
    -- === 待你填写 ===
    ANIM_NAME = "界面动效",           -- 改成你工程里的实际名称
    PLAY_ON_START = true,             -- 进入 Running 后是否立刻播一次
    PLAY_EVERY_SECONDS = 0,           -- 大于 0 时按固定间隔重复播；0 表示只播一次
}

local host, anim = nil, nil
local acc = 0
local started = false
local retry = 0

local function log(fmt, ...)
    print("[15]" .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt))
end

local function safe(tag, fn)
    local ok, err = pcall(fn)
    if not ok then printerr("[15] " .. tag .. " 失败: " .. tostring(err)) end
    return ok, err
end

-- 播放/停止不是所有 subtype 都实现：先取方法，再判类型
local function playMethod(control)
    if control == nil or not control.alive then return nil end
    local ok, fn = pcall(function() return control.PlayAnimation end)
    if not ok or type(fn) ~= "function" then return nil end
    return fn
end

local function stopMethod(control)
    if control == nil or not control.alive then return nil end
    local ok, fn = pcall(function() return control.StopAnimation end)
    if not ok or type(fn) ~= "function" then return nil end
    return fn
end

local function prepare()
    local candidateHost = script.object
    if candidateHost == nil or not candidateHost.alive then return false, "script.object 尚未就绪" end

    local candidate = candidateHost:GetChild(CONFIG.ANIM_NAME)
    if candidate == nil or not candidate.alive then
        return false, "找不到控件：" .. tostring(CONFIG.ANIM_NAME)
    end
    if playMethod(candidate) == nil then
        return false, "该控件没有 PlayAnimation，确认它是不是“界面动效”"
    end
    host, anim = candidateHost, candidate
    retry, acc = 0, 0
    log("找到动效控件，typeof=%s", tostring(typeof(anim)))
    return true
end

local function play()
    if anim == nil or not anim.alive then return false end
    local fn = playMethod(anim)
    if fn == nil then return false end
    local ok = safe("PlayAnimation", function() fn(anim) end)
    if ok then log("播放动效") end
    return ok
end

local function stop()
    if anim == nil or not anim.alive then return end
    local fn = stopMethod(anim)
    if fn ~= nil then
        local ok = safe("StopAnimation", function() fn(anim) end)
        if ok then log("停止动效") end
    end
end

function OnInit()
    if started then return end
    started = true
    safe("EnableUpdate", function() script:EnableUpdate(true) end)
end

function OnStart() end

function OnEnable()
    anim, host = nil, nil
    retry, acc = 0, 0
    safe("EnableUpdate", function() script:EnableUpdate(true) end)
end

function OnDisable()
    stop()                                     -- 停用先停表现
    safe("EnableUpdate", function() script:EnableUpdate(false) end)
end

function OnUpdate(dt)
    if type(dt) ~= "number" or math.isnan(dt) or math.isinf(dt) or dt <= 0 then return end

    if anim == nil or not anim.alive then
        if anim ~= nil then anim = nil end
        local ok, why = prepare()
        if not ok then
            retry = retry + 1
            if retry >= 300 then
                printerr("[15] 启动依赖始终未就绪: " .. tostring(why))
                safe("EnableUpdate", function() script:EnableUpdate(false) end)
            elseif retry % 60 == 1 then
                log("等待依赖（第 %d 次）：%s", retry, tostring(why))
            end
            return
        end
        if CONFIG.PLAY_ON_START then play() end
        return
    end

    if CONFIG.PLAY_EVERY_SECONDS > 0 then
        acc = acc + dt
        while acc >= CONFIG.PLAY_EVERY_SECONDS do
            acc = acc - CONFIG.PLAY_EVERY_SECONDS
            play()
        end
    end
end

function OnLevelUpdate(dt) end

function OnDestroy()
    stop()
    anim, host = nil, nil
end
