# b6 · Guess that song. Four pictures, each making exactly the same notes
# (computed: another picture with the heard notes of the model put in); then
# the picture found by computer as the one that best explains the notes.
#
# Every quantity that changes is an argument the editor keys (see `perform`):
# when each picture shows, and when the one found is singled out.

function build_guess_the_song(canvas)
    fig, ov = frame2d(canvas; padding = (30, 30, 110, 90))
    d = same_notes_pictures()
    # the model among the others, not first, so it is not singled out
    pictures = [d.pictures[1], d.truth, d.pictures[2], d.pictures[3]]
    axes = [picture_axis(fig[1, k]) for k in 1:4]
    a = (; shown1 = Observable(0f0), shown2 = Observable(0f0), shown3 = Observable(0f0), shown4 = Observable(0f0),
          found = Observable(0f0), heading = Observable(0f0))
    shown = (a.shown1, a.shown2, a.shown3, a.shown4)
    for (k, (ax, p)) in enumerate(zip(axes, pictures))
        # once the one found is named, every picture but it fades back
        dimmed = lift((s, t) -> s * (k == 2 ? 1f0 : 1 - 0.75f0 * t), shown[k], a.found)
        image!(ax, (-60, 60), (-60, 60), clamp.(p ./ maximum(p), 0, 1); colormap = HOT, colorrange = (0, 1), alpha = dimmed)
        filmtext!(ax, 0, -52; text = "✓ same notes", color = lift(x -> (RGBf(0.6, 1, 0.6), x), dimmed), fontsize = 24,
              align = (:center, :bottom))
    end
    heading!(ov, "Every one of these pictures makes exactly the notes the telescopes heard", a.heading)
    lines!(ov, lift(r -> outline(r; pad = 6), Makie.viewport(axes[2].scene)); color = lift(x -> (ACCENT, x), a.found),
           linewidth = 4)
    caption!(ov, "Inferred by computer: the picture that best explains the notes", a.found)
    return fig, a
end

"""
The keys of `build_guess_the_song`'s arguments for the narration timing `T`:
the pictures in turn with line 1, the one found singled out with line 2.
`picture` are the keys the picture draws, `labels` those only the labels do.
"""
function perform(::typeof(build_guess_the_song), T::Timing)
    s = T.starts
    picture = [
        ("shown$k" => ramp(s[1] + 0.6f0 * k) for k in 1:4)...,
        "found" => ramp(s[2]),
    ]
    labels = ["heading" => ramp(s[1])]
    return (; picture, labels)
end

PERFORMED["b6_guess_the_song"] = build_guess_the_song
