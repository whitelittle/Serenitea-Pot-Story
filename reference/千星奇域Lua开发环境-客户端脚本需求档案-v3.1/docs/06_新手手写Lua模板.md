# 新手手写 Lua：从一个效果开始

先在文本编辑器中写好文件，再按需要放进千星奇域编辑器。API 查 [正文](客户端控件API文档.md)，准备和挂载查 [开始之前](00_开始之前.md)。不必先完成真机验证才能继续写玩法。

## 1. 写一句动作说明

例如：“脚本启动后，图片在 0.2 秒内从当前位置向上移动 40；停用时取消；再次启用时等待下次调用。”分清对象、触发、效果、停止方式，这四件事决定代码结构。

## 2. 准备一个能找到的对象

本例在宿主下预建直接子控件 `图片`，由编辑器设置图片。若用户重命名，在下方 `CONFIG.NAME` 同步修改，也可让 Agent 代改；其他控件正式名称和配置位置见 [名称配置表](08_控件名称与CONFIG配置.md)。借用已有控件只需名字或路径，不必填写动态创建索引。需要动态创建时才查模板父节点资格并填写真实 `prefabIndex`。图片内容用 `imageSource` 与 `imageId`，获取方式见 [资产索引](02_图片资产ID索引.md)。

容器节点索引是选中【容器节点】读到的“容器索引”，用于脚本挂载；控件模板索引是【客户端控件模板】里打开模板后、控件名字下方的“控件索引”，用于创建模板实例和核对模板身份。已有实例优先按名称、路径、创建返回值或运行时 `id` 定位；运行时 `id`、图片 `imageId`、脚本映射 ID 也不能相互代用。

## 3. 手写最小完整例子

```lua
-- 前提：宿主下有直接子控件 图片，控件与父级已激活、可见。
local CONFIG = { NAME = "图片", DISTANCE = 40, SECONDS = 0.2 }
local image, tween, startY = nil, nil, nil
local enabled, ready = false, false

local function stop()
    if tween then tween:Kill(false); tween = nil end
end

function PlayMove()
    if not ready or not enabled or not image.alive then return false end
    stop()
    image.anchoredPositionY = startY -- 先设置起点
    tween = game.Tween(image, { anchoredPositionY = startY + CONFIG.DISTANCE }, CONFIG.SECONDS)
    tween:SetRelative(false) -- 明确使用绝对目标
    tween:SetEase(Enum.EaseType.OutCubic)
    tween:Play() -- 最后播放
    return true
end

function OnStart()
    if ready then return end
    script:EnableUpdate(false) -- 纯 Tween 不需要逐帧计时
    local host = script.object
    if not host or not host.alive then return end
    image = host:GetChild(CONFIG.NAME)
    if not image or not image.alive or not image.activeInHierarchy then
        printerr("[入门] 请准备已激活的 图片 子控件")
        return
    end
    startY = image.anchoredPositionY
    ready, enabled = true, true
    PlayMove()
end

function OnEnable() enabled = true end
function OnDisable()
    enabled = false
    stop()
end
function OnDestroy()
    OnDisable()
    if image and image.alive and startY ~= nil then image.anchoredPositionY = startY end
    image, ready = nil, false -- 借用的控件不销毁
end
```

把它另存为 `.lua` 并建立脚本映射即可继续接入。本例配置是固定教学值；修改成外部输入时，要加类型和范围检查：时长须为有限正数，距离须为有限数。其他脚本不能同时改这张图片的位置。

## 4. 一次只扩充一种能力

- 同时位移与缩放：把允许 Tween 的字段放在同一目标表；时长不同则分别创建 Tween，以 Sequence 的 `Append` 和 `Join` 组合。
- 先移动再缩放：把两条 Tween 依次 `Append`。等待用 `AppendInterval`，动作回调用 `AppendCallback`。
- 点击后播放：按文档登记输入回调，回调只调用 `PlayMove()`；停用时用同一函数引用注销。
- 连续帧图：按 `dt` 切换预建帧根，不是给 `imageId` 做 Tween。
- 状态切换：先列 Idle/Action 等有限状态，再定义进入、结束和中断条件；不必套五态框架。

教程来源提炼见 [动画知识](04_视频动画学习笔记.md)，扩展写法见 [复刻示例提炼](09_复刻示例提炼.md)。

## 5. 按需要选练习

| 目标 | 练习 |
|---|---|
| 两个状态切换 | `templates/12_状态动画_状态切换.lua` |
| 逐帧图像 | `templates/09_逐帧动画_配置与状态.lua` |
| 遮罩转场和抖动 | `templates/11_TweenSequence_遮罩转场与抖动.lua` |
| 多设备输入 | `templates/13_输入适配_键鼠与移动端拖拽.lua` |
| 特效复用 | `templates/10_特效复用_有界对象池.lua` |
| 更完整的挂载检查、信号、任务 | `templates/01–08` |

完整路径与使用条件见 [模板目录](../templates/README.md)。

## 6. 自己查六项

1. 外部 API 在正文中有完整定义；点号/冒号、类型、参数和返回值正确。
2. 引用不是 nil，操作时仍 alive；字段属于该控件且可写/可补间。
3. ID 有来源，不能用视频或样本数字代替工程配置。
4. 停用、重启、重复触发都有明确行为，同一字段只有一个写入者。
5. 借用资源不销毁；自建资源、监听、动画能清理，旧回调不能改新状态。
6. 分别报告文档依据、静态检查、模拟测试和实际观察，未真机运行也可交付。

排错查 [知识层级与 Debug](05_知识层级验证与Debug.md)。未知能力用已知能力替代，或仅暂停依赖它的部分，不把整套玩法变成新手的试玩任务。
