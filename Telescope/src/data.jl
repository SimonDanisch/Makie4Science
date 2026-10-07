# The telescope film's data: the simulated steady states of its telescopes
# (a `FieldSet`, computed once on a GPU and shipped as an artifact so every
# machine renders from identical numbers) and what is derived from them and from
# the optics on load: ray fans, landing profiles, sensor readouts, geometry.

"""The telescope of the first act and the grid it is simulated on."""
function telescope_setup(; D = 30f0)
    tel = refractor(; D)
    g = Grid(Point2f(-30, -32), Point2f(tel.sys.sensor + 22, 32), 12)
    return tel, g
end

"""A fresh continuous-wave simulation of `tel`, switched on at t = 0."""
function telescope_wave(tel::Refractor, g::Grid; waves = (PlaneWave(0f0),))
    index, metal, σ, dt = rasterize(g, tel.sys, 1f0)
    dev = device()
    return Wave(dev, g, Medium(dev, g, index, metal, σ, dt), dt; waves, envelope = Continuous(), xsrc = -16f0)
end


"""
A telescope with a given aperture (and focal length `f`) and its steady state,
for the comparisons. By default every one has the same tube and camera, so
only the aperture `D` differs.
`angles` are the stars' directions (radians); each is simulated on its own,
since two stars do not interfere: their intensities add.
"""
struct Observation
    tel::Refractor
    g::Grid
    A::Vector{Matrix{ComplexF32}}
    I::Vector{Matrix{Float32}}
end

"""
The telescope of aperture `D` and its grid: the grid reaches just past the
instrument, so its absorbing border (12λ) begins right outside the widest
drawn part.
"""
function observation_setup(D; f = 120f0, tube = 19f0)
    tel = refractor(; D = Float32(D), f = Float32(f), tube = Float32(tube))
    h = outer_radius(tel.parts) + 13f0
    return tel, Grid(Point2f(-30, -h), Point2f(tel.sys.sensor + 22, h), 12)
end

"The name of an observation's steady state in a `FieldSet`."
observation_name(D, θ; f = 120f0, tube = 19f0) = "obs_D$(Float32(D))_f$(Float32(f))_tube$(Float32(tube))_theta$(Float32(θ))"

"The steady state of a star at `θ` through the telescope of aperture `D`, simulated on the GPU."
function observation_field(D, θ; f = 120f0, tube = 19f0)
    tel, g = observation_setup(D; f, tube)
    w, _, _ = simulate(tel.sys, g; waves = (PlaneWave(Float32(θ)),), xsrc = -16f0, tend = 260, backend = device())
    return amplitude(w)
end

"The observation of stars at `angles` from precomputed `fields` (see `FieldSet`)."
function Observation(fields::AbstractDict, D; f = 120f0, tube = 19f0, angles = (0f0,))
    tel, g = observation_setup(D; f, tube)
    runs = [fields[observation_name(D, θ; f, tube)] for θ in angles]
    return Observation(tel, g, runs, [abs2.(A) for A in runs])
end

"""
The glow of every star's wave at phase `φ`, each in its own colour, added,
and only within the instrument's outline: light that misses it (and what the
baffle's rim scatters) stays dark.
"""
function observation_glow(o::Observation, φ; tints = (SUNLIGHT, SECONDARY_LIGHT))
    texs = [hide_source!(glow(phase_field(A, φ), I; GLOW..., tint), o.g, -14f0)
            for (A, I, tint) in zip(o.A, o.I, tints)]
    return outline_mask!(reduce((a, b) -> a .+ b, texs), o.g, o.tel.parts)
end

const INSET = (backgroundcolor = :black, xgridvisible = false, ygridvisible = false,
               leftspinevisible = false, rightspinevisible = false, topspinevisible = false,
               bottomspinecolor = :gray50, xticksvisible = false, yticksvisible = false,
               xticklabelsvisible = false, yticklabelsvisible = false, titlecolor = :white,
               titlesize = 18, xlabelcolor = :gray70)

const FIELD_COLORS = [SUNLIGHT, PALETTE.rose, PALETTE.blue]

const COLOUR_RAYS = ((0.45f0, PALETTE.spectral_blue), (0.55f0, PALETTE.spectral_green), (0.65f0, PALETTE.spectral_red))

const BLUE_LIGHT = 0.8f0   # wavelengths in units of the design (green) one

const RED_LIGHT = 1.15f0

const BLUE_TINT = PALETTE.spectral_blue

const RED_TINT = PALETTE.spectral_red

"""
Everything act 1 shows: the telescope and its steady state, the outline of
its cut and its lens's cross-section, the narrow and wide telescopes, the
telescope in blue and red light, and the refraction demo.
"""
struct Act
    tel::Refractor
    g::Grid
    A::Matrix{ComplexF32}
    I::Matrix{Float32}
    xexit::Float32
    xf::Float32
    obs::Vector{Observation}
    section::Matrix{Float32}
    outline::BitMatrix
    colours::Vector{Tuple{Matrix{ComplexF32},Matrix{Float32}}}
    refraction::Refraction
end

"Act 1 from precomputed `fields` (see `FieldSet`)."
function Act(fields::AbstractDict)
    tel, g = telescope_setup()
    A = fields["act"]
    inside = fill(Hikari.RGBSpectrum(1f0, 1f0, 1f0, 1f0), size(g))
    outline_mask!(hide_source!(inside, g, -0.5f0), g, tel.parts)
    outline = rim_mask(map(t -> t.c[1] > 0, inside), 4)
    colours = [(fields[k], abs2.(fields[k])) for k in ("act_blue", "act_red")]
    return Act(tel, g, A, abs2.(A), tel.sys.elements[end].back.x + 0.3f0, tel.sys.sensor,
               [Observation(fields, 15), Observation(fields, 30)],
               lens_section(g, tel.sys), outline, colours, Refraction(fields["refraction"]))
end

"""The height of the first dark pixel of `a`'s telescope: where its edges are one wavelength apart."""
lens_edges(a::Act) = Wavelets([Point2f(a.xexit, 15), Point2f(a.xexit, -15)], Point2f(a.xf, 0))

dark_height(a::Act) = height_for(lens_edges(a), 1, 2, 1f0)

half_height(a::Act) = height_for(lens_edges(a), 1, 2, 0.5f0)

const ORANGE = PALETTE.amber

const BLUE = PALETTE.blue

const PAIR_COLORS = [PALETTE.rose, PALETTE.gold, PALETTE.blue]

rgbf(c) = Makie.RGBf(c...)

"""
The height of the pixel at which the extra distance between sources `a` and `b`
of `wl` is `Δ` wavelengths (bisection; the far source is the longer path).
"""
function height_for(wl::Wavelets, a, b, Δ)
    f(y) = abs(delay(wl, wl.src[b], Point2f(wl.focus[1], y)) - delay(wl, wl.src[a], Point2f(wl.focus[1], y)))
    lo, hi = 0f0, 20f0
    for _ in 1:50
        m = (lo + hi) / 2
        f(m) < Δ ? (lo = m) : (hi = m)
    end
    return (lo + hi) / 2
end

"""A distance in wavelengths, as said: "½", "¾", "1", or "0.3" off the eighths."""
function fraction(e)
    k = round(Int, 8e)
    return 0 <= k <= 8 && abs(e - k / 8) < 0.02f0 ? EIGHTHS[k+1] : string(round(e; digits = 1))
end

const EIGHTHS = ["0", "⅛", "¼", "⅜", "½", "⅝", "¾", "⅞", "1"]

"""Four points of the lens, from the top edge down, evenly spaced: pairs half a lens apart."""
lens_points(s::Act, focus) = Wavelets([Point2f(s.xexit, y) for y in (15f0, 7.5f0, 0f0, -7.5f0)], focus)

const POINT_COLORS = [ORANGE, PALETTE.gold, PALETTE.rose, BLUE]

"""Both setups of the window beat: stars far away, and two points of a scene in front."""
struct WindowSetups
    g::Grid
    λ::Float32
    window::Rect2f
    stars::Tuple{FarSource,FarSource}
    scene::Tuple{NearSource,NearSource}
end

function WindowSetups(; λ = 0.6f0)
    δ = asin(λ / 12f0)   # as in act 1's window: a whole wavelength over 12 units
    # wide and flat, stacked one above the other; the window in the same place in both
    return WindowSetups(Grid(Point2f(-10, -3.5f0), Point2f(10, 3.5f0), 12 / λ), λ, Rect2f(5, -1.5f0, 3, 3),
                        (FarSource(Vec2f(1, 0)), FarSource(Vec2f(cos(δ), sin(δ)))),
                        (NearSource(Point2f(-6, 2.8f0)), NearSource(Point2f(-6, -2.8f0))))
end

const STACKED = (Vec3f(0, 4.3f0, 0), Vec3f(0, -4.3f0, 0))

const LENS_S = 0.2f0      # world units per millimetre

"""One fan of parallel rays: from `θ` (radians) to the side, of wavelength `λ` (relative to green), drawn in `tint`."""
struct Fan
    θ::Float32
    λ::Float32
    tint::NTuple{3,Float32}
end

"""
One lens and three, side by side, with their ray `fans` (drawn with 11 rays)
and where each fan's light lands (301 rays): its centre on the sensor, and its
profile per grid row, enlarged `zoom` times around that centre, ± `window` mm
of the sensor, scaled to its own peak.
"""
struct LensDemo
    lenses::Vector{CameraLens}
    grids::Vector{Grid}
    offsets::Vector{Vec3f}
    fans::Vector{Fan}
    paths::Matrix{Vector{Vector{Point2f}}}    # [lens, fan]
    centres::Matrix{Float32}                  # [lens, fan]
    profiles::Matrix{Vector{Float32}}         # [lens, fan], per grid row, 0..1
    zoom::Float32
    window::Float32
    bright::Float32                           # how bright the plots' curves glow
    height::Float32                           # mm the plots reach at their peak
end

function LensDemo(fans; D = 12.5f0, zoom = 4f0, window = 1.25f0, bright = 1.8f0, height = 10f0)
    lenses = [singlet_camera(; D), cooke_camera(; D)]
    shift = lenses[2].sys.sensor - lenses[1].sys.sensor
    offsets = [Vec3f(LENS_S * shift, 4.8f0, 0), Vec3f(0, -4.8f0, 0)]
    grids = [Grid(Point2f(-16, -23), Point2f(l.sys.sensor + PLOT_GAP + height + 3, 23), 16) for l in lenses]
    paths = [ray_fans(l.sys, (f.θ,); D, stop = l.stop, n = 11, λ = f.λ)[1] for l in lenses, f in fans]
    landed = [landing(l, f.θ; λ = f.λ) for l in lenses, f in fans]
    centres = [sum(h .* w) / sum(w) for (h, w) in landed]
    profiles = map(CartesianIndices(landed)) do I
        (h, wt), c, g = landed[I], centres[I], grids[I[1]]
        u = (collect(ys(g)) .- c) ./ zoom
        p = light_profile(h .- c, wt, u; σ = window / 10)
        p = p ./ maximum(p)
        p[abs.(u) .> window] .= 0f0
        p
    end
    return LensDemo(lenses, grids, offsets, collect(Fan, fans), paths, centres, profiles, Float32(zoom), Float32(window),
                    Float32(bright), Float32(height))
end

"""Light from straight ahead and from 15° to the side, in one colour."""
lens_demo() = LensDemo([Fan(0, 1, FIELD_COLORS[1]), Fan(deg2rad(15f0), 1, FIELD_COLORS[3])]; zoom = 4, window = 1.25)

"""
Blue, green and red light from straight ahead. The single lens spreads them
over ±0.12, ±0.04 and ±0.05 mm, so the plots are enlarged strongly, and drawn
dimmer, so that where the colours overlap they do not all turn white.
"""
colour_demo() = LensDemo([Fan(0, λ / 0.55f0, tint) for (λ, tint) in COLOUR_RAYS]; zoom = 50, window = 0.2, bright = 1f0,
                         height = 22)

"""
The lens beats' camera: over the middle of both lenses and their plots, below
the studio's softboxes (at heights 16 and 20; above them it looks through one).
"""
function lens_pose(d::LensDemo)
    xmid = LENS_S * (d.lenses[2].sys.sensor + PLOT_GAP + d.height - 16f0) / 2 + 2.2f0
    return Pose((xmid, -7.8, 15), (xmid, -1.7, 0); fov = 63)
end

"""When the rays of fan `k` reach lens `i`'s sensor, having set off at `t0`."""
landing_time(d::LensDemo, i, t0; speed = 40f0) = t0 + (d.lenses[i].sys.sensor + 12f0) / speed

"""A point of lens `i`'s cut (mm), in the world."""
lens_point(d::LensDemo, i, x, y) = Point3f(LENS_S * x + d.offsets[i][1], LENS_S * y + d.offsets[i][2], 0)

"""The peak of the plot of lens `i`'s fan `k`, in the world."""
plot_tip(d::LensDemo, i, k) =
    (j = argmax(d.profiles[i, k]); lens_point(d, i, d.lenses[i].sys.sensor + PLOT_GAP + d.height, ys(d.grids[i])[j]))

"""The colour beat's camera: closer in, on the sensors and their plots."""
function colour_pose(d::LensDemo)
    x = LENS_S * (d.lenses[2].sys.sensor + 2f0)
    return Pose((x, -7.5, 15), (x, -1.4, 0); fov = 60)
end


"""
How far apart the two stars of the comparisons are: 1.3 diffraction limits of
the 30λ telescope.
"""
const STAR_SEPARATION = 1.3f0 / 30f0

"""
    FieldSet

Steady-state complex amplitudes by name. `field_names()` lists what the film
needs; `compute_field(name)` simulates one.
"""
const FieldSet = Dict{String, Matrix{ComplexF32}}

"Every steady state the telescope film shows."
function field_names()
    δ = STAR_SEPARATION
    obs = [(15, 0f0), (30, 0f0), (15, δ / 2), (15, -δ / 2), (30, δ / 2), (30, -δ / 2), (30, δ)]
    return vcat(["act", "act_blue", "act_red", "refraction"], [observation_name(D, θ) for (D, θ) in obs])
end

"Simulate the steady state `name` (see `field_names`) on the GPU."
function compute_field(name::AbstractString)
    if name == "act"
        tel, g = telescope_setup()
        w, _, _ = simulate(tel.sys, g; xsrc = -16f0, tend = 260, backend = device())
        return amplitude(w)
    elseif name in ("act_blue", "act_red")
        tel, g = telescope_setup()
        return first(steady(tel.sys, g; λ = name == "act_blue" ? BLUE_LIGHT : RED_LIGHT, tend = 300f0))
    elseif name == "refraction"
        return refraction_field()
    end
    m = match(r"^obs_D([\d.]+)_f([\d.]+)_tube([\d.]+)_theta(-?[\d.e-]+)$", name)
    m === nothing && error("unknown telescope field: $name")
    D, f, tube, θ = parse.(Float32, m.captures)
    return observation_field(D, θ; f, tube)
end

"""
    savefields(dir, fields)

Write a `FieldSet` as raw little-endian `ComplexF32` files with a `fields.json`
index of their sizes: readable without Julia's serializer, so the artifact
outlives Julia versions.
"""
function savefields(dir::AbstractString, fields::AbstractDict)
    mkpath(dir)
    index = Dict{String, Any}()
    for (name, A) in fields
        write(joinpath(dir, name * ".c64"), htol.(A))
        index[name] = collect(size(A))
    end
    write(joinpath(dir, "fields.json"), JSON.json(index))
    return dir
end

"Read a `FieldSet` written by `savefields`."
function loadfields(dir::AbstractString)
    index = JSON.parsefile(joinpath(dir, "fields.json"))
    fields = FieldSet()
    for (name, dims) in index
        A = Matrix{ComplexF32}(undef, dims[1], dims[2])
        read!(joinpath(dir, name * ".c64"), A)
        fields[name] = ltoh.(A)
    end
    return fields
end

"The telescope film's fields: the `telescope-fields` artifact."
fields_dir() = artifact"telescope-fields"

"""
Everything the telescope film shows, derived once per process from its fields
and its optics.
"""
struct TelescopeData
    act::Act
    instruments::Instruments
    windows::WindowSetups
    lenses::LensDemo
    colours::LensDemo
    leftover::Leftover
    two_stars::Vector{Observation}
    sorting::Observation
end

function TelescopeData(fields::AbstractDict)
    δ = STAR_SEPARATION
    lenses = lens_demo()
    return TelescopeData(Act(fields), Instruments(), WindowSetups(), lenses, colour_demo(), Leftover(lenses),
                         [Observation(fields, 15; angles = (δ / 2, -δ / 2)), Observation(fields, 30; angles = (δ / 2, -δ / 2))],
                         Observation(fields, 30; angles = (0f0, δ)))
end

"""What is left of the lens smear: the three-lens camera of the lens beat, from `θ` to the side."""
WaveOptics.Leftover(d::LensDemo; θ = deg2rad(15f0)) = Leftover(bundle_spot(d.lenses[2], θ), 50f0 / d.lenses[2].D)

"The process's telescope data, loaded from the artifact on first use."
const DATA = Ref{Union{Nothing, TelescopeData}}(nothing)
function telescope_data()
    DATA[] === nothing && (DATA[] = TelescopeData(loadfields(fields_dir())))
    return DATA[]
end
