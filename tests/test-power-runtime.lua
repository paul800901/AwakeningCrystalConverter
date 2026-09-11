-- Executes the shipped power.lua against mock Unreal objects, not a game test.
local loop, discovered, hooks = nil, {}, {}
local function object(class)
  return {IsValid=function() return true end, IsA=function(_, c) return class==c end}
end
local idle = object('material'); idle.tag='idle'
local working = object('material'); working.tag='working'
function StaticFindObject(path)
  if path:find('PAE_ConversionIdle',1,true) then return idle end
  if path:find('PAE_ConversionWorking',1,true) then return working end
  return object(path)
end
function RegisterHook(path, pre, post) hooks[path]=post; return 1,2 end
function LoopInGameThreadWithDelay(ms, callback) assert(ms==100); loop=callback; return 1 end
function CancelDelayedAction() end
function FindAllOf(class) assert(class=='PalMapObjectConvertItemModel'); return discovered end
local function model(name, id, authority, state, energy_present)
  local gem=object('mesh'); gem.GetFullName=function() return 'PAE_ConversionGlow_0' end
  gem.SetMaterial=function(self,_,material) self.material=material.tag end
  local other=object('mesh'); other.GetFullName=function() return 'OtherMesh' end
  other.SetMaterial=function() error('unrelated mesh mutated') end
  local actor=object('actor'); actor.CurrentState=state
  actor.HasAuthority=function() return authority end
  actor.K2_GetComponentsByClass=function() return {gem,other} end
  local energy=object('/Script/Pal.PalMapObjectEnergyModule'); energy.powered=true
  energy.CanConsumeEnergy=function(self) return self.powered end
  energy.GetCurrentConsumeEnergySpeed=function(self) return self.CurrentConsumeEnergySpeed end
  energy.GetConsumeEnergySpeed=function(self) return self.ConsumeEnergySpeed end
  energy.IsRequiredEnergy=function(self) return self.bRequiredConsumeEnergy end
  local m=object('/Script/Pal.PalMapObjectConvertItemModel'); m.remain=0
  m.GetFullName=function() return name end
  m.TryGetMapObjectId=function() return {ToString=function() return id end} end
  m.GetActor=function() return actor end
  m.GetRemainCreateNum=function(self) return self.remain end
  m.GetEnergyModule=function() return energy_present and energy or nil end
  return m,energy,gem
end
local our,e,g=model('ours','PAE_ExchangePrototype',true,3,true)
local foreign,ef=model('foreign','Crusher',true,3,true)
local client,ec=model('client','PAE_ExchangePrototype',false,3,true)
local building,eb=model('building','PAE_ExchangePrototype',true,2,true)
local missing,em=model('missing','PAE_ExchangePrototype',true,3,false)
discovered={our,foreign,client,building,missing}
local power=dofile('src/AwakeningCrystalConverterUI/Scripts/power.lua')
loop(); assert(e.ConsumeEnergySpeed==36000 and e.CurrentConsumeEnergySpeed==36000)
assert(e.bRequiredConsumeEnergy and g.material=='idle')
our.remain=2; loop(); assert(e.CurrentConsumeEnergySpeed==576000 and g.material=='working')
e.powered=false; loop(); assert(e.CurrentConsumeEnergySpeed==576000 and g.material=='idle')
e.powered=true; loop(); assert(g.material=='working')
our.remain=0; hooks['/Script/Pal.PalMapObjectConvertItemModel:Cancel_ServerInternal']({get=function()return our end})
assert(e.CurrentConsumeEnergySpeed==36000 and g.material=='idle')
our.remain=1; loop(); assert(g.material=='working')
our.remain=0; hooks['/Script/Pal.PalMapObjectConvertItemModel:OnFinishWorkInServer']({get=function()return our end})
assert(e.CurrentConsumeEnergySpeed==36000 and g.material=='idle')
for _,v in ipairs({ef,ec,eb,em}) do assert(v.ConsumeEnergySpeed==nil,'guard failed') end
power.stop(); our.remain=1; loop(); assert(e.CurrentConsumeEnergySpeed==36000)
print('PASS shipped power.lua: idle, work, no power, resume, cancel, finish, repeated visual transitions, foreign/client/construction/missing-module guards, stop')
