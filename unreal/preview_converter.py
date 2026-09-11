"""Render the authored machine for local visual inspection; never touch game files.

Launch through ``build/preview_converter.ps1``.  UE 5.1's source uses the
case-insensitive ``-noshaderworker`` command-line parameter to disable the
external ShaderCompileWorker processes for this isolated preview.  The engine
then uses its local compiler thread, avoiding the worker IPC stall seen during
the first commandlet render.
"""
import unreal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
world = unreal.EditorLevelLibrary.get_editor_world()
if not world:
    raise RuntimeError('Preview editor world is unavailable')
bp = unreal.EditorAssetLibrary.load_blueprint_class('/Game/PalAwakeningExchange/BP_PAE_ExchangePrototype')
if not bp:
    raise RuntimeError('Preview blueprint is unavailable')
actor = unreal.EditorLevelLibrary.spawn_actor_from_class(bp, unreal.Vector(0, 0, 0))
if not actor:
    raise RuntimeError('Preview actor spawn failed')
light = unreal.EditorLevelLibrary.spawn_actor_from_class(unreal.DirectionalLight, unreal.Vector(200, -100, 400), unreal.Rotator(-35, -135, 0))
light.light_component.set_editor_property('intensity', 6.0)
fill = unreal.EditorLevelLibrary.spawn_actor_from_class(unreal.DirectionalLight, unreal.Vector(-100, 300, 300), unreal.Rotator(-25, 45, 0))
fill.light_component.set_editor_property('intensity', 2.0)
position = unreal.Vector(370, -285, 235)
rotation = unreal.MathLibrary.find_look_at_rotation(position, unreal.Vector(0, 0, 85))
camera = unreal.EditorLevelLibrary.spawn_actor_from_class(unreal.SceneCapture2D, position, rotation)
capture = camera.capture_component2d
target = unreal.RenderingLibrary.create_render_target2d(world, 1024, 1024, unreal.TextureRenderTargetFormat.RTF_RGBA8)
capture.set_editor_property('texture_target', target)
capture.set_editor_property('capture_source', unreal.SceneCaptureSource.SCS_FINAL_COLOR_LDR)
capture.set_editor_property('fov_angle', 35.0)
capture.set_editor_property('capture_every_frame', False)
unreal.log('[PAE] PREVIEW_CAPTURE_START position=%s target=(0,0,85)' % position)
capture.capture_scene()
unreal.RenderingLibrary.export_render_target(world, target, str(ROOT / 'build'), 'converter-preview.png')
unreal.log('[PAE] PREVIEW_EXPORTED path=%s' % str(ROOT / 'build' / 'converter-preview.png'))
