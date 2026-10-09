# 调试：typeof、控件树、traceback

排错时最先要用的三个全局能力，在 API 正文 §3 里，但前面几册没展开。这里补上用法。

## 1. 三个能力分别干什么

| 能力 | 签名 | 用途 |
|---|---|---|
| `typeof(value)` | `-> string` | 返回运行时类型名称；用来确认手上这个对象到底是什么 |
| `game.PrintClientUITree()` | `-> —` | 把当前客户端控件树按父子层级写进日志 |
| `debug.traceback([message[, level]])` | `-> string` | 生成调用栈文本；**只返回字符串，不自动写日志** |

`printerr(...)` 写错误级别日志且不抛错、不终止执行，配合上面三个用。

## 2. 按顺序排错

```
① 脚本被加载了吗      → 文件顶部 print；再看 script.path / script.alive / script.object
② 挂载对象对不对      → typeof(script.object) 是什么；归一化短名与期望是否一致
③ 控件找得到吗        → game.PrintClientUITree() 看整棵树，再按名称或路径找
④ 生命周期走到哪一步  → 每个回调进来先打一行
⑤ 逐帧在走吗          → 前几帧打 dt 与状态，之后改心跳
⑥ 值有没有生效        → 写进去后立刻读回来对比
⑦ 报错原文是什么      → pcall 包住可疑调用，把 err 打出来
```

每一步只回答一个问题。卡在哪一步就先修那一步，不要跳到后面。

## 3. `typeof` 怎么用

```lua
print("host typeof =", typeof(script.object))     -- 确认宿主是容器节点还是别的控件
print("image typeof =", typeof(image))            -- 确认取到的是图片控件而不是 nil
```

用途：

- **区分"取到 nil"和"取到别的控件"**：`GetChild` 按名称查找，名字写错会返回 nil，名字撞上别的控件却会返回一个**类型不对**的对象。`typeof` 是分辨这两种情况的直接手段。
- **确认 subtype 再写专用字段**：给图片控件写 `imageColor` 之前，先确认它确实是图片控件。
- 关键判断：`if typeof(c) == "ClientUIImageControl" then ... end` 这类按类型分支，比只看字段在不在更可靠。

## 4. `game.PrintClientUITree()` 怎么用

```lua
game.PrintClientUITree()
```

它会打印整棵树的层级关系与每个控件的标识信息。**这是排查 ID 错配的第一手段**：

- 界面"什么都没显示"时，先看树里到底有没有这个控件；
- 名称查找失败时，从树里抄真实名称（编辑器里显示的名字可能与你在 CONFIG 里写的不一致）；
- 层级不确定时，看目标控件挂在谁下面，`GetChild`（只查直接子级）和 `FindChild`（按相对路径）的区别立刻看得出。

建议在启动流程里**可选**调用一次，并放在 `CONFIG.VERBOSE` 开关后面，交付时能整体关掉。

## 5. `debug.traceback` 怎么用

```lua
local ok, err = pcall(function() risky() end)
if not ok then
    local tb = "<不可用>"
    local okT, tr = pcall(function() return debug.traceback("", 2) end)
    if okT and tr ~= nil then tb = tostring(tr) end
    printerr("[故障] " .. tostring(err) .. "\n" .. tb)
end
```

要点：

- 它**只返回文本**，要自己 `print` / `printerr` 出来；
- 参数 `level` 决定从哪一层开始记，包在 `pcall` 里用时给 `2` 比较合适；
- 它本身也可能失败，所以外面再套一层 `pcall`，取不到就写"不可用"，**不要省略这一行**。

## 6. 日志纪律

| 规则 | 做法 |
|---|---|
| 分级 | 普通信息走 `print`；错误走 `printerr` |
| 一次性 | 同一条日志只打一次，用 `seen` 表去重 |
| 不刷屏 | 逐帧日志只打前几帧，之后改心跳（每 N 帧一条）或只在状态变化时打 |
| 带前缀 | 每条日志带脚本短名或骨架标识，多脚本同时跑时才分得清 |
| 开关化 | 调试输出挂在 `CONFIG.VERBOSE` 上 |
| 可回收 | 临时探针集中写在一处，注明"定位完删掉" |

故障只输出**一个**连续块，用固定首尾包住，便于整段复制（字段集以 [05 知识层级验证与 Debug](05_知识层级验证与Debug.md) §5 为准）：

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

## 7. 探针规则

- 一次只验一件事；想问第二件事就另起一个探针。
- 只用文档里已经写明的接口，不夹带玩法逻辑。
- 能一键关掉，定位完就删。
- 查控件身份与变换的三组东西：`typeof` / `prefabIndex` / `id` / `alive`；`parent` / `GetChildren` / `GetSiblingIndex`；`GetAnchoredPosition` / `GetSizeDelta` / `GetLocalScale` / `GetLocalRotation`。

可直接用的调试骨架见 [08 调试探针](../templates/08_调试_日志与控件探针.lua)，里面已经实现了日志去重、控件树转储和控件探针。

## 8. 别做的事

- 不靠多打点看运气找问题；先想清楚这一条要证伪什么假设。
- 不把 `print` 当控制流用。
- 不把调试探针留在交付版本里。
- 不给每个 getter/setter 都套 `pcall`——只包**可能出错且你关心错误原文**的调用。
