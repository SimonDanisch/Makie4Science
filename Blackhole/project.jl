# Run in the Science4Makie environment (VideoEditor with RayMakie): builds the
# film as a VideoEditor project. Picture and transparent label clips per beat, from the recipe
# `film/film.jl`, as long as that beat's approved narration; the narration is
# laid under each clip as an approved take, anchored to it so it follows cuts.

using VideoEditor, RayMakie
import VideoEditor as VE

include(joinpath(@__DIR__, "film", "lines.jl"))

const VOICE = joinpath(@__DIR__, "voice")
const VOICE_RATE = 24000

"""The film recipe in a fresh module, so edits to film/ are picked up by calling it again."""
function loadfilm()
    m = Module(:Film)
    # what `module` syntax would define: the recipe includes its own files
    Core.eval(m, :(include(path) = Base.include($m, path)))
    Base.include(m, joinpath(@__DIR__, "film", "film.jl"))
    return m
end

"""
    keybeat!(clip, film) -> clip

Key a performed beat's native Makie properties on `clip`, from narration timing in its
scene arguments (`film.beatkeys`), replacing their keys. Its keys are all that
moves it, so frames with equal values trace once.
"""
function keybeat!(clip, film)
    performance=Base.invokelatest(getproperty,film,:beatkeys)
    keyed = Base.invokelatest(performance, clip.source.build["args"], clip.source.framerate)
    fx=VE.findslot(clip,:scene)
    # Remove the superseded argument interface, preserving the file-series input
    # under its actual medium-plot attribute address.
    for (i,p) in enumerate(fx.params)
        p.name===Symbol("args.plasma") || continue
        fx.params[i]=VE.Param{Any}(Symbol("plasma_volume.snapshot"),p.label,p.curve,p.visible,p.range,p.input,p.view)
    end
    filter!(p->!startswith(String(p.name),"args."),fx.params)
    delete!(clip.source.build,"static")
    isempty(keyed) && return clip
    for (path, keys, discrete) in keyed
        VE.keyframes!(clip, path, keys; discrete)
    end
    return clip
end

"Replace every film clip's animation with native property tracks, preserving the edit and takes."
function keyproject!(seq; film=loadfilm())
    for clip in seq.clips
        clip.source isa VE.SceneSource || continue
        args=get(clip.source.build,"args",Dict())
        haskey(args,"beat") || continue
        keybeat!(clip,film)
        clip.source.root=VE.SceneProgram(clip.source.build)
        clip.source.live=nothing
        VE.invalidateclip!(clip)
    end
    VE.bindinputs!(seq)
    return seq
end

"""Import a beat's approved line timing from its existing timing file."""
function read_timing(name;root=VOICE)
    l = readlines(joinpath(root, name * ".timing"))
    return (starts = parse.(Float32, split(l[2])), ends = parse.(Float32, split(l[3])), duration = parse(Float32, l[4]))
end

"Append the native Makie credits clips once; retain the existing edit and caches."
function appendcredits!(seq; seconds = 12)
    any(c -> c.source isa VE.SceneSource &&
        get(c.source.build["args"], "beat", "") == "c4_credits", seq.clips) && return seq
    seconds >= 10 || throw(ArgumentError("credits need at least ten seconds to read"))
    start = maximum(VE.clipend, seq.clips)
    frames = round(Int, seconds * seq.framerate)
    recipe = joinpath(@__DIR__, "film", "film.jl")
    for (track,layer) in ((1,"picture"),(2,"labels"))
        args = Dict{String,Any}("beat"=>"c4_credits", "starts"=>[0f0],
            "ends"=>[Float32(seconds)], "duration"=>Float32(seconds), "layer"=>layer)
        build = VE.programscene(recipe; args)
        clip = VE.sceneclip(VE.buildscene(build); build, start, frames,
            canvas=seq.canvas, framerate=seq.framerate, backend=:RayMakie)
        clip.track=track
        VE.setrenderconfig!(clip; raytrace=false, device="Mantle.defaultbackend()", fxaa=track!=2)
        push!(seq.clips,clip)
        clip.sequence=seq
    end
    VE.bindinputs!(seq)
    return seq
end

"""Import an existing approved narration take from its WAV file."""
function read_voice(name;root=VOICE)
    path=joinpath(root,name*".wav")
    command=`$(VE.FFMPEG_jll.ffmpeg()) -v error -i $path -f f32le -ar $VOICE_RATE -ac 1 pipe:1`
    return collect(reinterpret(Float32,read(command)))
end

"""The words as said, without stress marks."""
plain(line) = replace(line, r"\[([^\[\]]+)\]\([^)]*\)" => s"\1")

"""
    buildproject(path; canvas, fps, spp, beats) -> (; path, sequence)

The film as a `.videoedit` project at `path`. Previews rasterize; bake
(export, farm) traces at `spp` samples.
"""
function buildproject(path; canvas = (1280, 720), fps = 30, spp = 256, beats = first.(BEATS),
                      voice_root=VOICE, labels=Dict{String,String}(),
                      credits=true,
                      cache_root=path*".frames", raytraced=("a1_black_hole", "a2_two_numbers", "a3_tiny", "a4_giant_telescope", "b0_stations", "b4_one_note", "b5_earth_turns", "c2_space"))
    VE.usebackend!(RayMakie)
    recipe = joinpath(@__DIR__, "film", "film.jl")
    film = loadfilm()
    lines = Dict(BEATS)
    clips = VE.Clip[]
    start = 0
    for name in beats
        t = read_timing(name;root=voice_root)
        frames = ceil(Int, t.duration * fps)
        args=Dict{String,Any}("beat"=>name,"starts"=>t.starts,"ends"=>t.ends,"duration"=>t.duration,"layer"=>"picture")
        build = VE.programscene(recipe; args)
        clip = VE.sceneclip(VE.buildscene(build); build, start, frames, canvas, framerate = fps, backend = :RayMakie)
        VE.setrenderconfig!(clip;raytrace=name in raytraced,samples=spp,device="Mantle.defaultbackend()",
                           max_depth=name in ("a1_black_hole", "a2_two_numbers") ? 512 : 8)
        if name in raytraced
            VE.addslot!(clip,VE.Effect(VE.OIDNDenoiseEffect()))
            VE.addslot!(clip,VE.Effect(VE.LinearGradeEffect()))
            VE.addslot!(clip,VE.Effect(VE.ToneMapEffect()))
        end
        VE.addslot!(clip, VE.Effect(VE.ColorEffect()))
        keybeat!(clip, film)
        push!(clips, clip)
        labelbuild=VE.programscene(recipe;args=merge(args,Dict("layer"=>"labels","labels"=>labels)))
        labelclip=VE.sceneclip(VE.buildscene(labelbuild);build=labelbuild,start,frames,canvas,framerate=fps)
        labelclip.track=2
        # Glyphs already use their own distance-field antialiasing. Preserve
        # their exact coverage instead of applying a second FXAA pass.
        VE.setrenderconfig!(labelclip;device="Mantle.defaultbackend()",fxaa=false)
        keybeat!(labelclip, film)
        push!(clips,labelclip)
        start += frames
    end
    seq = VE.Sequence(clips, fps)
    seq.canvas = canvas
    VE.enabletrackcache!(seq,cache_root)
    for (clip, name) in zip(filter(c -> c.track==1,clips), beats)
        take = VE.Narration(join(plain.(lines[name]), " "), 0.0, "af_heart"; label = name, anchor = clip.source)
        append!(take.samples, read_voice(name;root=voice_root))
        take.rate = VOICE_RATE
        push!(seq.narration, take)
    end
    credits && "c3_outro" in beats && appendcredits!(seq)
    VE.saveproject(path, seq)
    return (; path, sequence = seq)
end

"Extend a beat's tail without changing the animation time of existing frames."
function extendbeat!(seq,name,seconds)
    added=round(Int,seconds*seq.framerate)
    added>0 || throw(ArgumentError("extension must add at least one frame"))
    pair=filter(c -> c.source isa VE.SceneSource && get(c.source.build["args"],"beat","")==name,seq.clips)
    isempty(pair) && error("unknown beat $name")
    cut=maximum(VE.clipend,pair)
    for c in seq.clips
        c in pair && continue
        c.start>=cut && (c.start+=added)
    end
    for c in pair
        c.source.nframes+=added
        c.src_out+=added
    end
    return seq
end

"""Refresh one revised beat in place, ripple later clips, and replace its voice take.

Stable clip/source identities retain every unaffected native track-cache entry.
Recipe edits and new cue timings are declared through `setsceneargs!`; a
performed beat's keys are written again for the new timing.
"""
function refreshbeat!(seq, name; voice_root = joinpath(@__DIR__, "voice_v6"), film = loadfilm())
    pair = filter(c -> c.source isa VE.SceneSource && get(c.source.build["args"], "beat", "") == name, seq.clips)
    isempty(pair) && error("unknown beat $name")
    timing = read_timing(name; root = voice_root)
    frames = ceil(Int, timing.duration * seq.framerate)
    cut = maximum(VE.clipend, pair)
    delta = first(pair).start + frames - cut
    for c in seq.clips
        c in pair && continue
        c.start >= cut && (c.start += delta)
    end
    for c in pair
        c.source.nframes = frames
        c.src_out = frames
        VE.setsceneargs!(c, Dict("starts" => timing.starts, "ends" => timing.ends, "duration" => timing.duration))
        keybeat!(c, film)
    end
    take = only(filter(n -> n.anchor === only(filter(c -> c.track == 1, pair)).source, seq.narration))
    take.text = join(plain.(Dict(BEATS)[name]), " ")
    empty!(take.samples)
    append!(take.samples, read_voice(name; root = voice_root))
    take.rate = VOICE_RATE
    return seq
end

"Replace raster labels; declare the source-frame span in which they appear."
function editlabels!(seq,name,replacements;frames=nothing)
    clip=only(filter(c -> c.track==2 && get(c.source.build["args"],"beat","")==name,seq.clips))
    old=get(clip.source.build["args"],"labels",Dict{String,String}())
    VE.setsceneargs!(clip,Dict("labels"=>merge(old,replacements));
                     frames=something(frames,clip.src_in:(clip.src_out-1)))
    return clip
end

"""
    exportraster(project, out)

Export a persistent raster review project. Renderer changes go through the
editor's invalidation API once; stable clip ids, track caches and composite
caches survive every export. Use a separate project for the traced final.
"""
function exportraster(project, out; progress = (d, t) -> ((d == t || (d - 1) % 300 == 0) && (println("$d/$t"); flush(stdout))))
    VE.usebackend!(RayMakie)
    seq = VE.loadproject(project)
    for clip in seq.clips
        s = clip.source
        s isa VE.SceneSource || continue
        if !get(s.bakescreenopts, :rasterize, true) || get(s.bakescreenopts, :samples, 1) != 1
            options = filter(p -> first(p) ∉ (:rasterize, :samples), s.bakescreenopts)
            VE.setrenderconfig!(clip; backend = s.backend, raytrace = false, options...)
        end
    end
    isempty(seq.trackcaches) && VE.enabletrackcache!(seq, project * ".frames")
    VE.saveproject(project, seq)
    checkpoint_progress = function (done, total)
        if done == total || (done - 1) % 300 == 0
            VE.saveproject(project, seq; checkpoint = false)
        end
        progress === nothing || progress(done, total)
    end
    try
        VE.exportvideo(out, seq; encoder_options = (crf = 18, preset = "medium"), progress = checkpoint_progress)
    finally
        # Preserve completed native cache entries even after an interrupted export.
        VE.saveproject(project, seq)
    end
    return out
end
