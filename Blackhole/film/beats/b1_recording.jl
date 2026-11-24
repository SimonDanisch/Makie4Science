# b1 · Recording. Line 1: the signal, measured four billion times a second.
# Line 2: each measurement kept as two bits, one of four levels. Line 3: four
# gigabytes a second, a laptop full in four minutes; a night, about a hundred
# terabytes per telescope (2017: 32 Gbit/s per station, EHT Paper II). Line 4:
# one drive writes about 0.2 GB a second, far too slow; each Mark 6 recorder
# writes to 32 drives in turn (two recorders per station in 2017).
#
# Every quantity that changes is an argument the editor keys (see `perform`):
# each line's pictures fading, the samples snapping to four levels, the drives
# filling, and the clocks of the drives' turns and of the data on its way.

"""A laptop seen from the front: its screen `r`, its drive shown filled to the fraction `full`, and its keyboard."""
function laptop!(ax, r::Rect2f, full, alpha; colour = RGBf(0.75, 0.8, 0.9))
    (x, y), (w, h) = GeometryBasics.origin(r), widths(r)
    poly!(ax, r; color = lift(a -> (RGBf(0.12, 0.12, 0.15), a), alpha), strokecolor = faded(colour, alpha), strokewidth = 2)
    poly!(ax, lift(f -> Rect2f(x + 0.08w, y + 0.15h, max(f, 1f-3) * 0.84w, 0.7h), full); color = faded(ACCENT, alpha))
    poly!(ax, Point2f[(x - 0.1w, y - 0.14h), (x + 1.1w, y - 0.14h), (x + w, y), (x, y)]; color = faded(colour, alpha))
end

"""A stretch of radio noise: smooth random wiggles (a fixed seed, so every frame draws the same)."""
function noise_signal(n; seed = 3)
    rng = Random.Xoshiro(seed)
    x = cumsum(randn(rng, n)); x .-= range(x[1], x[end]; length = n)
    y = [sum(x[max(1, i - 3):min(n, i + 3)]) / 7 for i in 1:n]
    return Float32.(y ./ maximum(abs, y))
end

function build_recording(canvas)
    fig, ov = frame2d(canvas; padding = (0, 0, 0, 0))
    ax = Axis(fig[1, 1]; backgroundcolor = SPACE, limits = (0, 16, 0, 9), aspect = DataAspect())
    hidedecorations!(ax); hidespines!(ax)
    write!(x, y, s, alpha; size = 26, align = (:left, :center), colour = :white) =
        filmtext!(ax, x, y; text = s, align, color = faded(colour, alpha), fontsize = size)
    a = (; signal = Observable(0f0), snap = Observable(0f0), measurements = Observable(0f0), bits = Observable(0f0),
          laptop = Observable(0f0), drive_full = Observable(0f0), night = Observable(0f0), laptops_filled = Observable(0f0),
          drives = Observable(0f0), handover = Observable(0f0), pile = Observable(0f0),
          drive_turn = Observable(0f0), flow = Observable(0f0))

    # lines 1 and 2: the signal, its samples, and the samples rounded to four levels
    shown = a.signal
    sig = noise_signal(600)
    xs = range(0.8, 12.8; length = 600)
    picks = 1:12:600
    levels = (-0.75f0, -0.25f0, 0.25f0, 0.75f0)
    nearest(y) = levels[argmin([abs(y - l) for l in levels])]
    snap = a.snap
    lines!(ax, [Point2f(x, 4.6 + 2.6y) for (x, y) in zip(xs, sig)]; color = lift((x, f) -> (ACCENT, x * (1 - 0.6f0 * f)), shown, snap),
           linewidth = 2)
    samples = lift(snap) do f
        [Point2f(xs[i], 4.6 + 2.6 * ((1 - f) * sig[i] + f * nearest(sig[i]))) for i in picks]
    end
    # the kept values drawn as a signal too: a line through them, which turns
    # coarse as they snap to the four levels
    lines!(ax, samples; color = lift((x, f) -> (:white, 0.9f0 * x * f), shown, lift(f -> clamp(4f0 * f, 0f0, 1f0), snap)),
           linewidth = 2)
    scatter!(ax, samples; color = faded(:white, shown), markersize = 8)
    write!(0.8, 8.3, "4 billion measurements every second", a.measurements; size = 28)
    two = a.bits
    for (l, name) in zip(levels, ("00", "01", "10", "11"))
        lines!(ax, [Point2f(0.6, 4.6 + 2.6l), Point2f(13.2, 4.6 + 2.6l)]; color = lift(x -> (NOTE, 0.6f0 * x), two), linestyle = :dash)
        write!(13.5, 4.6 + 2.6l, name, two; colour = NOTE, size = 26)
    end
    write!(0.8, 8.3, "each one kept as just 2 bits: one of 4 values", two; size = 28)

    # line 3: four gigabytes a second, a laptop full in four minutes; in a night, a hundred laptops
    three = a.laptop
    full = a.drive_full
    laptop!(ax, Rect2f(1.4, 3.4, 4.2, 2.7), full, three)
    write!(3.5, 7.4, "4 gigabytes every second", three; align = (:center, :center), size = 30, colour = ACCENT)
    write!(3.5, 2.1, lift(f -> (m = 240f * f; "$(floor(Int, m / 60)):$(lpad(floor(Int, mod(m, 60)), 2, '0')) minutes"), full), three;
           align = (:center, :center), size = 30)
    write!(3.5, 1.3, "a laptop's whole drive, full", lift(*, three, lift(f -> Float32(f >= 1), full)); align = (:center, :center))
    night = lift(*, three, a.night)
    laptops = [Point2f(7.6 + 0.8 * mod(k - 1, 10), 6.3 - 0.5 * div(k - 1, 10)) for k in 1:100]
    scatter!(ax, laptops; marker = Rect, markersize = Vec2f(44, 28),
             color = lift((f, x) -> [(k <= f * 100 ? ACCENT : RGBf(0.2, 0.2, 0.24), x) for k in 1:100], a.laptops_filled, night))
    write!(11.2, 7.4, "one telescope, one night: about 100 terabytes", night; align = (:center, :center), size = 28)
    write!(11.2, 1.3, "= 100 full laptops", night; align = (:center, :center), size = 30, colour = ACCENT)

    # line 4: one drive is far too slow; each recorder writes to 32 drives, in turn
    four = a.drives
    many = a.handover
    alone = lift(m -> 1 - m, many)
    dish!(ax, Point2f(1.3, 3.5), 1.6, four)
    write!(1.3, 6.0, "4 GB\nevery second", four; align = (:center, :center), size = 26, colour = ACCENT)
    source = Point2f(2.3, 4.6)
    # one drive: the data piles up in front of it
    drive!(ax, Point2f(7.0, 3.9), 1.1, lift(*, four, alone))
    poly!(ax, lift(p -> (w = 2.8f0 * p; Rect2f(6.8 - w, 4.25, w, 0.7)), a.pile);
          color = lift(x -> (RGBf(1, 0.35, 0.3), 0.8f0 * x), lift(*, four, alone)))
    write!(7.55, 2.9, "one drive: about 0.2 GB a second", lift(*, four, alone); align = (:center, :center))
    write!(7.55, 2.2, "20 times too slow", lift(*, four, alone); align = (:center, :center), colour = RGBf(1, 0.5, 0.45))
    # two recorders of 32 drives (4 modules of 8), the drives writing in turn
    boxes = (Rect2f(8.2, 4.4, 7.2, 3.0), Rect2f(8.2, 0.5, 7.2, 3.0))
    spots = [Point2f(GeometryBasics.origin(b)[1] + 0.45 + 0.85 * mod(j - 1, 8), GeometryBasics.origin(b)[2] + 0.25 + 0.68 * div(j - 1, 8))
             for b in boxes for j in 1:32]
    shown4 = lift(*, four, many)
    for (b, name) in zip(boxes, ("recorder 1: 32 drives", "recorder 2: 32 drives"))
        poly!(ax, b; color = lift(x -> (NOTE, 0.08f0 * x), shown4), strokecolor = faded(NOTE, shown4), strokewidth = 2)
        write!(GeometryBasics.origin(b)[1] + 3.6, GeometryBasics.origin(b)[2] + 3.25, name, shown4; align = (:center, :center), size = 24)
    end
    poly!(ax, [Rect2f(p, Vec2f(0.5, 0.55)) for p in spots]; color = lift(x -> (RGBf(0.2, 0.2, 0.22), x), shown4),
          strokecolor = lift(x -> (RGBf(0.75, 0.75, 0.78), x), shown4), strokewidth = 1)
    # the drive writing now (`drive_turn` counts drives, 24 a second), and the ones just before it, lit
    lit = lift(a.drive_turn, shown4) do now, x
        [begin
             age = mod(now - (mod(j - 1, 32)), 32f0)
             (RGBf(0.6, 1, 0.6), x * max(0f0, 1 - age / 5f0))
         end for j in eachindex(spots)]
    end
    scatter!(ax, [p + Point2f(0.25, 0.3) for p in spots]; color = lit, markersize = 12)
    # the data on its way (`flow` counts the trips made): to the one drive, then shared between the recorders
    flow = lift(a.flow, alone) do phase, x
        map(1:48) do k
            f = mod(phase + k / 48f0, 1f0)
            target = x > 0.5f0 ? Point2f(6.8, 4.6) : Point2f(8.2, isodd(k) ? 5.9 : 2.0)
            source + f * (target - source)
        end
    end
    scatter!(ax, flow; marker = Rect, markersize = 9, color = faded(ACCENT, four))
    write!(11.8, 8.55, "spinning disks recording in parallel", shown4; align = (:center, :center), size = 28)
    return fig, a
end

"""
The keys of `build_recording`'s arguments for the narration timing `T`: the
signal with lines 1 and 2, its samples snapping to four levels a second into
line 2, the laptop filling from 15% into line 3 and the hundred laptops from
60%, the one drive handing over to the recorders 36% into line 4. The drives
take their turns at 24 a second and the data makes 1.6 trips a second
throughout, both keyed on whole seconds so their rates stay exact. `picture`
are the keys the picture draws, `labels` those only the labels do.
"""
function perform(::typeof(build_recording), T::Timing)
    s, e = T.starts, T.ends
    within(i, u) = s[i] + u * (e[i] - s[i])
    D = ceil(T.duration)
    picture = [
        "signal" => inout(s[1], s[3]; d_out = 0.4f0),
        "snap" => dial(s[2] + 1f0, 1.5f0),
        "bits" => inout(s[2], s[3]; d_out = 0.4f0),
        "laptop" => inout(s[3], s[4]; d_out = 0.4f0),
        "drive_full" => dial(within(3, 0.15f0), 3f0),
        "night" => ramp(within(3, 0.55f0)),
        "laptops_filled" => ramp(within(3, 0.6f0), 3f0),
        "drives" => ramp(s[4]),
        "handover" => ramp(within(4, 0.36f0), 0.4f0),
        "pile" => ramp(s[4] + 0.5f0, 3f0),
        "drive_turn" => [(0f0, 0f0, :linear), (D, 24f0 * D, :linear)],
        "flow" => [(0f0, 0f0, :linear), (D, 1.6f0 * D, :linear)],
    ]
    labels = ["measurements" => inout(s[1], s[2]; d_out = 0.4f0)]
    return (; picture, labels)
end

PERFORMED["b1_recording"] = build_recording
