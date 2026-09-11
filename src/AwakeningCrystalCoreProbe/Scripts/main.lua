-- Containment feasibility only. Native DisplayCharacter owns movement,
-- persistence, withdrawal and disposal; no slot/handle/save/SAN writes here.
local VERSION = "0.4.1-containment-test"
local MACHINE_ID = "PAE_ContainmentProbe"
local MODEL = "/Script/Pal.PalMapObjectDisplayCharacterModel"
local MENU = "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/WBP_IngameMenu_CommonCharacterContainer.WBP_IngameMenu_CommonCharacterContainer_C"
local ELECTRICITY = 4 -- EPalWorkSuitability.GenerateElectricity, game 1.0.4
local menus = {}
local menu_hook_ready = false

local function valid(object) return object ~= nil and object:IsValid() end
local function log(message) print("[AwakeningCrystalCore] " .. message .. "\n") end
local function guarded(label, fn)
    local ok, result = pcall(fn)
    if not ok then log(label .. " failed: " .. tostring(result)) end
    return ok, result
end
local function own(model)
    return valid(model) and model:IsA(MODEL)
        and model:TryGetMapObjectId():ToString() == MACHINE_ID
end
local function parameter(slot)
    if not valid(slot) or slot:IsEmpty() then return end
    local handle = slot:GetHandle()
    if valid(handle) then
        local result = handle:TryGetIndividualParameter()
        if valid(result) then return result end
    end
    -- Clients may have the replicated parameter before a local handle exists.
    local result = slot.ReplicateIndividualParameter
    if valid(result) then return result end
end
local function rank(slot)
    local value = parameter(slot)
    if not value then return 0 end
    return value:GetWorkSuitabilityRankWithCharacterRank(ELECTRICITY)
end
local function guid(value)
    return string.format("%08x-%08x-%08x-%08x",
        value.A & 0xffffffff, value.B & 0xffffffff,
        value.C & 0xffffffff, value.D & 0xffffffff)
end
local function snapshot(model, reason)
    local module = model:GetCharacterContainerModule()
    if not valid(module) or not module:IsCompleteSetup() then
        return "原生容器準備中 / Preparing container"
    end
    local container = module:GetContainer()
    assert(valid(container), "native character container unavailable")
    assert(container:Num() == 1, "native container is not single-slot")
    local slot = container:Get(0)
    assert(valid(slot), "native slot unavailable")
    local pal = parameter(slot)
    local label
    if not pal then
        label = "封裝測試：空槽，請選一隻發電帕魯 / Empty core"
    else
        local level = rank(slot)
        label = level > 0
            and ("封裝測試：發電適應性 Lv." .. level .. "｜尚未連接兌換 / Not connected")
            or "此帕魯沒有發電適應性，請取回 / No electricity suitability"
    end
    log(reason .. " model=" .. guid(model:GetModelInstanceId())
        .. " container=" .. guid(module:GetContainerId().ID)
        .. " slots=" .. container:Num()
        .. " occupied=" .. (pal and "1" or "0")
        .. (pal and (" pal=" .. pal:GetCharacterID():ToString()
            .. " individual=" .. guid(pal.IndividualId.InstanceId)
            .. " electricity=" .. rank(slot) .. " san=" .. pal:GetSanityValue()
            .. " hunger_rate=" .. pal:HungerParameterRate()) or ""))
    return label
end
local function refresh(model, reason)
    local label = snapshot(model, reason)
    for key, entry in pairs(menus) do
        if not valid(entry.menu) then
            menus[key] = nil
        elseif entry.active and entry.model:GetFullName() == model:GetFullName() then
            entry.menu.MapObjectTitle:SetText(FText(label))
        end
    end
end

-- Keep native restrictions as well. Returning nil preserves the native result;
-- false only narrows eligibility for this test building's ordinary UI.
RegisterHook(MODEL .. ":CanMoveSlotToDisplayCage", function() end,
    function(context, original_result, slot_param)
        if not own(context:get()) then return end
        -- UE4SS 2281 native post hooks insert the original return value before
        -- fromSlot. A native rejection must not be turned into permission.
        if not original_result:get() then return end
        local ok, level = guarded("eligibility", function() return rank(slot_param:get()) end)
        if not ok or level <= 0 then return false end
    end)

RegisterHook(MODEL .. ":TryMoveToDisplayCage", function(context, slot_param)
    if not own(context:get()) then return end
    local ok, level = guarded("move eligibility", function() return rank(slot_param:get()) end)
    if not ok or level <= 0 then
        -- The inspected native function returns immediately on a null source.
        -- This changes only this call's argument; it never empties the slot.
        slot_param:set(nil)
        log("REJECT no electricity suitability")
    end
end)

RegisterHook(MODEL .. ":OnUpdateCharacterContainer_ServerInternal", function() end,
    function(context)
        local model = context:get()
        if own(model) then guarded("container changed", function() refresh(model, "CONTENTS") end) end
    end)

local function register_menu()
    if menu_hook_ready or not valid(StaticFindObject(MENU .. ":OnSetup")) then return end
    RegisterHook(MENU .. ":OnSetup", function(context)
        local menu = context:get()
        guarded("menu", function()
            local model = menu.Model
            if not own(model) then return end
            menus[menu:GetFullName()] = { menu = menu, model = model, active = true }
            refresh(model, "OPEN")
        end)
    end)
    RegisterHook(MENU .. ":Destruct", function(context)
        local entry = menus[context:get():GetFullName()]
        if entry then entry.active = false end
    end)
    menu_hook_ready = true
end

NotifyOnNewObject("/Script/UMG.UserWidget", function(object)
    if valid(object) and object:GetClass():GetFullName():find("WBP_IngameMenu_CommonCharacterContainer_C", 1, true) then
        guarded("menu hooks", register_menu)
    end
end)
guarded("menu hooks", register_menu)
log("Loaded " .. VERSION .. "; scope=" .. MACHINE_ID .. "; native storage test, conversion not connected")
