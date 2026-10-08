# Textures for a glowing cut: the wave, and what is drawn into the same plane
# (lens outline, rays, pixel bars, paths). Grid layout: tex[i, j] is cell (i, j).

"""Image with y up and x to the right, as the slice is drawn."""
toimage(A::AbstractMatrix) = permutedims(A)[end:-1:1, :]

"""The steady-state field at phase `φ` (in periods): Re(A e^{-2πiφ})."""
phase_field(A::AbstractMatrix{<:Complex}, φ) = real.(A .* cis(-2f0 * Float32(π) * Float32(φ)))

const GLOW = (lim = 1.2f0, ilim = 8f0, haze = 0.3f0, crest = 1.3f0)

"""Black out the glow left of `x`: the source line and the wave it sends backwards."""
function hide_source!(tex, g::Grid, x)
    i = cellindex(g, Point2f(x, 0))[1]
    tex[1:i, :] .= Ref(Hikari.RGBSpectrum(0f0, 0f0, 0f0, 1f0))
    return tex
end

"""
    sensor_pixels(g, I, x; pitch, halfwidth) -> (centres, values)

What a row of pixels of width `pitch` along the sensor at `x` records: the
intensity `I` averaged over each pixel, for pixels covering ±`halfwidth`.
"""
function sensor_pixels(g::Grid, I::AbstractMatrix, x; pitch = 1f0, halfwidth = 12f0)
    n = floor(Int, 2halfwidth / pitch)
    centres = [(k - (n + 1) / 2) * pitch for k in 1:n]
    i = cellindex(g, Point2f(x, 0))[1]
    y = collect(ys(g))
    vals = map(centres) do c
        js = findall(v -> abs(v - c) < pitch / 2, y)
        sum(I[i, js]) / length(js)
    end
    return Float32.(centres), Float32.(vals)
end

"""
    sensor_pixels(g, column, x; pitch, halfwidth) -> (centres, values)

The same for a quantity known only along the sensor's column: `column[j]` at
the height of grid row `j` (see `collected`).
"""
function sensor_pixels(g::Grid, column::AbstractVector, x; pitch = 1f0, halfwidth = 12f0)
    n = floor(Int, 2halfwidth / pitch)
    centres = [(k - (n + 1) / 2) * pitch for k in 1:n]
    y = collect(ys(g))
    vals = map(centres) do c
        js = findall(v -> abs(v - c) < pitch / 2, y)
        sum(column[js]) / length(js)
    end
    return Float32.(centres), Float32.(vals)
end

"""The largest radius of the parts that are drawn."""
outer_radius(parts) = maximum(p -> p.r1, filter(p -> p.look !== nothing, parts))

"""
Black out the sheet texture `tex` (grid layout) outside the drawn parts'
outline: at each x the radius of the widest part there, in front of the
instrument the radius of its front, behind it nothing.
"""
function outline_mask!(tex, g::Grid, parts)
    drawn = filter(p -> p.look !== nothing, parts)
    xfront = minimum(p -> p.x0, drawn)
    rfront = maximum(p -> p.r1, filter(p -> p.x0 == xfront, drawn))
    xback = maximum(p -> p.x1, drawn)
    black = Hikari.RGBSpectrum(0f0, 0f0, 0f0, 1f0)
    for (i, x) in enumerate(xs(g))
        r = x < xfront ? rfront : x > xback ? -1f0 :
            maximum(p -> p.x0 <= x <= p.x1 ? p.r1 : 0f0, drawn)
        for (j, y) in enumerate(ys(g))
            abs(y) > r && (tex[i, j] = black)
        end
    end
    return tex
end

"""
How much of the lens each cell of `g` holds (0..1), with its outline: 1 on a
rim `k` cells wide, `fill` inside. Added to the cut's glow, it shows the
lens's cross-section in every frame.
"""
function lens_section(g::Grid, sys::System; k = 3, fill = 0.25f0)
    glass = [sum(e -> glass_fraction(e, cellcenter(g, i, j), 0f0), sys.elements; init = 0f0)
             for i in 1:size(g)[1], j in 1:size(g)[2]]
    inside = glass .> 0.5f0
    core = copy(inside)
    for _ in 1:k
        prev = copy(core)
        for j in 2:size(g)[2]-1, i in 2:size(g)[1]-1
            core[i, j] = prev[i, j] && prev[i+1, j] && prev[i-1, j] && prev[i, j+1] && prev[i, j-1]
        end
    end
    return @. Float32(inside) * ifelse(core, fill, 1f0)
end

const GLASS_TINT = PALETTE.glass

"""Add the lens's cross-section `section` (from `lens_section`) to `tex`, at `alpha`."""
function show_lens!(tex, section; alpha = 1f0, tint = GLASS_TINT, gain = 0.3f0)
    alpha <= 0 && return tex
    for i in eachindex(tex, section)
        v = section[i]
        v > 0 || continue
        a = gain * alpha * v
        c = tex[i]
        tex[i] = Hikari.RGBSpectrum(c.c[1] + a * tint[1], c.c[2] + a * tint[2], c.c[3] + a * tint[3], 1f0)
    end
    return tex
end

const BLACK = Hikari.RGBSpectrum(0f0, 0f0, 0f0, 1f0)

blank(g::Grid) = fill(Hikari.RGBSpectrum(1f-5, 1f-5, 1f-5, 1f0), size(g))

"""Light up `mask` in `tex` in `tint`, at `alpha`."""
function light_up!(tex, mask, tint, alpha)
    alpha <= 0 && return tex
    for i in eachindex(tex, mask)
        mask[i] || continue
        c = tex[i]
        tex[i] = Hikari.RGBSpectrum(c.c[1] + alpha * tint[1], c.c[2] + alpha * tint[2], c.c[3] + alpha * tint[3], 1f0)
    end
    return tex
end

"""The texels of `lit` within `k` texels of an unlit one: the outline of the lit region."""
function rim_mask(lit::AbstractMatrix{Bool}, k)
    near = copy(lit)
    for _ in 1:k
        prev = copy(near)
        for j in axes(near, 2), i in axes(near, 1)
            near[i, j] = prev[i, j] && all(prev[clamp(i + di, axes(near, 1)), clamp(j + dj, axes(near, 2))]
                                           for (di, dj) in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        end
    end
    return lit .& .!near
end

"""`tex` with the outline of its lit region (`k` texels wide) turned bright green."""
function rimmed(tex, k)
    rim = Hikari.RGBSpectrum(0.15f0, 0.45f0, 0.22f0, 1f0)
    return map((t, r) -> r ? rim : t, tex, rim_mask(map(t -> t.c[1] + t.c[2] + t.c[3] > 0, tex), k))
end

"""
    path_glow!(tex, g, wl, k, target, t, color; width, gain)

Draw into `tex` (grid layout) the straight path from the `k`-th source of `wl`
to `target`, its crests at time `t` as bright beads on a dimmer line.
"""
function path_glow!(tex, g::Grid, wl::Wavelets, k::Integer, target::Point2f, t, color; width = 0.12f0, gain = 1f0)
    s = wl.src[k]
    pad = 4width
    lo = cellindex(g, min.(s, target) .- pad)
    hi = cellindex(g, max.(s, target) .+ pad)
    for j in max(lo[2], 1):min(hi[2], size(g)[2]), i in max(lo[1], 1):min(hi[1], size(g)[1])
        q = cellcenter(g, i, j)
        line = exp(-(segment_distance(q, s, target) / width)^2)
        line < 1f-3 && continue
        ph = delay(wl, s, q) - t
        bead = exp(-((ph - round(ph)) / 0.12f0)^2)
        a = gain * line * (0.35f0 + 1.2f0 * bead)
        tex[i, j] += Hikari.RGBSpectrum(a * color[1], a * color[2], a * color[3], 0f0)
    end
    return tex
end

"""Scale every texel of `tex` by `f` (the real wave, dimmed to context)."""
dim(tex, f) = map(c -> Hikari.RGBSpectrum(f * c.c[1], f * c.c[2], f * c.c[3], 1f0), tex)

"""
    ray_glow!(tex, g, a, b, color; width, head, gain)

An arrow from `a` to `b` drawn into `tex` (grid layout): a line `width` wide,
its head `head` long at `b`.
"""
function ray_glow!(tex, g::Grid, a::Point2f, b::Point2f, color; width = 0.25f0, head = 2.5f0, gain = 1f0)
    gain <= 0 && return tex
    d = b - a
    len = sqrt(d[1]^2 + d[2]^2)
    len < 1f-3 && return tex
    u = d / len
    nrm = Vec2f(-u[2], u[1])
    h = min(head, len)
    segs = [(a, b), (b, b - h * u + 0.5f0 * h * nrm), (b, b - h * u - 0.5f0 * h * nrm)]
    pad = 3width + h
    lo = cellindex(g, min.(a, b) .- pad)
    hi = cellindex(g, max.(a, b) .+ pad)
    for j in max(lo[2], 1):min(hi[2], size(g)[2]), i in max(lo[1], 1):min(hi[1], size(g)[1])
        q = cellcenter(g, i, j)
        dist = minimum(segment_distance(q, p0, p1) for (p0, p1) in segs)
        v = gain * exp(-(dist / width)^2)
        v < 1f-3 && continue
        c = tex[i, j]
        tex[i, j] = Hikari.RGBSpectrum(max(c.c[1], v * color[1]), max(c.c[2], v * color[2]), max(c.c[3], v * color[3]), 1f0)
    end
    return tex
end

const PLOT_GAP = 7f0      # mm behind the sensor where the plots start (past the camera's back wall)

"""
Into `tex` (grid `g`): where a fan landing around `centre` on the sensor at
`xf` puts its light, as a glowing curve behind the sensor, enlarged `zoom`
times across it over ± `window` mm, with two thin lines from the stretch of
sensor shown to the plot (a zoom), all at `alpha`; the curve grows out to
`grow` (0..1).
"""
function zoom_plot!(tex, g::Grid, xf, centre, profile, tint; zoom, window, bright = 1.8f0, height = 10f0, alpha = 1f0,
                    grow = 1f0)
    alpha <= 0 && return tex
    x0 = xf + PLOT_GAP
    xs_, ys_ = collect(xs(g)), collect(ys(g))
    reach = [x0 + height * grow * p for p in profile]
    w = 0.3f0
    for (j, y) in enumerate(ys_)
        abs(y - centre) <= zoom * window || continue
        lo = minimum(reach[max(j - 1, 1):min(j + 1, end)])
        hi = maximum(reach[max(j - 1, 1):min(j + 1, end)])
        for (i, x) in enumerate(xs_)
            x0 - 0.15f0 <= x <= hi + w || continue
            v = if x >= lo - w                           # the curve
                bright
            elseif x <= x0 + 0.15f0                      # the baseline
                0.2f0
            elseif x <= reach[j]                         # under the curve
                0.3f0
            else
                0f0
            end
            v > 0 || continue
            v *= alpha
            t = tex[i, j]
            tex[i, j] = Hikari.RGBSpectrum(max(t.c[1], v * tint[1]), max(t.c[2], v * tint[2]), max(t.c[3], v * tint[3]), 1f0)
        end
    end
    lines = [[Point2f(xf + 0.7f0, centre + s * window), Point2f(x0, centre + s * zoom * window)] for s in (-1, 1)]
    tex .+= ray_glow(g, lines, fill((0.22f0 * alpha, 0.22f0 * alpha, 0.22f0 * alpha), 2); width = 0.08f0)
    return tex
end

"""
    glow(u, I; lim, ilim, tint) -> Matrix{RGBSpectrum}

Colours for the wave sheet: the signed field `u` as bright crests over a faint
intensity haze `I`, in the colour `tint`, burning towards white where bright.
"""
function glow(u::AbstractMatrix, I::AbstractMatrix; lim, ilim, crest = 1f0, haze = 0.35f0, tint = SUNLIGHT)
    return map(u, I) do v, i
        c = clamp(v / lim, -1f0, 1f0)
        s = crest * max(c, 0f0)^1.5f0 + haze * clamp(i / ilim, 0f0, 1f0)^0.6f0
        hot = 0.6f0 * s^3
        Hikari.RGBSpectrum(tint[1] * s + (1 - tint[1]) * hot, tint[2] * s + (1 - tint[2]) * hot,
                           tint[3] * s + (1 - tint[3]) * hot, 1f0)
    end
end
