"""Limits every skinned mesh in a USDZ to 4 joint influences per vertex (largest weights kept, renormalised).
RealityKit skins with at most 4 joints per vertex; extra influences were dropped at runtime, which pinched and
squeezed the coaches' bodies. Usage: python3 limit_skin_influences.py <in.usdz> <work_dir> <out.usdz>"""
import sys, os, zipfile
import numpy as np
from pxr import Usd, UsdGeom, UsdSkel, Sdf, UsdUtils
src, work, out = sys.argv[1:4]
os.makedirs(work, exist_ok=True)
with zipfile.ZipFile(src) as z:
    z.extractall(work)
    root = next(n for n in z.namelist() if n.endswith(('.usdc', '.usda', '.usd')) and '/' not in n)
st = Usd.Stage.Open(os.path.join(work, root))
for p in st.Traverse():
    if not p.IsA(UsdGeom.Mesh): continue
    b = UsdSkel.BindingAPI(p)
    ji, jw = b.GetJointIndicesPrimvar(), b.GetJointWeightsPrimvar()
    if not ji or ji.GetElementSize() <= 4: continue
    k = ji.GetElementSize()
    I = np.array(ji.Get(), dtype=np.int32).reshape(-1, k)
    W = np.array(jw.Get(), dtype=np.float32).reshape(-1, k)
    order = np.argsort(-W, axis=1)[:, :4]
    I4 = np.take_along_axis(I, order, 1); W4 = np.take_along_axis(W, order, 1)
    s = W4.sum(1, keepdims=True); s[s == 0] = 1; W4 = W4 / s
    ji.Set(I4.flatten().tolist()); ji.SetElementSize(4)
    jw.Set(W4.flatten().tolist()); jw.SetElementSize(4)
    print('limited', p.GetPath(), k, '->', 4, 'max dropped weight', round(float((W.sum(1) - np.take_along_axis(W, order, 1).sum(1)).max()), 3))
st.GetRootLayer().Save()
UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(os.path.join(work, root)), out)
print('written', out)
