# Act 1, from the telescope to the f-number: what light is, the telescope, why
# glass bends light, the focus, why the focus is a spot, and what sets its size.
# Every beat is a scene built once; what moves is keyed (see each `keys_…`).

# ── B0: what the glowing lines mean ──────────────────────────────────────────

"""The light wave as a graph over `x`, `phase` periods on: a crest at x = 0.5 at phase 0."""
wave_curve(x, phase) = cos.(2f0 * Float32(π) .* (x .- 0.5f0 .- Float32(phase)))

"""The bottom strip: the same wave drawn as light, each crest a bright line, at brightness `shown`."""
function crest_strip(wave, shown)
    strip = map(wave) do v
        s = 1.3f0 * max(v, 0f0)^1.5f0
        hot = 0.6f0 * s^3
        RGBf((shown .* min.(1f0, SUNLIGHT .* s .+ (1 .- SUNLIGHT) .* hot))...)
    end
    return repeat(strip, 1, 40)
end

function build_wave(d::TelescopeData; size = (1280, 720))
    fig, ov = flat(; size, padding = (40, 40, 140, 30))
    ins = Inspector()
    phase, shown = Observable(0f0), Observable(0f0)
    x = range(0f0, 4.5f0; length = 900)
    wave = lift(φ -> wave_curve(x, φ), phase)
    top = Axis(fig[1, 1]; INSET..., title = "a graph of the light wave", titlesize = 26, bottomspinevisible = false,
               limits = (0, 4.5, -1.9, 2.4))
    object!(ins, "The wave", lines!(top, x, wave; color = rgbf(SUNLIGHT), linewidth = 4, name = :wave))
    words!(ins, top, :crest, (1.5, 1.15), "crest"; fontsize = 24, align = (:center, :bottom))
    words!(ins, top, :trough, (2.0, -1.15), "trough"; fontsize = 24, align = (:center, :top))
    bracket!(ins, top, :bracket, 2.5f0, 3.5f0, 1.9f0, "", (1f0, 1f0, 1f0))
    words!(ins, top, :wavelength, (3.0, 2.0), "1 wavelength"; fontsize = 24, align = (:center, :bottom))
    bot = Axis(fig[2, 1]; INSET..., title = "each bright line marks a crest", titlecolor = faded(:white, shown),
               titlesize = 26, bottomspinevisible = false, limits = (0, 4.5, 0, 1))
    object!(ins, "The wave as light", image!(bot, (0, 4.5), (0, 1), lift(crest_strip, wave, shown); name = :strip);
            attributes = ("alpha", "visible"))
    for (ax, name) in ((top, :marks_top), (bot, :marks_bottom))
        object!(ins, "Crest marks", vlines!(ax, 0.5:1:4.5; color = :white, linestyle = :dash, alpha = 0, name))
    end
    rowsize!(fig.layout, 2, Relative(0.3))
    caption!(ins, ov, :caption_moving; text = "The wave travels forward →", line = 1)
    caption!(ins, ov, :caption_scale; text = "Wavelength enlarged for visibility")
    return (scene = fig.scene, args = (; phase, shown), objects = ins.objects, controls = ins.controls)
end

function keys_wave(d::TelescopeData, tm::Timing)
    still = 1f0 - appear(tm, 5)
    s5 = tm.starts[5]
    return animation(Dict(
        "args.phase" => ramp(s5, tm.duration, 0, 0.6f0 * (tm.duration - s5)),
        "args.shown" => appear(tm, 4),
        "crest.alpha" => appear(tm, 2) * still, "trough.alpha" => appear(tm, 2) * still,
        "bracket.alpha" => appear(tm, 3) * still, "wavelength.alpha" => appear(tm, 3) * still,
        "marks_top.alpha" => 0.3f0 * (appear(tm, 4) * still), "marks_bottom.alpha" => 0.3f0 * (appear(tm, 4) * still),
        "caption_moving.alpha" => appear(tm, 5), "caption_scale.alpha" => appear(tm, 6)))
end

beat_wave() = Beat("b00_wave", [
    "Light is a [wave](+2).",
    "[This](-1) curve is a [graph](+2) of the wave, with crests and troughs. The light itself [isn't](+2) following a wiggly path.",
    "From one crest to the next is [one](+2) wavelength.",
    "In this video we look at light from above, and draw every crest as a bright line.",
    "[And](-1) the whole pattern moves [forward](+2), at the speed of light.",
    "Real light has about two thousand crests in a single millimetre. We draw them thousands of times [farther](+2) apart, so you can see them.",
], build_wave, keys_wave)

# ── B1: the telescope, cut open ──────────────────────────────────────────────

"""What a cut through an instrument shows besides its light: its lens and its outline, each faded in."""
struct CutLayers
    lens::Float32
    outline::Float32
end

"""
The cut's glow, as layers painted once: the dark base, and the lens and the
outline at full strength, in the image layout the sheet's texture takes
(`toimage`). Lighting a layer adds its colour times its fade, so a fade is a
weighted sum of the three rather than the cut painted again and turned into
an image; both happened every frame of a fade.
"""
struct CutTexture
    base::Matrix{Hikari.RGBSpectrum}
    lens::Matrix{Hikari.RGBSpectrum}
    outline::Matrix{Hikari.RGBSpectrum}
end

function CutTexture(a::Act)
    unlit() = fill(Hikari.RGBSpectrum(0f0, 0f0, 0f0, 1f0), size(a.g))
    return CutTexture(toimage(blank(a.g)), toimage(show_lens!(unlit(), a.section)),
                      toimage(light_up!(unlit(), a.outline, (0.15f0, 0.45f0, 0.22f0), 1f0)))
end

"The cut's glow with its lens and outline faded to `c`."
function (t::CutTexture)(c::CutLayers)
    return map(t.base, t.lens, t.outline) do b, l, o
        Hikari.RGBSpectrum(b.c[1] + c.lens * l.c[1] + c.outline * o.c[1],
                           b.c[2] + c.lens * l.c[2] + c.outline * o.c[2],
                           b.c[3] + c.lens * l.c[3] + c.outline * o.c[3], 1f0)
    end
end

function build_telescope(d::TelescopeData; size = (1280, 720))
    a = d.act
    fig, sc, ov = frame3d(Pose((-3, -13, 2.5), (6, 0, 0)); size)
    ins = Inspector()
    cut = Observable(CutLayers(0f0, 0f0))
    lid = Observable(0f0)
    tex = lift(CutTexture(a), cut)
    cutaway!(sc, telescope_meshes(a.tel), a.g, tex, a.tel.sys.sensor / 2; name = :telescope, inspector = ins,
             imagelayout = true)
    # the top half, lifted off along the cut and away; one object, its parts
    # taking the materials of the bottom half's
    shown = lift(l -> l < 13.9f0, lid)
    lidparts = [part.name => mesh!(sc, place(part.mesh, W); material = part.material,
                                   name = Symbol(:lid_, part.name), visible = shown)
                for part in telescope_meshes(a.tel; φ = (0, π))]
    for (_, p) in lidparts
        on(l -> translate!(p, Vec3f(0, 0.25f0 * l, l)), lid; update = true)
    end
    solid!(ins, "Telescope · lid", last.(lidparts)...; materials = false)
    alike!(ins, (Symbol(:telescope_, name) => p for (name, p) in lidparts)...)
    callout!(ins, ov, sc, :label_lens, w3(1, 12); text = "lens (glass)", offset = (-80, 120))
    callout!(ins, ov, sc, :label_tube, w3(60, 17); text = "tube, black inside", offset = (40, 120))
    callout!(ins, ov, sc, :label_sensor, w3(a.xf, 6); text = "camera sensor", offset = (40, 80))
    callout!(ins, ov, sc, :label_cut, w3(40, -8); text = "we draw the light on this cut", offset = (60, -90))
    return (scene = fig.scene, args = (; cut, lid), objects = ins.objects, controls = ins.controls)
end

function keys_telescope(d::TelescopeData, tm::Timing)
    t2 = tm.starts[2]
    return animation(
        posekeys([0 => Pose((-3, -13, 2.5), (6, 0, 0)), t2 => Pose((-4, -12, 5), (5, 0, -0.3)),
                  t2 + 4 => Pose((-6, -10, 7), (2, 0, -0.5))]),
        Dict("args.lid" => ramp(t2, t2 + 3.5f0, 0, 14; ease = :smooth),
             "args.cut.lens" => appear(tm, 3), "args.cut.outline" => appear(tm, 6),
             "label_lens.alpha" => appear(tm, 3), "label_tube.alpha" => appear(tm, 4),
             "label_sensor.alpha" => appear(tm, 5), "label_cut.alpha" => appear(tm, 6)))
end

beat_telescope() = Beat("b01_telescope", [
    "A telescope is such a window, with a machine behind it that sorts the light by [direction](+2): every direction gets its [own](+2) spot on the sensor.",
    "Let's cut one open.",
    "At the [front](+2) is the lens, made of glass.",
    "Behind it, a long tube, black inside, so that no stray light bounces around.",
    "At the [back](+2), the camera sensor: a grid of tiny light detectors, called [pixels](+2).",
    "On this flat cut through the middle, we'll draw the light: every crest a bright line, just as before.",
], build_telescope, keys_telescope)

# ── B2: why glass bends light ────────────────────────────────────────────────

"""How fast the refraction picture's crests run: periods per second."""
const REFRACTION_RATE = 1.2f0

"""A texel of a glow as a displayable colour, clipped at white."""
torgb(t::Hikari.RGBSpectrum) = RGBf(min(t.c[1], 1f0), min(t.c[2], 1f0), min(t.c[3], 1f0))

"""
The refraction picture's light: the simulated wave at `phase` (periods), the
glass tinted in by `glass`, and the crest number `crest` traced in white by
`trace`. Grid layout, as displayable colours.
"""
struct RefractionLight
    r::Refraction
    inside::Matrix{Float32}       # how far each cell is in the glass, 0..1
    optical::Matrix{Float32}      # the wave's phase at each cell, in wavelengths
end

function RefractionLight(r::Refraction)
    s, g = r.slab, r.g
    cells = [WaveOptics.cellcenter(g, i, j) for i in 1:size(g)[1], j in 1:size(g)[2]]
    return RefractionLight(r, [smoothstep(-s.ramp / 2, s.ramp / 2, WaveOptics.depth(s, p)) for p in cells],
                           [optical_phase(s, p) for p in cells])
end

function (l::RefractionLight)(phase, glass, trace, crest)
    r = l.r
    tex = hide_source!(glow(phase_field(r.A, phase), r.I; GLOW...), r.g, -14f0)
    return map(tex, l.inside, l.optical) do t, inside, opt
        a = 0.22f0 * glass * inside
        v = (t.c[1] + a * GLASS_TINT[1], t.c[2] + a * GLASS_TINT[2], t.c[3] + a * GLASS_TINT[3])
        if trace > 0
            w = 2f0 * trace * exp(-((opt + r.offset - phase - crest) / 0.07f0)^2)
            v = v .+ w
        end
        RGBf(min(v[1], 1f0), min(v[2], 1f0), min(v[3], 1f0))
    end
end

"""Where the traced crest is at `phase`: in the air, upright at x; where it meets the face, at y."""
function traced_crest(r::Refraction, phase, crest)
    s = r.slab
    xc = crest + phase - r.offset
    return xc, (xc - s.x0) / tan(s.θ)
end

function build_refraction(d::TelescopeData; size = (1280, 720))
    r = d.act.refraction
    s, g = r.slab, r.g
    ins = Inspector()
    phase, glass, trace, crest = Observable(0f0), Observable(0f0), Observable(0f0), Observable(0f0)
    fig = Figure(; size, backgroundcolor = :black, figure_padding = (0, 0, SUBTITLES, 0))
    ax = Axis(fig[1, 1]; backgroundcolor = :black, aspect = DataAspect(), limits = (-18, 40, -14, 14))
    hidedecorations!(ax)
    hidespines!(ax)
    xs_ = (g.origin[1], g.origin[1] + g.h * (g.dims[1] - 1))
    ys_ = (g.origin[2], g.origin[2] + g.h * (g.dims[2] - 1))
    object!(ins, "The light", image!(ax, xs_, ys_, lift(RefractionLight(r), phase, glass, trace, crest); name = :light);
            attributes = ("alpha", "visible"))
    tanθ = tan(s.θ)
    object!(ins, "Glass face", lines!(ax, [Point2f(s.x0 - 14 * tanθ, -14), Point2f(s.x0 + 14 * tanθ, 14)];
                                      color = rgbf(GLASS_TINT), linewidth = 2, alpha = 0, name = :face))
    dir = refracted(s)
    starts = Point2f[]
    arrows = Vec2f[]
    for y0 in (-7f0, 0f0, 7f0)
        q = Point2f(s.x0 + y0 * tanθ, y0)
        push!(starts, Point2f(-12, y0), q)
        push!(arrows, q - Point2f(-12, y0), 16f0 * dir)
    end
    object!(ins, "Rays", arrows2d!(ax, starts, arrows; color = :white, shaftwidth = 3, tipwidth = 14, tiplength = 14,
                                   alpha = 0, name = :rays))
    ov = Scene(fig.scene; camera = campixel!, clear = false)
    crestat = lift((φ, k) -> traced_crest(r, φ, k), phase, crest)
    # in the glass the crest runs across the new direction, from where it meets the face
    across = Vec2f(dir[2], -dir[1])
    entering = lift(crestat) do (xc, yface)
        p = Point2f(xc, yface) + 3f0 * across
        Point3f(p[1], clamp(p[2], -13f0, 13f0), 0)
    end
    still_in_air = lift(((xc, yface),) -> Point3f(xc, clamp(yface + 5f0, -13f0, 13f0), 0), crestat)
    callout!(ins, ov, ax.scene, :label_air, Point3f(-12, 8, 0); text = "air", offset = (0, 40))
    callout!(ins, ov, ax.scene, :label_glass, Point3f(32, 8, 0); text = "glass", offset = (0, 40))
    callout!(ins, ov, ax.scene, :label_slower, Point3f(30, -6, 0); text = "slower: crests closer together",
             offset = (-20, -60))
    callout!(ins, ov, ax.scene, :label_enters, entering; text = "this end enters first and slows down",
             offset = (40, -70))
    callout!(ins, ov, ax.scene, :label_air_end, still_in_air; text = "this end is still in the air, still fast",
             offset = (-40, 60))
    callout!(ins, ov, ax.scene, :label_direction, Point3f(s.x0 + 16f0 * dir[1], 16f0 * dir[2], 0);
             text = "new direction", offset = (40, -50))
    caption!(ins, ov, :caption; text = "Refraction: light bends because it slows down")
    return (scene = fig.scene, args = (; phase, glass, trace, crest), objects = ins.objects, controls = ins.controls)
end

function keys_refraction(d::TelescopeData, tm::Timing)
    r = d.act.refraction
    # one crest, followed from line 3 to line 5: the one whose part in the air is
    # 14 wavelengths before the face's middle when line 3 starts
    crest = round(r.slab.x0 - 14f0 + r.offset - REFRACTION_RATE * tm.starts[3])
    trace = appear(tm, 3) * (1f0 - appear(tm, 6))
    return animation(Dict(
        "args.phase" => ramp(0, tm.duration, 0, REFRACTION_RATE * tm.duration),
        "args.glass" => appear(tm, 2), "args.trace" => trace, "args.crest" => constant(Float32(crest)),
        "face.alpha" => 0.8f0 * appear(tm, 2), "rays.alpha" => appear(tm, 5),
        "label_air.alpha" => appear(tm, 2), "label_glass.alpha" => appear(tm, 2),
        "label_slower.alpha" => appear(tm, 2; delay = 1.5f0) * (1f0 - appear(tm, 3)),
        "label_enters.alpha" => appear(tm, 4) * trace, "label_air_end.alpha" => appear(tm, 4; delay = 1.5f0) * trace,
        "label_direction.alpha" => appear(tm, 5), "caption.alpha" => appear(tm, 6)))
end

beat_refraction() = Beat("b02_refraction", [
    "Lenses bend light. But why?",
    "In [glass](+2), light travels more [slowly](+2) than in air, so its crests bunch up closer together.",
    "Watch one crest as it reaches a slanted piece of glass.",
    "Its lower end enters the glass [first](+2) and slows down, while its upper end is [still](+2) racing ahead through the air.",
    "[So](-1) the crest swings around, and the light heads off in a [new](+2) direction.",
    "[That's](-1) refraction: light bends [because](+2) it slows down.",
], build_refraction, keys_refraction)

# ── B3: the lens focuses the starlight ───────────────────────────────────────

"""
The starlight arriving: the simulation, run to any time it is asked for (see
`SeekableWave`), and the pixels' light averaged as it arrives.
"""
struct ArrivalLight
    a::Act
    sim::SeekableWave
    peak::Float32          # the steady state's brightest pixel: a full bar
end

function ArrivalLight(a::Act)
    sim = SeekableWave(() -> telescope_wave(a.tel, a.g); sensor = a.xf - 0.3f0, τ = 1f0)
    return ArrivalLight(a, sim, a.tel.D^2 / (a.xf - a.tel.sys.elements[end].back.x))
end

"""
The glow at simulated `time` (periods): the wave and where its light is, the
lens's cross-section at `lens`, the bars of what the pixels have collected,
and rays (at `raysin` before the lens, `raysout` behind it) only where the
light has got to.
"""
function (l::ArrivalLight)(time, lens, raysin, raysout)
    a, g = l.a, l.a.g
    seek!(l.sim, time)
    E = energy(l.sim.wave)
    tex = hide_source!(glow(field(l.sim.wave), E; GLOW...), g, -14f0)
    show_lens!(tex, a.section; alpha = lens)
    cs, bars = sensor_pixels(g, collected(l.sim), a.xf - 0.3f0)
    readout_glow!(tex, g, a.xf, cs, [(min.(bars ./ l.peak, 1f0), SUNLIGHT)])
    front = time - 19f0
    white = (1.6f0, 1.6f0, 1.6f0)
    for y0 in (-10f0, 0f0, 10f0)
        stop = min(-2f0, front - 2f0)
        stop > -12f0 && ray_glow!(tex, g, Point2f(-13, y0), Point2f(stop, y0), white; gain = raysin)
    end
    reach = min(a.xf - 2f0, front - 6f0)
    if reach > a.xexit + 6f0
        for y0 in (-12f0, -6f0, 6f0, 12f0)
            p0 = Point2f(a.xexit + 1f0, y0)
            ray_glow!(tex, g, p0, p0 + (reach - p0[1]) / (a.xf - p0[1]) * (Point2f(a.xf, 0) - p0), white;
                      gain = raysout)
        end
    end
    return tex
end

function build_arrival(d::TelescopeData; size = (1280, 720))
    a = d.act
    fig, sc, ov = frame3d(Pose((-6, -10, 7), (2, 0, -0.5)); size)
    ins = Inspector()
    time, lens, raysin, raysout = Observable(3f0), Observable(0.4f0), Observable(0f0), Observable(0f0)
    telescope!(sc, a.tel, a.g, lift(ArrivalLight(a), time, lens, raysin, raysout); inspector = ins)
    callout!(ins, ov, sc, :label_flat, w3(-9, -10); text = "flat waves from the star", offset = (30, -60))
    callout!(ins, ov, sc, :label_glass, w3(2, 0); text = "glass, thickest in the middle", offset = (20, 200))
    callout!(ins, ov, sc, :label_behind, w3(a.xexit + 8, 0); text = "the middle falls behind", offset = (40, -110))
    callout!(ins, ov, sc, :label_curved, w3(55, 6); text = "now curved: heading inward", offset = (40, 110))
    callout!(ins, ov, sc, :label_focus, w3(a.xf, 0); text = "focus, on the sensor", offset = (30, -90))
    return (scene = fig.scene, args = (; time, lens, raysin, raysout), objects = ins.objects, controls = ins.controls)
end

function keys_arrival(d::TelescopeData, tm::Timing)
    s, T = tm.starts, tm.duration
    # the wave front at the lens on line 2, at the sensor on line 4
    clock = [Key(0f0, 3f0), Key(s[2], 21f0), Key(s[3], 70f0), Key(s[4], 150f0), Key(T, 150f0 + 8f0 * (T - s[4]))]
    return animation(
        posekeys([0 => Pose((-6, -10, 7), (2, 0, -0.5)), s[2] => Pose((-3, -11, 8), (3, 0, -0.5)),
                  s[3] => Pose((-2, -12, 10), (6, 0, -0.5)), s[4] => Pose((5, -9, 7), (10.5, 0, -0.5))]),
        Dict("args.time" => clock, "args.lens" => 0.4f0 + 0.6f0 * appear(tm, 2),
             "args.raysin" => appear(tm, 1; delay = 1f0), "args.raysout" => appear(tm, 3),
             "label_flat.alpha" => appear(tm, 1), "label_glass.alpha" => appear(tm, 2),
             "label_behind.alpha" => appear(tm, 2; delay = 2.5f0), "label_curved.alpha" => appear(tm, 3),
             "label_focus.alpha" => appear(tm, 4)))
end

beat_arrival() = Beat("b03_lens", [
    "[Back](-1) to our telescope. The star is so far away that its light arrives as flat waves, all heading straight in.",
    "The lens is thickest in the [middle](+2), so the middle of each wave spends the [longest](+2) time in slow glass, and falls behind the [most](+2).",
    "The wave comes out [curved](+2), and every part of it now heads [inward](+2), towards one point.",
    "That's how a lens bends light: onto the focus, on the sensor.",
], build_arrival, keys_arrival)

# ── B4: the spot ─────────────────────────────────────────────────────────────

"""The telescope's steady light at `phase`, its lens shown faintly, and the bars of its spot."""
function spot_glow(a::Act, phase)
    tex = steady_glow(a.A, a.I, a.g, phase)
    show_lens!(tex, a.section; alpha = 0.4f0)
    cs, v = readout(a.g, a.I, a.xf)
    return readout_glow!(tex, a.g, a.xf, cs, [(v, SUNLIGHT)])
end

function build_spot(d::TelescopeData; size = (1280, 720))
    a = d.act
    fig, sc, ov = frame3d(Pose((5, -9, 7), (10.5, 0, -0.5)); size)
    ins = Inspector()
    phase = Observable(0f0)
    telescope!(sc, a.tel, a.g, lift(φ -> spot_glow(a, φ), phase); inspector = ins)
    cs, v = readout(a.g, a.I, a.xf)
    tip(y) = bar_tip(a.xf, cs, v, y)
    callout!(ins, ov, sc, :label_bars, w3(a.xf + 4, -3.5); text = "each bar: the light one pixel collected",
             offset = (40, -90))
    callout!(ins, ov, sc, :label_centre, tip(0.5f0); text = "bright centre", offset = (60, 60))
    callout!(ins, ov, sc, :label_gap, tip(4.5f0); text = "dark gap", offset = (60, 40))
    callout!(ins, ov, sc, :label_bumps, tip(6.5f0); text = "faint bumps", offset = (60, 80))
    caption!(ins, ov, :caption; text = "Not a point: a small spot")
    return (scene = fig.scene, args = (; phase), objects = ins.objects, controls = ins.controls)
end

keys_spot(d::TelescopeData, tm::Timing) = animation(
    posekeys([0 => Pose((5, -9, 7), (10.5, 0, -0.5)), tm.ends[1] => Pose((10.6, -3.2, 6.2), (11.4, 0, 0); fov = 38)]),
    Dict("args.phase" => ramp(0, tm.duration, 0, 1.5f0 * tm.duration),
         "label_bars.alpha" => appear(tm, 1; delay = 1f0), "label_centre.alpha" => appear(tm, 3),
         "label_gap.alpha" => appear(tm, 3; delay = 1.2f0), "label_bumps.alpha" => appear(tm, 3; delay = 2.4f0),
         "caption.alpha" => appear(tm, 2)))

beat_spot() = Beat("b04_spot", [
    "Each bar behind the sensor shows how much light one pixel has collected.",
    "[And](-1) [here's](-1) the surprise: the light [doesn't](+2) end up in a single point.",
    "[There's](-1) a bright [centre](+2), a dark [gap](+2) beside it, and then faint bumps.",
], build_spot, keys_spot)

# ── B5: how waves add ────────────────────────────────────────────────────────

function build_adding(d::TelescopeData; size = (1280, 720))
    fig, ov = flat(; size)
    ins = Inspector()
    phase, shift = Observable(0f0), Observable(0f0)
    titles = (Observable(0f0), Observable(0f0))
    u = range(0f0, 3f0; length = 600)
    panels = ((Observable(0f0), "in step", "crest + crest → twice as high: bright"),
              (shift, "half a wavelength apart", "crest + trough → nothing: dark"))
    for (col, (δ, title, rule)) in enumerate(panels)
        ax = Axis(fig[1, col]; INSET..., title, titlecolor = faded(:white, titles[col]), titlesize = 28,
                  bottomspinevisible = false, limits = (-0.1, 3.6, -10.2, 1.6))
        a = lift(φ -> cos.(2f0 * Float32(π) .* (u .- φ)), phase)
        b = lift((φ, s) -> cos.(2f0 * Float32(π) .* (u .- φ .- s)), phase, δ)
        n(x) = Symbol(x, col)
        object!(ins, "Wave 1 · $title", lines!(ax, u, a; color = rgbf(ORANGE), linewidth = 3, alpha = 0, name = n(:wave_a)))
        object!(ins, "Wave 2 · $title", lines!(ax, u, lift(v -> v .- 3f0, b); color = rgbf(BLUE), linewidth = 3, alpha = 0,
                                               name = n(:wave_b)))
        base = hlines!(ax, [-6.5f0]; color = :white, linewidth = 1, xmax = 3.1f0 / 3.7f0, alpha = 0, name = n(:baseline))
        translate!(base, 0, 0, -1)
        object!(ins, "Sum · $title", lines!(ax, u, lift((x, y) -> x .+ y .- 6.5f0, a, b); color = :white, linewidth = 4,
                                            alpha = 0, name = n(:sum)), base)
        for (y, text, name) in ((0, "wave 1", :name_a), (-3, "wave 2", :name_b), (-6.5, "sum", :name_sum))
            words!(ins, ax, n(name), (3.08, y), text; fontsize = 20, align = (:left, :center))
        end
        words!(ins, ax, n(:rule), (1.5, -10.2), rule; fontsize = 24, align = (:center, :bottom))
    end
    caption!(ins, ov, :caption; text = "Where two waves meet, they add up")
    return (scene = fig.scene, args = (; phase, shift, title1 = titles[1], title2 = titles[2]), objects = ins.objects,
            controls = ins.controls)
end

function keys_adding(d::TelescopeData, tm::Timing)
    keys = Dict("args.phase" => ramp(0, tm.duration, 0, 0.4f0 * tm.duration),
                "args.shift" => ramp(tm.starts[3], tm.ends[3], 0, 0.5f0; ease = :smooth),
                "caption.alpha" => appear(tm, 1))
    for (col, waves, sums, says) in ((1, appear(tm, 1), appear(tm, 2), appear(tm, 2)),
                                     (2, appear(tm, 3), appear(tm, 3), appear(tm, 4)))
        for name in ("wave_a", "wave_b", "name_a", "name_b")
            keys["$name$col.alpha"] = waves
        end
        keys["args.title$col"] = waves
        keys["sum$col.alpha"] = sums
        keys["name_sum$col.alpha"] = sums
        keys["baseline$col.alpha"] = 0.25f0 * sums
        keys["rule$col.alpha"] = says
    end
    return animation(keys)
end

beat_adding() = Beat("b06_adding", [
    "To see why, we need one rule about waves: when two waves meet, they [add](+2) up.",
    "If they're [in](+2) step, crest on crest, the sum is [twice](+2) as high: bright.",
    "If one is half a wavelength behind, every crest meets a trough.",
    "They [cancel](+2) each other, and [nothing](+2) is left: dark.",
], build_adding, keys_adding)

# ── B9: the rule, as a diagram ───────────────────────────────────────────────

"""The rule's diagram: a lens `D` wide at x = 0, the sensor at `f`, and the drawn wavelength `λ`."""
const RULE = (D = 6f0, f = 10f0, λ = 0.6f0)

"""The height on the rule's sensor where the bottom edge of the lens is one drawn wavelength farther than the top."""
function rule_edge()
    D, f, λ = RULE
    dist(p, q) = norm(p - q)
    top, bottom = Point2f(0, D / 2), Point2f(0, -D / 2)
    lo, hi = 0f0, 3f0
    for _ in 1:40
        m = (lo + hi) / 2
        dist(bottom, Point2f(f, m)) - dist(top, Point2f(f, m)) < λ ? (lo = m) : (hi = m)
    end
    return lo
end

"""What the rule's diagram shows for the pixel at height `y`: the extra piece of the bottom path, and its arc."""
function rule_extra(y)
    D, f, λ = RULE
    top, bottom, pix = Point2f(0, D / 2), Point2f(0, -D / 2), Point2f(f, y)
    extra = norm(bottom - pix) - norm(top - pix)
    u = (pix - bottom) / norm(pix - bottom)
    r = norm(top - pix)
    dirs = [(top - pix) / r, (bottom + extra * u - pix) / r]
    a0, a1 = atan(dirs[2][2], dirs[2][1]), atan(dirs[1][2], dirs[1][1])
    a1 - a0 > π && (a1 -= 2f0 * Float32(π))   # the short way round, past the lens side
    arc = [pix + r * Point2f(cos(t), sin(t)) for t in range(a0, a1; length = 60)]
    return (; extra, piece = [bottom, bottom + extra * u], arc, at = bottom + extra * u / 2 + Point2f(0.25, -0.25),
            text = "$(fraction(extra / λ)) wavelength farther")
end

function build_rule(d::TelescopeData; size = (1280, 720))
    D, f, λ = RULE
    ins = Inspector()
    y = Observable(0f0)
    fig = Figure(; size, backgroundcolor = :black, figure_padding = (60, 60, SUBTITLES, 40))
    ax = Axis(fig[1, 1]; backgroundcolor = :black, aspect = DataAspect(), limits = (-2.5, 13.5, -4.2, 4.2))
    hidedecorations!(ax)
    hidespines!(ax)
    top, bottom = Point2f(0, D / 2), Point2f(0, -D / 2)
    pix = lift(h -> Point2f(f, h), y)
    object!(ins, "Lens", poly!(ax, Rect2f(-0.15, -D / 2, 0.3, D); color = rgba(GLASS_TINT, 0.6), name = :lens))
    object!(ins, "Sensor", lines!(ax, [Point2f(f, -3.5), Point2f(f, 3.5)]; color = :gray60, linewidth = 3, name = :sensor))
    words!(ins, ax, :lens_text, (0, D / 2 + 0.35), "lens"; alpha = 1, fontsize = 24, align = (:center, :bottom))
    words!(ins, ax, :sensor_text, (f, 3.6), "sensor"; alpha = 1, fontsize = 24, align = (:center, :bottom))
    object!(ins, "Path from the top edge", lines!(ax, lift(p -> [top, p], pix); color = rgbf(ORANGE), linewidth = 3,
                                                  name = :path_top))
    object!(ins, "Path from the bottom edge", lines!(ax, lift(p -> [bottom, p], pix); color = rgbf(BLUE), linewidth = 3,
                                                     name = :path_bottom))
    object!(ins, "Centre pixel", scatter!(ax, [Point2f(f, 0)]; color = :gray70, markersize = 10, name = :centre_dot))
    object!(ins, "The pixel", scatter!(ax, lift(p -> [p], pix); color = :white, markersize = 14, name = :pixel))
    words!(ins, ax, :centre_text, (f + 0.3, 0), "centre"; alpha = 1, color = :gray70, fontsize = 20,
           align = (:left, :center))
    # the extra piece of the bottom path: what is left after the top path's length, measured from the pixel
    extra = lift(rule_extra, y)
    shows = lift(e -> e.extra > 0.01f0, extra)
    object!(ins, "Extra distance", lines!(ax, lift(e -> e.piece, extra); color = :white, linewidth = 7, alpha = 0,
                                          visible = shows, name = :extra),
            lines!(ax, lift(e -> e.arc, extra); color = :white, linestyle = :dash, alpha = 0, visible = shows, name = :arc))
    extratext = text!(ax, lift(e -> e.at, extra); text = lift(e -> e.text, extra), color = :white, alpha = 0,
                      fontsize = 22, align = (:left, :top), visible = shows, name = :extra_text)
    label!(ins, "Text · extra distance", extratext)
    words!(ins, ax, :edge_text, lift(p -> p + Point2f(0.3, 0), pix), "edge of the spot"; fontsize = 24,
           align = (:left, :center))
    object!(ins, "Width", lines!(ax, [Point2f(-1, -D / 2), Point2f(-1, D / 2)]; color = rgbf(GLASS_TINT), linewidth = 2,
                                 alpha = 0, name = :width))
    words!(ins, ax, :width_text, (-1.2, 0), "width"; color = rgbf(GLASS_TINT), fontsize = 24, rotation = π / 2,
           align = (:center, :bottom))
    ov = Scene(fig.scene; camera = campixel!, clear = false)
    caption!(ins, ov, :caption_edge; line = 1,
             text = "Edge of the spot: one edge of the lens is 1 wavelength farther than the other")
    caption!(ins, ov, :caption_named; line = 1, text = "Diffraction: even perfect optics produce a spot")
    caption!(ins, ov, :caption_width; text = "At the same focal distance: wider opening → smaller spot")
    return (scene = fig.scene, args = (; y), objects = ins.objects, controls = ins.controls)
end

function keys_rule(d::TelescopeData, tm::Timing)
    shown = appear(tm, 2; delay = 1f0)
    # the last line names the effect, in place of the first caption
    named = switch(tm.starts[5], 1f0, 0f0)
    return animation(Dict(
        "args.y" => ramp(tm.starts[2], tm.ends[2], 0, rule_edge(); ease = :smooth),
        "centre_text.alpha" => 1f0 - appear(tm, 2),
        "extra.alpha" => shown, "arc.alpha" => 0.35f0 * shown, "extra_text.alpha" => shown,
        "edge_text.alpha" => appear(tm, 3), "width.alpha" => appear(tm, 4), "width_text.alpha" => appear(tm, 4),
        "caption_edge.alpha" => appear(tm, 3) * named, "caption_named.alpha" => appear(tm, 5),
        "caption_width.alpha" => appear(tm, 4)))
end

beat_rule() = Beat("b10_rule", [
    "[So](-1) [here's](-1) the rule.",
    "Step away from the centre, until one edge of the lens is a whole wavelength farther away than the other.",
    "There, it goes dark: that's the edge of the spot.",
    "Keep the sensor at the [same](+2) distance, and two things set this spot's size: the [width](+2) of the opening, and the [wavelength](+2) of the light.",
    "This spreading is called diffraction. Even perfect glass [can't](+2) remove it. The opening admits only part of the wave, and those parts add up to a [spot](+2), rather than a [point](+2).",
], build_rule, keys_rule)

# ── B10: the width of the lens ───────────────────────────────────────────────

function build_opening(d::TelescopeData; size = (1280, 720))
    a = d.act
    fig, sc, ov = frame3d(Pose((5, -17, 13), (7, 0, -0.8); fov = 40); size)
    ins = Inspector()
    phase, paths, highlight = Observable(0f0), Observable(0f0), Observable(false)
    y = dark_height(a)
    setups = [Setup(o.tel, o.g, o.A[1], o.I[1], SUNLIGHT) for o in a.obs]
    textures = [lift((φ, p, h) -> pair_glow(s, φ; y, paths = p, highlight = h), phase, paths, highlight)
                for s in setups]
    pair!(sc, ins, setups, textures; names = (:narrow, :wide))
    xe(o) = o.tel.sys.elements[end].back.x + 0.3f0
    narrow, wide = a.obs
    up, down = PAIR_OFFSETS[1][2], PAIR_OFFSETS[2][2]
    callout!(ins, ov, sc, :label_narrow, Point3f(0, up + W * 7.5f0, 0); text = "narrow lens", offset = (20, 90))
    callout!(ins, ov, sc, :label_wide, Point3f(0, down - W * 15f0, 0); text = "lens twice as wide", offset = (20, -70))
    callout!(ins, ov, sc, :label_pixel, Point3f(W * narrow.tel.sys.sensor, up + W * y, 0);
             text = "the same pixel, 4 wavelengths up", offset = (40, 70))
    callout!(ins, ov, sc, :label_narrow_edge, Point3f(W * xe(narrow), up - W * 7.5f0, 0);
             text = "far edge: ½ wavelength farther → still bright", offset = (40, -40))
    callout!(ins, ov, sc, :label_wide_edge, Point3f(W * xe(wide), down - W * 15f0, 0);
             text = "far edge: 1 wavelength farther → dark", offset = (40, -40))
    caption!(ins, ov, :caption; text = "Twice the opening → half the spot")
    return (scene = fig.scene, args = (; phase, paths, highlight), objects = ins.objects, controls = ins.controls)
end

keys_opening(d::TelescopeData, tm::Timing) = animation(Dict(
    "args.phase" => ramp(0, tm.duration, 0, 1.5f0 * tm.duration), "args.paths" => appear(tm, 2),
    "args.highlight" => switch(tm.starts[2], false, true),
    "label_narrow.alpha" => appear(tm, 1), "label_wide.alpha" => appear(tm, 1; delay = 1.5f0),
    "label_pixel.alpha" => appear(tm, 2), "label_narrow_edge.alpha" => appear(tm, 3),
    "label_wide_edge.alpha" => appear(tm, 4), "caption.alpha" => appear(tm, 5)))

beat_opening() = Beat("b11_opening", [
    "First, the width. [Here](-1) are two telescopes, one with a lens twice as wide as the other.",
    "Look at the [same](+2) pixel on both, four wavelengths from the centre.",
    "In the narrow one, the far edge is [only](+2) half a wavelength farther away. The waves still mostly agree, so it's bright.",
    "In the wide one, the edges are twice as far apart, so it's already a whole wavelength: dark.",
    "[Twice](+2) the opening: [half](+2) the spot.",
], build_opening, keys_opening)

# ── B11: the length of the waves ─────────────────────────────────────────────

function build_colours(d::TelescopeData; size = (1280, 720))
    a = d.act
    fig, sc, ov = frame3d(Pose((-1, -14, 11), (4, 0, -0.8); fov = 40); size)
    ins = Inspector()
    # the same time for both: the crests move at the same speed, the longer
    # waves' phase advances more slowly
    phase = Observable(0f0)
    (Ab, Ib), (Ar, Ir) = a.colours
    setups = [Setup(a.tel, a.g, Ab, Ib, BLUE_TINT), Setup(a.tel, a.g, Ar, Ir, RED_TINT)]
    textures = [lift(τ -> pair_glow(s, τ / λ), phase) for (s, λ) in zip(setups, (BLUE_LIGHT, RED_LIGHT))]
    pair!(sc, ins, setups, textures; names = (:blue, :red))
    tip(off) = Point3f(W * (a.xf + 1.5f0 + 17f0), off[2], 0)
    up, down = PAIR_OFFSETS
    callout!(ins, ov, sc, :label_blue, Point3f(W * -8, up[2] + W * 8, 0); text = "blue light: short waves",
             offset = (-20, 90))
    callout!(ins, ov, sc, :label_red, Point3f(W * -8, down[2] - W * 8, 0); text = "red light: longer waves",
             offset = (-20, -70))
    callout!(ins, ov, sc, :label_small, tip(up); text = "small spot", offset = (30, 60))
    callout!(ins, ov, sc, :label_bigger, tip(down); text = "bigger spot", offset = (30, -60))
    caption!(ins, ov, :caption_length; line = 1, text = "No wavelength, no blur: the wavelength sets the size of the spot")
    caption!(ins, ov, :caption_radio; text = "Radio waves are ~400 000× longer than light: radio telescopes are giant dishes")
    return (scene = fig.scene, args = (; phase), objects = ins.objects, controls = ins.controls)
end

function keys_colours(d::TelescopeData, tm::Timing)
    s3 = tm.starts[3]
    return animation(
        posekeys([0 => Pose((-1, -14, 11), (4, 0, -0.8)), s3 => Pose((-1, -14, 11), (4, 0, -0.8)),
                  s3 + 3 => Pose((9.5, -8, 7), (12, 0, -0.3))]),
        Dict("args.phase" => ramp(0, tm.duration, 0, 1.5f0 * tm.duration),
             "label_blue.alpha" => appear(tm, 1), "label_red.alpha" => appear(tm, 1; delay = 1.5f0),
             "label_small.alpha" => appear(tm, 4), "label_bigger.alpha" => appear(tm, 4; delay = 1f0),
             "caption_length.alpha" => appear(tm, 5), "caption_radio.alpha" => appear(tm, 6)))
end

beat_colours() = Beat("b12_colours", [
    "Second, the length of the waves. Blue light has [short](+2) waves, red light has [longer](+2) ones.",
    "[Here's](-1) the [same](+2) telescope twice: once with blue light, and once with red.",
    "With longer waves, you have to step farther from the centre before one edge is a whole wavelength behind.",
    "[So](-1) red light makes a [bigger](+2) spot than blue light.",
    "If light's waves had no length at all, the spot would be a perfect point. [It's](-1) the [wavelength](+2) that sets the size of the blur.",
    "Radio waves are hundreds of thousands of times longer than light, and that's why radio telescopes are giant dishes.",
], build_colours, keys_colours)

# ── B12: the f-number ────────────────────────────────────────────────────────

function build_formula(d::TelescopeData; size = (1280, 720))
    fig, ov = flat(; size)
    ins = Inspector()
    w, h = size
    lens, sensor = Point2f(340, 590), Point2f(940, 590)
    object!(ins, "Lens", lines!(ov, [lens - Vec2f(0, 30), lens + Vec2f(0, 30)]; color = rgbf(GLASS_TINT), linewidth = 8,
                                alpha = 0, name = :lens))
    object!(ins, "Focus", lines!(ov, [sensor - Vec2f(0, 30), sensor + Vec2f(0, 30)]; color = :gray80, linewidth = 3,
                                 alpha = 0, name = :focus))
    object!(ins, "Focal length", lines!(ov, [lens, sensor]; color = :white, linewidth = 2, alpha = 0, name = :length))
    words!(ins, ov, :lens_text, lens + Vec2f(-30, 0), "lens"; fontsize = 24, align = (:right, :center))
    words!(ins, ov, :focus_text, sensor + Vec2f(30, 0), "focus"; fontsize = 24, align = (:left, :center))
    words!(ins, ov, :length_text, (640, 625), "focal length"; fontsize = 28, align = (:center, :bottom))
    words!(ins, ov, :spot, (w / 2, h * 0.62), "spot size ≈ wavelength × focal length ÷ lens width"; fontsize = 36,
           align = (:center, :center))
    words!(ins, ov, :fnumber, (w / 2, h * 0.47), "focal length ÷ lens width  =  the f-number"; fontsize = 32,
           align = (:center, :center))
    words!(ins, ov, :result, (w / 2, h * 0.32), "spot size ≈ wavelength × f-number"; fontsize = 40,
           color = rgbf(SUNLIGHT), align = (:center, :center))
    return (scene = fig.scene, args = (;), objects = ins.objects, controls = ins.controls)
end

function keys_formula(d::TelescopeData, tm::Timing)
    keys = Dict{String, Any}(n * ".alpha" => appear(tm, 1)
                             for n in ("lens", "focus", "length", "lens_text", "focus_text", "length_text"))
    keys["spot.alpha"] = appear(tm, 2)
    keys["fnumber.alpha"] = 0.85f0 * appear(tm, 3)
    keys["result.alpha"] = appear(tm, 3; delay = 2f0)
    return animation(keys)
end

beat_formula() = Beat("b13_formula", [
    "There's one more distance to name: from the lens to the focus. For light from a distant star, that's the focal length. A longer focal length makes a [larger](+2) image, [including](+2) a larger spot on the sensor.",
    "Put together: the spot's size on the sensor is roughly the wavelength, [times](+2) the focal length, [divided](+2) by the width of the opening.",
    "Photographers call the focal length divided by the width the f-number.",
], build_formula, keys_formula)
