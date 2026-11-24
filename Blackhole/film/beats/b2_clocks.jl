# b2 · Clocks. Line 1: the waves from two telescopes, lined up wiggle on
# wiggle; one wiggle lasts four trillionths of a second. Line 2: the hydrogen
# maser at every telescope, and how little it drifts. Line 3: with worse
# clocks the waves slide out of step, and their sum blurs away.
#
# Every quantity that changes is an argument the editor keys (see `perform`):
# each line's fade and telescope B's phase offset.

"How far telescope B's wave has slid `τ` seconds after the clocks went bad: nothing for the first half second."
clocks_slide(τ) = τ < 0.5f0 ? 0f0 : 2.4f0 * sin(1.3f0 * τ) + 1.1f0 * sin(3.1f0 * τ)

function build_clocks(canvas)
    fig, ov = frame2d(canvas; padding = (30, 30, 110, 90))
    a = (; waves = Observable(0f0), wiggle = Observable(0f0), maser = Observable(0f0), sum_wave = Observable(0f0),
          phase_offset = Observable(0f0))
    ax = Axis(fig[1, 1]; backgroundcolor = SPACE, limits = (0, 16, 0, 9), aspect = DataAspect())
    hidedecorations!(ax); hidespines!(ax)
    write!(x, y, str, alpha; size = 26, align = (:left, :center), colour = :white) =
        filmtext!(ax, x, y; text = str, align, color = faded(colour, alpha), fontsize = size)
    xs = range(0, 11; length = 500)
    f = 0.45
    # how far telescope B's wave has slid: nothing, until the clocks go bad in line 3
    slide = a.phase_offset
    lines!(ax, wave(xs, f; amplitude = 0.8, origin = Point2f(3.5, 7.0)); color = faded(ACCENT, a.waves), linewidth = 3)
    lines!(ax, lift(s -> wave(xs, f; amplitude = 0.8, phase = s, origin = Point2f(3.5, 4.6)), slide); color = faded(NOTE, a.waves), linewidth = 3)
    write!(3.2, 7.0, "telescope A", a.waves; align = (:right, :center))
    write!(3.2, 4.6, "telescope B", a.waves; align = (:right, :center))
    crest(k) = 3.5 + (0.25 + k) / f
    lines!(ax, [Point2f(crest(1), 8.1), Point2f(crest(1), 8.4), Point2f(crest(2), 8.4), Point2f(crest(2), 8.1)]; color = faded(:white, a.wiggle),
           linewidth = 2)
    write!((crest(1) + crest(2)) / 2, 8.75, "one wiggle: 4 trillionths of a second", a.wiggle; align = (:center, :center))
    # line 2: the maser
    box!(ax, Rect2f(0.4, 0.4, 4.6, 2.4), "atomic clock\n(hydrogen maser)", a.maser; colour = RGBf(0.6, 1, 0.6))
    write!(5.6, 2.2, "off by 1 second in millions of years", a.maser; size = 28)
    write!(5.6, 1.1, "in 10 seconds: less than 1/20 of a wiggle", a.maser; size = 28)
    # line 3: sliding out of step, and what the two add up to
    sum_ = lift(s -> [Point2f(x + 3.5, 1.6 + 0.4 * (sin(2π * f * x) + sin(2π * f * x + s))) for x in xs], slide)
    lines!(ax, sum_; color = faded(:white, a.sum_wave), linewidth = 3)
    write!(3.2, 1.6, "A + B", a.sum_wave; align = (:right, :center))
    write!(8.0, 3.0, lift(s -> abs(s) < 0.3f0 ? "in step: they add up" : "out of step: they blur away", slide), a.sum_wave;
           align = (:center, :center), size = 28, colour = ACCENT)
    return fig, a
end

"""
The keys of `build_clocks`'s arguments for the narration timing `T`: the two
waves from line 1 on, the wiggle's length while line 1 is spoken, the maser
while line 2 is, and the sum from line 3 on. The actual phase offset is keyed
on the timeline. Everything here moves the picture.
"""
function perform(::typeof(build_clocks), T::Timing)
    s = T.starts
    picture = [
        "waves" => ramp(s[1]),
        "wiggle" => inout(s[1], s[2]; d_in = 0.6f0, d_out = 0.4f0),
        "maser" => inout(s[2], s[3]; d_in = 0.6f0, d_out = 0.4f0),
        "sum_wave" => ramp(s[3]),
        "phase_offset" => [(0f0, 0f0, :hold); (s[3] + 0.5f0, clocks_slide(0.5f0), :linear);
            sampledkeys(t -> clocks_slide(t - s[3]), s[3] + 0.5f0 + 1/60, T.duration)],
    ]
    return (; picture, labels = empty(picture))
end

PERFORMED["b2_clocks"] = build_clocks
