# "What makes a picture sharp?": a telescope explainer, as Makie scenes animated
# by sparse keys. Every part is built once by a function of the film's data;
# its motion is an `Animation`, keys on named plots, the camera and the scene's
# arguments, placed by the narration's line timing. VideoEditor turns each part
# into a clip whose keys are ordinary, editable keyframes.

"The approved narration: a WAV per narrated part and each beat's line timing."
narration_dir() = artifact"telescope-narration"

"When each line of beat `name` is spoken."
narration_timing(name::AbstractString) = Timing(joinpath(narration_dir(), name * ".timing"))

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
    view = viewof(sc)
    for (name, anchor, text, offset) in ((:label_lens, w3(1, 12), "lens (glass)", Vec2f(-80, 120)),
                                         (:label_tube, w3(60, 17), "tube, black inside", Vec2f(40, 120)),
                                         (:label_sensor, w3(a.xf, 6), "camera sensor", Vec2f(40, 80)),
                                         (:label_cut, w3(40, -8), "we draw the light on this cut", Vec2f(60, -90)))
        label!(ins, "Label · " * lowercase(partlabel(Symbol(chopprefix(String(name), "label_")))),
               callout!(ov, anchor; text, offset, alpha = 0, name, view...))
    end
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

# ── the film ─────────────────────────────────────────────────────────────────

"Every part of the film by name: its beats and its shots."
const TELESCOPE_PARTS = Dict{String, Union{Beat, Shot}}(p.name => p for p in (
    beat_telescope(),
))

"The film, as the editor assembles it (`partclip`)."
const FILM = Film(@__MODULE__, TELESCOPE_PARTS, telescope_data, narration_timing)

"""
    part(canvas, args) -> NamedTuple

The scene recipe a VideoEditor project names (`VideoEditor.packagescene`):
the part `args["part"]`, a beat or a shot, built at `canvas`.
"""
part(canvas, args) = buildpart(FILM, canvas, args)
