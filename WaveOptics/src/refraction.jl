# Refraction at a slanted glass face: the steady state of a plane wave through a slab.

"""
    Slab(x0, θ, n, ramp)

Glass of index `n` filling everything behind a flat face through `(x0, 0)`,
tilted `θ` from upright: glass where `(p - (x0, 0)) · (cos θ, -sin θ) > 0`.
The index rises over `ramp` wavelengths, so the face hardly reflects.
"""
struct Slab
    x0::Float32
    θ::Float32
    n::Float32
    ramp::Float32
end

"""How far `p` is inside the glass (negative in the air)."""
depth(s::Slab, p) = (p[1] - s.x0) * cos(s.θ) - p[2] * sin(s.θ)

index_at(s::Slab, p, λ) = 1f0 + (s.n - 1f0) * smoothstep(-s.ramp / 2, s.ramp / 2, depth(s, p))

metal_at(::Slab, p) = false

absorb_at(::Slab, p) = 0f0

"""The direction of light in the glass, for light arriving along +x (Snell's law)."""
function refracted(s::Slab)
    θt = asin(sin(s.θ) / s.n)
    inward = Vec2f(cos(s.θ), -sin(s.θ))
    along = Vec2f(sin(s.θ), cos(s.θ))
    return cos(θt) * inward + sin(θt) * along
end

"""
The wave's phase at `p`, in wavelengths: `x` in the air, carried on along the
refracted direction in the glass (continuous across the face).
"""
function optical_phase(s::Slab, p)
    depth(s, p) <= 0 && return p[1]
    t = refracted(s)
    return s.n * (t[1] * p[1] + t[2] * p[2]) + s.x0 * (1f0 - s.n * t[1])
end

"""
    steady(scene, g; λ, θ, xsrc, tend, tdft) -> (A, I)

The steady state of a plane wave of wavelength `λ` (design wavelengths)
through `scene` (anything `rasterize` takes): complex amplitude and intensity.
"""
function steady(scene, g::Grid; λ = 1f0, θ = 0f0, xsrc = -16f0, tend = 260f0, tdft = 40f0)
    index, metal, σ, dt = rasterize(g, scene, λ)
    w = Wave(device(), g, Medium(device(), g, index, metal, σ, dt), dt; waves = (PlaneWave(θ; λ),),
             envelope = Continuous(), xsrc, ν = 1f0 / λ)
    run_until!(w, tend - tdft * λ)
    run_until!(w, tend; dft = true)
    A = amplitude(w)
    return A, abs2.(A)
end

"""The refraction demo: the slab, its steady state, and the phase offset of `A` against `optical_phase`."""
struct Refraction
    slab::Slab
    g::Grid
    A::Matrix{ComplexF32}
    I::Matrix{Float32}
    offset::Float32
end

"The refraction demo's slab and grid."
refraction_setup() = (Slab(6f0, Float32(π / 4), 1.5f0, 1.5f0), Grid(Point2f(-30, -28), Point2f(52, 28), 12))

"The refraction demo's steady state, simulated on the GPU."
function refraction_field()
    slab, g = refraction_setup()
    return first(steady(slab, g; tend = 150f0, tdft = 30f0))
end

"The refraction demo from its steady-state amplitude `A` (see `refraction_field`)."
function Refraction(A::Matrix{ComplexF32})
    slab, g = refraction_setup()
    i, j = cellindex(g, Point2f(-8, 0))
    offset = mod(angle(A[i, j]) / 2f0 / Float32(π) - optical_phase(slab, cellcenter(g, i, j)), 1f0)
    return Refraction(slab, g, A, abs2.(A), offset)
end

# ── the act's data ───────────────────────────────────────────────────────────
