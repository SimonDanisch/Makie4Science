# Building scenes once: a 3D view with a pixel overlay for labels, and the
# studio. Everything that moves is a plot attribute or an Observable the editor
# keys; nothing is rebuilt per frame.

"""A camera pose: where it is, what it looks at, its vertical field of view."""
struct Pose
    eye::Vec3f
    lookat::Vec3f
    fov::Float32
end
Pose(eye, lookat; fov = 40) = Pose(Vec3f(eye), Vec3f(lookat), Float32(fov))

"""Smooth ease-in-out on 0..1."""
ease(t) = (t = clamp(t, 0f0, 1f0); t * t * (3f0 - 2f0 * t))

Base.:*(s::Real, p::Pose) = Pose(s * p.eye, s * p.lookat, s * p.fov)
Base.:+(a::Pose, b::Pose) = Pose(a.eye + b.eye, a.lookat + b.lookat, a.fov + b.fov)
lerp(a::Pose, b::Pose, t) = (1 - ease(t)) * a + ease(t) * b
lerp(a::Real, b::Real, t) = a + (b - a) * ease(t)

"""
    Keyframes([t1 => v1, t2 => v2, ...])

A value over time: holds the first value before `t1`, the last after the last
key, and eases between consecutive keys. The same motion as editor keys of
kind `:smooth`; used to compute positions that labels are anchored to.
"""
struct Keyframes{T}
    keys::Vector{Pair{Float32,T}}
end
Keyframes(keys::AbstractVector{<:Pair}) = Keyframes([Float32(t) => v for (t, v) in keys])

function (c::Keyframes)(t)
    ks = c.keys
    t <= ks[1].first && return ks[1].second
    for k in 1:length(ks)-1
        (t0, v0), (t1, v1) = ks[k], ks[k+1]
        t <= t1 && return lerp(v0, v1, (t - t0) / (t1 - t0))
    end
    return ks[end].second
end

"""Point a scene's 3D camera at `pose`, `up` the camera's up (world z by default)."""
function look!(scene, pose::Pose; up = Vec3f(0, 0, 1))
    cam = cameracontrols(scene)
    cam.fov[] = pose.fov
    update_cam!(scene, cam, pose.eye, pose.lookat, Vec3f(up))
    return scene
end

"""
    frame3d(pose; size) -> (figure, 3D scene, overlay)

A frame: a figure filled by a 3D scene looking from `pose`, with a pixel-space
scene on top of it for labels and captions.
"""
function frame3d(pose::Pose; size = (1280, 720), lights = [AmbientLight(RGBf(0.01, 0.01, 0.012))])
    fig = Figure(; size, backgroundcolor = :black, figure_padding = 0)
    ls = LScene(fig[1, 1]; show_axis = false, scenekw = (lights = lights, backgroundcolor = :black))
    cam3d!(ls.scene; center = false)
    look!(ls.scene, pose)
    ov = Scene(fig.scene; camera = campixel!, clear = false)
    return fig, ls.scene, ov
end

"""A flat 2D figure with an overlay for captions."""
function flat(; size = (1280, 720), padding = (40, 40, 100, 30))
    fig = Figure(; size, backgroundcolor = :black, figure_padding = padding, fontsize = 22)
    return fig, Scene(fig.scene; camera = campixel!, clear = false)
end

"""
A rectangular softbox, facing down or towards `target`, centred at `c`: an
emitting panel named `name`, so its brightness and placement can be keyed.
"""
function softbox!(scene, c::Point3f, w, d; Le = (6, 6, 6), target = nothing, name = :softbox)
    if target === nothing
        r = Rect3f(c .- Vec3f(w / 2, d / 2, 0), Vec3f(w, d, 0.001))
        return mesh!(scene, r; material = Hikari.MediumInterface(Hikari.Emissive(Le = Le, two_sided = true)), name)
    end
    # Keep the long edge along the instrument as far as possible. A real
    # plane has one emitting face, rather than the sides of a thin box.
    n = normalize(Vec3f(target - c))
    axis = abs(n[1]) < 0.95f0 ? Vec3f(1, 0, 0) : Vec3f(0, 1, 0)
    u = normalize(axis - dot(axis, n) * n)
    v = cross(n, u)
    a, b = Float32(w / 2) * u, Float32(d / 2) * v
    points = Point3f[c - a - b, c + a - b, c + a + b, c - a + b]
    panel = GeometryBasics.Mesh(points, GLTriangleFace[(1, 2, 3), (1, 3, 4)]; normal = fill(n, 4))
    return mesh!(scene, panel; material = Hikari.MediumInterface(Hikari.Emissive(Le = Le, two_sided = false)), name)
end

"""
A softly warm sand-coloured studio, with mostly neutral reflections on glass.
`scale` grows the lights' layout for bigger subjects, centred at `height`.
The floor and the three softboxes are named `studio_floor`, `softbox_key`,
`softbox_fill` and `softbox_side`, and offered to the editor through
`inspector` (see [`Inspector`](@ref)): each with its material, a softbox's being
its light.
"""
function studio!(scene, xmid; floor = -3.5f0, scale = 1f0, height = 0f0, inspector = nothing)
    scene.backgroundcolor[] = RGBf(0.70, 0.66, 0.60)
    # Ray-traced misses are composited against the root figure's background.
    Makie.root(scene).backgroundcolor[] = scene.backgroundcolor[]
    Makie.set_ambient_light!(scene, RGBf(0.40, 0.39, 0.37))
    ground = mesh!(scene, Rect3f(Vec3f(xmid - 200scale, -200scale, floor), Vec3f(400scale, 400scale, 0.01));
                   material = MAT.floor, name = :studio_floor)
    solid!(inspector, "Studio floor", ground)
    centre = Point3f(xmid, 0, height)
    target = centre + Vec3f(0, 0, -0.5f0 * scale)
    # Large neutral panels light the black mechanics and create readable
    # reflections in curved glass. The front panel reaches the objectives.
    keybox = softbox!(scene, centre + scale * Vec3f(-5, -12, 20), 24scale, 5scale; Le = (18, 17, 15.5), target, name = :softbox_key)
    fillbox = softbox!(scene, centre + scale * Vec3f(8, 14, 18), 20scale, 8scale; Le = (12, 12.5, 13), target, name = :softbox_fill)
    sidebox = softbox!(scene, centre + scale * Vec3f(-18, -6, 10), 12scale, 10scale; Le = (12, 12, 12), target, name = :softbox_side)
    solid!(inspector, "Softbox · key", keybox)
    solid!(inspector, "Softbox · fill", fillbox)
    solid!(inspector, "Softbox · side", sidebox)
    return scene
end
