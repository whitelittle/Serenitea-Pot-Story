-- 10 有界对象池：重复播放短暂的上浮淡出效果，最多创建 CAPACITY 个图片。
-- API 依据：docs/客户端控件API文档.md §1、§2、§4、§5、§6、§13、§14。
-- 本脚本拥有自己创建的控件；停用/销毁时销毁全部实例，再启用时按需重新创建。
-- 选择不带其他脚本的图片模板，模板内配置图像；无任何来自参考存档的资产 ID。

local CONFIG = {
    IMAGE_PREFAB_INDEX = nil, -- 必填：本项目的图片控件模板索引
    CAPACITY = 8, -- 池满时跳过新效果，不增加容量，也不打断已有效果
    DEFAULT_LIFETIME = 0.6,
    RISE_DISTANCE = 40,
    SIZE_X = 48,
    SIZE_Y = 48,
    COLOR_R = 255,
    COLOR_G = 255,
    COLOR_B = 255,
}

local host = nil
local pool = {}
local ready, enabled = false, false

local function finite(value)
    return type(value) == "number" and not math.isnan(value) and not math.isinf(value)
end

local function positive(value)
    return finite(value) and value > 0
end

local function validateConfig()
    local index = CONFIG.IMAGE_PREFAB_INDEX
    if not positive(index) or index % 1 ~= 0 then return false, "IMAGE_PREFAB_INDEX 必须是正整数" end
    if not positive(CONFIG.CAPACITY) or CONFIG.CAPACITY % 1 ~= 0 then return false, "CAPACITY 必须是正整数" end
    if not positive(CONFIG.DEFAULT_LIFETIME) then return false, "DEFAULT_LIFETIME 必须大于 0" end
    if not positive(CONFIG.SIZE_X) or not positive(CONFIG.SIZE_Y) then return false, "尺寸必须大于 0" end
    if not finite(CONFIG.RISE_DISTANCE) then return false, "RISE_DISTANCE 必须是有限数" end
    for _, key in ipairs({ "COLOR_R", "COLOR_G", "COLOR_B" }) do
        local color = CONFIG[key] -- 遍历字段名，避免 nil 让 ipairs 提前结束
        if not finite(color) or color < 0 or color > 255 then return false, "颜色必须在 0–255 范围内" end
    end
    return true
end

local function setColor(control, alpha)
    control.imageColor = Color.FromRGBA(CONFIG.COLOR_R, CONFIG.COLOR_G, CONFIG.COLOR_B, alpha)
end

-- 每次借出前重置本脚本会修改的全部表现属性，避免上一次效果残留。
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

local function acquire()
    -- 删除已被外部销毁的引用；池容量按实际存活实例计算。
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

-- 例：同一脚本事件逻辑中调用 SpawnEffect(120, 60)。返回 false 表示本次没有生成。
-- 从其他脚本调用时可用 Script:Invoke("SpawnEffect", x, y, lifetime)。
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

local function clearPool()
    for _, entry in ipairs(pool) do
        if entry.control.alive then
            pcall(function() game.DestroyClientUIControl(entry.control) end)
        end
    end
    pool = {}
    script:EnableUpdate(false)
end

function OnStart()
    script:EnableUpdate(false)
    local ok, message = validateConfig()
    if not ok then printerr("[10] " .. message); return end
    host = script.object
    if host == nil or not host.alive then printerr("[10] 请挂载到存活的客户端控件"); return end
    ready, enabled = true, true
    script:EnableUpdate(false) -- 没有活动效果时不需要逐帧更新
end

function OnEnable()
    enabled = true
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
                if progress >= 1 then
                    release(entry)
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

function OnDisable()
    enabled = false
    clearPool()
end

function OnDestroy()
    enabled, ready = false, false
    clearPool()
    host = nil
end
