module ScienceFilmsVideoEditorExt

using ScienceFilms, VideoEditor, Makie
import ScienceFilms as SF
import VideoEditor as VE
using VideoEditor.Performance: buildperformed, framekeys, performedtracks

# ── building a part for the editor ───────────────────────────────────────────

"Whether `scene` draws inside a 3D view: what is traced."
inview(scene::Makie.Scene) = isview(Makie.cameracontrols(scene)) || (scene.parent !== nothing && inview(scene.parent))
isview(::Makie.Camera3D) = true
isview(_) = false

"""
    buildpart(film, canvas, args) -> (; scene, objects, native)

Part `args["part"]` of `film`, built at `canvas` the way the editor takes a
scene: its keyed arguments bound to the native plot properties that consume
them (`VideoEditor.Performance.buildperformed`; `native` holds their paths), so
a project keys only Makie properties. `args["layer"]` keeps one layer of a part
with a 3D view: `"picture"`, what its views draw, or `"labels"`, the text and
everything drawn over them, on a clear background, with the views' cameras so
labels still follow them. The inspector lists what is left.
"""
function SF.buildpart(film::SF.Film, canvas, args)
    part = film.parts[args["part"]]
    objects = NamedTuple[]
    built = buildperformed(canvas; layer = Symbol(get(args, "layer", "combined")), annotation = !inview) do size
        b = part.build(film.data(); size)
        append!(objects, b.objects)
        return b.scene, b.args
    end
    drawn(name) = SF.findplot(built.scene, Symbol(name)) !== nothing
    return (scene = built.scene, objects = filter(o -> all(drawn, o.plots), objects),
            native = (; built.paths, built.transforms, built.aliases))
end

"Whether part `name` has a 3D view: it is then traced, and its labels are a clip of their own."
function hasview(film::SF.Film, name, layout)
    scene = film.parts[name].build(film.data(); size = layout).scene
    view = SF.findcamera3d(scene) !== nothing
    Makie.free(scene)
    return view
end

"""
    nativetracks(anim, built, fps) -> Vector{(path, keys, discrete)}

The editor's property tracks for `anim` on a part built by `buildpart`: keys on
its arguments stored on the native properties that consume them, keys on its
plots and the camera as they are, on source frames. What the built layer does
not draw is not keyed, so frames that differ only in their labels are one
picture.
"""
function nativetracks(anim::SF.Animation, built, fps)
    authored(keys) = [(k.t, k.value, k.ease) for k in keys]
    keyed = [(path, keys) for (path, keys) in anim if !isempty(keys)]
    args = [String(chopprefix(path, "args.")) => authored(keys) for (path, keys) in keyed if startswith(path, "args.")]
    tracks = Any[performedtracks((picture = args, labels = []), built.native, fps; layer = :picture)...]
    for (path, keys) in keyed
        head = first(split(path, '.'))
        head == "camera" || (head != "args" && SF.findplot(built.scene, Symbol(head)) !== nothing) || continue
        push!(tracks, (path, framekeys(authored(keys), fps), discretevalue(first(keys).value)))
    end
    return tracks
end

"Counts and switches step from key to key; everything else is interpolated."
discretevalue(::Union{Bool,Integer}) = true
discretevalue(_) = false

# ── clips ────────────────────────────────────────────────────────────────────

"""
    sceneclip(film, name, layer, nsource; canvas, layout, fps, spp, max_depth) -> Clip

A clip of `layer` of part `name` (`:picture`, `:labels`, or `:flat` for a part
without a 3D view), its scene `nsource` frames long, without keys. The scene
recipe is the film package's `part`, loaded from the package in the environment
that opens or renders the project, laid out at `layout` and drawn at `canvas`
pixels. Previews rasterize; a bake traces a picture with `spp` samples and up
to `max_depth` bounces into linear HDR, denoised, graded and display-mapped by
the editor's effects.
"""
function sceneclip(film::SF.Film, name::AbstractString, layer::Symbol, nsource::Integer; canvas, layout, fps,
                   spp, max_depth)
    args = Dict{String, Any}("part" => name)
    layer === :flat || (args["layer"] = String(layer))
    build = VE.packagescene(film.mod, :part; args, markers = [Dict{String, Any}("frame" => 0, "label" => name)])
    clip = VE.sceneclip(VE.buildscene(build); build, frames = nsource, canvas = layout, framerate = fps,
                        backend = :RayMakie)
    render!(clip, Val(layer); spp, max_depth)
    resize!(clip.source, canvas)
    px_per_unit = canvas[1] / layout[1]
    clip.source.screenopts[:px_per_unit] = px_per_unit
    clip.source.bakescreenopts[:px_per_unit] = px_per_unit
    return clip
end

"How a layer's clip renders: the picture traced into the editor's HDR chain, labels and flat parts rasterized."
function render!(clip, ::Val{:picture}; spp, max_depth)
    VE.setrenderconfig!(clip; raytrace = true, samples = spp, max_depth, device = "Mantle.defaultbackend()")
    VE.addslot!(clip, VE.Effect(VE.OIDNDenoiseEffect()))
    VE.addslot!(clip, VE.Effect(VE.LinearGradeEffect(; exposure = log2(0.6))))
    VE.addslot!(clip, VE.Effect(VE.ToneMapEffect(; mode = 2, gamma = 2.2)))
    VE.addslot!(clip, VE.Effect(VE.ColorEffect()))
    return clip
end
function render!(clip, ::Val{:flat}; spp, max_depth)
    VE.setrenderconfig!(clip; device = "Mantle.defaultbackend()")
    VE.addslot!(clip, VE.Effect(VE.ColorEffect()))
    return clip
end
# Glyphs antialias with their own distance field; no second FXAA pass.
render!(clip, ::Val{:labels}; spp, max_depth) = VE.setrenderconfig!(clip; device = "Mantle.defaultbackend()", fxaa = false)

"A part's keys and how many frames its scene runs: a beat's placed by its narration, a shot's retimed to `speed`."
performance(part::SF.Beat, film, data; frames, speed, fps, timing) =
    (part.keys(data, something(timing, film.timing(part.name))), frames)
performance(part::SF.Shot, film, data; frames, speed, fps, timing) =
    (SF.retime(part.keys(data), speed), ceil(Int, part.seconds / speed * fps))

"""
    partclips(film, name; frames, src_in = 0, speed = 1, canvas, layout, fps, spp, max_depth, timing) -> Vector{Clip}

The clips of the beat or shot `name` of `film`, with their keys: a traced
part's picture on track 1 and its labels on track 2, keyed with what each
draws, so frames that differ only in their labels are one traced picture; a
flat part as one clip. A beat runs `frames` frames, its keys placed by
`timing`, by default the film's narration timing for `name`. A shot plays
`speed` times as fast as its keys say: its keys are retimed (see `retime`), so
every frame is its own moment of the shot; the clips show `frames` frames from
`src_in` of the retimed shot.
"""
function SF.partclips(film::SF.Film, name::AbstractString; frames::Integer, src_in::Integer = 0, speed::Real = 1,
                      canvas = (1920, 1080), layout = (1280, 720), fps = 30, spp = 256, max_depth = 24,
                      timing = nothing)
    anim, nsource = performance(film.parts[name], film, film.data(); frames, speed, fps, timing)
    layers = hasview(film, name, layout) ? (:picture, :labels) : (:flat,)
    return map(enumerate(layers)) do (track, layer)
        clip = sceneclip(film, name, layer, nsource; canvas, layout, fps, spp, max_depth)
        clip.track = track
        clip.src_in = src_in
        clip.src_out = min(nsource, src_in + frames)
        # built here as the editor builds it, for the native property each key is stored on
        built = SF.buildpart(film, layout, clip.source.build["args"])
        for (path, keys, discrete) in nativetracks(anim, built, fps)
            VE.keyframes!(clip, path, keys; discrete)
        end
        Makie.free(built.scene)
        clip
    end
end

"""
    montageclips(film, montage; options...) -> Vector{Vector{Clip}}

The clips of a montage, one group per shot (see [`ScienceFilms.partclips`](@ref),
which takes `options`): each shot retimed to the montage's speed (see
[`ScienceFilms.fit`](@ref)), from where the shot is taken, the last one cut
where the narration and its tail end.
"""
function montageclips(film::SF.Film, m::SF.Montage; fps, options...)
    samples, rate = readwav(film.voice(m.name))
    speed, seconds = SF.fit(m, length(samples) / rate)
    left = round(Int, seconds * fps)
    groups = Vector{VE.Clip}[]
    for (shot, a, b) in m.shots
        left > 0 || break
        src_in = round(Int, a / speed * fps)
        frames = min(left, round(Int, b / speed * fps) - src_in)
        push!(groups, SF.partclips(film, shot; frames, src_in, speed, fps, options...))
        left -= frames
    end
    # Slowed or sped up, the shots can run short of the narration by a frame or
    # two of rounding: the last one is held on.
    for clip in groups[end]
        left > 0 && (clip.src_out = min(clip.src_out + left, clip.source.nframes))
    end
    return groups
end

"""
    readwav(path) -> (samples, rate)

A 16-bit PCM WAV file's samples, mono (channels averaged), as `Float32` in
-1..1, and its sample rate.
"""
function readwav(path::AbstractString)
    bytes = read(path)
    String(bytes[1:4]) == "RIFF" && String(bytes[9:12]) == "WAVE" || error("not a WAV file: $path")
    pos = 13
    channels, rate, bits = 0, 0, 0
    while pos + 8 <= length(bytes)
        id = String(bytes[pos:pos+3])
        n = Int(reinterpret(UInt32, bytes[pos+4:pos+7])[1])
        body = pos + 8
        if id == "fmt "
            channels = Int(reinterpret(UInt16, bytes[body+2:body+3])[1])
            rate = Int(reinterpret(UInt32, bytes[body+4:body+7])[1])
            bits = Int(reinterpret(UInt16, bytes[body+14:body+15])[1])
        elseif id == "data"
            bits == 16 || error("only 16-bit PCM WAV files are read: $path has $bits bits")
            pcm = reinterpret(Int16, bytes[body:body+n-1])
            frames = reshape(Float32.(ltoh.(pcm)) ./ 32768f0, channels, :)
            return vec(sum(frames; dims = 1) ./ channels), rate
        end
        pos = body + n + isodd(n)
    end
    error("no audio data in $path")
end

"""
    narration(film, name, groups, at) -> VideoEditor.Narration

The approved narration of part `name` as a spoken take of the sequence: its
lines as the text, the recorded samples as the take (saved with the project,
so a render farm uses this performance and loads no speech model). A beat's
take follows its picture clip when the clip is moved; a montage's, which spans
several clips played at another speed, starts at `at` seconds into the sequence.
"""
function narration(film::SF.Film, name::AbstractString, groups, at)
    samples, rate = readwav(film.voice(name))
    part = film.parts[name]
    text = join(part.lines, " ")
    anchor, start = takeplace(part, groups, at)
    return VE.Narration(text, start, "af_heart", samples, rate, VE.SpeechSettings(), VE.VoiceMix(), String(name),
                        anchor)
end

"Where a take sits: on its beat's picture, or at `at` seconds into the sequence."
takeplace(::SF.Beat, groups, at) = (first(only(groups)).source, 0.0)
takeplace(::SF.Montage, groups, at) = (nothing, Float64(at))

"""
    filmsequence(film; fps = 30, options...) -> Sequence

The whole film as one VideoEditor sequence: every part of `film.cut` in order,
as clips with their keys (see [`ScienceFilms.partclips`](@ref), which takes
`options`), and its narration laid under them.
"""
function SF.filmsequence(film::SF.Film; canvas = (1920, 1080), fps = 30, options...)
    seq = VE.Sequence(VE.Clip[], fps)
    seq.canvas = Tuple(canvas)
    for name in film.cut
        part = film.parts[name]
        at = VE.seqlength(seq) / fps
        groups = partgroups(part, film; canvas, fps, options...)
        for clips in groups
            start = VE.seqlength(seq)
            foreach(clip -> (clip.start = start; VE.addclip!(seq, clip)), clips)
        end
        push!(seq.narration, narration(film, name, groups, at))
    end
    VE.bindinputs!(seq)
    return seq
end

"A narrated part's clips, one group per scene shown: a beat's own, a montage's shots."
partgroups(part::SF.Beat, film; fps, options...) =
    [SF.partclips(film, part.name; frames = ceil(Int, film.timing(part.name).duration * fps), fps, options...)]
partgroups(part::SF.Montage, film; options...) = montageclips(film, part; options...)

end
