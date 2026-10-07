# Whole instruments as people know them: a camera on a photo tripod and a
# refractor with dew shield, finder, focuser, diagonal and eyepiece on its
# mount and tripod. Millimetres, world z up; both look towards -x.

"""The rotation taking the x axis to `d`, the y axis level where it can be."""
function frame_to(d)
    x = normalize(Vec3f(d))
    a = abs(x[3]) < 0.9f0 ? Vec3f(0, 0, 1) : Vec3f(0, 1, 0)
    y = normalize(cross(a, x))
    return Mat3f(x..., y..., cross(x, y)...)
end

"""A turn by `γ` about the z axis."""
turn_z(γ) = Mat3f(cos(γ), sin(γ), 0, -sin(γ), cos(γ), 0, 0, 0, 1)

"""The mesh rotated by `R`, then shifted by `t`."""
function moved(m::GeometryBasics.Mesh, R, t = Vec3f(0))
    P = [Point3f(R * Vec3f(p) + t) for p in coordinates(m)]
    N = [normalize(R * Vec3f(n)) for n in m.normal]
    return GeometryBasics.Mesh(P, faces(m); normal = N)
end

"""A whole solid of revolution: `prof` turned about the axis from `origin` along `dir`."""
around(prof::Profile, origin, dir) = moved(revolve(prof; φ = (0f0, 2f0 * Float32(π)), caps = false), frame_to(dir), Vec3f(origin))

"""A cylinder of radius `r` from `a` to `b`."""
rod(a, b, r) = around(disc(0f0, norm(Vec3f(b) - Vec3f(a)), Float32(r)), a, Vec3f(b) - Vec3f(a))

"""A ball of radius `r` at `c`."""
ball(c, r) = around(Profile([[Point2f(r * cos(θ), r * sin(θ)) for θ in range(0f0, Float32(π); length = 32)]]), c, Vec3f(1, 0, 0))

"""
    rounded_box(lo, hi, r; taper) -> mesh

A box from `lo` to `hi` with edges rounded to radius `r`. With `taper` < 1 the
top is narrower: x and y shrink towards it, to that fraction at the top.
"""
function rounded_box(lo, hi, r; taper = 1f0, m = 6)
    lo, hi = Vec3f(lo), Vec3f(hi)
    r = Float32(r)
    a, b = lo .+ r, hi .- r
    θs = range(0f0, Float32(π) / 2; length = m)
    ticks(k) = [[lo[k] + r * (1 - cos(θ)) for θ in θs]; [hi[k] - r * (1 - cos(θ)) for θ in reverse(θs)]]
    P, N, F = Point3f[], Vec3f[], GLTriangleFace[]
    for k in 1:3, side in (lo[k], hi[k])
        i, j = mod1(k + 1, 3), mod1(k + 2, 3)
        us, vs = ticks(i), ticks(j)
        base = length(P)
        for v in vs, u in us
            p = Vec3f(ntuple(l -> l == k ? side : l == i ? u : v, 3))
            n = normalize(p - clamp.(p, a, b))
            push!(P, Point3f(clamp.(p, a, b) + r * n))
            push!(N, n)
        end
        nu = length(us)
        for jv in 1:length(vs)-1, iu in 1:nu-1
            c = base + (jv - 1) * nu + iu
            push!(F, GLTriangleFace(c, c + 1, c + nu + 1), GLTriangleFace(c, c + nu + 1, c + nu))
        end
    end
    if taper != 1
        mid = (lo + hi) / 2
        P = map(P) do p
            s = 1f0 - (1f0 - Float32(taper)) * (p[3] - lo[3]) / (hi[3] - lo[3])
            Point3f(mid[1] + s * (p[1] - mid[1]), mid[2] + s * (p[2] - mid[2]), p[3])
        end
    end
    fix_winding!(F, P, N)
    return GeometryBasics.Mesh(P, F; normal = N)
end

"""Glass elements as whole solids along the x axis (cemented ones a hair apart)."""
glass_solids(elements) = [(around(profile(e; gap = k > 1 && elements[k-1].back == e.front ? 0.05f0 : 0f0), Vec3f(0), Vec3f(1, 0, 0)),
                           glass_material(e.glass)) for (k, e) in enumerate(elements)]

"""A tube along x from `x0` to `x1`, radii `r0..r1`, its bore in another material."""
lined(x0, x1, r0, r1, outside, inside) =
    [(revolve(annulus(Float32.((x0, x1, r0, r1))...); φ = (0f0, 2f0 * Float32(π)), caps = false, sweep), mat)
     for (sweep, mat) in ((2:4, outside), (1:1, inside))]

const XAXIS = Vec3f(1, 0, 0)

const ZAXIS = Vec3f(0, 0, 1)

"""A ring along x from `x0` to `x1` between radii `r0` and `r1`."""
ring(x0, x1, r0, r1) = around(annulus(Float32(x0), Float32(x1), Float32(r0), Float32(r1)), Vec3f(0), XAXIS)

const KIT = (
    body = Hikari.CoatedDiffuse(reflectance = (0.035, 0.035, 0.038), roughness = 0.45),
    white = MAT.paint,
    black = MAT.anodized,
    metal = MAT.aluminium,
    satin = MAT.satin_aluminium,
    rubber = MAT.rubber,
    screen = MAT.sensor,
)

# ── the instruments ──────────────────────────────────────────────────────────

"""A circle in the world (mm): an instrument's opening, `r` its radius."""
struct Opening
    centre::Point3f
    axis::Vec3f
    r::Float32
end

"""Meshes (mm, the instrument's own frame) and materials."""
const Parts = Vector{Tuple{GeometryBasics.Mesh,Any}}

"""
The refractor in its own frame: 100 mm opening, f = 1000 mm, light along +x
from the dew shield's front at x = 0, up +z. The eyepiece sits on a diagonal
pointing up; tube rings on a dovetail in the mount's saddle.
"""
function refractor_parts()
    p = Parts()
    objective = achromat(; f = 1000f0, a = 52f0, x0 = 180f0)
    append!(p, glass_solids(objective))
    append!(p, lined(0, 175, 60, 64, KIT.body, KIT.black))                   # dew shield
    push!(p, (ring(-3, 5, 57, 65.5), KIT.body))                              # its lip
    push!(p, (ring(170, 200, 52.5, 61.5), KIT.body))                         # lens cell
    push!(p, (ring(178, 179, 50, 52.6), KIT.black))                          # the opening's edge
    append!(p, lined(195, 880, 55, 57.5, KIT.white, KIT.black))              # tube
    push!(p, (ring(870, 905, 30, 61.5), KIT.body))                           # rear cell
    push!(p, (rounded_box((900, -40, -40), (965, 40, 46), 8), KIT.body))     # focuser
    for s in (-1, 1)                                                         # its knobs
        push!(p, (rod((930, 40s, -18), (930, 78s, -18), 11), KIT.metal))
        push!(p, (rod((930, 78s, -18), (930, 86s, -18), 13), KIT.rubber))
    end
    push!(p, (ring(960, 1030, 24, 28), KIT.satin))                           # draw tube
    push!(p, (rod((1026, 0, 0), (1068, 0, 0), 26), KIT.metal))               # diagonal
    push!(p, (rounded_box((1060, -27, -27), (1118, 27, 27), 9), KIT.body))
    push!(p, (rod((1089, 0, 24), (1089, 0, 60), 22), KIT.metal))             # eyepiece holder
    push!(p, (rod((1089, 0, 60), (1089, 0, 146), 19.5), KIT.body))           # eyepiece
    push!(p, (rod((1089, 0, 86), (1089, 0, 112), 20.8), KIT.rubber))
    push!(p, (around(annulus(0f0, 16f0, 12f0, 18.5f0), (1089, 0, 146), ZAXIS), KIT.rubber))
    # finder scope on top, in two rings on a shoe
    push!(p, (rounded_box((300, -14, 52), (380, 14, 66), 3), KIT.body))
    for x in (316, 352)
        push!(p, (rounded_box((x - 7, -6, 62), (x + 7, 6, 86), 2), KIT.body))
        push!(p, (around(annulus(0f0, 12f0, 18.2f0, 23f0), (x - 6, 0, 104), XAXIS), KIT.body))
    end
    finder = Vec3f(0, 0, 104)
    push!(p, (around(annulus(255f0, 430f0, 15.5f0, 18f0), finder, XAXIS), KIT.white))
    push!(p, (around(annulus(225f0, 262f0, 17f0, 21f0), finder, XAXIS), KIT.body))
    push!(p, (around(profile(Element(Surface(250f0, 60f0), Surface(254f0, -60f0), 16f0, BK7)), finder, XAXIS), glass_material(BK7)))
    push!(p, (around(disc(0f0, 6f0, 15.5f0), finder + Vec3f(262, 0, 0), XAXIS), KIT.black))
    push!(p, (around(disc(0f0, 40f0, 9f0), finder + Vec3f(430, 0, 0), XAXIS), KIT.body))
    push!(p, (around(annulus(0f0, 10f0, 6f0, 11f0), finder + Vec3f(470, 0, 0), XAXIS), KIT.rubber))
    # tube rings, the dovetail, the saddle that clamps it, the altitude pivot
    for x in (410, 640)
        push!(p, (ring(x, x + 22, 57.7, 64), KIT.body))
        push!(p, (rounded_box((x - 2, -16, -80), (x + 24, 16, -60), 4), KIT.body))
    end
    push!(p, (rounded_box((370, -22, -96), (700, 22, -79), 3), KIT.satin))
    push!(p, (rounded_box((440, -34, -118), (630, 34, -95), 5), KIT.body))
    push!(p, (rod((535, 34, -106), (535, 62, -106), 7), KIT.metal))
    push!(p, (rod((535, 62, -106), (535, 72, -106), 13), KIT.rubber))
    push!(p, (rounded_box((495, -30, -150), (575, 30, -114), 6), KIT.body))
    return p, Opening(Point3f(179, 0, 0), XAXIS, 50f0)
end

"""The point of the refractor's own frame its mount turns it about."""
const REFRACTOR_PIVOT = Point3f(535, 0, -140)

"""
The camera in its own frame: the lens mount at x = 0, the lens to -x (a 50 mm
lens whose opening is 25 mm), up +z, the grip on +y.
"""
function camera_parts()
    p = Parts()
    push!(p, (rounded_box((0, -66, -38), (66, 66, 40), 10), KIT.body))                   # body
    push!(p, (rounded_box((-28, 34, -38), (24, 70, 36), 14), KIT.rubber))                # grip
    push!(p, (rounded_box((2, -26, 34), (50, 26, 66), 8; taper = 0.6f0), KIT.body))      # viewfinder hump
    push!(p, (rounded_box((12, -10, 64), (38, 10, 67), 1.2), KIT.metal))                 # hot shoe
    push!(p, (rod((-10, 52, 35), (-10, 52, 42), 6), KIT.metal))                          # shutter button
    push!(p, (rod((36, -45, 39), (36, -45, 47), 11), KIT.body))                          # mode dial
    push!(p, (rod((36, -45, 47), (36, -45, 48), 9.5), KIT.metal))
    push!(p, (rounded_box((65, -50, -28), (68, 38, 26), 2), KIT.screen))                 # rear screen
    push!(p, (ring(-5, 0.5, 26, 31), KIT.metal))                                         # lens mount
    # the lens: barrel, focus ring with ridges, a silver ring, the front
    push!(p, (ring(-82, -4, 24, 32), KIT.body))
    push!(p, (ring(-64, -34, 32, 33.2), KIT.rubber))
    for k in 0:6
        push!(p, (ring(-63 + 4k, -61 + 4k, 33, 34.3), KIT.rubber))
    end
    push!(p, (ring(-28, -26, 31.9, 32.6), KIT.metal))
    push!(p, (ring(-88, -80, 15.5, 32.4), KIT.body))
    append!(p, glass_solids([Element(Surface(-86f0, 30f0), Surface(-80f0, 200f0), 15.6f0, SK16),
                             Element(Surface(-74f0, 60f0), Surface(-68f0, -60f0), 15.6f0, F2)]))
    push!(p, (ring(-58, -57, 12.5, 24), KIT.black))                                      # iris
    push!(p, (ring(-90, -86, 15.6, 17), KIT.black))
    push!(p, (around(disc(0f0, 2f0, 24f0), Vec3f(-46, 0, 0), XAXIS), KIT.black))
    return p, Opening(Point3f(-86, 0, 0), XAXIS, 12.5f0)
end

"""Where the camera sits on its tripod, in its own frame: under the middle of the body."""
const CAMERA_FOOT = Point3f(33, 0, -38)

"""
Three legs from a spider of radius `r0` at height `top` above the floor point
`c`, splayed by `splay` from upright, in sections of `radii` with a lock
between sections and a rubber foot; the first leg at azimuth `turn`.
"""
function tripod_legs!(p::Parts, c, top; splay, r0, radii, turn = 0f0, leg = KIT.satin, lock = KIT.body)
    c = Vec3f(c)
    for k in 0:2
        β = turn + k * 2f0 * Float32(π) / 3
        u = Vec3f(cos(β), sin(β), 0)
        a = c + r0 * u + Vec3f(0, 0, top)
        b = c + (r0 + top * tan(splay)) * u + Vec3f(0, 0, 30)
        dir = normalize(b - a)
        n = length(radii)
        for (i, r) in enumerate(radii)
            p0, p1 = a + (i - 1) / n * (b - a), a + i / n * (b - a)
            push!(p, (rod(p0, p1, r), leg))
            i < n && push!(p, (rod(p1 - 30dir, p1 + 10dir, r + 3), lock))
        end
        push!(p, (rod(b - 10dir, b - 30f0 / dir[3] * dir, radii[end] + 3), KIT.rubber))
    end
    return p
end

"""The parts of `parts` posed into the world: rotated by `R` about `from`, which lands on `to`."""
posed(parts::Parts, R, from, to) = [(moved(m, R, Vec3f(to) - R * Vec3f(from)), mat) for (m, mat) in parts]

posed(o::Opening, R, from, to) = Opening(Point3f(R * (Vec3f(o.centre) - Vec3f(from)) + Vec3f(to)), normalize(R * o.axis), o.r)

"""
The scene of the cold open (mm): the refractor on its alt-az mount and
tripod at the origin, tilted up `α` and looking towards -x (turned `γt`),
and the camera on its photo tripod at `cam` (turned `γc`).
"""
struct Instruments
    parts::Parts
    camera::Opening
    telescope::Opening
    camera_lens::Point3f       # anchors for the labels
    telescope_tube::Point3f
end

function Instruments(; α = deg2rad(32f0), γt = deg2rad(15f0), cam = Point3f(-700, -700, 0), γc = deg2rad(15f0))
    p = Parts()
    # the telescope's tripod, the mount head, its pan handle
    H0 = 1040f0
    tripod_legs!(p, Vec3f(0), H0 - 30; splay = deg2rad(22f0), r0 = 62f0, radii = (17f0, 13f0), turn = deg2rad(60f0))
    push!(p, (rod((0, 0, H0 - 45), (0, 0, H0), 80), KIT.body))
    push!(p, (rod((0, 0, 400), (0, 0, 408), 120), KIT.body))                       # accessory tray
    # the head turns with the telescope about the upright axis
    head = Parts()
    push!(head, (rod((0, 0, H0), (0, 0, H0 + 45), 62), KIT.metal))
    push!(head, (rounded_box((-55, -45, H0 + 40), (55, 45, H0 + 150), 10), KIT.body))
    pivot = Point3f(0, 0, H0 + 150)
    push!(head, (rod((0, -64, pivot[3]), (0, 64, pivot[3]), 34), KIT.body))
    for s in (-1, 1)
        push!(head, (rod((0, 64s, pivot[3]), (0, 72s, pivot[3]), 24), KIT.metal))
    end
    push!(head, (rod((40, 60, H0 + 120), (330, 140, H0 - 60), 7), KIT.metal))
    push!(head, (rod((250, 118, H0 - 10), (345, 144, H0 - 70), 11), KIT.rubber))
    append!(p, posed(head, turn_z(γt), Vec3f(0), Vec3f(0)))
    # the telescope on it
    Rt = turn_z(γt) * Mat3f(cos(α), 0, -sin(α), 0, 1, 0, sin(α), 0, cos(α))
    tel, opening = refractor_parts()
    append!(p, posed(tel, Rt, REFRACTOR_PIVOT, pivot))
    # the camera's tripod: legs, centre column, ball head, plate
    c = Vec3f(cam)
    Hs = 1000f0
    tripod_legs!(p, c, Hs - 20; splay = deg2rad(20f0), r0 = 46f0, radii = (12.5f0, 10.5f0, 8.5f0), leg = KIT.body,
                 lock = KIT.rubber, turn = deg2rad(-30f0))
    push!(p, (rod(c + Vec3f(0, 0, Hs - 40), c + Vec3f(0, 0, Hs), 52), KIT.body))
    push!(p, (rod(c + Vec3f(0, 0, Hs - 300), c + Vec3f(0, 0, Hs + 180), 14), KIT.satin))
    push!(p, (rod(c + Vec3f(0, 0, Hs + 180), c + Vec3f(0, 0, Hs + 200), 28), KIT.body))
    push!(p, (ball(c + Vec3f(0, 0, Hs + 222), 24), KIT.metal))
    push!(p, (rod(c + Vec3f(0, 0, Hs + 236), c + Vec3f(0, 0, Hs + 256), 27), KIT.body))
    push!(p, (rounded_box(c + Vec3f(-32, -26, Hs + 255), c + Vec3f(32, 26, Hs + 265), 3), KIT.satin))
    Rc = turn_z(γc)
    camera, aperture = camera_parts()
    seat = c + Vec3f(0, 0, Hs + 265)
    append!(p, posed(camera, Rc, CAMERA_FOOT, seat))
    return Instruments(p, posed(aperture, Rc, CAMERA_FOOT, seat), posed(opening, Rt, REFRACTOR_PIVOT, pivot),
                       Point3f(Rc * (Vec3f(-45, 0, 34.3) - Vec3f(CAMERA_FOOT)) + seat),
                       Point3f(Rt * (Vec3f(560, 0, 57.5) - Vec3f(REFRACTOR_PIVOT)) + Vec3f(pivot)))
end

# ── the beat ─────────────────────────────────────────────────────────────────

"""World units per millimetre in the cold open."""
const INTRO_S = 0.01f0

"""The top of an opening's rim, as seen from above (world units)."""
rim_top(o::Opening; S = INTRO_S) = S * (Vec3f(o.centre) + o.r * normalize(Vec3f(0, 0, 1) - o.axis[3] * o.axis))
