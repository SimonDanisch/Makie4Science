# c3 · Outro: the picture again, as the telescopes saw it, then the closing line.
#
# Every quantity that changes is an argument the editor keys (see `perform`):
# the picture dimming behind the closing line, and when each label shows.

function build_outro(canvas)
    fig, ov = frame2d(canvas; padding = (0, 0, 0, 0))
    a = (; ring_alpha = Observable(1f0), heading = Observable(0f0), motto = Observable(0f0),
          credits = Observable(0f0))
    ax = picture_axis(fig[1, 1])
    extent = fullframe!(ax, canvas)
    p = blurred(image(Ring(), WIDE), WIDE, EHT_BLUR)
    image!(ax, extent, extent, p ./ maximum(p); colormap = HOT, colorrange = (0, 1), alpha = a.ring_alpha)
    heading!(ov, "Not taken, but computed: from a few notes heard all over the Earth", a.heading)
    label!(ov, Point2f(640, 330), "Better software, better science"; alpha = a.motto, fontsize = 44)
    caption!(ov, "After Paul Tiede's JuliaCon keynote: Imaging Black Holes with Julia", a.credits;
             fontsize = 24)
    label!(ov, Point2f(640, 155), "Earth maps: NASA · ALMA antenna: NRAO/AUI/NSF (CC BY 4.0)";
           alpha = a.credits, fontsize = 18)
    label!(ov, Point2f(640, 128), "Plasma simulation: Dhruv et al. (2025) · Illinois v3 (CC BY 4.0)";
           alpha = a.credits, fontsize = 18)
    return fig, a
end

"""
The keys of `build_outro`'s arguments for the narration timing `T`: the heading
a second into line 1; with line 2 the picture dims to 40% over two seconds, the
closing line follows a second in and the credits three seconds in. `picture`
are the keys the picture draws, `labels` those only the labels do.
"""
function perform(::typeof(build_outro), T::Timing)
    s = T.starts
    picture = [
        "ring_alpha" => [(s[2], 1f0, :linear), (s[2] + 2f0, 0.4f0, :linear)],
    ]
    labels = [
        "heading" => ramp(s[1] + 1f0),
        "motto" => ramp(s[2] + 1f0),
        "credits" => ramp(s[2] + 3f0),
    ]
    return (; picture, labels)
end

PERFORMED["c3_outro"] = build_outro
