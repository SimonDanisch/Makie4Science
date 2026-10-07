# Skew rays: the whole bundle through a round lens, not only the cut. The
# meridional tracer (optics.jl) follows the rays in the cut through the axis;
# light from the side also crosses the lens outside that plane and lands
# beside the slice, so only the full bundle shows the shape of the smear.

struct Ray3
    o::Point3f
    d::Vec3f
end

curvature_centre(s::Surface) = Point3f(s.x + s.R, 0, 0)

"""Where the ray meets the surface (on the vertex side), or `nothing`."""
function intersect(r::Ray3, s::Surface)
    if isinf(s.R)
        abs(r.d[1]) < 1f-9 && return nothing
        t = (s.x - r.o[1]) / r.d[1]
        return t > 0 ? t : nothing
    end
    oc = r.o - curvature_centre(s)
    b = dot(oc, r.d)
    disc = b^2 - (dot(oc, oc) - s.R^2)
    disc < 0 && return nothing
    q = sqrt(disc)
    t1, t2 = -b - q, -b + q
    t = abs(r.o[1] + t1 * r.d[1] - s.x) < abs(r.o[1] + t2 * r.d[1] - s.x) ? t1 : t2
    return t > 1f-6 ? t : nothing
end

function normal(s::Surface, p::Point3f)
    isinf(s.R) && return Vec3f(-1, 0, 0)
    n = normalize(Vec3f(p - curvature_centre(s)))
    return s.R > 0 ? n : -n     # pointing back towards -x
end

"""Whether the segment `a`→`b` passes the iris plane `x = stop` inside its opening (true if it does not reach it)."""
function through_iris(a, b, stop, iris)
    (a[1] - stop) * (b[1] - stop) > 0 && return true
    q = a + (stop - a[1]) / (b[1] - a[1]) * (b - a)
    return hypot(q[2], q[3]) <= iris
end

"""
    trace(sys, r::Ray3; λ, stop, iris) -> Point2f or nothing

Where a skew ray lands on the sensor, as (y, z) in the sensor plane, or
`nothing` when a rim, the iris (radius `iris` at `x = stop`) or total
reflection stops it.
"""
function trace(sys::System, r::Ray3; λ = 1f0, stop, iris)
    n1 = 1f0
    for (surf, n2, a) in interfaces(sys, λ)
        t = intersect(r, surf)
        t === nothing && return nothing
        p = r.o + t * r.d
        through_iris(r.o, p, stop, iris) || return nothing
        hypot(p[2], p[3]) > a && return nothing
        d = refract(r.d, normal(surf, p), n1, n2)
        d === nothing && return nothing
        r = Ray3(p, d)
        n1 = n2
    end
    p = r.o + (sys.sensor - r.o[1]) / r.d[1] * r.d
    through_iris(r.o, p, stop, iris) || return nothing
    return Point2f(p[2], p[3])
end

"""
    bundle_spot(lens, θ; λ, n) -> Vector{Point2f}

Light from a distant point `θ` to the side, through the whole round opening:
rays on an `n`×`n` grid across a disc wider than the iris passes, centred on
the chief ray, each carrying the same light. Where those that get through land
on the sensor, (y, z) in mm, relative to their centroid: y away from the
picture's centre, z across.
"""
function bundle_spot(lens::CameraLens, θ; λ = 1f0, n = 301)
    sys = lens.sys
    x0 = sys.elements[1].front.x - 12f0
    yc = chief_height(sys, θ, lens.stop, x0)
    iris = abs(height_at(sys.elements, lens.D / 2, lens.stop))
    d = Vec3f(cos(θ), sin(θ), 0)
    R = 0.8f0 * lens.D
    hits = Point2f[]
    for u in range(-R, R; length = n), v in range(-R, R; length = n)
        u^2 + v^2 <= R^2 || continue
        h = trace(sys, Ray3(Point3f(x0, yc + u / cos(θ), v), d); λ, stop = lens.stop, iris)
        h === nothing || push!(hits, h)
    end
    c = sum(hits) / length(hits)
    return [h - c for h in hits]
end
