# c0 · Not one picture, but many. Line 1: a single picture, its parts in
# question. Line 2: a grid of pictures that all fit, then what they agree on
# (their average) and where they disagree (their spread).
#
# Every quantity that changes is an argument the editor keys (see `perform`):
# the single picture, each of the twelve that fit, the summary, and the caption.

"""Pictures that fit the notes about equally well: the ring's size, width and bright side varied as a fit's uncertainty would."""
fitting_pictures(n = 12; seed = 11) = cached("fitting_pictures") do
    s = Random.Xoshiro(seed)
    [blurred(image(Ring(radius = 21 + 1.2randn(s), width = 3.5 + 0.8abs(randn(s)), brightness = 0.6 + 0.12randn(s),
                         angle = π + 0.35randn(s)), GRID), GRID, 12.0) for _ in 1:n]
end

function build_many_pictures(canvas)
    fig, ov = frame2d(canvas; padding = (30, 30, 110, 80))
    a = merge((; single = Observable(0f0)), (; (Symbol("fit", k) => Observable(0f0) for k in 1:12)...),
              (; summary = Observable(0f0), better_caption = Observable(0f0)))
    pics = fitting_pictures()
    # line 1: one picture, big, with question marks
    single = picture_axis(fig[1:3, 1:3])
    p1 = blurred(model_ring(), GRID, EHT_BLUR)
    image!(single, (-60, 60), (-60, 60), p1 ./ maximum(p1); colormap = HOT, colorrange = (0, 1), alpha = a.single)
    for (x, y) in ((-30, 30), (32, -20), (0, -40))
        filmtext!(single, x, y; text = "?", fontsize = 60, color = lift(x -> (:white, x), a.single), align = (:center, :center))
    end
    # line 2: twelve pictures that fit, then their average and spread
    grid = [picture_axis(fig[i, j]) for i in 1:3, j in 1:4]
    for (k, ax) in enumerate(permutedims(grid))
        image!(ax, (-60, 60), (-60, 60), pics[k] ./ maximum(pics[k]); colormap = HOT, colorrange = (0, 1),
               alpha = a[Symbol("fit", k)])
    end
    m = sum(pics) ./ length(pics)
    sd = sqrt.(sum(p -> (p .- m) .^ 2, pics) ./ length(pics))
    titlecolor = lift(x -> RGBAf(1, 1, 1, x), a.summary)
    avg = picture_axis(fig[1:3, 5:6]; title = "where they agree", titlesize = 26, titlecolor)
    spread = picture_axis(fig[1:3, 7:8]; title = "where they disagree", titlesize = 26, titlecolor)
    image!(avg, (-60, 60), (-60, 60), m ./ maximum(m); colormap = HOT, colorrange = (0, 1), alpha = a.summary)
    image!(spread, (-60, 60), (-60, 60), sd ./ maximum(sd); colormap = :ice, colorrange = (0, 1), alpha = a.summary)
    caption!(ov, "Older methods: one picture, and arguments about what's real", a.single)
    caption!(ov, "Better: every picture that fits, and how likely each one is", a.better_caption)
    return fig, a
end

"""
The keys of `build_many_pictures`'s arguments for the narration timing `T`: the
single picture while line 1 is spoken; with line 2 the twelve that fit, each
0.15 s after the one before, dimmed to 30% 7 s into the line as their average
and spread show. `picture` are the keys the traced picture draws, `labels`
those only the labels do.
"""
function perform(::typeof(build_many_pictures), T::Timing)
    s = T.starts
    fit(k) = [(s[2] + 0.15f0 * k, 0f0, :linear), (s[2] + 0.15f0 * k + 0.6f0, 1f0, :linear),
              (s[2] + 7, 1f0, :linear), (s[2] + 7.6f0, 0.3f0, :linear)]
    picture = [
        "single" => inout(s[1], s[2]),
        ("fit$k" => fit(k) for k in 1:12)...,
        "summary" => ramp(s[2] + 7),
    ]
    labels = ["better_caption" => ramp(s[2])]
    return (; picture, labels)
end

PERFORMED["c0_many_pictures"] = build_many_pictures
