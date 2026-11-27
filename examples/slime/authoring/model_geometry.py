"""Owned procedural slime models. Standard library only; CLI cooks PLY into GCSPLAT.
Run: python tools/generate_assets.py --cli /path/to/gc_cli.exe
All models Y-up, front +Z, grounded at y=0. Body connectivity identical across forms.
"""
import argparse, bisect, hashlib, json, math, random, struct, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TAU = math.tau
SLICES, RINGS = 32, 20
FORMS = ['slime', 'mushroom', 'stone', 'apple', 'crate']
# Half spacing, center height, circular radius, palette-coordinated eye color.
EYES = {
    'slime': (.45,1.03,.108,'4B9848'),
    'mushroom': (.22,.60,.095,'886744'),
    'stone': (.39,.75,.108,'4C6378'),
    'apple': (.37,.85,.108,'993E38'),
    'crate': (.37,1.00,.108,'80532F'),
}

def add(a,b): return tuple(x+y for x,y in zip(a,b))
def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def mul(a,s): return tuple(x*s for x in a)
def dot(a,b): return sum(x*y for x,y in zip(a,b))
def cross(a,b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def norm(a): return mul(a,1/max(math.sqrt(dot(a,a)),1e-12))
def rgb(h): return tuple(int(h[i:i+2],16)/255 for i in (0,2,4))
def linear(c): return tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in c)
def signedpow(x,e): return math.copysign(abs(x)**e,x)

def surface(fn, slices=SLICES, rings=RINGS):
    vertices = [fn(0,0)]
    for r in range(1,rings):
        for s in range(slices): vertices.append(fn(math.pi*r/rings,TAU*s/slices))
    vertices.append(fn(math.pi,0))
    faces=[]
    for s in range(slices):
        ns=(s+1)%slices
        faces.append((0,1+ns,1+s))
        for r in range(rings-2):
            a,b=1+r*slices+s,1+r*slices+ns
            faces.extend([(a,b,a+slices),(b,b+slices,a+slices)])
        faces.append((len(vertices)-1,1+(rings-2)*slices+s,1+(rings-2)*slices+ns))
    return vertices,faces

def body_point(form,p,t):
    s,c=math.sin(p), math.cos(p)
    x,z=s*math.cos(t),s*math.sin(t)
    if form=='slime':
        # Reference: tall dome, short rounded sides, soft-flat base; no flared skirt.
        profile=[(1.88,0),(1.865,.20),(1.82,.40),(1.73,.58),(1.61,.74),
                 (1.46,.87),(1.29,.96),(1.11,1.01),(.93,1.03),(.75,1.03),
                 (.57,1.015),(.41,.98),(.28,.92),(.18,.84),(.10,.73),
                 (.055,.59),(.025,.43),(.025,.32),(.025,.22),(.025,.11),(.025,0)]
        u=min(p/math.pi*20,20); i=min(int(u),19); f=u-i
        y=profile[i][0]*(1-f)+profile[i+1][0]*f
        radius=profile[i][1]*(1-f)+profile[i+1][1]*f
        return (radius*math.cos(t)+.02*(y/1.88),y,radius*math.sin(t)*.84)
    if form=='mushroom':
        # Continuous cap -> undercut -> thick stalk. All a single closed surface.
        profile=[(0,2.0,0),(.10,1.98,.32),(.20,1.91,.63),(.30,1.77,.88),(.40,1.59,1.05),(.50,1.44,1.12),(.55,1.36,1.03),(.60,1.32,.66),(.65,1.28,.38),(.70,1.04,.35),(.75,.80,.38),(.80,.58,.44),(.85,.35,.50),(.90,.16,.48),(.95,.05,.30),(1,0,0)]
        u=p/math.pi
        for i in range(len(profile)-1):
            a,b=profile[i:i+2]
            if a[0]<=u<=b[0]:
                f=(u-a[0])/(b[0]-a[0]); y=a[1]*(1-f)+b[1]*f; radius=a[2]*(1-f)+b[2]*f; break
        if u>.6: radius*=1.24
        return (radius*math.cos(t),y*.82,radius*math.sin(t)*.88)
    if form=='stone':
        # Ray intersection with broad asymmetric rock planes, rather than a ball.
        direction=(x,c,z)
        planes=[((0,1,0),.80),((0,-1,0),.82)]
        for i in range(7):
            a=TAU*i/7+.13
            planes.extend([((math.cos(a),.10*math.sin(3*a),math.sin(a)),.86+.07*math.cos(2*a)),
                           ((.72*math.cos(a),.72,.72*math.sin(a)),.87+.06*math.cos(3*a)),
                           ((.78*math.cos(a),-.65,.78*math.sin(a)),.92)])
        radius=min(d/dot(n,direction) for n,d in planes if dot(n,direction)>1e-6)
        return (x*radius*1.12+.08*c,.64+c*radius*.75,z*radius*.90)
    if form=='apple':
        lobes=1+.055*math.cos(5*t)*s
        return (x*.90*lobes*(1+.12*c), max(.025,.86+.82*c-.19*abs(c)**12),z*.83*lobes*(1+.10*c))
    m=max(abs(x),abs(c),abs(z)); k=.92/m+.08
    return (.85*x*k, .85+.85*c*k, .77*z*k)

def base_color(form,p,n):
    x,y,z=p
    if form=='slime':
        return rgb('99D63E')
    if form=='stone':
        moss=y>1.12+.08*math.sin(8*x+3*z) and x<.33+.07*math.sin(9*z) and z<.34
        return rgb('8291AB') if not moss else rgb('82A847')
    if form=='apple':
        if ((x+.32)/.16)**2+((y-1.20)/.19)**2+((z-.57)/.20)**2<1: return rgb('F39A73')
        return rgb('D95C50')
    if form=='mushroom':
        if y<1.34*.82: return rgb('EDD3A0')
        spots=[(-.49,1.78,.48,.26),(.40,1.85,.24,.24),(.86,1.56,.39,.18),(-.2,1.92,-.42,.23),(-.92,1.54,-.25,.19)]
        if any(sum((v-w)**2 for v,w in zip((x,y/.82,z),q[:3]))<q[3]**2 for q in spots): return rgb('FFE6AF')
        return rgb('D75D48') if n[1]>-.3 else rgb('984A45')
    return rgb('B98045') if abs(n[1])>.75 else rgb('AF763C')

LIGHT=norm((-.6,1,1.4))
def shade(color,n,p):
    light=dot(n,LIGHT)
    factor=1.08 if light>.72 else .92 if light>.30 else .70 if light>-.12 else .49
    # Colored cool shadow and mild lower contact darkening.
    return tuple(max(0,min(1,c*factor*(.93 if p[1]<.18 else 1)+(1-max(0,light))*.022*(i==2))) for i,c in enumerate(color))

def ellipsoid(center, scale, color, slices=16,rings=10):
    v,f=surface(lambda p,t:add(center,(math.sin(p)*math.cos(t)*scale[0], math.cos(p)*scale[1], math.sin(p)*math.sin(t)*scale[2])),slices,rings)
    return v,f,lambda p,n:rgb(color)

def make_model(form, face=True):
    v,f=surface(lambda p,t:body_point(form,p,t))
    pieces=[(v,f,lambda p,n:base_color(form,p,n))]
    if form=='crate':
        # Actual shallow wooden rails with clean rectangular boundaries.
        def rail(a,b,width,depth,color,side):
            dx,dy=b[0]-a[0],b[1]-a[1]; length=math.hypot(dx,dy)
            nx,ny=-dy/length*width/2,dx/length*width/2
            vv=[]
            for zz in (-depth/2,depth/2):
                for xx,yy in [(a[0]+nx,a[1]+ny),(a[0]-nx,a[1]-ny),(b[0]-nx,b[1]-ny),(b[0]+nx,b[1]+ny)]:
                    z=.739+zz; x=xx
                    if side==1: x,z=z*1.10,-x*.90
                    if side==2: x,z=-x,-z
                    if side==3: x,z=-z*1.10,x*.90
                    vv.append((x,yy,z))
            ff=[(0,2,1),(0,3,2),(4,5,6),(4,6,7),(0,1,5),(0,5,4),(1,2,6),(1,6,5),(2,3,7),(2,7,6),(3,0,4),(3,4,7)]
            pieces.append((vv,ff,lambda p,n:rgb(color)))
        for side in range(4):
            for a,b in [((-.73,.13),(.73,.13)),((-.73,1.56),(.73,1.56)),((-.70,.205),(-.70,1.485)),((.70,.205),(.70,1.485))]: rail(a,b,.15,.065,'E5AE63',side)
            rail((-.62,.22),(.62,1.47),.13,.075,'DC9D52',side)
    if form=='apple':
        sv,sf=surface(lambda p,t:(.04+.055*math.cos(p)+.06*math.sin(p)*math.cos(t),1.65+.22*math.cos(p),.06*math.sin(p)*math.sin(t)),12,8)
        pieces.append((sv,sf,lambda p,n:rgb('775132')))
        lv,lf=surface(lambda p,t:(.32+.30*math.cos(p),1.78+.10*math.cos(p)+.055*math.sin(p)**2+.022*math.sin(p)*math.cos(t),.15*math.sin(p)*math.sin(t)),16,8)
        pieces.append((lv,lf,lambda p,n:rgb('A1C956') if abs(p[2])<.023 else rgb('75A53D') if p[2]>0 else rgb('507D31')))
    if face:
        spacing,cy,radius,eye_color=EYES[form]
        # Front silhouette at face height; curved surface placement keeps features grounded.
        def front(x,y):
            best=0
            for a,b,c in f:
                A,B,C=v[a],v[b],v[c]
                den=(B[1]-C[1])*(A[0]-C[0])+(C[0]-B[0])*(A[1]-C[1])
                if abs(den)<1e-9: continue
                u=((B[1]-C[1])*(x-C[0])+(C[0]-B[0])*(y-C[1]))/den
                w=((C[1]-A[1])*(x-C[0])+(A[0]-C[0])*(y-C[1]))/den
                if min(u,w,1-u-w)>=-1e-5: best=max(best,u*A[2]+w*B[2]+(1-u-w)*C[2])
            return best+.025
        for x in (-spacing,spacing):
            ev,ef,ec=ellipsoid((x,cy,0),(radius,radius,.025),eye_color)
            ev=[(xx,yy,front(xx,yy)+zz+.035) for xx,yy,zz in ev]
            pieces.append((ev,ef,ec))
    return pieces

def triangles(pieces,form=None):
    out=[]
    for piece_id,(vertices,faces,color_fn) in enumerate(pieces):
        for ids in faces:
            a,b,c=[vertices[i] for i in ids]; area2=cross(sub(b,a),sub(c,a)); area=math.sqrt(dot(area2,area2))*.5
            if area<1e-10: continue
            n=norm(area2); mid=mul(add(add(a,b),c),1/3)
            albedo=color_fn(mid,n)
            density=6.0 if albedo in tuple(rgb(spec[3]) for spec in EYES.values()) else 1.0
            color=shade(albedo,n,mid)
            if form=='slime' and piece_id==0:
                diffuse=dot(n,LIGHT)
                factor=1.03 if diffuse>.65 else .97 if diffuse>.15 else .89
                color=tuple(min(1,c*factor) for c in albedo)
            out.append((a,b,c,n,color,area,density))
    return out

def write_obj(path, vertices, faces, form):
    with path.open('w') as out:
        out.write('# Shared 610-vertex body template. Y up, front +Z, grounded.\n')
        for v in vertices: out.write('v '+' '.join(f'{a:.7f}' for a in (*v,*base_color(form,v,norm(sub(v,(0,.8,0))))))+'\n')
        for a,b,c in faces: out.write(f'f {a+1} {b+1} {c+1}\n')

def write_glb(path,tris):
    data=bytearray(); views=[]; acc=[]
    def accessor(values,kind,dimension):
        start=len(data); flat=[v for row in values for v in row]; data.extend(struct.pack('<'+'f'*len(flat),*flat))
        views.append({'buffer':0,'byteOffset':start,'byteLength':len(data)-start})
        acc.append({'bufferView':len(views)-1,'componentType':5126,'count':len(values),'type':kind,'min':[min(row[k] for row in values) for k in range(dimension)],'max':[max(row[k] for row in values) for k in range(dimension)]})
        return len(acc)-1
    pos=accessor([v for t in tris for v in t[:3]],'VEC3',3)
    normal=accessor([t[3] for t in tris for _ in range(3)],'VEC3',3)
    col=accessor([(*linear(t[4]),1) for t in tris for _ in range(3)],'VEC4',4)
    doc={'asset':{'version':'2.0','generator':'Slime asset pack procedural generator'},'extensionsUsed':['KHR_materials_unlit'],'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':path.stem,'mesh':0}],'meshes':[{'primitives':[{'attributes':{'POSITION':pos,'NORMAL':normal,'COLOR_0':col},'material':0}]}],'materials':[{'name':'Baked toon palette','extensions':{'KHR_materials_unlit':{}},'doubleSided':True,'pbrMetallicRoughness':{'metallicFactor':0,'roughnessFactor':1}}],'buffers':[{'byteLength':len(data)}],'bufferViews':views,'accessors':acc}
    js=json.dumps(doc,separators=(',',':')).encode(); js+=b' '*((-len(js))%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(js)+len(data))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(data),0x004e4942)+data)

def quaternion(n):
    # Shortest arc from +Z to surface normal, returned WXYZ for 3DGS PLY.
    if n[2]<-.999999: return (0,1,0,0)
    return norm((1+n[2],-n[1],n[0],0))

def write_ply(path,tris,count,seed):
    rng=random.Random(seed); cdf=[]; total=0
    # Allocate extra, smaller Gaussians to dark eyes. Global radius otherwise
    # dilates facial details and makes them look larger than their mesh counterparts.
    weights=[t[6] for t in tris]
    for t,weight in zip(tris,weights): total+=t[5]*weight; cdf.append(total)
    header='ply\nformat binary_little_endian 1.0\ncomment Owned procedural surface Gaussian asset; +Y up\nelement vertex '+str(count)+'\n'
    fields=['x','y','z','f_dc_0','f_dc_1','f_dc_2','opacity','scale_0','scale_1','scale_2','rot_0','rot_1','rot_2','rot_3']
    header+=''.join('property float '+name+'\n' for name in fields)+'end_header\n'
    points=[]
    with path.open('wb') as out:
        out.write(header.encode())
        for i in range(count):
            ti=bisect.bisect_left(cdf,rng.random()*total); t=tris[ti]
            sigma=math.sqrt(total/count/weights[ti])*.95
            u=math.sqrt(rng.random()); w=rng.random(); p=add(add(mul(t[0],1-u),mul(t[1],u*(1-w))),mul(t[2],u*w))
            points.append(p)
            color=t[4]
            dc=tuple((c-.5)/.28209479177387814 for c in color)
            out.write(struct.pack('<14f',*p,*dc,math.log(.94/.06),math.log(sigma*1.05),math.log(sigma*.85),math.log(sigma*.12),*quaternion(t[3])))
    lo=[min(p[k] for p in points) for k in range(3)]; hi=[max(p[k] for p in points) for k in range(3)]
    return [(a+b)*.5 for a,b in zip(lo,hi)],max(b-a for a,b in zip(lo,hi))*.5

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--cli',type=Path,required=True); parser.add_argument('--count',type=int,default=48000); args=parser.parse_args()
    cli=args.cli.resolve()
    for d in ('assets/topology','assets/splats','authoring/bodies','authoring/gaussians','authoring/projects','captures'): (ROOT/d).mkdir(parents=True,exist_ok=True)
    records=[]
    for form in FORMS:
        v,f=surface(lambda p,t:body_point(form,p,t)); write_obj(ROOT/f'authoring/bodies/{form}.obj',v,f,form)
        for is_character in ([True] if form=='slime' else [True,False]):
            # Both roles now carry the same round, mouthless expression.
            name=form if is_character else form+'_item'; tris=triangles(make_model(form,True),form)
            write_glb(ROOT/f'assets/topology/{name}.glb',tris)
            ply=ROOT/f'authoring/gaussians/{name}.ply'; center,extent=write_ply(ply,tris,args.count,FORMS.index(form)*100+1)
            project=ROOT/f'authoring/projects/{name}.gcproject'; output=ROOT/f'assets/splats/{name}.gcsplat'
            subprocess.run([str(cli),'new','--mode','splats','--a',str(ply),'--b',str(ply),'--output',str(project),'--duration','0.125','--style','classic','--rigid','0','--count',str(args.count),'--samples','600','--mixtures','4','--up','0','--crop','100'],check=True)
            settings=json.loads(project.read_text()); settings['export']['fps']=8
            project.write_text(json.dumps(settings,indent=2))
            subprocess.run([str(cli),'export',str(project),'--output',str(output),'--fps','8'],check=True)
            # Capture loader normalizes input. Record inverse mapping, used identically at preview.
            data=output.read_bytes()
            records.append({'name':name,'has_eyes':True,'role':'character' if is_character else 'touch_target','triangles':len(tris),'splats':args.count,'body_vertices':len(v),'body_triangles':len(f),'splat_restore_center':center,'splat_restore_scale':extent,'glb_bytes':(ROOT/f'assets/topology/{name}.glb').stat().st_size,'splat_bytes':len(data)})
    (ROOT/'assets/manifest.json').write_text(json.dumps({'forms':records,'body_faces_sha256':hashlib.sha256(json.dumps(f).encode()).hexdigest(),'note':'Static model assets. GCSPLAT contains a two-frame hold; inter-form morph clips are not baked yet.'},indent=2))

if __name__=='__main__': main()
