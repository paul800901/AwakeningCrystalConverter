"""Import the actual Blender mesh and matched material palette."""
import unreal
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
DEST='/Game/PalAwakeningExchange/WaferV2'
def author_visual(bp,component,library):
    assets=unreal.AssetToolsHelpers.get_asset_tools();ed=unreal.MaterialEditingLibrary
    mats={}
    for name,p in json.loads((ROOT/'art/blender/palette.json').read_text()).items():
        path=DEST+'/'+name
        m=library.load_asset(path) if library.does_asset_exist(path) else assets.create_asset(name,DEST,unreal.Material,unreal.MaterialFactoryNew())
        ed.delete_all_material_expressions(m)
        # The inset crystal emblems have single-sided faces; render both sides.
        m.set_editor_property('two_sided',name in ('M_PRF_StatusCyan','M_PRF_StatusAmber'))
        c=ed.create_material_expression(m,unreal.MaterialExpressionConstant3Vector,0,0)
        c.set_editor_property('constant',unreal.LinearColor(*p['color'],1));ed.connect_material_property(c,'',unreal.MaterialProperty.MP_BASE_COLOR)
        for prop,val in ((unreal.MaterialProperty.MP_METALLIC,p['metal']),(unreal.MaterialProperty.MP_ROUGHNESS,p['rough'])):
            e=ed.create_material_expression(m,unreal.MaterialExpressionConstant,0,100);e.set_editor_property('r',val);ed.connect_material_property(e,'',prop)
        if p['emission']:
            e=ed.create_material_expression(m,unreal.MaterialExpressionConstant3Vector,0,200)
            e.set_editor_property('constant',unreal.LinearColor(*(v*min(p['emission'],.6) for v in p['color']),1));ed.connect_material_property(e,'',unreal.MaterialProperty.MP_EMISSIVE_COLOR)
        ed.recompile_material(m);library.save_loaded_asset(m);mats[name]=m
    meshes={}
    for name in ('SM_PAE_WaferConverter','SM_PAE_Status'):
        task=unreal.AssetImportTask();task.filename=str(ROOT/'art/blender/models'/ (name+'.fbx'));task.destination_path=DEST;task.destination_name=name;task.automated=True;task.replace_existing=True;task.save=True
        opt=unreal.FbxImportUI();opt.import_mesh=True;opt.import_materials=False;opt.import_textures=False;opt.import_as_skeletal=False;opt.mesh_type_to_import=unreal.FBXImportType.FBXIT_STATIC_MESH
        opt.static_mesh_import_data.combine_meshes=True;opt.static_mesh_import_data.auto_generate_collision=True;opt.static_mesh_import_data.import_uniform_scale=100.0
        task.options=opt;assets.import_asset_tasks([task]);mesh=library.load_asset(DEST+'/'+name)
        if not isinstance(mesh,unreal.StaticMesh):raise RuntimeError(task.imported_object_paths)
        for i,entry in enumerate(mesh.get_editor_property('static_materials')):mesh.set_material(i,mats[str(entry.get_editor_property('imported_material_slot_name'))])
        library.save_loaded_asset(mesh);meshes[name]=mesh
    sub=unreal.get_engine_subsystem(unreal.SubobjectDataSubsystem)
    for h in sub.k2_gather_subobject_data_for_blueprint(bp):
        obj=unreal.SubobjectDataBlueprintFunctionLibrary.get_object(unreal.SubobjectDataBlueprintFunctionLibrary.get_data(h))
        if isinstance(obj,(unreal.StaticMeshComponent,unreal.TextRenderComponent)):
            obj.set_editor_property('visible',False);obj.set_editor_property('hidden_in_game',True)
            if isinstance(obj,unreal.StaticMeshComponent):obj.set_collision_profile_name('NoCollision')
    for name,mesh in (('PAE_Body',meshes['SM_PAE_WaferConverter']),('PAE_ConversionGlow_0',meshes['SM_PAE_Status'])):
        obj=component(name,unreal.StaticMeshComponent,True);obj.set_editor_property('static_mesh',mesh);obj.set_editor_property('override_materials',[])
        obj.set_editor_property('relative_location',unreal.Vector(0,0,0));obj.set_editor_property('relative_rotation',unreal.Rotator(pitch=0,yaw=-90,roll=0));obj.set_editor_property('relative_scale3d',unreal.Vector(1,1,1))
        obj.set_editor_property('visible',True);obj.set_editor_property('hidden_in_game',False);obj.set_collision_profile_name('BlockAll' if name=='PAE_Body' else 'NoCollision')
    icon=unreal.AssetImportTask()
    icon.filename=str(ROOT/'art/blender/previews/hero.png')
    icon.destination_path=DEST;icon.destination_name='T_PAE_ConverterIcon'
    icon.factory=unreal.TextureFactory()
    icon.automated=True;icon.replace_existing=True;icon.save=True
    assets.import_asset_tasks([icon])
    texture=library.load_asset(DEST+'/T_PAE_ConverterIcon')
    if not texture:
        raise RuntimeError('Icon import failed: '+str(icon.imported_object_paths))
    texture.set_editor_property('lod_group',unreal.TextureGroup.TEXTUREGROUP_UI)
    texture.set_editor_property('max_texture_size',256)
    library.save_loaded_asset(texture)
    return {'model':'Blender WaferV2','mesh':meshes['SM_PAE_WaferConverter'].get_path_name(),'yaw':-90,'icon':texture.get_path_name()}
