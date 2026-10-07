# Lens images of point sources: the Airy pattern, its pixels, and smear on a sensor.

"""Bessel function J₁ by Bessel's integral, (1/π)∫₀^π cos(τ - x sin τ) dτ (midpoint rule)."""
function besselj1(x; n = 96)
    h = Float32(π) / n
    return sum(cos((k - 0.5f0) * h - x * sin((k - 0.5f0) * h)) for k in 1:n) * h / Float32(π)
end

"""
The Airy pattern of a round lens at f-number `N`: relative intensity at
distance `r` (wavelengths) from the centre. First dark ring at 1.22 N.
"""
function airy(r, N)
    x = Float32(π) * r / N
    return abs(x) < 1f-4 ? 1f0 : (2f0 * besselj1(x) / x)^2
end

"""
    sensor_image(N, npix; pitch, oversample) -> Matrix{Float32}

The pixels (`npix` × `npix`, `pitch` wavelengths wide) a star makes through a
round lens at f-number `N`: the Airy pattern averaged over each pixel.
"""
function sensor_image(N, npix; pitch = 1f0, oversample = 5)
    c = (npix + 1) / 2
    offs = [((k - 0.5f0) / oversample - 0.5f0) * pitch for k in 1:oversample]
    return [sum(airy(hypot((i - c) * pitch + ox, (j - c) * pitch + oy), N) for ox in offs, oy in offs) / oversample^2
            for i in 1:npix, j in 1:npix]
end

"""
The Airy pattern at f-number `N` tabulated out to `reach` (wavelengths), for
adding up many stars quickly: `profile(r)` interpolates it, 0 beyond.
"""
struct AiryProfile
    step::Float32
    values::Vector{Float32}
end

AiryProfile(N; reach = 6f0 * N, step = 0.02f0) = AiryProfile(step, [airy(r, N) for r in 0f0:step:reach])

function (a::AiryProfile)(r)
    u = r / a.step + 1
    i = floor(Int, u)
    i >= length(a.values) && return 0f0
    t = u - i
    return (1 - t) * a.values[i] + t * a.values[i+1]
end

"""
    blurred(stars, profile, npix; pitch) -> Matrix{Float32}

A field of `stars` ((x, y, brightness), in wavelengths on the sensor) as the
pixels record it: every star replaced by the lens's spot `profile` (an
`AiryProfile`), all of them added.
"""
function blurred(stars, profile::AiryProfile, npix; pitch = 1f0)
    img = zeros(Float32, npix, npix)
    for (sx, sy, b) in stars, j in 1:npix, i in 1:npix
        img[i, j] += b * profile(hypot((i - 0.5f0) * pitch - sx, (j - 0.5f0) * pitch - sy))
    end
    return img
end

"""A random cluster of `n` stars in a `size`-wide field (wavelengths), some in close pairs."""
function cluster(n, size; seed = 7)
    rng = Random.Xoshiro(seed)
    stars = Tuple{Float32,Float32,Float32}[]
    for _ in 1:n
        x, y = size .* (0.1f0 .+ 0.8f0 .* rand(rng, Float32, 2))
        push!(stars, (x, y, 0.3f0 + 0.7f0 * rand(rng, Float32)))
        # every third one gets a close companion
        rand(rng) < 1 / 3 && push!(stars, (x + 3f0 + 3f0 * rand(rng, Float32), y + 2f0 * rand(rng, Float32) - 1f0,
                                         0.3f0 + 0.7f0 * rand(rng, Float32)))
    end
    return stars
end

const DARK = (backgroundcolor = :black, xgridvisible = false, ygridvisible = false,
              leftspinevisible = false, rightspinevisible = false, topspinevisible = false,
              bottomspinevisible = false, xticksvisible = false, yticksvisible = false,
              xticklabelsvisible = false, yticklabelsvisible = false, titlecolor = :white,
              titlesize = 24, aspect = DataAspect())

"""
Pixel values (0..1) in the light's green, burning to white where bright like
the wave glow; `γ` lifts faint values (the rings) into view.
"""
glow_pixels(img; γ = 0.45f0) = map(img) do v
    s = clamp(v, 0f0, 1f0)^γ
    hot = 0.6f0 * s^3
    Makie.RGBf(SUNLIGHT[1] * s + (1 - SUNLIGHT[1]) * hot, SUNLIGHT[2] * s + (1 - SUNLIGHT[2]) * hot,
               SUNLIGHT[3] * s + (1 - SUNLIGHT[3]) * hot)
end

const PIXEL_UM = 4f0

"""
What one star looks like on the camera's pixels at f-number `N`, the lens's
smear `smear` µm across (an rms diameter): the wave's spot (an Airy pattern
for green light) blurred by the smear, taken as round, on `npix`×`npix`
pixels of `PIXEL_UM` µm, summing to 1.
"""
function star_on_pixels(N, smear; npix = 15, sub = 8, λµm = 0.55f0)
    h = PIXEL_UM / sub                          # µm per sample
    n = npix * sub
    c = (n + 1) / 2
    wave = [airy(hypot((i - c) * h, (j - c) * h) / λµm, N) for i in 1:n, j in 1:n]
    # the smear as a round Gaussian with the same rms diameter, applied along both axes
    σ = max(smear / 2 / sqrt(2f0), 0.3f0)
    k = [exp(-(t * h / σ)^2 / 2) for t in -ceil(Int, 3σ / h):ceil(Int, 3σ / h)]
    k ./= sum(k)
    blur1(A, dim) = mapslices(v -> [sum(k[m] * v[clamp(i + m - (length(k) + 1) ÷ 2, 1, n)] for m in eachindex(k)) for i in 1:n], A; dims = dim)
    img = blur1(blur1(wave, 1), 2)
    px = [sum(img[(i-1)*sub+1:i*sub, (j-1)*sub+1:j*sub]) for i in 1:npix, j in 1:npix]
    return px ./ sum(px)
end

"""Only the lens's smear on the pixels: the star as a lens without the wave (a vanishing f-number) would put it."""
smear_on_pixels(smear; npix = 15) = star_on_pixels(1f-4, smear; npix)

"""
What is left of the lens smear: where the three-lens camera lens of the lens
beat (`d.lenses[2]`) puts the light from `θ` to the side, through its whole
round opening (`bundle_spot`): (y, z) in mm from the centroid, y away from the
picture's centre; and its f-number.
"""
struct Leftover
    spot::Vector{Point2f}
    N::Float32
end


"""
The lens smear on the pixels, and the result: the bundle's landing points
counted on a grid `sub` samples to a pixel; the result is that spread again by
the wave's spot (an Airy pattern at the lens's f-number, out to its first few
rings); both summed into `npix`×`npix` pixels of `PIXEL_UM` µm. Rows run away
from the picture's centre, columns across.
"""
function spot_pixel_tiles(lo::Leftover; npix = 41, sub = 8, λµm = 0.55f0, reach_um = 12f0)
    h = PIXEL_UM / sub
    n = npix * sub
    c = (n + 1) / 2
    fine = zeros(Float32, n, n)
    for p in lo.spot
        i, j = round(Int, c + 1000f0 * p[1] / h), round(Int, c + 1000f0 * p[2] / h)
        1 <= i <= n && 1 <= j <= n && (fine[i, j] += 1f0)
    end
    m = ceil(Int, reach_um / h)
    wave = [airy(hypot(a * h, b * h) / λµm, lo.N) for a in -m:m, b in -m:m]
    wave ./= sum(wave)
    both = zeros(Float32, n, n)
    for j in 1:n, i in 1:n
        v = fine[i, j]
        v > 0 || continue
        for b in -m:m, a in -m:m
            1 <= i + a <= n && 1 <= j + b <= n && (both[i+a, j+b] += v * wave[a+m+1, b+m+1])
        end
    end
    pixels(A) = (P = [sum(A[(i-1)*sub+1:i*sub, (j-1)*sub+1:j*sub]) for i in 1:npix, j in 1:npix]; P ./ sum(P))
    return pixels(fine), pixels(both)
end

"""
How the bundle's light spreads along the sensor, away from the picture's
centre: its landing points counted in bins `h` mm wide, as (bin centres,
counts) for `light_profile`.
"""
function along_sensor(spot; h = 0.0005f0)
    counts = Dict{Int,Float32}()
    for p in spot
        k = round(Int, p[1] / h)
        counts[k] = get(counts, k, 0f0) + 1f0
    end
    ks = sort!(collect(keys(counts)))
    return h .* Float32.(ks), [counts[k] for k in ks]
end

"""
How a fan's light lands along the sensor at the heights `ys` (mm, relative to
the fan's centre): each ray landing at `hits` carries its `weight` of the
light, spread over `σ` mm. Not binned into pixels, so a focus shows as a needle.
"""
light_profile(hits, weights, ys; σ = 0.12f0) =
    Float32[sum(w * exp(-((y - h) / σ)^2) for (h, w) in zip(hits, weights); init = 0f0) / (sum(weights) * σ * sqrt(Float32(π)))
            for y in ys]

"""Where the rays of the fan at field angle `θ` (colour `λ`) land on `lens`'s sensor: heights in mm."""
landing_heights(lens::CameraLens, θ; λ = 1f0, n = 301) = first(landing(lens, θ; λ, n))

"""
    landing(lens, θ; λ, n) -> (heights, weights)

Where the rays of the fan land on the sensor, and how much light each
carries. Straight ahead a round lens is the same all round, so a ray `r` from
the middle of the opening stands for a ring of it, and carries light in
proportion to `r`; to the side it is not, and each ray carries the same.
"""
function landing(lens::CameraLens, θ; λ = 1f0, n = 301)
    paths, _ = ray_fans(lens.sys, (θ,); D = lens.D, stop = lens.stop, n, λ)
    xf = lens.sys.sensor
    arrived = [abs(p[end][1] - xf) < 1f-3 for p in paths]
    rings = iszero(θ) ? abs.(collect(Float32, range(-lens.D / 2, lens.D / 2; length = n))) : ones(Float32, n)
    return Float32[p[end][2] for p in paths[arrived]], rings[arrived]
end
