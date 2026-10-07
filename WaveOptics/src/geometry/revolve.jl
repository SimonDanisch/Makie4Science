# 3D cutaway models: solids of revolution about the optical axis, cut in half by
# the horizontal plane through the axis. By default the half with z <= 0 is
# built, so the cut face lies in z = 0, where the wave slice is drawn; the top
# half (φ = (0, π)) is what lifts off when a telescope is opened up.
#
# Profiles are drawn in the (x, r) half plane, counter-clockwise, as a list of
# smooth runs: normals are interpolated inside a run and split between runs, so
# a lens surface is smooth and its rim meets it at a crease.


const Profile = Vector{Vector{Point2f}}

"""Outward normals of a counter-clockwise run, one per point."""
function run_normals(run::Vector{Point2f})
    n = length(run)
    out = Vector{Vec2f}(undef, n)
    for k in 1:n
        a = run[max(k - 1, 1)]
        b = run[min(k + 1, n)]
        t = normalize(Vec2f(b - a))
        out[k] = Vec2f(t[2], -t[1])
    end
    return out
end

"""
    revolve(profile; φ = (π, 2π), n = 96, caps = true, sweep) -> GeometryBasics.Mesh

Sweep the runs `sweep` (default all) of `profile` about the x axis over the
angles `φ` (z = r sin φ). Runs on the axis (r = 0) are skipped. With `caps`, the
whole profile polygon closes both cut faces, so a glass element is a closed
solid.
"""
function revolve(profile::Profile; φ = (π, 2π), n = 96, caps = true, sweep = eachindex(profile))
    P = Point3f[]
    N = Vec3f[]
    F = GLTriangleFace[]
    φs = range(φ[1], φ[2]; length = n + 1)
    for run in profile[sweep]
        all(p -> abs(p[2]) < 1f-6, run) && continue
        nr = run_normals(run)
        base = length(P)
        for (p, q) in zip(run, nr), ϕ in φs
            c, s = cos(ϕ), sin(ϕ)
            push!(P, Point3f(p[1], p[2] * c, p[2] * s))
            push!(N, normalize(Vec3f(q[1], q[2] * c, q[2] * s)))
        end
        m = length(φs)
        for k in 1:length(run)-1, l in 1:n
            a = base + (k - 1) * m + l
            b = a + 1
            c = a + m
            d = c + 1
            push!(F, GLTriangleFace(a, c, b), GLTriangleFace(b, c, d))
        end
    end
    fix_winding!(F, P, N)
    if caps
        poly = reduce(vcat, [run[1:end-1] for run in profile])
        tri = cap_triangles(poly)
        # the cut faces lie in z = 0 and face away from the half that is kept
        up = Vec3f(0, 0, -sign(sin((φ[1] + φ[2]) / 2)))
        for ϕ in (φ[1], φ[2])
            c = cos(ϕ)
            base = length(P)
            for p in poly
                push!(P, Point3f(p[1], p[2] * c, 0))
                push!(N, up)
            end
            for t in tri
                f = GLTriangleFace(base + t[1], base + t[2], base + t[3])
                push!(F, f)
            end
            fix_winding!(F, P, N; from = length(F) - length(tri) + 1)
        end
    end
    return GeometryBasics.Mesh(P, F; normal = N)
end

"""Orient every face so its geometric normal agrees with its vertex normals."""
function fix_winding!(F, P, N; from = 1)
    for k in from:length(F)
        f = F[k]
        a, b, c = P[f[1]], P[f[2]], P[f[3]]
        g = cross(b - a, c - a)
        if dot(g, N[f[1]] + N[f[2]] + N[f[3]]) < 0
            F[k] = GLTriangleFace(f[1], f[3], f[2])
        end
    end
    return F
end

"""Ear-clipping triangulation of a simple polygon, as index triples."""
function cap_triangles(poly::Vector{Point2f})
    idx = collect(1:length(poly))
    area = sum(k -> cross2(poly[k], poly[mod1(k + 1, end)]), 1:length(poly)) / 2
    area < 0 && reverse!(idx)
    tris = NTuple{3,Int}[]
    guard = 0
    while length(idx) > 3 && guard < 100_000
        guard += 1
        clipped = false
        for k in 1:length(idx)
            i0, i1, i2 = idx[mod1(k - 1, end)], idx[k], idx[mod1(k + 1, end)]
            a, b, c = poly[i0], poly[i1], poly[i2]
            cross2(b - a, c - b) <= 0 && continue
            any(j -> j ∉ (i0, i1, i2) && intriangle(poly[j], a, b, c), idx) && continue
            push!(tris, (i0, i1, i2))
            deleteat!(idx, k)
            clipped = true
            break
        end
        clipped || break
    end
    length(idx) == 3 && push!(tris, (idx[1], idx[2], idx[3]))
    return tris
end
cross2(a, b) = a[1] * b[2] - a[2] * b[1]
function intriangle(p, a, b, c)
    d1 = cross2(b - a, p - a)
    d2 = cross2(c - b, p - b)
    d3 = cross2(a - c, p - c)
    return d1 >= 0 && d2 >= 0 && d3 >= 0
end

# ── profiles ─────────────────────────────────────────────────────────────────

"""Points along a surface from r0 to r1."""
surface_run(s::Surface, r0, r1; n = 48) = [Point2f(surface_x(s, r), r) for r in range(r0, r1; length = n)]

"""Closed profile of a lens element, from the axis up the back, over the rim, down the front."""
function profile(e::Element; gap = 0f0)
    front = Surface(e.front.x + gap, e.front.R)
    back = e.back
    xb, xf = surface_x(back, e.a), surface_x(front, e.a)
    return Profile([
        [Point2f(front.x, 0), Point2f(back.x, 0)],
        surface_run(back, 0f0, e.a),
        [Point2f(xb, e.a), Point2f(xf, e.a)],
        surface_run(front, e.a, 0f0),
    ])
end

"""An annulus from x0 to x1 between radii r0 < r1, as four runs: inner, back, outer, front."""
annulus(x0, x1, r0, r1) = Profile([
    [Point2f(x0, r0), Point2f(x1, r0)],
    [Point2f(x1, r0), Point2f(x1, r1)],
    [Point2f(x1, r1), Point2f(x0, r1)],
    [Point2f(x0, r1), Point2f(x0, r0)],
])

"""A disc (solid cylinder) from x0 to x1 of radius r."""
disc(x0, x1, r) = Profile([
    [Point2f(x0, 0), Point2f(x1, 0)],
    [Point2f(x1, 0), Point2f(x1, r)],
    [Point2f(x1, r), Point2f(x0, r)],
    [Point2f(x0, r), Point2f(x0, 0)],
])

"""Scale and place a mesh: `S` world units per wavelength, then shift by `o`."""
function place(m::GeometryBasics.Mesh, S, o = Vec3f(0))
    P = [Point3f(S * p + o) for p in coordinates(m)]
    return GeometryBasics.Mesh(P, faces(m); normal = m.normal)
end
