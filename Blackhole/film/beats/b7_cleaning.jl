# b7 · Cleaning. Line 1: the air over each telescope wobbles, sliding each
# pair's stripes back and forth. Line 2: the closure trick: three telescopes
# in a triangle; each side's slide is the black hole's part, plus the wobble
# of one end, minus the wobble of the other. Around the triangle every wobble
# comes once with + and once with −, so the pairs cancel and the black hole's
# part is left. Lines 3–7: narrated scale stops, from the 4 petabytes recorded in
# 2017 (MPIfR) to the 4.5 megabytes of calibrated M87* data the picture was
# made from (EHT data release 2019-D01-01): a zoom in, and back out.
#
# Every quantity that changes is an argument the editor keys (see `perform`):
# the air texture's phases, the stripe offset, fades, the closure sum's steps, the zoom, and
# when each scale stop is named.

"""
The view heights of the narrated scale stops, in units of a square megabyte:
the whole recording, a terabyte, a gigabyte, the 4.5 megabytes.
"""
const CLEANING_STOPS = (1.25sqrt(4e9), 1.5sqrt(1e6), 1.5sqrt(1e3), 6sqrt(4.5))

"""Smooth made-up wobble of telescope `k` at time `t` (the air above it)."""
wobble(k, t) = 0.9f0 * sin(1.7f0 * t + 2.1f0 * k) + 0.5f0 * sin(3.3f0 * t + 0.7f0 * k^2) + 0.3f0 * sin(5.9f0 * t + k)

# Drifting, translucent patches of turbulent air, not another signal waveform.
# This is a schematic density visualization; water vapour itself is invisible.
function turbulent_air!(ax, x, y, width, height, phases, alpha; station = 1, colour = RGBf(0.7, 0.8, 0.95))
    density = lift(phases) do phase
        [begin
            envelope = exp(-3.5f0 * (u^2 + v^2))
            texture = 0f0
            for k in 1:4
                texture += exp(-((u - 0.42sin(phase[1] + k + station))^2 / 0.16 +
                                 (v - 0.45cos(phase[2] + 1.7k + station))^2 / 0.22))
            end
            # Warped, advected detail makes the patches billow instead of
            # reading as either a blurred dot or another clean sine wave.
            a = u + 0.22sin(4v + phase[3] + station)
            b = v + 0.18sin(5u + phase[4])
            wisps = clamp(0.55 + 0.22sin(8a + 3b) + 0.16sin(13b - 5a + phase[5]), 0, 1)
            RGBAf(colour.r, colour.g, colour.b, Float32(0.8 * envelope * (1 - exp(-texture)) * wisps))
        end for u in range(-1, 1; length = 64), v in range(-1, 1; length = 48)]
    end
    image!(ax, (x - width / 2, x + width / 2), (y, y + height), density; alpha)
end

function build_cleaning(canvas)
    fig, ov = frame2d(canvas; padding = (0, 0, 0, 0))
    ax = Axis(fig[1, 1]; backgroundcolor = SPACE, limits = (0, 16, 0, 9), aspect = DataAspect())
    hidedecorations!(ax); hidespines!(ax)
    write!(x, y, s, a; size = 26, align = (:left, :center), colour = :white) =
        filmtext!(ax, x, y; text = s, align, color = faded(colour, a), fontsize = size)
    a = (; air_phases = Observable(Vec{5,Float32}(zeros(5))), stripe_offset = Observable(0f0),
          pair = Observable(0f0), closure = Observable(0f0),
          focus = Observable(0f0), gather = Observable(0f0), vanish = Observable(0f0),
          to_scale = Observable(false), scaled = Observable(0f0), zoom = Observable(0f0),
          stop1 = Observable(0f0), stop2 = Observable(0f0), stop3 = Observable(0f0), stop4 = Observable(0f0),
          speck = Observable(0f0))

    # line 1: one pair's stripes, sliding with the air above its two telescopes
    one = a.pair
    g = ImageGrid(64, 120.0)
    (u, v) = uv(EHT[6], EHT[8], 0.4)     # Chile–Spain: a few stripes across the picture
    pattern = lift(a.stripe_offset) do φ
        [cos(2π * (u * x * UAS + v * y * UAS) + 1.6φ) for x in coords(g), y in coords(g)]
    end
    image!(ax, (5.0, 11.0), (1.6, 7.6), pattern; colormap = [RGBf(0.02, 0.03, 0.08), NOTE], colorrange = (-1, 1), alpha = one)
    dish!(ax, Point2f(2.0, 3.4), 1.6, one); dish!(ax, Point2f(14.0, 3.4), 1.6, one)
    for (x, telescope) in ((2.0, 1), (14.0, 2))
        turbulent_air!(ax, x, 4.7, 3.6, 2.6, a.air_phases, one; station = telescope)
        write!(x, 7.5, "turbulent air", one; align = (:center, :center), size = 22)
    end
    write!(8.0, 8.4, "the air above each telescope wobbles: the stripes slide", one; align = (:center, :center))

    # line 2: three telescopes; each side = black hole + wobble of one end − wobble of the other
    two = a.closure
    air = (RGBf(1, 0.45, 0.4), RGBf(0.45, 0.7, 1), RGBf(0.85, 0.6, 1))
    corners = (Point2f(2.6, 6.2), Point2f(1.0, 2.0), Point2f(4.2, 2.0))
    lines!(ax, [corners..., corners[1]] .+ Point2f(0, 0.6); color = lift(a -> (:white, 0.5f0 * a), two), linewidth = 2, linestyle = :dash)
    for (k, p) in enumerate(corners)
        dish!(ax, p, 1.0, two)
        turbulent_air!(ax, p[1], p[2] + 0.75, 2.0, 1.6, a.air_phases, two; station = k, colour = air[k])
        write!(p[1] + 0.85, p[2] + 0.5, ("A", "B", "C")[k], two; size = 30, align = (:center, :center), colour = air[k])
    end
    # the chips, as in a written sum: per side the black hole's part, then each
    # telescope's wobble in its own column (+ for the side's first end, − for its
    # other end); added down the columns, every wobble meets its opposite
    sides = ((1, 2), (2, 3), (3, 1))
    rows = (6.6, 5.2, 3.8)
    sumrow = 2.0f0
    column = (9.9, 11.4, 12.9)
    # the chips gather into the sum, and the wobbles vanish from it; while A is
    # spoken of, its two chips stand out
    gather, vanish, focus = a.gather, a.vanish, a.focus
    hole = (0.6f0, -0.2f0, 0.9f0)
    chip!(from, to, label, colour, alpha; width = 1.3) = begin
        at = lift(g -> from + g * (to - from), gather)
        poly!(ax, lift(q -> Rect2f(q[1] - width / 2, q[2] - 0.35, width, 0.7), at); color = faded(colour, alpha))
        filmtext!(ax, at; text = label, align = (:center, :center), color = faded(:black, alpha), fontsize = 26)
    end
    letters = ("A", "B", "C")
    sideoffsets=Pair{Symbol,Observable}[]
    for (j, ((i, k), y)) in enumerate(zip(sides, rows))
        write!(7.0, y, "$(letters[i])–$(letters[k]):", two; size = 28, align = (:right, :center))
        chip!(Point2f(8.15, y), Point2f(8.15, sumrow), "black hole", ACCENT, two; width = 1.8)
        for (n, sign) in ((i, "+"), (k, "−"))
            alpha = lift((a, v, f) -> a * (1 - v) * (1 - 0.65f0 * f * (n != 1)), two, vanish, focus)
            chip!(Point2f(column[n], y), Point2f(column[n], sumrow), sign * letters[n], air[n], alpha)
        end
        # how far this side's stripes slide right now
        slide=Observable(Float32(hole[j]+wobble(i,0f0)-wobble(k,0f0)))
        push!(sideoffsets,Symbol("side",j,"_offset")=>slide)
        lines!(ax, lift(v -> [Point2f(14.9, y), Point2f(14.9 + 0.25v, y)], slide); color = faded(NOTE, two), linewidth = 14)
    end
    write!(14.9, 7.5, "slide now", two; align = (:center, :center), size = 24, colour = NOTE)
    lines!(ax, [Point2f(5.8, 2.95), Point2f(13.7, 2.95)]; color = lift(a -> (:white, 0.7f0 * a), two), linewidth = 2)
    write!(7.0, sumrow, "sum:", two; size = 28, align = (:right, :center))
    for x in column
        filmtext!(ax, x, sumrow; text = "0", align = (:center, :center), color = faded(RGBf(0.6, 1, 0.6), lift(*, two, vanish)),
                  fontsize = 34)
    end
    lines!(ax, [Point2f(14.9, sumrow), Point2f(14.9 + 0.25sum(hole), sumrow)];
           color = faded(RGBf(0.6, 1, 0.6), lift(*, two, lift(g -> Float32(g > 0.98f0), gather))), linewidth = 14)
    write!(10.3, 1.0, "every wobble cancels: what's left is the black hole's", lift(*, two, vanish); align = (:center, :center),
           size = 26, colour = RGBf(0.6, 1, 0.6))
    write!(8.0, 8.4, "each telescope's wobble slides two pairs: one forward, one back", lift(*, two, lift(v -> 1 - v, vanish));
           align = (:center, :center))
    write!(8.0, 8.4, "added up, the wobbles cancel", lift(*, two, vanish); align = (:center, :center))

    # Lines 3–7: area to scale; 1 megabyte is 1 square unit, with a shared corner.
    sizes = (("recorded: about 4 petabytes", 4e9, ACCENT), ("1 terabyte: a laptop's drive", 1e6, RGBf(0.75, 0.8, 0.9)),
             ("1 gigabyte", 1e3, RGBf(0.75, 0.8, 0.9)), ("4.5 megabytes: the data the picture was made from", 4.5, RGBf(0.6, 1, 0.6)))
    big, small = sqrt(4e9), sqrt(4.5)
    W, H = canvas
    # how tall the view is, from the whole recording (zoom 0) to the 4.5 MB (zoom 1)
    zoom = a.zoom
    height(z) = exp((1 - z) * log(1.25 * big) + z * log(6 * small))
    scaled = a.scaled
    view = lift((z, s) -> (z, s), zoom, a.to_scale)
    on(view; update = true) do (z, to_scale)
        to_scale || return limits!(ax, 0, 16, 0, 9)
        h = height(z)
        # where the corner sits on screen: low left with the whole recording in view, the middle zoomed in
        f = (1 - ease(z)) .* (0.3, 0.1) .+ ease(z) .* (0.45, 0.4)
        w = h * W / H
        limits!(ax, -f[1] * w, (1 - f[1]) * w, -f[2] * h, (1 - f[2]) * h)
    end
    for ((name, area, colour), named) in zip(sizes, (a.stop1, a.stop2, a.stop3, a.stop4))
        side = sqrt(area)
        # the square once it is a few pixels tall; its name while it is less than a few screens tall
        px(z) = side / height(z) * H
        seen = lift((z, a) -> Float32(a * clamp((px(z) - 25) / 40, 0, 1)), zoom, scaled)
        # Labels belong to the narrated stop, not merely to a pixel-size threshold.
        square=poly!(ax, Rect2f(0, 0, side, side); color = lift(a -> (colour, area > 1e9 ? 0.3f0 * a : area < 10 ? a : 0.12f0 * a), seen),
              strokecolor = faded(colour, seen), strokewidth = 2)
        area>1e9 && plotattribute!(square,:to_scale,a.to_scale)
        # Fixed screen position keeps every unit readable throughout the zoom.
        filmtext!(ov, W / 2, H - 50; text = name, align = (:center, :center), color = faded(colour, named), fontsize = 28)
    end
    # the terabytes inside the recording, the gigabytes inside a terabyte, the megabytes inside a gigabyte
    for (unit, n) in ((1e3, 63), (sqrt(1e3), 31), (1.0, 31))
        cells = lift(zoom, scaled) do z, a
            px = unit / height(z) * H
            0.25f0 * a * clamp((px - 4) / 8, 0, 1)
        end
        span = unit * n
        grid = vcat([[Point2f(unit * k, 0), Point2f(unit * k, span)] for k in 1:n]...,
                    [[Point2f(0, unit * k), Point2f(span, unit * k)] for k in 1:n]...)
        linesegments!(ax, grid; color = faded(:white, cells), linewidth = 1)
    end
    # back out: where the 4.5 megabytes are, far too small to see
    corner = Point2f(0.3 * W, 0.1 * H)     # where (0, 0) is on screen with the whole recording in view
    lines!(ov, circlepoints(corner, 24); color = faded(RGBf(0.6, 1, 0.6), a.speck), linewidth = 3)
    label!(ov, corner + Vec2f(-34, 0), "4.5 megabytes: in here"; align = (:right, :center), alpha = a.speck, fontsize = 26)
    return fig, merge(a,(;sideoffsets...))
end

"""
The native property keys for narration timing `T`: the air texture phases and
the stripes' actual offsets are keyed; each line's picture fades in with it
and out as the next starts. In line 2 (a fraction `p` of it gone by) A's chips
stand out from p = 0.17 to 0.48, the chips gather into the sum from p = 0.5 and
the wobbles vanish from p = 0.7. From line 3 the view is to scale: lines 4 to 6
each zoom in to the next stop 0.8 s after they start, over 2.6 s; line 7 zooms
back out over 3 s and points at the 4.5 megabytes. (Each zoom ends before the
next begins while lines start at least 2.6 s apart, as they do.) `picture` are
the keys the picture draws, `labels` those only the labels do.
"""
function perform(::typeof(build_cleaning), T::Timing)
    s, e = T.starts, T.ends
    # the fraction `p` of line 2 gone by, in seconds into the beat
    at(p) = s[2] + p * (e[2] - s[2])
    span(p) = p * (e[2] - s[2])
    # each stop's zoom: how far its view height is, in log, from the whole recording's towards the 4.5 MB's
    z = map(h -> Float32((log(CLEANING_STOPS[1]) - log(h)) / (log(CLEANING_STOPS[1]) - log(CLEANING_STOPS[4]))), CLEANING_STOPS)
    picture = [
        "stripe_offset" => sampledkeys(t -> wobble(1, t) - wobble(2, t), s[1], s[2] + 0.4f0),
        "pair" => inout(s[1], s[2]; d_in = 0.6f0, d_out = 0.4f0),
        "closure" => inout(s[2], s[3]; d_in = 0.6f0, d_out = 0.4f0),
        "focus" => inout(at(0.17f0), at(0.48f0); d_in = span(0.05f0), d_out = span(0.05f0)),
        "gather" => dial(at(0.5f0), span(0.18f0)),
        "vanish" => ramp(at(0.7f0), span(0.08f0)),
        "to_scale" => [(0f0, false, :hold), (s[3], true, :hold)],
        "scaled" => ramp(s[3]),
        "zoom" => eased([s[4] + 0.8f0 => z[1], s[4] + 3.4f0 => z[2], s[5] + 0.8f0 => z[2], s[5] + 3.4f0 => z[3],
                         s[6] + 0.8f0 => z[3], s[6] + 3.4f0 => z[4], s[7] + 0.8f0 => z[4], s[7] + 3.8f0 => z[1]]),
    ]
    for (i, rate) in enumerate((0.39f0, 0.31f0, 0.45f0, -0.32f0, 0.2f0))
        push!(picture, "air_phases[$i]" => [(0f0, 0f0, :linear), (s[3] + 0.4f0, rate * (s[3] + 0.4f0), :linear)])
    end
    for (j,(i,k)) in enumerate(((1,2),(2,3),(3,1)))
        hole=(0.6f0,-0.2f0,0.9f0)[j]
        push!(picture,"side$(j)_offset"=>sampledkeys(t->hole+wobble(i,t)-wobble(k,t),s[2],s[3]+0.4f0))
    end
    labels = [
        ("stop$k" => inout(s[k + 2], s[k + 3]; d_in = 0.6f0, d_out = 0.4f0) for k in 1:4)...,
        "speck" => ramp(s[7] + 3.8f0),
    ]
    return (; picture, labels)
end

PERFORMED["b7_cleaning"] = build_cleaning
