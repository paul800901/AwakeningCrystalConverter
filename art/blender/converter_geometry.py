"""Original wafer converter. Run via build_converter.py in existing Blender."""
import colorsys
col=collection('PAE_WaferConverter')
feet(3.1,2.05)
box('Foundation',(0,0,.29),(3.1,2.05,.25),'dark',.09)
box('Gold_plinth',(0,0,.44),(3.02,1.98,.065),'brass',.025)
box('Deck',(0,0,.50),(2.97,1.93,.10),'ivory',.035)
# Deep process enclosure, with separately fitted panels and recessed wafer stage.
box('Process_chassis',(-.26,.24,1.58),(1.98,1.34,2.08),'dark',.12)
box('Top_lid',(-.26,.20,2.64),(2.13,1.48,.19),'ivory',.075)
box('Top_inset',(-.26,.25,2.755),(1.65,1.08,.045),'steel',.025)
for x in (-1.24,.72):
    front_panel('Structural_pillar',(x,-.47,1.64),(.19,.25,1.88))
    box('Pillar_inlay',(x,-.602,1.7),(.027,.016,1.4),'brass',.008)
front_panel('Upper_fascia',(-.26,-.51,2.45),(1.68,.18,.22))
text('Header','FORMOSA  /  CRYSTAL FOUNDRY',(-.26,-.608,2.45),.067,'dark')
front_panel('Lower_access',(-.26,-.51,.81),(1.68,.18,.45))
box('Nameplate',(-.26,-.61,.82),(1.04,.025,.17),'dark',.015)
text('Origin','TAIWAN  •  ACC-74',(-.26,-.629,.82),.069)
box('Stage_back',(-.26,-.465,1.66),(1.55,.12,1.23),'black',.045)
cyl('Wafer_chuck',(-.26,-.57,1.7),.60,.10,'steel','Y',96,.012)
ring('Chuck_bezel',(-.26,-.632,1.7),.585,.025,'brass','Y',96)
cyl('Silicon_disc',(-.26,-.638,1.7),.548,.016,'dark','Y',128,.003)
# Real thin wafer, coplanar die pattern; no separated floating grid.
for i in range(-7,8):
    M['die'+str(i)]=material('PAE_Die_%02d'%(i+7),colorsys.hsv_to_rgb((.58+i*.025)%1,.63,.37),.78,.23)
for i in range(-7,8):
    for j in range(-7,8):
        if (abs(i)*.068+.03)**2+(abs(j)*.068+.03)**2 < .527**2:
            box('Silicon_die',(-.26+i*.068,-.650,1.7+j*.068),(.061,.002,.061),'die'+str(i),.001)
# Three clamp fingers and an offset inspection head convey a working process.
for a in (30,150,270):
    x=-.26+.54*cos(radians(a)); z=1.7+.54*sin(radians(a))
    box('Wafer_clamp',(x,-.682,z),(.12,.07,.065),'steel',.016,rot=(0,radians(-a),0))
box('Scan_crossrail',(-.26,-.72,2.28),(1.47,.11,.09),'steel',.023)
box('Optical_head',(.25,-.755,2.21),(.26,.21,.23),'ivory',.035)
box('Scan_lens',(.25,-.871,2.17),(.15,.022,.06),'cyan',.007)
# Separate source/product load-lock doors, physically integrated, not loose crystals.
for x,z,label in ((1.12,1.03,'01  FEED'),(1.12,1.88,'02  PRODUCT')):
    box('Loadlock_body',(x,.02,z),(.69,1.30,.71),'dark',.065)
    front_panel('Loadlock_door',(x,-.66,z),(.63,.15,.62))
    cyl('Loadlock_window',(x,-.749,z+.02),.215,.02,'black','Y',48,.008)
    ring('Loadlock_trim',(x,-.766,z+.02),.219,.023,'brass','Y',48)
    # Small faceted crystal symbol seated behind the bezel.
    points=[(x,-.789,z+.17),(x+.085,-.789,z+.02),(x,-.789,z-.13),(x-.085,-.789,z+.02),(x,-.825,z+.02)]
    mesh=bpy.data.meshes.new('Crystal_emblem'); mesh.from_pydata(points,[],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)]);mesh.update()
    ob=bpy.data.objects.new('Contained_crystal',mesh);CURRENT.objects.link(ob);mesh.materials.append(M['cyan' if z<1.5 else 'amber'])
    text('Port_caption',label,(x,-.748,z-.235),.052,'dark')
    box('Dock_sill',(x,-.78,z-.37),(.70,.37,.09),'steel',.025)
# Attached operator panel, cooling assembly, rear service panels.
box('Console_mount',(.49,-.83,1.05),(.37,.31,.14),'dark',.025)
box('Console',(.49,-.97,1.19),(.48,.15,.34),'dark',.04)
box('Console_screen',(.49,-1.051,1.23),(.37,.014,.18),'cyan',.008)
text('Screen_text','1 : 1',(.49,-1.065,1.23),.086,'dark')
for x in (.35,.49,.63): cyl('Console_key',(x,-1.058,1.09),.023,.014,'brass','Y',16,.002)
front_panel('Rear_service',(-.26,.943,1.56),(1.65,.09,1.72))
for z in [1.10+i*.11 for i in range(9)]:
    box('Rear_vent',(-.26,1.002,z),(1.16,.025,.043),'dark',.01)
for x in (-1.30,1.48):
    pipe('Power_conduit',[(x,.60,.50),(x,.68,.9),(x,.68,2.25),(x,.68,2.43),(-1.10 if x<0 else .60,.50,2.48)],.045,'steel')
    for z in (.94,1.58,2.16): box('Conduit_clamp',(x,.68,z),(.13,.13,.08),'brass',.01)
box('Status_strip',(-.26,-.622,2.60),(1.30,.025,.032),'cyan',.01)
warning_band('High_voltage',(-.26,-.62,.585),1.45,.055)
# Apply geometry and preserve editable file. Export body/status separately.
bpy.ops.object.select_all(action='DESELECT')
for o in list(col.objects):
    o.select_set(True)
bpy.context.view_layer.objects.active=list(col.objects)[0]
bpy.ops.object.convert(target='MESH')
bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
for o in col.objects:
    if not o.data.uv_layers: o.data.uv_layers.new(name='UVMap')
palette={m.name: {'color':list(m.diffuse_color[:3]),'metal':m.node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value,'rough':m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value,'emission':m.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value} for m in M.values()}
(OUT/'palette.json').write_text(json.dumps(palette,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'models/Converter_editable.blend'))
objects=list(col.objects)
groups={flag:[o for o in objects if o.name.startswith('Status_strip')==flag] for flag in (False,True)}
for status in (False,True):
    bpy.ops.object.select_all(action='DESELECT')
    group=groups[status]
    for o in group:o.select_set(True)
    bpy.context.view_layer.objects.active=group[0]
    bpy.ops.object.join()
    o=bpy.context.object;o.name='SM_PAE_Status' if status else 'SM_PAE_WaferConverter'
    SCENE.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.export_scene.fbx(filepath=str(OUT/'models'/ (o.name+'.fbx')),use_selection=True,object_types={'MESH'},axis_forward='-Y',axis_up='Z',apply_unit_scale=True,apply_scale_options='FBX_SCALE_UNITS',bake_anim=False)
# CPU studio render of the exported geometry.
studio=collection('STUDIO')
M['floor']=material('Floor',(.055,.078,.091),.05,.56)
box('Ground',(0,0,-.14),(200,200,.25),'floor',0)
for loc,energy,size in (((1,-5,7),1500,5),((-5,-1,4),950,4),((2,5,6),1800,3)):
    d=bpy.data.lights.new('Softbox','AREA');d.energy=energy;d.size=size;o=bpy.data.objects.new('Softbox',d);studio.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,1.3))-o.location).to_track_quat('-Z','Y').to_euler()
d=bpy.data.cameras.new('Camera');cam=bpy.data.objects.new('Camera',d);studio.objects.link(cam);SCENE.camera=cam;d.type='ORTHO';d.ortho_scale=4.65
SCENE.render.resolution_x=1200;SCENE.render.resolution_y=1200;SCENE.cycles.samples=32
for label,loc in [('hero',(5,-8,4.5)),('rear',(-5,8,4.5))]:
    cam.location=loc;cam.rotation_euler=(Vector((0,0,1.35))-cam.location).to_track_quat('-Z','Y').to_euler();SCENE.render.filepath=str(OUT/'previews'/ (label+'.png'));bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Converter_presentation.blend'))
print('CONVERTER_MODEL_COMPLETE',flush=True)
