-- Work-light presentation only; original game owns all power consumption.
local M = {}

local MACHINE_ID = "PAE_ExchangePrototype"
local MODEL_CLASS = "/Script/Pal.PalMapObjectConvertItemModel"
local CONSTRUCTED_STATE_MIN = 3

local reported = {}
local visual_seen = {}

local function valid(object)
    if object == nil then return false end
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result == true
end

local function log(message)
    print("[AwakeningCrystalPower] " .. message .. "\n")
end

local function warn_once(key, message)
    if reported[key] then return end
    reported[key] = true
    log(message)
end

local function invoke(object, method, ...)
    if not valid(object) then return false, nil end
    return pcall(function(...) return object[method](object, ...) end, ...)
end

local function read(object, property)
    if not valid(object) then return false, nil end
    return pcall(function() return object[property] end)
end

local function unwrap(value)
    if value == nil then return nil end
    local ok_get, getter = pcall(function() return value.get end)
    if ok_get and type(getter) == "function" then
        local ok, result = pcall(getter, value)
        if ok then return result end
    end
    return value
end

local function fname(value)
    value = unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function() return value:ToString() end)
    if ok then return tostring(result) end
    return tostring(value)
end

local function model_key(model)
    local ok, result = invoke(model, "GetFullName")
    if ok and result ~= nil then return tostring(result) end
    return tostring(model)
end

local function own(model)
    if not valid(model) then return false end
    local ok_class, class_match = pcall(function() return model:IsA(MODEL_CLASS) end)
    if not ok_class or class_match ~= true then return false end
    local ok_id, id = invoke(model, "TryGetMapObjectId")
    return ok_id and fname(id) == MACHINE_ID
end

local function has_authority(actor, key)
    local ok, result = invoke(actor, "HasAuthority")
    if not ok then
        warn_once(key .. ":authority", key .. " HasAuthority unavailable; skipped")
        return false
    end
    return result == true
end

local function constructed(actor, key)
    local ok, state = read(actor, "CurrentState")
    state = unwrap(state)
    if not ok or type(state) ~= "number" then
        warn_once(key .. ":construction", key .. " construction state unavailable; skipped")
        return false
    end
    return state >= CONSTRUCTED_STATE_MIN
end

local function actor_of(model, key)
    local ok, actor = invoke(model, "GetActor")
    if not ok or not valid(actor) then
        warn_once(key .. ":actor", key .. " actor unavailable; skipped")
        return nil
    end
    if not has_authority(actor, key) then return nil end
    if not constructed(actor, key) then return nil end
    return actor
end

local function remain_num(model, key)
    local ok, value = invoke(model, "GetRemainCreateNum")
    value = unwrap(value)
    if not ok or type(value) ~= "number" then
        warn_once(key .. ":remain", key .. " GetRemainCreateNum unavailable; skipped")
        return nil
    end
    return value
end

local function refresh_visual(actor, working, powered, key)
    -- Visuals are optional and only touched when the visible state changes.
    -- A working glow requires both work and native CanConsumeEnergy().
    local visual_state = (working and powered) and "working" or "idle"
    if visual_seen[key] == visual_state then return end
    local component_class_ok, component_class = pcall(
        StaticFindObject, "/Script/Engine.StaticMeshComponent"
    )
    if not component_class_ok or not valid(component_class) then
        warn_once(key .. ":visual-class", key .. " StaticMeshComponent class unavailable")
        return
    end
    local asset_path = visual_state == "working"
        and "/Game/PalAwakeningExchange/Visual/PAE_ConversionWorking"
        or "/Game/PalAwakeningExchange/Visual/PAE_ConversionIdle"
    -- Both materials are hard-referenced by this actor's Blueprint.
    local asset_ok, material = pcall(StaticFindObject,
        asset_path .. "." .. asset_path:match("([^/]+)$"))
    if not asset_ok then material = nil end
    if not valid(material) then
        warn_once(key .. ":visual-asset:" .. visual_state, key .. " visual asset unavailable: " .. asset_path)
        return
    end
    local components_ok, components = invoke(actor, "K2_GetComponentsByClass", component_class)
    if not components_ok or components == nil then
        warn_once(key .. ":visual-components", key .. " StaticMesh components unavailable")
        return
    end
    local changed = false
    local function apply(component)
        component = unwrap(component)
        if valid(component) then
            local name_ok, name = invoke(component, "GetFullName")
            name = name_ok and tostring(name) or ""
            if name:find("PAE_ConversionGlow_", 1, true) then
                component:SetMaterial(0, material)
                changed = true
            end
        end
    end
    if type(components) == "table" then
        for _, component in pairs(components) do apply(component) end
    else
        components:ForEach(function(_, component) apply(component) end)
    end
    if changed then visual_seen[key] = visual_state end
end

local function refresh(model)
    if not own(model) then return end
    local key = model_key(model)
    local actor = actor_of(model, key)
    if not actor then return end
    local remain = remain_num(model, key)
    local ok, energy = invoke(model, "GetEnergyModule")
    if remain == nil or not ok or not valid(energy) then return end
    local power_ok, powered = invoke(energy, "CanConsumeEnergy")
    if power_ok then refresh_visual(actor, remain > 0, powered == true, key) end
end

-- Visual events only. Native BuildingData owns the fixed power rate.
-- No timers, global discovery, energy writes, or verification polling.
local function on_event(context)
    local ok, err = pcall(function() refresh(context:get()) end)
    if not ok then warn_once("event", "visual event: " .. tostring(err)) end
end
for _, event in ipairs({
    "ChangeRecipe_ServerInternal", "OnStartWorkAnyone_ServerInternal",
    "OnFinishWorkInServer", "Cancel_ServerInternal",
    "OnUpdateEnergyModuleState", "OnReadyStatusHUDModule",
    "OnRep_IsWorkable", "OnRep_RemainProductNum",
}) do
    local path = MODEL_CLASS .. ":" .. event
    local ok, fn = pcall(StaticFindObject, path)
    if ok and valid(fn) then RegisterHook(path, function() end, on_event) end
end
function M.reset_visuals() visual_seen = {} end
log("Native fixed power; event-driven work lights only")
return M
