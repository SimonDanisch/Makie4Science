# The Earth, raytraced: NASA's day colours with the day's clouds in them,
# glossy water, city lights glowing on the night side, inside a shell of air
# that scatters blue light (Rayleigh). Radius 1, z through the North Pole; the
# maps are assets/earth/*.png (experiments/earth.jl makes them from NASA's).
#
# The clouds are painted into the surface rather than floating on a shell of
# their own: 0.6 % above the ground their parallax is invisible from space, and
# a see-through shell needs the tracer's alpha test, which its hardware path
# does not have, so it would have to trace in software at a fraction of the speed.

const EARTH_MAPS = joinpath(@__DIR__, "..", "assets", "earth")

# ── the air ─────────────────────────────────────────────────────────────────

"""
Air around a planet of radius `radius` centred at the origin: Rayleigh
scattering `β` (per unit length at the ground, per RGB channel), thinning out
as exp(-height / `scale`); no absorption, no glow. Ten times thicker than the
real one (8.5 km of 6371) at the same optical depth, so the glow at the edge
shows from far away.
"""
struct Atmosphere <: Hikari.Medium
    radius::Float32
    top::Float32
    scale::Float32
    β::Hikari.RGBSpectrum
    bounds::Hikari.Bounds3
end

function Atmosphere(; radius = 1f0, scale = 0.0126f0, top = radius + 6scale,
                    β = Hikari.RGBSpectrum(5.8f-6, 13.5f-6, 33.1f-6) * (0.7f0 * 6.371f6 * 0.00133f0 / scale))
    return Atmosphere(Float32(radius), Float32(top), Float32(scale), β, Hikari.Bounds3(Point3f(-top), Point3f(top)))
end

Hikari.is_emissive(::Atmosphere) = false
@inline Hikari.get_template_grid(::Atmosphere) = Hikari.EmptyMajorantGrid()

function Hikari.sample_point(m::Atmosphere, media, table::Hikari.RGBToSpectrumTable, p::Point3f, λ::Hikari.Wavelengths)
    h = max(norm(p) - m.radius, 0f0)
    d = h > m.top - m.radius ? 0f0 : exp(-h / m.scale)
    σ_s = Hikari.uplift_rgb_unbounded(table, m.β, λ) * d
    return Hikari.MediumProperties(Hikari.SpectralRadiance(0f0), σ_s, Hikari.SpectralRadiance(0f0), 0f0)
end

function Hikari.create_majorant_iterator(m::Atmosphere, table::Hikari.RGBToSpectrumTable, ray::Raycore.Ray, t_max::Float32,
                                         λ::Hikari.Wavelengths)
    t0, t1 = Hikari.ray_bounds_intersect(ray.o, ray.d, m.bounds)
    t0 = max(t0, 0f0); t1 = min(t1, t_max)
    t0 >= t1 && return Hikari.RayMajorantIterator_homogeneous(0f0, 0f0, Hikari.SpectralRadiance(0f0))
    return Hikari.RayMajorantIterator_homogeneous(t0, t1, Hikari.uplift_rgb_unbounded(table, m.β, λ))
end

Base.@propagate_inbounds function Hikari.create_majorant_iterator(m::Atmosphere, table::Hikari.RGBToSpectrumTable,
                                                                  ray::Raycore.Ray, t_max::Float32, λ::Hikari.Wavelengths,
                                                                  template::G) where {G<:Hikari.MajorantGrid}
    t0, t1 = Hikari.ray_bounds_intersect(ray.o, ray.d, m.bounds)
    t0 = max(t0, 0f0); t1 = min(t1, t_max)
    res = template.res
    empty = t0 >= t1
    return Hikari.RayMajorantIterator{G}(
        empty ? Int32(0) : Int32(1), empty ? Hikari.SpectralRadiance(0f0) : Hikari.uplift_rgb_unbounded(table, m.β, λ),
        empty ? 0f0 : t0, empty ? 0f0 : t1, false, template,
        (Int32(res[1]), Int32(res[2]), Int32(res[3])),
        (0f0, 0f0, 0f0), (0f0, 0f0, 0f0),
        (Int32(0), Int32(0), Int32(0)), (Int32(0), Int32(0), Int32(0)), (Int32(0), Int32(0), Int32(0)))
end

# ── the ground ──────────────────────────────────────────────────────────────

"""The brightness of a map pixel, 0..1."""
level(c::Colors.AbstractGray) = Float32(Colors.gray(c))

"""
    earth_material(; citylights) -> Hikari.Material

The surface: the day colours with the clouds painted in (white where they are
thick), matte land and cloud, glossy open water, city lights glowing where no
cloud covers them. Decode the day map from sRGB before mixing linear surface
reflectance with cloud reflectance. Water/cloud masks are data, not colours.
"""
function earth_material(; citylights = 0.6f0)
    day = load(joinpath(EARTH_MAPS, "day.png"))
    water, clouds, lights = (level.(load(joinpath(EARTH_MAPS, f * ".png"))) for f in ("water", "clouds", "lights"))
    cover = clamp.(1.3f0 .* clouds .- 0.1f0, 0f0, 1f0)
    albedo = map(day, cover) do c, a
        linear = Hikari.srgb_gamma_to_linear.((Float32(Colors.red(c)), Float32(Colors.green(c)), Float32(Colors.blue(c))))
        rgb = (1 - a) .* linear .+ a .* 0.85f0
        Hikari.RGBSpectrum(rgb...)
    end
    glow = map((l, a) -> Hikari.RGBSpectrum(citylights * l * (1 - 0.85f0 * a) .* (1f0, 0.75f0, 0.45f0)...), lights, cover)
    tex = Hikari.Texture(albedo)
    surface = Hikari.MixMaterialSpec(Hikari.Diffuse(Kd = tex), Hikari.CoatedDiffuse(reflectance = tex, roughness = 0.06f0, eta = 1.33f0),
                                     Hikari.Texture(water .* (1 .- cover)))
    return Hikari.MediumInterface(surface; emission = Hikari.Emissive(Le = Hikari.Texture(glow)))
end

"""The shell of air around the Earth: an invisible boundary with the `Atmosphere` inside it."""
air!(scene; atmosphere = Atmosphere()) =
    mesh!(scene, Sphere(Point3f(0), atmosphere.top); transparency = true,
          material = Hikari.MediumInterface(Hikari.NullMaterial(); inside = atmosphere, outside = nothing))

"""
Light for scenes with the Earth: a sun from the front left (as the cameras look
along +y), bright enough for the air to glow. Space supplies no uniform grey
fill: an ambient environment was visible through null atmosphere boundaries,
making their finite outer extent look like a solid grey shell. Sunlight,
scattering and the existing city emission light the planet instead.
"""
sunlight(; towards = Vec3f(-0.75, -0.55, 0.35), brightness = 3f0) =
    [Makie.AmbientLight(RGBf(0, 0, 0)), Makie.DirectionalLight(RGBf(brightness, brightness, 0.97f0 * brightness), -normalize(towards))]
