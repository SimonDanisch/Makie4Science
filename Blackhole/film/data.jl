# The computed data the beats show, cached in `../data` as plain arrays (each
# clip's recipe is its own module, so nothing with a module-local type is stored).

using Serialization

const DATA = joinpath(@__DIR__, "..", "data")

"""The value `f()` computes, kept on disk under `name` after the first time."""
function cached(f, name)
    path = joinpath(DATA, name * ".jls")
    isfile(path) && return deserialize(path)
    mkpath(DATA)
    v = f()
    serialize(path, v)
    return v
end

"""The image grid every picture is drawn on: 96 pixels, 120 µas across."""
const GRID = ImageGrid(96, 120.0)

"""The model of M87*'s ring, sharp."""
model_ring() = image(Ring(), GRID)

"""A wider grid at the same pixel size, for the ring shown across a whole frame: its blur reaches past GRID's edges."""
const WIDE = ImageGrid(256, 320.0)

"""Limits for `ax` so that `fov` µas of height fill the `canvas`; returns the extent of a picture on `WIDE`."""
function fullframe!(ax, canvas; fov = 120)
    W, H = canvas
    limits!(ax, -fov / 2 * W / H, fov / 2 * W / H, -fov / 2, fov / 2)
    return (-WIDE.fov / 2, WIDE.fov / 2)
end

"""The EHT's resolution: about 20 µas (wavelength over the Earth's width)."""
const EHT_BLUR = 20.0

"""The hour angles of one night's observing: M87* above the horizon for most sites, every 10 minutes."""
night() = range(-1.6, 1.9; length = 120)

"""
The notes heard over one night, as `(a, b, H, u, v)` rows (stations by index
into `EHT`): plain numbers, cached.
"""
night_notes() = cached("night_notes") do
    [(t.a, t.b, t.H, t.u, t.v) for t in tracks(EHT, night())]
end

"""The notes as (u, v) points, each with its mirror (a real picture's notes come in pairs)."""
uv_points(rows) = vcat([(r[4], r[5]) for r in rows], [(-r[4], -r[5]) for r in rows])

"""Bright spots on a circle, brighter towards the bottom like the ring: fine detail and little else."""
function spots(g::ImageGrid; n = 8, radius = 21.0, size = 2.5)
    θs = range(0, 2π; length = n + 1)[1:n]
    img = [sum((1 - 0.6sin(θ)) * exp(-((x - radius * cos(θ))^2 + (y - radius * sin(θ))^2) / (2size^2)) for θ in θs)
           for x in coords(g), y in coords(g)]
    return img ./ sum(img)
end

"""
Pictures that all make exactly the same notes as the model ring: the ring,
and other pictures with the ring's heard notes put in. Cached.
"""
same_notes_pictures() = cached("same_notes_v2") do
    A = measure(GRID, uv_points(night_notes()))
    truth = model_ring()
    # pictures whose fine detail differs: detail smaller than the notes can
    # resolve survives in them, the coarse shape becomes the ring's
    others = [spots(GRID), image(Ring(width = 1.0), GRID),
              image(Ring(radius = 17, width = 1.0), GRID) .+ image(Ring(radius = 25, width = 1.0, angle = 0.0), GRID)]
    pictures = [samefit(A, truth, o) for o in others]
    (truth = truth, dirty = dirty(A, notes(A, truth), GRID), pictures = pictures)
end
