-- Mirror native building surfaces across this model's material slots only.
local M = {}
local busy = false
local phases = {}
local function valid(o) return o ~= nil and o:IsValid() end
local function value(p)
    if p and p.get then return p:get() end
    return p
end
local function own(actor)
    return valid(actor) and actor.BuildObjectId:ToString() == 'PAE_ExchangePrototype'
end
local function meshes(actor)
    local result={}
    local list=actor:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.StaticMeshComponent'))
    local function add(c)
        c=value(c)
        local n=c:GetFullName():match('([^%.: ]+)$'):gsub('_GEN_VARIABLE$','')
        if n=='PAE_Body' or n=='PAE_ConversionGlow_0' then result[#result+1]=c end
    end
    if type(list)=='table' then for _,c in pairs(list) do add(c) end
    else list:ForEach(function(_,c) add(c) end) end
    return result
end
local function surfaces(actor)
    local utility=StaticFindObject('/Script/Pal.Default__PalUtility')
    local manager=utility:GetMapObjectManager(actor)
    if not valid(manager) then return nil end
    return manager.BuildingSurfaceMaterialSet
end
local function paint(actor,material,restore)
    if busy then return end
    busy=true
    local ok,err=pcall(function()
        for _,mesh in ipairs(meshes(actor)) do
            for i=0,mesh:GetNumMaterials()-1 do
                mesh:SetMaterial(i,restore and mesh.StaticMesh:GetMaterial(i) or material)
            end
        end
    end)
    busy=false
    if not ok then error(err) end
end
function M.refresh(actor)
    if not own(actor) then return end
    local state=actor.CurrentState
    if state==1 or state==2 then
        local set=surfaces(actor)
        if not set then return end
        local surface=state==2 and set.Building or set.Highlight
        -- Keep native red invalid-placement indication if already selected.
        if state==1 then
            for _,mesh in ipairs(meshes(actor)) do
                local current=mesh:GetMaterial(0)
                if valid(current) and valid(set.Error) and current:GetFullName()==set.Error:GetFullName() then surface=set.Error;break end
            end
        end
        if valid(surface) then paint(actor,surface,false);phases[actor:GetFullName()]=state end
    elseif state>=3 and phases[actor:GetFullName()] then
        paint(actor,nil,true);phases[actor:GetFullName()]=nil
        local power=package.loaded.power
        if power and power.reset_visuals then power.reset_visuals() end
    end
end
function M.on_material(component,material)
    if busy or not valid(component) or not valid(material) then return end
    if component:GetFullName():match('([^%.: ]+)$')~='PAE_Body' then return end
    local actor=component:GetOwner()
    if not own(actor) then return end
    local state=actor.CurrentState
    if state~=1 and state~=2 then return end
    local set=surfaces(actor)
    if not set then return end
    for _,name in ipairs({'Highlight','Error','Building'}) do
        if valid(set[name]) and set[name]:GetFullName()==material:GetFullName() then
            paint(actor,material,false);phases[actor:GetFullName()]=state;return
        end
    end
end
local function guarded(fn,...)
    local ok,err=pcall(fn,...)
    if not ok then print('[AwakeningConstruction] '..tostring(err)..'\n') end
end
for _,event in ipairs({'OnStartSimulation','OnRep_CurrentState','OnRep_BuildProgressVisualRate'}) do
    RegisterHook('/Script/Pal.PalBuildObject:'..event,function() end,function(ctx) guarded(M.refresh,ctx:get()) end)
end
RegisterHook('/Script/Engine.PrimitiveComponent:SetMaterial',function() end,function(ctx,index,material)
    guarded(M.on_material,ctx:get(),value(material))
end)
return M
