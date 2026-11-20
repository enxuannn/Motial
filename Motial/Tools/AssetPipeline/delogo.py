import cv2, numpy as np, json, struct, io
from PIL import Image
b=open('/mnt/user-data/uploads/Downloads/steady_glove2.glb','rb').read()
l=struct.unpack('<I',b[12:16])[0]; j=json.loads(b[20:20+l]); binoff=20+l+8
def img(i):
    bv=j['bufferViews'][j['images'][i]['bufferView']]; o=binoff+bv.get('byteOffset',0)
    return np.array(Image.open(io.BytesIO(b[o:o+bv['byteLength']])).convert('RGB'))
tex=img(0); S=tex.shape[0]/1024
# regions (1024-space) : (x0,y0,x1,y1, mode) mode 'dark' = dark/blue marks on tan, 'light' = light marks on blue
R=[(120,40,320,215,'dark'),(330,10,430,95,'dark'),(430,15,610,110,'dark'),(790,15,1010,215,'dark'),
   (285,400,360,445,'dark'),(55,370,170,480,'dark'),(495,320,550,370,'dark'),(580,460,665,620,'light'),
   (780,390,860,570,'light'),(470,745,580,790,'light'),(770,755,860,815,'dark'),(890,640,950,700,'dark')]
mask=np.zeros(tex.shape[:2],np.uint8)
hsv=cv2.cvtColor(tex,cv2.COLOR_RGB2HSV).astype(int)
r,g,bl=[tex[...,k].astype(int) for k in range(3)]
for x0,y0,x1,y1,mode in R:
    X0,Y0,X1,Y1=[int(v*S) for v in (x0,y0,x1,y1)]
    sub=np.zeros_like(mask)
    if mode=='dark': m=((bl>r+5)|(hsv[...,2]<90)) & (hsv[...,2]>12)
    else: m=(hsv[...,2]>150)|((r>bl+25)&(hsv[...,2]>110))
    sub[Y0:Y1,X0:X1]=m[Y0:Y1,X0:X1]
    mask|=sub.astype(np.uint8)*255
mask=cv2.dilate(mask,np.ones((9,9),np.uint8))
out=cv2.inpaint(cv2.cvtColor(tex,cv2.COLOR_RGB2BGR),mask,9,cv2.INPAINT_TELEA)
out=cv2.cvtColor(out,cv2.COLOR_BGR2RGB)
Image.fromarray(out).resize((1024,1024),Image.LANCZOS).save('glove_base_clean.png')
Image.fromarray(mask).resize((1024,1024)).save('glove_mask.png')
img(1); Image.fromarray(img(1)).resize((1024,1024)).save('glove_orm.png')
Image.fromarray(img(2)).resize((1024,1024)).save('glove_normal.png')
print('ok')
# pass 2: local-deviation mask on residual text areas
src=out.copy()
R2=[(50,370,175,485),(455,15,600,60),(765,750,865,825),(480,750,575,785),(800,400,860,560)]
med=cv2.medianBlur(src,31)
dev=np.abs(src.astype(int)-med.astype(int)).sum(axis=2)
mask2=np.zeros(src.shape[:2],np.uint8)
for x0,y0,x1,y1 in R2:
    X0,Y0,X1,Y1=[int(v*S) for v in (x0,y0,x1,y1)]
    mask2[Y0:Y1,X0:X1]=(dev[Y0:Y1,X0:X1]>38).astype(np.uint8)*255
mask2=cv2.dilate(mask2,np.ones((11,11),np.uint8))
out2=cv2.inpaint(cv2.cvtColor(src,cv2.COLOR_RGB2BGR),mask2,11,cv2.INPAINT_TELEA)
out2=cv2.cvtColor(out2,cv2.COLOR_BGR2RGB)
Image.fromarray(out2).resize((1024,1024),Image.LANCZOS).save('glove_base_clean.png')
print('pass2')
