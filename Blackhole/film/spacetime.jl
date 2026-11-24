# Adapted from RayDemo/BlackHole/black_hole.jl, commit d8d3c20.
# Scene/medium recipe only: all ray generation, transport, sampling, HDR and
# reconstruction are RayMakie/Hikari's existing VolPath pipeline.
# SpacetimeMedium - A medium that bends light like a black hole
# ============================================================================

import GRMHDSnapshots

"""
    SpacetimeMedium

A participating medium that simulates gravitational lensing around a black hole.
Light rays are deflected toward the black hole center based on the Schwarzschild metric.

The emission, absorption and velocity fields are a GRMHD snapshot's own cells,
`(φ, θ, r)` as `Hikari.native_radiative_volume` prepares them, sampled where
they are, each cell one `PlasmaCell`: the radial shells are log-uniform from
`log_r0` in steps of `dlog_r`, `theta[r, θ]` holds every cell's colatitude and
`theta_lut` brackets it (see `theta_lookup`), and azimuth is uniform from
`phi0` in steps of `dphi`. Radii are in Schwarzschild radii.
"""
struct SpacetimeMedium{C<:AbstractArray, M<:AbstractMatrix{Float32}, L<:AbstractMatrix{Int32}, G<:Hikari.MajorantGrid} <: Hikari.Medium
    center::Point3f
    schwarzschild_radius::Float32
    lensing_strength::Float32
    bounds::Hikari.Bounds3
    density_bounds::Hikari.Bounds3
    render_to_medium::Mat4f
    medium_to_render::Mat4f
    cells::C
    cells_next::C
    theta::M
    theta_lut::L
    time_mix::Float32
    snapshot_key::UInt64
    next_snapshot_key::UInt64
    grid_res::Vec3{Int}
    log_r0::Float32
    dlog_r::Float32
    phi0::Float32
    dphi::Float32
    emission_scale::Float32
    g::Float32
    deflection_padding::Float32
    max_absorption::Float32
    gas_scale::Float32
    doppler::Float32
    electron_index::Float32
    step_scale::Float32
    # Emission is integrated, not tracked, in steps of this times the radius:
    # the native cells are 0.022 r radially and finer in colatitude.
    quadrature_scale::Float32
    # Majorant per cell over `density_bounds`, in medium space (see
    # `majorant_voxels`). Without one, a single cell holds the global bound.
    majorant_grid::G
end

"""
A native cell's emissivity, absorption and static-frame velocity, padded to one
aligned 32-byte load: a sample reads its eight corners instead of 24 values
spread over three arrays.
"""
const PlasmaCell = Hikari.SVector{8,Float32}

"Every cell of a native plasma state as a `PlasmaCell`."
pack_cells(plasma) = map(plasma.density, plasma.absorption, plasma.velocity) do j, a, v
    PlasmaCell(j, a, v[1], v[2], v[3], 0f0, 0f0, 0f0)
end

"""
    theta_lookup(theta) -> Matrix{Int32}

For every shell, the colatitude bracket at the start of each of `n` equal bins
over [0, π], `n` the smallest power of two that puts no more than one colatitude
of a shell inside a bin: a bracket is one read and a step at most, where a
binary search was seven dependent reads.
"""
function theta_lookup(theta)
    nr, ntheta = size(theta)
    narrowest = minimum(minimum(diff(theta[i, :])) for i in 1:nr)
    narrowest > 0 || throw(ArgumentError("colatitudes must increase along every shell"))
    bins = nextpow(2, ceil(Int, π / narrowest))
    return Int32[clamp(searchsortedlast(view(theta, i, :), (b - 1) * π / bins), 1, ntheta - 1)
                 for i in 1:nr, b in 1:bins]
end

function SpacetimeMedium(
    cells::AbstractArray{PlasmaCell,3};
    cells_next = cells,
    theta::AbstractMatrix{Float32}, theta_lut::AbstractMatrix{Int32} = theta_lookup(theta),
    log_r0::Float32, dlog_r::Float32,
    phi0::Float32 = 0f0, dphi::Float32 = Float32(2π / size(cells, 1)),
    time_mix=0f0, snapshot_key=UInt64(0), next_snapshot_key=UInt64(0),
    max_absorption = maximum(c -> c[2], cells),
    electron_index = 2.5f0,
    center::Point3f = Point3f(0f0, 0f0, 0f0),
    schwarzschild_radius::Float32 = 1f0,
    lensing_strength::Float32 = 1f0,
    emission_scale::Float32 = 1f0,
    g::Float32 = 0f0,
    bounds::Hikari.Bounds3 = Hikari.Bounds3(Point3f(-10f0, -10f0, -10f0), Point3f(10f0, 10f0, 10f0)),
    density_bounds::Hikari.Bounds3 = bounds,
    transform::Mat4f = Mat4f(I),
    deflection_padding::Float32 = 0.05f0,
    gas_scale::Float32 = 1f0, doppler::Float32 = 1f0,
    step_scale::Float32 = 1f0,
    quadrature_scale::Float32 = 0.02f0,
    majorant_grid::Hikari.MajorantGrid = Hikari.MajorantGrid(
        [Float32(max_absorption) * gas_scale + deflection_padding], Vec{3,Int32}(1, 1, 1))
)
    isfinite(step_scale) && step_scale > 0 || throw(ArgumentError("step_scale must be finite and positive"))
    isfinite(quadrature_scale) && quadrature_scale > 0 || throw(ArgumentError("quadrature_scale must be finite and positive"))
    isfinite(time_mix) && 0<=time_mix<=1 || throw(ArgumentError("time_mix must lie in [0,1]"))
    size(cells_next) == size(cells) || throw(DimensionMismatch("plasma states must have identical grids"))
    nphi, ntheta, nr = size(cells)
    min(nphi, ntheta, nr) >= 2 || throw(DimensionMismatch("a native plasma grid needs two cells per axis"))
    size(theta) == (nr, ntheta) || throw(DimensionMismatch("theta must hold a colatitude per shell and cell"))
    size(theta_lut, 1) == nr || throw(DimensionMismatch("theta_lut must bracket every shell"))
    dlog_r > 0 && dphi > 0 || throw(ArgumentError("grid spacings must be positive"))
    inv_transform = inv(transform)

    SpacetimeMedium(
        center, schwarzschild_radius, lensing_strength, bounds, density_bounds,
        inv_transform, transform, cells, cells_next, theta, theta_lut, Float32(time_mix),
        UInt64(snapshot_key), UInt64(next_snapshot_key), Vec3{Int}(nphi, ntheta, nr),
        log_r0, dlog_r, phi0, dphi,
        emission_scale, g, deflection_padding, Float32(max_absorption), gas_scale, doppler,
        Float32(electron_index), step_scale, quadrature_scale, majorant_grid
    )
end

"""
    SpacetimeMedium(plasma; next = plasma, kwargs...)

The medium of a native plasma state from `Hikari.native_radiative_volume`,
interpolated toward `next`. A scene packs each state once, not every frame.
"""
SpacetimeMedium(plasma::NamedTuple; next = plasma, kwargs...) =
    SpacetimeMedium(pack_cells(plasma); cells_next = pack_cells(next), plasma.theta,
                    plasma.log_r0, plasma.dlog_r, plasma.phi0, plasma.dphi, kwargs...)

Hikari.is_emissive(m::SpacetimeMedium) = m.emission_scale > 0f0

# The gas absorbs and emits and never scatters: integrated along each chord,
# its emission has no Monte Carlo noise at all.
@inline Hikari.integrates_emission(::SpacetimeMedium) = true
@inline Hikari.medium_quadrature_step(m::SpacetimeMedium, p::Point3f, d::Vec3f) =
    m.quadrature_scale * max(norm(p - m.center), m.schwarzschild_radius)

# The scene owns immutable snapshot arrays. Keep their existing GPU texture
# slots between frames; only upload when the snapshot pair changes. Scalar
# interpolation updates must not copy unchanged volume data.
function Raycore.update_item(storage::Raycore.MultiTypeSet, old::SpacetimeMedium, new::SpacetimeMedium)
    same=old.snapshot_key!=0 && old.snapshot_key==new.snapshot_key
    nextsame=old.next_snapshot_key!=0 && old.next_snapshot_key==new.next_snapshot_key
    fields=map(fieldnames(typeof(old))) do name
        keep=(same && name in (:cells,:theta,:theta_lut)) || (nextsame && name === :cells_next)
        keep ? getfield(old,name) : Raycore.update_item(storage,getfield(old,name),getfield(new,name))
    end
    typeof(old).name.wrapper(fields...)
end

# GRMHDSnapshots' trilinear stencil (`_sample_stencil`/`_apply_stencil`) on
# the medium's own arrays: linear in r between log-uniform shells, θ bracketed
# on each of the two shells' own colatitude rows, periodic in φ. Every index is
# valid for any input, including NaN; outside the shells every weight is zero.
@inline function theta_bracket(theta, lut, shell::Int, θ::Float32, ntheta::Int)
    bins = size(lut, 2)
    # Float32 throughout: Metal has no doubles.
    j = Int(@inbounds lut[shell, clamp(unsafe_trunc(Int, θ * (Float32(bins) / Float32(π))), 0, bins - 1) + 1])
    # One colatitude at most lies inside a bin; Float32 rounding at a bin's
    # edge can add the next one.
    for _ in 1:2
        j = ifelse(j < ntheta - 1 && (@inbounds theta[shell, j + 1]) <= θ, j + 1, j)
    end
    a = @inbounds theta[shell, j]
    b = @inbounds theta[shell, j + 1]
    return j, clamp((θ - a) / (b - a), 0f0, 1f0)
end

@inline function native_stencil(m::SpacetimeMedium, theta, lut, q::Vec3f)
    nphi, ntheta, nr = m.grid_res[1], m.grid_res[2], m.grid_res[3]
    r = norm(q)
    fr = (log(r) - m.log_r0) / m.dlog_r
    inside = 0f0 <= fr <= Float32(nr - 1)
    i = clamp(unsafe_trunc(Int, floor(fr)), 0, nr - 2) + 1
    r0 = exp(m.log_r0 + Float32(i - 1) * m.dlog_r)
    r1 = exp(m.log_r0 + Float32(i) * m.dlog_r)
    ti = clamp((r - r0) / (r1 - r0), 0f0, 1f0)
    θ = atan(sqrt(q[1]^2 + q[2]^2), q[3])
    fk = (atan(q[2], q[1]) - m.phi0) / m.dphi
    k0 = unsafe_trunc(Int, floor(fk))
    tk = clamp(fk - Float32(k0), 0f0, 1f0)
    k = mod(k0, nphi) + 1
    kp = mod(k0 + 1, nphi) + 1
    ji, tji = theta_bracket(theta, lut, i, θ, ntheta)
    jp, tjp = theta_bracket(theta, lut, i + 1, θ, ntheta)
    # Outside, every weight is zero rather than NaN for a NaN position.
    keep(x) = ifelse(inside, x, 0f0)
    return (; i, ti = keep(ti), k, kp, tk = keep(tk), ji, tji = keep(tji), jp, tjp = keep(tjp), w = keep(1f0))
end

@inline function native_value(st, A)
    face(shell, j, tj) = @inbounds (A[st.k, j, shell] * (1f0 - tj) + A[st.k, j + 1, shell] * tj) * (1f0 - st.tk) +
                                   (A[st.kp, j, shell] * (1f0 - tj) + A[st.kp, j + 1, shell] * tj) * st.tk
    return st.w * (face(st.i, st.ji, st.tji) * (1f0 - st.ti) + face(st.i + 1, st.jp, st.tjp) * st.ti)
end

# The stencil reads unchecked: every array must have the grid's shape. Apart
# from keeping malformed inputs safe, this keeps BoundsError paths out of the
# native shader: Metal otherwise force-inlines the entire shadow transport
# routine because its callees can throw.
@inline native_shape_ok(m::SpacetimeMedium, theta, lut, cells, cells_next) =
    size(theta) == (m.grid_res[3], m.grid_res[2]) && size(lut, 1) == m.grid_res[3] && size(lut, 2) >= 1 &&
    size(cells) == size(cells_next) == (m.grid_res[1], m.grid_res[2], m.grid_res[3])

function Hikari.sample_point(
    medium::SpacetimeMedium,
    media,  # StaticMultiTypeSet for dereferencing TextureRefs
    table::Hikari.RGBToSpectrumTable,
    p::Point3f,
    λ::Hikari.Wavelengths,
    ray_d::Vec3f
)::Hikari.MediumProperties
    p4 = medium.render_to_medium * Vec4f(p[1], p[2], p[3], 1f0)
    p_medium = Point3f(p4[1], p4[2], p4[3])

    r_vec = p_medium - medium.center
    r = norm(r_vec)

    # Fast-light interpolation between actual simulation snapshots. No
    # procedural rotation/shear of the gas, and no CPU-sized blended volume.
    theta = Raycore.deref(media, medium.theta)
    lut = Raycore.deref(media, medium.theta_lut)
    cells = Raycore.deref(media, medium.cells)
    cells_next = Raycore.deref(media, medium.cells_next)
    native_shape_ok(medium, theta, lut, cells, cells_next) ||
        return Hikari.MediumProperties(Hikari.SpectralRadiance(0f0), Hikari.SpectralRadiance(0f0),
                                       Hikari.SpectralRadiance(0f0), medium.g)
    st = native_stencil(medium, theta, lut, Vec3f(r_vec))
    cell = native_value(st, cells)
    if medium.time_mix > 0f0
        cell = (1f0 - medium.time_mix) * cell + medium.time_mix * native_value(st, cells_next)
    end
    d = cell[1]
    alpha0 = cell[2]
    v = Vec3f(cell[3], cell[4], cell[5])
    d*=medium.gas_scale
    alpha0*=medium.gas_scale
    f = max(1f0 - medium.schwarzschild_radius / r, 1f-5)
    radial = r_vec / max(r, 1f-6)
    dr = dot(ray_d, radial)
    local_d = ray_d + (inv(sqrt(f)) - 1f0) * dr * radial
    metric_length = max(norm(local_d), 1f0)
    local_d /= metric_length
    gamma_inv = sqrt(max(1f0 - dot(v, v), 1f-5))
    doppler_shift = gamma_inv / max(1f0 + dot(v, local_d), 1f-4)
    shift = sqrt(f) * exp(medium.doppler * log(max(doppler_shift, 1f-5)))
    # Invariant transfer: j/nu^2 and alpha*nu. Convert the Schwarzschild
    # coordinate-length step to the fluid-frame path length. Power-law
    # frequency dependence is evaluated at nu_emit = nu_observer/g.
    length_factor = sqrt(f) * metric_length
    alpha = max(alpha0 * shift^((medium.electron_index + 2f0)/2f0) * length_factor, 0f0)
    j = medium.emission_scale * d * shift^((medium.electron_index + 3f0)/2f0) * length_factor
    # Hikari/PBRT stores a source function Le, not j itself: emission is
    # accumulated as sigma_a*Le. A tiny floor supports optically thin emission.
    alpha = max(alpha, d > 0f0 ? 1f-6 : 0f0)
    sigma_a = Hikari.SpectralRadiance(alpha)
    sigma_s = Hikari.SpectralRadiance(0f0)
    # 230-GHz intensity is monochromatic. Orange is an explicit false colour,
    # not a claim that this radio-emitting gas has an orange visible spectrum.
    Le = j > 0f0 ? Hikari.uplift_rgb_unbounded(table,
        Hikari.RGBSpectrum(1f0, 0.32f0, 0.055f0) * (j / max(alpha, 1f-20)), λ) :
        Hikari.SpectralRadiance(0f0)

    return Hikari.MediumProperties(sigma_a, sigma_s, Le, medium.g)
end

Hikari.sample_point(m::SpacetimeMedium, media, table::Hikari.RGBToSpectrumTable, p::Point3f, λ::Hikari.Wavelengths) =
    Hikari.sample_point(m, media, table, p, λ, Vec3f(0))

# Outside its bounds the medium has nothing to bend: a ray that left the boundary
# sphere without the crossing registering, at an edge, goes straight to the sky
# rather than stepping outward in chords until the depth budget cuts it off.
@inline Hikari.medium_step_limit(m::SpacetimeMedium, p::Point3f, d::Vec3f) =
    m.lensing_strength <= 0f0 || !Raycore.inside(m.bounds, p) ? Inf32 :
        m.step_scale * clamp(0.15f0 * (norm(p - m.center) - m.schwarzschild_radius), 0.04f0, 4f0)

using Base: @propagate_inbounds
# A DDA walk over the medium's majorant grid, in medium space. Outside
# `density_bounds` the plasma is zero, so a chord there takes no samples at all;
# Hikari still bends it at its end.
@propagate_inbounds function Hikari.create_majorant_iterator(
    medium::SpacetimeMedium,
    table::Hikari.RGBToSpectrumTable,
    ray::Raycore.Ray,
    t_max::Float32,
    λ::Hikari.Wavelengths,
    ::Hikari.MajorantGrid
)
    M = medium.render_to_medium
    o = M * Vec4f(ray.o[1], ray.o[2], ray.o[3], 1f0)
    d = M * Vec4f(ray.d[1], ray.d[2], ray.d[3], 0f0)
    ray_o = Point3f(o[1], o[2], o[3])
    ray_d = Vec3f(d[1], d[2], d[3])
    t_enter, t_exit = Hikari.ray_bounds_intersect(ray_o, ray_d, medium.density_bounds)
    t_enter = max(t_enter, 0f0)
    t_exit = min(t_exit, t_max)
    t_enter >= t_exit && return Hikari.RayMajorantIterator(medium.majorant_grid)
    return Hikari.RayMajorantIterator(Hikari.create_dda_iterator(medium.majorant_grid,
        medium.density_bounds, ray_o, ray_d, t_enter, t_exit, Hikari.SpectralRadiance(1f0)))
end

@propagate_inbounds Hikari.create_majorant_iterator(medium::SpacetimeMedium,
        table::Hikari.RGBToSpectrumTable, ray::Raycore.Ray, t_max::Float32, λ::Hikari.Wavelengths) =
    Hikari.create_majorant_iterator(medium, table, ray, t_max, λ, medium.majorant_grid)

@inline Hikari.get_template_grid(medium::SpacetimeMedium) = medium.majorant_grid

# Light bending. A Schwarzschild null orbit, in areal Cartesian coordinates and
# Euclidean arc length, turns toward the hole with curvature 1.5·rs·ℓ³/r⁵,
# ℓ = |x × d|: the orbit equation u'' + u = 1.5·rs·u², whose circular photon
# orbit lies at r = 1.5 rs. Hikari traces the orbit as straight chords: the
# start callback turns the direction onto the chord, the end callback turns the
# chord onto the direction at its end. The two turns are the curvature weighted
# along the arc of length S, α₀ = ∫κ(1 - s/S) and α₁ = ∫κ s/S, here by
# Simpson's rule at the arc's start, midpoint and end. That is fourth order;
# the staggered half kicks it replaces were second order, and needed several
# times the chords, each a wavefront round, for the same accuracy.
# Powers as products: Julia raises a Float32 to an integer power in Float64.
@inline function orbit_curvature(m::SpacetimeMedium, x::Vec3f, d::Vec3f)
    l2 = sum(abs2, cross(x, d))
    r2 = dot(x, x)
    return 1.5f0 * m.lensing_strength * m.schwarzschild_radius * l2 * sqrt(l2) / max(r2 * r2 * sqrt(r2), 1f-8)
end

"The unit vector perpendicular to `d`, in its orbit plane, toward the hole."
@inline function inward(x::Vec3f, d::Vec3f)
    n = dot(x, d) * d - x
    len = norm(n)
    return len > 0f0 ? n / len : Vec3f(0)
end

"`d` turned by the angle `α` toward the unit vector `n ⟂ d`."
@inline turn(d::Vec3f, n::Vec3f, α::Float32) = Vec3f(normalize(cos(α) * d + sin(α) * n))

"""
    chord_turns(m, o, c, h, d0, Val(refinements)) -> (; α0, α1, n, κo)

The turns from the start direction onto the chord `o + s·c`, `0 ≤ s ≤ h`, and
from the chord onto the end direction, both toward `n`, and the curvature at
the start. `d0` is the start direction, or `nothing` where
only the chord is known. The arc's own directions at its start, midpoint and end
are the chord's turned by the current estimate of the turns, `refinements`
times: by -α₀, S(κ₀ - κ₁)/24 and α₁, exact on an arc of linearly changing
curvature. Its midpoint lies the sagitta S·Θ/8 of the total
turn Θ outside the chord's, away from the hole, and it is longer than the chord
by the factor 1 + Θ²/24.
"""
@inline function chord_turns(m::SpacetimeMedium, o::Vec3f, c::Vec3f, h::Float32, d0, ::Val{refinements}=Val(2)) where {refinements}
    q = o + h * c
    mid = o + 0.5f0 * h * c
    n = inward(mid, c)
    κo = start_curvature(m, o, c, n, 0.5f0 * h * orbit_curvature(m, o, c), d0)
    κm = orbit_curvature(m, mid, c)
    κq = orbit_curvature(m, q, c)
    for _ in 1:refinements
        Θ = h * (κo + 4f0 * κm + κq) / 6f0
        S = h * (1f0 + Θ^2 / 24f0)
        α0 = S * (κo + 2f0 * κm) / 6f0
        α1 = S * (2f0 * κm + κq) / 6f0
        κo = start_curvature(m, o, c, n, α0, d0)
        κq = orbit_curvature(m, q, turn(c, n, α1))
        κm = orbit_curvature(m, mid - (S * Θ / 8f0) * n, turn(c, n, S * (κo - κq) / 24f0))
    end
    Θ = h * (κo + 4f0 * κm + κq) / 6f0
    S = h * (1f0 + Θ^2 / 24f0)
    return (; α0 = S * (κo + 2f0 * κm) / 6f0, α1 = S * (2f0 * κm + κq) / 6f0, n, κo)
end

@inline start_curvature(m, o, c, n, α0, d0::Vec3f) = orbit_curvature(m, o, d0)
@inline start_curvature(m, o, c, n, α0, ::Nothing) = orbit_curvature(m, o, turn(c, n, -α0))

@inline bends(m::SpacetimeMedium, x::Vec3f) =
    m.lensing_strength > 0f0 && m.schwarzschild_radius <= norm(x) <= 50f0 * m.schwarzschild_radius

@inline function Hikari.medium_start_direction(m::SpacetimeMedium, p, d, h)
    o = Vec3f(p - m.center)
    bends(m, o) || return d
    n = inward(o, d)
    c = turn(d, n, 0.5f0 * h * orbit_curvature(m, o, d))
    for _ in 1:2
        c = turn(d, n, chord_turns(m, o, c, h, d).α0)
    end
    return c
end

# The direction at the point `p`, `t` along the chord `c` of planned length `h`:
# the chord's turned by the quadratic in `t` from -α₀ at the start, with the
# start's curvature as its slope, to α₁ at the end. A medium sample only needs
# it for the Doppler shift, so it takes the turns unrefined; the chord's end
# takes them refined.
@inline function chord_direction(m::SpacetimeMedium, p, c, h, t, refinements)
    o = Vec3f(p - m.center) - t * c
    bends(m, o) || return c
    k = chord_turns(m, o, c, h, nothing, refinements)
    return turn(c, k.n, -k.α0 + k.κo * t + (k.α0 + k.α1 - k.κo * h) * (t / h)^2)
end
@inline Hikari.medium_point_direction(m::SpacetimeMedium, p, c, h, t) = chord_direction(m, p, c, h, t, Val(0))
@inline Hikari.medium_end_direction(m::SpacetimeMedium, p, c, h, t) = chord_direction(m, p, c, h, t, Val(2))

# ============================================================================
# Density Field Generation
# ============================================================================

smoothstep(edge0, edge1, x) = let t = clamp((x - edge0) / (edge1 - edge0), 0f0, 1f0)
    t * t * (3f0 - 2f0 * t)
end

include("grmhd.jl")

const BH_SKY_EXPOSURE = 0.08f0

"""
    spacetime_blackhole!(scene; gas, bending, doppler, horizon_visible, ...) -> (; boundary, horizon, state)

The black hole in `scene`: the spacetime medium inside its boundary sphere and
the horizon. `gas`, `bending` and `doppler` (0 to 1) and `horizon_visible` are
construction Observables connected to the boundary plot's native attributes.
"""
function spacetime_blackhole!(scene; emission_scale = 12f0,
                             bending = Observable(1f0), gas = Observable(1f0), doppler = Observable(1f0),
                             horizon_visible = Observable(true), step_scale = 1f0,
                             animate_plasma=false,plasma_input=Observable{Any}(nothing))
    labelsonly=labels_only()
    plasma = labelsonly || animate_plasma ? empty_plasma() : grmhd_plasma()
    # A state's cells are packed once, and the pair's per-cell bounds computed
    # once, when the pair changes; the frame's grid is derived from them with
    # its own gas scale. A pair moving on by one snapshot keeps its packing.
    packed(s)=(; cells=pack_cells(s), theta_lut=theta_lookup(s.theta))
    static_key=UInt64(objectid(plasma.density))
    static_state=packed(plasma)
    static=(; key=static_key, next_key=static_key, bounds=grmhd_pair_cells(plasma,plasma),
              a=static_state, b=static_state)
    pair=Ref(static)
    function state(gas_scale,bending_scale,doppler_scale,input=plasma_input[])
        if labelsonly || !animate_plasma || isnothing(input)
            a=plasma; mix=0f0; now=static
        else
            a,b,mix=input.a,input.b,input.weight
            key,next_key=UInt64(objectid(a.density)),UInt64(objectid(b.density))
            if (pair[].key,pair[].next_key)!=(key,next_key)
                old=pair[]
                reuse(k,s)=k==old.key ? old.a : k==old.next_key ? old.b : packed(s)
                pair[]=(; key, next_key, bounds=grmhd_pair_cells(a,b), a=reuse(key,a), b=reuse(next_key,b))
            end
            now=pair[]
        end
        cells=now.bounds
        gas_scale=Float32(gas_scale)
        dop=Float32(doppler_scale)
        0f0<=dop<=1f0 || error("The plasma majorant bounds Doppler shifts for doppler in [0, 1], got $dop")
        padding=0.5f0
        SpacetimeMedium(now.a.cells; cells_next=now.b.cells, a.theta, theta_lut=now.a.theta_lut,
        a.log_r0, a.dlog_r, a.phi0, a.dphi, max_absorption=maximum(cells.absorption)*1.0001f0+1f-6,
        time_mix=mix,snapshot_key=now.key,next_snapshot_key=now.next_key,
        lensing_strength=Float32(bending_scale), emission_scale=Float32(emission_scale),
        bounds=Hikari.Bounds3(Point3f(-18),Point3f(18)),
        density_bounds=Hikari.Bounds3(Point3f(-a.extent),Point3f(a.extent)),
        gas_scale, doppler=dop,
        deflection_padding=padding, step_scale=Float32(step_scale),
        majorant_grid=Hikari.MajorantGrid(majorant_voxels(cells,gas_scale,padding),
                                     Vec{3,Int32}(size(cells.absorption)...)))
    end
    material = lift((g,b,d,input) -> Hikari.MediumInterface(Hikari.NullMaterial(); inside=state(g,b,d,input)),
                    gas, bending, doppler, plasma_input)
    boundary = mesh!(scene, Sphere(Point3f(0),18f0); name=:plasma_volume, material, transparency=true)
    plotattribute!(boundary,:gas_scale,gas)
    plotattribute!(boundary,:lensing_strength,bending)
    plotattribute!(boundary,:doppler,doppler)
    plotattribute!(boundary,:snapshot,plasma_input)
    horizon = mesh!(scene, Sphere(Point3f(0),1f0);
        name=:event_horizon,material=Hikari.Diffuse(Kd=Hikari.RGBSpectrum(0f0)), visible=horizon_visible)
    plotattribute!(horizon,:visible,horizon_visible)
    return (; boundary, horizon, state)
end

# Projection helpers for label anchors only. These do not generate rays/images.
struct BHCamera
    eye::Vec3f
    forward::Vec3f
    right::Vec3f
    up::Vec3f
    tanhalf::Float32
end
function BHCamera(p::Pose)
    forward = normalize(p.lookat - p.eye)
    right = normalize(cross(forward, Vec3f(0, 0, 1)))
    return BHCamera(p.eye, forward, right, cross(right, forward), Float32(tand(p.fov / 2)))
end
function screenpoint(cam::BHCamera, p, canvas)
    d = Vec3f(p) - cam.eye
    z = dot(d, cam.forward)
    x = dot(d, cam.right) / (z * cam.tanhalf)
    y = dot(d, cam.up) / (z * cam.tanhalf)
    W, H = canvas
    return Point2f((x * H / W + 1) * W / 2, (y + 1) * H / 2)
end
apparent(cam::BHCamera, r, canvas) = Float32(r / (norm(cam.eye) * cam.tanhalf) * canvas[2] / 2)
const PHOTON_RING = Float32(3sqrt(3) / 2)

"""
Projected critical curve of the production Schwarzschild medium (rs = 1).

The tracer bends rays only inside the radius-18 medium boundary. Its orbit
equation u'' + u = 3u²/2 conserves u'² + u² - u³ = 1/b∞². At entry,
u'² + u² = 1/bentry², hence 1/bentry² = 1/bcritical² + 1/18³.
Project that incoming cone, not the small-angle approximation `apparent`,
and do not enlarge it to fit the broad, glowing accretion-disk image.
The photon subrings converge on this curve; it is not the event horizon.
"""
function photon_ring_contour(cam::BHCamera, canvas; samples=721)
    impact = inv(sqrt(inv(Float64(PHOTON_RING)^2) + inv(18.0^3)))
    distance = Float64(norm(cam.eye))
    distance > 18 || throw(ArgumentError("Photon-ring annotation requires a camera outside the medium"))
    axis = normalize(-cam.eye)
    # Use the camera's transverse basis so the projection remains correct even
    # if a later edit looks slightly away from the centre of the hole.
    u = normalize(cam.right - dot(cam.right,axis)*axis)
    v = normalize(cross(axis,u))
    sintheta = impact/distance
    costheta = sqrt(1-sintheta^2)
    W,H = canvas
    map(range(0,2π;length=samples)) do angle
        d = costheta*axis + sintheta*(cos(angle)*u + sin(angle)*v)
        z = dot(d,cam.forward)*cam.tanhalf
        Point2f(W/2 + H/2*dot(d,cam.right)/z,
                H/2 + H/2*dot(d,cam.up)/z)
    end
end
# NASA SVS Deep Star Maps 2020 at 16k: two texels per pixel at the film's 30°
# view, where the 4k map had half a texel and blurred every star. NASA scales
# each resolution on its own: the 16k sky integrates to 1/8.02 of the 4k one the
# film was exposed with (the Milky Way band alike), so it is scaled back.
const STARMAP = joinpath(@__DIR__, "..", "assets", "starmap_2020_16k.exr")
const STARMAP_SCALE = 8.02f0
blackhole_lights(; exposure=BH_SKY_EXPOSURE) =
    [EnvironmentLight(Float32(exposure) * STARMAP_SCALE, load(STARMAP))]
