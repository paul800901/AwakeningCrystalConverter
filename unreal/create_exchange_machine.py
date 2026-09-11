"""Author a small converter and check real FPalItemRecipe serialization in UE 5.1.

The editor SDK contains stub game functions: this does not test game settlement.
Only /Game/PalAwakeningExchange is packaged; the recipe check table is editor-only.
"""
import json
import runpy
from pathlib import Path
import unreal


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = "/Game/PalAwakeningExchange"
ASSET_NAME = "BP_PAE_ExchangePrototype"


def main():
    library = unreal.EditorAssetLibrary
    assets = unreal.AssetToolsHelpers.get_asset_tools()
    subsystem = unreal.get_engine_subsystem(unreal.SubobjectDataSubsystem)
    handles = unreal.SubobjectDataBlueprintFunctionLibrary
    path = ASSET_ROOT + "/" + ASSET_NAME
    bp = library.load_asset(path) if library.does_asset_exist(path) else None
    if not bp:
        factory = unreal.BlueprintFactory()
        factory.set_editor_property("parent_class", unreal.load_class(None, "/Script/Pal.PalBuildObject"))
        bp = assets.create_asset(ASSET_NAME, ASSET_ROOT, unreal.Blueprint, factory)
    unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    actor = subsystem.k2_gather_subobject_data_for_blueprint(bp)[0]

    def find(name):
        for handle in subsystem.k2_gather_subobject_data_for_blueprint(bp):
            obj = handles.get_object(handles.get_data(handle))
            if obj.get_name() in (name, name + "_GEN_VARIABLE"):
                return handle, obj
        return None, None

    root_handle, root_obj = find("PAE_Root")
    if root_handle is None:
        root_handle, reason = subsystem.add_new_subobject(unreal.AddNewSubobjectParams(
            parent_handle=actor, new_class=unreal.SceneComponent, blueprint_context=bp))
        if str(reason):
            raise RuntimeError(str(reason))
        subsystem.rename_subobject(root_handle, unreal.Text("PAE_Root"))
        subsystem.make_new_scene_root(actor, root_handle, bp)

    def component(name, cls, scene=False):
        handle, obj = find(name)
        if handle is None:
            handle, reason = subsystem.add_new_subobject(unreal.AddNewSubobjectParams(
                parent_handle=root_handle if scene else actor, new_class=cls,
                blueprint_context=bp))
            if str(reason):
                raise RuntimeError(str(reason))
            subsystem.rename_subobject(handle, unreal.Text(name))
            obj = handles.get_object(handles.get_data(handle))
        if scene:
            subsystem.attach_subobject(root_handle, handle)
        return obj

    body = component("PAE_Body", unreal.StaticMeshComponent, True)
    body.set_editor_property("static_mesh", library.load_asset("/Engine/BasicShapes/Cube"))
    body.set_editor_property("relative_location", unreal.Vector(0, 0, 50))
    body.set_collision_profile_name("BlockAll")

    bounds = component("PAE_BuildBounds", unreal.BoxComponent, True)
    bounds.set_editor_property("box_extent", unreal.Vector(110, 160, 140))
    bounds.set_editor_property("relative_location", unreal.Vector(0, 0, 140))
    bounds.set_editor_property("generate_overlap_events", False)
    bounds.set_collision_profile_name("NoCollision")

    work_bounds = component("BuildWorkableBounds", unreal.BoxComponent, True)
    work_bounds.set_editor_property("box_extent", unreal.Vector(145, 185, 145))
    work_bounds.set_editor_property("relative_location", unreal.Vector(0, 0, 140))
    work_bounds.set_editor_property("generate_overlap_events", False)
    work_bounds.set_collision_profile_name("NoCollision")

    interact = component("PAE_Interact", unreal.load_class(
        None, "/Script/Pal.PalInteractiveObjectBoxComponent"), True)
    interact.set_editor_property("box_extent", unreal.Vector(155, 200, 150))
    interact.set_editor_property("relative_location", unreal.Vector(0, 0, 140))
    interact.set_editor_property("is_enable_trigger_interact", True)
    interact.set_editor_property("is_implemented_trigger_interact", True)
    interact.set_editor_property("is_enable_interacting_tick", False)
    interact.set_editor_property("generate_overlap_events", True)
    interact.set_collision_profile_name("OverlapAllDynamic")

    facing = component("PAE_WorkFacing", unreal.load_class(
        None, "/Script/Pal.PalWorkFacingComponent"), True)
    facing.set_editor_property("relative_location", unreal.Vector(100, 0, 0))
    facing.set_editor_property("relative_rotation", unreal.Rotator(0, 0, 180))

    converter = component("PAE_Converter", unreal.load_class(
        None, "/Script/Pal.PalMapObjectItemConverterParameterComponent"))
    # Both input and output are finished awakening crystals. The game's actual
    # filtering and settlement behavior need a live test.
    crystal_type = unreal.PalItemTypeB.CONSUME_PAL_AWAKENING
    # The game's converter requires both output categories to match. Empty
    # TargetTypesA rejects every recipe (1.0.4 native predicate RVA 0x3001610).
    converter.set_editor_property("target_types_a", [unreal.PalItemTypeA.CONSUME])
    converter.set_editor_property("target_types_b", [crystal_type])
    converter.set_editor_property("material_types_a", [])
    converter.set_editor_property("material_types_b", [crystal_type])
    converter.set_editor_property("target_rank_max", 99)
    converter.set_editor_property("auto_work_amount_by_sec", 1.0)
    converter.set_editor_property("work_speed_additional_rate", 1.0)

    visual = runpy.run_path(str(ROOT / "unreal/import_wafer_model.py"))
    visual_report = visual["author_visual"](bp, component, library)

    unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    cdo = unreal.get_default_object(library.load_blueprint_class(path))
    cdo.set_editor_property("concrete_model_class", unreal.load_class(
        None, "/Script/Pal.PalMapObjectConvertItemModel"))
    cdo.set_editor_property("replicates", True)
    cdo.set_editor_property("build_object_id", "PAE_ExchangePrototype")
    for prop, name in (("overlap_check_collision_ref", "PAE_BuildBounds"),
                       ("main_mesh_ref", "PAE_Body")):
        ref = unreal.ComponentReference()
        ref.set_editor_property("component_property", name)
        cdo.set_editor_property(prop, ref)
    library.save_loaded_asset(bp, only_if_is_dirty=False)

    # The real Unreal row struct must retain distinct row names and product IDs.
    recipe_file = ROOT / "src/PalAwakeningExchangePrototype/raw/exchange_recipes.json"
    recipes = json.loads(recipe_file.read_text(encoding="utf-8"))["DT_ItemRecipeDataTable"]
    factory = unreal.DataTableFactory()
    factory.set_editor_property("struct", unreal.load_object(None, "/Script/Pal.PalItemRecipe"))
    check_path = "/Game/PAE_EditorChecks/DT_ExchangeRecipeCheck"
    table = library.load_asset(check_path) if library.does_asset_exist(check_path) else None
    if not table:
        table = assets.create_asset("DT_ExchangeRecipeCheck", "/Game/PAE_EditorChecks",
                                    unreal.DataTable, factory)
    rows = [dict(Name=name, **row) for name, row in recipes.items()]
    if not unreal.DataTableFunctionLibrary.fill_data_table_from_json_string(table, json.dumps(rows)):
        raise RuntimeError("Unreal rejected recipe table import")
    row_names = [str(name) for name in unreal.DataTableFunctionLibrary.get_data_table_row_names(table)]
    products = list(unreal.DataTableFunctionLibrary.get_data_table_column_as_string(table, "Product_Id"))
    materials = list(unreal.DataTableFunctionLibrary.get_data_table_column_as_string(table, "Material1_Id"))
    imported = dict(zip(row_names, zip(products, materials)))
    expected = {name: (row["Product_Id"], row["Material1_Id"]) for name, row in recipes.items()}
    if imported != expected:
        raise RuntimeError("Unreal recipe readback mismatch: " + repr(imported))
    library.save_loaded_asset(table, only_if_is_dirty=False)

    # A missing assignment falls back to construction work, which bypasses the
    # converter's remaining-quantity check in the game (RVA 0x3365c00, 1.0.4).
    building_file = ROOT / "src/PalAwakeningExchangePrototype/buildings/exchange_machine.json"
    building = json.loads(building_file.read_text(encoding="utf-8"))["PAE_ExchangePrototype"]
    assignment_rows = [dict(Name="PAE_ExchangePrototype_0", **building["Assignments"][0])]
    assignment_factory = unreal.DataTableFactory()
    assignment_factory.set_editor_property("struct", unreal.load_object(None, "/Script/Pal.PalMapObjectAssignData"))
    assignment_path = "/Game/PAE_EditorChecks/DT_ExchangeAssignmentCheck"
    assignment_table = library.load_asset(assignment_path) if library.does_asset_exist(assignment_path) else None
    if not assignment_table:
        assignment_table = assets.create_asset("DT_ExchangeAssignmentCheck", "/Game/PAE_EditorChecks",
                                               unreal.DataTable, assignment_factory)
    if not unreal.DataTableFunctionLibrary.fill_data_table_from_json_string(assignment_table, json.dumps(assignment_rows)):
        raise RuntimeError("Unreal rejected converter assignment import")
    assignment_readback = {
        prop: list(unreal.DataTableFunctionLibrary.get_data_table_column_as_string(assignment_table, prop))
        for prop in ("WorkType", "WorkSuitability", "bPlayerWorkable", "bBaseCampWorkerWorkable")
    }
    if assignment_readback != {"WorkType": ["ConvertItem"], "WorkSuitability": ["None"],
                               "bPlayerWorkable": ["False"], "bBaseCampWorkerWorkable": ["False"]}:
        raise RuntimeError("Converter assignment readback mismatch: " + repr(assignment_readback))
    library.save_loaded_asset(assignment_table, only_if_is_dirty=False)

    _, saved_converter = find("PAE_Converter")
    if list(saved_converter.get_editor_property("target_types_a")) != [unreal.PalItemTypeA.CONSUME]:
        raise RuntimeError("Converter output major category readback mismatch")
    if list(saved_converter.get_editor_property("target_types_b")) != [crystal_type]:
        raise RuntimeError("Converter output filter readback mismatch")
    if list(saved_converter.get_editor_property("material_types_b")) != [crystal_type]:
        raise RuntimeError("Converter input filter readback mismatch")
    report = {
        "scope": "Unreal editor asset authoring and FPalItemRecipe import only; game functions are SDK stubs",
        "blueprint": path,
        "model": cdo.get_editor_property("concrete_model_class").get_path_name(),
        "output_major_type": str(unreal.PalItemTypeA.CONSUME),
        "input_type": str(crystal_type),
        "output_type": str(crystal_type),
        "assignment": assignment_readback,
        "visual": visual_report,
        "recipes": {name: {"output": pair[0], "input": pair[1]} for name, pair in imported.items()},
        "game_runtime_tested": False,
    }
    (ROOT / "build/editor-check.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    unreal.log("[PAE] EDITOR_CHECK_OK " + json.dumps(report))


if __name__ == "__main__":
    main()
    runpy.run_path(str(ROOT / "unreal/create_containment_probe.py"), run_name="__main__")
