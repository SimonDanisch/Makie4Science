# Analytic light fields on a plane: stars' spherical waves, far sources' flat
# wavefronts, and the crests a window picks out of them. No simulation.

"""A star in the plane: its position (world units), its light's colour."""
struct Star
    pos::Point2f
    tint::NTuple{3,Float32}
end

"""
Distance fog on a glowing plane: full strength out to `near` from the `eye`,
gone by `far`. The plane is made larger than the fog reaches, so it fades
into the dark before any edge shows, and reads as endless.
"""
struct Fog
    eye::Point3f
    near::Float32
    far::Float32
end

"""Fog for a camera `pose`: fading from just past what it looks at to about twice as far."""
function Fog(pose::Pose; near = 1.05f0, far = 1.9f0)
    L = norm(pose.eye - pose.lookat)
    return Fog(Point3f(pose.eye), near * L, far * L)
end

visibility(::Nothing, p) = 1f0

visibility(f::Fog, p) = 1f0 - smoothstep(f.near, f.far, norm(Point3f(p[1], p[2], 0) - f.eye))

"""
    star_glow(stars, g, t; λ, width, near, fog) -> Matrix{RGBSpectrum}

The crests of every star's spherical wave where it cuts the plane, at time `t`
(periods), each in its star's colour and added: thin bright rings `width`
wavelengths wide, full strength within `near` of the star and dimming beyond.
Much more gently than a real wave's 1/r: at a hundred units out the rings
still have to be seen. The sheet fades out over `margin` at its edges, and
with the distance `fog` (a `Fog`, or `nothing`).
"""
function star_glow(stars, g::Grid, t; λ = 1.5f0, width = 0.1f0, near = 3f0, gain = 1.4f0, margin = 12f0, fog = nothing)
    img = fill(Hikari.RGBSpectrum(0f0, 0f0, 0f0, 1f0), size(g))
    b = bounds(g)
    lo, hi = minimum(b), maximum(b)
    Threads.@threads for j in 1:size(g)[2]
        for i in 1:size(g)[1]
            p = cellcenter(g, i, j)
            # fade out towards the sheet's edges, so it has none
            edge = smoothstep(0f0, margin, min(p[1] - lo[1], hi[1] - p[1], p[2] - lo[2], hi[2] - p[2])) * visibility(fog, p)
            r_, g_, b_ = 0f0, 0f0, 0f0
            for s in stars
                r = norm(p - s.pos)
                ph = r / λ - t
                d = abs(ph - round(ph))                     # distance to a crest, in wavelengths
                a = edge * gain * exp(-(d / width)^2) * (near / max(r, near))^0.35f0
                r_ += a * s.tint[1]; g_ += a * s.tint[2]; b_ += a * s.tint[3]
            end
            img[i, j] = Hikari.RGBSpectrum(r_, g_, b_, 1f0)
        end
    end
    return img
end

"""
The crests of a star's wave near it, as bubbles: every third crest out to
`rmax`, each fading out (its index going to 1) as it grows past `rfade`.
"""
function crest_shells(t; λ = 1.5f0, every = 3, rmax = 24f0, rfade = 12f0)
    shells = Tuple{Float32,Float32}[]
    r = λ * mod(Float32(t), every)
    while r < rmax
        r > 0.5f0 && push!(shells, (r, 1f0 + 0.5f0 * (1f0 - smoothstep(rfade, rmax, r))))
        r += every * λ
    end
    return shells
end

"""
    window_glow(g, t, δ; λ, width, windows, faint, gain, base) -> Matrix{RGBSpectrum}

Far from two stars: the warm star's flat wavefronts straight ahead, the
blue star's tilted by `δ`, all crests faint (`faint`) at time `t`. Inside
each of the `windows`, one warm and one blue crest are drawn bright: the
two that pass nearest the window's centre, where they cross. Across a narrow
window they stay one line; across a wide one they end up half a wavelength
apart at its edges: two directions, clearly. `width` is a crest's width in
wavelengths; `base` a dim glow everywhere, so the gaps are not pitch black.
"""
function window_glow(g::Grid, t, δ; λ = 0.6f0, width = 0.07f0, windows = Rect2f[], faint = 0.3f0, gain = 1.6f0,
                     base = (0f0, 0f0, 0f0))
    img = fill(Hikari.RGBSpectrum(0f0, 0f0, 0f0, 1f0), size(g))
    dirs = (Vec2f(1, 0), Vec2f(cos(δ), sin(δ)))
    tints = (SUNLIGHT, SECONDARY_LIGHT)
    # per window, per star: the crest (phase number) nearest to its centre
    chosen = [[round(dot(Vec2f(minimum(w) + widths(w) / 2), d) / λ - t) for d in dirs] for w in windows]
    Threads.@threads for j in 1:size(g)[2]
        for i in 1:size(g)[1]
            p = cellcenter(g, i, j)
            k = findfirst(w -> p in w, windows)
            r_, g_, b_ = base
            for (s, (d, c)) in enumerate(zip(dirs, tints))
                ph = dot(Vec2f(p), d) / λ - t
                line = exp(-((ph - round(ph)) / width)^2)
                a = faint * line
                if k !== nothing
                    # the chosen crest, bright
                    a += gain * exp(-((ph - chosen[k][s]) / width)^2)
                end
                r_ += a * c[1]; g_ += a * c[2]; b_ += a * c[3]
            end
            img[i, j] = Hikari.RGBSpectrum(r_, g_, b_, 1f0)
        end
    end
    return img
end

"""Light from far away: flat waves travelling along `dir`."""
struct FarSource
    dir::Vec2f
end

"""Light from a point close by: circular waves from `pos`."""
struct NearSource
    pos::Point2f
end

"""How many wavelengths `λ` the wave from `s` has travelled to reach `p` (up to a constant)."""
travelled(s::FarSource, p, λ) = (p[1] * s.dir[1] + p[2] * s.dir[2]) / λ

travelled(s::NearSource, p, λ) = sqrt((p[1] - s.pos[1])^2 + (p[2] - s.pos[2])^2) / λ

"""
The slip between the waves of `a` and `b` across `window` (along y, through
its middle): how many wavelengths one falls behind the other from one side of
the window to the other.
"""
function slip(a, b, window::Rect2f, λ)
    x = minimum(window)[1] + widths(window)[1] / 2
    lo, hi = Point2f(x, minimum(window)[2]), Point2f(x, maximum(window)[2])
    return abs((travelled(a, hi, λ) - travelled(b, hi, λ)) - (travelled(a, lo, λ) - travelled(b, lo, λ)))
end

"""
    pair_window_glow(g, t, sources, window; λ, width, faint, gain)

Two sources' crests (sunlight and soft blue) at time `t`, faint; inside `window`
the one crest of each that passes nearest its middle drawn bright, so how far
they slip apart across it shows. Near sources also get a glowing dot.
"""
function pair_window_glow(g::Grid, t, sources, window::Rect2f; λ = 0.6f0, width = 0.07f0, faint = 0.35f0, gain = 1.8f0,
                          highlight = 1f0)
    img = fill(Hikari.RGBSpectrum(0f0, 0f0, 0f0, 1f0), size(g))
    tints = (SUNLIGHT, SECONDARY_LIGHT)
    mid = Point2f(minimum(window) + widths(window) / 2)
    chosen = [round(travelled(s, mid, λ) - t) for s in sources]
    Threads.@threads for j in 1:size(g)[2]
        for i in 1:size(g)[1]
            p = cellcenter(g, i, j)
            inside = p in window
            r_, g_, b_ = 0f0, 0f0, 0f0
            for (k, (s, c)) in enumerate(zip(sources, tints))
                ph = travelled(s, p, λ) - t
                a = faint * exp(-((ph - round(ph)) / width)^2)
                inside && (a += highlight * gain * exp(-((ph - chosen[k]) / width)^2))
                if s isa NearSource
                    d = sqrt((p[1] - s.pos[1])^2 + (p[2] - s.pos[2])^2)
                    a += 3f0 * exp(-(d / 0.25f0)^2)
                end
                r_ += a * c[1]; g_ += a * c[2]; b_ += a * c[3]
            end
            img[i, j] = Hikari.RGBSpectrum(r_, g_, b_, 1f0)
        end
    end
    return img
end
