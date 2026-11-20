"""Removes the instrument pod in front of the passenger seat of RemerCar.usdz ("Cuy3", CC BY 4.0), so the car has one
driver's seat (right-hand drive). Usage: python3 remove_passenger_pod.py <unzipped_usdz_dir> <out.usdz>
Deletes every face (except dash base and glass) whose centroid lies in the left pod's box (USD cm: x -125..-25,
y 175..240, z -140..-50) and filters faceVarying/uniform primvars to match."""
import sys
from pxr import Usd, UsdGeom, Gf, Sdf, UsdShade, UsdUtils
d, out = sys.argv[1], sys.argv[2]
st = Usd.Stage.Open(d + '/scene.usdc')
for p in st.Traverse():
    if not p.IsA(UsdGeom.Mesh): continue
    mesh = UsdGeom.Mesh(p)
    mat = UsdShade.MaterialBindingAPI(p).ComputeBoundMaterial()[0]
    name = mat.GetPrim().GetName() if mat else ''
    if name.startswith('Interior_Sierra') or name.startswith('Translucent'): continue
    xf = UsdGeom.Xformable(p).ComputeLocalToWorldTransform(Usd.TimeCode.Default())
    pts = mesh.GetPointsAttr().Get(); counts = list(mesh.GetFaceVertexCountsAttr().Get()); idx = list(mesh.GetFaceVertexIndicesAttr().Get())
    keep, off = [], 0
    for c in counts:
        vs = [xf.Transform(Gf.Vec3d(pts[i])) for i in idx[off:off + c]]
        cx, cy, cz = (sum(v[k] for v in vs) / c for k in range(3))
        keep.append(not (-125 < cx < -25 and 175 < cy < 240 and -140 < cz < -50)); off += c
    if all(keep): continue
    newc, newi, fv, off = [], [], [], 0
    for k, c in enumerate(counts):
        if keep[k]: newc.append(c); newi += idx[off:off + c]
        fv += [keep[k]] * c; off += c
    for pv in UsdGeom.PrimvarsAPI(p).GetPrimvars():
        it = pv.GetInterpolation(); mask = fv if it == 'faceVarying' else (keep if it == 'uniform' else None)
        if mask is None: continue
        if pv.IsIndexed(): pv.SetIndices([v for v, m in zip(pv.GetIndices(), mask) if m])
        elif pv.Get() is not None and len(pv.Get()) == len(mask): pv.Set([v for v, m in zip(pv.Get(), mask) if m])
    na = mesh.GetNormalsAttr()
    if na.Get() is not None and mesh.GetNormalsInterpolation() == 'faceVarying':
        na.Set([v for v, m in zip(na.Get(), fv) if m])
    mesh.GetFaceVertexCountsAttr().Set(newc); mesh.GetFaceVertexIndicesAttr().Set(newi)
st.GetRootLayer().Save()
UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(d + '/scene.usdc'), out)
