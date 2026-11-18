"""
Генератор моделей для Anime Team Survival.
Запуск (Windows):  blender.exe --background --python make_models.py -- <папка_вывода>
Запуск (bpy):      python make_models.py <папка_вывода>

Все модели — стилизованный лоу-поли в духе Warcraft 3. Персонажи — временные, собственного дизайна.
"""
import bpy, bmesh, math, random, sys, os
from mathutils import Matrix, Vector, Euler, Quaternion

OUT = None
argv = sys.argv
if "--" in argv:
    rest = argv[argv.index("--") + 1:]
    OUT = rest[0] if rest else None
elif len(argv) > 1 and not argv[1].endswith(".py"):
    OUT = argv[1]
if OUT is None:
    OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "game", "models")
OUT = os.path.abspath(OUT)
os.makedirs(OUT, exist_ok=True)

FPS = 24
UP = Vector((0, 0, 1))
_mats = {}


def reset_scene():
    _mats.clear()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS


# ---------------------------------------------------------------- materials
def mat(name, color, rough=0.75, metal=0.0, emit=None, emit_strength=0.0):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    c = (color[0], color[1], color[2], 1.0)
    p.inputs["Base Color"].default_value = c
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emit is not None:
        p.inputs["Emission Color"].default_value = (emit[0], emit[1], emit[2], 1.0)
        p.inputs["Emission Strength"].default_value = emit_strength
    m.diffuse_color = c
    _mats[name] = m
    return m


def hexc(h):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple((c / 12.92) if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb)


# ---------------------------------------------------------------- mesh builder
def mtx(loc=(0, 0, 0), rot=None, scale=(1, 1, 1)):
    q = rot if isinstance(rot, Quaternion) else (Euler([math.radians(a) for a in (rot or (0, 0, 0))]).to_quaternion())
    return Matrix.LocRotScale(Vector(loc), q, Vector(scale))


class Builder:
    """Одна сетка, много материалов, опционально — веса на кости."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.deform = self.bm.verts.layers.deform.verify()
        self.materials = []
        self.groups = []

    def _mat_index(self, m):
        if m not in self.materials:
            self.materials.append(m)
        return self.materials.index(m)

    def _group_index(self, g):
        if g not in self.groups:
            self.groups.append(g)
        return self.groups.index(g)

    def _finish(self, verts, m, bone, smooth=False):
        mi = self._mat_index(m)
        faces = set()
        for v in verts:
            faces.update(v.link_faces)
            if bone:
                v[self.deform][self._group_index(bone)] = 1.0
        for f in faces:
            f.material_index = mi
            f.smooth = smooth
        return verts

    def box(self, m, loc, size, rot=None, bone=None):
        r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=mtx(loc, rot, size))
        return self._finish(r["verts"], m, bone)

    def sphere(self, m, loc, radius, scale=(1, 1, 1), seg=(10, 7), rot=None, bone=None, smooth=False):
        r = bmesh.ops.create_uvsphere(self.bm, u_segments=seg[0], v_segments=seg[1], radius=1.0,
                                      matrix=mtx(loc, rot, (radius * scale[0], radius * scale[1], radius * scale[2])))
        return self._finish(r["verts"], m, bone, smooth)

    def ico(self, m, loc, radius, scale=(1, 1, 1), sub=1, rot=None, bone=None, jitter=0.0, seed=0):
        r = bmesh.ops.create_icosphere(self.bm, subdivisions=sub, radius=1.0,
                                       matrix=mtx(loc, rot, (radius * scale[0], radius * scale[1], radius * scale[2])))
        if jitter > 0:
            rnd = random.Random(seed)
            c = Vector(loc)
            for v in r["verts"]:
                v.co = c + (v.co - c) * (1.0 + rnd.uniform(-jitter, jitter))
        return self._finish(r["verts"], m, bone)

    def cyl(self, m, loc, r1, r2, depth, seg=8, rot=None, scale=(1, 1, 1), bone=None, smooth=False):
        r = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg,
                                  radius1=r1, radius2=r2, depth=depth, matrix=mtx(loc, rot, scale))
        return self._finish(r["verts"], m, bone, smooth)

    def limb(self, m, p0, p1, r0, r1, seg=8, bone=None, smooth=False):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        q = UP.rotation_difference(d.normalized())
        r = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg,
                                  radius1=r0, radius2=max(r1, 0.0001), depth=d.length,
                                  matrix=Matrix.LocRotScale((p0 + p1) / 2, q, Vector((1, 1, 1))))
        return self._finish(r["verts"], m, bone, smooth)

    def to_object(self, parent=None):
        me = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.materials:
            me.materials.append(m)
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        for g in self.groups:
            ob.vertex_groups.new(name=g)
        if parent is not None:
            ob.parent = parent
            mod = ob.modifiers.new("Armature", "ARMATURE")
            mod.object = parent
        return ob


# ---------------------------------------------------------------- skeleton
def make_skeleton(name, J):
    arm = bpy.data.armatures.new(name + "_Rig")
    ob = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.edit_bones

    def add(n, head, tail, parent=None):
        b = eb.new(n)
        b.head = Vector(head)
        b.tail = Vector(tail)
        b.roll = 0.0
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
        return b

    add("hips", J["hip"], J["hip"] + Vector((0, 0, 0.14)))
    add("spine", J["hip"] + Vector((0, 0, 0.14)), J["neck"], "hips")
    add("head", J["neck"], J["neck"] + Vector((0, 0, J["head_r"] * 2)), "spine")
    for s, sx in (("L", 1), ("R", -1)):
        sh = Vector((sx * J["shoulder"].x, J["shoulder"].y, J["shoulder"].z))
        el = Vector((sx * J["elbow"].x, J["elbow"].y, J["elbow"].z))
        ha = Vector((sx * J["hand"].x, J["hand"].y, J["hand"].z))
        add("upper_arm." + s, sh, el, "spine")
        add("forearm." + s, el, ha, "upper_arm." + s)
        hp = Vector((sx * J["hip_w"], 0, J["hip"].z))
        kn = Vector((sx * J["hip_w"], J["knee"].y, J["knee"].z))
        an = Vector((sx * J["hip_w"], 0, J["ankle"]))
        add("thigh." + s, hp, kn, "hips")
        add("shin." + s, kn, an, "thigh." + s)
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def joints(scale=1.0, hip=0.92, knee=0.5, ankle=0.08, hip_w=0.1, shoulder=(0.21, 0, 1.42),
           elbow=(0.25, 0.0, 1.16), hand=(0.27, -0.03, 0.92), neck=1.48, head_r=0.24):
    s = scale
    return {
        "hip": Vector((0, 0, hip * s)),
        "knee": Vector((0, -0.01, knee * s)),
        "ankle": ankle * s,
        "hip_w": hip_w * s,
        "shoulder": Vector(shoulder) * s,
        "elbow": Vector(elbow) * s,
        "hand": Vector(hand) * s,
        "neck": Vector((0, 0, neck * s)),
        "head_r": head_r * s,
    }


# ---------------------------------------------------------------- animation
class Animator:
    def __init__(self, rig):
        self.rig = rig
        self.pb = rig.pose.bones
        for b in self.pb:
            b.rotation_mode = "QUATERNION"
        rig.animation_data_create()

    def q_world(self, bone, axis, deg):
        b = self.rig.data.bones[bone]
        local_axis = (b.matrix_local.to_3x3().inverted() @ Vector(axis)).normalized()
        return Quaternion(local_axis, math.radians(deg))

    def _sign_toward(self, bone, axis, target):
        b = self.rig.data.bones[bone]
        v = b.vector.normalized()
        moved = Quaternion(Vector(axis), math.radians(10)) @ v
        return 1.0 if (moved - v).dot(Vector(target)) > 0 else -1.0

    def fwd(self, bone, deg):
        s = self._sign_toward(bone, (1, 0, 0), (0, -1, 0))
        return self.q_world(bone, (1, 0, 0), s * deg)

    def out(self, bone, deg):
        b = self.rig.data.bones[bone]
        side = 1.0 if b.head_local.x >= 0 else -1.0
        s = self._sign_toward(bone, (0, 1, 0), (side, 0, 0))
        return self.q_world(bone, (0, 1, 0), s * deg)

    def twist(self, bone, deg):
        return self.q_world(bone, (0, 0, 1), deg)

    def action(self, name, keys, loop):
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        self.rig.animation_data.action = act
        for frame, pose in keys:
            for b in self.pb:
                q = Quaternion()
                loc = Vector((0, 0, 0))
                if b.name in pose:
                    v = pose[b.name]
                    if isinstance(v, tuple):
                        q, loc = v
                    else:
                        q = v
                b.rotation_quaternion = q
                b.location = loc
                b.keyframe_insert("rotation_quaternion", frame=frame)
                b.keyframe_insert("location", frame=frame)
        return act


def hips_loc(rig, world_offset):
    b = rig.data.bones["hips"]
    return b.matrix_local.to_3x3().inverted() @ Vector(world_offset)


def standard_anims(rig, style="hero"):
    A = Animator(rig)
    I = Quaternion()
    heavy = style in ("boss",)
    hunch = 18 if style in ("imp", "boss") else 0

    def base(extra=None):
        d = {"spine": A.fwd("spine", hunch)} if hunch else {}
        if extra:
            for k, v in extra.items():
                if k == "spine" and hunch and not isinstance(v, tuple):
                    d[k] = A.fwd("spine", hunch) @ v
                else:
                    d[k] = v
        return d

    k = []
    for f, t in ((1, 0), (13, 1), (25, 0), (37, -1), (49, 0)):
        b = abs(t)
        k.append((f, base({
            "hips": (I, hips_loc(rig, (0, 0, -0.025 * b))),
            "spine": A.fwd("spine", 2 * b),
            "head": A.fwd("head", -2 * b),
            "upper_arm.L": A.out("upper_arm.L", 8 + 3 * b) @ A.fwd("upper_arm.L", 4),
            "upper_arm.R": A.out("upper_arm.R", 8 + 3 * b) @ A.fwd("upper_arm.R", 4),
            "forearm.L": A.fwd("forearm.L", 15 + 4 * b),
            "forearm.R": A.fwd("forearm.R", 15 + 4 * b),
        })))
    A.action("Idle", k, True)

    sw = 30 if heavy else 38
    k = []
    for f, ph in ((1, 0), (5, 1), (9, 2), (13, 3), (17, 0)):
        a = math.sin(ph * math.pi / 2)
        bob = abs(math.cos(ph * math.pi / 2))
        k.append((f, base({
            "hips": (A.twist("hips", 6 * a), hips_loc(rig, (0, 0, -0.04 + 0.05 * (1 - bob)))),
            "spine": A.fwd("spine", 10) @ A.twist("spine", -10 * a),
            "head": A.fwd("head", -6),
            "thigh.L": A.fwd("thigh.L", sw * a),
            "thigh.R": A.fwd("thigh.R", -sw * a),
            "shin.L": A.fwd("shin.L", -(10 + 45 * max(0, -a))),
            "shin.R": A.fwd("shin.R", -(10 + 45 * max(0, a))),
            "upper_arm.L": A.fwd("upper_arm.L", -32 * a) @ A.out("upper_arm.L", 10),
            "upper_arm.R": A.fwd("upper_arm.R", 32 * a) @ A.out("upper_arm.R", 10),
            "forearm.L": A.fwd("forearm.L", 45),
            "forearm.R": A.fwd("forearm.R", 45),
        })))
    A.action("Run", k, True)

    k = [
        (1, base({"upper_arm.R": A.out("upper_arm.R", 10), "forearm.R": A.fwd("forearm.R", 20)})),
        (6, base({"spine": A.twist("spine", 25) @ A.fwd("spine", -6),
                  "upper_arm.R": A.fwd("upper_arm.R", 150) @ A.out("upper_arm.R", 35),
                  "forearm.R": A.fwd("forearm.R", 40),
                  "upper_arm.L": A.fwd("upper_arm.L", 30), "forearm.L": A.fwd("forearm.L", 40),
                  "thigh.L": A.fwd("thigh.L", 20), "thigh.R": A.fwd("thigh.R", -15)})),
        (10, base({"spine": A.twist("spine", -30) @ A.fwd("spine", 18),
                   "upper_arm.R": A.fwd("upper_arm.R", 40) @ A.out("upper_arm.R", -10),
                   "forearm.R": A.fwd("forearm.R", 5),
                   "upper_arm.L": A.fwd("upper_arm.L", -25), "forearm.L": A.fwd("forearm.L", 30),
                   "thigh.L": A.fwd("thigh.L", 25), "thigh.R": A.fwd("thigh.R", -20),
                   "shin.R": A.fwd("shin.R", -15)})),
        (17, base({"upper_arm.R": A.out("upper_arm.R", 10), "forearm.R": A.fwd("forearm.R", 20)})),
    ]
    A.action("Attack", k, False)

    k = [
        (1, base({})),
        (6, base({"spine": A.fwd("spine", -10), "head": A.fwd("head", -8),
                  "upper_arm.L": A.fwd("upper_arm.L", 130) @ A.out("upper_arm.L", 25),
                  "upper_arm.R": A.fwd("upper_arm.R", 130) @ A.out("upper_arm.R", 25),
                  "forearm.L": A.fwd("forearm.L", 10), "forearm.R": A.fwd("forearm.R", 10)})),
        (11, base({"spine": A.fwd("spine", 14),
                   "upper_arm.L": A.fwd("upper_arm.L", 85) @ A.out("upper_arm.L", 10),
                   "upper_arm.R": A.fwd("upper_arm.R", 85) @ A.out("upper_arm.R", 10),
                   "forearm.L": A.fwd("forearm.L", 5), "forearm.R": A.fwd("forearm.R", 5),
                   "thigh.L": A.fwd("thigh.L", 18), "thigh.R": A.fwd("thigh.R", -12)})),
        (19, base({})),
    ]
    A.action("Cast", k, False)

    hip_h = rig.data.bones["hips"].head_local.z
    k = [
        (1, base({})),
        (8, base({"hips": (A.fwd("hips", -35), hips_loc(rig, (0, 0.1, -hip_h * 0.35))),
                  "upper_arm.L": A.out("upper_arm.L", 50), "upper_arm.R": A.out("upper_arm.R", 50),
                  "head": A.fwd("head", 20), "shin.L": A.fwd("shin.L", -40), "shin.R": A.fwd("shin.R", -30)})),
        (18, {"hips": (A.fwd("hips", -88), hips_loc(rig, (0, 0.25, -hip_h * 0.72))),
              "upper_arm.L": A.out("upper_arm.L", 75), "upper_arm.R": A.out("upper_arm.R", 70),
              "forearm.L": A.fwd("forearm.L", 20), "forearm.R": A.fwd("forearm.R", 30),
              "head": A.fwd("head", -10), "thigh.L": A.fwd("thigh.L", 75), "thigh.R": A.fwd("thigh.R", 70),
              "shin.L": A.fwd("shin.L", -10), "shin.R": A.fwd("shin.R", -20)}),
        (25, {"hips": (A.fwd("hips", -90), hips_loc(rig, (0, 0.27, -hip_h * 0.78))),
              "upper_arm.L": A.out("upper_arm.L", 80), "upper_arm.R": A.out("upper_arm.R", 75),
              "forearm.L": A.fwd("forearm.L", 15), "forearm.R": A.fwd("forearm.R", 25),
              "head": A.fwd("head", -15), "thigh.L": A.fwd("thigh.L", 85), "thigh.R": A.fwd("thigh.R", 80),
              "shin.L": A.fwd("shin.L", -5), "shin.R": A.fwd("shin.R", -15)}),
    ]
    A.action("Death", k, False)
    rig.animation_data.action = bpy.data.actions["Idle"]


# ---------------------------------------------------------------- body parts
def body_common(B, J, skin, top, pants, boots, belt=None, shoulder_pad=None, chest_scale=1.0, pad_k=1.0):
    hip = J["hip"]; neck = J["neck"]; hw = J["hip_w"]
    team = mat("TeamBand", hexc("ffffff"), 0.6)
    for s, sx in (("L", 1), ("R", -1)):
        hp = Vector((sx * hw, 0, hip.z))
        kn = Vector((sx * hw, J["knee"].y, J["knee"].z))
        an = Vector((sx * hw, 0, J["ankle"]))
        B.limb(pants, hp + Vector((0, 0, 0.03)), kn, 0.105, 0.085, bone="thigh." + s)
        B.limb(boots, kn + Vector((0, 0, 0.02)), an, 0.085, 0.08, bone="shin." + s)
        B.box(boots, (sx * hw, -0.06, J["ankle"] - 0.03), (0.14, 0.26, 0.1), bone="shin." + s)
        sh = Vector((sx * J["shoulder"].x, J["shoulder"].y, J["shoulder"].z))
        el = Vector((sx * J["elbow"].x, J["elbow"].y, J["elbow"].z))
        ha = Vector((sx * J["hand"].x, J["hand"].y, J["hand"].z))
        B.limb(top, sh, el, 0.078, 0.066, bone="upper_arm." + s)
        B.limb(top, el, ha + (el - ha).normalized() * 0.06, 0.066, 0.06, bone="forearm." + s)
        B.sphere(skin, ha, 0.068, bone="forearm." + s)
        B.sphere(team, sh + Vector((sx * 0.03, 0, 0.035)), 0.11 * pad_k, scale=(1.2, 1.05, 0.75), bone="upper_arm." + s)
        B.cyl(team, sh + (el - sh) * 0.55, 0.075, 0.072, 0.07, rot=UP.rotation_difference((el - sh).normalized()),
              bone="upper_arm." + s)
    B.box(pants, (0, 0, hip.z + 0.03), (hw * 2 + 0.16, 0.2, 0.18), bone="hips")
    B.limb(top, hip + Vector((0, 0, 0.1)), neck - Vector((0, 0, 0.04)), 0.15 * chest_scale, 0.2 * chest_scale,
           seg=8, bone="spine")
    B.cyl(top, (0, 0, neck.z - 0.04), 0.2 * chest_scale, 0.1, 0.06, bone="spine")
    if belt:
        B.cyl(belt, (0, 0, hip.z + 0.12), 0.165 * chest_scale, 0.165 * chest_scale, 0.06, bone="spine")
    B.cyl(skin, (0, 0, neck.z + 0.02), 0.05, 0.05, 0.08, bone="head")


def head_anime(B, J, skin, hair, eye_col, spikes, eyes=True):
    hr = J["head_r"]
    c = J["neck"] + Vector((0, 0, hr * 1.05))
    B.sphere(skin, c, hr, scale=(0.95, 0.95, 1.05), seg=(12, 8), bone="head", smooth=True)
    if eyes:
        white = mat("EyeWhite", hexc("f4f4f0"), rough=0.4)
        iris = mat("Eye_" + eye_col, hexc(eye_col), rough=0.3, emit=hexc(eye_col), emit_strength=0.6)
        for sx in (1, -1):
            B.box(white, (sx * hr * 0.36, -hr * 0.86, c.z - hr * 0.08), (hr * 0.34, hr * 0.12, hr * 0.42), bone="head")
            B.box(iris, (sx * hr * 0.34, -hr * 0.93, c.z - hr * 0.1), (hr * 0.22, hr * 0.06, hr * 0.32), bone="head")
    B.sphere(hair, c + Vector((0, hr * 0.08, hr * 0.12)), hr * 1.04, scale=(1.0, 1.0, 0.9), seg=(10, 6), bone="head")
    for d, length, base in spikes:
        d = Vector(d).normalized()
        B.limb(hair, c + d * hr * 0.55, c + d * (hr + length), base, 0.0, seg=5, bone="head")
    return c


HERO_SPIKES = [
    ((0, 0.2, 1), 0.22, 0.1), ((0.5, 0.3, 0.9), 0.2, 0.09), ((-0.5, 0.3, 0.9), 0.2, 0.09),
    ((0, 0.8, 0.6), 0.24, 0.1), ((0.6, 0.7, 0.3), 0.2, 0.09), ((-0.6, 0.7, 0.3), 0.2, 0.09),
    ((0.9, 0.2, 0.3), 0.15, 0.08), ((-0.9, 0.2, 0.3), 0.15, 0.08),
    ((0.35, -0.85, 0.55), 0.12, 0.07), ((-0.3, -0.85, 0.6), 0.13, 0.07), ((0, -0.9, 0.45), 0.1, 0.06),
    ((0, 0.9, -0.1), 0.2, 0.09),
]


def build_swordsman():
    reset_scene()
    J = joints()
    rig = make_skeleton("Swordsman", J)
    B = Builder("SwordsmanBody")
    skin = mat("Skin", hexc("f2c9a5"), 0.6)
    coat = mat("NavyCoat", hexc("23315c"), 0.7)
    pants = mat("DarkPants", hexc("1b1d26"), 0.8)
    boots = mat("Boots", hexc("3a2a22"), 0.7)
    scarf = mat("WhiteScarf", hexc("e9ecf2"), 0.8)
    hair = mat("TealHair", hexc("3fd6c8"), 0.5)
    belt = mat("Gold", hexc("d8a640"), 0.35, 0.8)
    blade_glow = mat("WindBlade", hexc("bff7ff"), 0.15, 0.6, emit=hexc("6fe8ff"), emit_strength=1.6)
    hilt = mat("Hilt", hexc("10131c"), 0.6)
    body_common(B, J, skin, coat, pants, boots, belt=belt, shoulder_pad=coat)
    head_anime(B, J, skin, hair, "1d8fd6", HERO_SPIKES)
    B.cyl(scarf, (0, 0, J["neck"].z - 0.01), 0.13, 0.11, 0.08, bone="spine")
    B.box(scarf, (0.08, 0.2, J["neck"].z - 0.2), (0.1, 0.04, 0.38), rot=(18, 0, 10), bone="spine")
    B.box(coat, (0, 0.06, J["hip"].z - 0.14), (0.36, 0.16, 0.26), rot=(-8, 0, 0), bone="hips")
    ha = Vector((-J["hand"].x, J["hand"].y, J["hand"].z))
    d = Vector((0, -0.85, -0.35)).normalized()
    B.limb(hilt, ha - d * 0.12, ha + d * 0.04, 0.025, 0.025, seg=6, bone="forearm.R")
    B.cyl(belt, ha + d * 0.07, 0.06, 0.06, 0.02, rot=UP.rotation_difference(d), seg=8, bone="forearm.R")
    B.box(blade_glow, ha + d * 0.6, (0.018, 0.07, 1.0), rot=UP.rotation_difference(d), bone="forearm.R")
    B.limb(hilt, (0.2, 0.05, J["hip"].z + 0.1), (0.25, 0.75, J["hip"].z - 0.2), 0.03, 0.025, seg=6, bone="hips")
    B.to_object(parent=rig)
    standard_anims(rig, "hero")
    export("hero_swordsman.glb")


def build_sorceress():
    reset_scene()
    J = joints(hip=0.9, knee=0.48, shoulder=(0.19, 0, 1.38), elbow=(0.23, 0, 1.13), hand=(0.25, -0.03, 0.9),
               neck=1.44, head_r=0.235)
    rig = make_skeleton("Sorceress", J)
    B = Builder("SorceressBody")
    skin = mat("Skin", hexc("f5d2b3"), 0.6)
    white = mat("MikoWhite", hexc("f3f0ea"), 0.8)
    red = mat("Crimson", hexc("b3202e"), 0.7)
    boots = mat("Sandals", hexc("4b2b1f"), 0.7)
    hair = mat("RedHair", hexc("e0412f"), 0.5)
    gold = mat("Gold", hexc("d8a640"), 0.35, 0.8)
    wood = mat("StaffWood", hexc("5a3a24"), 0.8)
    orb = mat("FireOrb", hexc("ffb347"), 0.2, emit=hexc("ff7a1a"), emit_strength=3.0)
    body_common(B, J, skin, white, red, boots, belt=red, chest_scale=0.88, pad_k=0.85)
    c = head_anime(B, J, skin, hair, "e8a21c", [
        ((0, 0.3, 1), 0.12, 0.09), ((0.4, -0.85, 0.5), 0.1, 0.07), ((-0.4, -0.85, 0.5), 0.1, 0.07),
        ((0, -0.9, 0.45), 0.08, 0.06), ((0.85, 0.1, 0.0), 0.08, 0.08), ((-0.85, 0.1, 0.0), 0.08, 0.08),
    ])
    hr = J["head_r"]
    B.box(hair, (0, hr * 0.7, c.z - hr * 1.3), (hr * 1.7, hr * 0.5, hr * 2.4), rot=(-6, 0, 0), bone="head")
    for sx in (1, -1):
        p0 = c + Vector((sx * hr * 0.8, hr * 0.4, hr * 0.5))
        p1 = p0 + Vector((sx * 0.25, 0.25, -0.75))
        B.limb(hair, p0, p1, 0.09, 0.02, seg=6, bone="head")
        B.sphere(gold, p0, 0.04, bone="head")
    B.limb(red, J["hip"] + Vector((0, 0, 0.1)), Vector((0, 0, J["knee"].z - 0.06)), 0.17, 0.3, seg=10, bone="hips")
    for s, sx in (("L", 1), ("R", -1)):
        el = Vector((sx * J["elbow"].x, J["elbow"].y, J["elbow"].z))
        ha = Vector((sx * J["hand"].x, J["hand"].y, J["hand"].z))
        B.limb(white, el, ha + (el - ha).normalized() * 0.04, 0.07, 0.11, seg=8, bone="forearm." + s)
    ha = Vector((-J["hand"].x, J["hand"].y, J["hand"].z))
    B.limb(wood, ha + Vector((0, -0.05, -0.75)), ha + Vector((0, -0.05, 0.75)), 0.025, 0.03, seg=6, bone="forearm.R")
    top = ha + Vector((0, -0.05, 0.85))
    B.cyl(gold, top - Vector((0, 0, 0.08)), 0.03, 0.08, 0.08, bone="forearm.R")
    B.ico(orb, top + Vector((0, 0, 0.04)), 0.09, sub=1, bone="forearm.R")
    B.to_object(parent=rig)
    standard_anims(rig, "hero")
    export("hero_sorceress.glb")


def build_assassin():
    reset_scene()
    J = joints(hip=0.9, knee=0.48, shoulder=(0.2, 0, 1.4), elbow=(0.24, 0, 1.15), hand=(0.26, -0.03, 0.91),
               neck=1.46)
    rig = make_skeleton("Assassin", J)
    B = Builder("AssassinBody")
    skin = mat("Skin", hexc("e9c3a0"), 0.6)
    black = mat("ShadowCloth", hexc("1a1622"), 0.85)
    plum = mat("Plum", hexc("4a2463"), 0.7)
    boots = mat("Wraps", hexc("2c2733"), 0.8)
    hair = mat("VioletHair", hexc("6b4ad6"), 0.5)
    mask = mat("PurpleScarf", hexc("8e3fd1"), 0.7)
    steel = mat("DarkSteel", hexc("7d8596"), 0.25, 1.0)
    glow = mat("ShadowEdge", hexc("d6b3ff"), 0.2, 0.4, emit=hexc("a35cff"), emit_strength=1.4)
    body_common(B, J, skin, black, black, boots, belt=plum, shoulder_pad=plum, chest_scale=0.92)
    c = head_anime(B, J, skin, hair, "b04dff", [
        ((0, 0.4, 1), 0.2, 0.1), ((0.6, 0.4, 0.8), 0.18, 0.08), ((-0.6, 0.4, 0.8), 0.18, 0.08),
        ((0, 0.9, 0.4), 0.22, 0.1), ((0.7, 0.6, 0.2), 0.16, 0.08), ((-0.7, 0.6, 0.2), 0.16, 0.08),
        ((0.2, -0.9, 0.5), 0.14, 0.07), ((-0.25, -0.88, 0.55), 0.16, 0.07),
    ])
    hr = J["head_r"]
    B.sphere(mask, c - Vector((0, 0.02, hr * 0.45)), hr * 0.98, scale=(1.0, 1.02, 0.55), seg=(10, 6), bone="head")
    B.box(mask, (0.06, 0.22, J["neck"].z - 0.15), (0.09, 0.04, 0.42), rot=(20, 0, -12), bone="spine")
    B.box(mask, (-0.04, 0.24, J["neck"].z - 0.25), (0.08, 0.04, 0.5), rot=(26, 0, 8), bone="spine")
    for s, sx in (("L", 1), ("R", -1)):
        ha = Vector((sx * J["hand"].x, J["hand"].y, J["hand"].z))
        d = Vector((sx * 0.15, 0.25, -1)).normalized()
        q = UP.rotation_difference(d)
        B.box(steel, ha + d * 0.25, (0.02, 0.06, 0.42), rot=q, bone="forearm." + s)
        B.box(glow, ha + d * 0.25 + Vector((0, -0.032, 0)), (0.008, 0.012, 0.4), rot=q, bone="forearm." + s)
        B.box(plum, ha + d * 0.03, (0.1, 0.03, 0.03), rot=q, bone="forearm." + s)
    B.to_object(parent=rig)
    standard_anims(rig, "hero")
    export("hero_assassin.glb")


def build_imp():
    reset_scene()
    J = joints(hip=0.5, knee=0.27, ankle=0.06, hip_w=0.09, shoulder=(0.2, 0, 0.88), elbow=(0.27, -0.02, 0.65),
               hand=(0.3, -0.06, 0.42), neck=0.92, head_r=0.22)
    rig = make_skeleton("Imp", J)
    B = Builder("ImpBody")
    skin = mat("ImpSkin", hexc("6d5a8c"), 0.8)
    belly = mat("ImpBelly", hexc("a594c2"), 0.8)
    cloth = mat("Loincloth", hexc("4a3a2a"), 0.9)
    horn = mat("Horn", hexc("e7dcc0"), 0.5)
    claw = mat("Claw", hexc("2a2230"), 0.5)
    eye = mat("ImpEye", hexc("ffe14a"), 0.3, emit=hexc("ffcc00"), emit_strength=2.5)
    hip = J["hip"]; neck = J["neck"]
    for s, sx in (("L", 1), ("R", -1)):
        hp = Vector((sx * J["hip_w"], 0, hip.z)); kn = Vector((sx * J["hip_w"], J["knee"].y, J["knee"].z))
        an = Vector((sx * J["hip_w"], 0, J["ankle"]))
        B.limb(skin, hp, kn, 0.075, 0.06, bone="thigh." + s)
        B.limb(skin, kn, an, 0.06, 0.05, bone="shin." + s)
        B.box(claw, (sx * J["hip_w"], -0.06, 0.03), (0.11, 0.18, 0.06), bone="shin." + s)
        sh = Vector((sx * J["shoulder"].x, 0, J["shoulder"].z)); el = Vector((sx * J["elbow"].x, J["elbow"].y, J["elbow"].z))
        ha = Vector((sx * J["hand"].x, J["hand"].y, J["hand"].z))
        B.limb(skin, sh, el, 0.065, 0.05, bone="upper_arm." + s)
        B.limb(skin, el, ha, 0.05, 0.045, bone="forearm." + s)
        B.sphere(skin, ha, 0.06, bone="forearm." + s)
        for i in (-1, 0, 1):
            B.limb(claw, ha + Vector((i * 0.03, -0.03, -0.02)), ha + Vector((i * 0.04, -0.09, -0.1)), 0.015, 0.0, seg=4,
                   bone="forearm." + s)
    B.box(cloth, (0, 0, hip.z), (0.3, 0.2, 0.16), bone="hips")
    B.sphere(belly, (0, -0.02, hip.z + 0.2), 0.2, scale=(1.0, 0.9, 1.1), bone="spine")
    B.limb(skin, hip + Vector((0, 0.02, 0.15)), neck, 0.17, 0.2, bone="spine")
    hr = J["head_r"]; c = neck + Vector((0, -0.03, hr * 0.9))
    B.sphere(skin, c, hr, scale=(1.1, 1.0, 0.95), seg=(10, 7), bone="head")
    for sx in (1, -1):
        B.box(eye, (sx * hr * 0.4, -hr * 0.92 - 0.03, c.z + 0.02), (hr * 0.32, 0.03, hr * 0.18), rot=(0, sx * -12, 0),
              bone="head")
        B.limb(horn, c + Vector((sx * hr * 0.55, 0, hr * 0.55)), c + Vector((sx * hr * 1.0, 0.05, hr * 1.4)), 0.05, 0.0,
               seg=6, bone="head")
        B.limb(skin, c + Vector((sx * hr * 0.9, 0, 0)), c + Vector((sx * hr * 1.6, 0.05, hr * 0.3)), 0.06, 0.0, seg=4,
               bone="head")
    B.box(horn, (0, -hr * 0.95, c.z - hr * 0.45), (hr * 0.8, 0.03, 0.05), bone="head")
    B.to_object(parent=rig)
    standard_anims(rig, "imp")
    export("creep_imp.glb")


def build_boss():
    reset_scene()
    s = 1.9
    J = joints(scale=s, hip=0.9, knee=0.48, hip_w=0.13, shoulder=(0.3, 0, 1.38), elbow=(0.38, -0.02, 1.1),
               hand=(0.42, -0.08, 0.86), neck=1.44, head_r=0.2)
    rig = make_skeleton("Oni", J)
    B = Builder("OniBody")
    skin = mat("OniSkin", hexc("b8322a"), 0.75)
    dark = mat("OniDark", hexc("6d1a17"), 0.8)
    tiger = mat("TigerCloth", hexc("e3a72f"), 0.8)
    stripe = mat("TigerStripe", hexc("1e1712"), 0.8)
    horn = mat("Horn", hexc("e7dcc0"), 0.5)
    iron = mat("Iron", hexc("3b3d44"), 0.45, 0.9)
    stud = mat("Studs", hexc("a9adb6"), 0.3, 1.0)
    hairm = mat("OniHair", hexc("efe9df"), 0.7)
    eye = mat("OniEye", hexc("fff07a"), 0.3, emit=hexc("ffd400"), emit_strength=3.0)
    hip = J["hip"]; neck = J["neck"]
    for sd, sx in (("L", 1), ("R", -1)):
        hp = Vector((sx * J["hip_w"], 0, hip.z)); kn = Vector((sx * J["hip_w"], J["knee"].y, J["knee"].z))
        an = Vector((sx * J["hip_w"], 0, J["ankle"]))
        B.limb(skin, hp, kn, 0.2, 0.16, bone="thigh." + sd)
        B.limb(skin, kn, an, 0.16, 0.13, bone="shin." + sd)
        B.box(dark, (sx * J["hip_w"], -0.1, 0.08), (0.24, 0.4, 0.16), bone="shin." + sd)
        B.cyl(stud, kn - Vector((0, 0, 0.18)), 0.15, 0.15, 0.08, bone="shin." + sd)
        sh = Vector((sx * J["shoulder"].x, 0, J["shoulder"].z)); el = Vector((sx * J["elbow"].x, J["elbow"].y, J["elbow"].z))
        ha = Vector((sx * J["hand"].x, J["hand"].y, J["hand"].z))
        B.sphere(skin, sh, 0.2, bone="upper_arm." + sd)
        B.limb(skin, sh, el, 0.17, 0.14, bone="upper_arm." + sd)
        B.limb(skin, el, ha, 0.14, 0.12, bone="forearm." + sd)
        B.cyl(stud, el + (ha - el) * 0.55, 0.15, 0.15, 0.12, rot=UP.rotation_difference((ha - el).normalized()),
              bone="forearm." + sd)
        B.sphere(skin, ha, 0.13, bone="forearm." + sd)
    B.limb(skin, hip + Vector((0, 0, 0.2)), neck - Vector((0, 0, 0.05)), 0.42, 0.5, seg=10, bone="spine")
    B.sphere(skin, (0, -0.08, hip.z + 0.45), 0.42, scale=(1.0, 0.9, 0.9), bone="spine")
    B.box(tiger, (0, 0, hip.z + 0.02), (0.75, 0.5, 0.34), bone="hips")
    for i in range(4):
        B.box(stripe, (-0.27 + i * 0.18, -0.255, hip.z + 0.02), (0.05, 0.02, 0.3), rot=(0, 15, 0), bone="hips")
    hr = J["head_r"]; c = neck + Vector((0, -0.05, hr * 0.95))
    B.sphere(skin, c, hr, scale=(1.05, 1.0, 1.0), seg=(10, 7), bone="head")
    B.sphere(hairm, c + Vector((0, 0.1, 0.05)), hr * 1.1, scale=(1.05, 0.9, 1.0), seg=(9, 6), bone="head")
    for sx in (1, -1):
        B.box(eye, (sx * hr * 0.38, -hr * 0.95 - 0.05, c.z + 0.03), (hr * 0.3, 0.04, hr * 0.14), rot=(0, sx * -15, 0),
              bone="head")
        B.limb(horn, c + Vector((sx * hr * 0.5, -0.05, hr * 0.6)), c + Vector((sx * hr * 1.1, 0.0, hr * 1.9)), 0.08,
               0.0, seg=6, bone="head")
        B.limb(horn, c + Vector((sx * hr * 0.35, -hr * 0.9, -hr * 0.45)), c + Vector((sx * hr * 0.4, -hr * 1.05, hr * 0.0)),
               0.035, 0.0, seg=4, bone="head")
    ha = Vector((-J["hand"].x, J["hand"].y, J["hand"].z))
    d = Vector((0, -0.55, 0.85)).normalized()
    B.limb(iron, ha - d * 0.25, ha + d * 1.6, 0.06, 0.16, seg=8, bone="forearm.R")
    q = UP.rotation_difference(d)
    for i in range(5):
        t = 0.5 + i * 0.25
        p = ha + d * t
        r = 0.06 + (0.1 * t / 1.6)
        for a in range(0, 360, 90):
            ang = math.radians(a + i * 45)
            off = q @ Vector((math.cos(ang) * r, math.sin(ang) * r, 0))
            B.limb(stud, p + off * 0.8, p + off * 1.6, 0.04, 0.0, seg=4, bone="forearm.R")
    B.to_object(parent=rig)
    standard_anims(rig, "boss")
    export("boss_oni.glb")


# ---------------------------------------------------------------- props
def crystal_cluster(B, m, base_m, loc, size, seed, count=7):
    rnd = random.Random(seed)
    x, y, z = loc
    B.ico(base_m, (x, y, z + 0.2 * size), 0.7 * size, scale=(1.3, 1.1, 0.5), sub=1, jitter=0.25, seed=seed)
    for k in range(count):
        a = rnd.uniform(0, math.tau)
        r = rnd.uniform(0.0, 0.55) * size
        h = rnd.uniform(0.8, 2.0) * size * (1.4 if k == 0 else 1.0)
        tilt = (math.degrees(math.cos(a)) * 0.0 + rnd.uniform(-25, 25), rnd.uniform(-25, 25), rnd.uniform(0, 60))
        B.cyl(m, (x + math.cos(a) * r, y + math.sin(a) * r, z + 0.3 * size + h / 2), 0.22 * size, 0.0, h, seg=5,
              rot=tilt)


def build_props():
    reset_scene()
    stone = mat("Stone", hexc("77736d"), 0.9)
    stone_dark = mat("StoneDark", hexc("4f4c4a"), 0.9)
    slate = mat("Slate", hexc("2c2f38"), 0.85)
    gem = mat("CrystalGem", hexc("6fd0ff"), 0.1, 0.0, emit=hexc("3aa8ff"), emit_strength=1.5)
    rune = mat("PortalGlow", hexc("9ff0ff"), 0.2, emit=hexc("41d7ff"), emit_strength=1.2)
    torii_red = mat("ToriiRed", hexc("c0392b"), 0.6)
    torii_black = mat("ToriiBlack", hexc("1d1a1a"), 0.7)
    bark = mat("Bark", hexc("5b3b2a"), 0.9)
    bark_dark = mat("BarkDark", hexc("3a2a22"), 0.9)
    sakura = mat("Sakura", hexc("de7aa3"), 0.85)
    sakura2 = mat("SakuraLight", hexc("eb9dbd"), 0.85)
    pine = mat("Pine", hexc("2f6b3f"), 0.85)
    pine2 = mat("PineDark", hexc("234f31"), 0.85)
    snow = mat("Snow", hexc("eef4fa"), 0.7)
    leaf = mat("ForestLeaf", hexc("2a4d2a"), 0.9)
    leaf2 = mat("ForestLeafDark", hexc("1c3720"), 0.9)
    wood = mat("Wood", hexc("8a5a36"), 0.8)
    wood_dark = mat("WoodDark", hexc("4a3020"), 0.85)
    roof = mat("RoofTile", hexc("5b6068"), 0.65)
    roof_dark = mat("RoofTileDark", hexc("3f444b"), 0.7)
    plaster = mat("Plaster", hexc("e8e2d4"), 0.85)
    cloth = mat("Awning", hexc("e7d3a3"), 0.9)
    lamp = mat("LanternLight", hexc("ffd9a0"), 0.4, emit=hexc("ffb347"), emit_strength=1.2)
    gold = mat("Gold", hexc("d8a640"), 0.35, 0.8)
    gold_bright = mat("GoldBright", hexc("f0c45a"), 0.3, 0.9)
    red_cr = mat("RedCrystal", hexc("ff3b3b"), 0.15, emit=hexc("ff1a1a"), emit_strength=1.4)
    ice_cr = mat("IceCrystal", hexc("bfe9ff"), 0.08, emit=hexc("6cc8ff"), emit_strength=0.6)
    ice_rock = mat("IceRock", hexc("9fc3d6"), 0.35)
    water = mat("FountainWater", hexc("ffffff"), 0.1, emit=hexc("ffffff"), emit_strength=1.0)
    team = mat("TeamCloth", hexc("ffffff"), 0.8)
    coal = mat("Coal", hexc("151515"), 0.9)
    carrot = mat("Carrot", hexc("e8761c"), 0.7)

    # Кристалл выживания
    B = Builder("Crystal")
    B.cyl(stone_dark, (0, 0, 0.2), 2.0, 1.8, 0.4, seg=8)
    B.cyl(stone, (0, 0, 0.6), 1.5, 1.3, 0.4, seg=8)
    B.cyl(stone_dark, (0, 0, 0.9), 1.0, 0.9, 0.2, seg=8)
    B.cyl(gem, (0, 0, 2.2), 0.75, 0.0, 2.6, seg=6, rot=(0, 0, 30))
    B.cyl(gem, (0, 0, 1.25), 0.0, 0.75, 0.7, seg=6, rot=(0, 0, 30))
    for i in range(6):
        a = math.radians(i * 60)
        B.cyl(gem, (math.cos(a) * 1.2, math.sin(a) * 1.2, 1.15), 0.18, 0.0, 0.9, seg=4,
              rot=(math.degrees(math.sin(a)) * -0.3, math.degrees(math.cos(a)) * 0.3, i * 20))
        B.box(stone, (math.cos(a) * 1.75, math.sin(a) * 1.75, 0.5), (0.3, 0.3, 0.6), rot=(0, 0, i * 60))
    B.to_object()

    # Круг силы (портал)
    B = Builder("Portal")
    n = 16
    for i in range(n):
        a = i / n * math.tau
        B.box(stone, (math.cos(a) * 1.9, math.sin(a) * 1.9, 0.06), (0.75, 0.45, 0.12), rot=(0, 0, math.degrees(a) + 90))
    B.cyl(rune, (0, 0, 0.03), 1.65, 1.65, 0.04, seg=24)
    for i in range(4):
        a = i / 4 * math.tau + math.pi / 4
        p = (math.cos(a) * 2.35, math.sin(a) * 2.35, 0)
        B.cyl(stone_dark, (p[0], p[1], 0.55), 0.18, 0.14, 1.1, seg=6)
        B.ico(rune, (p[0], p[1], 1.25), 0.14, sub=0)
    B.to_object()

    # Тории — врата монстров
    B = Builder("Torii")
    for sx in (1, -1):
        B.cyl(torii_red, (sx * 1.9, 0, 2.4), 0.24, 0.2, 4.8, seg=8)
        B.cyl(torii_black, (sx * 1.9, 0, 0.2), 0.3, 0.3, 0.4, seg=8)
    B.box(torii_red, (0, 0, 3.9), (4.6, 0.3, 0.3))
    B.box(torii_black, (0, 0, 4.75), (5.6, 0.55, 0.3))
    B.box(torii_red, (0, 0, 4.5), (5.0, 0.42, 0.25))
    for sx in (1, -1):
        B.box(torii_black, (sx * 2.95, 0, 4.85), (0.6, 0.55, 0.25), rot=(0, sx * -14, 0))
    B.box(torii_black, (0, -0.05, 4.2), (0.25, 0.32, 0.6))
    B.to_object()

    # Сакура
    B = Builder("TreeSakura")
    B.limb(bark, (0, 0, 0), (0.2, 0.1, 2.0), 0.28, 0.18, seg=7)
    B.limb(bark, (0.2, 0.1, 1.8), (1.0, 0.3, 2.7), 0.14, 0.07, seg=6)
    B.limb(bark, (0.15, 0.1, 1.9), (-0.7, -0.2, 2.8), 0.13, 0.07, seg=6)
    for i, (x, y, z, r) in enumerate([(0.2, 0.1, 3.0, 1.3), (1.1, 0.3, 2.8, 0.9), (-0.8, -0.2, 2.9, 0.95),
                                      (0.3, -0.7, 2.7, 0.8), (-0.1, 0.8, 2.9, 0.85), (0.5, 0.2, 3.7, 0.8)]):
        B.ico(sakura if i % 2 == 0 else sakura2, (x, y, z), r, sub=1, jitter=0.18, seed=i + 10)
    B.to_object()

    # Сосна
    B = Builder("TreePine")
    B.cyl(bark, (0, 0, 0.7), 0.25, 0.18, 1.4, seg=6)
    for i, (z, r, h) in enumerate([(1.5, 1.6, 1.8), (2.6, 1.25, 1.6), (3.6, 0.85, 1.4), (4.4, 0.45, 1.0)]):
        B.cyl(pine if i % 2 == 0 else pine2, (0, 0, z), r, 0.0, h, seg=7, rot=(0, 0, i * 17))
    B.to_object()

    # Заснеженная сосна (как в зимних зонах карты)
    B = Builder("SnowPine")
    B.cyl(bark_dark, (0, 0, 0.7), 0.25, 0.18, 1.4, seg=6)
    for i, (z, r, h) in enumerate([(1.6, 1.8, 2.0), (2.8, 1.4, 1.8), (3.9, 1.0, 1.5), (4.8, 0.55, 1.1)]):
        B.cyl(pine2, (0, 0, z), r, 0.0, h, seg=7, rot=(0, 0, i * 23))
        B.cyl(snow, (0, 0, z + h * 0.28), r * 0.55, 0.0, h * 0.45, seg=7, rot=(0, 0, i * 23 + 10))
        B.cyl(snow, (0, 0, z - h * 0.42), r * 1.02, r * 0.8, 0.12, seg=7, rot=(0, 0, i * 23))
    B.to_object()

    # Лиственное дерево для леса
    B = Builder("ForestTree")
    B.limb(bark_dark, (0, 0, 0), (0.1, 0.0, 2.3), 0.32, 0.2, seg=7)
    B.limb(bark_dark, (0.1, 0.0, 2.0), (0.9, 0.4, 3.0), 0.15, 0.07, seg=6)
    B.limb(bark_dark, (0.05, 0.0, 2.1), (-0.8, -0.3, 3.1), 0.14, 0.07, seg=6)
    for i, (x, y, z, r) in enumerate([(0.1, 0.0, 3.4, 1.5), (1.0, 0.4, 3.1, 1.0), (-0.9, -0.3, 3.2, 1.05),
                                      (0.2, -0.8, 3.0, 0.9), (-0.2, 0.9, 3.3, 0.95), (0.3, 0.1, 4.2, 0.9)]):
        B.ico(leaf if i % 2 == 0 else leaf2, (x, y, z), r, sub=1, jitter=0.2, seed=i + 40)
    B.to_object()

    # Куст
    B = Builder("Bush")
    for i, (x, y, z, r) in enumerate([(0, 0, 0.45, 0.7), (0.5, 0.2, 0.35, 0.5), (-0.45, -0.1, 0.35, 0.55)]):
        B.ico(leaf if i % 2 == 0 else leaf2, (x, y, z), r, sub=1, jitter=0.2, seed=i + 70)
    B.to_object()

    # Камни
    for k in range(3):
        B = Builder("Rock%d" % k)
        B.ico(stone if k != 1 else stone_dark, (0, 0, 0.35), 0.8, scale=(1.3, 1.0, 0.75), sub=1, jitter=0.25, seed=k * 3)
        if k == 2:
            B.ico(stone, (0.9, 0.3, 0.2), 0.45, sub=1, jitter=0.3, seed=99)
        B.to_object()

    # Ледяная глыба
    B = Builder("IceRock")
    B.ico(ice_rock, (0, 0, 0.5), 1.0, scale=(1.4, 1.0, 0.9), sub=1, jitter=0.3, seed=5)
    B.ico(ice_rock, (1.0, 0.3, 0.3), 0.6, sub=1, jitter=0.3, seed=6)
    B.to_object()

    # Красные кристаллы на тёмном камне (у стен и ворот)
    B = Builder("RedCrystal")
    crystal_cluster(B, red_cr, stone_dark, (0, 0, 0), 1.0, 11)
    B.to_object()

    # Голубые ледяные кристаллы
    B = Builder("IceCrystal")
    crystal_cluster(B, ice_cr, ice_rock, (0, 0, 0), 1.0, 21, count=6)
    B.to_object()

    # Низкая стена (сегмент 4 м вдоль X)
    B = Builder("LowWall")
    B.box(slate, (0, 0, 0.55), (4.0, 0.8, 1.1))
    B.box(stone_dark, (0, 0, 1.15), (4.1, 0.95, 0.14))
    for i in range(4):
        B.box(stone, (-1.5 + i * 1.0, -0.41, 0.55), (0.06, 0.02, 0.9))
    B.to_object()

    # Лавка (старая, для декора)
    B = Builder("Shop")
    B.box(wood, (0, 0, 0.5), (3.2, 2.2, 1.0))
    B.box(cloth, (0, -1.15, 1.0), (3.2, 0.1, 0.25))
    for sx in (1, -1):
        for sy in (1, -1):
            B.cyl(wood, (sx * 1.5, sy * 1.0, 1.5), 0.1, 0.1, 3.0, seg=6)
    B.cyl(roof, (0, 0, 3.4), 2.8, 0.25, 1.1, seg=4, rot=(0, 0, 45), scale=(1.15, 0.85, 1))
    B.to_object()

    # Дом выживания — японский дом
    B = Builder("House")
    B.box(stone_dark, (0, 0, 0.3), (8.6, 5.6, 0.6))
    B.box(plaster, (0, 0, 1.8), (7.6, 4.6, 2.4))
    for x in (-3.8, -1.3, 1.3, 3.8):
        B.box(wood_dark, (x, -2.32, 1.8), (0.22, 0.12, 2.4))
        B.box(wood_dark, (x, 2.32, 1.8), (0.22, 0.12, 2.4))
    B.box(wood_dark, (0, -2.32, 3.0), (7.8, 0.14, 0.2))
    B.box(wood_dark, (0, -2.32, 0.7), (7.8, 0.14, 0.2))
    B.box(wood, (0, -2.4, 1.4), (1.8, 0.1, 1.6))
    B.box(roof_dark, (0, 0, 3.15), (9.4, 6.4, 0.25))
    B.cyl(roof, (0, 0, 4.15), 5.6, 1.0, 1.9, seg=4, rot=(0, 0, 45), scale=(1.25, 0.82, 1))
    B.box(roof_dark, (0, 0, 5.1), (5.0, 0.4, 0.3))
    for sx in (1, -1):
        B.cyl(roof_dark, (sx * 2.6, 0, 5.2), 0.18, 0.05, 0.5, seg=6, rot=(0, sx * 30, 0))
    B.box(lamp, (-2.6, -2.45, 1.6), (0.9, 0.06, 0.8))
    B.box(lamp, (2.6, -2.45, 1.6), (0.9, 0.06, 0.8))
    B.to_object()

    # Золотая пагода (Затерянные руины)
    B = Builder("Pagoda")
    B.box(plaster, (0, 0, 0.15), (3.2, 3.2, 0.3))
    for i, (s, z) in enumerate([(2.4, 0.3), (1.9, 1.5), (1.4, 2.6)]):
        B.box(torii_red if i == 0 else wood_dark, (0, 0, z + 0.45), (s * 0.75, s * 0.75, 0.9))
        B.cyl(gold_bright, (0, 0, z + 1.05), s * 1.05, s * 0.35, 0.45, seg=4, rot=(0, 0, 45))
    B.cyl(gold, (0, 0, 4.0), 0.12, 0.0, 1.0, seg=6)
    B.to_object()

    # Золотой обелиск (Камень силы)
    B = Builder("Obelisk")
    B.box(stone_dark, (0, 0, 0.2), (2.4, 2.4, 0.4))
    B.box(stone, (0, 0, 0.5), (1.8, 1.8, 0.2))
    B.cyl(gold_bright, (0, 0, 2.6), 0.75, 0.42, 4.0, seg=4, rot=(0, 0, 45))
    B.cyl(gold, (0, 0, 5.0), 0.42, 0.0, 0.8, seg=4, rot=(0, 0, 45))
    for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        B.box(rune, (sx * 0.5, sy * 0.5, 2.6), (0.08 if sx else 0.5, 0.08 if sy else 0.5, 1.8))
    B.to_object()

    # Фонтан (вода перекрашивается в игре: жизнь — красный, мана — синий)
    B = Builder("Fountain")
    n = 12
    for i in range(n):
        a = i / n * math.tau
        B.box(stone, (math.cos(a) * 1.55, math.sin(a) * 1.55, 0.35), (0.85, 0.45, 0.7), rot=(0, 0, math.degrees(a) + 90))
    B.cyl(stone_dark, (0, 0, 0.1), 1.6, 1.6, 0.2, seg=16)
    B.cyl(water, (0, 0, 0.55), 1.38, 1.38, 0.06, seg=16)
    B.cyl(stone, (0, 0, 1.0), 0.35, 0.28, 1.4, seg=8)
    B.cyl(stone, (0, 0, 1.75), 0.75, 0.3, 0.25, seg=10)
    B.cyl(water, (0, 0, 1.9), 0.62, 0.62, 0.05, seg=10)
    B.ico(water, (0, 0, 2.3), 0.28, sub=1)
    B.to_object()

    # Снеговик
    B = Builder("Snowman")
    B.ico(snow, (0, 0, 0.55), 0.6, sub=2)
    B.ico(snow, (0, 0, 1.3), 0.42, sub=2)
    B.ico(snow, (0, 0, 1.85), 0.3, sub=2)
    B.cyl(coal, (0, 0, 2.2), 0.24, 0.24, 0.3, seg=10)
    B.cyl(coal, (0, 0, 2.06), 0.36, 0.36, 0.04, seg=12)
    B.cyl(carrot, (0, -0.38, 1.85), 0.05, 0.0, 0.25, seg=6, rot=(90, 0, 0))
    for sx in (1, -1):
        B.ico(coal, (sx * 0.1, -0.26, 1.95), 0.035, sub=0)
    B.to_object()

    # Каменный фонарь
    B = Builder("Lantern")
    B.cyl(stone, (0, 0, 0.1), 0.45, 0.45, 0.2, seg=6)
    B.cyl(stone, (0, 0, 0.75), 0.14, 0.14, 1.1, seg=6)
    B.cyl(stone, (0, 0, 1.38), 0.38, 0.38, 0.16, seg=6)
    B.box(lamp, (0, 0, 1.68), (0.42, 0.42, 0.42))
    for sx, sy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        B.box(stone, (sx * 0.22, sy * 0.22, 1.68), (0.08, 0.08, 0.44))
    B.cyl(stone_dark, (0, 0, 2.05), 0.6, 0.05, 0.4, seg=6)
    B.to_object()

    # Колонна арены
    B = Builder("ArenaPillar")
    B.cyl(stone_dark, (0, 0, 0.2), 0.8, 0.8, 0.4, seg=8)
    B.cyl(stone, (0, 0, 2.2), 0.5, 0.45, 3.6, seg=8)
    B.cyl(stone_dark, (0, 0, 4.1), 0.7, 0.7, 0.3, seg=8)
    B.ico(rune, (0, 0, 4.6), 0.3, sub=0)
    B.to_object()

    # Жаровня
    B = Builder("Brazier")
    B.cyl(stone_dark, (0, 0, 0.6), 0.25, 0.18, 1.2, seg=6)
    B.cyl(stone, (0, 0, 1.3), 0.6, 0.35, 0.35, seg=8)
    B.ico(lamp, (0, 0, 1.55), 0.35, sub=1, scale=(1, 1, 0.6))
    B.to_object()

    # Башня лагеря: каменная башня с парящим кристаллом (цвет команды задаётся в игре)
    tower_gem = mat("TowerGem", hexc("ffffff"), 0.1, emit=hexc("ffffff"), emit_strength=1.2)
    B = Builder("Tower")
    B.cyl(stone_dark, (0, 0, 0.3), 1.55, 1.6, 0.6, seg=8)
    B.cyl(stone, (0, 0, 2.3), 1.15, 0.85, 3.4, seg=8)
    for i in range(8):
        a = i / 8 * math.tau + math.tau / 16
        B.box(stone_dark, (math.cos(a) * 1.05, math.sin(a) * 1.05, 1.6), (0.22, 0.22, 2.4), rot=(0, 0, math.degrees(a)))
    B.cyl(slate, (0, 0, 4.1), 1.25, 1.25, 0.3, seg=8)
    for i in range(8):
        a = i / 8 * math.tau
        B.box(stone, (math.cos(a) * 1.05, math.sin(a) * 1.05, 4.45), (0.42, 0.42, 0.45), rot=(0, 0, math.degrees(a)))
    B.cyl(snow, (0, 0, 4.28), 0.95, 0.95, 0.08, seg=8)
    B.cyl(stone_dark, (0, 0, 4.6), 0.35, 0.5, 0.6, seg=6)
    B.cyl(tower_gem, (0, 0, 5.75), 0.0, 0.42, 0.9, seg=5)
    B.cyl(tower_gem, (0, 0, 6.6), 0.42, 0.0, 0.8, seg=5)
    for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        B.box(red_cr, (sx * 0.62, sy * 0.62, 3.2), (0.16, 0.16, 0.5), rot=(0, 0, 45))
    B.to_object()

    # Врата монстров: каменный ромб с тёмным вихрем внутри
    vortex = mat("GateVortex", hexc("5a1a7a"), 0.3, emit=hexc("8a2be2"), emit_strength=1.6)
    B = Builder("SpawnGate")
    B.box(stone_dark, (0, 0, 0.2), (4.2, 1.6, 0.4))
    R = 2.6
    c = (0, 0, 3.0)
    pts = [(0, R), (R, 0), (0, -R), (-R, 0)]
    for k in range(4):
        x0, z0 = pts[k]
        x1, z1 = pts[(k + 1) % 4]
        mid = ((x0 + x1) / 2, 0, c[2] + (z0 + z1) / 2)
        ang = math.degrees(math.atan2(z1 - z0, x1 - x0))
        B.box(stone, mid, (math.hypot(x1 - x0, z1 - z0) + 0.5, 0.6, 0.5), rot=(0, -ang, 0))
    for x0, z0 in pts:
        B.ico(red_cr, (x0, 0, c[2] + z0), 0.35, sub=0)
    B.box(vortex, (0, 0, c[2]), (R * 1.25, 0.12, R * 1.25), rot=(0, 45, 0))
    B.to_object()

    # Курьер-помощник: маленькая снежная сова-дух с шарфом цвета команды и сумкой
    owl = mat("OwlWhite", hexc("f3f6fb"), 0.8)
    owl_grey = mat("OwlGrey", hexc("b9c4d4"), 0.8)
    owl_eye = mat("OwlEye", hexc("ffd23f"), 0.3, emit=hexc("ffb000"), emit_strength=0.6)
    beak_m = mat("OwlBeak", hexc("e0a030"), 0.6)
    satchel = mat("Satchel", hexc("7a4a2a"), 0.8)
    B = Builder("CourierBody")
    B.ico(owl, (0, 0, 0), 0.42, scale=(1.0, 0.95, 1.1), sub=2)
    B.ico(owl_grey, (0, -0.28, -0.04), 0.27, scale=(1.0, 0.45, 1.1), sub=1)
    B.ico(owl, (0, -0.04, 0.5), 0.34, sub=2)
    for sx in (1, -1):
        B.cyl(owl_grey, (sx * 0.19, -0.02, 0.8), 0.075, 0.0, 0.2, seg=5, rot=(0, sx * 22, 0))
        B.ico(owl_eye, (sx * 0.13, -0.29, 0.54), 0.09, sub=1)
        B.ico(coal, (sx * 0.13, -0.36, 0.54), 0.045, sub=0)
        B.ico(beak_m, (sx * 0.12, -0.12, -0.45), 0.07, sub=0)
    B.cyl(beak_m, (0, -0.37, 0.43), 0.055, 0.0, 0.13, seg=4, rot=(90, 0, 0))
    B.cyl(team, (0, -0.02, 0.27), 0.37, 0.37, 0.11, seg=12)
    B.box(team, (0.2, 0.28, 0.1), (0.1, 0.05, 0.32), rot=(0, 12, 0))
    B.box(satchel, (0.33, 0.06, -0.08), (0.16, 0.24, 0.22))
    B.box(satchel, (0.0, 0.0, 0.12), (0.7, 0.05, 0.04), rot=(0, 38, 0))
    B.box(gold, (0.41, 0.06, -0.06), (0.02, 0.08, 0.06))
    B.to_object()
    B = Builder("CourierWing")  # правое крыло: корень в начале координат, вдоль +X
    B.ico(owl, (0.33, 0, 0), 0.36, scale=(1.0, 0.22, 0.5), sub=1)
    B.ico(owl_grey, (0.6, 0.02, -0.06), 0.2, scale=(1.0, 0.2, 0.55), sub=1)
    B.to_object()

    # Флаг команды
    B = Builder("Banner")
    B.cyl(wood, (0, 0, 2.0), 0.07, 0.06, 4.0, seg=6)
    B.box(wood, (0.55, 0, 3.85), (1.2, 0.08, 0.08))
    B.box(team, (0.55, 0, 3.0), (1.0, 0.04, 1.6))
    B.cyl(gold, (0, 0, 4.1), 0.1, 0.0, 0.25, seg=6)
    B.to_object()

    export("props.glb", animations=False)


def export(fname, animations=True):
    path = os.path.join(OUT, fname)
    kw = dict(filepath=path, export_format="GLB", export_yup=True, export_apply=False)
    if animations:
        kw.update(export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
                  export_def_bones=False)
    else:
        kw.update(export_animations=False)
    bpy.ops.export_scene.gltf(**kw)
    print("EXPORTED", path)


if __name__ == "__main__":
    build_swordsman()
    build_sorceress()
    build_assassin()
    build_imp()
    build_boss()
    build_props()
    print("ALL DONE")
