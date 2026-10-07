# The camera lens: a Cooke triplet, and the single lens it improves on.
#
# Prescriptions in millimetres, scaled into wavelength units by the shots.

"""
    cooke(; scale) -> Vector{Element}

The classic Cooke triplet (the Zemax "Cooke 40 degree field" sample: SK16 /
F2 / SK16, f ≈ 50 mm, f/5, ±20°), every length times `scale`. Returns the
elements and the stop position (between the flint and the rear crown).
"""
function cooke(; scale = 1f0)
    s = Float32(scale)
    # radius, thickness after the surface, glass after the surface (nothing: air)
    rx = [
        (22.01359f0, 3.25896f0, SK16),
        (-435.7604f0, 6.00755f0, nothing),
        (-22.21328f0, 0.99997f0, F2),
        (20.29192f0, 4.75041f0, nothing),
        (79.68360f0, 2.95208f0, SK16),
        (-18.39533f0, 0f0, nothing),
    ]
    semis = [8.5f0, 8.5f0, 6.5f0, 6.5f0, 8.0f0, 8.0f0]
    elements = Element[]
    x = 0f0
    for k in 1:2:length(rx)
        (R1, t1, glass), (R2, t2, _) = rx[k], rx[k+1]
        push!(elements, Element(Surface(s * x, s * R1), Surface(s * (x + t1), s * R2), s * semis[k], glass))
        x += t1 + t2
    end
    stop = s * (3.25896f0 + 6.00755f0 + 0.99997f0 + 2.0f0)
    return elements, stop
end

"""A single plano-convex lens of focal length `f` (curved side to the object), rim `a`."""
function singlet(f, a; glass = BK7, x0 = 0f0, λµm = 0.55f0)
    n = refractive_index(glass, λµm)
    R = (n - 1f0) * f
    t = a^2 / (2R) + 0.08f0 * a
    return [Element(Surface(x0, R), Surface(x0 + t, Inf32), a, glass)]
end

"""
    spot(sys, θ; D, n, x) -> (points on the image plane, rms radius)

Trace `n` parallel rays at angle `θ` filling the entrance aperture `D` (the
first surface's), and where they land on the plane `x` (default the sensor).
The rms is about their centroid.
"""
function spot(sys::System, θ; D, n = 41, x = sys.sensor, λ = 1f0)
    x0 = sys.elements[1].front.x - 5f0
    # aim the fan so its centre ray passes the first surface's centre
    ys = range(-D / 2, D / 2; length = n)
    hits = Float32[]
    for y in ys
        o = Point2f(x0, y - 5f0 * tan(θ))
        p = trace(System(; elements = sys.elements, λµm = sys.λµm, sensor = x), Ray2(o, Vec2f(cos(θ), sin(θ))); λ)
        abs(p[end][1] - x) < 1f-3 && push!(hits, p[end][2])
    end
    c = sum(hits) / length(hits)
    return hits, sqrt(sum(abs2, hits .- c) / length(hits))
end

"""A camera lens: its optics (elements, the iris as metal), its mechanics, its stop."""
struct CameraLens
    sys::System
    parts::Vector{Part}
    stop::Float32
    D::Float32
end

"""
Height at which the on-axis ray entering at `h` crosses the plane `x`, traced
through `els` (for sizing the iris to a given f-number).
"""
function height_at(els, h, x)
    p = trace(System(; elements = els, sensor = 1f6), Ray2(Point2f(els[1].front.x - 5, h), Vec2f(1, 0)))
    y = crossing(p, x)
    y === nothing && error("ray at h = $h never reaches x = $x")
    return y
end

"""
    cooke_camera(; D) -> CameraLens

The Cooke triplet in a barrel, stopped down so the entrance beam is `D` wide
(f/5 at D = 10), on a camera body with the sensor at best focus. Millimetres.
"""
function cooke_camera(; D = 10f0)
    els, stop = cooke()
    xf = best_focus(els, D)
    iris = abs(height_at(els, D / 2, stop))
    rin, rout = 9f0, 11.5f0
    xl = els[end].back.x
    parts = [
        # barrel with a front ring, spacers between the elements
        Part(-4f0, xl + 4f0, rin, rout; look = :anodized),
        Part(-4f0, -3f0, 8f0, rin; look = :aluminium),
        Part(els[1].back.x + 0.3f0, els[2].front.x - 0.5f0, 8.6f0, rin),
        Part(els[2].back.x + 0.5f0, els[3].front.x - 0.3f0, 8.1f0, rin),
        # the iris at the stop
        Part(stop - 0.15f0, stop + 0.15f0, iris, rin; look = :aluminium),
        # focus ring (rubber grip)
        Part(1f0, 11f0, rout, rout + 1.2f0; look = :rubber),
    ]
    append!(parts, camera_body(xl + 4f0, xf))
    return CameraLens(System(; elements = els, metal = iris_metal(stop, iris, rin), sensor = xf), parts, stop, Float32(D))
end

"""
    singlet_camera(; D, f) -> CameraLens

The simplest camera lens: one plano-convex lens of focal length `f`, the iris
right in front of it cutting the beam to `D`, same body. Millimetres.
"""
function singlet_camera(; D = 10f0, f = 50f0)
    els = singlet(f, 13f0)
    stop = -0.6f0
    xf = best_focus(els, D)
    rin, rout = 13.5f0, 16f0
    xl = els[end].back.x
    parts = [
        Part(-4f0, xl + 4f0, rin, rout; look = :anodized),
        Part(-4f0, -3f0, 12f0, rin; look = :aluminium),
        Part(stop - 0.15f0, stop + 0.15f0, D / 2, rin; look = :aluminium),
        Part(xl + 0.3f0, xl + 4f0, 13.05f0, rin),
    ]
    append!(parts, camera_body(xl + 4f0, xf))
    return CameraLens(System(; elements = els, metal = iris_metal(stop, D / 2, rin), sensor = xf), parts, stop, Float32(D))
end

"""
The image plane with the smallest spot, near the paraxial focus: the rms
averaged over the field `angles` (on axis only by default), found by
golden-section search.
"""
function best_focus(els, D; angles = (0f0,), n = 41)
    xp, _ = paraxial_focus(System(; elements = els))
    blur(x) = sum(θ -> spot(System(; elements = els, sensor = x), θ; D, n)[2], angles) / length(angles)
    return golden_min(blur, xp - 3f0, xp + 0.5f0)
end

"""Minimum of `f` on `a..b` (assumed unimodal) by golden-section search."""
function golden_min(f, a, b; iters = 40)
    r = Float32((sqrt(5) - 1) / 2)
    c, d = b - r * (b - a), a + r * (b - a)
    fc, fd = f(c), f(d)
    for _ in 1:iters
        if fc < fd
            b, d, fd = d, c, fc
            c = b - r * (b - a)
            fc = f(c)
        else
            a, c, fc = c, d, fd
            d = a + r * (b - a)
            fd = f(d)
        end
    end
    return (a + b) / 2
end

"""The iris as the ray tracer and the wave see it: metal above and below the opening."""
iris_metal(stop, r, rin) = [Metal(stop - 0.15f0, r, stop + 0.15f0, rin), Metal(stop - 0.15f0, -rin, stop + 0.15f0, -r)]

"""Mount and camera body from `x0` on, the sensor at `xf`."""
camera_body(x0, xf) = [
    Part(x0, x0 + 2f0, 10f0, 14f0; look = :aluminium),      # mount
    Part(x0 + 2f0, x0 + 3.5f0, 12f0, 22f0),                  # front wall
    Part(x0 + 2f0, xf + 6f0, 20f0, 22f0),                    # walls
    Part(xf + 4f0, xf + 6f0, 0f0, 20f0),                     # back wall
    # full-frame: light from 20° to the side lands 18 mm off the middle
    Part(xf, xf + 0.6f0, 0f0, 19.5f0; look = :sensor),
]

"""
    ray_glow(g, paths, colors; width, gain) -> Matrix{RGBSpectrum}

Ray paths (polylines, as `trace` returns them) as glowing lines `width` wide
on grid `g`, each in its colour.
"""
function ray_glow(g::Grid, paths, colors; width = 0.08f0, gain = 1.2f0)
    img = fill(Hikari.RGBSpectrum(0f0, 0f0, 0f0, 1f0), size(g))
    pad = 3width
    for (path, c) in zip(paths, colors), k in 1:length(path)-1
        a, b = path[k], path[k+1]
        lo = cellindex(g, min.(a, b) .- pad)
        hi = cellindex(g, max.(a, b) .+ pad)
        for j in max(lo[2], 1):min(hi[2], size(g)[2]), i in max(lo[1], 1):min(hi[1], size(g)[1])
            s = gain * exp(-(segment_distance(cellcenter(g, i, j), a, b) / width)^2)
            s < 1f-3 && continue
            img[i, j] += Hikari.RGBSpectrum(s * c[1], s * c[2], s * c[3], 0f0)
        end
    end
    return img
end

"""Height where the path crosses the plane `x`, or `nothing` if it never does."""
function crossing(path, x)
    for k in 1:length(path)-1
        a, b = path[k], path[k+1]
        a[1] <= x <= b[1] && return a[2] + (x - a[1]) / (b[1] - a[1]) * (b[2] - a[2])
    end
    return nothing
end

"""
The height (on the plane `x0`) from which a ray at angle `θ` passes through the
centre of the stop at `stop`: the chief ray. A coarse scan over ±`range` finds
where the crossing height changes sign (rays a rim stops before the stop
plane are skipped), then bisection pins it down.
"""
function chief_height(sys::System, θ, stop, x0; range = 20f0, step = 0.5f0)
    free = System(; elements = sys.elements, sensor = stop + 1f0)   # no iris in the way
    height(y) = crossing(trace(free, Ray2(Point2f(x0, y), Vec2f(cos(θ), sin(θ)))), stop)
    ys = -range:step:range
    hs = height.(ys)
    k = findfirst(i -> hs[i] !== nothing && hs[i+1] !== nothing && hs[i] <= 0 <= hs[i+1], 1:length(ys)-1)
    k === nothing && error("no ray at $(rad2deg(θ))° reaches the stop at x = $stop")
    lo, hi = Float32(ys[k]), Float32(ys[k+1])
    for _ in 1:30
        mid = (lo + hi) / 2
        height(mid) > 0 ? (hi = mid) : (lo = mid)
    end
    return (lo + hi) / 2
end

"""
    ray_fans(sys, angles; D, stop, n, x0, λ) -> (paths, fan index per path)

Fans of `n` parallel rays for each field angle, starting on the plane `x0`,
`D` wide (measured across the beam) and centred on the chief ray through the
middle of the stop, traced to the sensor (rays the iris blocks end on it), in
the colour `λ` (relative to the design wavelength).
"""
function ray_fans(sys::System, angles; D, stop, n = 13, x0 = sys.elements[1].front.x - 12f0, λ = 1f0)
    paths = Vector{Point2f}[]
    fan = Int[]
    for (k, θ) in enumerate(angles)
        yc = chief_height(sys, θ, stop, x0)
        for off in range(-D / 2, D / 2; length = n)
            o = Point2f(x0, yc + off / cos(θ))
            push!(paths, trace(sys, Ray2(o, Vec2f(cos(θ), sin(θ))); λ))
            push!(fan, k)
        end
    end
    return paths, fan
end

"""The first `L` of a polyline's length."""
function truncate_path(path, L)
    out = [path[1]]
    for k in 1:length(path)-1
        a, b = path[k], path[k+1]
        l = norm(b - a)
        if L <= l
            push!(out, a + (L / l) * (b - a))
            return out
        end
        push!(out, b)
        L -= l
    end
    return out
end

"""
    landings(lens, θ; λ, n) -> Vector{Float32}

Where the rays of the fan at field angle `θ` (colour `λ`, relative to the
design wavelength) land on the sensor, in mm, relative to the middle ray of
the fan. Rays stopped on the way are left out.
"""
function landings(lens::CameraLens, θ; λ = 1f0, n = 41)
    paths, _ = ray_fans(lens.sys, (θ,); D = lens.D, stop = lens.stop, n, λ)
    xf = lens.sys.sensor
    ys = [p[end][2] for p in paths if abs(p[end][1] - xf) < 1f-3]
    mid = paths[(n + 1) ÷ 2][end]
    ref = abs(mid[1] - xf) < 1f-3 ? mid[2] : sum(ys) / length(ys)
    return ys .- ref
end
