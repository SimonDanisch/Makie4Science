# Optical systems in the meridional plane: the same description drives the wave
# simulation (index_at / metal_at), the ray tracer and the 3D models.
#
# The optical axis is x, light travels towards +x. Lengths are in design
# wavelengths (see wave.jl) unless a scene says otherwise.


# ── glass ────────────────────────────────────────────────────────────────────

"""
    Glass(nd, Vd)

A glass by its index at the helium d line (587.6 nm) and Abbe number, with the
dispersion of a two-term Cauchy formula fitted to them.
"""
struct Glass
    nd::Float32
    Vd::Float32
end

# Cauchy n(λ) = A + B/λ², λ in µm, through nd and nF - nC = (nd - 1)/Vd
function refractive_index(g::Glass, λµm::Real)
    B = (g.nd - 1f0) / g.Vd / (1f0 / 0.4861f0^2 - 1f0 / 0.6563f0^2)
    A = g.nd - B / 0.5876f0^2
    return A + B / Float32(λµm)^2
end

const BK7 = Glass(1.5168f0, 64.17f0)
const SK16 = Glass(1.6204f0, 60.32f0)
const F2 = Glass(1.6200f0, 36.37f0)
const SF2 = Glass(1.6477f0, 33.85f0)

# ── surfaces and elements ────────────────────────────────────────────────────

"""
    Surface(x, R)

A spherical surface with its vertex on the axis at `x` and radius `R`: positive
when the centre of curvature lies to the right (+x), `Inf` when flat.
"""
struct Surface
    x::Float32
    R::Float32
end

@inline sag(s::Surface, y) = isinf(s.R) ? 0f0 : s.R - sign(s.R) * sqrt(max(s.R^2 - y^2, 0f0))
@inline surface_x(s::Surface, y) = s.x + sag(s, y)

"""
    Element(front, back, a, glass)

Glass between two surfaces, `a` its semi-diameter (the rim).
"""
struct Element
    front::Surface
    back::Surface
    a::Float32
    glass::Glass
end

"""An element from a vertex position, two radii and the centre thickness."""
Element(x, R1, R2, t, a, glass) = Element(Surface(x, R1), Surface(x + t, R2), Float32(a), glass)

inside(e::Element, p) = abs(p[2]) <= e.a && surface_x(e.front, p[2]) <= p[1] <= surface_x(e.back, p[2])

"""An axis-aligned metal part in the slice: a lens cell, a blade, a tube wall."""
struct Metal
    rect::Rect2f
end
Metal(xlo, ylo, xhi, yhi) = Metal(Rect2f(xlo, ylo, xhi - xlo, yhi - ylo))
inside(m::Metal, p) = p in m.rect

@inline smoothstep(a, b, x) = (t = clamp((x - a) / (b - a), 0f0, 1f0); t * t * (3f0 - 2f0 * t))

"""
Something that swallows light: `damping(a, p)` is its damping (per period) at
`p`, zero outside it.
"""
abstract type Absorber end

"""
    Black(xlo, ylo, xhi, yhi; σ, ramp)

A blackened region. The damping rises from 0 at the boundary to `σ` (per
period) at depth `ramp`, quadratically: a sudden step reflects like a mirror,
a ramp over a few wavelengths swallows the wave.
"""
struct Black <: Absorber
    rect::Rect2f
    σ::Float32
    ramp::Float32
end
Black(xlo, ylo, xhi, yhi; σ = 3f0, ramp = 3f0) =
    Black(Rect2f(xlo, ylo, xhi - xlo, yhi - ylo), Float32(σ), Float32(ramp))

function damping(b::Black, p)
    p in b.rect || return 0f0
    lo, hi = minimum(b.rect), maximum(b.rect)
    d = min(p[1] - lo[1], hi[1] - p[1], p[2] - lo[2], hi[2] - p[2])
    return b.σ * clamp(d / b.ramp, 0f0, 1f0)^2
end

"""
    Apodizer(x0, x1, r0, r1; σ)

A soft edge for an aperture: a plate between `x0..x1` that lets light through
freely up to `|y| = r0` and dims it smoothly to almost nothing at `r1`. The
damping also rises smoothly into the plate from both faces, so it does not
reflect.
"""
struct Apodizer <: Absorber
    x0::Float32
    x1::Float32
    r0::Float32
    r1::Float32
    σ::Float32
end
Apodizer(x0, x1, r0, r1; σ = 2f0) = Apodizer(Float32(x0), Float32(x1), Float32(r0), Float32(r1), Float32(σ))

function damping(a::Apodizer, p)
    a.x0 <= p[1] <= a.x1 || return 0f0
    mid, half = (a.x0 + a.x1) / 2, (a.x1 - a.x0) / 2
    across = 1f0 - smoothstep(0f0, half, abs(p[1] - mid))   # 1 in the middle of the plate, 0 at its faces
    return a.σ * smoothstep(a.r0, a.r1, abs(p[2])) * smoothstep(0f0, 0.5f0, across)
end

"""
    Part(x0, x1, r0, r1; name, look, inner, sim, σ, ramp)

A ring (or disc, r0 = 0) of the mechanics between `x0..x1` and radii `r0..r1`.
`name` is what the part is (`:tube`, `:sensor`): its 3D model is named after it,
which is how an editor lists it. `look` names its 3D material in `MAT`
(`nothing`: not drawn), `sim` what it is to the wave: `:metal` reflects,
`:black` absorbs (damping `σ` reached `ramp` wavelengths in), `:none` is not
simulated. `inner` optionally names a different material for the bore (a white
tube, black inside).
"""
Base.@kwdef struct Part
    name::Symbol = :part
    x0::Float32
    x1::Float32
    r0::Float32
    r1::Float32
    look::Union{Symbol,Nothing} = :anodized
    inner::Union{Symbol,Nothing} = nothing
    sim::Symbol = :metal
    σ::Float32 = 3f0
    ramp::Float32 = 2f0
end
Part(x0, x1, r0, r1; kw...) = Part(; x0, x1, r0, r1, kw...)

"""
Where a part cuts the slice, as y ranges: a ring twice (above and below the
axis), a disc once across it, so an absorber's ramp does not open up on the axis.
"""
slice_spans(p::Part) = iszero(p.r0) ? ((-p.r1, p.r1),) : ((p.r0, p.r1), (-p.r1, -p.r0))

"""
    System(elements, metal, absorbers; λµm, sensor, coating)

An optical system. `λµm` is the real wavelength the design colour stands for,
used for dispersion only. `sensor` is the x of the image plane. `coating` (in
wavelengths) grades the index across every glass surface: 0 is a bare surface
reflecting ~4 %, a ramp of a wavelength or more reflects almost nothing (the
simulated stand-in for an anti-reflection coating).
"""
Base.@kwdef struct System
    elements::Vector{Element} = Element[]
    metal::Vector{Metal} = Metal[]
    absorbers::Vector{Absorber} = Absorber[]
    λµm::Float32 = 0.55f0
    sensor::Float32 = 0f0
    coating::Float32 = 0f0
end

"""
How much of `e`'s glass is at `p`, 0..1: a step at its surfaces, or a ramp
`w` wide centred on them. Measured along x, which is close to the normal for
the gently curved surfaces here. Symmetric, so across a cemented surface the
two elements' fractions add up to one.
"""
function glass_fraction(e::Element, p, w)
    abs(p[2]) > e.a && return 0f0
    d = min(p[1] - surface_x(e.front, p[2]), surface_x(e.back, p[2]) - p[1])
    return iszero(w) ? Float32(d >= 0) : smoothstep(-w / 2, w / 2, d)
end

function index_at(s::System, p, λ)
    n = 1f0
    for e in s.elements
        n += glass_fraction(e, p, s.coating) * (refractive_index(e.glass, s.λµm * λ) - 1f0)
    end
    return n
end
metal_at(s::System, p) = any(m -> inside(m, p), s.metal)
absorb_at(s::System, p) = sum(a -> damping(a, p), s.absorbers; init = 0f0)

# ── meridional ray tracing ───────────────────────────────────────────────────

struct Ray2
    o::Point2f
    d::Vec2f
end

"""Where the ray meets the surface (nearest to the vertex), or `nothing`."""
function intersect(r::Ray2, s::Surface)
    if isinf(s.R)
        abs(r.d[1]) < 1f-9 && return nothing
        t = (s.x - r.o[1]) / r.d[1]
        return t > 0 ? t : nothing
    end
    c = Point2f(s.x + s.R, 0)
    oc = r.o - c
    b = dot(oc, r.d)
    disc = b^2 - (dot(oc, oc) - s.R^2)
    disc < 0 && return nothing
    q = sqrt(disc)
    # the vertex side of the sphere: for R > 0 the left half, the smaller x
    t1, t2 = -b - q, -b + q
    x1 = r.o[1] + t1 * r.d[1]
    x2 = r.o[1] + t2 * r.d[1]
    t = abs(x1 - s.x) < abs(x2 - s.x) ? t1 : t2
    return t > 1f-6 ? t : nothing
end

function normal(s::Surface, p)
    isinf(s.R) && return Vec2f(-1, 0)
    n = normalize(Vec2f(p - Point2f(s.x + s.R, 0)))
    return s.R > 0 ? n : -n     # pointing back towards -x
end

"""Refract direction `d` at normal `n` (facing the incoming side), index n1 → n2."""
function refract(d::V, n::V, n1, n2) where {V<:Vec}
    n = dot(d, n) > 0 ? -n : n
    η = n1 / n2
    c = -dot(d, n)
    k = 1 - η^2 * (1 - c^2)
    k < 0 && return nothing
    return normalize(η * d + (η * c - sqrt(k)) * n)
end

"""
    trace(system, ray; λ = 1) -> Vector{Point2f}

Sequential trace through every element in order, ending on the sensor plane.
Returns the path; a ray blocked by a rim, metal or total reflection ends where
it stopped.
"""
function trace(sys::System, r::Ray2; λ = 1f0)
    path = [r.o]
    n1 = 1f0
    for (surf, n2, a) in interfaces(sys, λ)
        t = intersect(r, surf)
        t === nothing && return path
        p = r.o + t * r.d
        blocked = segment_hits_metal(sys, r.o, p)
        if blocked !== nothing
            push!(path, blocked)
            return path
        end
        push!(path, p)
        abs(p[2]) > a && return path
        d = refract(r.d, normal(surf, p), n1, n2)
        d === nothing && return path
        r = Ray2(p, d)
        n1 = n2
    end
    t = (sys.sensor - r.o[1]) / r.d[1]
    p = r.o + t * r.d
    blocked = segment_hits_metal(sys, r.o, p)
    push!(path, blocked === nothing ? p : blocked)
    return path
end

"""
The refracting interfaces in order, as (surface, index after it, rim). A
cemented pair (one element's back is the next one's front) is one interface
from the first glass straight into the second.
"""
function interfaces(sys::System, λ)
    out = Tuple{Surface,Float32,Float32}[]
    for e in sys.elements
        ng = refractive_index(e.glass, sys.λµm * λ)
        if !isempty(out) && out[end][1] == e.front
            out[end] = (e.front, ng, min(out[end][3], e.a))
        else
            push!(out, (e.front, ng, e.a))
        end
        push!(out, (e.back, 1f0, e.a))
    end
    return out
end

"""First point where the segment a→b enters a metal part, or `nothing`."""
function segment_hits_metal(sys::System, a, b)
    best = nothing
    bt = Inf32
    for m in sys.metal
        t = segment_rect(a, b, m.rect)
        if t !== nothing && t < bt
            bt = t
            best = a + t * (b - a)
        end
    end
    return best
end

# slab test, entry parameter in [0, 1]
function segment_rect(a, b, r::Rect2f)
    d = b - a
    lo, hi = minimum(r), maximum(r)
    t0, t1 = 0f0, 1f0
    for k in 1:2
        if abs(d[k]) < 1f-12
            (a[k] < lo[k] || a[k] > hi[k]) && return nothing
        else
            ta = (lo[k] - a[k]) / d[k]
            tb = (hi[k] - a[k]) / d[k]
            ta, tb = minmax(ta, tb)
            t0 = max(t0, ta)
            t1 = min(t1, tb)
            t0 > t1 && return nothing
        end
    end
    return t0
end

"""A fan of parallel rays at angle `θ` filling heights `-a..a`, starting at `x0`."""
function fan(x0, a, θ, n)
    d = Vec2f(cos(θ), sin(θ))
    return [Ray2(Point2f(x0, y), d) for y in range(-a, a; length = n)]
end

"""
Paraxial focus: where a ray at height `y` crosses the axis after the last
element, for small `y`. Returns (back focal x, effective focal length).
"""
function paraxial_focus(sys::System; y = 1f-2, λ = 1f0)
    x0 = minimum(e -> e.front.x, sys.elements) - 1
    p = trace(System(; elements = sys.elements, λµm = sys.λµm, sensor = 1f6), Ray2(Point2f(x0, y), Vec2f(1, 0)); λ)
    a, b = p[end-1], p[end]
    d = b - a
    t = -a[2] / d[2]
    xf = a[1] + t * d[1]
    # EFL from the exit angle
    efl = -y / (d[2] / norm(d)) * cos(atan(d[2], d[1]))
    return xf, efl
end
