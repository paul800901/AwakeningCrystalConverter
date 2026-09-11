-- UI only. The original converter owns material consumption, quantity,
-- completion and collection. The separate power module controls energy only.
local VERSION = "0.6.1"
local MACHINE_ID = "PAE_ExchangePrototype"
local MENU_CLASS = "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/WBP_IngameMenu_WorkSpace.WBP_IngameMenu_WorkSpace_C"
local CLICK_PATH = "/Script/UMG.Widget:SetKeyboardFocus"
local locale = require("locale")
local ELEMENTS = {
    { "Electric" }, { "Fire" }, { "Water" }, { "Grass" },
    { "Ground" }, { "Ice" }, { "Dragon" }, { "Dark" }, { "Neutral" },
}
local menus, buttons = {}, {}
local hooks_ready = false

local function valid(object)
    return object ~= nil and object:IsValid()
end

local function log(message)
    print("[AwakeningCrystalConverterUI] " .. message .. "\n")
end

local function guarded(label, callback)
    local ok, err = pcall(callback)
    if not ok then log(label .. " failed: " .. tostring(err)) end
    return ok
end

local function is_our_menu(menu)
    if not valid(menu) then return false end
    local parameter = menu:GetParam()
    if not valid(parameter) or not parameter:IsA("/Script/Pal.PalHUDDispatchParameter_ConvertItem") then
        return false
    end
    local model = parameter.ConvertItemModel
    return valid(model) and model:TryGetMapObjectId():ToString() == MACHINE_ID
end

local function element_name(state, element_id)
    local strings = locale.entry(state.language)
    return strings.elements[element_id] or locale.data.en.elements[element_id] or element_id
end

local function refresh_localized_widgets(state)
    local strings = locale.entry(state.language)
    if valid(state.title) then state.title:SetText(FText(strings.receive)) end
    for _, element in ipairs(ELEMENTS) do
        local element_id = element[1]
        local label = state.labels and state.labels[element_id]
        local button = state.buttons[element_id]
        if valid(label) then label:SetText(FText(element_name(state, element_id))) end
        if valid(button) then
            button:SetToolTipText(FText(locale.entry(state.language).obtain_tooltip:gsub("{element}", element_name(state, element_id))))
        end
    end
    if valid(state.hint) then state.hint:SetText(FText(strings.payment_prompt)) end
end

local function exchange_text(state, row)
    local source, target = row:match("^PAE_Test_(%a+)To(%a+)$")
    if target ~= state.target or not state.recipes[source] or source == target then return end
    return locale.format(state.language, "spend_receive", element_name(state, source), element_name(state, target))
end

local function select_target(state, target)
    local menu = state.menu
    if not valid(menu) then return end
    local rows = state.recipes[target]
    assert(rows and #rows == 8, "target does not have eight loaded recipes: " .. target)

    -- Native cancel returns from the quantity pane to recipe selection.
    -- Clear the UI selection as well, so the start shortcut cannot submit a
    -- recipe belonging to the previously selected target.
    if menu.IsSelectingProductNumFlag then menu:OnCancelInput() end
    local setting = menu["Convert Item Model"].ProductSettingModel
    assert(valid(setting), "product setting model unavailable")
    setting.SelectedRecipeId = FName("None")
    setting.FocusedRecipeId = FName("None")
    setting.ProductNum = 1
    menu.IsSelectingProductNumFlag = false
    menu.Canvas_Select:SetVisibility(1) -- Collapsed

    local ids = {}
    for _, row in ipairs(rows) do ids[#ids + 1] = FName(row) end
    -- Empty before replacing the array: UE4SS's table setter constructs a new
    -- array. This is the menu's cache, never the converter's recipe array.
    menu.CachedRecipeIds:Empty()
    menu.CachedRecipeIds = ids
    state.target = target
    state.hint:SetText(FText(locale.entry(state.language).payment_prompt))
    menu:RefleshFIltering()

    for element, button in pairs(state.buttons) do
        button:SetBackgroundColor(element == target
            and { R = 0.0, G = 0.52, B = 0.68, A = 1.0 }
            or { R = 0.08, G = 0.16, B = 0.20, A = 1.0 })
    end
    local count = menu.CommonTileView_146:GetNumItems()
    log("TARGET " .. target .. " payment_choices=" .. tostring(count))
    assert(count == 8, "expected eight payment entries after target filtering")
end

local function attach(menu)
    if not is_our_menu(menu) then return end
    for old_key, old in pairs(menus) do
        if not valid(old.menu) then
            for button_key, binding in pairs(buttons) do
                if binding.state == old then buttons[button_key] = nil end
            end
            menus[old_key] = nil
        end
    end
    local key = menu:GetFullName()
    -- OnSetup can run again for a reused widget. Its native setup restores the
    -- full recipe cache; recapture it before applying this menu's target.
    local recipes = {}
    for _, element in ipairs(ELEMENTS) do recipes[element[1]] = {} end
    menu.CachedRecipeIds:ForEach(function(_, value)
        local row = value:get():ToString()
        local source, target = row:match("^PAE_Test_(%a+)To(%a+)$")
        if recipes[source] and recipes[target] and source ~= target then
            table.insert(recipes[target], row)
        end
    end)
    for _, element in ipairs(ELEMENTS) do
        assert(#recipes[element[1]] == 8, "missing loaded recipes for " .. element[1])
    end

    menu.HorizontalBox_SearchName:SetVisibility(1)
    menu.PalEditableTextBox_Search:SetText(FText(""))
    menu.CurrentFilteringItemTypeA:Empty()
    menu.CurrentExcludeItemTypeB:Empty()

    local culture = StaticFindObject("/Script/Engine.Default__KismetInternationalizationLibrary")
    local language = valid(culture) and culture:GetCurrentLanguage() or "en"
    if type(language) ~= "string" then language = language:ToString() end
    language = locale.resolve(language)

    local state = menus[key]
    if state and valid(state.bar) then
        state.recipes = recipes
        state.language = language
        state.active = true
        menu.WBP_IngameMenu_WorkSpace_TabSet:SetVisibility(1)
        refresh_localized_widgets(state)
        select_target(state, state.target)
        return
    end

    local tree = menu.WidgetTree
    local tabs = menu.WBP_IngameMenu_WorkSpace_TabSet
    local parent = tabs:GetParent()
    assert(valid(tree) and valid(parent), "target selector parent unavailable")
    assert(parent:IsA("/Script/UMG.CanvasPanel"), "target selector expects native canvas")

    local function create(class_name, name)
        local class = StaticFindObject("/Script/UMG." .. class_name)
        assert(valid(class), class_name .. " class unavailable")
        local object = StaticConstructObject(class, tree, FName(name))
        assert(valid(object), "could not create " .. name)
        return object
    end
    local bar = create("VerticalBox", "ACC_TargetSelector")
    local slot = parent:AddChildToCanvas(bar)
    slot:SetLayout(tabs.Slot:GetLayout())
    slot:SetZOrder(20)
    state = { menu = menu, bar = bar, recipes = recipes, buttons = {}, labels = {}, target = "Fire", active = true, language = language }
    menus[key] = state
    -- The native tab area is only 70 units tall. Give the buttons their own
    -- 42-unit row; the previous Fill row lost its height to the hint text.
    local target_height = create("SizeBox", "ACC_TargetHeight")
    target_height:SetHeightOverride(42)
    local target_row = create("HorizontalBox", "ACC_TargetRow")
    target_height:AddChild(target_row)
    bar:AddChildToVerticalBox(target_height)
    local title = create("TextBlock", "ACC_TargetLabel")
    title.Font = menu.BP_PalTextBlock_Name.Font
    local title_font = title.Font
    title_font.Size = 16
    title.Font = title_font
    title:SetText(FText(locale.entry(language).receive))
    state.title = title
    title:SetColorAndOpacity({ SpecifiedColor = { R = 0.65, G = 0.87, B = 0.94, A = 1.0 }, ColorUseRule = 0 })
    local title_slot = target_row:AddChildToHorizontalBox(title)
    title_slot:SetVerticalAlignment(2) -- Center
    title_slot:SetPadding({ Left = 0, Top = 0, Right = 10, Bottom = 0 })

    for _, element in ipairs(ELEMENTS) do
        local target = element[1]
        local button = create("Button", "ACC_Target_" .. target)
        local label = create("TextBlock", "ACC_TargetText_" .. target)
        label:SetText(FText(element_name(state, target)))
        label:SetJustification(1)
        label:SetColorAndOpacity({ SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 })
        -- Use the game's font, including its Chinese fallback glyphs.
        local font = menu.BP_PalTextBlock_Name.Font
        label.Font = font
        local size = label.Font
        size.Size = (language == "zh-Hans" or language == "zh-Hant") and 18 or 14
        label.Font = size
        local content = button:AddChild(label)
        content:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        content:SetHorizontalAlignment(2) -- Center
        content:SetVerticalAlignment(2)
        local cell = target_row:AddChildToHorizontalBox(button)
        cell:SetSize({ Value = 1.0, SizeRule = 1 }) -- Equal-width Fill
        cell:SetPadding({ Left = 3, Top = 2, Right = 3, Bottom = 2 })
        button:SetToolTipText(FText(locale.entry(language).obtain_tooltip:gsub("{element}", element_name(state, target))))
        button.OnClicked:Add(button, "SetKeyboardFocus")
        state.buttons[target] = button
        state.labels[target] = label
        buttons[button:GetFullName()] = { state = state, target = target }
    end

    local hint = create("TextBlock", "ACC_PaymentHint")
    hint.Font = menu.BP_PalTextBlock_Name.Font
    local hint_font = hint.Font
    hint_font.Size = 14
    hint.Font = hint_font
    state.hint = hint
    hint:SetText(FText(locale.entry(language).payment_prompt))
    hint:SetColorAndOpacity({ SpecifiedColor = { R = 0.65, G = 0.87, B = 0.94, A = 1.0 }, ColorUseRule = 0 })
    bar:AddChildToVerticalBox(hint):SetPadding({ Left = 0, Top = 4, Right = 0, Bottom = 0 })
    tabs:SetVisibility(1)
    select_target(state, "Fire")
    log("ATTACHED version=" .. VERSION .. " targets=9 recipes=72")
end

local function register_menu_hooks()
    if hooks_ready then return end
    -- Blueprint callbacks run after the original function in UE4SS; register
    -- only once the class has actually been loaded.
    if not valid(StaticFindObject(MENU_CLASS .. ":OnSetup")) then return end
    RegisterHook(MENU_CLASS .. ":OnSetup", function(context)
        local menu = context:get()
        guarded("attach", function() attach(menu) end)
    end)
    RegisterHook(MENU_CLASS .. ":BndEvt__WBP_IngameMenu_WorkSpace_CommonTileView_146_K2Node_ComponentBoundEvent_6_OnListEntryInitializedDynamic__DelegateSignature",
        function(context, item_param, widget_param)
            local state = menus[context:get():GetFullName()]
            if not state or not state.active then return end
            guarded("payment icon", function()
                local item, widget = item_param:get(), widget_param:get()
                if not valid(item) or not valid(widget) then return end
                local row = item.RecipeID:ToString()
                local source, target = row:match("^PAE_Test_(%a+)To(%a+)$")
                if target ~= state.target or not state.recipes[source] or source == target then return end
                -- Only change the inner icon. The slot's RecipeId and Product
                -- ItemId retain the native values, so clicks, required material
                -- checks and the right-hand result pane use the original recipe.
                widget.WBP_PalInGameMenuItemIcon:Setup(FName("PalAwakening_" .. source))
                widget:SetToolTipText(FText(exchange_text(state, row)))
            end)
        end)
    RegisterHook(MENU_CLASS .. ":OnHoveredRecipeSlot", function(context, slot_param)
        local menu = context:get()
        local state = menus[menu:GetFullName()]
        if not state or not state.active then return end
        guarded("payment hover", function()
            local slot = slot_param:get()
            if not valid(slot) or not exchange_text(state, slot.RecipeId:ToString()) then return end
            -- Native hover opens a large OUTPUT-item popup for this recipe,
            -- contradicting the PAYMENT icon. Its unhover function only calls
            -- GetHUDService -> HideCommonItemInfo (verified in the game asset).
            -- Close that popup; keep our matching spend -> receive tooltip.
            menu:OnUnhoveredRecipeSlot(slot)
        end)
    end)
    RegisterHook(MENU_CLASS .. ":OnClickedRecipeSlot", function(context, slot_param)
        local menu = context:get()
        local state = menus[menu:GetFullName()]
        if not state or not state.active then return end
        guarded("selected exchange", function()
            local slot = slot_param:get()
            if not valid(slot) then return end
            local text = exchange_text(state, slot.RecipeId:ToString())
            if text and menu.IsSelectingProductNumFlag then
                state.hint:SetText(FText(locale.entry(state.language).selected .. text))
            end
        end)
    end)
    RegisterHook(MENU_CLASS .. ":OnCancelInput", function(context)
        local state = menus[context:get():GetFullName()]
        if state and state.active then
            guarded("cancel exchange", function() state.hint:SetText(FText(locale.entry(state.language).payment_prompt)) end)
        end
    end)
    -- UnregisterActionBinding takes an opaque in/out struct that this UE4SS
    -- Lua bridge cannot pass as userdata (observed in the 0.2.0 live log).
    -- Keep the native bindings. After their category event, restore the
    -- target-filtered list on this converter's menu only.
    RegisterHook(MENU_CLASS .. ":OnChangedCategory", function(context)
        local menu = context:get()
        local state = menus[menu:GetFullName()]
        if not state or not state.active then return end
        guarded("category filter", function()
            menu.CurrentFilteringItemTypeA:Empty()
            menu.CurrentExcludeItemTypeB:Empty()
            menu:RefleshFIltering()
        end)
    end)
    RegisterHook(MENU_CLASS .. ":Destruct", function(context)
        local state = menus[context:get():GetFullName()]
        if state then state.active = false end
    end)
    hooks_ready = true
    log("HOOKS ready")
end

RegisterHook(CLICK_PATH, function(context)
    local button = context:get()
    if not valid(button) then return end
    local binding = buttons[button:GetFullName()]
    if not binding or not binding.state.active or binding.state.target == binding.target then return end
    guarded("target selection", function() select_target(binding.state, binding.target) end)
end)

-- WorkSpace is a streamed Blueprint. Object notification registers its setup
-- hook before the newly constructed widget executes OnSetup; no polling loop.
NotifyOnNewObject("/Script/UMG.UserWidget", function(object)
    if valid(object) and object:GetClass():GetFullName():find("WBP_IngameMenu_WorkSpace_C", 1, true) then
        guarded("hook registration", register_menu_hooks)
    end
end)
guarded("hook registration", register_menu_hooks)
log("Loaded " .. VERSION .. "; waiting for the converter menu")
guarded("power module", function() require("power") end)
guarded("technology order", function() require("technology_order") end)
guarded("construction surfaces", function() require("construction") end)
