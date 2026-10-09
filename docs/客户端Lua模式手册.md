# 千星奇域客户端 Lua · 模式手册

本文件是开发指导总览的**附录 B**。全部代码骨架取自仓库 `reference/千星奇域Lua开发环境-客户端脚本需求档案-v3.1/templates/` 与同包 `docs/`，只做删减、未改函数名与字段名。

> 提炼自教学包 `C:\Users\Cheng\Documents\deepseek-harness\vampire-survivors\Serenitea-Pot-Story\reference\千星奇域Lua开发环境-客户端脚本需求档案-v3.1\`。所有代码骨架均取自该包 `templates\` 或 `docs\` 原文（仅做删减，未改函数名/字段名）。
>
> **共用前提**：Lua 5.3；不可用 `string.dump`、`io.*`、`coroutine.*`、`os.time/date/clock/difftime` 以外的 `os.*`、`debug.traceback` 以外的 `debug.*`；补充了 `math.isnan/math.isinf`。生命周期回调名固定为 `OnInit / OnStart / OnEnable / OnDisable / OnUpdate(dt) / OnLevelUpdate(dt) / OnDestroy`（`docs\客户端控件API文档.md` §1）。
>
> **不混用编号**：容器节点索引（挂载用，Lua 侧无字段）、控件模板索引 `prefabIndex`（只读）、运行时 `id`（只读）、图片 `imageId`（只读）、脚本映射 ID `scriptMappingId`（只读）、网格 `itemPrefabIndex`、模板引用 `referencedPrefabIndex`（只读）——七者用途不同，不能互换（`AGENT.md`「不可省略的规则」；`prompts\10_文件树.md` §「不要混用编号」为 `AGENT.md` 原文）。

---

## 1. 生命周期与五态骨架

**用途**：给一个脚本定义「初始化 → 启动 → 运行 → 失败 → 销毁」的确定状态，保证重复启用不会重复创建/注册。

**关键调用序列**：
`OnInit` 校验 `CONFIG` → `script:EnableUpdate(true)` → `OnStart`/`OnUpdate` 内 `tryStart()` → `pcall(function() return script.object end)` 取宿主并查 `object.alive` → 成功置 `RUNNING` → `OnEnable`/`OnDisable` 分别 `setUpdate(true)/setUpdate(false)` 并 `callbackToken = callbackToken + 1` → `OnDestroy` 幂等收尾。

**最短可用骨架**（删自 `templates\01_基础骨架_生命周期与五态.lua`，原文件 139 行）：

```lua
local STATE = { NEW = "NEW", STARTING = "STARTING", RUNNING = "RUNNING", FAILED = "FAILED", DESTROYED = "DESTROYED" }
local state = STATE.NEW
local host = nil
local attempts = 0
local callbackToken = 0

local function setUpdate(enabled)
    local ok, err = pcall(function() script:EnableUpdate(enabled == true) end)
    if not ok then printerr("[01] EnableUpdate 失败：" .. tostring(err)) end
    return ok
end

local function fail(message)
    if state == STATE.FAILED or state == STATE.DESTROYED then return end
    state = STATE.FAILED
    callbackToken = callbackToken + 1
    setUpdate(false)
    printerr("[01][FAILED] " .. tostring(message))
end

local function tryStart()
    if state ~= STATE.STARTING then return end
    local ok, object = pcall(function() return script.object end)
    if not ok or object == nil or not object.alive then return end -- 未就绪，留给下一帧
    host = object
    state = STATE.RUNNING
    setUpdate(false) -- 本示例没有持续玩法
end

function OnInit()
    if state ~= STATE.NEW then return end
    state = STATE.STARTING
    attempts = 0
    setUpdate(true)
end

function OnStart() tryStart() end
function OnEnable()
    if state == STATE.STARTING then setUpdate(true) end
    if state == STATE.RUNNING then setUpdate(false) end
end
function OnDisable()
    callbackToken = callbackToken + 1
    setUpdate(false)
end
function OnUpdate(dt)
    if state ~= STATE.STARTING then return end
    attempts = attempts + 1
    tryStart()
    if state == STATE.STARTING and attempts >= 30 then
        fail("script.object 在 30 次启动检查内仍未就绪")
    end
end
function OnLevelUpdate(dt) end
function OnDestroy()
    if state == STATE.DESTROYED then return end
    callbackToken = callbackToken + 1
    state = STATE.DESTROYED
    setUpdate(false)
    host = nil
end
```

要点：`OnInit` 只管不依赖完整控件树的本地状态，`OnStart` 才取宿主并建内容；启动函数必须幂等；`OnDestroy` 重复清理无副作用。`pcall(fn)` 第一个返回值只表示「是否抛错」——若 `fn` 返回 `false, reason`，要接成 `callOk, ready, reason` 分别判断（`prompts\30_生命周期.md`）。

**来源文件**：`C:\Users\Cheng\Documents\deepseek-harness\vampire-survivors\Serenitea-Pot-Story\reference\千星奇域Lua开发环境-客户端脚本需求档案-v3.1\templates\01_基础骨架_生命周期与五态.lua`；规则见同包 `prompts\30_生命周期.md`

---

## 2. 控件获取与父子/层级操作

**用途**：拿到已有控件的引用；改名/改层级后只动 `CONFIG`；诊断时按模板索引确认身份。

**关键调用序列**：
- 直接子级：`host:GetChild(name)`（只查直接子控件）
- 相对路径：`host:FindChild(path)`
- 全部子级：`host:GetChildren()` → `ClientUIBaseControl[]`
- 按模板索引递归确认：`child.prefabIndex == prefabIndex`（只读字段，非通用查找器）
- 同级与层级：`GetSiblingIndex()` / `SetSiblingIndex(index)` / `SetAsFirstSibling()` / `SetAsLastSibling()`
- 显隐：`SetActive(bool)`（连脚本逻辑一起停）与 `SetVisible(bool)`（只改可见性）——`active`/`visible` 是只读字段。

**最短可用骨架**（两个来源合并：删自 `templates\01` 的索引扫描 + 删自 `docs\08_控件名称与CONFIG配置.md`）：

```lua
local CONFIG = {
    IMAGE_NAME = "图片",
    CURSOR_AREA_NAME = "光标检测区域",
    TARGET_PREFAB_INDEX = nil, -- 可选：填正整数才启用索引扫描
}
local image = script.object:GetChild(CONFIG.IMAGE_NAME)
local area = script.object:GetChild(CONFIG.CURSOR_AREA_NAME)

-- 仅在当前父级内确认唯一时用于诊断；不当作通用查找
local function findChildByPrefabIndex(parent, prefabIndex)
    if parent == nil or not parent.alive or not validPositiveInteger(prefabIndex) then return nil end
    local ok, children = pcall(function() return parent:GetChildren() end)
    if not ok or type(children) ~= "table" then return nil end
    for i = 1, #children do
        local child = children[i]
        if child ~= nil and child.alive then
            if child.prefabIndex == prefabIndex then return child end -- 模板索引，不是运行时 id
            local nested = findChildByPrefabIndex(child, prefabIndex)
            if nested ~= nil then return nested end
        end
    end
    return nil
end
```

（`validPositiveInteger` 定义见 `templates\01` 第 26–28 行。）要点：**名字写错返回 `nil`，名字撞上别的控件却返回类型不对的对象**——用 `typeof` 区分（`docs\13_调试_typeof与控件树.md` §3）。已有实例优先用创建返回值、运行时 `id`、名称或路径。

**来源文件**：`...\v3.1\templates\01_基础骨架_生命周期与五态.lua`；`...\v3.1\docs\08_控件名称与CONFIG配置.md`；API §13(1)(2)(3)

---

## 3. 按键输入：按下/抬起绑定、持续按住

**用途**：持续按键移动（按下置 `true`、抬起置 `false`，真正位移放 `OnUpdate` 乘 `dt`）；单次动作只绑 Down。

**关键调用序列**：
- 注册：`host:AddKeyEventListener(eventType, callback)`，回调返回 `boolean`，**处理了本次事件才返回 `true`**
- 注销：`host:RemoveKeyEventListener(eventType, callback)`——必须传注册时的同一回调引用
- 枚举逐字取自 §26(3)：`Enum.KeyEventType.KeyboardMoveForwardKeyDown/KeyUp`、`KeyboardMoveBackwardKeyDown/Up`、`KeyboardMoveLeftKeyDown/Up`、`KeyboardMoveRightKeyDown/Up`；单次用 `KeyboardJumpKeyDown`、`KeyboardCharacterSkill1KeyDown`
- 跨父级位移前提：`identityChain(control)` 沿 `control.parent` 校验缩放 `(1,1,1)`、旋转 `(0,0,0)`

**最短可用骨架**（删自 `templates\05_按键输入_DownUp与移动.lua`，原文件 179 行）：

```lua
local direction = { forward = false, backward = false, left = false, right = false }
local bindings = {}
local token = 0

local function clearDirection()
    for key in pairs(direction) do direction[key] = false end
end

local function unbindKeys()
    for i = #bindings, 1, -1 do
        local item = bindings[i]
        bindings[i] = nil
        if host and host.alive then
            pcall(function() host:RemoveKeyEventListener(item.eventType, item.callback) end)
        end
    end
end

local function addKey(eventType, field)
    local expectedToken = token
    local callback = function()
        if state ~= "RUNNING" or expectedToken ~= token then return true end
        direction[field] = true
        return true
    end
    host:AddKeyEventListener(eventType, callback)
    bindings[#bindings + 1] = { eventType = eventType, callback = callback }
end
local function addKeyUp(eventType, field) -- 同上，direction[field] = false
    local expectedToken = token
    local callback = function()
        if state ~= "RUNNING" or expectedToken ~= token then return true end
        direction[field] = false
        return true
    end
    host:AddKeyEventListener(eventType, callback)
    bindings[#bindings + 1] = { eventType = eventType, callback = callback }
end

local function bindKeys()
    unbindKeys()
    token = token + 1
    addKey(Enum.KeyEventType.KeyboardMoveForwardKeyDown, "forward")
    addKeyUp(Enum.KeyEventType.KeyboardMoveForwardKeyUp, "forward")
    addKey(Enum.KeyEventType.KeyboardMoveLeftKeyDown, "left")
    addKeyUp(Enum.KeyEventType.KeyboardMoveLeftKeyUp, "left")
end

-- OnUpdate 内真正移动（原文件 154–169 行）
--   local dx = (direction.right and 1 or 0) - (direction.left and 1 or 0)
--   local dy = (direction.forward and 1 or 0) - (direction.backward and 1 or 0)
--   local step = CONFIG.MOVE_SPEED * validDt(dt)
--   image:SetAnchoredPosition(x + dx * step, y + dy * step)
```

要点：失焦/停用必须 `clearDirection()` + `unbindKeys()`；恢复时不得重复注册；`Enum.KeyboardKeyCode` 用于按键提示配置，**不等于** `KeyEventType`（`prompts\38_输入.md`）。

**来源文件**：`...\v3.1\templates\05_按键输入_DownUp与移动.lua`；`...\v3.1\prompts\38_输入.md`；API §13(5)、§26(3)

---

## 4. 鼠标/光标检测区域的点击（含拖拽）

**用途**：自定义交互按钮/可拖拽内容。命中由 `ClientUICursorEventAreaControl` 负责，外观由同级「图片」「文本框」负责。

**关键调用序列**：
1. 所属容器节点开光标：`host.showCursor = true`（`showCursor` 属于 `ClientUIContainerControl`，**不属于**光标检测区域；`CursorEvent` 相关方法都需它先为真）
2. 检测目标开射线：`area.raycastTarget = true`
3. 注册：`area:AddCursorEventListener(eventType, callback)`，回调收 `CursorEventData`
4. 枚举逐字取自 §11(7)：`CursorDown`、`CursorUp`、`CursorEnter`、`CursorExit`、`CursorDrag`、`CursorBeginDrag`、`CursorEndDrag`、`CursorClick`
5. 坐标：`data:GetUIPos()`（画布左下为原点）→ `ghost:SetAnchoredPosition(x, y)`；位移用 `data:GetUIPosDelta()`；按下位置用 `data:GetPressUIPos()`
6. 注销：`area:RemoveCursorEventListener(eventType, callback)`（原回调引用）

**最短可用骨架**（删自 `templates\13_输入适配_键鼠与移动端拖拽.lua`）：

```lua
local function bindKey(event, direction, held)
    local callback = function()
        if not enabled then return false end
        directions[direction] = held
        return true
    end
    bindings[#bindings + 1] = { event = event, callback = callback }
    host:AddKeyEventListener(event, callback)
end

-- 移动端触屏拖拽：dragCallback 由 area 的光标事件触发
dragCallback = function(data)
    if enabled and data and game.GetDevice() == Enum.Device.Mobile then
        local dx, dy = data:GetUIPosDelta()
        move(dx, dy)
    end
end
area:AddCursorEventListener(Enum.CursorEventType.CursorDrag, dragCallback)

-- 注销（原文件 50–59 行）
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
```

要点：不要认为 `alpha=0` 自动禁用交互；`CursorEventData.touchId` 可用但**防重复结算要脚本自己按 `touchId` 去重**（实现策略，非 API 保证）；停用时移除自己注册的监听，**不要调用 `RemoveAll*` 删其他脚本的监听**。

**来源文件**：`...\v3.1\templates\13_输入适配_键鼠与移动端拖拽.lua`；`...\v3.1\prompts\38_输入.md`；API §18、§19、§24(1)

---

## 5. Tween 单次动画 + 回调

**用途**：一次位移/淡入/缩放，结束时触发一次逻辑。

**关键调用序列**（顺序固定，`prompts\34_动效.md` §「采用 Tween 时的编写顺序」）：
`pcall(image:GetAnchoredPosition())` 读当前值 → 算终点 → `game.Tween(object, tweenDataTable, duration)` → `t:SetEase(Enum.EaseType.OutCubic)` → `t:SetOnComplete(fn)` → `t:Play()` → 保存句柄 → 取消用 `t:Kill(false)`。

`tweenDataTable` 的键必须是文档标注 **Tweenable** 的字段：`anchoredPositionX/Y`、`sizeDeltaX/Y`、`anchorMinX/Y`、`anchorMaxX/Y`、`pivotX/Y`、`localScaleX/Y/Z`、`localRotationX/Y/Z`、`imageColor`、`fillAmount`、`fontSize`、`fontColor`、`bgColor`、`outlineColor`、`minimumFontSize`、`scrollProgress`、`softEdgeWidthX/Y`、`horizontalSoftRange`、`verticalSoftRange`。`active`/`visible`/`imageId` 只读，分别用 `SetActive/SetVisible/SetImage`；`text` 可赋值但**不可 Tween**。

**最短可用骨架**（删自 `templates\03_单次任务_Tween回调与计时器.lua`）：

```lua
local tween = nil
local runToken = 0

local function stopTween()
    if tween ~= nil then pcall(function() tween:Kill(false) end) end
    tween = nil
end

local function startDemo()
    if state ~= "RUNNING" or image == nil or not image.alive then return end
    runToken = runToken + 1
    local token = runToken
    stopTween()
    local ok, x, y = pcall(function() return image:GetAnchoredPosition() end)
    if not ok then fail("无法读取图片位置") return end
    local targetX = x + CONFIG.MOVE_DISTANCE
    local okTween, created = pcall(function()
        local t = game.Tween(image, { anchoredPositionX = targetX }, CONFIG.MOVE_SECONDS)
        t:SetEase(Enum.EaseType.OutCubic)
        t:SetOnComplete(function()
            if state ~= "RUNNING" or token ~= runToken or not image.alive then return end
            tweenDone = true
        end)
        return t
    end)
    if not okTween or created == nil then fail("创建 Tween 失败") return end
    tween = created
    tween:Play()
end
```

要点：先设起点再创建 Tween，同一字段保持**单一写入者**；`Kill(false)` 取消不触发完成回调，`Kill(true)` 才先切到结束状态并触发回调——**清理默认前者**；回调必须同时检查 `state`、本次演出代号（`token == runToken`）和 `object.alive`。

**来源文件**：`...\v3.1\templates\03_单次任务_Tween回调与计时器.lua`；`...\v3.1\prompts\34_动效.md`；API §7

---

## 6. 循环/重复任务与间隔计时

**用途**：无限旋转 + 固定间隔事件；或与动画无关的倒计时。

**关键调用序列**：
`game.Tween` → `t:SetEase(Enum.EaseType.Linear)` → `t:SetRelative(true)` → `t:SetLoops(-1)`（负数=无限） → `t:Play()`；间隔计时在 `OnUpdate` 累加 `finiteDt(dt)`，余数保留。

**最短可用骨架**（删自 `templates\04_重复任务_循环Tween与间隔.lua`）：

```lua
local intervalElapsed, intervalCount = 0, 0

local function startRepeat()
    if state ~= "RUNNING" or image == nil or not image.alive then return end
    token = token + 1
    intervalElapsed, intervalCount = 0, 0
    stopRotation()
    local ok, created = pcall(function()
        local t = game.Tween(image, { localRotationZ = CONFIG.ROTATE_DEGREES }, CONFIG.ROTATE_SECONDS)
        t:SetEase(Enum.EaseType.Linear)
        t:SetRelative(true)
        t:SetLoops(-1)
        return t
    end)
    if not ok or created == nil then fail("创建循环 Tween 失败") return end
    rotateTween = created
    rotateTween:Play()
    setUpdate(true) -- 只负责固定间隔任务
end

function OnUpdate(dt)
    if state ~= "RUNNING" or rotateTween == nil then return end
    intervalElapsed = intervalElapsed + finiteDt(dt)
    while intervalElapsed >= CONFIG.INTERVAL_SECONDS do
        intervalElapsed = intervalElapsed - CONFIG.INTERVAL_SECONDS
        intervalCount = intervalCount + 1
    end
end
```

要点：**API 正文没有通用定时器接口**——不要编造 `setTimeout`/`Wait`/`coroutine`；与动画无关的倒计时在 Update 累加 `dt`，达到时长置 done 后**随即关逐帧**；重复逻辑保留余数，补执行要设上限，不能无界 `while`；循环 ≠ 自动往返，呼吸效果显式写放大和缩小两段；常驻循环不得依赖最终完成回调推进玩法。

**来源文件**：`...\v3.1\templates\04_重复任务_循环Tween与间隔.lua`；`...\v3.1\prompts\36_任务.md`

---

## 7. 逐帧驱动

**用途**：持续按键移动、摇杆读取、自定义插值、帧图播放。

**关键调用序列**：
`script:EnableUpdate(true/false)`；时间来源二选一——`OnUpdate(dt)` **不受**关卡时停影响，`OnLevelUpdate(dt)` **受**关卡时停影响（文档未声明 Tween 如何受时停影响，不据此推断）。进入前先校验 `dt`：

```lua
local function finiteDt(value)
    if type(value) ~= "number" or math.isnan(value) or math.isinf(value) or value <= 0 then return 0 end
    return value
end
```

**最短可用骨架**（删自 `templates\09_逐帧动画_配置与状态.lua`，原文件 153 行 —— 帧图按「状态 + 帧列表」切换、只改 `visible`、不销毁借用控件）：

```lua
local function hideFrames()
    for control in pairs(borrowed) do
        if control.alive then control:SetVisible(false) end
    end
end

function StopFrameAnimation()
    current, frameIndex, elapsed = nil, 1, 0
    hideFrames()
    script:EnableUpdate(false)
end

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

function OnUpdate(dt)
    if not enabled or current == nil then return end
    if not finite(dt) or dt < 0 then
        printerr("[09] dt 无效，停止播放"); StopFrameAnimation(); return
    end
    elapsed = math.min(elapsed + dt, current.interval * CONFIG.MAX_STEPS) -- 超出部分丢弃，避免长时间追帧
    for _ = 1, CONFIG.MAX_STEPS do
        if elapsed < current.interval then break end
        elapsed = elapsed - current.interval
        local previous = current.frames[frameIndex]
        if previous.alive then previous:SetVisible(false) end
        frameIndex = frameIndex + 1
        if frameIndex > #current.frames then
            if current.loop then frameIndex = 1
            elseif current.nextState ~= nil then PlayFrameState(current.nextState); return
            else StopFrameAnimation(); return end
        end
        local frame = current.frames[frameIndex]
        if not frame.alive then printerr("[09] 帧控件已被外部销毁"); StopFrameAnimation(); return end
        frame:SetVisible(true)
    end
end
```

要点：**纯 Tween 不要为了计时开逐帧**；不要在逐帧里重复建 Tween、找整棵控件树或注册监听；连续帧图按 `dt` 切预建帧根，不是给 `imageId` 做 Tween。

**来源文件**：`...\v3.1\templates\09_逐帧动画_配置与状态.lua`；`...\v3.1\prompts\32_逐帧与调试.md`；API §2

---

## 8. 信号：发送与接收

**用途**：客户端按钮动作上行到服务器；服务器信号下行刷新界面。

**关键调用序列**：
- 上行：`game.ServerSignal(name)` → 按协议顺序 `signal:AddInt(1)`（或 `AddFloat/AddString/AddBool/AddParam/AddVector3/AddEntity/AddPrefabId/AddConfigId` 及其 `*List` 版本，API §9(2)）→ `signal:SendSignal()`
- 下行：`script:RegisterServerSignalHandler(name, callback)`，回调签名 `fun(signalName: string, signalParams: any[])`；解除用 `script:UnregisterServerSignalHandler(name)`
- 名称、参数类型与顺序**必须来自双方约定**；「第一个参数一定是实体」不是 API 要求

**最短可用骨架**（删自 `templates\02_信号_收发与自定义变量.lua`）：

```lua
local function sendReady()
    if state ~= "RUNNING" then return end
    local ok, signal = pcall(function() return game.ServerSignal(CONFIG.UP_SIGNAL_NAME) end)
    if not ok or signal == nil then
        printerr("[02] 创建上行信号失败")
        return
    end
    signal:AddInt(1) -- 参数顺序必须按服务器节点图契约修改
    signal:SendSignal()
end

local function bind()
    callbackToken = callbackToken + 1
    local token = callbackToken
    signalCallback = function(signalName, signalParams)
        if state ~= "RUNNING" or token ~= callbackToken then return end
        local first = type(signalParams) == "table" and signalParams[1] or nil
        print("[02] 收到 " .. tostring(signalName) .. "，第一个参数=" .. tostring(first))
    end
    script:RegisterServerSignalHandler(CONFIG.DOWN_SIGNAL_NAME, signalCallback)
end

local function unbind()
    if signalCallback then
        pcall(function() script:UnregisterServerSignalHandler(CONFIG.DOWN_SIGNAL_NAME) end)
    end
    signalCallback = nil
end
```

要点：**成功注册一条就记录其清理**，不能等整批成功才登记；数据到达与演出播放解耦（先更新本地视图目标，再触发表现）；中断动画不改变服务器权威结算；官方指南说明传送/重连会重建客户端控件，需重新读权威数据并恢复界面——它不是「动画完成就一定落库」的机制。

**来源文件**：`...\v3.1\templates\02_信号_收发与自定义变量.lua`；`...\v3.1\prompts\40_信号.md`；API §5(2)、§9

---

## 9. 自定义变量：Get / Set 与 serverSet

**用途**：监听全局自定义变量变化并刷新界面。

**关键调用序列**：
`script:RegisterCustomVariableChangedHandler(entityType, customVariableName, callback)` —— 回调**只给实体类型和变量名**：`fun(entityType: CustomVariableEntityType, customVariableName: string)`；当前值必须再调 `game.GetGlobalCustomVariableValue(entityType, customVariableName)` 读取；解除用 `script:UnregisterCustomVariableChangedHandler(entityType, customVariableName)`。

实体枚举（§11(2)）：`Enum.CustomVariableEntityType.Level` / `.PlayerSelf` / `.AvatarSelf`。

**最短可用骨架**（删自 `templates\02`）：

```lua
variableCallback = function(entityType, variableName)
    if state ~= "RUNNING" or token ~= callbackToken then return end
    local ok, value = pcall(function()
        return game.GetGlobalCustomVariableValue(entityType, variableName)
    end)
    if ok then print("[02] 变量变化 " .. tostring(variableName) .. "=" .. tostring(value)) end
end
script:RegisterCustomVariableChangedHandler(CONFIG.WATCH_ENTITY_TYPE, CONFIG.WATCH_VARIABLE_NAME, variableCallback)

-- 注销（templates\02 的 unbind 内）
if variableCallback then
    pcall(function() script:UnregisterCustomVariableChangedHandler(CONFIG.WATCH_ENTITY_TYPE, CONFIG.WATCH_VARIABLE_NAME) end)
end
```

**「serverSet」的边界**：本包 API 正文与模板中**没有** `serverSet` 这类接口；脚本侧只有上面的 `Get`（`game.GetGlobalCustomVariableValue`）与「变更监听」两条路径。写入变量走服务器节点图 / 上行 `ServerSignal`，客户端 Lua 不能直接 set。凡读到「serverSet」字样，按 `unknown` 处理，不写进必经路径（`docs\01_API阅读与防混淆.md` §7）。

要点：监听与注销成对，不无限重复注册；变量名与实体类型都要填，只填一个要在 `CONFIG` 校验里直接报错。

**来源文件**：`...\v3.1\templates\02_信号_收发与自定义变量.lua`；`...\v3.1\prompts\40_信号.md`；API §5(2)、§6(3)、§11(2)

---

## 10. 网格列表：`itemPrefabIndex` + `RefreshItems` 的正确用法

**用途**：背包 / 商店 / 滚动列表，由网格控件虚拟化复用列表项。

**关键调用序列**（顺序见 `docs\16` §2）：
1. `game.FindClientUIRoot(CONFIG.ROOT_NAME)` 找到根 → `foundRoot:GetChild(CONFIG.GRID_NAME)` 找到网格，确认 `alive`
2. `root.showCursor = true`
3. `grid.itemPrefabIndex = CONFIG.ITEM_PREFAB_INDEX`（**只有列表项模板索引写到这里**）
4. `grid.raycastTarget = true`；`grid.interactable = true`
5. `grid:RefreshItems(capacity, function(item, callbackIndex) ... end)` —— 回调形式 `fun(control: ClientUIBaseControl, index: integer)`
6. 回调内 `grid:GetItemIndex(item)` 取真实索引（**不要猜从 0 还是 1 开始**）；`item:GetChild("图片"/"文本框"/"光标检测区域")` 取直接子级
7. 滚动位置：刷新前读 `grid.scrollProgress`，刷新后写回（钳到 `[0,1]`）

**最短可用骨架**（删自 `templates\16_网格背包_动态列表与拖拽.lua`，原文件 311 行）：

```lua
local refreshSerial = 0
local savedScrollProgress = 0

function refreshInventory(keepScroll)
    if state ~= "RUNNING" or not alive(grid) then return end
    if keepScroll then
        local ok, progress = pcall(function() return grid.scrollProgress end)
        if ok and type(progress) == "number" then savedScrollProgress = math.max(0, math.min(1, progress)) end
    end
    refreshSerial = refreshSerial + 1
    local serial = refreshSerial
    grid:RefreshItems(capacity, function(item, callbackIndex)
        if state ~= "RUNNING" or serial ~= refreshSerial then return end
        local count = bindItem(item, callbackIndex)
        log("列表项事件已注册；回调索引=" .. tostring(callbackIndex) .. " 注册数=" .. tostring(count))
    end)
    -- 若目标版本的 RefreshItems 回调异步完成，应把恢复移动到「本轮回调完成」分支，并继续检查 serial
    if keepScroll and serial == refreshSerial then
        local ok, err = pcall(function() grid.scrollProgress = savedScrollProgress end)
        if not ok then printerr("[16][网格背包] 恢复滚动进度失败：" .. tostring(err)) end
    end
end
```

单个列表项的绑定核心（`templates\16` 的 `bindItem`）：

```lua
local function bindItem(item, callbackIndex)
    if not alive(item) then return 0 end
    clearControlListeners(item)          -- 复用前先移除本脚本上一次登记的回调
    local area = item:GetChild(CONFIG.ITEM_AREA_NAME)
    if not alive(area) then return 0 end
    area.raycastTarget = true
    local okIndex, runtimeIndex = pcall(function() return grid:GetItemIndex(item) end)
    if not okIndex then runtimeIndex = callbackIndex end
    local records = {}
    local function add(eventType, callback)
        area:AddCursorEventListener(eventType, callback)
        records[#records + 1] = { eventType = eventType, callback = callback }
    end
    add(Enum.CursorEventType.CursorEnter, function() ... end)
    add(Enum.CursorEventType.CursorExit, function() ... end)
    add(Enum.CursorEventType.CursorDown, function() selectedIndex = runtimeIndex end)
    add(Enum.CursorEventType.CursorUp, function() finishDrag() end)
    add(Enum.CursorEventType.CursorClick, function() selectedIndex = runtimeIndex end)
    add(Enum.CursorEventType.CursorBeginDrag, function(data) beginDrag(item, runtimeIndex, data) end)
    add(Enum.CursorEventType.CursorDrag, function(data) updateDrag(data) end)
    add(Enum.CursorEventType.CursorEndDrag, function() finishDrag() end)
    return #records
end
```

要点：**事件监听属于列表项内部的「光标检测区域」，不是只给网格根注册一次**；虚拟化会复用控件，所以每次回调都要重新绑定并按「每控件只绑定一次」的登记表去重；等待 UI 就绪要有上限（模板用 `startupFrames >= 120`）；`itemCount` 是只读结果，不等于模板索引；换位刷新不能把滚动位置无故重置为顶部。

**来源文件**：`...\v3.1\templates\16_网格背包_动态列表与拖拽.lua`；`...\v3.1\docs\11_网格列表项与InstantiateClientUI区别.md`；`...\v3.1\docs\16_网格背包动态列表与拖拽配方.md`；API §20

---

## 11. 动态生成控件：`InstantiateClientUIControl` 的适用与禁忌

**用途**：创建**不属于网格管理**的普通控件——面板、独立图片/文本框、拖拽幽灵、特效实例。

**关键调用序列**：
`game.InstantiateClientUIControl(controlPrefabIndex, parent)` → 校验 `control ~= nil and control.alive` → 使用 → 自建自销：`game.DestroyClientUIControl(control)`。清理前先 `SetVisible(false)` + `SetActive(false)`。

**最短可用骨架**（删自 `templates\10_特效复用_有界对象池.lua`）：

```lua
local function acquire()
    -- 删除已被外部销毁的引用；池容量按实际存活实例计算
    for i = #pool, 1, -1 do
        if not pool[i].control.alive then table.remove(pool, i) end
    end
    for _, entry in ipairs(pool) do
        if not entry.busy then return entry end
    end
    if #pool >= CONFIG.CAPACITY then return nil end
    local ok, control = pcall(function()
        return game.InstantiateClientUIControl(CONFIG.IMAGE_PREFAB_INDEX, host)
    end)
    if not ok or control == nil or not control.alive then
        printerr("[10] 创建图片控件失败：" .. tostring(control))
        return nil
    end
    local entry = { control = control, busy = false }
    pool[#pool + 1] = entry
    return entry
end

local function release(entry)
    if entry.control.alive then
        entry.control:SetVisible(false)
        entry.control:SetActive(false)
    end
    entry.busy, entry.elapsed = false, 0
end

local function clearPool()
    for _, entry in ipairs(pool) do
        if entry.control.alive then
            pcall(function() game.DestroyClientUIControl(entry.control) end)
        end
    end
    pool = {}
    script:EnableUpdate(false)
end
```

要点（`docs\11` 的「为什么不能用普通实例塞进网格」）：
- **禁忌**：网格列表项**不能**用 `InstantiateClientUIControl` 创建。这样创建的是 `parent` 下的普通子控件，不会加入网格虚拟化列表，无法参与 `RefreshItems` 回调、`GetItemIndex` 索引映射、滚动/布局/复用，还可能导致重复显示、点击区域重叠、清理时误删宿主控件。
- **适用**：本地背包的面板背景、文本框、独立图片、拖拽幽灵。
- 只有**已保存为模板的父节点**能被动态创建；主屏画布节点、模板内部子节点都不行。容器节点索引**不是**控件模板索引，不能传进这个函数。
- 借用（`script.object` 和 `GetChild/FindChild/GetChildren` 找到的已有控件）**不销毁**。

**来源文件**：`...\v3.1\templates\10_特效复用_有界对象池.lua`；`...\v3.1\docs\11_网格列表项与InstantiateClientUI区别.md`；`...\v3.1\prompts\20_开工交接.md`；API §6(1)

---

## 12. 预设按钮四态

**用途**：需要编辑器管理四态、按键样式或点击音效时使用 `ClientUIPresetButtonControl`。四态是**编辑器前置条件，不能用 Lua 代替**。

**关键调用序列**：
1. 脚本必须挂在按钮父级的 `ClientUIContainerControl` 上（才能设 `showCursor`），**不要直接挂在预设按钮本体**
2. `previousShowCursor = host.showCursor; host.showCursor = true`
3. `button = host:GetChild(CONFIG.BUTTON_NAME)` —— 按钮的直接子级是四个「模板引用控件」
4. 逐个 `button:GetChild(name)` 校验四个引用（`default / hover / pressed / disabled` 角色名只是 CONFIG 键，不是编辑器默认名）
5. 注册点击：`button:AddCursorEventListener(Enum.CursorEventType.CursorClick, clickCallback)`
6. 注销：`button:RemoveCursorEventListener(Enum.CursorEventType.CursorClick, clickCallback)`

**最短可用骨架**（删自 `templates\14_预设按钮_四态点击.lua`）：

```lua
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
local refs = {}

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
            printerr("[14] 缺少四态模板引用控件：" .. tostring(role) .. "；请检查按钮直接子级和 CONFIG 名称")
            clearRefs()
            return false
        end
        refs[role] = reference
    end
    -- 不覆盖编辑器的 raycastTarget/interactable 设置，尤其保留不可用态测试
    return true
end

local function bind()
    if not prepare() then return false end
    clickCallback = function(eventData)
        if not enabled then return end
        print("[14] 预设按钮点击")
    end
    button:AddCursorEventListener(Enum.CursorEventType.CursorClick, clickCallback)
    enabled = true
    return true
end
```

要点：
- 预设按钮本体**专有字段只有 `interactable`、`clickAudioId`、`raycastTarget`**（API §17(1)），没有图片/文字/颜色字段；外观来自子层级显示控件。
- `ClientUIReferenceControl.referencedPrefabIndex` 是**只读诊断字段**，不能赋值，也不能用运行时 `id` 替代模板引用。
- 当前状态未绑定可显示内容时按钮**没有外观，但仍可能被光标命中**——点击响应不能证明外观已显示；`SimulateCursorClick()` 也不证明真实命中。
- Lua 可以修改**已取得的显示子控件**（`SetImage`、`imageColor`、`text`、`fontColor`），但不能替代编辑器的四态绑定。
- 四个引用必须放在按钮**直接子级**，否则 `button:GetChild(name)` 找不到。

**来源文件**：`...\v3.1\templates\14_预设按钮_四态点击.lua`；`...\v3.1\docs\10_预设按钮四态与样式.md`；`...\v3.1\docs\08_控件名称与CONFIG配置.md`；API §17、§25

---

## 13. 界面动效（编辑器做的动效）如何播放与停止

**用途**：播放编辑器里已配好的动效资源。**Lua 不能创建动效、不能编辑动效内容、不要猜动效 ID**。

**关键调用序列**：
`host:GetChild(CONFIG.ANIM_NAME)` → 先取方法再判类型：`pcall(function() return control.PlayAnimation end)` 且 `type(fn) == "function"` → `fn(anim)` 播放 → `StopAnimation` 停止。写字段用 `animationId`（读写）、`playSoundEffect`（读写）、`layer`（读写，`Enum.UIAnimationLayer.AboveAllControls` / `BelowAllControls`）。

**最短可用骨架**（删自 `templates\15_界面动效_播放与停止.lua`）：

```lua
-- 播放/停止不是所有 subtype 都实现：先取方法，再判类型
local function playMethod(control)
    if control == nil or not control.alive then return nil end
    local ok, fn = pcall(function() return control.PlayAnimation end)
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
    return true
end

local function play()
    if anim == nil or not anim.alive then return false end
    local fn = playMethod(anim)
    if fn == nil then return false end
    local ok = safe("PlayAnimation", function() fn(anim) end)
    return ok
end

local function stop()
    if anim == nil or not anim.alive then return end
    local fn = stopMethod(anim)
    if fn ~= nil then safe("StopAnimation", function() fn(anim) end) end
end
```

要点：**`StopAnimation()` 的收尾状态（停在哪一帧）API 没有声明**——需要固定收尾时自己兜住，不要假设它回到初始画面；`ClientUIFullscreenAnimationControl` **没有** `PlayAnimation/StopAnimation` 专用方法，播放走编辑器配置的播放入口，Lua 可写字段只有 `animationId`、`playSoundEffect`（API §23(1)）；动效和 Tween 是两条路，同时改同一控件时注意字段归属。

**来源文件**：`...\v3.1\templates\15_界面动效_播放与停止.lua`；`...\v3.1\docs\12_界面动效与全屏界面动效.md`；API §11(24)、§22、§23

---

## 14. 状态动画切换（Idle → Action → Idle）

**用途**：两个画面状态之间切换，逻辑状态与控件可见性分开管理。

**关键调用序列**：
`host:GetChild(IDLE_NAME)` / `GetChild(ACTION_NAME)` → 校验 `alive` 且 `activeInHierarchy` → 记录 `originalIdleVisible/originalActionVisible` → `showState(nextState)` 内 `SetVisible` + `script:EnableUpdate(nextState == "ACTION")` → 计时到 `ACTION_SECONDS` 回 `IDLE`。

**最短可用骨架**（删自 `templates\12_状态动画_状态切换.lua`）：

```lua
local currentState, elapsed = "IDLE", 0

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

-- 必须保存同一个回调引用，停用时才能只移除本脚本注册的监听
local function onTrigger()
    return PlayAction()
end

local function unbind()
    if bound and host and host.alive then
        host:RemoveKeyEventListener(CONFIG.TRIGGER_KEY, onTrigger)
    end
    bound = false
end

function OnUpdate(dt)
    if not enabled or not ready or currentState ~= "ACTION" then return end
    elapsed = elapsed + dt
    if elapsed >= CONFIG.ACTION_SECONDS then showState("IDLE") end
end
```

（`CONFIG.TRIGGER_KEY = Enum.KeyEventType.KeyboardCharacterSkill1KeyDown`。）要点：停用后回到 Idle 并 `restoreVisible()` 还原借用控件的原始可见性；`OnDestroy` 里调 `OnDisable` 再清引用。

**来源文件**：`...\v3.1\templates\12_状态动画_状态切换.lua`；`...\v3.1\prompts\36_任务.md`

---

## 15. 对象池 / 特效复用

**用途**：重复播放短特效（上浮淡出），最多创建 `CAPACITY` 个实例；池满跳过新效果，不增加容量、不打断已有效果。

**关键调用序列**：
`acquire()`（先剔除 `not alive` 的引用 → 找 `not busy` → 未满则 `game.InstantiateClientUIControl`）→ `reset(entry, x, y, lifetime)` **重置本脚本会修改的全部表现属性** → `script:EnableUpdate(true)` → `OnUpdate` 推进 `progress = elapsed / lifetime` → `release(entry)` → 全部空闲时 `script:EnableUpdate(false)` → `clearPool()` 里 `game.DestroyClientUIControl`。

**最短可用骨架**（删自 `templates\10_特效复用_有界对象池.lua`）：

```lua
-- 每次借出前重置本脚本会修改的全部表现属性，避免上一次效果残留
local function reset(entry, x, y, lifetime)
    local control = entry.control
    control:SetVisible(false)
    control:SetActive(false)
    control:SetAnchoredPosition(x, y)
    control:SetSizeDelta(CONFIG.SIZE_X, CONFIG.SIZE_Y)
    control:SetLocalScale(1, 1, 1)
    control:SetLocalRotation(0, 0, 0)
    setColor(control, 255)
    entry.x, entry.y, entry.elapsed, entry.lifetime = x, y, 0, lifetime
    entry.busy = true
    control:SetActive(true)
    control:SetVisible(true)
end

function SpawnEffect(x, y, lifetime)
    if not ready or not enabled or host == nil or not host.alive then return false end
    lifetime = lifetime or CONFIG.DEFAULT_LIFETIME
    if not finite(x) or not finite(y) or not positive(lifetime) then
        printerr("[10] 坐标须为有限数，lifetime 须大于 0"); return false
    end
    local entry = acquire()
    if entry == nil then return false end
    reset(entry, x, y, lifetime)
    script:EnableUpdate(true)
    return true
end

function OnUpdate(dt)
    if not ready or not enabled then return end
    if not finite(dt) or dt < 0 then
        printerr("[10] dt 无效，清理对象池"); clearPool(); return
    end
    local anyBusy = false
    for _, entry in ipairs(pool) do
        if entry.busy then
            if not entry.control.alive then
                entry.busy = false
            else
                entry.elapsed = math.min(entry.elapsed + dt, entry.lifetime)
                local progress = entry.elapsed / entry.lifetime
                if progress >= 1 then release(entry)
                else
                    entry.control:SetAnchoredPosition(entry.x, entry.y + CONFIG.RISE_DISTANCE * progress)
                    setColor(entry.control, 255 * (1 - progress))
                    anyBusy = true
                end
            end
        end
    end
    if not anyBusy then script:EnableUpdate(false) end
end
```

要点：`reset` 必须覆盖**所有**被本脚本改过的属性（含颜色 alpha、缩放、旋转、尺寸）；池容量按**实际存活实例**计算；`OnDisable` 与 `OnDestroy` 都走同一个 `clearPool()`；池满返回 `false` 表示本次没生成，不扩容。

**来源文件**：`...\v3.1\templates\10_特效复用_有界对象池.lua`；API §6(1)、§14(2)

---

## 16. 多文件工程的组织方式与入口写法

**用途**：多个功能确实有独立职责、共享状态难以管理时拆模块。**先读模块寻址前提**——官方指南只确认「脚本映射后才会上传」与「可通过 `scriptMappingId` 调用其他脚本」，**没有规定 Lua `require` 的路径语法**，所以 `require` 写法是待当前编辑器确认的装载点。

**文件树**（`templates\multifile\README.md`）：

```text
external_lua_file/
  入口文件示例.lua       -- 唯一生命周期入口
  core/runtime.lua       -- 状态、清理、错误边界
  data/balance.lua       -- 只放数值
  ui/hud.lua             -- 一个简单的文本控件示例
```

**关键调用序列**：入口 `require("core.runtime")` → `Runtime.Configure(CONFIG)` → `Runtime.GetHost()` → 各模块 `Init(...)` → `Build(host)` → `Runtime.EnableUpdate(false)` → `OnDestroy` 里 `Hud.Destroy()` + `Runtime.Destroy()`。

**最短可用骨架**（删自 `templates\multifile\入口文件示例.lua`，原文件 98 行）：

```lua
-- 模块声明集中在顶部；若编辑器不支持此路径，先用 README 的最小模块确认
local Runtime = require("core.runtime")
local Balance = require("data.balance")
local Hud = require("ui.hud")

local CONFIG = {
    TEXTBOX_PREFAB_INDEX = 0, -- 0=跳过 HUD 示例，不会让脚本调用空索引
    EXPECTED_SCRIPT_NAME = nil,
    MAX_START_RETRIES = 120,
    VERBOSE = true,
}

Runtime.Configure(CONFIG)

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

function OnUpdate(dt)
    if state == "FAILED" or state == "DESTROYED" then return end
    if state == "STARTING" then
        local ok, err = tryBuild()
        if ok then
            state = "RUNNING"; retry = 0
            Runtime.EnableUpdate(false)
            return
        end
        retry = retry + 1
        if type(err) == "table" and err.kind == "not_ready" then
            if retry >= CONFIG.MAX_START_RETRIES then fail("START_DEPENDENCY_TIMEOUT", err.message) end
        else
            fail("BUILD_ERROR", tostring(err))
        end
    end
end
```

模块侧契约（`templates\multifile\ui\hud.lua` + `核心\runtime.lua`）：
- 模块导出普通 Lua 表：`local Hud = { ... }` … `return Hud`
- **模块不注册 `OnInit`/`OnUpdate` 等全局回调，只有入口注册**；模块间不互相 `require`
- 模块顶层**不创建控件、不启动 Tween**；把宿主等运行时依赖显式传入：`function Hud.Init(runtime, balance, config)`
- 模块出错返回 `false, message`，由入口统一进入故障状态，不在模块里静默吞掉错误
- `Runtime.Track(cleanup)` 登记清理函数，`Runtime.Cleanup()` 逆序 `pcall` 执行，保留首错

要点：**入口名使用实际挂载脚本名，不固定叫 `levelScript.lua`**；依赖单向不循环；数据表与操作函数分开，共享状态只保留一份；`require` 无依据时优先交付单文件版本，或保留拆分结构但标注 `pending/unknown`。

**来源文件**：`...\v3.1\templates\multifile\入口文件示例.lua`、`...\multifile\README.md`、`...\multifile\core\runtime.lua`、`...\multifile\data\balance.lua`、`...\multifile\ui\hud.lua`；`...\v3.1\prompts\10_文件树.md`

---

## 17. 调试：`typeof` 判型、控件树打印、日志级别

**用途**：排错时最先要用的三个全局能力 + 日志纪律。

**关键调用序列**：
| 能力 | 签名 | 用途 |
|---|---|---|
| `typeof(value)` | `-> string` | 返回运行时类型名；`typeof(script.object)` 确认宿主、`typeof(image)` 区分「取到 nil」与「取到别的控件」 |
| `game.PrintClientUITree()` | `-> —` | 把当前客户端控件树按父子层级写进日志；**排查 ID 错配第一手段** |
| `debug.traceback([message[, level]])` | `-> string` | 只返回文本，不自动写日志；包在 `pcall` 里用时给 `level = 2` |

`print` = 普通级别日志；`printerr` = 错误级别日志，**不抛出 Lua 错误、不阻断运行**（`docs\01` §5：故障分支需要显式返回或改变状态）。

**最短可用骨架**（删自 `templates\08_调试_日志与控件探针.lua`）：

```lua
local seen = {}

local function logOnce(message)
    if seen[message] then return end
    seen[message] = true
    print("[08] " .. message)
end

local function field(control, key)
    local ok, value = pcall(function() return control[key] end)
    return ok and value or "<读取失败>"
end

local function safe(tag, fn)
    local ok, err = pcall(fn)
    if not ok then printerr("[08] " .. tostring(tag) .. " 失败：" .. tostring(err)) end
    return ok
end

local function dumpTree(control, depth)
    if control == nil or depth > 5 then return end
    local indent = string.rep("  ", depth)
    print("[08] " .. indent .. tostring(field(control, "name"))
        .. " prefabIndex=" .. tostring(field(control, "prefabIndex"))
        .. " id=" .. tostring(field(control, "id"))
        .. " alive=" .. tostring(field(control, "alive")))
    local ok, children = pcall(function() return control:GetChildren() end)
    if not ok or type(children) ~= "table" then return end
    for i = 1, #children do dumpTree(children[i], depth + 1) end
end

-- 启动探针（templates\08 的 buildProbe）
local function printContext()
    print("[08] script.path=" .. tostring(script.path))
    print("[08] script.alive=" .. tostring(script.alive) .. " enabled=" .. tostring(script.enabled))
    print("[08] scriptMappingId=" .. tostring(script.scriptMappingId))
    print("[08] script.object=" .. tostring(script.object) .. " typeof=" .. tostring(script.object and typeof(script.object)))
end
local function buildProbe()
    printContext()
    if CONFIG.DUMP_TREE_ON_START then
        safe("game.PrintClientUITree", function() game.PrintClientUITree() end)
        if host then dumpTree(host, 0) end
    end
end
```

`debug.traceback` 用法（`docs\13` §5）：

```lua
local ok, err = pcall(function() risky() end)
if not ok then
    local tb = "<不可用>"
    local okT, tr = pcall(function() return debug.traceback("", 2) end)
    if okT and tr ~= nil then tb = tostring(tr) end
    printerr("[故障] " .. tostring(err) .. "\n" .. tb)
end
```

**日志纪律**（`docs\13` §6）：分级（`print`/`printerr`）；一次性（`seen` 表去重）；不刷屏（逐帧只打前几帧，之后改心跳每 N 帧一条或只在状态变化时打）；带前缀（脚本短名或骨架标识）；开关化（挂 `CONFIG.VERBOSE`）；可回收（临时探针集中一处，注明「定位完删掉」）。**致命故障只输出一个连续块**：

```text
GAME FAULT BEGIN <错误码>
  phase: <阶段>
  message: <原因>
  object: <对象或 nil>
  evidence: <K级别/来源>
  traceback: <调用栈文本；取不到写“不可用”>
  cleanup[1..n]: <清理错误，只追加，不覆盖首个错误>
GAME FAULT END <错误码>
```

**探针规则**：一次只验一件事；只用文档已写明的接口，不夹带玩法逻辑；能一键关掉，定位完删；查控件身份与变换用三组 —— `typeof`/`prefabIndex`/`id`/`alive`；`parent`/`GetChildren`/`GetSiblingIndex`；`GetAnchoredPosition`/`GetSizeDelta`/`GetLocalScale`/`GetLocalRotation`。**不要给每个 getter/setter 都套 `pcall`**，只包可能出错且你关心错误原文的调用。

**来源文件**：`...\v3.1\templates\08_调试_日志与控件探针.lua`；`...\v3.1\docs\13_调试_typeof与控件树.md`；`...\v3.1\docs\05_知识层级验证与Debug.md` §5；API §3

---

## 交付前反查清单

整理自 `prompts\90_交付前反查.md`（11 项原文）+ `prompts\50_证据与文档.md`（证据路由）。**只检查与本次功能有关的项目，不要求每个小脚本实现所有系统。**

## A. 来自 `90_交付前反查`

- [ ] 用户范围与既有信息已复用；需要的实际配置有来源，未填项明确标出
- [ ] Lua 5.3 语法/禁用库检查；多返回值与 `pcall` 返回值未混淆
- [ ] 使用的宿主标识逐个回查 API 完整小节，调用形式、类型、枚举、读写性、Tweenable 一致
- [ ] `prefabIndex` / `id` / `imageId` / `scriptMappingId` 使用场合正确；模板是否可实例化有官方指南依据
- [ ] 初始化、再次启用、停用、失败、销毁路径明确；无重复创建、重复监听和无限资源积累
- [ ] 动画的字段写入者唯一、可取消；旧回调有守卫；正常结束和取消不会重复结算
- [ ] 只清理本脚本拥有的资源；注销使用原回调；局部构建失败也可清理
- [ ] 逐帧仅在需要时开启，外部数字先检查类型/有限性；循环/补执行有停止条件
- [ ] 已知坐标/接口边界写成代码约束，未把 unknown 交给用户反复试玩
- [ ] 所有文档链接存在、模板说明适合手写；未使用包外绝对路径作为运行依赖
- [ ] 交付说明区分文档依据、静态/模拟检查和真实客户端观察，没有伪称已实测

## B. 方法论前缀（`90` 引用 `docs\05` 的 L0–L4 五步验证链）

- [ ] **L0 Lua 结构**：括号、`end`、局部变量、表结构、字符串和函数返回路径
- [ ] **L1 API 事实**：精确标识、点号/冒号、参数、返回值、读写性、可补间字段、枚举、生命周期；**未命中必须为零**
- [ ] **L2 结构与所有权**：有启动入口和销毁入口；四类编号用不同变量名；只有文档允许的模板父节点可动态创建；动态控件/监听器/Tween 创建成功即登记拥有者；同一对象同一字段不被多条 Tween 同时写；关闭时停 Tween、注销监听、清空引用；配置缺失产生明确错误而非调用 `nil` 或 `0`
- [ ] **L3 日志与最小探针**：只读、`pcall` 包住已知 API、唯一前缀和开关、记录完就删
- [ ] **L4 可选运行观察**：只验证一个假设，不把整套玩法交给创作者校准

## C. 证据与真机状态分开（`50_证据与文档` + `docs\05` §1、`docs\07` §2）

- [ ] `evidence_source` 已填：`documented` / `static_checked` / `provided_unverified` / `user_confirmed` / `video_observed` / `inferred` / `observed` / `unknown`
- [ ] `device_status` 已单列：`passed` / `failed` / `confirmed_by_user` / `pending` / `not_required` / `unknown`
- [ ] 未执行的检查**没有**写「通过」；模拟通过**没有**写「真机通过」；`pending` 未被当成失败
- [ ] 用户的既有运行结果已注明**原工程范围**，未外推到本次改动
- [ ] 故障只输出一个连续块，用固定首尾包住；清理错误追加不覆盖首错
- [ ] 每个结论不靠「应该可以」「一般来说」「试玩看看就知道」

## D. 交付回复格式（`docs\07` §4）

```text
完成内容：<文件/函数/表现>
API 依据：<docs/客户端控件API文档.md 的章节>
静态检查：通过 / 有问题（说明问题）
证据：<documented | provided_unverified | user_confirmed | video_observed | inferred | observed | unknown>
真机状态：<passed | failed | confirmed_by_user | pending | not_required>
未决事项：<没有则写“无”；unknown 列出最小补充信息>
运行前动作：<需要建立哪些脚本映射、挂载哪个入口；不把它写成编码前置条件>
```

## E. `unknown` 的处理（`docs\01` §7）

- [ ] 指出缺失的是 API 定义、控件索引、父级作用域、图片资产还是运行时行为
- [ ] 暂停依赖该事实的**那一小段**，不让整份需求停摆
- [ ] 给出**最小**补充信息（一个完整 API 小节 / 一个编辑器属性值 / 一个父控件路径）
- [ ] 其他已有依据的代码继续做静态实现
- [ ] 未把 `unknown` 改写成「真机待确认后大概率可用」

**来源文件**：`...\v3.1\prompts\90_交付前反查.md`；`...\v3.1\prompts\50_证据与文档.md`；`...\v3.1\docs\05_知识层级验证与Debug.md`；`...\v3.1\docs\07_自我约束与证据回报.md`

---

## 坐标与尺寸约定

整理自 `prompts\60_坐标.md`、`docs\01_API阅读与防混淆.md` §4、`docs\客户端控件API文档.md` §13(3)。

## 1. 文档明确写了什么（`prompts\60` 原文表）

| 来源 | 文档明确内容 |
|---|---|
| `GetAnchoredPosition` / `SetAnchoredPosition` | **无父级**以画布**左下**为原点；**有父级**为与父级**中心**的相对偏移 |
| `CursorEventData:GetUIPos()` | 画布左下为原点，坐标比例和布局坐标一致 |
| `game.GetCursorUIPos()` | 取得光标 UI 坐标；单独的函数说明未展开全部变换语义 |
| `game.GetUICanvasSize()` | 返回画布宽高两个数，**不是屏幕分辨率** |
| 锚点、轴心、尺寸增量、缩放、旋转 | 可读写/可补间字段；具体组合效果受父子层级影响 |

## 2. 位置/尺寸的三层来源，不能混

- **布局坐标**：`GetAnchoredPosition() -> x, y`（**多返回值，用两个变量接收**，不把返回数当 `.x/.y` 对象）
- **输入坐标**：`data:GetUIPos()`（左下原点）、`data:GetPressUIPos()`（按下时）、`data:GetUIPosDelta()`（本次位移）
- **画布尺寸**：`game.GetUICanvasSize() -> x, y`

**布局位置与画布输入坐标不能直接比较。** 点击/拖拽优先使用原生控件事件；确需跨层换算时，必须列明父级缩放、旋转、锚点、裁剪前提。

## 3. 可读写 / 可补间字段（API §13(1)(3)）

| 字段 | 访问 | Tweenable |
|---|---|---|
| `anchoredPositionX`, `anchoredPositionY` | 读写 | ✔ |
| `sizeDeltaX`, `sizeDeltaY` | 读写 | ✔ |
| `anchorMinX`, `anchorMinY` | 读写 | ✔ |
| `anchorMaxX`, `anchorMaxY` | 读写 | ✔ |
| `pivotX`, `pivotY` | 读写 | ✔ |
| `localScaleX`, `localScaleY`, `localScaleZ` | 读写 | ✔ |
| `localRotationX`, `localRotationY`, `localRotationZ` | 读写 | ✔ |
| `active`, `visible`, `alive`, `id`, `prefabIndex` | **只读** | ✘ |

对应 getter / setter：`GetSizeDelta()/SetSizeDelta(x,y)`、`GetAnchorMin()/SetAnchorMin(x,y)`、`GetAnchorMax()/SetAnchorMax(x,y)`、`GetPivot()/SetPivot(x,y)`、`GetLocalScale()/SetLocalScale(x,y,z)`、`GetLocalRotation()/SetLocalRotation(x,y,z)`。

## 4. 入门位姿示例的固定前提（`prompts\60`）

固定父级、相同最小/最大锚点、已知轴心，**仅改变当前效果需要的位置/缩放/旋转**。需要尺寸、锚点、颜色、填充或羽化动画时，按对应控件的 Tweenable 定义另选字段，不受入门方案限制。

## 5. 跨父级位移的可换算前提（`templates\13_输入适配_键鼠与移动端拖拽.lua` 的硬约束）

只有沿父链全部满足 **缩放 =(1,1,1)、旋转 =(0,0,0)**，且目标为宿主的直接子级时，屏幕 UI 位移才等于父级局部位移：

```lua
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
```

前提变化时**拒绝移动并报明确原因**，不猜坐标换算。

## 6. 旋转 / 图层

- `localRotationZ` 可做平面旋转；**正方向、最短路径、重复 360 度的绕圈语义 API 未声明**——不为玩法正确性依赖这些细节。平面图片绕 Z 轴转，画面变化是平面内的角度变化。
- 图层顺序：**编辑器同级列表第一项在上**；Lua 侧 `sibling` 数值大的在上（`SetSiblingIndex`：范围 `0` 到父控件子控件数量减一，数值越大通常越靠后、显示越靠上）；另可用 `SetAsFirstSibling()` / `SetAsLastSibling()`。
- **复用列表生成的列表项不保证同级排序结果稳定**（API §13(2) 原文）。

## 7. 硬性禁止

- 不把通用矩形递归公式宣称为官方实现
- 不用假定 `1920×1080` 掩盖未取得画布尺寸
- 画布大小无效时**停止依赖该大小的布局**，保留明确原因；仅有已知异步依赖时有界重试
- 不根据 Unity / uGUI 或其他引擎经验补出沙箱未声明的坐标换算规则
- 几何是本地表现参数，关键玩法判定采用清晰状态/原生命中，不让新手靠反复真机校准替代算法边界

**来源文件**：`...\v3.1\prompts\60_坐标.md`；`...\v3.1\templates\13_输入适配_键鼠与移动端拖拽.lua`；`...\v3.1\docs\01_API阅读与防混淆.md`；API §6(1)、§13(1)(3)、§19

---

## 附：模板 → 模式对照（按目标挑文件）

| 想做什么 | 文件 | 主要入口 |
|---|---|---|
| 完整接入与排错 | `templates\01`–`08` | 五态、信号、单次/重复任务、按键、属性动画、序列、探针 |
| 两个画面状态切换 | `templates\12` | `PlayAction()` 或 E 键 |
| 按顺序显示动画帧 | `templates\09` | `PlayFrameState(name)` |
| 上下遮罩开合、UI 抖动 | `templates\11` | `PlayTransition()` / `PlayShake()` |
| 重复生成短特效 | `templates\10` | `SpawnEffect(x,y,lifetime)` |
| 键鼠、触屏、手柄移动图片 | `templates\13` | `IMAGE_NAME` / `CURSOR_AREA_NAME` + 坐标前提 |
| 播放编辑器配好的动效 | `templates\15` | `PlayAnimation()` / `StopAnimation()` |
| 预置四态按钮的点击 | `templates\14` | `AddCursorEventListener(CursorClick, ...)` |
| 网格背包、动态容量和拖拽预览 | `templates\16` | `itemPrefabIndex` + `RefreshItems` |
| 多文件拆分 | `templates\multifile\` | 入口 + `core/runtime` + `data/balance` + `ui/hud` |

新手路径：`docs\00_开始之前.md` → `docs\06_新手手写Lua模板.md`（含 47 行最小完整例子）→ `templates\README.md`。**一次只练一个主要目标，不要一次拼接多个模板，也不要照抄工程编号**（`templates\README.md`）。
