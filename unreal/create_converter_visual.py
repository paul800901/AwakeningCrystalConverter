"""Author the wafer-process shell for the Awakening Crystal Converter.

This module only authors Blueprint scene components and local materials.  It
does not add Pal character meshes or change any of the converter's gameplay
parameters.  ``author_visual`` is intentionally shaped for the ``component``
helper used by the other authoring scripts::

    import create_converter_visual
    create_converter_visual.author_visual(bp, component, unreal.EditorAssetLibrary)

Conversion state is represented by controllable ``PAE_ConversionGlow_0..N``
components.  The runtime can keep them on the idle material or swap them to
``/Game/PalAwakeningExchange/Visual/PAE_ConversionWorking`` while processing.
"""

from pathlib import Path

import unreal


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = "/Game/PalAwakeningExchange"
MATERIAL_ROOT = ASSET_ROOT + "/Visual"


def _asset(library, path):
    return library.load_asset(path) if library.does_asset_exist(path) else None


def _ensure_material(library, assets, name, color, *, opacity=1.0,
                     emissive=None, roughness=0.45, metallic=0.0,
                     two_sided=False):
    """Create one small, dependency-free material and return it."""
    path = MATERIAL_ROOT + "/" + name
    material = _asset(library, path)
    if material:
        return material

    material = assets.create_asset(name, MATERIAL_ROOT, unreal.Material,
                                   unreal.MaterialFactoryNew())
    if not material:
        raise RuntimeError("Could not create visual material: " + path)

    material.set_editor_property("two_sided", two_sided)
    if opacity < 1.0:
        material.set_editor_property("blend_mode", unreal.BlendMode.BLEND_TRANSLUCENT)

    editing = unreal.MaterialEditingLibrary

    def color_expression(value, x, y):
        expression = editing.create_material_expression(
            material, unreal.MaterialExpressionConstant3Vector, x, y)
        expression.set_editor_property(
            "constant", unreal.LinearColor(value[0], value[1], value[2], 1.0))
        return expression

    def scalar_expression(value, x, y):
        expression = editing.create_material_expression(
            material, unreal.MaterialExpressionConstant, x, y)
        expression.set_editor_property("r", float(value))
        return expression

    base = color_expression(color, -400, -80)
    editing.connect_material_property(base, "", unreal.MaterialProperty.MP_BASE_COLOR)

    rough = scalar_expression(roughness, -400, 80)
    editing.connect_material_property(rough, "", unreal.MaterialProperty.MP_ROUGHNESS)
    metal = scalar_expression(metallic, -400, 160)
    editing.connect_material_property(metal, "", unreal.MaterialProperty.MP_METALLIC)

    if opacity < 1.0:
        alpha = scalar_expression(opacity, -400, 240)
        editing.connect_material_property(alpha, "", unreal.MaterialProperty.MP_OPACITY)
    if emissive is not None:
        glow = color_expression(emissive, -400, 320)
        editing.connect_material_property(glow, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)

    editing.recompile_material(material)
    library.save_loaded_asset(material, only_if_is_dirty=False)
    return material


def _materials(library):
    assets = unreal.AssetToolsHelpers.get_asset_tools()
    white = _ensure_material(library, assets, "PAE_WhiteBody",
                             (0.88, 0.91, 0.94), roughness=0.28, metallic=0.18)
    dark = _ensure_material(library, assets, "PAE_DarkFrame",
                            (0.025, 0.04, 0.055), roughness=0.24, metallic=0.65)
    steel = _ensure_material(library, assets, "PAE_Steel",
                             (0.32, 0.38, 0.43), roughness=0.3, metallic=0.8)
    screen = _ensure_material(library, assets, "PAE_ControlScreen",
                              (0.03, 0.18, 0.24), emissive=(0.0, 0.42, 0.62),
                              roughness=0.18, metallic=0.25)
    glass = _ensure_material(library, assets, "PAE_ObservationGlass",
                             (0.22, 0.42, 0.52), opacity=0.18,
                             emissive=(0.0, 0.035, 0.05), roughness=0.08,
                             metallic=0.05, two_sided=True)
    conversion_idle = _ensure_material(
        library, assets, "PAE_ConversionIdle", (0.02, 0.18, 0.24),
        emissive=(0.03, 0.16, 0.24), roughness=0.2, metallic=0.2)
    conversion_working = _ensure_material(
        library, assets, "PAE_ConversionWorking", (1.0, 0.68, 0.03),
        emissive=(4.0, 2.6, 0.08), roughness=0.24, metallic=0.08)
    wafer = _ensure_material(library, assets, "PAE_WaferRainbow",
                             (0.12, 0.28, 0.62), emissive=(0.04, 0.11, 0.26),
                             roughness=0.2, metallic=0.55)
    die = _ensure_material(library, assets, "PAE_WaferDie",
                           (0.72, 0.84, 0.9), emissive=(0.05, 0.14, 0.2),
                           roughness=0.2, metallic=0.45)
    rainbow = []
    for name, color, glow in (
        ("PAE_RainbowRed", (0.95, 0.05, 0.04), (0.35, 0.01, 0.0)),
        ("PAE_RainbowGold", (1.0, 0.48, 0.02), (0.4, 0.08, 0.0)),
        ("PAE_RainbowGreen", (0.04, 0.82, 0.28), (0.0, 0.24, 0.04)),
        ("PAE_RainbowCyan", (0.02, 0.7, 0.9), (0.0, 0.25, 0.42)),
        ("PAE_RainbowBlue", (0.08, 0.2, 0.95), (0.02, 0.05, 0.36)),
        ("PAE_RainbowViolet", (0.62, 0.08, 0.9), (0.18, 0.01, 0.35)),
    ):
        rainbow.append(_ensure_material(library, assets, name, color,
                                        emissive=glow, roughness=0.18,
                                        metallic=0.38))
    return {
        "white": white, "dark": dark, "steel": steel, "screen": screen,
        "glass": glass,
        "conversion_idle": conversion_idle,
        "conversion_working": conversion_working,
        "wafer": wafer,
        "die": die, "rainbow": rainbow,
    }


def _visual_component(component, name, mesh, material, location, scale,
                      rotation=None):
    value = component(name, unreal.StaticMeshComponent, True)
    value.set_editor_property("static_mesh", mesh)
    value.set_editor_property("relative_location", unreal.Vector(*location))
    value.set_editor_property("relative_scale3d", unreal.Vector(*scale))
    if rotation is not None:
        value.set_editor_property("relative_rotation", unreal.Rotator(*rotation))
    if material is not None:
        value.set_material(0, material)
    value.set_collision_profile_name("NoCollision")
    return value


def _button(component, cube, material, name, y, z):
    return _visual_component(component, name, cube, material,
                             (52, y, z), (0.05, 0.08, 0.055))


def _crystal(component, cone, name, material, y, x=18):
    """Make a stylised faceted crystal from two opposing BasicShapes cones."""
    _visual_component(component, name + "_Upper", cone, material,
                      (x, y, 93), (0.22, 0.22, 0.25))
    _visual_component(component, name + "_Lower", cone, material,
                      (x, y, 67), (0.22, 0.22, 0.25), (180, 0, 0))


def _energy_link(component, cube, material, name, location, scale, rotation=None):
    return _visual_component(component, name, cube, material, location, scale,
                             rotation)


def author_visual(bp, component, library):
    """Add/update the converter's visual components and return material paths.

    ``bp`` is accepted for the same call signature as the parent authoring
    script; component lookup/creation remains the source of truth for edits.
    """
    del bp
    materials = _materials(library)
    cube = _asset(library, "/Engine/BasicShapes/Cube")
    cylinder = _asset(library, "/Engine/BasicShapes/Cylinder")
    sphere = _asset(library, "/Engine/BasicShapes/Sphere")
    cone = _asset(library, "/Engine/BasicShapes/Cone")
    if not cube or not cylinder or not sphere or not cone:
        raise RuntimeError("Required Engine BasicShapes assets are unavailable")

    # White semiconductor process housing and a large front observation window.
    body = component("PAE_Body", unreal.StaticMeshComponent, True)
    body.set_editor_property("static_mesh", cube)
    body.set_editor_property("relative_location", unreal.Vector(0, 0, 82))
    body.set_editor_property("relative_scale3d", unreal.Vector(0.72, 1.05, 1.52))
    body.set_material(0, materials["white"])

    _visual_component(component, "PAE_ObservationFrame", cube, materials["dark"],
                      (38, 0, 100), (0.08, 0.78, 0.66))
    _visual_component(component, "PAE_ObservationWindow", cube, materials["glass"],
                      (43, 0, 100), (0.035, 0.68, 0.56))

    # The wafer is deliberately a front-facing disk.  Colored bars and a grid
    # of square dies make the rainbow reflection and semiconductor layout read
    # clearly even at the game's normal build-distance camera.
    _visual_component(component, "PAE_WaferRainbow", cylinder, materials["wafer"],
                      # Cylinder's local Z axis must be pitched into +X.  Yaw
                      # rotates around Z and would leave the wafer edge-on.
                      (48, 0, 103), (0.58, 0.58, 0.055), (90, 0, 0))
    for index, material in enumerate(materials["rainbow"]):
        z = 84 + index * 7.6
        _visual_component(component, "PAE_WaferRainbowBand_%d" % index,
                          cube, material, (53, 0, z), (0.025, 0.18, 0.012))
    for row in range(5):
        for col in range(5):
            y = -20 + col * 10
            z = 87 + row * 8
            die_material = materials["rainbow"][(row + col) % 6]
            _visual_component(component, "PAE_WaferDie_%02d" % (row * 5 + col),
                              cube, die_material, (54, y, z),
                              (0.024, 0.065, 0.055))

    # Simple robotic arm and its control panel.
    _visual_component(component, "PAE_ArmMast", cube, materials["steel"],
                      (30, 30, 112), (0.14, 0.14, 0.92))
    _visual_component(component, "PAE_ArmReach", cube, materials["steel"],
                      (42, 15, 126), (0.32, 0.12, 0.10), (0, 0, -20))
    _visual_component(component, "PAE_ArmGripper", sphere, materials["dark"],
                      (53, 2, 116), (0.10, 0.10, 0.10))
    _visual_component(component, "PAE_ControlPanel", cube, materials["dark"],
                      (49, -38, 74), (0.08, 0.34, 0.36), (0, 0, -12))
    _visual_component(component, "PAE_ControlScreen", cube, materials["screen"],
                      (54, -38, 84), (0.025, 0.23, 0.12), (0, 0, -12))
    _button(component, cube, materials["conversion_working"], "PAE_ControlButton_0", -49, 70)
    _button(component, cube, materials["rainbow"][2], "PAE_ControlButton_1", -39, 70)
    _button(component, cube, materials["rainbow"][4], "PAE_ControlButton_2", -29, 70)

    # Two side cradles show the input/output direction.  The game decides
    # which item is accepted; these are intentionally generic prototype gems.
    red = _ensure_material(library, unreal.AssetToolsHelpers.get_asset_tools(),
                           "PAE_CrystalRed", (0.8, 0.03, 0.02),
                           emissive=(0.32, 0.0, 0.0), roughness=0.2, metallic=0.3)
    blue = _ensure_material(library, unreal.AssetToolsHelpers.get_asset_tools(),
                            "PAE_CrystalBlue", (0.02, 0.22, 0.92),
                            emissive=(0.0, 0.08, 0.42), roughness=0.2, metallic=0.3)
    violet = _ensure_material(library, unreal.AssetToolsHelpers.get_asset_tools(),
                              "PAE_CrystalVioletGold", (0.55, 0.08, 0.82),
                              emissive=(0.18, 0.01, 0.32), roughness=0.2, metallic=0.35)
    for name, y, material in (("PAE_InputCrystal", -68, red),
                              ("PAE_OutputCrystal", 68, blue)):
        _visual_component(component, name + "_Cradle", cylinder, materials["steel"],
                          (18, y, 38), (0.32, 0.32, 0.10))
        _crystal(component, cone, name, material, y)
        _visual_component(component, name + "_Collar", cylinder, materials["dark"],
                          (18, y, 80), (0.27, 0.27, 0.06))
    # A smaller violet/gold faceted core sits in the exchange chamber.
    _visual_component(component, "PAE_ConversionCrystal_Upper", cone, violet,
                      (62, 0, 59), (0.12, 0.12, 0.14))
    _visual_component(component, "PAE_ConversionCrystal_Lower", cone, violet,
                      (62, 0, 45), (0.12, 0.12, 0.14), (180, 0, 0))

    # Energy rails feed both cradles into the front conversion chamber.
    for index, y in enumerate((-58, 58)):
        _energy_link(component, cube, materials["conversion_idle"],
                     "PAE_EnergyRail_%d" % index, (58, y * 0.5, 62),
                     (0.08, 0.46, 0.055), (0, 0, 0))
        _visual_component(component, "PAE_EnergyNode_%d" % index, sphere,
                          materials["conversion_idle"], (58, y * 0.5, 62),
                          (0.10, 0.10, 0.10))

    # Glow nodes are deliberately separate components so root can toggle the
    # whole conversion pulse without looking up material graph expressions.
    glow_points = ((58, -34, 132), (58, 34, 132), (58, -18, 62),
                   (58, 18, 62), (58, 0, 140), (58, 0, 55))
    for index, location in enumerate(glow_points):
        _visual_component(component, "PAE_ConversionGlow_%d" % index, sphere,
                          materials["conversion_idle"], location,
                          (0.08, 0.08, 0.08))

    # A small readable Taiwan/Formosa marker supplies the local semiconductor
    # cue without importing a logo or flag asset.
    label = component("PAE_TaiwanLabel", unreal.TextRenderComponent, True)
    label.set_editor_property("text", unreal.Text("FORMOSA / TAIWAN"))
    label.set_editor_property("world_size", 8.0)
    label.set_editor_property("relative_location", unreal.Vector(40, 43, 39))
    label.set_editor_property("relative_rotation", unreal.Rotator(0, 0, 0))
    label.set_editor_property("text_render_color", unreal.Color(30, 140, 170, 255))

    return {
        "material_root": MATERIAL_ROOT,
        "conversion_glow_components": ["PAE_ConversionGlow_%d" % i for i in range(6)],
        "conversion_idle_material": MATERIAL_ROOT + "/PAE_ConversionIdle",
        "conversion_working_material": MATERIAL_ROOT + "/PAE_ConversionWorking",
        "wafer_material": MATERIAL_ROOT + "/PAE_WaferRainbow",
    }


if __name__ == "__main__":
    raise SystemExit("Import this module and call author_visual(bp, component, library)")
