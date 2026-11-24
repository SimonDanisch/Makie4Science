# Experiment: a raytraced Earth seen from space. Textured land, glossy oceans,
# and an atmosphere that scatters blue light (Rayleigh), as a medium Hikari's
# volumetric path tracer walks through. Run in the BlackholeImage environment;
# `include` after `using Makie, RayMakie, Hikari`.

using LinearAlgebra: norm, I
import LinearAlgebra
using GeometryBasics
import Raycore

# ── the atmosphere ──────────────────────────────────────────────────────────

"""
Air around a planet of radius `radius` centred at the origin: Rayleigh
scattering `β` (per unit length, at the surface, per RGB channel), thinning out
as exp(-height / `scale`), no absorption, no emission.

Ten times thicker than the real one (8.5 km of 6371) with the same optical
depth, so its glow shows at the limb from far away.
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
    b = Hikari.Bounds3(Point3f(-top), Point3f(top))
    return Atmosphere(Float32(radius), Float32(top), Float32(scale), β, b)
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

# ── the planet ──────────────────────────────────────────────────────────────

"""Where the oceans are, 1 for water: given, or guessed from a day picture as the blue-dominated pixels."""
oceanmask(day) = Float32[(Makie.blue(c) > Makie.red(c) + 0.02 && Makie.blue(c) > Makie.green(c)) for c in day]

"""
    earth!(scene; day, ocean) -> NamedTuple of plots

The Earth (radius 1, at the origin): land matte, water glossy (a clear coat
over the day colour), inside a shell of `Atmosphere`.
"""
function earth!(scene, mesh; day, ocean = oceanmask(day), atmosphere = Atmosphere())
    albedo = Hikari.Texture(RayMakie.to_spectrum(day))
    land = Hikari.Diffuse(Kd = albedo)
    water = Hikari.CoatedDiffuse(reflectance = albedo, roughness = 0.06f0, eta = 1.33f0)
    surface = Hikari.MixMaterialSpec(land, water, Hikari.Texture(ocean))
    planet = mesh!(scene, mesh; material = surface)
    air = air!(scene, atmosphere)
    return (; planet, air)
end

"""The shell of air around the planet: an invisible boundary with `atmosphere` inside; none for `nothing`."""
air!(scene, atmosphere::Atmosphere) =
    mesh!(scene, Sphere(Point3f(0), atmosphere.top); visible = false, transparency = true,
          material = Hikari.MediumInterface(Hikari.NullMaterial(); inside = atmosphere, outside = nothing))
air!(scene, ::Nothing) = nothing

# ── the photo-real planet: NASA's maps ──────────────────────────────────────

const ASSETS = joinpath(@__DIR__, "..", "assets")

"""Every other pixel of `img` in both directions, `times` times."""
halve(img, times = 1) = times == 0 ? img : halve(img[1:2:end, 1:2:end], times - 1)

"""The brightness of a map pixel: grey as it is, colour by its red channel (the maps are grey stored as RGB)."""
level(c::Makie.Colors.AbstractGray) = Float32(Makie.Colors.gray(c))
level(c::Makie.Colors.AbstractRGB) = Float32(Makie.Colors.red(c))

"""NASA's maps of the Earth, equirectangular, rows from the North Pole down: day colour, water, clouds, city lights."""
function earth_maps()
    A = joinpath(ASSETS, "downloads", "nasa-visible-earth"); P = joinpath(ASSETS, "processed", "earth")
    # Floored at 0.015 per channel. With exactly-zero channels (500+ coastal water
    # texels off Brazil alone) the traced Earth showed pink and teal patches along
    # coasts; flat textures of the same colours on a test sphere did not, so the
    # cause in Hikari is not found yet. No real surface reflects exactly nothing.
    day = map(c -> Makie.RGBf(max(Float32(Makie.red(c)), 0.015f0), max(Float32(Makie.green(c)), 0.015f0),
                              max(Float32(Makie.blue(c)), 0.015f0)), load(joinpath(A, "world.200407.3x5400x2700_geo.tif")))
    water = level.((load(joinpath(P, "water_mask_naturalearth_5400x2700.png"))))
    clouds = level.((halve(load(joinpath(A, "cloud_combined_8192.tif")))))
    lights = level.((halve(load(joinpath(P, "BlackMarble_2016_gray_8192x4096.png")))))
    return (; day, water, clouds, lights)
end

"""A sphere mesh of `radius` with the globe's texture coordinates."""
shell(radius, n = 256) = (m = film.globe_mesh(n); GeometryBasics.Mesh(Point3f.(coordinates(m) .* Float32(radius)), faces(m);
                                                                    normal = normals(m), uv = texturecoordinates(m)))

"""
    photoreal_earth!(scene, maps; citylights, atmosphere)

The Earth (radius 1): land matte and water glossy, city lights glowing (seen
on the night side, where the sun does not drown them), a cloud shell just
above, and the air around it all.
"""
function photoreal_earth!(scene, maps; citylights = 0.6f0, clouds = true, atmosphere = Atmosphere())
    albedo = Hikari.Texture(RayMakie.to_spectrum(maps.day))
    surface = Hikari.MixMaterialSpec(Hikari.Diffuse(Kd = albedo),
                                     Hikari.CoatedDiffuse(reflectance = albedo, roughness = 0.06f0, eta = 1.33f0), Hikari.Texture(maps.water))
    planet = mesh!(scene, shell(1); material = lit(surface, maps.lights, citylights))
    sky = clouds ? cloudshell!(scene, maps.clouds) : nothing
    return (; planet, clouds = sky, air = air!(scene, atmosphere))
end

"""`surface` with the city lights glowing from it, `strength` bright; as it is for no lights."""
lit(surface, lights, strength) = strength <= 0 ? surface :
    Hikari.MediumInterface(surface; emission = Hikari.Emissive(Le = Hikari.Texture([Hikari.RGBSpectrum(strength * l, 0.75f0 * strength * l,
                                                                                                         0.45f0 * strength * l) for l in lights])))

"""White clouds on a shell just above the ground, see-through where the map has none."""
function cloudshell!(scene, clouds)
    tex = Hikari.Texture([Hikari.RGBSpectrum(1f0, 1f0, 1f0, clamp(1.3f0 * c - 0.1f0, 0f0, 1f0)) for c in clouds])
    return mesh!(scene, shell(1.006); material = Hikari.Diffuse(Kd = tex))
end

"""A traced still of the photo-real Earth from `eye`, lit by a sun in direction `sun` (towards the sun)."""
function earth_still(maps; size = (1280, 720), samples = 256, eye = Vec3f(2.6, -2.2, 0.9), lookat = Vec3f(0), fov = 30,
                     sun = Vec3f(0.82, 0.57, 0.25), brightness = 3f0, hw_accel = false, kw...)
    sc = Scene(; size, backgroundcolor = RGBf(0, 0, 0),
               lights = [Makie.AmbientLight(RGBf(0.002, 0.002, 0.003)),
                         Makie.DirectionalLight(RGBf(brightness, brightness, 0.97f0 * brightness), -LinearAlgebra.normalize(Vec3f(sun)))])
    cam3d!(sc; center = false)
    photoreal_earth!(sc, maps; kw...)
    update_cam!(sc, Vec3f(eye), Vec3f(lookat), Vec3f(0, 0, 1))
    cameracontrols(sc).fov[] = fov
    update_cam!(sc, cameracontrols(sc))
    RayMakie.activate!(rasterize = false)
    # hw_accel off: the hardware RT pipeline has no any-hit stage yet, so it would treat the clouds' alpha as opaque
    return colorbuffer(sc; backend = RayMakie, samples, max_depth = 16, hw_accel)
end

"""`img` averaged down to `h` × `w` pixels (each output pixel the mean of the source pixels it covers)."""
function shrink(img::AbstractMatrix, h, w)
    H, W = size(img)
    out = similar(img, float(eltype(img)), h, w)
    Threads.@threads for j in 1:w
        c0, c1 = floor(Int, (j - 1) * W / w) + 1, floor(Int, j * W / w)
        for i in 1:h
            r0, r1 = floor(Int, (i - 1) * H / h) + 1, floor(Int, i * H / h)
            block = view(img, r0:r1, c0:c1)
            out[i, j] = sum(block) / length(block)
        end
    end
    return out
end

"""
The film's Earth maps, `w` × `w÷2`, written to assets/earth as PNGs (day
colour, water, clouds, city lights): small enough to ship with the repository
and the farm jobs, sharp enough for a globe filling the frame.
"""
function export_earth_maps(; w = 2700, dir = joinpath(ASSETS, "earth"))
    m = earth_maps()
    mkpath(dir)
    h = w ÷ 2
    save(joinpath(dir, "day.png"), map(c -> Makie.RGB{Makie.Colors.N0f8}(clamp.((c.r, c.g, c.b), 0, 1)...), shrink(m.day, h, w)))
    for (name, a) in (("water", m.water), ("clouds", m.clouds), ("lights", m.lights))
        save(joinpath(dir, name * ".png"), Makie.Colors.Gray{Makie.Colors.N0f8}.(clamp.(shrink(a, h, w), 0, 1)))
    end
    return readdir(dir; join = true)
end
