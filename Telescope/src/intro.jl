# The cold open: a camera and a telescope as people know them, whole and at
# their true relative size (`Instruments`), each opening outlined as the
# narration names it.

"""Points around an opening (mm) in the world (world units, `INTRO_S` per mm): a ring to outline it."""
function opening_ring(o::WaveOptics.Opening; S = WaveOptics.INTRO_S, n = 97)
    R = WaveOptics.frame_to(o.axis)
    return [Point3f(S * (Vec3f(o.centre) + R * Vec3f(0, o.r * cos(t), o.r * sin(t)))) for t in range(0f0, 2f0 * Float32(π); length = n)]
end

function build_intro(d::TelescopeData; size = (1280, 720), S = WaveOptics.INTRO_S)
    k = d.instruments
    fig, sc, ov = frame3d(intro_poses(k, nothing)[1][2]; size)
    ins = Inspector()
    for (name, range) in k.groups
        plots = [mesh!(sc, place(m, S); material = mat, name = Symbol(replace(name, ' ' => '_'), :_, j))
                 for (j, (m, mat)) in enumerate(k.parts[range])]
        solid!(ins, uppercasefirst(name), plots...)
    end
    studio!(sc, -3f0; floor = 0f0, scale = 1.6f0, height = 8f0, inspector = ins)
    for (name, o) in ((:ring_camera, k.camera), (:ring_telescope, k.telescope))
        p = projectedlines!(ov, opening_ring(o; S); color = rgbf(PALETTE.gold), alpha = 0, name, viewof(sc)...)
        object!(ins, "Opening · " * (name === :ring_camera ? "camera" : "telescope"), p;
                attributes = ("color", "alpha", "linewidth", "visible"))
    end
    # What optical resolution is, while the camera rests on the lens.
    caption!(ins, ov, :caption_resolution; line = 1, text = "Optical resolution: the finest detail the lens itself can show")
    caption!(ins, ov, :caption_pixels; text = "(not the number of pixels)")
    callout!(ins, ov, sc, :label_lens, S * k.camera_lens; text = "camera lens", offset = (-40, 100), fontsize = 26)
    callout!(ins, ov, sc, :label_camera_opening, S * k.camera.centre - Vec3f(0, 0, S * k.camera.r);
             text = "opening: up to 25 mm", offset = (-70, -70), fontsize = 26)
    callout!(ins, ov, sc, :label_telescope, S * k.telescope_tube; text = "telescope", offset = (40, 120), fontsize = 26)
    callout!(ins, ov, sc, :label_telescope_opening, WaveOptics.rim_top(k.telescope); text = "opening: 100 mm",
             offset = (-60, 70), fontsize = 26)
    return (scene = fig.scene, args = (;), objects = ins.objects)
end

"""
The cold open's camera path: close on the camera lens while it is described,
back to show both as the telescope is named (`tm` the narration's timing; a
still for `nothing`).
"""
function intro_poses(k::Instruments, tm; S = WaveOptics.INTRO_S)
    lens = S * k.camera.centre
    both = Point3f(-4.4, -3.2, 13.1)
    close = Pose(lens + Vec3f(-2.6, -2.4, 0.9), lens + Vec3f(0.35, 0, -0.1); fov = 32)
    tm === nothing && return [0 => close]
    s, e = tm.starts, tm.ends
    # Close on the lens while optical resolution is defined and the lens described,
    # back to both as the telescope is named.
    return [0 => close,
            e[4] - 0.6f0 => Pose(lens + Vec3f(-2.2, -2.7, 1.0), lens + Vec3f(0.35, 0, -0.1); fov = 32),
            s[5] + 1.4f0 => Pose(both + Vec3f(-12.8, -20.4, 5), both; fov = 32),
            tm.duration => Pose(both + Vec3f(-10.2, -21.3, 4.2), both; fov = 32)]
end

function keys_intro(d::TelescopeData, tm::Timing)
    # the astronomer's answer lights the telescope's opening, the lens maker's the lens's
    dimmed(i) = 1f0 - 0.65f0 * (appear(tm, i) - appear(tm, i + 1))
    return animation(posekeys(intro_poses(d.instruments, tm)), Dict(
        "caption_resolution.alpha" => appear(tm, 2) * (1f0 - appear(tm, 4)),
        "caption_pixels.alpha" => appear(tm, 3) * (1f0 - appear(tm, 4)),
        "label_lens.alpha" => appear(tm, 4),
        "ring_camera.alpha" => appear(tm, 4; delay = 1.2f0) * dimmed(6),
        "label_camera_opening.alpha" => appear(tm, 4; delay = 1.2f0),
        "label_telescope.alpha" => appear(tm, 5; delay = 1.4f0),
        "ring_telescope.alpha" => appear(tm, 5; delay = 2f0) * dimmed(7),
        "label_telescope_opening.alpha" => appear(tm, 5; delay = 2f0)))
end

beat_intro() = Beat("a0_intro", [
    "Why are some pictures sharp, and others blurry?",
    "Every lens and every telescope has a limit: details finer than that, it can't show. That limit is called its [optical](+2) resolution.",
    "[Not](-1) the number of pixels: even a camera with endless pixels can't show what the lens itself has already blurred.",
    "This camera lens lets light in through an opening of at most 25 millimetres, and still takes sharp photos.",
    "This telescope's opening is [four](+2) times as wide: a hundred millimetres.",
    "Every astronomer knows: for a sharp telescope, what matters most is the [width](+2) of the opening.",
    "Camera makers, on the other hand, put their effort into the [glass](+2): the right materials, and cleverly designed shapes.",
    "[So](-1), how can both of these be true? To find out, let's follow the light from the very beginning.",
], build_intro, keys_intro)
