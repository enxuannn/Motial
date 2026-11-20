import numpy as np, math, sys
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0,'build')
W,H=1920,1080; fov=64; f=0.5*W/math.tan(math.radians(fov)/2)
CAM=np.array([0.5,1.6,4.2]); pitch=math.radians(0.5)
def proj(p):
    d=np.array(p,float)-CAM
    # inverse of camera rotation Rx(pitch): world->cam
    c,s=math.cos(-pitch),math.sin(-pitch)
    y=d[1]*c-d[2]*s; z=d[1]*s+d[2]*c; x=d[0]
    return (W/2+f*x/(-z), H/2-f*y/(-z), -z)
base=Image.open('out/court_persp.png').convert('RGBA')
glow=Image.new('RGBA',(W,H),(0,0,0,0)); g=ImageDraw.Draw(glow)
# footwork targets (jump stop), relative to the person at the FT line (origin)
for i,(x,z,hop) in enumerate([(0,-0.5,False),(0,-1.0,False),(0,-1.6,True)]):
    pts=[proj((x+0.17*math.cos(a),0.01,z+0.17*math.sin(a))) for a in np.linspace(0,2*math.pi,60)]
    col=(255,210,170,255) if hop else (168,210,255,255)
    if i==2: col=(255,244,224,255)
    g.line([(p[0],p[1]) for p in pts],fill=col,width=6)
# ball arc from coach hands to rim
coach_pos=(-0.9,0,-2.3); hands=(coach_pos[0]+0.15,1.9,coach_pos[2]+0.1); rim=(0,3.05,-4.225)
arc=[]
for t in np.linspace(0,1,40):
    p=np.array(hands)+(np.array(rim)-np.array(hands))*t; p[1]+=1.3*4*t*(1-t); arc.append(proj(p))
for i,p in enumerate(arc):
    if i%2==0 and i<36: g.ellipse((p[0]-4,p[1]-4,p[0]+4,p[1]+4),fill=(255,244,224,230))
# Lumi glow near next target
lp=proj((0.25,0.4,-1.0)); g.ellipse((lp[0]-9,lp[1]-9,lp[0]+9,lp[1]+9),fill=(201,182,255,255))
blur=glow.filter(ImageFilter.GaussianBlur(10)); a=np.array(blur); a[...,3]=np.clip(a[...,3]*2,0,255)
out=Image.alpha_composite(base,Image.fromarray(a)); out=Image.alpha_composite(out,glow)
# ball near apex
bp=arc[35]; d=ImageDraw.Draw(out); r=max(6,int(0.12*f/bp[2]))
d.ellipse((bp[0]-r,bp[1]-r,bp[0]+r,bp[1]+r),fill=(236,116,52,255)); d.arc((bp[0]-r,bp[1]-r,bp[0]+r,bp[1]+r),200,340,fill=(60,30,20,255),width=2)
# coach: shadow + cutout scaled to 1.68 m
coach=Image.open('out/coach_land.png')
foot=proj(coach_pos); head=proj((coach_pos[0],1.62,coach_pos[2]))
hpx=foot[1]-head[1]; sc=hpx/coach.size[1]*1.02
cw,ch=int(coach.size[0]*sc),int(coach.size[1]*sc); cimg=coach.resize((cw,ch),Image.LANCZOS)
sh=Image.new('RGBA',(W,H),(0,0,0,0)); ImageDraw.Draw(sh).ellipse((foot[0]-cw*0.55,foot[1]-12,foot[0]+cw*0.55,foot[1]+12),fill=(20,20,40,120))
out=Image.alpha_composite(out,sh.filter(ImageFilter.GaussianBlur(8)))
out.alpha_composite(cimg,(int(foot[0]-cw/2),int(foot[1]-ch)))
out.convert('RGB').save('deck2/sportlab_court.jpg',quality=92); print('ok',hpx)
