--[[ ui/hud.lua
  一个可以读懂的 UI 模块：找到一个已有文本框，显示分数。
  不注册生命周期，不静默吞掉错误；错误以 false, message 返回给入口。
]]

local Hud = {
    runtime = nil,
    balance = nil,
    config = nil,
    title = nil,
    score = 0,
}

function Hud.Init(runtime, balance, config)
    Hud.runtime, Hud.balance, Hud.config = runtime, balance, config
    return true
end

local function findChildByPrefabIndex(parent, prefabIndex)
    if parent == nil or not parent.alive then return nil, "宿主控件不可用" end
    if type(prefabIndex) ~= "number" or prefabIndex <= 0 then
        return nil, "TEXTBOX_PREFAB_INDEX 未填写（0 表示示例功能关闭）"
    end

    local ok, children = pcall(function() return parent:GetChildren() end)
    if not ok then return nil, "读取子控件失败: " .. tostring(children) end
    for i = 1, #children do
        local child = children[i]
        -- 7.1 API 文档声明的是 prefabIndex；不要改成 prefabId。
        if child ~= nil and child.alive and child.prefabIndex == prefabIndex then
            return child
        end
    end
    return nil, "没有找到 prefabIndex=" .. tostring(prefabIndex) .. " 的子控件"
end

function Hud.Build(host)
    local prefabIndex = Hud.config and Hud.config.TEXTBOX_PREFAB_INDEX or 0
    if type(prefabIndex) ~= "number" or prefabIndex <= 0 then
        -- 教学配置可以留 0：不创建、不查找，其他模块仍可继续阅读或运行。
        Hud.runtime.Log("TEXTBOX_PREFAB_INDEX 未填写，跳过 HUD 示例")
        return true
    end
    local child, err = findChildByPrefabIndex(host, Hud.config.TEXTBOX_PREFAB_INDEX)
    if child == nil then return false, err end
    Hud.title = child
    Hud.Refresh()
    return true
end

function Hud.SetScore(value)
    if type(value) ~= "number" then return false, "分数必须是数字" end
    Hud.score = value
    Hud.Refresh()
    return true
end

function Hud.Refresh()
    if Hud.title == nil or not Hud.title.alive then return false end
    local prefix = (Hud.balance.ui and Hud.balance.ui.scorePrefix) or "分数："
    -- text 是文本字段，不放进 Tween 表；这里直接设置最终文本。
    Hud.title.text = prefix .. tostring(Hud.score)
    return true
end

function Hud.Destroy()
    Hud.title = nil
    Hud.runtime, Hud.balance, Hud.config = nil, nil, nil
    Hud.score = 0
end

return Hud
