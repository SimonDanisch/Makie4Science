# Experiment: the Chajnantor plateau, 5000 m up in the Atacama desert, where
# ALMA stands. A flat plain of reddish gravel around the antenna, gentle swells
# further out, rocks strewn about, snow-capped volcanoes on the horizon, under
# a physical sun and sky. Run in the Science4Makie environment after
# `film = loadfilm()`; lengths in metres, z up, the antenna at the origin.

using LinearAlgebra: norm
import LinearAlgebra
using GeometryBasics, Random

"""Grid coordinate s ∈ [-1, 1] to metres: centimetres apart at the antenna, hundreds of metres at the horizon."""
spread(s; L = 12000f0, a = 9f0) = L * sinh(a * s) / sinh(a)

"""The volcanoes on the horizon: where (m), how high above the plain, how wide at the foot."""
const VOLCANOES = [(Point2f(-5200, 7400), 900f0, 3200f0), (Point2f(-1500, 9200), 650f0, 2600f0),
                   (Point2f(2600, 8600), 1100f0, 3600f0), (Point2f(-8800, 2500), 700f0, 3000f0),
                   (Point2f(7800, 5200), 800f0, 3400f0), (Point2f(-7400, -5600), 950f0, 3300f0),
                   (Point2f(6200, -7600), 600f0, 2800f0), (Point2f(9800, -1200), 750f0, 3000f0)]

noise(x, y, scale, seed) = film.fbm(Vec3f(x / scale, y / scale, 0.37f0 * seed), Int32(seed))

"""One volcano's height at (x, y): a steep cone with a rounded top, a shallow crater, and gullies down its sides."""
function volcano(x, y, (c, H, R))
    d = norm(Point2f(x, y) - c)
    d > R && return 0f0
    cone = H * (1 - d / R)^1.6f0
    crater = 0.06f0 * H * exp(-(d / (0.06f0 * R))^2)
    gullies = 0.08f0 * H * (noise(x, y, 0.07f0 * R, 11) - 0.5f0) * (d / R)
    return max(cone - crater + gullies, 0f0)
end

"""The ground's height at (x, y): flat by the antenna, swelling further out, volcanoes far away."""
function ground_height(x, y)
    r = sqrt(x^2 + y^2)
    ripples = 0.006f0 * (noise(x, y, 0.35f0, 1) - 0.5f0) + 0.05f0 * (noise(x, y, 6f0, 7) - 0.5f0)
    swells = 3f0 * (noise(x, y, 160f0, 2) - 0.5f0) * film.smoothstep(25f0, 250f0, r)
    hills = 60f0 * max(noise(x, y, 1800f0, 3) - 0.45f0, 0f0) * film.smoothstep(800f0, 3000f0, r)
    return ripples + swells + hills + sum(v -> volcano(x, y, v), VOLCANOES)
end

"""The ground's colour at (x, y), linear RGB: reddish-brown gravel in patches, finer speckle near by, dark rock on the volcanoes with snow on top, hazier far off."""
function ground_colour(x, y, h)
    base = Vec3f(0.33f0, 0.22f0, 0.15f0)
    patches = noise(x, y, 35f0, 4)
    red = noise(x, y, 220f0, 5)
    c = base .* (0.75f0 + 0.5f0 * patches) .* Vec3f(1f0 + 0.25f0 * (red - 0.5f0), 1f0, 1f0 - 0.2f0 * (red - 0.5f0))
    speckle = film.hash01(unsafe_trunc(Int32, floor(x / 0.05f0)), unsafe_trunc(Int32, floor(y / 0.05f0)), Int32(0), Int32(9))
    c = c .* (0.6f0 + 0.8f0 * speckle)
    rock = film.smoothstep(60f0, 250f0, h)
    c = (1 - rock) .* c .+ rock .* Vec3f(0.16f0, 0.1f0, 0.08f0) .* (0.7f0 + 0.6f0 * noise(x, y, 150f0, 8))
    snow = film.smoothstep(620f0, 720f0, h + 260f0 * (noise(x, y, 350f0, 6) - 0.5f0))
    c = (1 - snow) .* c .+ snow .* Vec3f(0.8f0, 0.82f0, 0.86f0)
    haze = film.smoothstep(2000f0, 14000f0, sqrt(x^2 + y^2))
    return (1 - 0.3f0 * haze) .* c .+ 0.3f0 * haze .* Vec3f(0.3f0, 0.4f0, 0.55f0)
end

"""
    plateau(n, texels) -> (; mesh, albedo)

The ground as one mesh, `n` × `n` vertices on the `spread` grid, with an albedo
texture laid out on the same grid (so it too is fine near the antenna).
"""
function plateau(n = 1024, texels = 2048)
    ss = range(-1f0, 1f0; length = n)
    P = [Point3f(spread(sx), spread(sy), ground_height(spread(sx), spread(sy))) for sy in ss for sx in ss]
    UV = [Vec2f((sx + 1) / 2, (sy + 1) / 2) for sy in ss for sx in ss]
    F = GLTriangleFace[]
    for j in 1:n-1, i in 1:n-1
        a = (j - 1) * n + i
        push!(F, GLTriangleFace(a, a + 1, a + n + 1), GLTriangleFace(a, a + n + 1, a + n))
    end
    mesh = GeometryBasics.Mesh(P, F; normal = GeometryBasics.normals(P, F), uv = UV)
    # Hikari samples texel [i, j] at v = 1 - (i - ½)/rows, u = (j - ½)/cols
    t = texels
    albedo = Matrix{Hikari.RGBSpectrum}(undef, t, t)
    Threads.@threads for i in 1:t
        sy = 2f0 * (1f0 - (i - 0.5f0) / t) - 1f0
        for j in 1:t
            sx = 2f0 * ((j - 0.5f0) / t) - 1f0
            x, y = spread(sx), spread(sy)
            c = ground_colour(x, y, ground_height(x, y))
            albedo[i, j] = Hikari.RGBSpectrum(c[1], c[2], c[3])
        end
    end
    return (; mesh, albedo)
end

"""An angular rock, about 1 m across: a coarse sphere pushed in and out by noise, every facet flat (its own normal)."""
function rock(seed)
    m = normal_mesh(Tesselation(Sphere(Point3f(0), 0.5f0), 9))
    lumpy = map(coordinates(m)) do p
        k = 1f0 + 0.9f0 * (film.fbm(Vec3f(p) * 1.6f0 + Vec3f(seed), Int32(seed)) - 0.5f0)
        Point3f(p[1] * k * 1.15f0, p[2] * k * 0.9f0, 0.7f0 * p[3] * k)
    end
    P = Point3f[]; N = Vec3f[]; F = GLTriangleFace[]
    for f in faces(m)
        a, b, c = lumpy[f[1]], lumpy[f[2]], lumpy[f[3]]
        n = LinearAlgebra.normalize(LinearAlgebra.cross(b - a, c - a))
        k = length(P)
        append!(P, (a, b, c)); append!(N, (n, n, n))
        push!(F, GLTriangleFace(k + 1, k + 2, k + 3))
    end
    return GeometryBasics.Mesh(P, F; normal = N)
end

"""Rocks strewn around the antenna (none right under it): positions, sizes and turns."""
function rocks(n = 450; seed = 3)
    s = Random.Xoshiro(seed)
    pos = Point3f[]; scale = Vec3f[]; rot = Makie.Quaternionf[]; colour = RGBf[]
    while length(pos) < n
        r = 8 + 220 * rand(s)^2; θ = 2π * rand(s)
        x, y = Float32(r * cos(θ)), Float32(r * sin(θ))
        size = Float32(0.12 + 1.4 * rand(s)^3)
        push!(pos, Point3f(x, y, ground_height(x, y) - 0.1f0 * size))
        push!(scale, Vec3f(size * (0.8 + 0.4rand(s)), size * (0.8 + 0.4rand(s)), size))
        push!(rot, Makie.qrotation(Vec3f(0, 0, 1), Float32(2π * rand(s))))
        g = Float32(0.13 + 0.14 * rand(s))
        push!(colour, RGBf(1.25f0 * g, g, 0.85f0 * g))
    end
    return (; pos, scale, rot, colour)
end

"""
    chajnantor!(scene; sun, turbidity, intensity)

The plateau, its rocks, the sun and the sky. `sun` points towards the sun.
"""
function chajnantor!(scene; ground = plateau())
    mesh!(scene, ground.mesh; material = Hikari.Diffuse(Kd = Hikari.Texture(ground.albedo), σ = 25f0))
    # four rock shapes, each strewn a quarter of the rocks
    r = rocks()
    for k in 1:4
        i = k:4:length(r.pos)
        meshscatter!(scene, r.pos[i]; marker = rock(4k + 1), markersize = r.scale[i], rotation = r.rot[i], color = r.colour[i])
    end
    return scene
end

"""A traced still of an ALMA antenna on the plateau."""
function alma_on_plateau(file; ground = plateau(), size = (1280, 720), samples = 256, eye = Vec3f(10, -9, 1.6),
                         lookat = Vec3f(1.1, 1.2, 3.2), fov = 40, sun = Vec3f(0.35, -0.75, 0.45), turbidity = 2f0,
                         intensity = 1f0)
    sc = Scene(; size, lights = [Makie.SunSkyLight(sun; intensity, turbidity, ground_enabled = false)])
    cam3d!(sc; center = false)
    antennas!(sc)
    chajnantor!(sc; ground)
    update_cam!(sc, eye, lookat, Vec3f(0, 0, 1))
    cameracontrols(sc).fov[] = fov
    update_cam!(sc, cameracontrols(sc))
    RayMakie.activate!(rasterize = false)
    save(file, colorbuffer(sc; backend = RayMakie, samples, max_depth = 12))
    return file
end

"""Where more antennas of the array stand, and which way each faces (radians about z); all point at the same spot in the sky."""
const ARRAY = [(Point2f(-38, 62), 0f0), (Point2f(-95, 30), 0f0), (Point2f(30, 120), 0f0), (Point2f(-160, 140), 0f0)]

"""The antenna model, and more of them standing on the plateau as the array."""
function antennas!(scene; array = ARRAY)
    model = FileIO.load(File{format"GLB"}(abspath("assets/downloads/nrao-ar-models/alma.glb")))
    mesh!(scene, model)
    for (p, θ) in array
        a = mesh!(scene, model)
        translate!(a, p[1], p[2], ground_height(p[1], p[2]))
        rotate!(a, Vec3f(0, 0, 1), θ)
    end
    return scene
end
