-- 13 输入适配：动态按钮/可拖拽内容的基础结构。
--    推荐结构：容器节点 + 图片等显示内容 + 光标检测区域；不使用预设按钮四态。
--    也包含 WASD、触屏拖拽、主机/移动端手柄左摇杆输入。
-- API：docs/客户端控件API文档.md §3、§6、§11、§13、§18、§19、§24、§26。
-- 宿主：ClientUIContainerControl（容器节点）；直接子控件默认名为“图片”“光标检测区域”。
-- 若已改名，填写 CONFIG 的实际名称；控件及父级已激活/可见，光标检测区域的 raycastTarget=true。
-- 坐标前提：两个子控件及所有祖先的缩放=(1,1,1)、旋转=(0,0,0)。
-- 这样屏幕 UI 位移才等于父级局部位移；前提变化时拒绝移动，不猜坐标换算。

local CONFIG = {
    IMAGE_NAME = "图片",
    CURSOR_AREA_NAME = "光标检测区域",
    SPEED = 240,
    DEAD_ZONE = 0.15,
}
local host, image, area, original = nil, nil, nil, nil
local ready, enabled = false, false
local device = nil
local directions, bindings = {}, {}
local dragCallback = nil
local keys = {
    { "left", Enum.KeyEventType.KeyboardMoveLeftKeyDown, Enum.KeyEventType.KeyboardMoveLeftKeyUp },
    { "right", Enum.KeyEventType.KeyboardMoveRightKeyDown, Enum.KeyEventType.KeyboardMoveRightKeyUp },
    { "up", Enum.KeyEventType.KeyboardMoveForwardKeyDown, Enum.KeyEventType.KeyboardMoveForwardKeyUp },
    { "down", Enum.KeyEventType.KeyboardMoveBackwardKeyDown, Enum.KeyEventType.KeyboardMoveBackwardKeyUp },
}

local function finite(n)
    return type(n) == "number" and not math.isnan(n) and not math.isinf(n)
end

local function identityChain(control)
    for _ = 1, 64 do
        if control == nil then return true end
        if not control.alive then return false end
        local sx, sy, sz = control:GetLocalScale()
        local rx, ry, rz = control:GetLocalRotation()
        if sx ~= 1 or sy ~= 1 or sz ~= 1 or rx ~= 0 or ry ~= 0 or rz ~= 0 then return false end
        control = control.parent
    end
    return false -- 超过教学例的层级上限也不猜换算
end

local function validSpace()
    return host.alive and image.alive and area.alive
        and image.parent == host and area.parent == host
        and identityChain(image) and identityChain(area)
end

local function unbind()
    for _, item in ipairs(bindings) do
        if host and host.alive then host:RemoveKeyEventListener(item.event, item.callback) end
    end
    if dragCallback and area and area.alive then
        area:RemoveCursorEventListener(Enum.CursorEventType.CursorDrag, dragCallback)
    end
    bindings, directions, dragCallback, device = {}, {}, nil, nil
    if original and host and host.alive then host.showCursor = original.showCursor end
end

local function fail(message)
    enabled, ready = false, false
    unbind()
    script:EnableUpdate(false)
    printerr("[13] " .. message)
end

local function move(dx, dy)
    if not finite(dx) or not finite(dy) then return end
    if not validSpace() then
        fail("层级、缩放或旋转发生变化，当前例子无法换算屏幕位移")
        return
    end
    local x, y = image:GetAnchoredPosition()
    if finite(x + dx) and finite(y + dy) then image:SetAnchoredPosition(x + dx, y + dy) end
end

local function bindKey(event, direction, held)
    local callback = function()
        if not enabled then return false end
        directions[direction] = held
        return true
    end
    bindings[#bindings + 1] = { event = event, callback = callback }
    host:AddKeyEventListener(event, callback)
end

local function switchDevice(nextDevice)
    unbind() -- 先移除旧回调并清方向，避免切换后保留“按下”状态
    device = nextDevice
    if device == Enum.Device.KeyboardAndMouse then
        for _, key in ipairs(keys) do
            bindKey(key[2], key[1], true)
            bindKey(key[3], key[1], false)
        end
    elseif device == Enum.Device.Mobile then
        host.showCursor = true -- showCursor 属于容器节点，不属于光标检测区域
        dragCallback = function(data)
            if enabled and data and game.GetDevice() == Enum.Device.Mobile then
                local dx, dy = data:GetUIPosDelta()
                move(dx, dy)
            end
        end
        area:AddCursorEventListener(Enum.CursorEventType.CursorDrag, dragCallback)
    elseif device ~= Enum.Device.Controller and device ~= Enum.Device.MobileController then
        fail("不支持的输入设备：" .. tostring(device))
        return false
    end
    return true -- 两类手柄均在 OnUpdate 中读取摇杆，无需绑定键盘事件
end

local function resume()
    if not ready or enabled then return end
    if not validSpace() then
        fail("请保持直接子层级、单位缩放和零旋转")
        return
    end
    enabled = true
    if switchDevice(game.GetDevice()) then script:EnableUpdate(true) end
end

function OnStart()
    script:EnableUpdate(false)
    if type(CONFIG.IMAGE_NAME) ~= "string" or CONFIG.IMAGE_NAME == ""
        or type(CONFIG.CURSOR_AREA_NAME) ~= "string" or CONFIG.CURSOR_AREA_NAME == "" then
        printerr("[13] 请在 IMAGE_NAME / CURSOR_AREA_NAME 填写实际控件名称")
        return
    end
    if not finite(CONFIG.SPEED) or CONFIG.SPEED <= 0 or not finite(CONFIG.DEAD_ZONE)
        or CONFIG.DEAD_ZONE < 0 or CONFIG.DEAD_ZONE >= 1 then
        printerr("[13] SPEED 须大于 0，DEAD_ZONE 须在 [0,1)")
        return
    end
    host = script.object
    if host == nil or not host.alive or typeof(host) ~= "ClientUIContainerControl" then
        printerr("[13] 请挂载到 ClientUIContainerControl 容器")
        return
    end
    image, area = host:GetChild(CONFIG.IMAGE_NAME), host:GetChild(CONFIG.CURSOR_AREA_NAME)
    if image == nil or area == nil or not image.alive or not area.alive
        or typeof(image) ~= "ClientUIImageControl" or typeof(area) ~= "ClientUICursorEventAreaControl" then
        printerr("[13] 找不到配置的图片或光标检测区域，或控件类型不符，请核对 CONFIG 名称")
        return
    end
    if not image.activeInHierarchy or not area.activeInHierarchy or not area.raycastTarget then
        printerr("[13] 请激活控件及父级，并开启光标检测区域的 raycastTarget")
        return
    end
    local x, y = image:GetAnchoredPosition()
    original = { x = x, y = y, showCursor = host.showCursor }
    ready = true
    resume()
end

function OnEnable()
    resume()
end

function OnUpdate(dt)
    if not ready or not enabled then return end
    local nextDevice = game.GetDevice()
    if nextDevice ~= device and not switchDevice(nextDevice) then return end
    if not validSpace() then
        fail("坐标前提已变化，输入已停止")
        return
    end
    if not finite(dt) or dt <= 0 or device == Enum.Device.Mobile then return end
    local dx, dy = 0, 0
    if device == Enum.Device.KeyboardAndMouse then
        dx = (directions.right and 1 or 0) - (directions.left and 1 or 0)
        dy = (directions.up and 1 or 0) - (directions.down and 1 or 0)
    else -- Controller / MobileController：左摇杆按半径应用死区
        dx, dy = game.GetControllerLeftStickAxis()
        if not finite(dx) or not finite(dy) then return end
        dx, dy = math.max(-1, math.min(1, dx)), math.max(-1, math.min(1, dy))
        local length = math.sqrt(dx * dx + dy * dy)
        if length <= CONFIG.DEAD_ZONE then return end
        local strength = math.min(1, (length - CONFIG.DEAD_ZONE) / (1 - CONFIG.DEAD_ZONE))
        dx, dy = dx / length * strength, dy / length * strength
    end
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 1 then dx, dy = dx / length, dy / length end -- 防止 WASD 斜向加速
    local distance = CONFIG.SPEED * math.min(dt, 0.1) -- 切后台后限制一次移动量
    move(dx * distance, dy * distance)
end

function OnDisable()
    enabled = false
    unbind()
    script:EnableUpdate(false)
end

function OnDestroy()
    OnDisable()
    if original and image and image.alive then image:SetAnchoredPosition(original.x, original.y) end
    ready = false
    host, image, area, original = nil, nil, nil, nil
end
