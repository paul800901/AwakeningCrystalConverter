-- Adjust only the returned technology list; never change unlocks or point data.
local path = '/Script/Pal.PalTechnologyData:GetRecipeTechnologyRowNameArray'
local warned = false
RegisterHook(path, function() end, function(_, result)
    local ok, err = pcall(function()
        local array = result:get()
        local names, own, reference = {}, nil, nil
        for i=1,#array do
            names[i] = array[i]:ToString()
            if names[i]=='PAE_ExchangePrototype' then own=i end
            if names[i]=='AncientRelicRecycler' then reference=i end
        end
        if not own or not reference or own==reference+1 then return end
        table.remove(names, own)
        if own<reference then reference=reference-1 end
        table.insert(names, reference+1, 'PAE_ExchangePrototype')
        for i=1,#names do
            if array[i]:ToString()~=names[i] then array[i]=FName(names[i]) end
        end
    end)
    if not ok and not warned then
        warned=true
        print('[AwakeningCrystalConverterUI] technology ordering unavailable: '..tostring(err)..'\n')
    end
end)
return true
