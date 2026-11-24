# c1 · The price, and Julia: a thousand processors busy for a week, against
# one processor for half an hour (Comrade.jl), with forty times more numbers
# in the model (about 25 then, about 1000 now).
#
# Every quantity that changes is an argument the editor keys (see `perform`):
# the thousand processors filling in, and each side and the caption fading in.

function build_julia(canvas)
    fig, ov = frame2d(canvas; padding = (40, 40, 110, 90))
    ax = Axis(fig[1, 1]; backgroundcolor = SPACE, aspect = DataAspect(), limits = (0, 32, 0, 18))
    hidedecorations!(ax); hidespines!(ax)
    a = (; older = Observable(0f0), processors = Observable(0f0), julia = Observable(0f0), detail_caption = Observable(0f0))
    one = a.older
    two = a.julia
    # a thousand processors: 40 × 25 small squares, filling in
    n = 1000
    pos = [Point2f(1.4 + 0.4 * mod(k - 1, 30), 3 + 0.37 * div(k - 1, 30)) for k in 1:n]
    scatter!(ax, pos; marker = :rect, markersize = 8, color = lift(f -> [k <= f * n ? (RGBf(0.9, 0.45, 0.2), 1.0) : (RGBf(0.9, 0.45, 0.2), 0.0)
                                                                     for k in 1:n], a.processors))
    filmtext!(ax, 7.2, 2.2; text = "about a week\non a thousand processors", align = (:center, :top), color = lift(v -> (:white, v), one),
          fontsize = 28)
    filmtext!(ax, 7.2, 17.8; text = "older code", align = (:center, :top), color = lift(v -> (:gray70, v), one), fontsize = 26)
    # one processor, half an hour
    scatter!(ax, [Point2f(23, 9)]; marker = :rect, markersize = 30, color = lift(v -> (RGBf(0.35, 0.75, 0.45), v), two))
    filmtext!(ax, 23, 7.6; text = "about half an hour\non one processor", align = (:center, :top), color = lift(v -> (:white, v), two),
          fontsize = 28)
    filmtext!(ax, 23, 17.8; text = "Julia: Comrade.jl", align = (:center, :top), color = lift(v -> (RGBf(0.6, 1, 0.65), v), two),
          fontsize = 30)
    caption!(ov, "and with 40 times more detail in the model", a.detail_caption)
    return fig, a
end

"""
The keys of `build_julia`'s arguments for the narration timing `T`: the older
code's labels with line 1 and its thousand processors filling in from a second
into it, over three seconds; the one processor with line 2, the caption three
and a half seconds into it. `picture` are the keys the picture draws, `labels`
those only the labels do.
"""
function perform(::typeof(build_julia), T::Timing)
    s = T.starts
    picture = [
        "processors" => ramp(s[1] + 1f0, 3f0),
        "julia" => ramp(s[2]),
    ]
    labels = [
        "older" => ramp(s[1]),
        "detail_caption" => ramp(s[2] + 3.5f0),
    ]
    return (; picture, labels)
end

PERFORMED["c1_julia"] = build_julia
