# 卡牌 Tween 演出配方

来源编号：`REF-CARD`；接口依据：`REF-API`。

> 本文是独立的表现层参考，只讲如何用 `Tween` / `TweenSequence` 编排卡牌移动、缩放、旋转、淡入淡出和入场演出。
>
> 不包含服务器信号、卡牌数据结构、输入处理、控件实例化、图片资产 ID 或项目目录。把示例中的 `card`、`mask`、坐标和时长替换成自己的对象即可。

## 1. 证据边界

| 标记 | 含义 |
|---|---|
| `documented` | `docs/客户端控件API文档.md` 明确写出的签名、字段或方法。 |
| `provided_unverified` | 来自现成存档中的 Lua 静态样本；这里没有把它当成真机通过。 |
| `inferred` | 从文档和样本抽出的通用编排方式，使用前仍应按自己的控件结构检查。 |
| `unknown` | API 文档没有说明，本文不为它补充结论。 |

## 2. 能做什么

### 2.1 Tween 的最小模型（`documented`）

```lua
local tween = game.Tween(target, {
    anchoredPositionX = targetX,
    anchoredPositionY = targetY,
}, durationSeconds)

tween:SetEase(Enum.EaseType.OutCubic)
tween:Play()
```

`game.Tween(object, tweenDataTable, duration)` 的目标字段必须是文档列出的 Tweenable 字段。卡牌常用字段是：

- `anchoredPositionX/Y`：位移；
- `localScaleX/Y/Z`：缩放；
- `localRotationX/Y/Z`：旋转；
- 图片的 `imageColor`、`fillAmount`；
- 文本框的 `fontSize`、`fontColor`、`bgColor`、`outlineColor`、`minimumFontSize`。

`text`、`interactable` 等读写字段按 API 直接赋值；`active`、`visible`、`imageId` 为只读字段，分别使用文档声明的 `SetActive`、`SetVisible`、`SetImage`。这些都不能放进 Tween 表（`documented`）。

### 2.2 绝对目标优先（`inferred`）

卡牌手牌刷新通常有明确的最终位姿，因此每次刷新都用绝对目标值：

```lua
local pose = {
    x = 120,
    y = -40,
    scale = 0.92,
    rotZ = -4,
}
```

只有“在当前值上再偏移一段距离”才使用 `SetRelative(true)`。循环演出尽量不要对位置使用相对值，否则每一轮都可能累积漂移（`inferred`）。

## 3. 单张卡牌的位移动效

### 3.1 重新播放前先停旧动画（`provided_unverified` → `inferred`）

同一张卡牌的布局、悬停、入场可能在短时间内连续触发。样本以 `slotIndex`（这里仅作抽象键）保存 Tween 列表，开始新演出前先全部 `Kill(false)`，再清空列表。这样不会让两条动画同时改同一组字段。

```lua
local activeByCard = {}

local function KillCardTweens(cardKey)
    local list = activeByCard[cardKey]
    if list == nil then return end
    for i = #list, 1, -1 do
        local tween = list[i]
        list[i] = nil
        if tween ~= nil then
            pcall(function() tween:Kill(false) end)
        end
    end
end

local function TrackCardTween(cardKey, tween)
    if tween == nil then return end
    activeByCard[cardKey] = activeByCard[cardKey] or {}
    table.insert(activeByCard[cardKey], tween)
end
```

`Tween:Kill(false)` 的含义是停止并保留当前状态，不触发完成回调（`documented`）。样本中的“每卡一组”属于表现层管理策略，不是 API 强制要求（`provided_unverified`）。

### 3.2 移动、缩放、旋转同时到达（`provided_unverified`）

样本将三条 Tween 放进一个序列：第一条用 `Append`，其余用 `Join`。序列结束时再用回调把旋转写成最终值，避免角度小数残留。

```lua
-- 约定：cardControl 是客户端控件对象（数据对象见 §4.1 的 cardData.control）；
-- 全篇的 Tween 和控件方法都只接收控件对象，不接收卡牌数据对象。
local function TweenCardTo(cardKey, cardControl, pose, duration, easeType, onComplete)
    if cardControl == nil or not cardControl.alive or pose == nil then return nil end

    KillCardTweens(cardKey)

    local ease = easeType or Enum.EaseType.OutCubic
    local seq = game.TweenSequence()

    local moveTween = game.Tween(cardControl, {
        anchoredPositionX = pose.x,
        anchoredPositionY = pose.y,
    }, duration)
    moveTween:SetEase(ease)

    local scale = pose.scale or 1
    local scaleTween = game.Tween(cardControl, {
        localScaleX = scale,
        localScaleY = scale,
        localScaleZ = pose.scaleZ or 1,
    }, duration)
    scaleTween:SetEase(ease)

    seq:Append(moveTween)
    seq:Join(scaleTween)

    if type(pose.rotZ) == "number" then
        local rotateTween = game.Tween(cardControl, {
            localRotationX = pose.rotX or 0,
            localRotationY = pose.rotY or 0,
            localRotationZ = pose.rotZ,
        }, duration)
        rotateTween:SetEase(ease)
        seq:Join(rotateTween)
        seq:AppendCallback(function()
            if cardControl.alive then
                pcall(function() cardControl:SetLocalRotation(pose.rotX or 0, pose.rotY or 0, pose.rotZ or 0) end)
            end
        end)
    end

    if onComplete ~= nil then
        seq:AppendCallback(function()
            if cardControl.alive then onComplete() end
        end)
    end

    TrackCardTween(cardKey, seq)
    seq:Play()
    return seq
end
```

`Append` 把步骤接到序列末尾；`Join` 与当前队尾步骤并行；`AppendCallback` 在队列位置执行（`documented`）。这里的“先移动、同时缩放和旋转”来自存档样本（`provided_unverified`），可以按演出需要删掉任一通道。

## 4. 手牌刷新与新卡入场

### 4.1 先确定最终位姿，再决定是否演出（`inferred`）

刷新时为每张卡计算一个最终 `pose`，并区分“新出现的卡”和“已经存在的卡”：

```lua
for _, cardData in ipairs(cards) do
    local cardControl = cardData.control
    local pose = cardData.finalPose
    if cardControl ~= nil and cardControl.alive and pose ~= nil then
        if cardData.isNew then
            -- 先放到最终位置外，再用 Tween 拉入
            cardControl:SetAnchoredPosition(cardData.spawnX, cardData.spawnY)
            TweenCardTo(cardData.key, cardControl, pose, 0.22, Enum.EaseType.OutCubic)
        else
            -- 普通刷新直接落位，避免每帧重复播放
            KillCardTweens(cardData.key)
            cardControl:SetAnchoredPosition(pose.x, pose.y)
            cardControl:SetLocalScale(pose.scale, pose.scale, pose.scaleZ or 1)
            cardControl:SetLocalRotation(pose.rotX or 0, pose.rotY or 0, pose.rotZ or 0)
        end
    end
end
```

这里约定 `cardData` 是卡牌数据对象，`cardData.control` 才是客户端控件对象；Tween 和控件方法始终接收后者。

样本采用“最后一张卡的目标位置 + 一个横向间距”作为新卡出生点，然后把新卡 Tween 到目标位姿（`provided_unverified`）。出生偏移和 `0.22` 秒只是样本参数，不是通用默认值。

### 4.2 入场遮罩：停留后淡出（`provided_unverified`）

卡牌加入时可以先显示一层颜色遮罩，短暂保持，再把 `imageColor` 的 alpha Tween 到 0。`imageColor` 是 Tweenable；颜色通道范围是 0–255（`documented`）。

```lua
local function PlayJoinMask(mask, holdSeconds, fadeSeconds)
    if mask == nil or not mask.alive then return nil end

    mask.imageColor = Color.FromRGBA(40, 130, 255, 220)
    mask:SetVisible(true)

    local seq = game.TweenSequence()
    seq:AppendInterval(holdSeconds)

    local fade = game.Tween(mask, {
        imageColor = Color.FromRGBA(40, 130, 255, 0),
    }, fadeSeconds)
    fade:SetEase(Enum.EaseType.OutCubic)
    seq:Append(fade)

    seq:AppendCallback(function()
        if mask.alive then
            -- 结束后的业务状态由调用方决定；这里仅示范回调时机。
            mask:SetVisible(false)
        end
    end)
    seq:Play()
    return seq
end
```

样本在遮罩演出期间设置一个“正在播放”标志，让普通遮罩刷新暂时跳过该卡，结束回调再恢复刷新（`provided_unverified`）。这属于状态协调，不是 Tween API 的隐含行为；如果项目有刷新逻辑，应显式加守卫。

## 5. 其他常见卡牌演出

### 5.1 预览卡从下方进入（`provided_unverified`）

1. 读取当前 `anchoredPosition`；
2. 直接把 Y 减去入场偏移；
3. 另行设置初始颜色；
4. 用 `Tween` 把 Y 移回目标值；
5. 用 `AppendCallback` 做结束处理。

```lua
local cardControl = cardData.control          -- 控件对象；cardData 是卡牌数据对象
local offsetY, duration, onEnterFinished = entryOffsetY, 0.22, nil
if cardControl == nil or not cardControl.alive then return end
local x, y = cardControl:GetAnchoredPosition()
cardControl:SetAnchoredPosition(x, y - offsetY)

local seq = game.TweenSequence()
local move = game.Tween(cardControl, { anchoredPositionY = y }, duration)
move:SetEase(Enum.EaseType.OutCubic)
seq:Append(move)
seq:AppendCallback(function()
    if cardControl.alive and onEnterFinished ~= nil then
        onEnterFinished()
    end
end)
seq:Play()
```

### 5.2 结算时把卡牌形象移到目标区（`provided_unverified`）

样本把“淡出原卡”和“移动独立的卡牌形象控件”分开；移动使用 `InOutSine`，到达后再结束本次表现。不要在 Tween 完成回调里重复发送玩法信号，信号应由玩法状态层负责（后半句属于工程约束，不在本文范围）。

```lua
local seq = game.TweenSequence()
local move = game.Tween(effectControl, {
    anchoredPositionX = targetX,
    anchoredPositionY = targetY,
}, duration)
move:SetEase(Enum.EaseType.InOutSine)
seq:Append(move)
seq:AppendCallback(function()
    if effectControl.alive and onArrived ~= nil then onArrived() end
end)
seq:Play()
```

### 5.3 文本的“淡出”（`provided_unverified`）

文本内容本身不是 Tweenable。样本对 `fontColor`、`bgColor` 和 `outlineColor` 做颜色 Tween，同时用少量 `InsertCallback` 分段改富文本颜色标签的 alpha。新手可先只 Tween `fontColor`，不要把 `text` 塞进 Tween 表。

```lua
local seq = game.TweenSequence()
seq:Append(game.Tween(textBox, {
    fontColor = Color.FromRGBA(255, 255, 255, 0),
}, duration))
for step = 0, 6 do
    local ratio = step / 6
    seq:InsertCallback(duration * ratio, function()
        if textBox.alive then
            -- 这里直接写 text；具体富文本格式由项目自行定义。
            textBox.text = BuildTextWithAlpha(ratio)
        end
    end)
end
seq:Play()
```

## 6. 停止、替换与清理

- 同一控件同一字段的演出，启动下一条前先停上一条；按卡牌或演出槽位分组管理（`inferred`）。
- 需要取消时使用 `Kill(false)`；不要用 `Kill(true)` 取消入场，因为 `true` 会先完成目标并触发完成回调（`documented`）。
- 完成回调开头检查控件仍然 `alive`，并检查演出是否仍属于当前卡牌（`inferred`）。
- 在脚本销毁或页面离开时，遍历仍保存的 Tween/Sequence 并 `Kill(false)`；这是资源管理策略，不是 Tween 自动保证（`inferred`）。
- `SetLoops(-1)` 适合呼吸、旋转等持续表现；无限循环没有自然完成回调（`documented` + `inferred`）。
- 不要同时让 Tween 和逐帧逻辑写同一个字段；若确实需要逐帧控制，应先停该字段上的 Tween（`inferred`）。

## 7. 新手自检清单

1. `game.Tween` 的目标字段是否在 API 文档的 Tweenable 列表中？
2. `Append` 和 `Join` 的先后是否与想要的时间轴一致？
3. 新卡是否先设置出生位姿，再开始入场 Tween？
4. 同一张卡再次布局时，旧 Tween 是否已 `Kill(false)` 并清空记录？
5. 完成回调是否检查 `alive`，取消时是否不会误触发？
6. 颜色是否通过 `Color.FromRGBA` 构造，alpha 是否在 0–255？
7. 退出或销毁时是否能停掉仍在运行的 Tween？

## 8. 明确不包含的内容

本文不决定控件模板索引、运行时 ID、图片资产 ID、容器节点、服务器信号、卡牌数据、拖拽输入、坐标换算、`require` 路径或真机验收。需要这些能力时，回到入口 `AGENT.md`，按路由阅读对应分册和 API 文档。


