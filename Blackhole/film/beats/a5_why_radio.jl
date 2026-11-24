# a5 · Why radio? Line 1: visible light's waves are far shorter, so a much
# smaller telescope would do. Line 2: an Earth-sized telescope is stitched
# from many, which needs every telescope to record the wave itself, for a
# computer to combine later. Line 3: radio can be recorded, visible light
# wiggles far too fast. Line 4 establishes opaque gas; line 5 clears it.
# Line 6 introduces Earth's absorbing atmosphere as a separate obstacle.
#
# Every quantity that changes is an argument the editor keys (see `perform`):
# each line's fade, the fog's, how far it has cleared, and the question.

function build_why_radio(canvas)
    fig, ov = frame2d(canvas; padding = (30, 30, 110, 90))
    a = (; wavelengths = Observable(0f0), recordings = Observable(0f0), sampling = Observable(0f0),
          fog = Observable(0f0), clear = Observable(0f0), air = Observable(0f0), question = Observable(0f0))
    ax = Axis(fig[1, 1]; backgroundcolor = SPACE, limits = (0, 16, 0, 9), aspect = DataAspect())
    hidedecorations!(ax); hidespines!(ax)
    write!(x, y, str, alpha; size = 26, align = (:left, :center), colour = :white) =
        filmtext!(ax, x, y; text = str, align, color = faded(colour, alpha), fontsize = size)

    # line 1: the two waves, and the telescope each would need
    one = a.wavelengths
    lines!(ax, wave(range(0, 7; length = 300), 0.3; amplitude = 0.7, origin = Point2f(0.6, 6.4)); color = faded(ACCENT, one), linewidth = 4)
    write!(0.6, 7.7, "radio light: 1.3 millimetres", one)
    lines!(ax, wave(range(0, 7; length = 3000), 12; amplitude = 0.25, origin = Point2f(0.6, 2.8)); color = faded(NOTE, one), linewidth = 1.5)
    write!(0.6, 3.6, "visible light: thousands of times shorter", one)
    poly!(ax, Circle(Point2f(12, 6.4), 1.6f0); color = lift(x -> (RGBf(0.15, 0.35, 0.7), x), one))
    write!(12, 4.4, "telescope needed: as wide as the Earth", one; align = (:center, :center), size = 22)
    poly!(ax, Circle(Point2f(12, 2.4), 0.05f0); color = faded(:white, one))
    write!(12, 1.7, "visible light: a few kilometres", one; align = (:center, :center), size = 22)

    # line 2: many telescopes, each recording, combined later
    two = a.recordings
    for (k, p) in enumerate((Point2f(1.6, 6.6), Point2f(1.6, 2.2), Point2f(5.2, 7.4), Point2f(5.2, 1.0)))
        dish!(ax, p, 1.3, two)
        lines!(ax, wave(range(0, 1.4; length = 80), 2.0; amplitude = 0.18, origin = p + Point2f(0.9, 0.5)); color = faded(ACCENT, two),
               linewidth = 2)
        arrows2d!(ax, [p + Point2f(2.5, 0.5)], [Point2f(10.4, 4.6) - (p + Point2f(2.5, 0.5))]; color = faded(:white, two),
                  shaftwidth = 2, tipwidth = 10, tiplength = 12)
    end
    box!(ax, Rect2f(10.6, 3.4, 4.4, 2.4), "computer:\ncombines the\nrecordings later", two)
    write!(8, 8.6, "every telescope records the wave itself", two; align = (:center, :center), size = 24)

    # line 3: radio can be recorded, visible light cannot
    three = a.sampling
    xs = range(0, 6.5; length = 400)
    lines!(ax, wave(xs, 0.35; amplitude = 1.0, origin = Point2f(0.8, 6.0)); color = faded(ACCENT, three), linewidth = 3)
    scatter!(ax, wave(range(0, 6.5; length = 34), 0.35; amplitude = 1.0, origin = Point2f(0.8, 6.0)); color = faded(:white, three),
             markersize = 9)
    write!(8.0, 6.0, "radio: electronics keep up ✓", three; colour = RGBf(0.6, 1, 0.6), size = 28)
    lines!(ax, wave(range(0, 6.5; length = 4000), 40; amplitude = 1.0, origin = Point2f(0.8, 2.4)); color = faded(NOTE, three),
           linewidth = 0.8)
    write!(8.0, 2.4, "visible light: 500 trillion\nwiggles a second ✗", three; colour = RGBf(1, 0.55, 0.5), size = 28)

    # line 4: the fog clears at 1.3 mm; the air lets it through above dry mountains
    fog = a.fog
    clear = a.clear
    ring = blurred(model_ring(), GRID, 12.0); ring = ring ./ maximum(ring)
    fogged = blurred(model_ring(), GRID, 40.0); fogged = 0.55 .* fogged ./ maximum(fogged) .+ 0.25
    image!(ax, (4.6, 11.4), (1.4, 8.2), lift(f -> (1 - f) .* fogged .+ f .* ring, clear); colormap = HOT, colorrange = (0, 1),
           alpha = fog)
    filmtext!(ax, 8.0, 0.9; text = lift(f -> f < 0.01 ? "longer radio waves: hidden in glowing gas" : "at 1.3 mm: the gas becomes transparent", clear),
          align = (:center, :center), color = faded(:white, fog), fontsize = 24)
    air = a.air
    mountain = Point2f[(1.0, 0.5), (5.6, 5.2), (7.4, 4.6), (10.2, 6.0), (15.0, 0.5)]
    poly!(ax, mountain; color = lift(x -> (RGBf(0.35, 0.3, 0.28), x), air))
    poly!(ax, Rect2f(0.6, 1.6, 14.8, 1.2); color = lift(x -> (RGBf(0.55, 0.62, 0.75), 0.4f0 * x), air))
    write!(15.8, 2.2, "damp air", air; align = (:right, :center), size = 24)
    dish!(ax, Point2f(10.2, 6.0), 0.9, air)
    write!(8.0, 8.2, "a second obstacle: water vapour in Earth's air", air; align = (:center, :center), size = 28)
    write!(8.0, 0.9, "high and dry: less absorbing air above the telescope", air; align = (:center, :center), size = 24)
    caption!(ov, "So why radio?", a.question)
    return fig, a
end

"""
The keys of `build_why_radio`'s arguments for the narration timing `T`: each of
lines 1 to 3 shows while it is spoken; the fogged ring from line 4 until line 6,
held for the whole explanation and cleared only on "The fog clears", 64% into
line 5; the damp air and the mountain from line 6. The question shows from 5 s
into line 1 until line 2.
"""
function perform(::typeof(build_why_radio), T::Timing)
    s, e = T.starts, T.ends
    shown(i) = inout(s[i], s[i + 1]; d_in = 0.6f0, d_out = 0.4f0)
    picture = [
        "wavelengths" => shown(1),
        "recordings" => shown(2),
        "sampling" => shown(3),
        "fog" => inout(s[4], s[6]),
        "clear" => dial(s[5] + 0.64f0 * (e[5] - s[5]), 1.8f0),
        "air" => ramp(s[6]),
    ]
    labels = [
        "question" => inout(s[1] + 5, s[2]),
    ]
    return (; picture, labels)
end

PERFORMED["a5_why_radio"] = build_why_radio
