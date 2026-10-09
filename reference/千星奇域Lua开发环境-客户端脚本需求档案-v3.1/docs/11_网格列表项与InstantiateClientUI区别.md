# 网格列表项与 `InstantiateClientUIControl` 的边界

这份短文用于处理一个常见混淆：普通客户端控件可以用 `game.InstantiateClientUIControl` 创建，但 `ClientUIGridScrollerControl` 的列表项要交给网格控件管理。

## 两条创建路径

| 目标 | 正确入口 | 生命周期负责人 | 典型用途 |
|---|---|---|---|
| 网格中的第 0、1、2 … 项 | 先设置 `grid.itemPrefabIndex`，再调用 `grid:RefreshItems(count, callback)` | `ClientUIGridScrollerControl` | 背包、商店、滚动列表、虚拟化复用 |
| 网格外的普通控件 | `game.InstantiateClientUIControl(controlPrefabIndex, parent)` | 当前脚本 | 面板、独立图片、文字框、按钮、拖拽幽灵 |

`RefreshItems` 的回调是 `function(control, index)`。在回调中读取列表项的直接子控件（简体中文预设通常是“图片”“文本框”“光标检测区域”），更新文字、图片和事件；需要确认索引时使用 `grid:GetItemIndex(control)`。不要用 `GetChild` 找到的普通实例去伪装成列表项。

## 为什么不能用普通实例“塞进”网格

`InstantiateClientUIControl` 创建的是 `parent` 下的普通子控件。即使 `parent` 看起来是网格或网格的父容器，创建出的控件也不会自动加入网格的虚拟化列表，因而不能可靠参与：

- `RefreshItems` 的回调；
- `GetItemIndex` 的索引映射；
- 网格的滚动、布局和复用；
- 网格自身的列表项销毁与重建。

把普通实例硬塞到网格层级还可能造成重复显示、点击区域重叠和清理时误删宿主控件。列表项模板必须先在“界面控件组管理”中保存为可实例化的模板父节点；模板内部的“图片”“文本框”“光标检测区域”作为子树随列表项一起生成。

## 网格背包的最小顺序

```lua
-- CONFIG.ITEM_PREFAB_INDEX 来自“界面控件组管理”保存后的模板索引。
grid.itemPrefabIndex = CONFIG.ITEM_PREFAB_INDEX

grid:RefreshItems(CONFIG.CAPACITY, function(item, runtimeIndex)
    local logicalSlot = runtimeIndex - runtimeBase + 1
    local image = item:GetChild("图片")
    local text = item:GetChild("文本框")
    local area = item:GetChild("光标检测区域")
    -- 校验类型、alive、activeInHierarchy、raycastTarget 后再写入和监听。
end)
```

真实索引必须以回调的 `runtimeIndex` 和 `GetItemIndex` 为准；不要猜测索引从 0 还是 1 开始。若回调没有出现，先检查 UI 树加载时序、模板是否已登记、`itemPrefabIndex` 是否是模板父节点索引；不要把 `InstantiateClientUIControl` 当成网格回调的替代品。

## 何时使用 `InstantiateClientUIControl`

本地背包交互实现用它创建面板背景、文本框、独立图片和拖拽中的幽灵图片。这些控件不由网格管理，脚本创建后要登记所有权，并在停用或销毁时调用 `game.DestroyClientUIControl`。如果要让拖拽图标跟随光标，可以复制图片模板为独立幽灵；不要移动网格管理的列表项自身。

## 证据与排错

接口事实以 [客户端控件API文档](客户端控件API文档.md) §6 和 §20 为准：§6 说明 `InstantiateClientUIControl` 创建普通子控件，§20 说明 `itemPrefabIndex`、`RefreshItems` 与 `GetItemIndex`。官方指南还规定：只有保存的模板父节点支持动态创建，主屏节点和模板内部子节点不能单独动态创建。

网格示例应打印以下证据：

1. 根容器、网格的 `alive`、`activeInHierarchy` 和 `typeof`；
2. 写入后读回的 `itemPrefabIndex`；
3. 每次 `RefreshItems` 回调的 `runtimeIndex`、`GetItemIndex` 和列表项 `typeof`；
4. 回调未出现时，停止猜索引并报告模板登记/加载时序问题。

列表项模板的索引由当前工程产生，本包不给出示例数值。它来自你在【界面控件组管理】里保存为模板的那个父节点，另存模板后必须重新读取并更新 `CONFIG`；容器实例的索引不能因为名称相同就当模板索引。
