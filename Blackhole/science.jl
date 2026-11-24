# The science behind the pictures: a model black hole image, the Event Horizon
# Telescope's stations, the "notes" (Fourier samples) each pair of them hears as
# the Earth turns, and pictures made from those notes alone.
#
# Angles on the sky in microarcseconds (µas), baselines in metres, uv in
# wavelengths. One microarcsecond is 4.848e-12 radians.

using LinearAlgebra

const UAS = Float64(π) / 180 / 3600 / 1e6     # radians per microarcsecond
const LAMBDA = 1.3e-3                          # metres: the EHT observes at 230 GHz

# ── the picture ─────────────────────────────────────────────────────────────

"""A square image grid: `n` pixels a side, `fov` µas across, centred on the black hole."""
struct ImageGrid
    n::Int
    fov::Float64
end
pixel(g::ImageGrid) = g.fov / g.n
coords(g::ImageGrid) = [(-g.fov / 2 + (k - 0.5) * pixel(g)) for k in 1:g.n]

"""
    Ring(; radius, width, brightness, angle, floor)

A crescent like M87*'s: a ring of `radius` µas and Gaussian `width`, brighter
by `brightness` (0..1) towards `angle` (radians, from +y towards +x), with a
faint `floor` inside the shadow.
"""
Base.@kwdef struct Ring
    radius::Float64 = 21.0
    width::Float64 = 3.5
    brightness::Float64 = 0.6
    angle::Float64 = π            # brighter below, as in M87*
    floor::Float64 = 0.02
end

"""The image of `ring` on grid `g`, summing to 1, as a matrix indexed [x, y]."""
function image(ring::Ring, g::ImageGrid)
    xs = coords(g)
    img = [begin
               r = hypot(x, y)
               θ = atan(x, y)
               ringpart = exp(-(r - ring.radius)^2 / (2 * ring.width^2)) *
                          (1 + ring.brightness * cos(θ - ring.angle))
               inside = ring.floor * exp(-r^2 / (2 * (0.6 * ring.radius)^2))
               ringpart + inside
           end for x in xs, y in xs]
    return img ./ sum(img)
end

"""The image blurred by a Gaussian of full width at half maximum `fwhm` µas (what a telescope of that resolution sees)."""
function blurred(img::AbstractMatrix, g::ImageGrid, fwhm)
    σ = fwhm / 2.355 / pixel(g)
    r = ceil(Int, 4σ)
    k = [exp(-t^2 / (2σ^2)) for t in -r:r]
    k ./= sum(k)
    n = size(img, 1)
    pass(A) = [sum(k[m+r+1] * A[clamp(i + m, 1, n), j] for m in -r:r) for i in 1:n, j in 1:n]
    out = permutedims(pass(permutedims(pass(img))))
    return out ./ sum(out)
end

# ── the stations ────────────────────────────────────────────────────────────

"""A telescope: its name, where it is (degrees, metres above sea level), and the place it is in."""
struct Station
    name::String
    place::String
    lat::Float64
    lon::Float64
    height::Float64
end

"""The Event Horizon Telescope's sites (approximate coordinates)."""
const EHT = [
    Station("SMA", "Hawaii", 19.824, -155.478, 4115),
    Station("JCMT", "Hawaii", 19.823, -155.477, 4120),
    Station("SMT", "Arizona", 32.702, -109.891, 3185),
    Station("KP", "Arizona", 31.954, -111.613, 1914),
    Station("LMT", "Mexico", 18.986, -97.315, 4640),
    Station("ALMA", "Chile", -23.029, -67.755, 5058),
    Station("APEX", "Chile", -23.006, -67.759, 5104),
    Station("PV", "Spain", 37.066, -3.393, 2850),
    Station("NOEMA", "France", 44.634, 5.907, 2550),
    Station("GLT", "Greenland", 76.535, -68.686, 100),
    Station("SPT", "South Pole", -89.99, -45.0, 2800),
]

"""Earth-centred position (metres) of a station: WGS84."""
function ecef(s::Station)
    a, f = 6378137.0, 1 / 298.257223563
    e2 = f * (2 - f)
    φ, λ = deg2rad(s.lat), deg2rad(s.lon)
    N = a / sqrt(1 - e2 * sin(φ)^2)
    return [(N + s.height) * cos(φ) * cos(λ), (N + s.height) * cos(φ) * sin(λ), (N * (1 - e2) + s.height) * sin(φ)]
end

"""M87*: right ascension and declination (degrees)."""
const M87 = (ra = 187.70593, dec = 12.39112)

"""The source's elevation (radians) seen from station `s` when the Greenwich hour angle of the source is `H` (radians)."""
function elevation(s::Station, H; source = M87)
    φ, δ = deg2rad(s.lat), deg2rad(source.dec)
    h = H + deg2rad(s.lon)                  # local hour angle
    return asin(sin(φ) * sin(δ) + cos(φ) * cos(δ) * cos(h))
end

"""
    uv(a, b, H; source, λ) -> (u, v)

The note the pair `a`–`b` hears at Greenwich hour angle `H`: the baseline
projected onto the sky, in wavelengths.
"""
function uv(a::Station, b::Station, H; source = M87, λ = LAMBDA)
    bx, by, bz = ecef(b) .- ecef(a)
    δ = deg2rad(source.dec)
    u = (bx * sin(H) + by * cos(H)) / λ
    v = (-bx * sin(δ) * cos(H) + by * sin(δ) * sin(H) + bz * cos(δ)) / λ
    return u, v
end

"""
    tracks(stations, Hs; minel) -> Vector{(a, b, H, u, v)}

Every note heard over the hour angles `Hs`: each pair, at each hour angle when
the source stands at least `minel` above both stations' horizons. Both (u, v)
and its mirror image are notes of a real picture; the mirror is added where
pictures are made.
"""
function tracks(stations, Hs; minel = deg2rad(15), source = M87)
    out = NamedTuple{(:a, :b, :H, :u, :v),Tuple{Int,Int,Float64,Float64,Float64}}[]
    for i in eachindex(stations), j in i+1:lastindex(stations), H in Hs
        a, b = stations[i], stations[j]
        # two dishes on one mountain hear (almost) the same note as one dish
        norm(ecef(a) .- ecef(b)) < 50e3 && continue
        (elevation(a, H; source) > minel && elevation(b, H; source) > minel) || continue
        u, v = uv(a, b, H; source)
        push!(out, (a = i, b = j, H, u, v))
    end
    return out
end

# ── the notes of a picture, and pictures from notes ──────────────────────────

"""
    measure(g, uvs) -> Matrix{ComplexF64}

The measurement: row k is how the picture's pixels add up to the note at
`uvs[k]` (a Fourier component). Each note `V = Σ I(x, y) e^{-2πi(ux + vy)}`.
"""
function measure(g::ImageGrid, uvs)
    xs = coords(g) .* UAS
    pix = [(x, y) for x in xs, y in xs]
    return [cis(-2π * (u * p[1] + v * p[2])) for (u, v) in uvs, p in vec(pix)]
end

"""The notes `A * image` the telescopes hear."""
notes(A, img) = A * vec(img)

"""
    dirty(A, V, g) -> Matrix

The picture from the notes alone, no guessing: every heard note played back
(and its mirror), summed. What a dish with gaps in it would show.
"""
function dirty(A, V, g::ImageGrid)
    img = real.(A' * V)
    img = reshape(img, g.n, g.n)
    return img ./ maximum(img)
end

"""
    samefit(A, img, other) -> Matrix

A picture that makes exactly the same notes as `img`, but otherwise looks like
`other`: `other` with its heard notes replaced by `img`'s. Proof by
construction that the notes alone do not decide the picture.
"""
function samefit(A, img, other)
    # Real and imaginary parts as separate real equations: images are real.
    R = vcat(real.(A), imag.(A))
    # An orthonormal basis of exactly what the notes see. R is rank deficient
    # (a note and its mirror are the same equation), and a QR basis fills the
    # missing rank with arbitrary directions: they added pixel noise and pulled
    # every picture towards `img`.
    F = svd(R')
    Q = F.U[:, F.S .> 1e-9 * F.S[1]]
    x, y = vec(img), vec(other)
    z = y .- Q * (Q' * y) .+ Q * (Q' * x)        # other's unseen part, img's seen part
    return reshape(z, size(img))
end
