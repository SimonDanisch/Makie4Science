# c2 · Sharper still: a telescope in space. Left: the globe and a satellite
# on a wide orbit (an illustration of the Black Hole Explorer, not its real
# orbit). Right: the picture sharpening, from what the Earth-sized telescope
# resolves to what a telescope several times larger would: the thin photon
# ring appears.
#
# Every quantity that changes is an argument the editor keys (see `perform`):
# the globe's turn, the orbit fading in and the satellite's angle along it,
# the picture's focus, and the caption.

"""The model with a thin photon ring added, the feature a sharper telescope would show."""
photon_ring_model() = (img = image(Ring(), GRID) .+ 0.35 .* image(Ring(radius = 19.5, width = 0.7, brightness = 0.3, floor = 0.0), GRID);
                       img ./ sum(img))

function build_space(canvas)
    fig, ov = frame2d(canvas; padding = (20, 40, 110, 40))
    a = (; turn = Observable(-1.6f0), orbit = Observable(0f0), orbit_angle = Observable(0f0), focus = Observable(0f0),
          sharper_caption = Observable(0f0))
    ls = LScene(fig[1, 1]; show_axis = false, scenekw = (backgroundcolor = SPACE, lights = sunlight()))
    cam3d!(ls.scene; center = false)
    sc = ls.scene
    pic = picture_axis(fig[1, 2]; title = "", titlesize = 26)
    colsize!(fig.layout, 2, Relative(0.42))
    scatter!(sc, starfield(); color = (:white, 0.5), markersize = 3)
    globe!(sc, a.turn)
    look!(sc, Pose((0, -11, 4), (0, 0, 0); fov = 40))
    # the orbit and the satellite on it
    R = 3.4f0
    orbitpts = [Point3f(R * cos(t), 0.35f0 * R * sin(t), R * 0.8f0 * sin(t)) for t in range(0, 2π; length = 200)]
    lines!(sc, orbitpts; color = lift(x -> (ACCENT, 0.7f0 * x), a.orbit), linewidth = 2)
    sat = lift(t -> Point3f(R * cos(t), 0.35f0 * R * sin(t), R * 0.8f0 * sin(t)), a.orbit_angle)
    mesh!(sc, lift(p -> Rect3f(p .- Vec3f(0.08), Vec3f(0.16)), sat); color = RGBf(0.85, 0.85, 0.9))
    mesh!(sc, lift(p -> Rect3f(p .- Vec3f(0.45, 0.01, 0.06), Vec3f(0.9, 0.02, 0.12)), sat); color = RGBf(0.2, 0.3, 0.8))
    # A label following the satellite sweeps across Earth and the right panel.
    # Keep its identity in a fixed, bounded heading; the orbit is illustrative.
    label!(ov,Point2f(0.27canvas[1],canvas[2]-35),"Black Hole Explorer · illustrative orbit";
           align=(:center,:top),alpha=a.orbit,fontsize=22)
    # the picture sharpening
    sharp = photon_ring_model()
    levels = range(EHT_BLUR, 4.0; length = 20)
    stack = [(b = blurred(sharp, GRID, f); b ./ maximum(b)) for f in levels]
    img = lift(a.focus) do f
        x = 1 + f * (length(stack) - 1)
        i = clamp(floor(Int, x), 1, length(stack) - 1)
        w = Float32(x - i)
        (1 - w) .* stack[i] .+ w .* stack[i+1]
    end
    image!(pic, (-60, 60), (-60, 60), img; colormap = HOT, colorrange = (0, 1))
    label!(ov, lift(r -> Point2f(GeometryBasics.origin(r)[1] + widths(r)[1] / 2, GeometryBasics.origin(r)[2] + widths(r)[2] + 8), Makie.viewport(pic.scene)), lift(f -> f < 0.5 ? "an Earth-sized telescope" : "a telescope reaching into space", a.focus);
           align = (:center, :bottom), alpha = Observable(1f0), fontsize = 24)
    caption!(ov, "Longer distances between telescopes: finer notes, sharper pictures", a.sharper_caption)
    return fig, a
end

"""
The keys of `build_space`'s arguments for the narration timing `T`: the globe
turning at 0.05 rad/s and the satellite going round at 0.25 rad/s throughout,
its orbit fading in 2 s into line 1; the picture sharpening, eased over the
first 60% of line 2, with the caption. `picture` are the keys the traced
picture draws, `labels` those only the labels do.
"""
function perform(::typeof(build_space), T::Timing)
    s, e = T.starts, T.ends
    # Keys on whole seconds: on a whole frame at any rate, so the rates stay exact.
    D = ceil(T.duration)
    picture = [
        "turn" => [(0f0, -1.6f0, :linear), (D, -1.6f0 + 0.05f0 * D, :linear)],
        "orbit" => ramp(s[1] + 2),
        "orbit_angle" => [(0f0, 0f0, :linear), (D, 0.25f0 * D, :linear)],
        "focus" => dial(s[2], 0.6f0 * (e[2] - s[2])),
    ]
    labels = ["sharper_caption" => ramp(s[2])]
    return (; picture, labels)
end

PERFORMED["c2_space"] = build_space
