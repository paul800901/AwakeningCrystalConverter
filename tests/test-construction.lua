local hooks={}
function RegisterHook(path,pre,post) hooks[path]=post end
local function object(name)
 return {IsValid=function() return true end,GetFullName=function() return name end}
end
local set={Highlight=object('preview'),Error=object('invalid'),Building=object('construction')}
local manager=object('manager');manager.BuildingSurfaceMaterialSet=set
function StaticFindObject(path)
 return {GetMapObjectManager=function() return manager end}
end
local actor=object('actor');actor.CurrentState=1;actor.BuildObjectId={ToString=function() return 'PAE_ExchangePrototype' end}
local function mesh(name,count)
 local m=object(name);m.GetName=function() return name end;m.GetOwner=function() return actor end
 m.original={};m.current={}
 for i=0,count-1 do m.original[i]=object(name..i);m.current[i]=m.original[i] end
 m.GetNumMaterials=function() return count end
 m.GetMaterial=function(self,i) return self.current[i] end
 m.StaticMesh={GetMaterial=function(_,i) return m.original[i] end}
 m.SetMaterial=function(self,i,v) self.current[i]=v end
 return m
end
local body,light,other=mesh('PAE_Body',24),mesh('PAE_ConversionGlow_0',1),mesh('OldHiddenGeometry',2)
actor.K2_GetComponentsByClass=function() return {body,light,other} end
local resets=0;package.loaded.power={reset_visuals=function() resets=resets+1 end}
local module=dofile('src/AwakeningCrystalConverterUI/Scripts/construction.lua')
local function expect(mat)
 for i=0,23 do assert(body.current[i]==mat) end
 assert(light.current[0]==mat);assert(other.current[0]==other.original[0])
end
module.refresh(actor);expect(set.Highlight)
module.on_material(body,set.Error);expect(set.Error)
module.refresh(actor);expect(set.Error)
module.on_material(body,set.Highlight);expect(set.Highlight)
actor.CurrentState=2;module.refresh(actor);expect(set.Building)
actor.CurrentState=3;module.refresh(actor)
for i=0,23 do assert(body.current[i]==body.original[i]) end
assert(light.current[0]==light.original[0]);assert(resets==1)
module.refresh(actor);assert(resets==1)
actor.BuildObjectId.ToString=function() return 'OtherBuilding' end
actor.CurrentState=1;module.refresh(actor);assert(body.current[0]==body.original[0])
assert(hooks['/Script/Pal.PalBuildObject:OnStartSimulation'])
print('PASS: all slots, invalid/valid placement, construction, complete restoration, unrelated objects unchanged')
