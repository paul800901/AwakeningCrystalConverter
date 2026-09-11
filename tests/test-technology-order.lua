local callback
function RegisterHook(path,pre,post) assert(path:find('GetRecipeTechnologyRowNameArray'));callback=post end
function FName(s) return {ToString=function()return s end} end
dofile('src/AwakeningCrystalConverterUI/Scripts/technology_order.lua')
local function check(input, expected)
  local a={};for _,s in ipairs(input)do a[#a+1]=FName(s)end
  callback(nil,{get=function()return a end})
  local result={};for _,n in ipairs(a)do result[#result+1]=n:ToString()end
  assert(table.concat(result,',')==table.concat(expected,','))
end
check({'A','AncientRelicRecycler','Cake','PAE_ExchangePrototype'},{'A','AncientRelicRecycler','PAE_ExchangePrototype','Cake'})
check({'PAE_ExchangePrototype','A','AncientRelicRecycler','Cake'},{'A','AncientRelicRecycler','PAE_ExchangePrototype','Cake'})
check({'A','AncientRelicRecycler','PAE_ExchangePrototype','Cake'},{'A','AncientRelicRecycler','PAE_ExchangePrototype','Cake'})
check({'A','Cake'},{'A','Cake'})
print('PASS shipped technology_order.lua preserves entries and relative order; places converter immediately after reference')
