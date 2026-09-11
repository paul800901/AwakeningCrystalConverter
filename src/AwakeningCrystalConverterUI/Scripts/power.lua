-- Optional native EnergyModule rate probe for the single converter.
-- Load with: local power = require("power")  -- starts once
-- This is deliberately independent from main.lua.
local M = {}

local MACHINE_ID = "PAE_ExchangePrototype"
local MODEL_CLASS = "/Script/Pal.PalMapObjectConvertItemModel"
local ENERGY_CLASS = "/Script/Pal.PalMapObjectEnergyModule"
local REFRESH_MS = 100
local DISCOVERY_TICKS = 10
local IDLE_RATE = 36000.0
local WORKING_RATE = 576000.0
local CONSTRUCTED_STATE_MIN = 3

local running = false
local loop_handle = nil
local discover_countdown = 0
local models = {}
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

local function write_energy(module, rate, key)
    if not valid(module) then
        warn_once(key .. ":module", key .. " EnergyModule unavailable; no module created")
        return false, false
    end
    local ok_class, class_match = pcall(function() return module:IsA(ENERGY_CLASS) end)
    if not ok_class or class_match ~= true then
        warn_once(key .. ":module-class", key .. " returned a non-EnergyModule; skipped")
        return false, false
    end

    local ok_write, write_error = pcall(function()
        module.ConsumeEnergySpeed = rate
        module.CurrentConsumeEnergySpeed = rate
        module.bRequiredConsumeEnergy = true
    end)
    if not ok_write then
        warn_once(key .. ":write", key .. " EnergyModule property write failed: " .. tostring(write_error))
        return false, false
    end

    local ok_power, powered = invoke(module, "CanConsumeEnergy")
    if not ok_power then
        warn_once(key .. ":can-consume", key .. " CanConsumeEnergy unavailable after write")
        powered = false
    end

    local ok_current, current = invoke(module, "GetCurrentConsumeEnergySpeed")
    current = unwrap(current)
    local ok_base, base = invoke(module, "GetConsumeEnergySpeed")
    base = unwrap(base)
    local ok_required, required = invoke(module, "IsRequiredEnergy")
    required = unwrap(required)
    if not (ok_current and ok_base and ok_required)
        or type(current) ~= "number"
        or type(base) ~= "number"
        or current ~= rate
        or base ~= rate
        or required ~= true then
        warn_once(key .. ":readback", key .. " EnergyModule readback mismatch")
        return false, powered == true
    end
    return true, powered == true
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
    local key = model_key(model)
    if not own(model) then return end
    local actor = actor_of(model, key)
    if not actor then return end
    local remain = remain_num(model, key)
    if remain == nil then return end

    local ok_module, module = invoke(model, "GetEnergyModule")
    if not ok_module or not valid(module) then
        warn_once(key .. ":module", key .. " EnergyModule unavailable; no module created")
        return
    end
    local working = remain > 0
    local rate = working and WORKING_RATE or IDLE_RATE
    local wrote, powered = write_energy(module, rate, key)
    if not wrote then return end
    local state = tostring(rate) .. ":" .. tostring(powered)
    local state_key = key .. ":state"
    if reported[state_key] ~= state then
        reported[state_key] = state
        log("STATE id=" .. MACHINE_ID
            .. " remain=" .. tostring(remain)
            .. " rate=" .. tostring(rate)
            .. " powered=" .. tostring(powered)
            .. " fields=readback")
    end
    refresh_visual(actor, working, powered, key)
end

local function discover()
    local ok, found = pcall(FindAllOf, "PalMapObjectConvertItemModel")
    if not ok then
        warn_once("discover", "FindAllOf PalMapObjectConvertItemModel unavailable")
        return
    end
    if type(found) == "table" then
        for _, model in pairs(found) do
            if own(model) then models[model_key(model)] = model end
        end
    elseif found ~= nil then
        warn_once("discover-shape", "FindAllOf PalMapObjectConvertItemModel returned an unexpected value")
        return
    end
    for key, model in pairs(models) do
        if not valid(model) then models[key] = nil end
    end
end

local function tick()
    if not running then return end
    discover_countdown = discover_countdown - 1
    if discover_countdown <= 0 then
        discover_countdown = DISCOVERY_TICKS
        discover()
    end
    for key, model in pairs(models) do
        local ok, err = pcall(refresh, model)
        if not ok then warn_once(key .. ":refresh", key .. " refresh disabled after error: " .. tostring(err)) end
    end
end

local function register_refresh_hooks()
    local paths = {
        "/Script/Pal.PalMapObjectConvertItemModel:ChangeRecipe_ServerInternal",
        "/Script/Pal.PalMapObjectConvertItemModel:OnStartWorkAnyone_ServerInternal",
        "/Script/Pal.PalMapObjectConvertItemModel:OnFinishWorkInServer",
        "/Script/Pal.PalMapObjectConvertItemModel:Cancel_ServerInternal",
    }
    for _, path in ipairs(paths) do
        local ok_exists, fn = pcall(StaticFindObject, path)
        if ok_exists and valid(fn) then
            local ok_hook = pcall(RegisterHook, path, function() end, function(context)
                local model = context:get()
                if own(model) then
                    models[model_key(model)] = model
                    pcall(refresh, model)
                end
            end)
            if not ok_hook then warn_once("hook:" .. path, "refresh hook unavailable: " .. path) end
        end
    end
end

function M.start()
    if running then return true end
    if type(LoopInGameThreadWithDelay) ~= "function" then
        log("LoopInGameThreadWithDelay unavailable; power probe not started")
        return false
    end
    running = true
    discover_countdown = 0
    register_refresh_hooks()
    local ok, handle = pcall(LoopInGameThreadWithDelay, REFRESH_MS, function()
        -- UE4SS executes this delayed callback on the game thread.
        local done, err = pcall(tick)
        if not done then warn_once("tick", "tick failed: " .. tostring(err)) end
    end)
    if not ok then
        running = false
        log("power probe timer failed: " .. tostring(handle))
        return false
    end
    loop_handle = handle
    log("START id=" .. MACHINE_ID .. " refresh=100ms discover=1000ms idle=36000 working=576000")
    return true
end

function M.stop()
    running = false
    if loop_handle ~= nil and type(CancelDelayedAction) == "function" then
        pcall(CancelDelayedAction, loop_handle)
    end
    loop_handle = nil
    models = {}
    visual_seen = {}
end

function M.refresh_now()
    local ok, err = pcall(function()
        discover()
        for _, model in pairs(models) do refresh(model) end
    end)
    return ok, err
end

function M.reset_visuals()
    visual_seen = {}
end

M.start()
return M
