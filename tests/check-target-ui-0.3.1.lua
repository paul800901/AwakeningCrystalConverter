-- This is a local interaction-contract test, not a game or UE4SS runtime test.
package.preload.locale = function() return dofile('src/AwakeningCrystalConverterUI/Scripts/locale.lua') end
-- Companion modules have their own tests; this mock covers only the menu.
package.preload.power = function() return {} end
package.preload.construction = function() return {} end
package.preload.technology_order = function() return {} end
local hooks, objects = {}, {}
local invalid = { IsValid = function() return false end }
local methods = {}
function methods:IsValid() return self.live ~= false end
function methods:GetFullName() return self.name end
function methods:IsA(class) return self.class == class end
function methods:GetClass() return {GetFullName=function() return self.class end} end
function methods:GetCurrentLanguage() return 'zh-Hant' end
function methods:SetVisibility(v) self.visibility=v end
function methods:GetParent() return self.parent end
function methods:GetLayout() return {} end
function methods:SetText(t) self.text=t end
function methods:SetBackgroundColor(c) self.color=c end
function methods:SetHeightOverride(h) self.height=h end
function methods:SetToolTipText(t) self.tooltip=t end
for _,m in ipairs({'SetLayout','SetZOrder','SetColorAndOpacity','SetVerticalAlignment','SetHorizontalAlignment','SetPadding','SetJustification','SetSize'}) do methods[m]=function() end end
local function object(name,class)
 local o=setmetatable({name=name,class=class,Font={Size=20}}, {__index=methods})
 objects[name]=o; o.OnClicked={Add=function() end};return o
end
function methods:AddChild(child) child.parent=self; return child end
function methods:AddChildToCanvas(child) self:AddChild(child); return object(child.name..'.slot','slot') end
function methods:AddChildToHorizontalBox(child) return self:AddChildToCanvas(child) end
function methods:AddChildToVerticalBox(child) return self:AddChildToCanvas(child) end
function methods:Setup(id) self.displayed_item=id:ToString() end
function FName(s) return {ToString=function()return s end} end
function FText(s) return s end
function StaticFindObject(p) return object(p,p) end
function StaticConstructObject(c,tree,n) return object(tree.name..'.'..n:ToString(),c.name) end
function RegisterHook(p,fn) assert(not hooks[p], 'duplicate hook');hooks[p]=fn; return 1,2 end
function NotifyOnNewObject() end
local function array(values)
 local t={values=values or {}}
 function t:Empty() self.values={} end
 function t:ForEach(fn) for i,v in ipairs(self.values)do fn(i,{get=function()return v end})end end
 return t
end
local elements={'Electric','Fire','Water','Grass','Ground','Ice','Dragon','Dark','Neutral'}
local labels={Electric='雷',Fire='火',Water='水',Grass='草',Ground='地',Ice='冰',Dragon='龍',Dark='暗',Neutral='無'}
local function all_rows()
 local r={};for _,s in ipairs(elements)do for _,t in ipairs(elements)do if s~=t then r[#r+1]=FName('PAE_Test_'..s..'To'..t) end end end;return r
end
local function make_menu(name,id)
 local fields={}
 local menu=setmetatable({}, {__index=function(_,k)return fields[k] or methods[k]end,__newindex=function(_,k,v)
  fields[k]=(k=='CachedRecipeIds' and not v.ForEach) and array(v) or v
 end})
 menu.name=name;menu.WidgetTree=object(name..'.Tree','tree');menu.IsSelectingProductNumFlag=false
 menu.CachedRecipeIds=array(all_rows());menu.CurrentFilteringItemTypeA=array();menu.CurrentExcludeItemTypeB=array()
 menu['Convert Item Model']={ProductSettingModel=object(name..'.Setting','setting')}
 menu.BP_PalTextBlock_Name=object(name..'.Title','text')
 menu.Canvas_Select=object(name..'.Selection','canvas')
 menu.HorizontalBox_SearchName=object(name..'.Search','box')
 menu.PalEditableTextBox_Search=object(name..'.SearchText','text')
 menu.WBP_IngameMenu_WorkSpace_TabSet=object(name..'.Tabs','tabs')
 menu.WBP_IngameMenu_WorkSpace_TabSet.parent=object(name..'.Canvas','/Script/UMG.CanvasPanel')
 menu.WBP_IngameMenu_WorkSpace_TabSet.Slot=object(name..'.TabSlot','slot')
 menu.ActionHandle_NextCategory={};menu.ActionHandle_PrevCategory={}
 menu.CommonTileView_146=object(name..'.Targets','list')
 function menu.CommonTileView_146:GetNumItems()return #menu.visible end
 function menu:GetParam()
  local p=object(name..'.Param','/Script/Pal.PalHUDDispatchParameter_ConvertItem')
  p.ConvertItemModel=object(name..'.Model','model');function p.ConvertItemModel:TryGetMapObjectId()return FName(id)end;return p
 end
 function menu:UnregisterActionBinding()error("Tried storing reference to a Lua table for an 'Out' parameter when calling a UFunction but no table was on the stack")end
 function menu:OnCancelInput() self.IsSelectingProductNumFlag=false;self.cancelled=true end
 function menu:OnUnhoveredRecipeSlot(slot) self.popup=nil;self.hidden_popup_slot=slot end
 function menu:RefleshFIltering()
  self.visible={}
  if #self.CurrentFilteringItemTypeA.values>0 or #self.CurrentExcludeItemTypeB.values>0 then return end
  self.CachedRecipeIds:ForEach(function(_,p)self.visible[#self.visible+1]=p:get():ToString()end)
 end
 return menu
end
dofile('src/AwakeningCrystalConverterUI/Scripts/main.lua')
local path='/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/WBP_IngameMenu_WorkSpace.WBP_IngameMenu_WorkSpace_C'
local function setup(m)hooks[path..':OnSetup']({get=function()return m end})end
local function click(m,s)hooks['/Script/UMG.Widget:SetKeyboardFocus']({get=function()return objects[m.name..'.Tree.ACC_Target_'..s]end})end
local a=make_menu('A','PAE_ExchangePrototype');setup(a)
assert(a.visible and #a.visible==8,'initial target did not attach')
assert(objects['A.Tree.ACC_TargetHeight'].height==42,'missing reserved button height')
local b=make_menu('B','PAE_ExchangePrototype');setup(b)
local entry_path=path..':BndEvt__WBP_IngameMenu_WorkSpace_CommonTileView_146_K2Node_ComponentBoundEvent_6_OnListEntryInitializedDynamic__DelegateSignature'
for _,target in ipairs(elements)do
 a['Convert Item Model'].ProductSettingModel.SelectedRecipeId=FName('PAE_Test_ElectricToFire')
 a['Convert Item Model'].ProductSettingModel.ProductNum=283;a.IsSelectingProductNumFlag=true
 click(a,target=='Fire' and 'Water' or 'Fire');click(a,target)
 assert(#a.visible==8)
 local payments={}
 for _,r in ipairs(a.visible)do
  local source,output=r:match('^PAE_Test_(%a+)To(%a+)$')
  assert(output==target and source~=target,r)
  assert(not payments[source],'duplicate payment source');payments[source]=true
  local item=object('Entry-'..r,'entry');item.RecipeID=FName(r)
  local widget=object('Slot-'..r,'slot');widget.RecipeId=FName(r);widget['Product ItemId']=FName('PalAwakening_'..target)
  widget.WBP_PalInGameMenuItemIcon=object('Icon-'..r,'icon')
  hooks[entry_path]({get=function()return a end},{get=function()return item end},{get=function()return widget end})
  assert(widget.WBP_PalInGameMenuItemIcon.displayed_item=='PalAwakening_'..source,'wrong payment icon')
  assert(widget.RecipeId:ToString()==r,'changed settlement recipe')
  assert(widget['Product ItemId']:ToString()=='PalAwakening_'..target,'changed native output identity')
  local direction='消耗 '..labels[source]..'之覺醒晶石 → 取得 '..labels[target]..'之覺醒晶石'
  assert(widget.tooltip==direction,'hover explanation disagrees with recipe')
  -- Reproduce native hover: the recipe popup describes the output even though
  -- this entry's icon represents payment. Our post hook must close only that
  -- popup; hovering must not commit another payment or rewrite the summary.
  local hint=objects['A.Tree.ACC_PaymentHint']
  local previous=hint.text
  a.popup='PalAwakening_'..target
  hooks[path..':OnHoveredRecipeSlot']({get=function()return a end},{get=function()return widget end})
  assert(a.popup==nil and a.hidden_popup_slot==widget,'contradictory output popup remains')
  assert(hint.text==previous,'hover changed committed exchange text')
  a.IsSelectingProductNumFlag=true
  hooks[path..':OnClickedRecipeSlot']({get=function()return a end},{get=function()return widget end})
  assert(hint.text=='已選擇：'..direction,'selected exchange text disagrees with clicked recipe')
  a.IsSelectingProductNumFlag=false
  hooks[path..':OnCancelInput']({get=function()return a end})
  assert(hint.text=='點選下方要消耗的晶石，再設定兌換數量','cancel left stale exchange text')
 end
 assert(a['Convert Item Model'].ProductSettingModel.SelectedRecipeId:ToString()=='None','stale recipe')
 assert(a['Convert Item Model'].ProductSettingModel.ProductNum==1,'stale quantity')
 assert(not a.IsSelectingProductNumFlag,'stale quantity pane')
 for _,r in ipairs(b.visible)do assert(r:match('ToFire$'),'cross-menu change')end
end
hooks[path..':Destruct']({get=function()return a end});click(a,'Fire')
assert(a.visible[1]:match('ToNeutral$'),'closed menu handled click')
a.CachedRecipeIds=all_rows();setup(a);click(a,'Water')
assert(a.visible[1]:match('ToWater$'),'reopened menu failed')
a.CurrentFilteringItemTypeA=array({'Weapon'});a.CurrentExcludeItemTypeB=array({'Awakening'})
a:RefleshFIltering();assert(#a.visible==0,'category event precondition')
hooks[path..':OnChangedCategory']({get=function()return a end})
assert(#a.visible==8 and a.visible[1]:match('ToWater$'),'category shortcut lost target filter')
local unrelated=make_menu('Crusher','Crusher');setup(unrelated)
unrelated.CurrentFilteringItemTypeA=array({'Weapon'})
hooks[path..':OnChangedCategory']({get=function()return unrelated end})
assert(#unrelated.CurrentFilteringItemTypeA.values==1,'other workbench category changed')
assert(unrelated.visible==nil and #unrelated.CachedRecipeIds.values==72,'unrelated machine changed')
local other_item=object('OtherEntry','entry');other_item.RecipeID=FName('PAE_Test_WaterToFire')
local other_slot=object('OtherSlot','slot');other_slot.WBP_PalInGameMenuItemIcon=object('OtherIcon','icon')
hooks[entry_path]({get=function()return unrelated end},{get=function()return other_item end},{get=function()return other_slot end})
assert(other_slot.WBP_PalInGameMenuItemIcon.displayed_item==nil,'other workbench icon changed')
unrelated.popup='native output'
hooks[path..':OnHoveredRecipeSlot']({get=function()return unrelated end},{get=function()return other_slot end})
assert(unrelated.popup=='native output','other workbench tooltip was hidden')
print('PASS: 72 exchanges keep settlement IDs; matching payment icons and direction text; native output popup closed; hover preserves selection; click/cancel summary; button height reserved; target reset; two menus; reopen; category; unrelated workbench unchanged. Native rendering still requires a game test.')
