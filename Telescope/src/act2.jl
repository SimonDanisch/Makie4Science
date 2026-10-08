# Act 2: why a camera lens with a small opening can be sharp, why it needs
# several glasses, and which source of blur limits each instrument.

# ── C1: the window again ─────────────────────────────────────────────────────

"""
The window beat's light for one pair of sources at `time` (periods): their
crests at `faint`, the one crest of each passing nearest the window's middle
drawn bright by `lit`.
"""
window_pair_light(w::WindowSetups, sources, time, faint, lit) =
    wave_material(toimage(pair_window_glow(w.g, time, sources, w.window; λ = w.λ, faint, highlight = lit)); scale = 2f0)

function build_window_again(d::TelescopeData; size = (1280, 720))
    w = d.windows
    fig, sc, ov = frame3d(Pose((0, -2.2, 28.5), (0, -1.9, 0); fov = 40); size)
    ins = Inspector()
    softbox!(sc, Point3f(-4, -7, 45), 24, 8; Le = (160, 160, 160), name = :softbox_key)
    softbox!(sc, Point3f(8, 10, 40), 16, 6; Le = (100, 100, 112), name = :softbox_fill)
    time = Observable(0f0)
    fades = (stars = (Observable(0f0), Observable(0f0)), scene = (Observable(0f0), Observable(0f0)))
    b = bounds(w.g)
    for (key, sources, off) in ((:stars, w.stars, STACKED[1]), (:scene, w.scene, STACKED[2]))
        shown, lit = fades[key]
        visible = lift(>(0), shown)
        material = lift((t, s, l) -> window_pair_light(w, sources, t, 0.35f0 * s, l), time, shown, lit)
        plane = mesh!(sc, sheet(Rect2f(minimum(b) + Vec2f(off[1], off[2]), widths(b)), 0.01f0); material, visible,
                      name = Symbol(:plane_, key), inspectable = false)
        solid!(ins, "Light · $key", plane; materials = false)
        frame = window_frame!(sc, Rect2f(minimum(w.window) + Vec2f(off[1], off[2]), widths(w.window));
                              name = Symbol(:frame_, key), visible)
        solid!(ins, "Window · $key", frame)
    end
    at(off, x, y) = Point3f(off[1] + x, off[2] + y, 0)
    beside(off) = at(off, maximum(w.window)[1] + 0.2f0, 0)
    top, bottom = STACKED
    s_stars = slip(w.stars..., w.window, w.λ)
    s_scene = slip(w.scene..., w.window, w.λ)
    # every label points at the waves; the windows' readings to the right of them
    callout!(ins, ov, sc, :label_stars, at(top, -8, 1.5f0); text = "two close directions\nin the sky", offset = (-90, 0))
    callout!(ins, ov, sc, :label_stars_slip, beside(top); offset = (110, 0),
             text = "in the window:\nonly $(fraction(s_stars)) wavelength\napart")
    callout!(ins, ov, sc, :label_scene, at(bottom, -3, 0); text = "two details\nin this scene", offset = (-250, 0))
    callout!(ins, ov, sc, :label_scene_slip, beside(bottom); offset = (110, 0),
             text = "in the window:\n$(round(Int, s_scene)) wavelengths\napart")
    caption!(ins, ov, :caption_closer; line = 1, text = "Closer directions need a wider opening")
    caption!(ins, ov, :caption_edges; text = "A wide picture also needs sharp edges")
    args = (; time, stars_shown = fades.stars[1], stars_lit = fades.stars[2], scene_shown = fades.scene[1],
            scene_lit = fades.scene[2])
    return (scene = fig.scene, args, objects = ins.objects, controls = ins.controls)
end

keys_window_again(d::TelescopeData, tm::Timing) = animation(Dict(
    "args.time" => ramp(0, tm.duration, 0, 1.2f0 * tm.duration),
    "args.stars_shown" => appear(tm, 1), "args.stars_lit" => appear(tm, 2),
    "args.scene_shown" => appear(tm, 3), "args.scene_lit" => appear(tm, 4),
    "label_stars.alpha" => appear(tm, 2), "label_stars_slip.alpha" => appear(tm, 2; delay = 2f0),
    "label_scene.alpha" => appear(tm, 3), "label_scene_slip.alpha" => appear(tm, 4),
    "caption_closer.alpha" => appear(tm, 5), "caption_edges.alpha" => appear(tm, 6)))

beat_window_again() = Beat("c1_window_again", [
    "[So](-1) how can a camera lens, with its [small](+2) opening, be sharp? Remember the window from the beginning.",
    "[These](-1) two stars are extremely [close](+2) together in the sky. Their waves arrive from almost the [same](+2) direction. Across this small window they slip apart by only a quarter of a wavelength.",
    "In [this](-1) everyday scene, the two details we've picked are farther apart in [angle](+2). Their waves arrive from clearly different directions.",
    "Across the very [same](+2) small window, their crests slip apart by two whole wavelengths. Easy to tell apart.",
    "[It's](-1) the separation in [direction](+2) that matters, [not](+2) simply whether the object is near or far. For these details, the small opening is enough.",
    "[But](-1) the camera must keep a [wide](+2) picture sharp, [including](+2) its edges. Light from there enters at an angle. Our telescope concentrates on a small patch near the middle of its view.",
], build_window_again, keys_window_again)

# ── C3, C4: one lens and three ───────────────────────────────────────────────

"""How fast the lens beats' rays travel: millimetres per second."""
const RAY_SPEED = 40f0

"""
Lens `i`'s cut: each fan's rays, travelled `travel[k]` seconds (not set off
while 0), and where its light lands plotted behind the sensor once it has
arrived (`zoom_plot!`).
"""
function fans_light(d::LensDemo, i, travel)
    lens, g = d.lenses[i], d.grids[i]
    tex = fill(Hikari.RGBSpectrum(0f0, 0f0, 0f0, 1f0), size(g))
    paths, colours = Vector{Point2f}[], NTuple{3,Float32}[]
    for (k, fan) in enumerate(d.fans)
        travel[k] > 0 || continue
        append!(paths, [truncate_path(q, RAY_SPEED * travel[k]) for q in d.paths[i, k]])
        append!(colours, fill(fan.tint, length(d.paths[i, k])))
        grow = clamp((travel[k] - landing_time(d, i, 0f0; speed = RAY_SPEED)) / 1.2f0, 0f0, 1f0)
        zoom_plot!(tex, g, lens.sys.sensor, d.centres[i, k], d.profiles[i, k], fan.tint;
                   d.zoom, d.window, d.bright, d.height, alpha = min(1f0, 3grow), grow)
    end
    tex .+= ray_glow(g, paths, colours)
    return tex
end

"""When the plot of lens `i`'s fan, set off at `t0`, has arrived and grown out: when its label shows."""
plot_shown(d::LensDemo, i, t0) = ramp(landing_time(d, i, t0; speed = RAY_SPEED) + 1.2f0,
                                      landing_time(d, i, t0; speed = RAY_SPEED) + 1.8f0)

"""How far fan `k` of lens `i` has travelled: 0 until `t0`, then a second a second."""
travelled_keys(t0, T) = ramp(t0, T, 0, T - t0)

"""
Both lenses, the single one (`one`) and the three-element one (`three`, shown
while `args.second`), each with its fans' rays and plots glowing on its cut,
travelled as `args.ray_<lens>_<fan>` say.
"""
function build_fans(d::LensDemo; pose, scale = 2f0, size = (1280, 720))
    fig, sc, ov = frame3d(pose; size)
    ins = Inspector()
    nf = length(d.fans)
    travel = [[Observable(0f0) for _ in 1:nf] for _ in 1:2]
    second = Observable(false)
    for (i, (lens, g, off, name)) in enumerate(zip(d.lenses, d.grids, d.offsets, (:one, :three)))
        tex = lift((t...) -> fans_light(d, i, t), travel[i]...)
        cutaway!(sc, optics_meshes(lens.sys.elements, lens.parts), g, tex, lens.sys.sensor / 2; S = LENS_S,
                 offset = off, studio = i == 1, visible = i == 1 ? true : second, scale, name, inspector = ins)
    end
    rays = (Symbol(:ray_, i, :_, k) => travel[i][k] for i in 1:2 for k in 1:nf)
    return (; fig, sc, ov, ins, args = (; second, rays...))
end

fans_part(p) = (scene = p.fig.scene, args = p.args, objects = p.ins.objects, controls = p.ins.controls)

function build_lenses(d::TelescopeData; size = (1280, 720))
    l = d.lenses
    p = build_fans(l; pose = lens_pose(l), size)
    callout!(p.ins, p.ov, p.sc, :label_one, lens_point(l, 1, -3, 10); text = "one lens", offset = (-40, 10))
    callout!(p.ins, p.ov, p.sc, :label_centre, plot_tip(l, 1, 1); text = "picture centre:\ntight group",
             offset = (40, -30))
    # the smeared plot is named on line 3, and keeps its name
    callout!(p.ins, p.ov, p.sc, :label_edge, plot_tip(l, 1, 2); text = "towards picture edge (15°):\nsmeared out",
             offset = (45, 0))
    callout!(p.ins, p.ov, p.sc, :label_smear, plot_tip(l, 1, 2); text = "lens smear\n(towards picture edge, 15°)",
             offset = (45, 0))
    callout!(p.ins, p.ov, p.sc, :label_three, lens_point(l, 2, -3, -12); text = "three lenses,\ntwo kinds of glass",
             offset = (-30, -25))
    callout!(p.ins, p.ov, p.sc, :label_less, plot_tip(l, 2, 2); text = "towards picture edge (15°):\nmuch less lens smear",
             offset = (40, 30))
    caption!(p.ins, p.ov, :caption_enlarged; text = "Behind each sensor: where the light lands, enlarged")
    caption!(p.ins, p.ov, :caption_smear; text = "Lens smear: blur from the lens's own errors")
    return fans_part(p)
end

function keys_lenses(d::TelescopeData, tm::Timing)
    l, s, T = d.lenses, tm.starts, tm.duration
    t0 = Dict((1, 1) => s[1], (1, 2) => s[2], (2, 1) => s[4], (2, 2) => s[4])
    named = switch(s[3], 0f0, 1f0)
    keys = Dict{String, Any}("ray_$(i)_$(k)" => travelled_keys(t, T) for ((i, k), t) in t0)
    keys = Dict{String, Any}("args." * k => v for (k, v) in keys)
    merge!(keys, Dict(
        "args.second" => switch(s[4], false, true),
        "label_one.alpha" => appear(tm, 1), "label_centre.alpha" => plot_shown(l, 1, t0[(1, 1)]),
        "label_edge.alpha" => plot_shown(l, 1, t0[(1, 2)]) * (1f0 - named),
        "label_smear.alpha" => plot_shown(l, 1, t0[(1, 2)]) * named,
        "label_three.alpha" => appear(tm, 4), "label_less.alpha" => plot_shown(l, 2, t0[(2, 2)]),
        "caption_enlarged.alpha" => plot_shown(l, 1, t0[(1, 1)]) * (1f0 - appear(tm, 3)),
        "caption_smear.alpha" => appear(tm, 3) * (1f0 - appear(tm, 4))))
    return animation(keys)
end

beat_lenses() = Beat("c3_lenses", [
    "These rays show where the lens sends the light. For now, we [leave](+2) out the wave's own spreading, so we can see the lens's errors [separately](+2). Straight ahead, the rays land in a tight group at the picture's centre. Behind the sensor, we show that group enlarged.",
    "[Now](-1) the [same](+2) distant point of light, fifteen degrees to the [side](+2), towards the edge of the picture. The rays land in [different](+2) places: the lens smears the light out.",
    "From here on, we'll call this the lens smear: blur from the lens's own errors. Unlike the wave's spot, a [perfect](+2) lens would have [none](+2) of it.",
    "Three lenses, made of two kinds of glass, share the bending, and each one cancels the others' errors.",
    "From fifteen degrees to the side, their rays now meet almost in one point. The lens smear is much [smaller](+2), though [not](+2) quite gone.",
], build_lenses, keys_lenses)

function build_lens_colours(d::TelescopeData; size = (1280, 720))
    l = d.colours
    p = build_fans(l; pose = colour_pose(l), scale = 0.3f0, size)
    blue, green = 1, 2
    xs1, xs2 = l.lenses[1].sys.sensor, l.lenses[2].sys.sensor
    callout!(p.ins, p.ov, p.sc, :label_one, lens_point(l, 1, xs1 - 30, 12); text = "one lens", offset = (-30, 20))
    callout!(p.ins, p.ov, p.sc, :label_green, plot_tip(l, 1, green); text = "green: sharp", offset = (40, 40))
    callout!(p.ins, p.ov, p.sc, :label_blue, lens_point(l, 1, xs1 + PLOT_GAP + 6, l.centres[1, blue] - 6f0);
             text = "blue: smeared out,\na coloured fringe", offset = (40, -40))
    callout!(p.ins, p.ov, p.sc, :label_three, lens_point(l, 2, xs2 - 30, -12); text = "three lenses,\ntwo kinds of glass",
             offset = (-30, -20))
    callout!(p.ins, p.ov, p.sc, :label_sharp, plot_tip(l, 2, green); text = "all colours sharp", offset = (40, 30))
    caption!(p.ins, p.ov, :caption_enlarged; text = "Behind each sensor: where the light lands, enlarged")
    return fans_part(p)
end

function keys_lens_colours(d::TelescopeData, tm::Timing)
    l, s, T = d.colours, tm.starts, tm.duration
    keys = Dict{String, Any}("args.ray_$(i)_$(k)" => travelled_keys(i == 1 ? s[1] : s[3], T)
                             for i in 1:2 for k in eachindex(l.fans))
    merge!(keys, Dict(
        "args.second" => switch(s[3], false, true),
        "label_one.alpha" => appear(tm, 1), "label_green.alpha" => plot_shown(l, 1, s[1]),
        "label_blue.alpha" => appear(tm, 2), "label_three.alpha" => appear(tm, 3),
        "label_sharp.alpha" => plot_shown(l, 2, s[3]),
        "caption_enlarged.alpha" => plot_shown(l, 1, s[1]) * (1f0 - appear(tm, 3))))
    return animation(keys)
end

beat_lens_colours() = Beat("c4_colours", [
    "[There's](-1) one more problem: [colour](+2). [Here's](-1) light from straight ahead again, now in blue, green and red.",
    "Glass bends blue light a little [more](+2) than red, so a single lens can't focus all colours on the sensor at [once](+2). Green is sharp, but blue is smeared out, and red a little too: every edge gets a coloured fringe. That's lens smear too.",
    "The three lenses use two kinds of glass, whose colour errors cancel, so all the colours land [together](+2), sharp.",
    "Good lens design combines the right kinds of glass with carefully chosen shapes. Making those shapes [accurately](+2) matters [too](+2). It's how the lens reduces its own blur.",
], build_lens_colours, keys_lens_colours)

# ── C5: what is left of the smear, at the scale of the pixels ────────────────

"""
The zoom beat: the three lenses' light from 15° to the side, as in the lens
beat (a narrow needle at the scale of millimetres), zoomed in by `args.zoom`
(0..1) to the scale of the pixels, whose 4 µm stripes then fade in.
"""
function build_zoom(d::TelescopeData; size = (1280, 720))
    lo = d.leftover
    ins = Inspector()
    zoom = Observable(0f0)
    fig = Figure(; size, backgroundcolor = :black, figure_padding = (60, 60, SUBTITLES, 40), fontsize = 22)
    ax = Axis(fig[1, 1]; backgroundcolor = :black, xlabel = "position on the sensor (mm)", xlabelcolor = :gray80,
              xticklabelcolor = :gray70, yticksvisible = false, yticklabelsvisible = false, leftspinevisible = false,
              rightspinevisible = false, topspinevisible = false, bottomspinecolor = :gray60, xgridvisible = false,
              ygridvisible = false)
    half = lift(z -> exp(log(0.6f0) + z * (log(0.075f0) - log(0.6f0))), zoom)    # mm either side of the middle
    on(h -> limits!(ax, -h, h, 0, 1.25), half; update = true)
    hits, weights = along_sensor(lo.spot)
    curve = lift(half) do h
        u = range(-h, h; length = 600)
        p = light_profile(hits, weights, u; σ = 0.002f0)
        Point2f.(u, p ./ maximum(p))
    end
    edges = Float32[e for k in 0:40 for e in (0.002f0 + 0.004f0 * k, -0.002f0 - 0.004f0 * k)]
    object!(ins, "Pixel stripes", vlines!(ax, edges; color = :white, linewidth = 1, alpha = 0, name = :pixels))
    object!(ins, "Where the light lands",
            band!(ax, lift(pts -> [Point2f(p[1], 0) for p in pts], curve), curve; color = rgba(FIELD_COLORS[3], 0.35),
                  name = :area),
            lines!(ax, curve; color = rgbf(FIELD_COLORS[3]), linewidth = 3, name = :curve))
    ov = Scene(fig.scene; camera = campixel!, clear = false)
    caption!(ins, ov, :caption_lenses; text = "Three lenses, light from 15° to the side")
    caption!(ins, ov, :caption_pixel; text = "Each stripe: one pixel")
    return (scene = fig.scene, args = (; zoom), objects = ins.objects, controls = ins.controls)
end

keys_zoom(d::TelescopeData, tm::Timing) = animation(Dict(
    "args.zoom" => through(tm, 2; ease = :smooth),
    "pixels.alpha" => 0.2f0 * ramp(tm.ends[2] - 0.3f0, tm.ends[2] + 0.5f0),
    "caption_lenses.alpha" => appear(tm, 1) * (1f0 - appear(tm, 3)), "caption_pixel.alpha" => appear(tm, 3)))

beat_zoom() = Beat("c5_zoom", [
    "[But](-1) how small is much smaller? [Here's](-1) where that light lands, from fifteen degrees to the side, through the three lenses.",
    "Let's zoom in, until we can see the [pixels](+2).",
    "Each stripe is [one](+2) pixel, four thousandths of a millimetre. The leftover lens smear [still](+2) covers [many](+2) of them: the picture is blurry there.",
], build_zoom, keys_zoom)

# ── C6: which blur limits each ───────────────────────────────────────────────

"""The limits beat's tiles: (row, column) → the pixels of each picture, peak-normalized."""
function limits_tiles(lo::Leftover; npix = 41)
    smear, together = spot_pixel_tiles(lo; npix)
    point = zeros(Float32, npix, npix)
    point[(npix + 1) ÷ 2, (npix + 1) ÷ 2] = 1f0
    return ((star_on_pixels(10f0, 0f0; npix), point, star_on_pixels(10f0, 0f0; npix)),
            (star_on_pixels(lo.N, 0f0; npix), smear, together))
end

"""
The limits beat compares two examples, not a universal instrument distinction.
The camera's lens smear is the whole traced bundle (`bundle_spot`); its result
spreads every ray by the Airy spot, a geometric approximation to the aberrated
spot, not a full wave calculation. All tiles have the same pixel pitch but are
individually peak-normalized. They compare spreading on the sensor, not
angular resolution or brightness.
"""
function build_limits(d::TelescopeData; size = (1280, 720))
    lo = d.leftover
    ins = Inspector()
    fig = Figure(; size, backgroundcolor = :black, figure_padding = (20, 20, SUBTITLES - 40, 10))
    ax = Axis(fig[1, 1]; backgroundcolor = :black, aspect = DataAspect(), limits = (-2.4, 6.6, -0.1, 2.75))
    hidedecorations!(ax)
    hidespines!(ax)
    cols = (0.6f0, 2.2f0, 3.8f0)
    for (k, (x, h)) in enumerate(zip(cols, ("wave spot", "lens smear", "result")))
        words!(ins, ax, Symbol(:header, k), (x, 2.72), h; fontsize = 28, align = (:center, :top), color = RGBf(0.8, 0.8, 0.8))
    end
    rows = (("our telescope", "centre · f/10", "wave sets the limit\n→ wider opening"),
            ("camera example", "towards edge · 15° · f/$(round(Int, lo.N))", "lens adds more blur\n→ better design"))
    for (r, ((name, setting, verdict), tiles)) in enumerate(zip(rows, limits_tiles(lo)))
        y0 = r == 1 ? 1.3f0 : 0f0
        words!(ins, ax, Symbol(:name, r), (-0.25, y0 + 0.62f0), name; fontsize = 34, font = :bold, align = (:right, :bottom))
        words!(ins, ax, Symbol(:setting, r), (-0.25, y0 + 0.52f0), setting; fontsize = 19, align = (:right, :top),
               color = RGBf(0.7, 0.7, 0.7))
        for (k, (x, tile)) in enumerate(zip(cols, tiles))
            p = maximum(tile)
            picture = [RGBf((sqrt(v / p) .* SUNLIGHT)...) for v in tile]
            object!(ins, "Tile · $name · $k",
                    image!(ax, (x - 0.55f0, x + 0.55f0), (y0, y0 + 1.1f0), picture; interpolate = false, alpha = 0,
                           name = Symbol(:tile, r, :_, k)),
                    lines!(ax, Rect2f(x - 0.55f0, y0, 1.1, 1.1); color = :white, linewidth = 1, alpha = 0,
                           name = Symbol(:frame, r, :_, k)))
        end
        words!(ins, ax, Symbol(:arrow, r, :_1), (1.4, y0 + 0.55f0), "→"; fontsize = 40, align = (:center, :center))
        words!(ins, ax, Symbol(:arrow, r, :_2), (3.0, y0 + 0.55f0), "→"; fontsize = 40, align = (:center, :center))
        words!(ins, ax, Symbol(:verdict, r), (4.5, y0 + 0.55f0), verdict; fontsize = 32, align = (:left, :center))
    end
    ov = Scene(fig.scene; camera = campixel!, clear = false)
    caption!(ins, ov, :caption; text = "Same pixel size in every picture", fontsize = 22)
    return (scene = fig.scene, args = (;), objects = ins.objects, controls = ins.controls)
end

function keys_limits(d::TelescopeData, tm::Timing)
    keys = Dict{String, Any}("caption.alpha" => appear(tm, 1))
    for k in 1:3
        keys["header$k.alpha"] = appear(tm, 1; delay = 1.2f0 * (k - 1))
    end
    for (r, line, says, step) in ((1, 1, 3, 5f0), (2, 4, 5, 4f0))
        for n in ("name", "setting")
            keys["$n$r.alpha"] = appear(tm, line)
        end
        for k in 1:3
            shown = appear(tm, line; delay = step * (k - 1))
            keys["tile$(r)_$k.alpha"] = shown
            keys["frame$(r)_$k.alpha"] = 0.25f0 * shown
        end
        keys["arrow$(r)_1.alpha"] = appear(tm, line; delay = step)
        keys["arrow$(r)_2.alpha"] = appear(tm, line; delay = 2step)
        keys["verdict$r.alpha"] = appear(tm, says)
    end
    return animation(keys)
end

beat_limits() = Beat("c6_limits", [
    "[Here's](-1) how to read these pictures. First, the spot even a perfect lens would produce. Next, the lens smear. Finally, the result. We're separating two [causes](+2) of blur, [not](+2) taking three different photographs.",
    "In our telescope example, near the centre of its view, the well-made optics add very little blur. The result is [almost](+2) just the [wave's](+2) spot.",
    "That's diffraction limited: the optics are good enough that the [opening](+2) sets the limit on detail in the sky. A wider opening can separate closer stars.",
    "[Now](-1) our camera example, with the [same](+2) light from fifteen degrees to the side. The middle picture follows rays through the [whole](+2) round lens, not just our flat cut, so the smear is wide as well as long. It's much [bigger](+2) than the wave spot.",
    "In [this](-1) example, the lens adds [most](+2) of the blur. A better design can reduce it. Modern camera lenses correct these errors much better than this simple three-lens example.",
    "Both instruments face [both](+2) effects. These tiles compare spreading on the [sensor](+2), [not](+2) how much sky detail each instrument can see. The useful question is: [which](+2) source of blur is [larger](+2)?",
], build_limits, keys_limits)
