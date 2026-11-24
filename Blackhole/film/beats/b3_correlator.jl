# b3 · To the supercomputers. Line 1: too much for the internet (about a year
# for one campaign), so the drives fly to two correlators, in Germany (MPIfR,
# Bonn) and the USA (MIT Haystack). Line 2: for every pair, the recordings are
# lined up and compared; what they share is the black hole's light, the rest
# averages away, shown as the running average of their product settling.
#
# Every quantity that changes is an argument the editor keys (see `perform`):
# line 1's drawings, the plane's flight, line 2's recordings, and how much of
# their running average is drawn.

function build_correlator(canvas)
    fig, ov = frame2d(canvas; padding = (30, 30, 110, 90))
    a = (; shipping = Observable(0f0), flight = Observable(0f0), comparison = Observable(0f0), average = Observable(0f0))
    ax = Axis(fig[1, 1]; backgroundcolor = SPACE, limits = (0, 16, 0, 9), aspect = DataAspect())
    hidedecorations!(ax); hidespines!(ax)
    write!(x, y, s, alpha; size = 26, align = (:left, :center), colour = :white) =
        filmtext!(ax, x, y; text = s, align, color = faded(colour, alpha), fontsize = size)

    # line 1: dishes and drives, the plane, the two supercomputers
    for y in (6.8, 4.2, 1.6)
        dish!(ax, Point2f(1.0, y - 0.5), 1.3, a.shipping)
        for k in 0:2
            drive!(ax, Point2f(2.0 + 0.55k, y - 0.4), 0.45, a.shipping)
        end
    end
    poly!(ax, lift(f -> plane(Point2f(4.6 + 4.6f, 4.6 + 1.2sin(π * f)), 1.8), a.flight); color = faded(:white, a.shipping))
    box!(ax, Rect2f(10.6, 5.2, 4.8, 2.0), "supercomputer\nBonn, Germany", a.shipping)
    box!(ax, Rect2f(10.6, 1.8, 4.8, 2.0), "supercomputer\nMassachusetts, USA", a.shipping)
    write!(8.0, 8.4, "over the internet: about a year. By plane: days.", a.shipping; align = (:center, :center), size = 26,
           colour = ACCENT)

    # line 2: two recordings, mostly noise, sharing a faint signal; their product, averaged, finds it
    rng = Random.Xoshiro(5)
    n = 700
    shared = [0.25f0 * sin(0.21f0 * k) for k in 1:n]
    rec1 = shared .+ 0.8f0 .* Float32.(randn(rng, n)); rec2 = shared .+ 0.8f0 .* Float32.(randn(rng, n))
    xs = range(3.2, 11.6; length = n)
    lines!(ax, [Point2f(x, 7.2 + 0.6y) for (x, y) in zip(xs, rec1)]; color = faded(ACCENT, a.comparison), linewidth = 1)
    lines!(ax, [Point2f(x, 5.0 + 0.6y) for (x, y) in zip(xs, rec2)]; color = faded(NOTE, a.comparison), linewidth = 1)
    write!(3.0, 7.2, "telescope 1", a.comparison; align = (:right, :center), size = 22)
    write!(3.0, 5.0, "telescope 2", a.comparison; align = (:right, :center), size = 22)
    # the running average of the product over many more samples than are drawn, revealed as line 2 goes on
    m = 30 * n
    long = [0.25f0 * sin(0.21f0 * k) for k in 1:m]
    product = (long .+ 0.8f0 .* Float32.(randn(rng, m))) .* (long .+ 0.8f0 .* Float32.(randn(rng, m)))
    avg = (cumsum(product) ./ (1:m))[30:30:m]
    level = sum(abs2, long) / m
    height(v) = 1.8f0 + clamp(25f0 * v, -1.4f0, 1.4f0)
    lines!(ax, lift(r -> [Point2f(xs[k], height(avg[k])) for k in 1:max(2, round(Int, r * n))], a.average);
           color = faded(:white, a.comparison), linewidth = 3)
    lines!(ax, [Point2f(3.2, height(level)), Point2f(11.6, height(level))];
           color = lift(x -> (RGBf(0.6, 1, 0.6), 0.8f0 * x), a.comparison), linestyle = :dash, linewidth = 2)
    write!(11.8, 2.3, "what they have\nin common:\nthe black hole's light", a.comparison; size = 22, colour = RGBf(0.6, 1, 0.6))
    write!(3.0, 1.8, "compared", a.comparison; align = (:right, :center), size = 22)
    return fig, a
end

"""
The keys of `build_correlator`'s arguments for the narration timing `T`: line
1's drawings while it is spoken, the plane flying in 2.5 s from 45% into the
line; line 2's recordings with it, and their running average drawn over 5 s
from a second in. Every key is drawn by the picture; the labels only follow it.
"""
function perform(::typeof(build_correlator), T::Timing)
    s, e = T.starts, T.ends
    picture = [
        "shipping" => inout(s[1], s[2]; d_out = 0.4f0),
        "flight" => dial(s[1] + 0.45f0 * (e[1] - s[1]), 2.5f0),
        "comparison" => ramp(s[2]),
        "average" => ramp(s[2] + 1, 5f0),
    ]
    return (; picture, labels = empty(picture))
end

PERFORMED["b3_correlator"] = build_correlator
