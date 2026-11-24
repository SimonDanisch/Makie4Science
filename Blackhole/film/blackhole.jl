# A schematic black hole in 3D: the horizon (a black ball), the accretion disk
# (a flat, glowing, swirling ring of gas), the photon ring (a thin bright circle
# around the shadow, facing the viewer) and a sky of stars. Not a simulation of
# bent light: a labelled picture of the parts.

"""Points on a flat ring from `rin` to `rout`, with their radius and angle, and the faces between them."""
function disk_mesh(rin, rout; nr = 40, nθ = 240)
    rs = exp.(range(log(rin), log(rout); length = nr))
    θs = range(0, 2π; length = nθ + 1)
    P = [Point3f(r * cos(θ), r * sin(θ), 0) for θ in θs for r in rs]
    R = [Float32(r) for θ in θs for r in rs]
    Θ = [Float32(θ) for θ in θs for r in rs]
    F = GLTriangleFace[]
    for j in 1:nθ, i in 1:nr-1
        a = (j - 1) * nr + i
        push!(F, GLTriangleFace(a, a + 1, a + nr + 1), GLTriangleFace(a, a + nr + 1, a + nr))
    end
    return GeometryBasics.Mesh(P, F; normal = fill(Vec3f(0, 0, 1), length(P))), R, Θ
end

"""
The disk's colours at `phase`: hottest inside, swirling streaks that wind as
they orbit, brighter on the side moving towards us (`towards`, radians).
"""
function disk_colours(R, Θ, rin, phase; towards = -π / 2, gain = 1f0)
    map(R, Θ) do r, θ
        heat = (rin / r)^1.3f0
        streak = 0.75f0 + 0.25f0 * sin(5θ - 7f0 * log(r) + phase / sqrt(r))
        beam = 1 + 0.45f0 * cos(θ - towards)
        HOT[clamp(gain * heat * streak * beam, 0f0, 1f0)]
    end
end

"""Random faint stars on a sphere of radius `r` around the origin."""
function starfield(n = 600; r = 80f0, seed = 3)
    s = Random.Xoshiro(seed)
    return [Point3f(r .* normalize(randn(s, Vec3f))) for _ in 1:n]
end

"""
    blackhole!(scene, cue_t; mass, spin, at) -> NamedTuple

A black hole of horizon radius `mass` at `at`, its disk orbiting at a rate set
by `spin`, in `scene`; `cue_t` is an Observable of time in seconds. Returns
points to label: the horizon's edge, the disk, the photon ring radius.
"""
function blackhole!(scene, t::Observable; mass = 1f0, spin = 1f0, at = Vec3f(0), towards = -π / 2, gain = 1f0, visible = true)
    rin, rout = 2.4f0 * mass, 7.5f0 * mass
    m, R, Θ = disk_mesh(rin, rout)
    disk = mesh!(scene, m; color = lift(s -> disk_colours(R, Θ, rin, 2.5f0 * spin * s; towards, gain), t), shading = NoShading, visible)
    translate!(disk, at)
    # nearly black, but shaded, so its round edge can be seen against the gap in the disk
    hole = mesh!(scene, Sphere(Point3f(at), mass); color = RGBf(0.05, 0.05, 0.07), visible)
    return (; disk, hole, rin, rout, ring = 2.6f0 * mass, at = Point3f(at))
end

"""A circle of radius `r` around `c`, facing the camera at `eye`: the photon ring as seen from there."""
function facing_circle(c, r, eye; n = 128)
    d = normalize(Vec3f(eye) - Vec3f(c))
    a = normalize(abs(d[3]) < 0.9f0 ? cross(d, Vec3f(0, 0, 1)) : cross(d, Vec3f(1, 0, 0)))
    b = cross(d, a)
    return [Point3f(c) + r * (cos(φ) * a + sin(φ) * b) for φ in range(0, 2π; length = n)]
end

"""
    ring_on_top!(ov, scene, centre, r, eye; color, linewidth, linestyle)

A circle facing the camera, drawn in the overlay from its projection so the
disk cannot hide half of it (the photon ring is light that comes towards us).
"""
function ring_on_top!(ov, scene, centre, r, eye::Observable; color, linewidth = 4, linestyle = :solid)
    pts = lift((e, _...) -> [screen_position(scene, p) for p in facing_circle(centre, r, e)], eye,
               scene.camera.projectionview, Makie.viewport(scene))
    lines!(ov, pts; color, linewidth, linestyle)
    return ov
end
