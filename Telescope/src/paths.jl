# B6 to B8: why the focus is a spot, in three steps. Four points of the lens
# send their waves to a pixel; each path is straightened into a wave that ends
# at the pixel, so whether crests meet crests can be seen, and added up.
#   1. the centre pixel: every path equally long, in step, bright
#   2. one step up: the paths slip out of step, the sum gets smaller
#   3. where the edges are a whole wavelength apart, every point and the one
#      half a lens below it cancel: the dark gap at the edge of the spot

"""How far apart the straightened waves of a panel are stacked."""
const UNROLL_GAP = 3f0
wave_baseline(row) = -UNROLL_GAP * (row - 1)
sum_baseline(n) = -UNROLL_GAP * (n - 1) - 3.6f0

"""The lens's cross-section's brightness in the paths beats."""
const PATHS_LENS = 0.6f0

"""
The paths beats' light: the telescope's wave dimmed to context at `phase`, the
lens faintly, the paths from the four lens points to the pixel at height `y`
(at `paths`), and the sensor's bars with that pixel framed.
"""
struct PathsLight
    a::Act
    wl::Wavelets
    cs::Vector{Float32}
    v::Vector{Float32}
end
PathsLight(a::Act) = PathsLight(a, lens_points(a, Point2f(a.xf, 0)), readout(a.g, a.I, a.xf)...)

function (l::PathsLight)(phase, y, paths)
    a = l.a
    tex = dim(steady_glow(a.A, a.I, a.g, phase), 0.1f0)
    show_lens!(tex, a.section; alpha = PATHS_LENS)
    if paths > 0
        for (k, c) in enumerate(POINT_COLORS)
            path_glow!(tex, a.g, l.wl, k, Point2f(a.xf, y), phase, c; width = 0.2f0, gain = Float32(paths))
        end
    end
    return readout_glow!(tex, a.g, a.xf, l.cs, [(l.v, SUNLIGHT)]; highlight = y)
end

"""
The fades of a paths beat's panel, from its arguments: the title and axis
(`panel`), the waves once they are laid out (`morph` at 1), their sum
(`sums`) and the extra-distance brackets (`marks`).
"""
function panel_fades(args)
    shown = lift((m, p) -> m >= 1 ? p : 0f0, args.morph, args.panel)
    return (; title = args.panel, shown, sums = lift(*, args.sums, shown), marks = lift(*, args.marks, shown))
end

"""
    unrolled!(ins, pos, wl, members, args, fades; title, first, xlabel, name) -> Axis

A panel of the paths beats: the path from each lens point in `members` to the
pixel, straightened into a wave that ends at the pixel (the dashed line), the
last three wavelengths of it, stacked; below them in white their sum, what the
pixel gets. Each wave's extra distance (compared with the shortest) is a
bracket. `first` labels the pixel line. Named `name_…`.
"""
function unrolled!(ins, pos, wl::Wavelets, members, args, fades; title, first = true, xlabel = true, name)
    n = length(members)
    ysum = sum_baseline(n)
    beige(c = ON_BEIGE) = faded(c, fades.title)
    ax = Axis(pos; INSET..., title, titlesize = 22, titlecolor = beige(), limits = (-3.2, 0.9, ysum - 2.4f0, 2.2),
              xlabel = xlabel ? "← along the path, in wavelengths" : "", xlabelsize = 18, xlabelcolor = beige(),
              xticksvisible = xlabel, xticklabelsvisible = xlabel, xticks = [-3, -2, -1, 0],
              xticklabelcolor = beige(), xticklabelsize = 16, xtickcolor = beige(), bottomspinecolor = beige(:gray50))
    u = range(-3.2f0, 0f0; length = 400)
    target = lift(y -> Point2f(wl.focus[1], y), args.y)
    delays = lift(t -> [delay(wl, wl.src[m], t) for m in members], target)
    waves = [lift((d, φ) -> [Point2f(ui, wave_baseline(row) + cos(2f0 * Float32(π) * (d[row] + ui - φ))) for ui in u],
                  delays, args.phase) for row in 1:n]
    for (row, (m, wave)) in enumerate(zip(members, waves))
        c = POINT_COLORS[m]
        p = lines!(ax, wave; color = rgbf(c), linewidth = 3, alpha = fades.shown, name = Symbol(name, :_wave, m))
        object!(ins, "$title · wave $m", p)
        # its extra distance, once it has one
        extra = lift(d -> d[row] - minimum(d), delays)
        mark = lift((e, a) -> e > 0.02f0 ? a : 0f0, extra, fades.marks)
        y = wave_baseline(row) + 1.5f0
        lines!(ax, lift(e -> [Point2f(-e, y - 0.25f0), Point2f(-e, y), Point2f(0, y), Point2f(0, y - 0.25f0)], extra);
               color = rgbf(c), linewidth = 2, alpha = mark)
        text!(ax, lift(e -> Point2f(-e - 0.05f0, y), extra); text = lift(e -> "$(fraction(e)) wavelength farther", extra),
              color = rgbf(c), alpha = mark, fontsize = 16, align = (:right, :center))
    end
    # the sum, scaled so that all waves in step reach 2
    translate!(hlines!(ax, [ysum]; color = :white, linewidth = 1, alpha = lift(a -> 0.25f0 * a, fades.title)), 0, 0, -1)
    total = lift(ws -> [Point2f(p[1], ysum + 2f0 * sum(w[i][2] - wave_baseline(r) for (r, w) in enumerate(ws)) / n)
                        for (i, p) in enumerate(ws[1])], lift((w...) -> w, waves...))
    object!(ins, "$title · sum", lines!(ax, total; color = :white, linewidth = 4, alpha = fades.sums,
                                        name = Symbol(name, :_sum)))
    text!(ax, 0.08, ysum; text = "sum", color = :white, alpha = fades.sums, fontsize = 16, align = (:left, :center))
    vlines!(ax, [0]; color = :white, alpha = lift(a -> 0.6f0 * a, fades.title), linestyle = :dash, linewidth = 2)
    first && text!(ax, 0.08, 1.0; text = "pixel", color = :white, alpha = lift(a -> 0.8f0 * a, fades.title),
                   fontsize = 16, align = (:left, :center))
    return ax
end

"""Where the data point `p` of axis `ax` shows, in figure pixels."""
function axis_position(lims, vp, p)
    rel = (Vec2f(p) .- Vec2f(minimum(lims))) ./ Vec2f(widths(lims))
    return Point2f(Vec2f(origin(vp)) .+ rel .* Vec2f(widths(vp)))
end

"""
The paths being laid out straight, `morph` (0..1) of the way: each path, as the
3D scene `sc` shows it, eased into the wave its panel shows for it. Drawn in
the overlay while `morph` is between 0 and 1.
"""
function straighten!(ov, sc, panels, wl, args)
    target = lift(y -> Point2f(wl.focus[1], y), args.y)
    moving = lift(m -> 0 < m < 1, args.morph)
    for (ax, members) in panels, (row, k) in enumerate(members)
        src = wl.src[k]
        pts = lift(args.morph, args.phase, target, sc.camera.projectionview, ax.finallimits, ax.scene.viewport) do m, φ, t, pv, lims, vp
            e = ease(m)
            dk = delay(wl, src, t)
            map(range(0f0, 1f0; length = 120)) do s
                a = screen_position(pv, sc.viewport[], Point3f(W * (src + s * (t - src))..., 0))
                ui = -3.2f0 * (1 - s)
                b = axis_position(lims, vp, Point2f(ui, wave_baseline(row) + cos(2f0 * Float32(π) * (dk + ui - φ))))
                (1 - e) * a + e * b
            end
        end
        lines!(ov, pts; color = rgbf(POINT_COLORS[k]), linewidth = 3, visible = moving)
    end
    return ov
end

"""
    build_paths(d; layouts, size) -> NamedTuple

A paths beat's picture: the cutaway from above on the left, its light keyed
by `args.phase`, `args.y` (the pixel) and `args.paths`; on the right the
panels of each layout in `layouts`, `(rows, titles)` pairs, of which
`args.layout` shows one (1, the first, if there is one).
"""
function build_paths(d::TelescopeData; layouts, size = (1280, 720))
    a = d.act
    ins = Inspector()
    args = (phase = Observable(0f0), y = Observable(0f0), paths = Observable(1f0), panel = Observable(1f0),
            sums = Observable(1f0), morph = Observable(1f0), marks = Observable(0f0), layout = Observable(1))
    fig = Figure(; size, backgroundcolor = :black, figure_padding = (0, 0, SUBTITLES, 0))
    nrows = maximum(length(rows) for (rows, _) in layouts)
    ls = LScene(fig[1:nrows, 1]; show_axis = false,
                scenekw = (lights = [AmbientLight(RGBf(0.01, 0.01, 0.012))], backgroundcolor = :black))
    light = PathsLight(a)
    wl = light.wl
    fades = panel_fades(args)
    shown = Tuple{Axis, Vector{Int}}[]
    for (l, (rows, titles)) in enumerate(layouts)
        axes = map(enumerate(zip(rows, titles))) do (r, (members, title))
            cell = length(rows) == 1 ? fig[1:nrows, 2] : fig[r, 2]
            ax = unrolled!(ins, cell, wl, members, args, fades; title, first = r == 1, xlabel = r == length(rows),
                           name = Symbol(:panel, l, :_, r))
            on(k -> (ax.blockscene.visible[] = k == l), args.layout; update = true)
            (ax, collect(members))
        end
        l == 1 && append!(shown, axes)
    end
    colsize!(fig.layout, 2, Relative(0.34))
    sc = ls.scene
    cam3d!(sc; center = false)
    telescope!(sc, a.tel, a.g, lift(light, args.phase, args.y, args.paths); inspector = ins)
    look!(sc, Pose((5.6, -0.8, 19), (5.6, 0, 0); fov = 40))
    ov = Scene(fig.scene; camera = campixel!, clear = false)
    straighten!(ov, sc, shown, wl, args)
    # captions under the cutaway they describe, clear of the panel's axis label
    vp = viewport(sc)[]
    centre = origin(vp)[1] + widths(vp)[1] / 2
    return (; fig, sc, ov, ins, args, centre, wl)
end

"""The paths beats' result as the editor takes it."""
paths_part(p, ins) = (scene = p.fig.scene, args = p.args, objects = ins.objects, controls = ins.controls)

"""A paths beat's pixel, as a callout anchor following `args.y`."""
pixel_anchor(a::Act, args) = lift(y -> w3(a.xf, y), args.y)

const PATHS_TITLE = "each path, straightened out"

function build_centre(d::TelescopeData; size = (1280, 720))
    a = d.act
    p = build_paths(d; layouts = [([1:4], [PATHS_TITLE])], size)
    callout!(p.ins, p.ov, p.sc, :label_points, w3(a.xexit, 15); text = "4 points of the lens (really: every point)",
             offset = (20, 170))
    callout!(p.ins, p.ov, p.sc, :label_pixel, w3(a.xf, 0); text = "the centre pixel", offset = (-40, 100))
    caption!(p.ins, p.ov, :caption_together; line = 1, centre = p.centre,
             text = "All paths take equally long: the crests arrive together")
    caption!(p.ins, p.ov, :caption_bright; centre = p.centre, text = "→ they add up: the centre pixel is bright")
    return paths_part(p, p.ins)
end

keys_centre(d::TelescopeData, tm::Timing) = animation(Dict(
    "args.phase" => ramp(0, tm.duration, 0, 0.5f0 * tm.duration), "args.paths" => appear(tm, 1),
    "args.morph" => through(tm, 2), "args.panel" => appear(tm, 2), "args.sums" => appear(tm, 4),
    "label_points.alpha" => appear(tm, 1), "label_pixel.alpha" => appear(tm, 1; delay = 2f0),
    "caption_together.alpha" => appear(tm, 3), "caption_bright.alpha" => appear(tm, 4)))

beat_centre() = Beat("b07_centre", [
    "Every point of the lens sends its own wave to every pixel. Let's follow four of them, to the centre pixel.",
    "To compare them, we straighten each path out, and lay them side by side, all ending at the pixel.",
    "The lens is shaped so that all these paths take [equally](+2) long, so their crests arrive at the [same](+2) moment.",
    "Added up, they make one big wave: the centre pixel is bright.",
], build_centre, keys_centre)

function build_dimmer(d::TelescopeData; size = (1280, 720))
    a = d.act
    p = build_paths(d; layouts = [([1:4], [PATHS_TITLE])], size)
    callout!(p.ins, p.ov, p.sc, :label_pixel, pixel_anchor(a, p.args); text = "a pixel higher up", offset = (-40, 100))
    callout!(p.ins, p.ov, p.sc, :label_closer, w3(a.xexit, 15); text = "a bit closer", offset = (20, 120))
    callout!(p.ins, p.ov, p.sc, :label_farther, w3(a.xexit, -7.5); text = "a bit farther", offset = (20, -110))
    caption!(p.ins, p.ov, :caption_slip; line = 1, centre = p.centre,
             text = "The waves arrive out of step: their sum gets smaller")
    caption!(p.ins, p.ov, :caption_dimmer; centre = p.centre, text = "→ a dimmer pixel")
    return paths_part(p, p.ins)
end

keys_dimmer(d::TelescopeData, tm::Timing) = animation(Dict(
    "args.phase" => ramp(0, tm.duration, 0, 0.5f0 * tm.duration),
    "args.y" => ramp(tm.starts[1], tm.ends[2], 0, half_height(d.act); ease = :smooth), "args.marks" => appear(tm, 3),
    "label_pixel.alpha" => appear(tm, 1), "label_closer.alpha" => appear(tm, 2),
    "label_farther.alpha" => appear(tm, 2; delay = 1.5f0),
    "caption_slip.alpha" => appear(tm, 3), "caption_dimmer.alpha" => appear(tm, 4)))

beat_dimmer() = Beat("b08_dimmer", [
    "[Now](-1) let's move to a pixel a little [higher](+2) up.",
    "[It's](-1) a bit [closer](+2) to the top of the lens, and a bit [farther](+2) from the bottom.",
    "[So](-1) the waves [no](+2) longer arrive in step. They slip apart, and their sum gets smaller.",
    "[This](-1) pixel is [dimmer](+2).",
], build_dimmer, keys_dimmer)

function build_dark(d::TelescopeData; size = (1280, 720))
    a = d.act
    p = build_paths(d; layouts = [([1:4], [PATHS_TITLE]), ([[1, 3], [2, 4]], ["pair 1", "pair 2"])], size)
    # how much farther each point is from the dark pixel than the nearest one
    y1 = dark_height(a)
    dist = [delay(p.wl, s, Point2f(a.xf, y1)) for s in p.wl.src]
    for (k, (s, dk)) in enumerate(zip(p.wl.src, dist))
        callout!(p.ins, p.ov, p.sc, Symbol(:label_point, k), w3(s[1], s[2]); text = fraction(dk - minimum(dist)),
                 offset = (-34, 0))
    end
    callout!(p.ins, p.ov, p.sc, :label_farther, w3(a.xexit, 15);
             text = "how much farther from this pixel (wavelengths)", offset = (20, 170))
    callout!(p.ins, p.ov, p.sc, :label_bottom, w3(a.xexit, -15); text = "bottom edge: 1 wavelength farther",
             offset = (30, -70))
    callout!(p.ins, p.ov, p.sc, :label_pixel, pixel_anchor(a, p.args); text = "a pixel 4 wavelengths up",
             offset = (-40, 100))
    caption!(p.ins, p.ov, :caption_pairs; line = 1, centre = p.centre,
             text = "Each point and the one half a lens lower: ½ wavelength apart")
    caption!(p.ins, p.ov, :caption_cancel; centre = p.centre, text = "→ crest meets trough: every pair cancels")
    caption!(p.ins, p.ov, :caption_dark; centre = p.centre,
             text = "Every pair cancels → a dark pixel: the edge of the spot")
    return paths_part(p, p.ins)
end

function keys_dark(d::TelescopeData, tm::Timing)
    a = d.act
    s3, s5 = tm.starts[3], tm.starts[5]
    numbers = appear(tm, 2)
    before5 = switch(s5, 1f0, 0f0)
    keys = Dict(
        "args.phase" => ramp(0, tm.duration, 0, 0.5f0 * tm.duration),
        "args.y" => ramp(tm.starts[1], tm.ends[1], half_height(a), dark_height(a); ease = :smooth),
        "args.layout" => switch(s3, 1, 2), "args.marks" => appear(tm, 3),
        # the four waves are shown summed; paired, each pair's sum comes in on line 4
        "args.sums" => switch(s3, 1f0, 0f0) + appear(tm, 4),
        "label_farther.alpha" => numbers, "label_bottom.alpha" => after(tm, 1), "label_pixel.alpha" => appear(tm, 1),
        "caption_pairs.alpha" => appear(tm, 3) * before5, "caption_cancel.alpha" => appear(tm, 4) * before5,
        "caption_dark.alpha" => switch(s5, 0f0, 1f0))
    for k in 1:4
        keys["label_point$k.alpha"] = numbers
    end
    return animation(keys)
end

beat_dark() = Beat("b09_dark", [
    "Keep going, until the bottom edge of the lens is a [whole](+2) wavelength farther away than the top.",
    "These numbers show how much farther each point is: zero, a quarter, a half, three quarters.",
    "[Now](-1) pair each point with the one [half](+2) a lens below it. In every pair, one wave is half a wavelength behind the other.",
    "[Crest](+2) meets [trough](+2), so every pair cancels.",
    "[This](-1) pixel is [dark](+2): it's the dark gap, at the edge of the spot.",
], build_dark, keys_dark)
