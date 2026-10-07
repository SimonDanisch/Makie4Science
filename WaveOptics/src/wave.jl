# Light as a scalar wave in a 2D slice through the optics, on the GPU.
#
# The field u(x, y, t) obeys
#     ∂²u/∂t² = (c/n)² ∇²u − σ ∂u/∂t
# with n the refractive index (glass) and σ a damping that is zero everywhere
# except in the absorbing border and on blackened surfaces. Metal (lens cells,
# aperture blades) holds u = 0, so it reflects.
#
# Units: lengths in vacuum wavelengths of the design colour, time in its
# periods, so c = 1. A colour of wavelength λ (in those units) has frequency
# 1/λ. Leapfrog in time, five-point Laplacian in space.


"""
    Grid(origin, h, dims)

Cell `(i, j)` is centred at `origin + h * (i - 1, j - 1)`. `h` in wavelengths.
"""
struct Grid
    origin::Point2f
    h::Float32
    dims::NTuple{2,Int}
end

"""Grid covering `lo`..`hi` with `ppw` cells per wavelength."""
function Grid(lo::Point2f, hi::Point2f, ppw::Real)
    h = 1f0 / Float32(ppw)
    dims = Tuple(ceil.(Int, (hi .- lo) ./ h) .+ 1)
    return Grid(lo, h, dims)
end

Base.size(g::Grid) = g.dims
@inline cellcenter(g::Grid, i, j) = g.origin + g.h * Vec2f(i - 1, j - 1)
xs(g::Grid) = g.origin[1] .+ g.h .* (0:g.dims[1]-1)
ys(g::Grid) = g.origin[2] .+ g.h .* (0:g.dims[2]-1)
cellindex(g::Grid, p) = (round(Int, (p[1] - g.origin[1]) / g.h) + 1, round(Int, (p[2] - g.origin[2]) / g.h) + 1)
bounds(g::Grid) = Rect2f(g.origin .- g.h / 2, g.h .* Vec2f(g.dims))

# ── materials ────────────────────────────────────────────────────────────────

"""
Per-cell medium, as the solver consumes it: `coef = (dt / (h n))²`, and
`damp = σ dt / 2`, or -1 for metal.
"""
struct Medium{A}
    coef::A
    damp::A
end

"""
    Sponge(width, σmax)

Absorbing border of `width` wavelengths on every side of the grid, with damping
rising quadratically to `σmax` (per period) at the edge.
"""
struct Sponge
    width::Float32
    σmax::Float32
end
Sponge(; width = 12f0, σmax = 3f0) = Sponge(width, σmax)

function sponge_σ(s::Sponge, g::Grid, p::Point2f)
    b = bounds(g)
    lo, hi = minimum(b), maximum(b)
    d = min(p[1] - lo[1], hi[1] - p[1], p[2] - lo[2], hi[2] - p[2])
    d >= s.width && return 0f0
    return s.σmax * (1f0 - max(d, 0f0) / s.width)^2
end

"""
    rasterize(g, scene, λ; sponge, courant, ss) -> (index, metal, σ, dt)

Evaluate `scene` (anything with `index_at(scene, p, λ)`, `metal_at`, `absorb_at`)
on the grid. The index is averaged over `ss × ss` subsamples per cell, so a
curved glass surface does not become a staircase.
"""
function rasterize(g::Grid, scene, λ::Real; sponge = Sponge(), courant = 0.5f0, ss = 4)
    nx, ny = size(g)
    index = Matrix{Float32}(undef, nx, ny)
    metal = falses(nx, ny)
    σ = Matrix{Float32}(undef, nx, ny)
    offs = [(k - 0.5f0) / ss - 0.5f0 for k in 1:ss]
    Threads.@threads for j in 1:ny
        for i in 1:nx
            c = cellcenter(g, i, j)
            acc = 0f0
            nm = 0
            for oy in offs, ox in offs
                p = c + g.h * Vec2f(ox, oy)
                acc += index_at(scene, p, λ)
                nm += metal_at(scene, p)
            end
            index[i, j] = acc / ss^2
            metal[i, j] = 2nm > ss^2
            σ[i, j] = sponge_σ(sponge, g, c) + absorb_at(scene, c)
        end
    end
    dt = Float32(courant) * g.h
    return index, metal, σ, dt
end

function Medium(backend, g::Grid, index, metal, σ, dt)
    coef = @. (dt / (g.h * index))^2
    damp = @. ifelse(metal, -1f0, σ * dt / 2)
    return Medium(KA.adapt(backend, coef), KA.adapt(backend, damp))
end

# ── sources ──────────────────────────────────────────────────────────────────

"""
    PlaneWave(θ, amp, λ)

A plane wave travelling at angle `θ` (radians) to +x, of wavelength `λ` (in
design wavelengths), injected along the column `x = xsrc` of the simulation.
"""
struct PlaneWave
    θ::Float32
    amp::Float32
    λ::Float32
end
PlaneWave(θ; amp = 1f0, λ = 1f0) = PlaneWave(Float32(θ), Float32(amp), Float32(λ))

"""Smooth switch-on over `rise` periods starting at `t0`: a continuous wave."""
struct Continuous
    t0::Float32
    rise::Float32
end
Continuous(; t0 = 0f0, rise = 6f0) = Continuous(t0, rise)

"""A wave packet: Gaussian envelope of width `τ` periods centred at `tc`."""
struct Pulse
    tc::Float32
    τ::Float32
end

@inline function envelope(e::Continuous, t)
    s = clamp((t - e.t0) / e.rise, 0f0, 1f0)
    return s * s * (3f0 - 2f0 * s)
end
@inline envelope(e::Pulse, t) = exp(-((t - e.tc) / e.τ)^2)

# sin(2πx), reduced to one period first. Not `sinpi`: Lava miscompiles
# `sinpi(::Float32)` (wrong quadrant from the fourth sample of a ramp on).
@inline function sin2π(x::Float32)
    r = x - round(x)
    return sin(2f0 * Float32(π) * r)
end

@inline function drive(w::PlaneWave, env, t, y)
    # phase is constant on lines x cosθ + y sinθ = const; on the source column
    # that makes the delay y sinθ
    τ = t - y * sin(w.θ)
    return w.amp * envelope(env, τ) * sin2π(τ / w.λ)
end

# ── solver ───────────────────────────────────────────────────────────────────

@kernel function leapfrog!(up, @Const(u), @Const(coef), @Const(damp))
    i, j = @index(Global, NTuple)
    nx, ny = size(u)
    @inbounds if 1 < i < nx && 1 < j < ny
        d = damp[i, j]
        if d < 0f0
            up[i, j] = 0f0
        else
            c = u[i, j]
            lap = u[i+1, j] + u[i-1, j] + u[i, j+1] + u[i, j-1] - 4f0 * c
            up[i, j] = (2f0 * c - (1f0 - d) * up[i, j] + coef[i, j] * lap) / (1f0 + d)
        end
    end
end

# A line source launches the time INTEGRAL of what it is fed (half each way),
# so feeding the drive itself would leave a DC step behind every switch-on that
# then rings in the tube. Fed the drive's time difference instead, with the
# 2 dt/h that makes the launched wave's amplitude the drive's.
@kernel function inject!(u, isrc, y0, h, dt, waves, env, t)
    j = @index(Global)
    y = y0 + h * (j - 1)
    s = 0f0
    for w in waves
        s += drive(w, env, t, y) - drive(w, env, t - dt, y)
    end
    @inbounds u[isrc, j] += 2f0 * dt / h * s
end

@kernel function accumulate_dft!(re, im, @Const(u), c, s)
    I = @index(Global, Linear)
    @inbounds v = u[I]
    @inbounds re[I] += c * v
    @inbounds im[I] += s * v
end

"""
    Wave(backend, grid, medium, dt; waves, envelope, xsrc)

The simulation state. `u` holds the field at the current time `t`, `up` the
one a step earlier. `re`/`im` accumulate the field's Fourier component at the
frequency `ν` (the complex amplitude of the steady state).
"""
mutable struct Wave{A,W,E}
    grid::Grid
    medium::Medium{A}
    u::A
    up::A
    re::A
    im::A
    dt::Float32
    t::Float64
    nsteps::Int
    ndft::Int
    ν::Float32
    waves::W
    env::E
    isrc::Int
end

function Wave(backend, g::Grid, m::Medium, dt; waves, envelope, xsrc, ν = 1f0)
    z() = KA.zeros(backend, Float32, size(g)...)
    isrc = cellindex(g, Point2f(xsrc, 0))[1]
    return Wave(g, m, z(), z(), z(), z(), Float32(dt), 0.0, 0, 0, Float32(ν), waves, envelope, isrc)
end

"""
Advance `n` steps; accumulate the Fourier component when `dft` is set. `each(w)`
runs after every step, before the single synchronisation at the end: a
measurement kernel that has to see every step.
"""
function step!(w::Wave, n::Integer = 1; dft = false, each = nothing)
    backend = KA.get_backend(w.u)
    g = w.grid
    lf = leapfrog!(backend)
    inj = inject!(backend)
    acc = accumulate_dft!(backend)
    for _ in 1:n
        lf(w.up, w.u, w.medium.coef, w.medium.damp; ndrange = size(g))
        w.u, w.up = w.up, w.u
        w.t += w.dt
        w.nsteps += 1
        inj(w.u, w.isrc, g.origin[2], g.h, w.dt, w.waves, w.env, Float32(w.t); ndrange = size(g)[2])
        if dft
            ph = 2π * w.ν * w.t
            acc(w.re, w.im, w.u, Float32(cos(ph)), Float32(sin(ph)); ndrange = length(w.u))
            w.ndft += 1
        end
        each === nothing || each(w)
    end
    KA.synchronize(backend)
    return w
end

"""Run until time `t` (periods)."""
run_until!(w::Wave, t; dft = false) = step!(w, max(0, ceil(Int, (t - w.t) / w.dt)); dft)

"""The complex steady-state amplitude, `u ≈ Re(A e^{-2πiνt})`, on the host."""
function amplitude(w::Wave)
    s = 2f0 / max(w.ndft, 1)
    return complex.(Array(w.re) .* s, Array(w.im) .* s)
end

field(w::Wave) = Array(w.u)

"""
    simulate(sys, g; waves, xsrc, tend, tdft, backend) -> (wave, index, metal)

Run a continuous wave through `sys` until `tend`, accumulating the steady-state
amplitude over the last `tdft` periods.
"""
function simulate(sys, g::Grid; waves = (PlaneWave(0f0),), xsrc, tend, tdft = 40, backend)
    index, metal, σ, dt = rasterize(g, sys, 1f0)
    med = Medium(backend, g, index, metal, σ, dt)
    w = Wave(backend, g, med, dt; waves, envelope = Continuous(), xsrc)
    run_until!(w, tend - tdft)
    run_until!(w, tend; dft = true)
    return w, index, metal
end

"""
    energy(w) -> Matrix{Float32}

Local wave energy u² + (∂u/∂t / 2πν)² on the host: for a sinusoid it is the
squared amplitude whatever the phase, so it shows where light is without the
flicker of the oscillation, in a transient as well as in the steady state.
"""
function energy(w::Wave)
    u = Array(w.u)
    up = Array(w.up)
    s = 1f0 / (2f0 * Float32(π) * w.ν * w.dt)
    return @. u^2 + ((u - up) * s)^2
end

# ── a transient simulation that can be asked for any time ────────────────────

@kernel function sensor_ema!(ema, @Const(u), @Const(up), i, s, α)
    j = @index(Global)
    @inbounds begin
        e = u[i, j]^2 + ((u[i, j] - up[i, j]) * s)^2
        ema[j] += α * (e - ema[j])
    end
end

"""
    SeekableWave(make; every, sensor, τ)

A transient simulation that answers for any time, in any order: what a
keyframed simulation clock needs. `make()` returns a fresh `Wave` at t = 0.
Going forward steps the solver; going back restores the latest checkpoint
before the target (one every `every` periods, kept on the host) and steps from
there, so the field at a time is the same whichever way it was reached: always
the same number of steps from the same state.

With a `sensor` x position, it also keeps the light collected along that
column as a running average over `τ` periods of the local energy: what the
pixels of a sensor there would show.
"""
mutable struct SeekableWave{W<:Wave,A}
    make::Any
    wave::W
    ema::A
    sensor::Int
    α::Float32
    every::Int                                   # steps between checkpoints
    checkpoints::Vector{Tuple{Int,Float64,Matrix{Float32},Matrix{Float32},Vector{Float32}}}
end

function SeekableWave(make; every = 10f0, sensor = nothing, τ = 1f0)
    w = make()
    ny = size(w.grid)[2]
    i = sensor === nothing ? 0 : cellindex(w.grid, Point2f(sensor, 0))[1]
    ema = KA.zeros(KA.get_backend(w.u), Float32, ny)
    sw = SeekableWave(make, w, ema, i, Float32(w.dt / τ), max(1, round(Int, every / w.dt)),
                      Tuple{Int,Float64,Matrix{Float32},Matrix{Float32},Vector{Float32}}[])
    checkpoint!(sw)
    return sw
end

function checkpoint!(sw::SeekableWave)
    w = sw.wave
    any(c -> c[1] == w.nsteps, sw.checkpoints) && return sw
    push!(sw.checkpoints, (w.nsteps, w.t, Array(w.u), Array(w.up), Array(sw.ema)))
    sort!(sw.checkpoints; by = first)
    return sw
end

function restore!(sw::SeekableWave, c)
    w = sw.wave
    n, t, u, up, ema = c
    copyto!(w.u, u); copyto!(w.up, up); copyto!(sw.ema, ema)
    w.nsteps = n; w.t = t
    return sw
end

"""
    seek!(sw, t) -> sw

Bring the simulation to time `t` (periods): exactly `ceil(t / dt)` solver steps
from the start, however it gets there.
"""
function seek!(sw::SeekableWave, t::Real)
    w = sw.wave
    target = max(0, ceil(Int, t / w.dt))
    if target < w.nsteps
        k = findlast(c -> c[1] <= target, sw.checkpoints)
        restore!(sw, sw.checkpoints[k])
    end
    backend = KA.get_backend(w.u)
    while w.nsteps < target
        stop = min(target, (w.nsteps ÷ sw.every + 1) * sw.every)
        if sw.sensor == 0
            step!(w, stop - w.nsteps)
        else
            ema! = sensor_ema!(backend)
            s = 1f0 / (2f0 * Float32(π) * w.ν * w.dt)
            step!(w, stop - w.nsteps;
                  each = w -> ema!(sw.ema, w.u, w.up, sw.sensor, s, sw.α; ndrange = length(sw.ema)))
        end
        w.nsteps % sw.every == 0 && checkpoint!(sw)
    end
    return sw
end

"The light collected along the sensor column so far (see `SeekableWave`)."
collected(sw::SeekableWave) = Array(sw.ema)
