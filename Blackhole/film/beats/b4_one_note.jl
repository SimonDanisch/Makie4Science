# b1 · Each pair hears one note. Left: the globe with one pair of telescopes
# and the line between them. Right: the stripe pattern that pair measures (its
# Fourier component), large, and the picture: wide stripes for a pair close
# together, fine ones for a pair far apart, and how strongly they are in it.
# Lines 2–4 explain the geometrical delay and the stripes. Line 6 rebuilds the
# picture from its stripes, coarse to fine, one note after
# another and then thousands.

"""The stripe pattern a pair at (u, v) measures, on the image grid: cos 2π(ux + vy)."""
stripes(u, v, g::ImageGrid) = [cos(2π * (u * x * UAS + v * y * UAS)) for x in coords(g), y in coords(g)]

"""How strongly the stripes of (u, v) are in the picture: |Σ I e^{-2πi(ux+vy)}|, the picture summing to 1."""
strength(u, v, img, g::ImageGrid) = abs(sum(img[i, j] * cis(-2π * (u * x * UAS + v * y * UAS))
                                            for (i, x) in enumerate(coords(g)), (j, y) in enumerate(coords(g))))

"""
    stripe_sums(img, counts) -> (; sums, stripes)

The picture `img` (n × n, indexed [x, y]) built up from its stripes, coarse to
fine: each note is one stripe pattern with its mirror, at the strength and
shift the picture has of it (a term of its discrete Fourier series). For each
count in `counts`, the sum of the first that many notes, and the stripes of the
last one (−1 to 1).
"""
function stripe_sums(img, counts)
    n = size(img, 1)
    fs = -(n ÷ 2)+1:(n ÷ 2)-1
    W = [cis(-2π * f * x / n) for f in fs, x in 0:n-1]
    F = W * img * transpose(W)
    # one of each mirror pair, the widest stripes first
    notes = [(a, b) for (a, p) in enumerate(fs), (b, q) in enumerate(fs) if q > 0 || (q == 0 && p >= 0)]
    sort!(notes; by = ((a, b),) -> (hypot(fs[a], fs[b]), atan(fs[b], fs[a])))
    total = zeros(n, n)
    sums = Matrix{Float32}[]; stripes = Matrix{Float32}[]
    for (k, (a, b)) in enumerate(notes)
        p, q = fs[a], fs[b]
        weight = (p == 0 && q == 0 ? 1 : 2) * abs(F[a, b]) / n^2
        pattern = [cos(2π * (p * x + q * y) / n + angle(F[a, b])) for x in 0:n-1, y in 0:n-1]
        total .+= weight .* pattern
        k in counts && (push!(sums, Float32.(total)); push!(stripes, Float32.(pattern)))
        k >= last(counts) && break
    end
    return (; sums, stripes)
end

"""Why a wider baseline gives finer fringes: delay B sin(θ), at fixed wavelength."""
function stripe_geometry!(ov, a)
    visible, recordings, pattern = a.diagram, a.recordings, a.pattern
    geometry = lift(*, visible, a.geometry_opacity)
    receivers=lift(*,geometry,a.receivers)
    wavefronts=lift(*,geometry,a.wavefronts)
    paths=lift(*,geometry,a.light_paths)
    delaymark=lift(*,geometry,a.delay_mark)
    phase_words = a.phase_words
    # Plain type on an empty background; the spoken explanation supplies the
    # sentences. Reveal each representation only when it is introduced.
    note!(pos, text; alpha = visible, fontsize = 25, align = (:center, :center)) =
        filmtext!(ov, pos; text, color = faded(:white, alpha), fontsize, align)
    state = lift(a.baseline, a.source_angle, a.wave_phase) do B, θ, phase
        pointa = Point2f(345 - 15B, 405)
        pointb = Point2f(345 + 15B, 405)
        direction = Vec2f(sin(θ), -cos(θ))
        delay = B * sin(θ)
        # `foot` is on B's light path and on the wavefront through A.
        foot = pointb - (30delay) * direction
        (; B, θ, delay, a=pointa, b=pointb, foot, direction, phase)
    end
    backdrop=poly!(ov, Rect2f(0, 0, 1280, 720); color = faded(SPACE, visible))
    # Own the shared controls on the schematic backdrop, not on a TextLabel
    # whose derived text/background alpha changes during the same transaction.
    # The latter loses reentrant derived-alpha updates in native playback.
    for key in (:shown,:diagram,:which,:reconstruction)
        plotattribute!(backdrop,key,getproperty(a,key))
    end
    note!(Point2f(640, 665), lift(stage -> stage >= 4 ? "Wider separation → finer stripes" :
          stage >= 3 ? "The recordings slip out of step — and back" : "One wave reaches two telescopes", a.geometry_stage);
          fontsize = 32)

    # Parallel wavefronts, clipped to the geometry panel. They move at the
    # same speed and wavelength even as the telescope separation changes.
    fronts = lift(state) do s
        n = Vec2f(cos(s.θ), sin(s.θ))
        points = Point2f[]
        for k in -15:3
            p = s.a + (30f0 * (k + mod(s.phase, 1f0))) * s.direction
            candidates = Point2f[]
            for x in (70f0, 620f0)
                q = p + ((x - p[1]) / n[1]) * n
                440 <= q[2] <= 560 && push!(candidates, q)
            end
            if abs(n[2]) > 1f-5
                for y in (440f0, 560f0)
                    q = p + ((y - p[2]) / n[2]) * n
                    70 <= q[1] <= 620 && push!(candidates, q)
                end
            end
            length(candidates) >= 2 && append!(points, (first(candidates), last(candidates), Point2f(NaN)))
        end
        isempty(points) ? [Point2f(NaN)] : points
    end
    lines!(ov, fronts; color = lift(a -> (NOTE, 0.55f0 * a), wavefronts), linewidth = 2)
    for key in (:a, :b)
        p = lift(s -> getproperty(s, key), state)
        lines!(ov, lift((s, q) -> [q - 150f0 * s.direction, q], state, p);
               color = faded(NOTE, paths), linewidth = 2)
        lines!(ov, lift(q -> [q + Vec2f(x, 0.025f0 * x^2) for x in range(-22f0, 22f0; length = 40)], p);
               color = faded(:white, receivers), linewidth = 3)
        lines!(ov, lift(q -> [q, q + Vec2f(0, -23), q + Vec2f(-18, -23), q + Vec2f(18, -23)], p);
               color = faded(:white, receivers), linewidth = 2)
        note!(lift(q -> q + Vec2f(0, -42), p), key === :a ? "A" : "B";
              alpha = receivers, fontsize = 24)
    end
    lines!(ov, lift(s -> [s.a, s.foot], state); color = faded(NOTE, delaymark), linewidth = 2, linestyle = :dash)
    lines!(ov, lift(s -> [s.b, s.foot], state); color = faded(ACCENT, delaymark), linewidth = 4)
    note!(lift(s -> (s.b + s.foot) / 2 + Vec2f(24, 0), state), "extra path";
          alpha = lift((a, s) -> a * Float32(s.delay > 0.08), delaymark, state), fontsize = 22, align = (:left, :center))
    lines!(ov, lift(s -> [Point2f(s.a[1], 344), Point2f(s.b[1], 344)], state);
           color = faded(:gray70, receivers), linewidth = 2)
    note!(Point2f(345, 321), lift(s -> s.B < 7 ? "close pair" : "wide pair", state);
          alpha = a.pair_label, fontsize = 22)

    xs = range(0f0, 1f0; length = 320)
    for (row, shift, colour, name) in ((540f0, false, NOTE, "A"), (460f0, true, ACCENT, "B"))
        lines!(ov, lift(state) do s
            phase = shift ? 2f0 * π * s.delay : 0f0
            [Point2f(755 + 445x, row + 25sin(2f0 * π * (4x - s.phase) - phase)) for x in xs]
        end; color = faded(colour, recordings), linewidth = 3)
        note!(Point2f(733, row), name; alpha = recordings, fontsize = 25)
    end
    note!(Point2f(990, 385), lift(s -> s.delay < 0.75f0 ? "Half a wavelength: opposite" :
          "One wavelength: in step", state); alpha = phase_words, fontsize = 25)

    angles = range(-0.45f0, 0.45f0; length = 500)
    image!(ov, (90, 1190), (112, 232), lift(s -> [cos(2π * s.B * sin(θ)) for θ in angles, _ in 1:12], state);
           colormap = [RGBf(0.02, 0.03, 0.08), NOTE], colorrange = (-1, 1), alpha = pattern)
    cursor = lift(s -> 90 + 1100 * (s.θ + 0.45f0) / 0.9f0, state)
    lines!(ov, lift(x -> [Point2f(x, 110), Point2f(x, 235)], cursor);
           color = faded(ACCENT, pattern), linewidth = 3)
    note!(Point2f(640, 80), "the same patch of sky"; alpha = pattern, fontsize = 23)
    note!(Point2f(640, 28), "Fixed wavelength · geometry enlarged"; fontsize = 17)
    return nothing
end

function build_one_note(canvas)
    fig, ov = frame2d(canvas; padding = (20, 30, 100, 30))
    a = (; which = Observable(1), shown = Observable(0f0), reconstruction = Observable(0f0),
          globe_visible = Observable(true), diagram = Observable(0f0),
          baseline_caption = Observable(0f0), note_caption = Observable(0f0),
          recordings = Observable(0f0), pattern = Observable(0f0), geometry_opacity = Observable(1f0),
          phase_words = Observable(0f0), baseline = Observable(3f0), source_angle = Observable(0f0),
          wave_phase = Observable(0f0), geometry_stage = Observable(2), pair_label = Observable(0f0),
          receivers=Observable(1f0),wavefronts=Observable(1f0),light_paths=Observable(1f0),delay_mark=Observable(1f0),
          note_count = Observable(1))
    ls = LScene(fig[1, 1]; show_axis = false, scenekw = (backgroundcolor = SPACE, lights = sunlight()))
    cam3d!(ls.scene; center = false)
    sc = ls.scene
    str = picture_axis(fig[1, 2]; title = "the stripes this pair measures", titlesize = 26)
    pic = picture_axis(fig[1, 3]; title = "the picture", titlesize = 22)
    colsize!(fig.layout, 1, Relative(0.37))
    colsize!(fig.layout, 3, Relative(0.17))
    truth = model_ring()
    image!(pic, (-60, 60), (-60, 60), truth ./ maximum(truth); colormap = HOT, colorrange = (0, 1))
    # the two pairs: Arizona–Mexico (close), Chile–Spain (far), at one moment of the night
    H = 0.4
    pairs = [(EHT[3], EHT[5], (EHT[3].lat, EHT[3].lon), (EHT[5].lat, EHT[5].lon)),
             (EHT[6], EHT[8], (EHT[6].lat, EHT[6].lon), (EHT[8].lat, EHT[8].lon))]
    uvs = [uv(a, b, H) for (a, b, _, _) in pairs]
    pats = [stripes(u, v, GRID) for (u, v) in uvs]
    amps = [strength(u, v, truth, GRID) for (u, v) in uvs]
    which, shown = a.which, a.shown
    image!(str, (-60, 60), (-60, 60), lift(k -> pats[k], which); colormap = [RGBf(0.02, 0.03, 0.08), NOTE], colorrange = (-1, 1),
           alpha = shown)
    turn = Observable(Float32(deg2rad(-90 + 60)))
    g = globe!(sc, turn)
    labels_only() || plotattribute!(g.earth,:visible,a.globe_visible)
    look!(sc, Pose((0, -3.9, 1.5), (0, 0, 0.15); fov = 40))
    for (k, (_, _, pa, pb)) in enumerate(pairs)
        pa_obs, pb_obs = g.point(pa...; h = 0.012), g.point(pb...; h = 0.012)
        on_ = lift((k_, s) -> s * Float32(k_ == k), which, shown)
        lines!(sc, lift((p, q) -> arc(p, q; rise = 0.1f0), pa_obs, pb_obs); color = lift(x -> (ACCENT, x), on_), linewidth = 5)
        scatter!(sc, lift((p, q) -> [p, q], pa_obs, pb_obs); color = lift(x -> (ACCENT, x), on_), markersize = 18)
    end
    four = a.reconstruction
    # The schematic and reconstruction fill the frame; do not render a globe
    # underneath them.
    connect!(sc.visible, a.globe_visible)
    diagram = a.diagram
    before = lift((a, f, d) -> a * (1 - f) * (1 - d), shown, four, diagram)
    names = ["Arizona – Mexico: close together", "Chile – Spain: far apart"]
    label!(ov, Point2f(245, 650), lift(k -> names[k], which); alpha = before, fontsize = 28)
    label!(ov, Point2f(1148, 190), lift(k -> "how strongly they\nare in it: $(round(Int, 100amps[k])) %", which);
           alpha = before, fontsize = 22)
    caption!(ov, lift(k -> k == 1 ? "wide stripes: the coarse shape" : "fine stripes: the small details", which),
             a.baseline_caption)
    caption!(ov, "Each pair of telescopes hears one note of the picture", a.note_caption)

    stripe_geometry!(ov, a)

    # Line 6: the picture rebuilt from its stripes; the first notes one by one, then thousands.
    counts = vcat(1:12, unique(round.(Int, exp.(range(log(13), log(1400); length = 90)))))
    built = cached("stripe_sums_$(length(counts))_$(last(counts))") do
        stripe_sums(truth, counts)
    end
    peak = maximum(truth)
    step = lift(n -> clamp(searchsortedlast(counts, n), 1, length(counts)), a.note_count)
    W, Hc = canvas
    # black, as the picture's own background, so its square does not show
    poly!(ov, Rect2f(0, 0, W, Hc); color = faded(RGBf(0, 0, 0), four))
    image!(ov, (150, 470), (200, 520), lift(k -> built.stripes[k], step); colormap = [RGBf(0.02, 0.03, 0.08), NOTE],
           colorrange = (-1, 1), alpha = four)
    image!(ov, (640, 1100), (110, 570), lift(k -> clamp.(built.sums[k] ./ peak, 0f0, 1f0), step); colormap = HOT,
           colorrange = (0, 1), alpha = four)
    label!(ov, Point2f(310, 560), "the newest note"; alpha = four, fontsize = 26)
    label!(ov, Point2f(870, 610), "all the notes so far, added up"; alpha = four, fontsize = 26)
    lines!(ov, [Point2f(505, 360), Point2f(600, 360)]; color = faded(:white, four), linewidth = 4)
    lines!(ov, [Point2f(580, 378), Point2f(602, 360), Point2f(580, 342)]; color = faded(:white, four), linewidth = 4)
    label!(ov, Point2f(310, 160), lift(k -> counts[k] == 1 ? "1 note" : "$(counts[k]) notes", step); alpha = four, fontsize = 30)
    caption!(ov, lift(k -> counts[k] <= 12 ? "wide stripes: the rough shape" : "fine stripes: the sharp details", step), four)
    return fig, a
end

function perform(::typeof(build_one_note), T::Timing)
    s, e = T.starts, T.ends
    within(i, u) = s[i] + u * (e[i] - s[i])
    picture = [
        "which" => [(0f0, 1, :hold), (within(4, 0.5f0), 2, :hold)],
        "shown" => ramp(s[1] + 2),
        "globe_visible" => [(0f0, true, :hold), (s[2], false, :hold), (s[5], true, :hold), (s[6], false, :hold)],
    ]
    # The schematic is in the annotation overlay, so only label clips need its keys.
    labels = [
        "reconstruction" => ramp(s[6]),
        "diagram" => inout(s[2], s[5]),
        "receivers" => ramp(s[2]),
        "wavefronts" => ramp(within(2,0.2f0)),
        "light_paths" => ramp(within(2,0.35f0)),
        "delay_mark" => ramp(within(2,0.6f0)),
        "baseline_caption" => inout(s[1], s[2]),
        "note_caption" => inout(s[5], s[6]),
        "recordings" => inout(within(2, 0.75f0), s[5]),
        "pattern" => inout(within(3, 0.72f0), s[5]),
        "geometry_opacity" => [(0f0, 1f0, :hold), (s[3], 0.45f0, :hold), (s[4], 1f0, :hold)],
        "phase_words" => inout(s[3], s[4]),
        "baseline" => eased([s[4] => 3, within(4, 0.6f0) => 12]),
        "geometry_stage" => [(0f0, 2, :hold), (s[3], 3, :hold), (s[4], 4, :hold)],
        "pair_label" => inout(s[4], s[5]),
        "wave_phase" => [(s[2], 0.55f0 * s[2], :linear), (s[5] + 0.6f0, 0.55f0 * (s[5] + 0.6f0), :linear)],
    ]
    # Key the actual angle and count, rather than a clock evaluated inside the scene.
    angle(t) = t < s[3] ? asin(0.5f0 / 3f0) * ease((t - within(2, 0.3f0)) / (0.6f0 * (e[2] - s[2]))) :
        t < s[4] ? asin((0.5f0 + 0.5f0 * ease((t - within(3, 0.35f0)) / (0.4f0 * (e[3] - s[3])))) / 3f0) :
        asin(1f0 / 3f0) * (0.5f0 + 0.5f0 * cos(2f0 * π * 0.12f0 * (t - s[4])))
    push!(labels, "source_angle" => sampledkeys(angle, s[2], s[5] + 0.6f0))
    heard(t) = (u = t - s[6] - 0.4f0; u < 3.6f0 ? clamp(floor(Int, u / 0.6f0) + 1, 1, 6) :
        round(Int, exp(log(6) + (log(1400) - log(6)) * ease((u - 3.6f0) / 4f0))))
    counts = [(0f0, 1, :hold)]
    for t in s[6]:1f0/60: min(T.duration, s[6] + 8.1f0)
        n = heard(t)
        n == last(counts)[2] || push!(counts, (t, n, :hold))
    end
    push!(labels, "note_count" => counts)
    return (; picture, labels)
end

PERFORMED["b4_one_note"] = build_one_note
