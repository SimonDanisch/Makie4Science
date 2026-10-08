# The film's shots: animated pictures without narration of their own, cut into
# its montages (a stretch of narration shown with shots, see `Montage`). Each
# shot's keys are in its own seconds; a montage retimes them to its narration.

# ── a star, and every window holding the whole sky ───────────────────────────

"""How many crest bubbles the star shot can show at once (see `crest_shells`)."""
const MAX_SHELLS = 8

"""The star shot's two stars: the warm one at the origin, the soft blue one that joins it."""
const STARS = (Star(Point2f(0, 0), SUNLIGHT), Star(Point2f(0, 20), SECONDARY_LIGHT))

"""The stars shown when the second is faded to `second` (0: not there yet)."""
stars_at(second) = second > 0 ? [STARS[1], Star(STARS[2].pos, second .* STARS[2].tint)] : [STARS[1]]

"""A star's glowing core: emissive, in the star's colour whitened."""
star_material(tint) = Hikari.MediumInterface(Hikari.Emissive(Le = 6f0 .* (0.5f0 .+ 0.5f0 .* tint), two_sided = true))

function build_star(d::TelescopeData; size = (1280, 720))
    ins = Inspector()
    time, second = Observable(0f0), Observable(0f0)
    sc = Scene(; size, backgroundcolor = :black, lights = [AmbientLight(RGBf(0, 0, 0))])
    cam3d!(sc; center = false)
    look!(sc, Pose((5, -9, 5), (0, 0, 0); fov = 45))
    first = mesh!(sc, Sphere(Point3f(STARS[1].pos..., 0), 0.35f0); material = star_material(STARS[1].tint), name = :star)
    other = mesh!(sc, Sphere(Point3f(STARS[2].pos..., 0), 0.35f0); visible = false, name = :star2,
                  material = lift(s -> star_material(s .* STARS[2].tint), second))
    solid!(ins, "Star", first; materials = false)
    solid!(ins, "Second star", other; materials = false)
    # the crests near the first star as soap bubbles: as many as are out at the time
    shells = lift(t -> crest_shells(t), time)
    ball = normal_mesh(Tesselation(Sphere(Point3f(0), 1f0), 96))
    centre = Vec3f(STARS[1].pos..., 0)
    bubbles = map(1:MAX_SHELLS) do k
        p = mesh!(sc, ball; visible = lift(s -> k <= length(s), shells), name = Symbol(:bubble, k),
                  material = lift(s -> Hikari.ThinDielectric(; eta = k <= length(s) ? s[k][2] : 1f0), shells))
        on(s -> (k <= length(s) && (translate!(p, centre); scale!(p, Vec3f(s[k][1])))), shells; update = true)
        p
    end
    solid!(ins, "Crest bubbles", bubbles...; materials = false)
    # the crests in the plane, fading with the distance from the camera
    g = Grid(Point2f(-130, -50), Point2f(140, 130), 12 / 1.5f0)
    cam = cameracontrols(sc)
    light = lift(time, second, cam.eyeposition, cam.lookat) do t, s, eye, at
        fog = Fog(Pose(eye, at; fov = 45))
        wave_material(toimage(star_glow(stars_at(s), g, t; fog)); scale = 2f0)
    end
    solid!(ins, "Light in the plane", mesh!(sc, sheet(bounds(g), 0f0); material = light, name = :plane,
                                             inspectable = false); materials = false)
    return (scene = sc, args = (; time, second), objects = ins.objects, controls = ins.controls)
end

keys_star(d::TelescopeData) = animation(
    posekeys([0 => Pose((5, -9, 5), (0, 0, 0); fov = 45), 5 => Pose((5, -9, 5), (0, 0, 0); fov = 45),
              20 => Pose((0, -38, 30), (0, 2, 0); fov = 45), 30 => Pose((-6, -40, 30), (0, 6, 0); fov = 45),
              36 => Pose((-6, -44, 36), (0, 10, 0); fov = 45), 52 => Pose((86, -6, 9), (94, 10, 0); fov = 45)]),
    Dict("args.time" => ramp(0, 60, 0, 1.2f0 * 60), "args.second" => ramp(30, 32; ease = :smooth),
         "star2.visible" => switch(30, false, true)))

shot_star() = Shot("star", 60, build_star, keys_star)

# ── reading the direction: two windows onto two stars' wavefronts ───────────

"""Brushed gold: warm and soft, between bright aluminium (which flickered against the crests) and black (dead)."""
const GOLD = Hikari.Conductor(eta = (0.143f0, 0.374f0, 1.442f0), k = (3.983f0, 2.385f0, 1.603f0), roughness = 0.3)

"""
A window frame lying on the plane around `r` (world units): four bars `w`
wide and `h` high, one mesh named `name`.
"""
function window_frame!(sc, r::Rect2f; name, w = 0.45f0, h = 0.3f0, visible = true, material = GOLD)
    lo, hi = minimum(r), maximum(r)
    bars = (Rect3f(Vec3f(lo[1] - w, lo[2] - w, 0), Vec3f(hi[1] - lo[1] + 2w, w, h)),
            Rect3f(Vec3f(lo[1] - w, hi[2], 0), Vec3f(hi[1] - lo[1] + 2w, w, h)),
            Rect3f(Vec3f(lo[1] - w, lo[2], 0), Vec3f(w, hi[2] - lo[2], h)),
            Rect3f(Vec3f(hi[1], lo[2], 0), Vec3f(w, hi[2] - lo[2], h)))
    return mesh!(sc, merge([normal_mesh(b) for b in bars]); material, visible, name)
end

"""
The window shot's light at `time` (periods): two stars' crests, faint, and in
each window shown the one crest of each star nearest its middle, bright.
"""
struct WindowLight
    g::Grid
    δ::Float32
    λ::Float32
    narrow::Rect2f
    wide::Rect2f
end

function (l::WindowLight)(time, narrow, wide, faint)
    windows = Rect2f[w for (w, shown) in ((l.narrow, narrow), (l.wide, wide)) if shown]
    tex = window_glow(l.g, time, l.δ; λ = l.λ, windows, faint, width = 0.05f0, base = (0.012f0, 0.013f0, 0.02f0))
    return wave_material(toimage(tex); scale = 2f0)
end

"""The window shot's camera, straight down over its middle, north up, `height` above the plane."""
window_pose(height) = Pose(Vec3f(-1, 0.5, height), Vec3f(-1, 0.5, 0); fov = 40)

function build_window(d::TelescopeData; size = (1280, 720), λ = 1.2f0, beat = 12f0, light = 0.1f0)
    ins = Inspector()
    time, faint = Observable(0f0), Observable(0.45f0)
    narrow_on, wide_on = Observable(false), Observable(false)
    δ = asin(λ / beat)                    # one wavelength of slip across the wide window
    # larger than the frame, which looks straight down: no edge in view
    g = Grid(Point2f(-24, -14), Point2f(22, 24), 24 / λ)
    narrow = Rect2f(-9, -1.5f0, 3, 3)
    wide = Rect2f(0, -6, beat, beat)      # from half a wavelength slipped, through in step, to half the other way
    sc = Scene(; size, backgroundcolor = :black, lights = [AmbientLight(RGBf(0.02, 0.02, 0.02))])
    cam3d!(sc; center = false)
    # straight down, north up: looking down at a slant made the straight-ahead
    # crests converge in perspective, and the whole pattern seemed to lean
    pose = window_pose(26f0)
    update_cam!(sc, pose.eye, pose.lookat, Vec3f(0, 1, 0))
    cameracontrols(sc).fov[] = pose.fov
    update_cam!(sc, cameracontrols(sc))
    # out in space: no floor, only light for the frames, from high above the camera
    softbox!(sc, Point3f(-4, -7, 45), 24, 8; Le = light .* (160, 160, 160), name = :softbox_key)
    softbox!(sc, Point3f(8, 10, 40), 16, 6; Le = light .* (100, 100, 112), name = :softbox_fill)
    plane = mesh!(sc, sheet(bounds(g), 0.01f0); name = :plane, inspectable = false,
                  material = lift(WindowLight(g, δ, λ, narrow, wide), time, narrow_on, wide_on, faint))
    solid!(ins, "Light in the plane", plane; materials = false)
    solid!(ins, "Narrow window", window_frame!(sc, narrow; name = :frame_narrow, visible = narrow_on))
    solid!(ins, "Wide window", window_frame!(sc, wide; name = :frame_wide, visible = wide_on))
    return (scene = sc, args = (; time, faint, narrow = narrow_on, wide = wide_on), objects = ins.objects,
            controls = ins.controls)
end

keys_window(d::TelescopeData) = animation(
    posekeys([0 => window_pose(26f0), 40 => window_pose(24f0)]),
    Dict("args.time" => ramp(0, 40, 0, 1.2f0 * 40), "args.narrow" => switch(8, false, true),
         "args.wide" => switch(18, false, true), "args.faint" => ramp(8, 10, 0.45f0, 0.18f0; ease = :smooth)))

shot_window() = Shot("window", 40, build_window, keys_window)

# ── from a row of pixels to the picture: the rings ───────────────────────────

const AIRY_PIXELS = 31

function build_airy(d::TelescopeData; size = (1280, 720), N = 4f0, npix = AIRY_PIXELS)
    ins = Inspector()
    reveal, whole = Observable(0f0), Observable(false)
    img = sensor_image(N, npix)
    img ./= maximum(img)
    mid = (npix + 1) ÷ 2
    fig = Figure(; size, backgroundcolor = :black)
    ax = Axis(fig[1, 1]; DARK..., title = lift(w -> w ? "the whole sensor: a disk with rings" : "one row of pixels", whole))
    # the picture grows outwards from the middle row
    shown = lift(r -> glow_pixels([abs(j - mid) <= r ? img[i, j] : 0f0 for i in 1:npix, j in 1:npix]), reveal)
    object!(ins, "The pixels", image!(ax, 0.5 .. npix + 0.5, 0.5 .. npix + 0.5, shown; interpolate = false,
                                      name = :pixels); attributes = ("alpha", "visible"))
    edges = 0.5:1:npix+0.5
    object!(ins, "Pixel grid",
            linesegments!(ax, [Point2f(p, q) for x in edges for (p, q) in ((x, 0.5), (x, npix + 0.5))];
                          color = :white, alpha = 0.08, linewidth = 1, name = :grid_x),
            linesegments!(ax, [Point2f(q, p) for x in edges for (p, q) in ((x, 0.5), (x, npix + 0.5))];
                          color = :white, alpha = 0.08, linewidth = 1, name = :grid_y))
    object!(ins, "The row", lines!(ax, Rect2f(0.5, mid - 0.5, npix, 1); color = :white, linewidth = 2, name = :row))
    words!(ins, ax, :note, (npix + 0.5, 0.2), "brightened to show the rings"; fontsize = 18, align = (:right, :top))
    return (scene = fig.scene, args = (; reveal, whole), objects = ins.objects, controls = ins.controls)
end

keys_airy(d::TelescopeData) = animation(Dict(
    "args.reveal" => ramp(2, 6, 0, AIRY_PIXELS / 2; ease = :smooth), "args.whole" => switch(6, false, true),
    "row.alpha" => 1f0 - ramp(7, 9; ease = :smooth), "note.alpha" => switch(7, 0f0, 0.6f0)))

shot_airy() = Shot("airy", 10, build_airy, keys_airy)

# ── how detail is lost: a star cluster through a big and a small opening ────

const BLUR_PIXELS = 96

function build_blur(d::TelescopeData; size = (1280, 720), npix = BLUR_PIXELS, Nbig = 2f0, Nsmall = 8f0)
    ins = Inspector()
    count = Observable(0f0)
    stars = cluster(28, Float32(npix))
    order = sortperm([s[1] + 0.3f0 * s[2] for s in stars])   # left to right
    fig = Figure(; size, backgroundcolor = :black)
    shown = lift(n -> stars[order[1:clamp(round(Int, n), 0, length(stars))]], count)
    for (col, N, title, name) in ((1, Nbig, "large opening", :large), (2, Nsmall, "small opening", :small))
        spot = AiryProfile(N)
        ax = Axis(fig[1, col]; DARK..., title)
        img = lift(s -> glow_pixels(blurred(s, spot, npix) ./ 0.9f0; γ = 0.6f0), shown)
        object!(ins, "Picture · $title", image!(ax, 0 .. npix, 0 .. npix, img; interpolate = false, name);
                attributes = ("alpha", "visible"))
    end
    return (scene = fig.scene, args = (; count), objects = ins.objects, controls = ins.controls)
end

"""Each star added as its spot, one after the other, from 1 s to 9 s."""
keys_blur(d::TelescopeData) = animation(Dict("args.count" => ramp(1, 9, 0, 28)))

shot_blur() = Shot("blur", 14, build_blur, keys_blur)

# ── telescopes side by side: two stars ───────────────────────────────────────

"""
The light of an observation (one or more stars, each in its own colour) at
phase `φ`, within the telescope's outline, with its pixels' bars stacked by
star, each telescope scaled to its own brightest pixel (the spot's SHAPE is the
point, not how much light a bigger lens collects), grown out to `grow`.
"""
function observation_light(o::Observation, φ; grow = 1f0, tints = (SUNLIGHT, SECONDARY_LIGHT))
    tex = observation_glow(o, φ; tints)
    xf = o.tel.sys.sensor
    pix = [sensor_pixels(o.g, I, xf - 0.3f0) for I in o.I]
    vmax = maximum(sum(p[2] for p in pix))
    return readout_glow!(tex, o.g, xf, pix[1][1], [(vs ./ vmax, tint) for ((_, vs), tint) in zip(pix, tints)];
                         fill = grow)
end

"""The two-telescope shots' camera path over `seconds`."""
comparison_poses(seconds) = [0 => Pose((4, -14, 12), (6.5, 0, -0.5)), seconds => Pose((8.5, -9, 8), (11.5, 0, 0.2))]

function build_two_stars(d::TelescopeData; size = (1280, 720))
    ins = Inspector()
    phase, grow = Observable(0f0), Observable(0f0)
    fig, sc, _ = frame3d(last(first(comparison_poses(10))); size)
    for (k, (o, off, name)) in enumerate(zip(d.two_stars, PAIR_OFFSETS, (:small, :large)))
        telescope!(sc, o.tel, o.g, lift((φ, g) -> observation_light(o, φ; grow = g), phase, grow); name,
                   inspector = ins, offset = off, studio = k == 1)
    end
    return (scene = fig.scene, args = (; phase, grow), objects = ins.objects, controls = ins.controls)
end

keys_two_stars(d::TelescopeData) = animation(posekeys(comparison_poses(10)),
    Dict("args.phase" => ramp(0, 10, 0, 1.5f0 * 10), "args.grow" => ramp(1, 4; ease = :smooth)))

shot_two_stars() = Shot("two_stars", 10, build_two_stars, keys_two_stars)

# ── a telescope sorts directions ─────────────────────────────────────────────

function build_sorting(d::TelescopeData; size = (1280, 720))
    ins = Inspector()
    phase, rays = Observable(0f0), Observable(0f0)
    o = d.sorting
    tel, g = o.tel, o.g
    tints = (SUNLIGHT, SECONDARY_LIGHT)
    paths, fan = ray_fans(tel.sys, (0f0, STAR_SEPARATION); D = tel.D - 1f0, stop = -1.25f0, n = 9, x0 = -14f0)
    colours = [tints[f] for f in fan]
    fig, sc, _ = frame3d(Pose((-2, -12, 10), (6, 0, -0.5)); size)
    light = lift(phase, rays) do φ, r
        tex = observation_light(o, φ; tints)
        r > 0 && (tex .+= ray_glow(g, paths, colours; width = 0.12f0, gain = 1.5f0 * r))
        tex
    end
    telescope!(sc, tel, g, light; inspector = ins)
    return (scene = fig.scene, args = (; phase, rays), objects = ins.objects, controls = ins.controls)
end

keys_sorting(d::TelescopeData) = animation(
    posekeys([0 => Pose((-2, -12, 10), (6, 0, -0.5)), 6 => Pose((-2, -12, 10), (6, 0, -0.5)),
              12 => Pose((9.5, -5, 4.5), (12, 0, 0.3))]),
    Dict("args.phase" => ramp(0, 14, 0, 1.5f0 * 14), "args.rays" => ramp(3, 5; ease = :smooth)))

shot_sorting() = Shot("sorting", 14, build_sorting, keys_sorting)

# ── the montages: narration shown with shots ─────────────────────────────────

montage_rings() = Montage("b05_rings", [
    "With a real, round lens, those bumps become rings. Every star becomes a tiny disk with rings around it.",
    "[And](-1) [no](+2) lens, however perfect, does better. Why?",
], [("airy", 0, 10)]; tail = 0.8f0)

montage_star() = Montage("scene_02", [
    "Light starts at a star. A star sends light out in every direction at once: it spreads as a [sphere](+2), crest after crest, growing without end. Wherever you are, if you can see the star, you're standing inside that sphere. Its light is right there, reaching you.",
], [("star", 0, 30)])

montage_sky() = Montage("scene_03", [
    "Add a second star, and its spheres fill the same space. Every patch of space, however small, has light from [both](+2) stars going through it, from every star you can see from there. So every little window onto space holds the visible sky. [But](-1) letting the light in [isn't](+2) the same as telling its directions apart. A smaller opening makes nearby directions harder to distinguish.",
], [("star", 30, 60)])

montage_direction() = Montage("scene_04", [
    "Far from the stars, a small piece of each sphere is almost perfectly flat. The [direction](+2) to a star is written in the [tilt](+2) of these flat wavefronts. Two stars close together in the sky give two sets of wavefronts with almost the same tilt. Through a [narrow](+2) window you can hardly tell them apart: across the window, one wave slips behind the other by only a fraction of a wavelength. Through a [wide](+2) window the same small tilt adds up. At the far edge one wave has slipped by roughly a whole wavelength across the window. The wider the window, the finer the difference in direction it can tell apart. Remember that: [one](+2) wavelength across the window.",
], [("window", 0, 40)])

montage_detail() = Montage("scene_10", [
    "Point the telescope at two stars close together. Each star makes its own spot; here each has its own colour. With the [big](+2) lens the spots stay apart. With the [small](+2) one they merge into a single blob, and we can't tell there are two. That is all low resolution is: every point of the scene smeared into a little spot, and neighbouring spots running into each other. It's the rule from the window again: two stars come apart when, across the lens, their wavefronts drift one wavelength apart. The smallest angle a telescope can split is about the wavelength divided by the opening.",
    "Once the optics add very little blur, the opening sets this limit on detail in the sky. A longer focal length [enlarges](+2) the image, but [doesn't](+2) separate closer directions. That's why astronomers want big telescopes.",
], [("two_stars", 0, 10), ("blur", 0, 14)])

montage_simple() = Montage("scene_12", [
    "Let's draw rays too: arrows along the direction the wave travels. They're a convenient way to show where the optics send the light. Our telescope looks at a small patch of sky. Near the centre of that view, its two well-made pieces of glass add very little blur. The [wave's](+2) spot is larger than the lens's errors. That's called diffraction-limited. A wider opening can then separate closer stars. Real telescopes [also](+2) need accurate optics, and Earth's turbulent air can blur their images. [Here](-1) we're looking at the optics [without](+2) that atmospheric blur.",
], [("sorting", 0, 14)])

montage_outro() = Montage("scene_17", [
    "Both instruments face the [same](+2) two sources of blur: the wave's spreading and the lens's errors. [Our](-1) telescope's optics are good enough that the opening sets the limit. [Our](-1) camera example [still](+2) adds blur towards the picture's edges, so better design helps. Once those errors are small enough, diffraction is the limit for a camera [too](+2). [Which](+2) source of blur is [larger](+2)? That tells you what needs improving.",
], [("star", 0, 15)])
