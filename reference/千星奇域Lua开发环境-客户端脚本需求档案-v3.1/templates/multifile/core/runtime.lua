--[[ core/runtime.lua
  只提供示例所需的配置、宿主检查、逐帧开关、故障和清理。
  不创建控件，不猜坐标，不替业务模块保存状态。
]]

local Runtime = {
    config = {},
    cleanups = {},
    state = "NEW",
    faultPrinted = false,
}

function Runtime.Configure(config)
    Runtime.config = config or {}
end

function Runtime.Log(fmt, ...)
    if Runtime.config.VERBOSE == false then return end
    local text = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
    print("[Runtime] " .. text)
end

function Runtime.EnableUpdate(enabled)
    local ok, err = pcall(function() script:EnableUpdate(enabled == true) end)
    if not ok then return false, tostring(err) end
    return true
end

local function normalizeName(path)
    if path == nil then return nil end
    local s = tostring(path):gsub("\\", "/")
    local last = nil
    for part in s:gmatch("[^/]+") do last = part end
    if last == nil then return nil end
    return last:gsub("%.lua$", "")
end

function Runtime.GetHost()
    local object = script.object
    if object == nil or not object.alive then
        return false, { kind = "not_ready", message = "script.object 尚未就绪" }
    end

    local expected = Runtime.config.EXPECTED_SCRIPT_NAME
    if expected ~= nil and expected ~= "" then
        local actual = normalizeName(script.path)
        if actual ~= expected:gsub("%.lua$", "") then
            return false, { kind = "mismatch", message = string.format("期望 %q，实际 %q", expected, tostring(actual)) }
        end
    end
    return true, object
end

function Runtime.Track(cleanup)
    if type(cleanup) ~= "function" then return false end
    Runtime.cleanups[#Runtime.cleanups + 1] = cleanup
    return true
end

function Runtime.Fail(code, message)
    if Runtime.state == "FAILED" or Runtime.state == "DESTROYED" then return end
    Runtime.state = "FAILED"
    Runtime.EnableUpdate(false)
    Runtime.Cleanup()
    if Runtime.faultPrinted then return end
    Runtime.faultPrinted = true
    -- 多文件骨架用精简故障块（错误码 + 消息）；完整字段集见 docs/05 知识层级验证与Debug.md §5。
    printerr("GAME FAULT BEGIN " .. tostring(code))
    printerr("  message = " .. tostring(message))
    printerr("GAME FAULT END " .. tostring(code))
end

function Runtime.Cleanup()
    for i = #Runtime.cleanups, 1, -1 do
        local cleanup = Runtime.cleanups[i]
        Runtime.cleanups[i] = nil
        if type(cleanup) == "function" then
            local ok, err = pcall(cleanup)
            if not ok then printerr("[Runtime][cleanup] " .. tostring(err)) end
        end
    end
end

function Runtime.Destroy()
    Runtime.Cleanup()
    Runtime.state = "DESTROYED"
end

return Runtime
