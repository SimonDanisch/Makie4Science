# A radio telescope, built from parts: a paraboloid reflector with ribs behind
# it, a small subreflector held on four legs, the receiver cabin, the yoke that
# tilts it (elevation) and the pedestal it turns on (azimuth). Shaped after
# ALMA's 12-metre antennas. Lengths in metres; the pedestal stands on z = 0.

"""Rotation about x by `a` (radians)."""
rotx(a) = Mat3f(1, 0, 0, 0, cos(a), sin(a), 0, -sin(a), cos(a))
"""Rotation about z by `a` (radians)."""
rotz(a) = Mat3f(cos(a), sin(a), 0, -sin(a), cos(a), 0, 0, 0, 1)

"""`m` with every vertex moved by `f` and every normal turned by `R` (per-face normals spread to the vertices first)."""
function moved(m::GeometryBasics.Mesh, f, R)
    m = GeometryBasics.expand_faceviews(m)
    ps = [Point3f(f(p)) for p in coordinates(m)]
    ns = [Vec3f(normalize(R * n)) for n in normals(m)]
    return GeometryBasics.Mesh(ps, faces(m); normal = ns)
end

"""A surface of revolution about z: the profile `(r, z)` points turned through `n` steps."""
function lathe(profile; n = 96)
    P = Point3f[]
    for (r, z) in profile, k in 0:n
        θ = 2π * k / n
        push!(P, Point3f(r * cos(θ), r * sin(θ), z))
    end
    m = n + 1
    F = GLTriangleFace[]
    for i in 1:length(profile)-1, k in 1:n
        a = (i - 1) * m + k
        push!(F, GLTriangleFace(a, a + 1, a + m + 1), GLTriangleFace(a, a + m + 1, a + m))
    end
    return GeometryBasics.Mesh(P, F; normal = GeometryBasics.normals(P, F))
end

"""A cylinder (closed) from `a` to `b`, radius `r`."""
function rod(a, b, r; n = 12)
    c = GeometryBasics.Cylinder(Point3f(a), Point3f(b), Float32(r))
    return normal_mesh(Tesselation(c, n))
end

"""A box with corners `lo` and `hi`."""
block(lo, hi) = normal_mesh(Rect3f(Point3f(lo), Vec3f(hi) - Vec3f(lo)))

"""
    dish_parts(; diameter, focal, elevation, azimuth) -> (; reflector, structure, cabin)

The antenna as three meshes (for three materials): the reflecting surface, the
white-painted structure (backing, legs, subreflector, yoke, pedestal), and the
receiver cabin. `elevation` tilts the dish up from the horizon, `azimuth` turns
it about the vertical (radians).
"""
function dish_parts(; diameter = 12f0, focal = 4.8f0, elevation = 0.8f0, azimuth = 0f0)
    R = diameter / 2
    depth(r) = r^2 / (4focal)
    # in the dish's own frame: axis along +z, vertex at the origin
    surface = lathe([(r, depth(r)) for r in range(0.35f0, R; length = 24)])
    back = lathe([(r, depth(r) - 0.18f0 - 0.5f0 * (1 - r / R)) for r in range(0.35f0, R; length = 12)])
    rim = lathe([(R, depth(R)), (R + 0.08f0, depth(R) - 0.05f0), (R + 0.08f0, depth(R) - 0.3f0), (R * 0.98f0, depth(R) - 0.35f0)])
    sub = Point3f(0, 0, focal - 0.25f0)
    legs = [rod(Point3f(0.92f0R * cos(θ), 0.92f0R * sin(θ), depth(0.92f0R)), sub + Point3f(0.25f0 * cos(θ), 0.25f0 * sin(θ), -0.1f0), 0.06f0)
            for θ in (π / 4, 3π / 4, 5π / 4, 7π / 4)]
    subreflector = lathe([(0f0, focal - 0.18f0), (0.38f0, focal - 0.28f0), (0.38f0, focal - 0.33f0), (0f0, focal - 0.3f0)]; n = 48)
    cabin = block((-0.9f0, -0.9f0, -2.2f0), (0.9f0, 0.9f0, -0.25f0))
    dishframe = [surface, back, rim, subreflector, legs..., cabin]
    # placed: tilt about the elevation axle (x, 1.6 m behind the vertex), up on the yoke, turned in azimuth
    axle = 6.2f0
    tilt = rotx(-(π / 2 - elevation))
    turn = rotz(azimuth)
    place(p) = turn * (tilt * (Vec3f(p) + Vec3f(0, 0, 1.6f0)) + Vec3f(0, 0, axle))
    R3 = turn * tilt
    reflector = moved(surface, place, R3)
    structure = [moved(m, place, R3) for m in (back, rim, subreflector, legs...)]
    cabinmesh = moved(cabin, place, R3)
    # yoke arms either side of the axle, the axle itself, and the pedestal (these turn but do not tilt)
    base(p) = turn * Vec3f(p)
    yoke = [moved(block((s * 2.4f0 - 0.35f0, -0.6f0, 3.2f0), (s * 2.4f0 + 0.35f0, 0.6f0, axle + 0.4f0)), base, turn) for s in (-1, 1)]
    beam = moved(block((-2.75f0, -0.7f0, 2.6f0), (2.75f0, 0.7f0, 3.4f0)), base, turn)
    pedestal = lathe([(0f0, 2.6f0), (1.5f0, 2.6f0), (1.7f0, 0.4f0), (2.2f0, 0.3f0), (2.2f0, 0f0)]; n = 64)
    axlerod = moved(rod(Point3f(-2.4f0, 0, 0), Point3f(2.4f0, 0, 0), 0.3f0), p -> base(Vec3f(p) + Vec3f(0, 0, axle)), turn)
    return (; reflector, structure = merge([structure; yoke; beam; pedestal; axlerod]), cabin = cabinmesh)
end
