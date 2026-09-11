"""Author a small one-slot native DisplayCharacter containment probe.

This script only authors editor assets.  It does not test native game
storage, save, retrieval, or demolition behavior.
"""
import json
from pathlib import Path

import unreal


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = "/Game/PalAwakeningExchange"
ASSET_NAME = "BP_PAE_ContainmentProbe"
CONTROLLER_ASSET = "/Game/Pal/Blueprint/Controller/Monster/BP_MonsterAIController_BaseCamp"
CONTROLLER_CLASS_PATH = CONTROLLER_ASSET + ".BP_MonsterAIController_BaseCamp_C"
WIDGET_ASSET = "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/WBP_IngameMenu_CommonCharacterContainer"
WIDGET_CLASS_PATH = WIDGET_ASSET + ".WBP_IngameMenu_CommonCharacterContainer_C"


def _load_class(path):
    value = unreal.load_class(None, path)
    if not value:
        raise RuntimeError("Required native class is unavailable: " + path)
    return value


def _ensure_class_or_local_dummy(library, assets, class_path, asset_path, parent_path):
    value = unreal.load_class(None, class_path)
    if value:
        return value, False

    parent = _load_class(parent_path)
    package_path, asset_name = asset_path.rsplit("/", 1)
    asset = library.load_asset(asset_path) if library.does_asset_exist(asset_path) else None
    if not asset:
        factory = unreal.BlueprintFactory()
        factory.set_editor_property("parent_class", parent)
        asset = assets.create_asset(asset_name, package_path, unreal.Blueprint, factory)
    unreal.BlueprintEditorLibrary.compile_blueprint(asset)
    value = library.load_blueprint_class(asset_path)
    if not value:
        raise RuntimeError("Could not create local dummy class: " + class_path)
    library.save_loaded_asset(asset, only_if_is_dirty=False)
    return value, True


def main():
    library = unreal.EditorAssetLibrary
    assets = unreal.AssetToolsHelpers.get_asset_tools()
    subsystem = unreal.get_engine_subsystem(unreal.SubobjectDataSubsystem)
    handles = unreal.SubobjectDataBlueprintFunctionLibrary
    path = ASSET_ROOT + "/" + ASSET_NAME

    controller_class, controller_dummy = _ensure_class_or_local_dummy(
        library, assets, CONTROLLER_CLASS_PATH, CONTROLLER_ASSET,
        "/Script/Pal.PalAIController")
    widget_class, widget_dummy = _ensure_class_or_local_dummy(
        library, assets, WIDGET_CLASS_PATH, WIDGET_ASSET,
        "/Script/Pal.PalUserWidgetOverlayUI")

    bp = library.load_asset(path) if library.does_asset_exist(path) else None
    if not bp:
        factory = unreal.BlueprintFactory()
        factory.set_editor_property("parent_class", _load_class("/Script/Pal.PalBuildObject"))
        bp = assets.create_asset(ASSET_NAME, ASSET_ROOT, unreal.Blueprint, factory)
    unreal.BlueprintEditorLibrary.compile_blueprint(bp)

    def find(name):
        for handle in subsystem.k2_gather_subobject_data_for_blueprint(bp):
            obj = handles.get_object(handles.get_data(handle))
            if obj.get_name() in (name, name + "_GEN_VARIABLE"):
                return handle, obj
        return None, None

    actor = subsystem.k2_gather_subobject_data_for_blueprint(bp)[0]
    root_handle, _ = find("PAE_Root")
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
                parent_handle=root_handle if scene else actor,
                new_class=cls,
                blueprint_context=bp))
            if str(reason):
                raise RuntimeError(str(reason))
            subsystem.rename_subobject(handle, unreal.Text(name))
            obj = handles.get_object(handles.get_data(handle))
        if scene:
            subsystem.attach_subobject(root_handle, handle)
        return obj

    cube = library.load_asset("/Engine/BasicShapes/Cube")
    platform = component("PAE_Platform", unreal.StaticMeshComponent, True)
    platform.set_editor_property("static_mesh", cube)
    platform.set_editor_property("relative_location", unreal.Vector(0, 0, 10))
    platform.set_editor_property("relative_scale3d", unreal.Vector(2.4, 2.4, 0.2))
    platform.set_collision_profile_name("BlockAll")

    for name, x, y in (
        ("PAE_Pillar_NW", -80, -80),
        ("PAE_Pillar_NE", 80, -80),
        ("PAE_Pillar_SW", -80, 80),
        ("PAE_Pillar_SE", 80, 80),
    ):
        pillar = component(name, unreal.StaticMeshComponent, True)
        pillar.set_editor_property("static_mesh", cube)
        pillar.set_editor_property("relative_location", unreal.Vector(x, y, 75))
        pillar.set_editor_property("relative_scale3d", unreal.Vector(0.12, 0.12, 1.5))
        pillar.set_collision_profile_name("BlockAll")

    build_bounds = component("PAE_BuildBounds", unreal.BoxComponent, True)
    build_bounds.set_editor_property("box_extent", unreal.Vector(120, 120, 90))
    build_bounds.set_editor_property("relative_location", unreal.Vector(0, 0, 90))
    build_bounds.set_editor_property("generate_overlap_events", False)
    build_bounds.set_collision_profile_name("NoCollision")

    work_bounds = component("BuildWorkableBounds", unreal.BoxComponent, True)
    work_bounds.set_editor_property("box_extent", unreal.Vector(100, 100, 75))
    work_bounds.set_editor_property("relative_location", unreal.Vector(0, 0, 45))
    work_bounds.set_editor_property("generate_overlap_events", False)
    work_bounds.set_collision_profile_name("NoCollision")

    interact = component("PAE_Interact", _load_class(
        "/Script/Pal.PalInteractiveObjectBoxComponent"), True)
    interact.set_editor_property("box_extent", unreal.Vector(130, 130, 100))
    interact.set_editor_property("relative_location", unreal.Vector(0, 0, 60))
    interact.set_editor_property("is_enable_trigger_interact", True)
    interact.set_editor_property("is_implemented_trigger_interact", True)
    interact.set_editor_property("is_enable_interacting_tick", False)
    interact.set_editor_property("generate_overlap_events", True)
    interact.set_collision_profile_name("OverlapAllDynamic")

    limit_volume = component("PalLimitVolumeBoxComponent", _load_class(
        "/Script/Pal.PalLimitVolumeBoxComponent"), True)
    limit_volume.set_editor_property("box_extent", unreal.Vector(100, 100, 85))
    limit_volume.set_editor_property("relative_location", unreal.Vector(0, 0, 85))
    limit_volume.set_editor_property("generate_overlap_events", False)
    limit_volume.set_collision_profile_name("NoCollision")

    facing = component("PAE_WorkFacing", _load_class(
        "/Script/Pal.PalWorkFacingComponent"), True)
    facing.set_editor_property("relative_location", unreal.Vector(120, 0, 0))
    facing.set_editor_property("relative_rotation", unreal.Rotator(0, 0, 180))

    parameter = component("PAE_DisplayCharacterParameters", _load_class(
        "/Script/Pal.PalMapObjectDisplayCharacterParameterComponent"))
    parameter.set_editor_property("slot_num", 1)
    parameter.set_editor_property("recover_amount_by_sec", 0.0)
    parameter.set_editor_property("controller_class", controller_class)
    parameter.set_editor_property("menu_ui_widget_class", widget_class)
    parameter.set_editor_property("character_spawn_local_transform", unreal.Transform(
        location=unreal.Vector(0, 0, 25), rotation=unreal.Rotator(0, 0, 0), scale=unreal.Vector(1, 1, 1)))

    unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    generated_class = library.load_blueprint_class(path)
    cdo = unreal.get_default_object(generated_class)
    cdo.set_editor_property("concrete_model_class", _load_class(
        "/Script/Pal.PalMapObjectDisplayCharacterModel"))
    cdo.set_editor_property("replicates", True)
    cdo.set_editor_property("build_object_id", "PAE_ContainmentProbe")
    for prop, name in (("overlap_check_collision_ref", "PAE_BuildBounds"),
                       ("main_mesh_ref", "PAE_Platform")):
        ref = unreal.ComponentReference()
        ref.set_editor_property("component_property", name)
        cdo.set_editor_property(prop, ref)
    library.save_loaded_asset(bp, only_if_is_dirty=False)

    _, parameter = find("PAE_DisplayCharacterParameters")
    report = {
        "scope": "Unreal editor asset authoring only; native game storage behavior is unverified",
        "blueprint": path,
        "model": cdo.get_editor_property("concrete_model_class").get_path_name(),
        "build_object_id": str(cdo.get_editor_property("build_object_id")),
        "replicates": bool(cdo.get_editor_property("replicates")),
        "slot_num": int(parameter.get_editor_property("slot_num")),
        "recover_amount_by_sec": float(parameter.get_editor_property("recover_amount_by_sec")),
        "controller_class": parameter.get_editor_property("controller_class").get_path_name(),
        "menu_ui_widget_class": parameter.get_editor_property("menu_ui_widget_class").get_path_name(),
        "controller_dummy": controller_dummy,
        "widget_dummy": widget_dummy,
        "game_runtime_tested": False,
    }
    if report["slot_num"] != 1 or report["recover_amount_by_sec"] != 0.0:
        raise RuntimeError("Containment parameter readback mismatch")
    if report["controller_class"] != CONTROLLER_CLASS_PATH or report["menu_ui_widget_class"] != WIDGET_CLASS_PATH:
        raise RuntimeError("Containment native class references changed")
    (ROOT / "build/containment-editor-check.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8")
    unreal.log("[PAE] CONTAINMENT_EDITOR_CHECK_OK " + json.dumps(report))


if __name__ == "__main__":
    main()
