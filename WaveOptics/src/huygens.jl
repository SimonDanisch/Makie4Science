# Huygens' picture of the focus: every point of the aperture sends out a
# wavelet, and the lens delays each one so that all of them arrive at the focus
# in step. Anywhere else they arrive with different delays, and the phasor sum
# (each wavelet an arrow of its phase, laid head to tail) shrinks.
#
# Analytic, in the same wavelength units as the simulation: cylindrical
# wavelets u = cos(2π(r - r_F) - 2πt) / √r, r the distance from the source, r_F
# its distance to the focus.

"""
    Wavelets(x, D, n, focus)

`n` point sources spread evenly over an aperture of width `D` at `x`, the
outer two on its edges, phased so their wavelets meet in step at `focus`.
On the edges so that where the edges are one wavelength apart (the first dark
point of the real lens) the sources' extra distances climb from 0 to exactly
1; seven such waves then cancel to within 2 % of the peak, not exactly, which
the whole lens (infinitely many sources) does.
"""
struct Wavelets
    src::Vector{Point2f}
    focus::Point2f
end
function Wavelets(x::Real, D::Real, n::Integer, focus::Point2f)
    ys = range(-Float32(D) / 2, Float32(D) / 2; length = n)
    return Wavelets([Point2f(x, y) for y in ys], focus)
end

"""Path delay of source `s` at `p`, in wavelengths, relative to the focus."""
@inline delay(w::Wavelets, s::Point2f, p) = norm(p - s) - norm(w.focus - s)

"""The wavelets' arrows at `p`: unit phasors, one per source, as complex numbers."""
phasors(w::Wavelets, p) = [cis(2f0 * Float32(π) * delay(w, s, p)) for s in w.src]

"""Intensity at `p` relative to the focus: |Σ phasors|² / n²."""
relative_intensity(w::Wavelets, p) = abs2(sum(phasors(w, p))) / length(w.src)^2

"""
    wavelet_field(w, g, t; sources = eachindex(w.src)) -> Matrix{Float32}

The summed field of the chosen sources on grid `g` at time `t` (periods), zero
left of the aperture and outside the light cone of each wavelet (a wavelet
emitted at t = 0 has reached r = t).
"""
function wavelet_field(w::Wavelets, g::Grid, t; sources = eachindex(w.src))
    u = zeros(Float32, size(g))
    x0 = w.src[1][1]
    Threads.@threads for j in 1:size(g)[2]
        for i in 1:size(g)[1]
            p = cellcenter(g, i, j)
            p[1] < x0 && continue
            acc = 0f0
            for k in sources
                s = w.src[k]
                r = norm(p - s)
                # the wavelet's front: emitted when the (lens-delayed) wave passes
                front = t + norm(w.focus - s) - norm(w.focus - w.src[end÷2+1])
                r > front && continue
                acc += cos(2f0 * Float32(π) * (delay(w, s, p) - t)) / sqrt(max(r, 0.5f0))
            end
            u[i, j] = acc
        end
    end
    return u
end

"""Distinct, bright colours for `n` wavelets (a hue wheel), as RGB tuples."""
function wavelet_colors(n)
    return map(1:n) do k
        c = convert(Makie.RGB{Float32}, Makie.HSV(360f0 * (k - 1) / n, 0.75f0, 1f0))
        (c.r, c.g, c.b)
    end
end

"""Distance from `p` to the segment a→b."""
function segment_distance(p, a, b)
    ab = b - a
    l2 = dot(ab, ab)
    iszero(l2) && return norm(p - a)
    t = clamp(dot(p - a, ab) / l2, 0f0, 1f0)
    return norm(p - (a + t * ab))
end

"""
    wavelet_glow(w, g, t; reach, colors, width, probe, line) -> Matrix{RGBSpectrum}

Each wavelet's crests as thin rings in its own colour (crests `width`
wavelengths wide, fading as 1/√r like the wave) at time `t`, out to where the
wavelets have got after travelling `reach` wavelengths (default: everywhere).
Only every `every`-th crest is drawn, and only inside `region`: seven full
sets of rings overlap into white noise.
With a `probe` point, a line of `line` wavelengths width from every source to
it, in that source's colour.
"""
function wavelet_glow(w::Wavelets, g::Grid, t; reach = Inf32, colors = wavelet_colors(length(w.src)),
                      width = 0.18f0, every = 10, probe = nothing, line = 0.12f0, line_gain = 0.8f0, gain = 0.8f0,
                      region = Rect2f(-Inf32, -Inf32, Inf32, Inf32))
    img = fill(Hikari.RGBSpectrum(0f0, 0f0, 0f0, 1f0), size(g))
    x0 = w.src[1][1]
    rc = norm(w.focus - w.src[(end + 1) ÷ 2])
    Threads.@threads for j in 1:size(g)[2]
        for i in 1:size(g)[1]
            p = cellcenter(g, i, j)
            (p[1] < x0 - 0.5f0 || !(p in region)) && continue
            r_, g_, b_ = 0f0, 0f0, 0f0
            for (k, s) in enumerate(w.src)
                c = colors[k]
                r = norm(p - s)
                front = reach + norm(w.focus - s) - rc
                a = 0f0
                if r <= front
                    # distance to the nearest drawn crest (every `every`-th), in wavelengths
                    ph = (delay(w, s, p) - t) / every
                    d = every * abs(ph - round(ph))
                    a = gain * exp(-(d / width)^2) * sqrt(10f0 / max(r, 10f0))
                end
                if probe !== nothing
                    dl = segment_distance(p, s, probe)
                    a += line_gain * exp(-(dl / line)^2)
                end
                # the source itself, a small bright dot
                a += 3f0 * exp(-(r / 0.35f0)^2)
                r_ += a * c[1]; g_ += a * c[2]; b_ += a * c[3]
            end
            img[i, j] = Hikari.RGBSpectrum(r_, g_, b_, 1f0)
        end
    end
    return img
end

"""
    pixel_values(w, centres; pitch) -> Vector{Float32}

What each pixel of a row centred at `centres` (heights on the focal plane)
records in the wavelet model: the relative intensity averaged over the pixel.
"""
pixel_values(w::Wavelets, centres; pitch = 1f0) =
    [sum(relative_intensity(w, Point2f(w.focus[1], c + pitch * o)) for o in range(-0.45f0, 0.45f0; length = 9)) / 9
     for c in centres]

"""
    readout_glow!(tex, g, x, centres, layers; pitch, len, fill, highlight)

Draw the sensor's pixels into the sheet texture `tex` (grid layout), in the
plane of the waves: each pixel's tile at `x` lights up with its value, and a
bar behind it, `len` wavelengths long at value 1, shows how much light it has
collected (`fill`, 0..1, is the exposure so far). `layers` are
`(values, tint)` pairs, values relative (1 = full bar), stacked along the bar:
two stars' light on one pixel. The pixel containing the height `highlight`
gets a white frame.
"""
function readout_glow!(tex, g::Grid, x, centres, layers; pitch = 1f0, len = 17f0, fill = 1f0,
                       highlight = nothing)
    xs_ = collect(xs(g))
    ys_ = collect(ys(g))
    hk = highlight === nothing ? 0 : argmin(abs.(centres .- highlight))
    for (k, c) in enumerate(centres)
        jsel = findall(y -> abs(y - c) < 0.45f0 * pitch, ys_)
        total = sum(values[k] for (values, _) in layers)
        # the tile: all layers' light, in their mixed colour
        tile = reduce((a, b) -> a .+ b, (values[k] .* tint for (values, tint) in layers)) ./ max(total, 1f-6)
        start = x + 1.5f0
        for (values, tint) in layers
            v = values[k]
            stop = start + len * fill * v
            for j in jsel, i in eachindex(xs_)
                xi = xs_[i]
                if start <= xi <= stop
                    s = 0.35f0 + 0.35f0 * fill * v
                    tex[i, j] = Hikari.RGBSpectrum(tint[1] * s, tint[2] * s, tint[3] * s, 1f0)
                end
            end
            start = stop
        end
        s = 0.1f0 + 1.2f0 * fill * total
        for j in jsel, i in eachindex(xs_)
            x <= xs_[i] <= x + 1f0 && (tex[i, j] = Hikari.RGBSpectrum(tile[1] * s, tile[2] * s, tile[3] * s, 1f0))
        end
        if k == hk
            # a white frame around tile and bar
            lo, hi = c - 0.55f0 * pitch, c + 0.55f0 * pitch
            xe = max(start, x + 3f0) + 0.4f0
            for (j, y) in enumerate(ys_), (i, xi) in enumerate(xs_)
                (x - 0.5f0 <= xi <= xe && lo - 0.12f0 <= y <= hi + 0.12f0) || continue
                edge = min(abs(y - lo), abs(y - hi)) < 0.12f0 || min(abs(xi - x + 0.5f0), abs(xi - xe)) < 0.12f0
                edge && (tex[i, j] = Hikari.RGBSpectrum(3f0, 3f0, 3f0, 1f0))
            end
        end
    end
    return tex
end
