--[[
  多文件进阶示例：入口文件。
  只有入口文件注册客户端脚本生命周期，模块只导出普通函数。
  配置保持 0 时会安全拒绝对应功能，不要求新手先填满所有索引。

  官方指南说明“脚本映射后才会上传”，但没有规定 Lua require 的路径语法。
  这里的 require 写法是待当前编辑器确认的装载点，见同目录 README.md。
]]

-- 模块声明集中在顶部；若编辑器不支持此路径，先用 README 的最小模块确认。
local Runtime = require("core.runtime")
local Balance = require("data.balance")
local Hud = require("ui.hud")

local CONFIG = {
    TEXTBOX_PREFAB_INDEX = 0, -- 0=跳过 HUD 示例，不会让脚本调用空索引
    EXPECTED_SCRIPT_NAME = nil, -- 可选：保留 nil 则不比较挂载脚本名（与 templates/01–08 一致）
    MAX_START_RETRIES = 120,
    VERBOSE = true,
}

Runtime.Configure(CONFIG)
print("[入口] 多文件示例已加载")

local state = "NEW"
local retry = 0

local function fail(code, message)
    Runtime.Fail(code, message)
    state = "FAILED"
end

local function tryBuild()
    local okHost, hostOrError = Runtime.GetHost()
    if not okHost then return false, hostOrError end

    local okInit, errInit = Hud.Init(Runtime, Balance, CONFIG)
    if not okInit then return false, errInit end
    local okBuild, errBuild = Hud.Build(hostOrError)
    if not okBuild then return false, errBuild end
    return true
end

function OnInit()
    if state ~= "NEW" then return end
    state = "STARTING"
    local ok, err = Runtime.EnableUpdate(true)
    if not ok then fail("UPDATE_ENABLE_ERROR", err) end
end

function OnStart() end

function OnEnable()
    if state == "RUNNING" then Runtime.EnableUpdate(true) end
end

function OnDisable()
    Runtime.EnableUpdate(false)
end

function OnUpdate(dt)
    if state == "FAILED" or state == "DESTROYED" then return end
    if state == "STARTING" then
        local ok, err = tryBuild()
        if ok then
            state = "RUNNING"
            retry = 0
            Runtime.Log("启动完成")
            -- 这个 HUD 示例不需要逐帧；Tween 自己推进时间。
            Runtime.EnableUpdate(false)
            return
        end

        retry = retry + 1
        if type(err) == "table" and err.kind == "not_ready" then
            if retry >= CONFIG.MAX_START_RETRIES then
                fail("START_DEPENDENCY_TIMEOUT", err.message)
            elseif retry == 1 or retry % 30 == 0 then
                Runtime.Log("等待宿主就绪（%d/%d）：%s", retry, CONFIG.MAX_START_RETRIES, err.message)
            end
        else
            fail("BUILD_ERROR", tostring(err))
        end
        return
    end

    -- 本例没有逐帧玩法；需要时再在这里调用模块 Update(dt)。
end

function OnLevelUpdate(dt) end

function OnDestroy()
    if state == "DESTROYED" then return end
    state = "DESTROYED"
    Runtime.EnableUpdate(false)
    Hud.Destroy()
    Runtime.Destroy()
end
