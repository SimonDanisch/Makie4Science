module ScienceFilmsVideoEditorExt

using ScienceFilms, VideoEditor
import ScienceFilms as SF
import VideoEditor as VE

"""
    animate!(clip, animation; fps = clip.source.framerate) -> clip

Write an `Animation` as the clip's keyframes: each path's keys become an
ordinary, editable keyframe curve on the clip's scene effect. Key times are
seconds into the scene, placed on the nearest source frame; two keys landing
on one frame keep the later one.
"""
function SF.animate!(clip::VE.Clip, anim::SF.Animation; fps = clip.source.framerate)
    for (path, keys) in anim
        isempty(keys) && continue
        byframe = Dict{Int, Tuple{Int, Any, Symbol}}()
        for k in keys
            f = round(Int, k.t * fps)
            byframe[f] = (f, k.value, k.ease)
        end
        entries = sort!(collect(values(byframe)); by = first)
        discrete = first(keys).value isa Union{Bool, Integer}
        VE.keyframes!(clip, path, entries; discrete)
    end
    return clip
end

"""
    sceneclip(film, name, nsource; canvas, fps, spp) -> Clip

A clip of part `name` of `film`, its scene `nsource` frames long, without keys.
The scene recipe is the film package's `part`, loaded from the package in the
environment that opens or renders the project. Previews use RayMakie's raster
mode; finished frames are path traced with `spp` samples.
"""
function sceneclip(film::SF.Film, name::AbstractString, nsource::Integer; canvas, fps, spp)
    build = VE.packagescene(film.mod, :part; args = Dict{String, Any}("part" => name),
                            markers = [Dict{String, Any}("frame" => 0, "label" => name)])
    clip = VE.sceneclip(VE.buildscene(build); build, frames = nsource, canvas, framerate = fps, backend = :RayMakie)
    src = clip.source
    src.screenopts = Dict{Symbol, Any}(:device => "Mantle.defaultbackend()", :rasterize => true, :samples => 1,
                                       :exposure => 0.6f0, :tonemap => :aces, :gamma => 2.2f0,
                                       :max_component_value => 10f0)
    src.bakewith = :RayMakie
    src.bakescreenopts = Dict{Symbol, Any}(:rasterize => false, :samples => spp, :max_depth => 12, :denoise => false)
    return clip
end

"""
    partclip(film, name; frames, src_in = 0, speed = 1, canvas, fps, spp, timing) -> Clip

A clip of the beat or shot `name` of `film`, with its keys. A beat runs
`frames` frames, its keys placed by `timing`, by default the film's narration
timing for `name`. A shot plays `speed` times as fast as its keys say: its keys
are retimed (see `retime`), so every frame is its own moment of the shot; the
clip shows `frames` frames from `src_in` of the retimed shot.
"""
function SF.partclip(film::SF.Film, name::AbstractString; frames::Integer, src_in::Integer = 0, speed::Real = 1,
                     canvas = (1280, 720), fps = 30, spp = 64, timing = nothing)
    part = film.parts[name]
    data = film.data()
    if part isa SF.Beat
        clip = sceneclip(film, name, frames; canvas, fps, spp)
        SF.animate!(clip, part.keys(data, something(timing, film.timing(name))); fps)
        return clip
    end
    nsource = ceil(Int, part.seconds / speed * fps)
    clip = sceneclip(film, name, nsource; canvas, fps, spp)
    clip.src_in = src_in
    clip.src_out = min(nsource, src_in + frames)
    SF.animate!(clip, SF.retime(part.keys(data), speed); fps)
    return clip
end

"""
    montageclips(film, montage; canvas, fps, spp) -> Vector{Clip}

The clips of a montage: each of its shots retimed to the montage's speed (see
[`ScienceFilms.fit`](@ref)), from where the shot is taken, the last one cut
where the narration and its tail end.
"""
function montageclips(film::SF.Film, m::SF.Montage; canvas, fps, spp)
    samples, rate = readwav(film.voice(m.name))
    speed, seconds = SF.fit(m, length(samples) / rate)
    left = round(Int, seconds * fps)
    clips = VE.Clip[]
    for (shot, a, b) in m.shots
        left > 0 || break
        src_in = round(Int, a / speed * fps)
        frames = min(left, round(Int, b / speed * fps) - src_in)
        push!(clips, SF.partclip(film, shot; frames, src_in, speed, canvas, fps, spp))
        left -= frames
    end
    # Slowed or sped up, the shots can run short of the narration by a frame or
    # two of rounding: the last one is held on.
    left > 0 && (clips[end].src_out = min(clips[end].src_out + left, clips[end].source.nframes))
    return clips
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
    narration(film, name, clips, at) -> VideoEditor.Narration

The approved narration of part `name` as a spoken take of the sequence: its
lines as the text, the recorded samples as the take (saved with the project,
so a render farm uses this performance and loads no speech model). A beat's
take follows its clip when the clip is moved; a montage's, which spans several
clips played at another speed, starts at `at` seconds into the sequence.
"""
function narration(film::SF.Film, name::AbstractString, clips, at)
    samples, rate = readwav(film.voice(name))
    part = film.parts[name]
    text = join(part.lines, " ")
    anchor, start = part isa SF.Beat ? (only(clips).source, 0.0) : (nothing, Float64(at))
    return VE.Narration(text, start, "af_heart", samples, rate, VE.SpeechSettings(), VE.VoiceMix(), String(name),
                        anchor)
end

function SF.filmsequence(film::SF.Film; canvas = (1280, 720), fps = 30, spp = 64)
    seq = VE.Sequence(VE.Clip[], fps)
    seq.canvas = Tuple(canvas)
    for name in film.cut
        part = film.parts[name]
        at = VE.seqlength(seq) / fps
        clips = if part isa SF.Beat
            frames = ceil(Int, film.timing(name).duration * fps)
            [SF.partclip(film, name; frames, canvas, fps, spp)]
        else
            montageclips(film, part; canvas, fps, spp)
        end
        for clip in clips
            clip.start = VE.seqlength(seq)
            VE.addclip!(seq, clip)
        end
        push!(seq.narration, narration(film, name, clips, at))
    end
    return seq
end

end
