"""Build owned static models, exact shared-topology GLBs, and Gaussian Cake clips.

python examples/slime/tools/build_assets.py --cli ../Gaussian-Cake/build/Release/gc_cli.exe
No external Python packages. Godot playback requires only the generated assets.
"""
import argparse
import importlib.util
import json
import math
import itertools
from pathlib import Path
import struct
import subprocess
import zlib

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'res://examples/slime/'
spec = importlib.util.spec_from_file_location('model_geometry', ROOT/'authoring/model_geometry.py')
geo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(geo)
DURATION = .75
FPS = 16
COUNT = 48000


def chunk(kind, data):
    return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)


def write_colors(path, colors):
    width = 1024
    height = math.ceil(len(colors)/width)
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            i=y*width+x
            color=colors[i] if i<len(colors) else (0,0,0)
            rows.extend(round(max(0,min(1,c))*255) for c in color)
    header=struct.pack('>IIBBBBB',width,height,8,2,0,0,0)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',header)+chunk(b'IDAT',zlib.compress(rows,9))+chunk(b'IEND',b''))
    return width,height


def ordered_triangles(form):
    pieces=geo.make_model(form,True)
    if form=='slime':
        return geo.triangles(pieces,form)
    # Shared core and the same two eye meshes come first. Decorations get their
    # own fixed correspondence, collapsing harmlessly inside slime at weight 0.
    body=geo.triangles([pieces[0]],form)
    eyes=geo.triangles(pieces[-2:])
    details=geo.triangles(pieces[1:-2])
    return body+eyes+details


def write_morph(target):
    start=ordered_triangles('slime')
    end=ordered_triangles(target)
    assert len(end)>=len(start)
    # Tiny triangles preserve target vertices through importer mesh optimization;
    # they sit inside the opaque source body and grow into stem/leaf/crate rails.
    for i,t in enumerate(end[len(start):]):
        anchor=(0,.75,0)
        center=geo.mul(geo.add(geo.add(t[0],t[1]),t[2]),1/3)
        verts=[geo.add(anchor,geo.mul(geo.sub(v,center),.0001)) for v in t[:3]]
        start.append((*verts,t[3],geo.rgb('99D63E'),t[5],1.0))
    assert len(start)==len(end)
    colors=[t[4] for t in end for _ in range(3)]
    width,height=write_colors(ROOT/f'assets/colors/{target}.png',colors)
    data=bytearray(); views=[]; accessors=[]

    def accessor(values,kind,dimension):
        values=list(values); offset=len(data)
        flat=[v for row in values for v in row]
        data.extend(struct.pack('<'+'f'*len(flat),*flat))
        views.append({'buffer':0,'byteOffset':offset,'byteLength':len(data)-offset})
        accessors.append({'bufferView':len(views)-1,'componentType':5126,'count':len(values),'type':kind,
                          'min':[min(row[k] for row in values) for k in range(dimension)],
                          'max':[max(row[k] for row in values) for k in range(dimension)]})
        return len(accessors)-1

    positions=[v for t in start for v in t[:3]]
    target_positions=[v for t in end for v in t[:3]]
    normals=[t[3] for t in start for _ in range(3)]
    target_normals=[t[3] for t in end for _ in range(3)]
    attrs={
        'POSITION':accessor(positions,'VEC3',3),
        'NORMAL':accessor(normals,'VEC3',3),
        'COLOR_0':accessor([(*geo.linear(t[4]),1) for t in start for _ in range(3)],'VEC4',4),
        'TEXCOORD_0':accessor([((i%width+.5)/width,(i//width+.5)/height) for i in range(len(positions))],'VEC2',2),
    }
    morph={
        'POSITION':accessor([geo.sub(b,a) for a,b in zip(positions,target_positions)],'VEC3',3),
        'NORMAL':accessor([geo.sub(b,a) for a,b in zip(normals,target_normals)],'VEC3',3),
    }
    times=accessor([(0,),(DURATION,)],'SCALAR',1)
    weights=accessor([(0,),(1,)],'SCALAR',1)
    doc={'asset':{'version':'2.0','generator':'Gaussian Cake sample exact-correspondence authoring'},
         'scene':0,'scenes':[{'nodes':[0]}], 'nodes':[{'name':'SlimeMorph','mesh':0}],
         'meshes':[{'name':'SlimeMorph','weights':[0], 'extras':{'targetNames':[target]},
                    'primitives':[{'attributes':attrs,'targets':[morph],'material':0}]}],
         'materials':[{'name':'Sample baked color','doubleSided':True,
                       'extensions':{'KHR_materials_unlit':{}},
                       'pbrMetallicRoughness':{'metallicFactor':0,'roughnessFactor':1}}],
         'extensionsUsed':['KHR_materials_unlit'],
         'animations':[{'name':'Morph','samplers':[{'input':times,'output':weights,'interpolation':'LINEAR'}],
                        'channels':[{'sampler':0,'target':{'node':0,'path':'weights'}}]}],
         'buffers':[{'byteLength':len(data)}], 'bufferViews':views, 'accessors':accessors,
         'extras':{'sample_profile':'shared-body-eyes-with-growing-details','duration':DURATION,
                   'target_color_texture':f'../colors/{target}.png', 'color_texture_space':'sRGB'}}
    js=json.dumps(doc,separators=(',',':')).encode();js+=b' '*((-len(js))%4)
    path=ROOT/f'assets/morphs/slime_to_{target}.glb'
    path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(js)+len(data))+
                    struct.pack('<II',len(js),0x4e4f534a)+js+
                    struct.pack('<II',len(data),0x004e4942)+data)
    return len(positions)


def cook(cli, start, target, output, duration, fps):
    project=ROOT/f'authoring/projects/{output.stem}.gcproject'
    subprocess.run([str(cli),'new','--mode','splats','--a',str(ROOT/f'authoring/sources/{start}.ply'),
                    '--b',str(ROOT/f'authoring/sources/{target}.ply'),'--output',str(project),
                    '--duration',str(duration),'--style','classic','--rigid','0','--count',str(COUNT),
                    '--samples','1200','--mixtures','8','--color-match','.35','--up','0','--crop','100'],check=True)
    doc=json.loads(project.read_text())
    doc['export']['fps']=fps
    doc['splats']['area_preserve']=False
    style=doc['segments'][0]['style']
    style.update({'cohesion':0,'mid_grow':0,'wave':0,'jiggle':0,'sag':0,
                  'early':[0,0,1,1],'late':[0,0,1,1]})
    project.write_text(json.dumps(doc,indent=2))
    subprocess.run([str(cli),'export',str(project),'--output',str(output),'--fps',str(fps)],check=True)


def validate_manifest(manifest):
    def glb(path):
        data=path.read_bytes(); size=struct.unpack_from('<I',data,12)[0]
        return json.loads(data[20:20+size]),data[28+size:]

    def values(doc,data,accessor):
        a=doc['accessors'][accessor]; v=doc['bufferViews'][a['bufferView']]
        dimensions={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        assert a['componentType']==5126
        offset=v.get('byteOffset',0)+a.get('byteOffset',0)
        flat=struct.unpack_from('<'+str(a['count']*dimensions)+'f',data,offset)
        assert all(math.isfinite(x) for x in flat)
        return [flat[i:i+dimensions] for i in range(0,len(flat),dimensions)]

    def records(data,frame):
        count,frames=struct.unpack_from('<II',data,16)
        return list(struct.iter_unpack('<14f',data[64+4*frames+frame*count*56:64+4*frames+(frame+1)*count*56]))

    for target, entry in manifest['transitions'].items():
        doc,buffer=glb(ROOT/entry['glb'].removeprefix(PREFIX))
        primitive=doc['meshes'][0]['primitives'][0]
        start=values(doc,buffer,primitive['attributes']['POSITION'])
        delta=values(doc,buffer,primitive['targets'][0]['POSITION'])
        expected=[v for t in ordered_triangles(target) for v in t[:3]]
        assert len(start)==len(delta)==len(expected)==entry['vertices']
        error=max(abs(a[k]+d[k]-e[k]) for a,d,e in zip(start,delta,expected) for k in range(3))
        assert error<1e-6,(target,'GLB endpoint error',error)
        values(doc,buffer,primitive['attributes']['NORMAL'])
        values(doc,buffer,primitive['targets'][0]['NORMAL'])
        assert doc['animations'][0]['channels'][0]['target']['path']=='weights'
        assert values(doc,buffer,doc['animations'][0]['samplers'][0]['input'])==[(0.0,),(.75,)]
        data=(ROOT/entry['splat'].removeprefix(PREFIX)).read_bytes()
        count,frames=struct.unpack_from('<II',data,16)
        assert count==COUNT and frames==13,(target,count,frames)
        assert len(data)==64+4*frames+count*frames*56
        # All clips share the same complete source point set; ID ordering need
        # only remain stable within a clip, since handoffs occur at the source.
        rest=(ROOT/'assets/rest/slime.gcsplat').read_bytes()
        first,source=records(data,0),records(rest,0)
        assert max(abs(a-b) for p,q in zip(first,source) for a,b in zip(p,q))<1e-6
        rest_target=(ROOT/f'assets/rest/{target}.gcsplat').read_bytes()
        end,expected_end=records(data,12),records(rest_target,0)
        # B's point IDs may be permuted by optimal transport. Compare its surface
        # point set, color, alpha and scale after restoring the same sorted order.
        bins={}
        cell=lambda p:tuple(math.floor(v*10000) for v in p[:3])
        for q in expected_end: bins.setdefault(cell(q),[]).append(q)
        endpoint_error=0.0
        neighbors=list(itertools.product((-1,0,1),repeat=3))
        for p in end:
            key=cell(p); matches=[]
            for shift in neighbors:
                bucket=tuple(a+b for a,b in zip(key,shift))
                for i,q in enumerate(bins.get(bucket,())):
                    distance=sum((p[k]-q[k])**2 for k in range(3))
                    if distance<1e-10: matches.append((distance,bucket,i,q))
            assert matches,(target,'target Gaussian missing',p[:3])
            _,bucket,i,q=min(matches,key=lambda m:m[0])
            bins[bucket].pop(i)
            endpoint_error=max(endpoint_error,max(abs(p[k]-q[k]) for k in (0,1,2,7,8,9,10,11,12,13)))
        assert endpoint_error<1e-5,(target,'splat endpoint error',endpoint_error)
        for p in first+end:
            assert all(math.isfinite(v) for v in p)
            assert abs(sum(v*v for v in p[3:7])-1)<1e-5
        print(f'{target}: GLB endpoint error {error:.2g}; splat endpoint error {endpoint_error:.2g}; {count} x {frames}')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--cli',type=Path)
    parser.add_argument('--validate-only',action='store_true')
    args=parser.parse_args()
    if args.validate_only:
        validate_manifest(json.loads((ROOT/'assets/manifest.json').read_text()))
        print('PASS: exact decorated GLB endpoints and all splat endpoint sets')
        return
    if args.cli is None: parser.error('--cli is required for baking')
    cli=args.cli.resolve()
    for d in ('assets/models','assets/rest','assets/morphs','assets/colors','authoring/sources','authoring/projects'):
        (ROOT/d).mkdir(parents=True,exist_ok=True)
    manifest={'version':1,'duration':DURATION,'splats_per_model':COUNT,'forms':{},'transitions':{}}
    for i,form in enumerate(geo.FORMS):
        tris=geo.triangles(geo.make_model(form,True),form)
        geo.write_glb(ROOT/f'assets/models/{form}.glb',tris)
        center,scale=geo.write_ply(ROOT/f'authoring/sources/{form}.ply',tris,COUNT,i*100+1)
        cook(cli,form,form,ROOT/f'assets/rest/{form}.gcsplat',.125,8)
        manifest['forms'][form]={'static_scene':PREFIX+f'assets/models/{form}.glb',
                                'static_splat':PREFIX+f'assets/rest/{form}.gcsplat',
                                'center':center,'scale':scale,'triangles':len(tris)}
    for target in geo.FORMS[1:]:
        vertices=write_morph(target)
        cook(cli,'slime',target,ROOT/f'assets/morphs/slime_to_{target}.gcsplat',DURATION,FPS)
        manifest['transitions'][target]={'glb':PREFIX+f'assets/morphs/slime_to_{target}.glb',
                                         'splat':PREFIX+f'assets/morphs/slime_to_{target}.gcsplat',
                                         'color_texture':PREFIX+f'assets/colors/{target}.png',
                                         'duration':DURATION,'vertices':vertices}
    (ROOT/'assets/manifest.json').write_text(json.dumps(manifest,indent=2))
    validate_manifest(manifest)
    print('PASS: 5 model pairs, 4 reversible native GLB animations, 4 48k Gaussian clips; shared source frames verified')

if __name__=='__main__': main()
