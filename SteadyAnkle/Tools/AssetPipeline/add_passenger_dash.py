"""Closes the opening left in the passenger side of the dashboard after its instrument pod was removed
(remove_passenger_pod.py): a soft-touch ink dash panel with a thin Pulse trim line, so the passenger side reads as
a clean, continuous dashboard. Usage: python3 add_passenger_dash.py <unzipped_usdz_dir> <out.usdz>
World units are USD cm (Y up, front of the car = -Z)."""
import sys
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf, UsdUtils
d, out = sys.argv[1], sys.argv[2]
st = Usd.Stage.Open(d + '/scene.usdc')
grp = st.GetPrimAtPath('/scene/Meshes/Sketchfab_model/Collada_visual_scene_group')
inv = UsdGeom.Xformable(grp).ComputeLocalToWorldTransform(0).GetInverse()


def material(name, color, rough, emit=None):
    m = UsdShade.Material.Define(st, f'/scene/MotialMaterials/{name}')
    s = UsdShade.Shader.Define(st, f'/scene/MotialMaterials/{name}/PBR')
    s.CreateIdAttr('UsdPreviewSurface')
    s.CreateInput('diffuseColor', Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*color))
    s.CreateInput('roughness', Sdf.ValueTypeNames.Float).Set(rough)
    s.CreateInput('metallic', Sdf.ValueTypeNames.Float).Set(0.0)
    if emit: s.CreateInput('emissiveColor', Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*emit))
    m.CreateSurfaceOutput().ConnectToSource(s.ConnectableAPI(), 'surface')
    return m


def prism(path, profile, x0, x1, mat):
    """profile: [(z, y), ...] closed polygon in the YZ plane, extruded along X."""
    n = len(profile)
    pts = [Gf.Vec3f(*inv.Transform(Gf.Vec3d(x, y, z))) for x in (x0, x1) for (z, y) in profile]
    counts, idx = [n, n], [list(range(n))[::-1], list(range(n, 2 * n))]
    idx = idx[0] + idx[1]
    for i in range(n):
        j = (i + 1) % n
        counts.append(4); idx += [i, j, n + j, n + i]
    m = UsdGeom.Mesh.Define(st, path)
    m.CreatePointsAttr(pts); m.CreateFaceVertexCountsAttr(counts); m.CreateFaceVertexIndicesAttr(idx)
    m.CreateSubdivisionSchemeAttr('none'); m.CreateDoubleSidedAttr(True)
    UsdShade.MaterialBindingAPI.Apply(m.GetPrim()).Bind(mat)


ink = material('DashInk', (0.055, 0.06, 0.07), 0.8)
pulse = material('DashPulse', (0.298, 0.949, 0.690), 0.4, emit=(0.15, 0.48, 0.35))
base = grp.GetPath()
prism(base.AppendChild('PassengerDashCover'),
      [(-150, 170), (-150, 207), (-64, 207), (-48, 201), (-43, 190), (-43, 170)], -134, -31, ink)
prism(base.AppendChild('PassengerDashTrim'),
      [(-64.4, 207.25), (-61.4, 206.1), (-61.6, 205.6), (-64.6, 206.75)], -128, -37, pulse)
st.GetRootLayer().Save()
UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(d + '/scene.usdc'), out)
print('written', out)
