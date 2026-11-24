# a0 · The first picture: a blurry orange ring on black, coming into focus as
# it is described; then what it took.
#
# Every quantity that changes is an argument the editor keys (see `perform`):
# the ring's focus, and when each caption shows.

function build_first_picture(canvas)
    fig, ov = frame2d(canvas; padding = (0, 0, 0, 0))
    ax = picture_axis(fig[1, 1])
    extent = fullframe!(ax, canvas)
    a = (; focus = Observable(0f0), question = Observable(1f0), answer = Observable(0f0))
    # from very blurred to what the Event Horizon Telescope resolves
    stack = cached("first_picture_focus") do
        sharp = image(Ring(), WIDE)
        [(s = blurred(sharp, WIDE, f); s ./ maximum(s)) for f in range(26.0, EHT_BLUR; length = 24)]
    end
    img = lift(a.focus) do f
        x = 1 + f * (length(stack) - 1)
        i = clamp(floor(Int, x), 1, length(stack) - 1)
        w = Float32(x - i)
        (1 - w) .* stack[i] .+ w .* stack[i+1]
    end
    brightness = Observable(1f0)
    image!(ax, extent, extent, lift((m, b) -> b .* m, img, brightness); colormap = HOT, colorrange = (0, 1),
           interpolate = true)
    heading!(ov, "How do you photograph a black hole?", a.question)
    caption!(ov, "M87*, 2019 · illustration of the observed ring", a.question; fontsize = 24)
    caption!(ov, "An Earth-sized telescope. A picture computed from its recordings.", a.answer)
    return fig, a
end

"""
The keys of `build_first_picture`'s arguments for the narration timing `T`: the
ring comes into focus over the first two seconds; the question and the ring's
caption give way to what it took as line 2 starts. `picture` are the keys the
picture draws, `labels` those only the labels do.
"""
function perform(::typeof(build_first_picture), T::Timing)
    s = T.starts
    picture = ["focus" => dial(0f0, 2f0)]
    labels = [
        "question" => [(s[2], 1f0, :linear), (s[2] + 0.6f0, 0f0, :linear)],
        "answer" => ramp(s[2]),
    ]
    return (; picture, labels)
end

PERFORMED["a0_first_picture"] = build_first_picture
