# Corrections to the completed delivery, using only the Science4Makie root.
# Run prepare_corrections! once. The baseline project/movie/caches stay intact.
include(joinpath(@__DIR__, "..", "project.jl"))
using FileIO
import Mantle, OIDNRunner, Makie

const BASE_DELIVERY = normpath(joinpath(@__DIR__, "..", "renders", "recording_1080p_20261023", "film_1080p.videoedit"))
const FIXED_DELIVERY = normpath(joinpath(@__DIR__, "..", "renders", "corrections_1080p_20261024", "film_1080p.videoedit"))
beatclip(seq, beat, track) = only(c for c in seq.clips if c.track == track && get(c.source.build["args"], "beat", "") == beat)

"Insert editorial holds without losing, synthesizing, or tracing a picture frame."
function hold_blackhole!(seq, baseline)
    old = beatclip(baseline, "a1_black_hole", 1)
    args = old.source.build["args"]
    fps = seq.framerate
    # Pauses FOLLOW complete recorded sentences, never split a spoken word.
    holds = [(ceil(Int, args["ends"][i] * fps), round(Int, seconds * fps))
             for (i, seconds) in ((1, 5), (3, 2), (4, 5), (5, 2))]
    mapping = Int[]
    for sf in old.src_in:old.src_out-1
        for (at, count) in holds
            sf == at && append!(mapping, fill(sf - 1, count))
        end
        push!(mapping, sf)
    end
    extra = length(mapping) - VE.srclength(old)
    for c in seq.clips
        c.start >= VE.clipend(old) && (c.start += extra)
    end
    shifted(t) = Float32(t + sum(count / fps for (at, count) in holds if at / fps <= t; init=0.0))
    for track in (1, 2)
        c = beatclip(seq, "a1_black_hole", track)
        previous = beatclip(baseline, "a1_black_hole", track)
        c.source.nframes = length(mapping)
        c.src_out = length(mapping)
        VE.setsceneargs!(c, Dict("starts" => shifted.(args["starts"]),
            "ends" => shifted.(args["ends"]), "duration" => length(mapping) / fps))
        fx = VE.findslot(c, :scene)
        for (i, p) in enumerate(VE.findslot(previous, :scene).params)
            p.input === nothing || continue
            # Sample EXACT existing source-frame values; do not regenerate the
            # camera/medium animation from revised narration timing.
            values = [VE.valueat(p.curve[], sf) for sf in mapping]
            all(v -> v isa Real, values) || continue
            VE.keyframes!(c, String(p.name), [(n-1, v, :hold) for (n, v) in enumerate(values)]; discrete=true)
            fresh = only(q for q in fx.params if q.name == p.name)
            @assert all(isequal(VE.valueat(fresh.curve[], n-1), values[n]) for n in eachindex(mapping))
        end
        VE.bindcacheparams!(c, fx)
        if track == 1
            # Every linked plane is an actual, valid original picture. The
            # native cache adoption API publishes it under the new edit's clock.
            cache, before = VE.trackcache(c), VE.trackcache(previous)
            @assert all(sf -> VE.cachevalid(before, previous.id, sf), mapping)
            for (n, sf) in enumerate(mapping)
                VE.linkplane!(cache, c.id, n-1, VE.cachefile(before, previous.id, sf))
            end
            @assert all(sf -> VE.cachevalid(cache, c.id, sf), 0:length(mapping)-1)
        end
    end
    # Reuse the approved voice samples, inserting silence at the same holds.
    oldtake = only(n for n in baseline.narration if n.anchor === old.source)
    newpicture = beatclip(seq, "a1_black_hole", 1)
    take = only(n for n in seq.narration if n.anchor === newpicture.source)
    samples = Float32[]
    firstsample = 1
    for (at, count) in holds
        stop = min(round(Int, at / fps * oldtake.rate), length(oldtake.samples))
        append!(samples, oldtake.samples[firstsample:stop])
        append!(samples, zeros(Float32, round(Int, count / fps * oldtake.rate)))
        firstsample = stop + 1
    end
    append!(samples, oldtake.samples[firstsample:end])
    empty!(take.samples); append!(take.samples, samples)
    return (; mapping, holds, extra)
end

function prepare_corrections!()
    marker = joinpath(dirname(FIXED_DELIVERY), "prepared.json")
    isfile(marker) && error("Corrections already prepared; open the saved corrected project")
    VE.usebackend!(RayMakie)
    baseline = VE.loadproject(BASE_DELIVERY)
    seq = VE.loadproject(FIXED_DELIVERY)
    before = Dict(c.id => (c.start, c.src_out) for c in baseline.clips)
    retiming = hold_blackhole!(seq, baseline)
    film = loadfilm()
    # Rebuild only annotation cues: picture values/planes above stay exact.
    labels = beatclip(seq, "a1_black_hole", 2)
    built = Base.invokelatest(film.buildscene, (1280,720), labels.source.build["args"])
    paths = film.NATIVE_PATHS[("a1_black_hole", :labels)]
    oldargs = beatclip(baseline, "a1_black_hole", 1).source.build["args"]
    shiftframe(sf) = sf + sum(n for (at,n) in retiming.holds if at <= sf; init=0)
    ringstart = round(Int, (oldargs["starts"][4] + 0.55 * (oldargs["ends"][4] - oldargs["starts"][4])) * seq.framerate)
    dopplerstart = round(Int, oldargs["starts"][5] * seq.framerate)
    VE.keyframes!(labels, paths["ring_label"], [(shiftframe(ringstart), 0.0, :linear),
        (shiftframe(ringstart)+12, 1.0, :linear), (shiftframe(dopplerstart)-12, 1.0, :linear),
        (shiftframe(dopplerstart), 0.0, :linear)])
    VE.bindcacheparams!(labels, VE.findslot(labels,:scene))
    Makie.free(built.scene)
    # Station controls now survive the layer split; write those missing tracks
    # and replace the old stop/start rotation in both layers.
    for track in (1,2)
        c = beatclip(seq,"b0_stations",track)
        keybeat!(c,film)
        VE.bindcacheparams!(c,VE.findslot(c,:scene))
        VE.invalidateclip!(c)
    end
    # air! is shared by these Earth shots. Do not invalidate their unrelated
    # label layers, nor any other picture shot (especially either black hole).
    for beat in ("a3_tiny", "a4_giant_telescope", "b4_one_note", "b5_earth_turns", "c2_space")
        c = beatclip(seq,beat,1)
        VE.invalidateclip!(c)
        c.source.root = VE.SceneProgram(c.source.build)
        c.source.live = nothing
    end
    VE.bindinputs!(seq)
    VE.saveproject(FIXED_DELIVERY,seq;checkpoint=false)
    # Reopening is part of the no-black-hole-render contract.
    check = VE.loadproject(FIXED_DELIVERY)
    bh = beatclip(check,"a1_black_hole",1)
    @assert all(sf -> VE.cachevalid(VE.trackcache(bh),bh.id,sf), bh.src_in:bh.src_out-1)
    needed = VE.farmneededframes(check)
    @assert all(n -> all(c -> !(get(c.source.build["args"],"beat","") in ("a1_black_hole","a2_two_numbers")), VE.frameclips(check,n)), needed)
    report = Dict("baseline_frames"=>VE.seqlength(baseline),"frames"=>VE.seqlength(check),
        "blackhole_new_traces"=>0,"blackhole_picture_frames_reused"=>length(retiming.mapping),
        "blackhole_holds"=>retiming.holds,"farm_frames_before_test"=>length(needed))
    open(io -> write(io,VE.JSON.json(report)), marker, "w")
    println(report)
    return check
end

"Replace only the inaccurate recording sentence, retaining the other takes."
function correct_recording_voice!(seq)
    picture = beatclip(seq,"b1_recording",1)
    take = only(n for n in seq.narration if n.anchor === picture.source)
    start = Float64(picture.source.build["args"]["starts"][4])
    line = last(Dict(BEATS)["b1_recording"])
    k = VE.KokoroRunner.Kokoro(;backend=Mantle.defaultbackend())
    spoken = replace(line,r"(?<=\w)-(?=\w)"=>" ")
    voice = Float32.(vec(Array(VE.KokoroRunner.speak(k,spoken;voice="af_heart",speed=0.95))))
    offset = round(Int,start*take.rate)
    oldlength = length(take.samples)
    # A changed final sentence may extend this raster-only beat, never shorten
    # its natural speech or touch the first three approved takes.
    frames = max(VE.srclength(picture),ceil(Int,(start+length(voice)/take.rate+1.5)*seq.framerate))
    extra = frames-VE.srclength(picture)
    cut = VE.clipend(picture)
    if extra > 0
        for c in seq.clips
            c.start >= cut && (c.start += extra)
        end
    end
    prefix = copy(take.samples[1:offset])
    empty!(take.samples);append!(take.samples,prefix);append!(take.samples,voice)
    append!(take.samples,zeros(Float32,round(Int,frames/seq.framerate*take.rate)-length(take.samples)))
    take.text=join(plain.(Dict(BEATS)["b1_recording"])," ")
    for track in (1,2)
        c=beatclip(seq,"b1_recording",track)
        c.source.nframes=frames;c.src_out=frames
        # This text exists only on the annotation layer. All earlier source
        # planes, the first three takes, and all other clips stay reusable.
        track==2 && VE.invalidateclip!(c;frames=floor(Int,start*seq.framerate):frames-1)
        c.source.root=VE.SceneProgram(c.source.build);c.source.live=nothing
    end
    VE.saveproject(FIXED_DELIVERY,seq;checkpoint=false)
    println("RECORDING VOICE corrected final sentence; added ",extra," frames; preserved ",offset," approved audio samples")
    return seq
end

"Separate horizon/shadow/ring; reuse a straight-light master for the introduction."
function clarify_blackhole!(seq)
    baseline=VE.loadproject(BASE_DELIVERY)
    old=beatclip(baseline,"a1_black_hole",1)
    args=old.source.build["args"]
    fps=seq.framerate
    holds=[(ceil(Int,args["ends"][i]*fps),round(Int,seconds*fps))
        for (i,seconds) in ((1,5),(3,2),(4,5),(5,2))]
    mapping=Int[]
    for sf in 0:old.src_out-1
        for (at,count) in holds
            sf==at && append!(mapping,fill(sf-1,count))
        end
        push!(mapping,sf)
    end
    # Frame 360 already has bending=0, and a clean visible physical horizon.
    # Hold that SAME cached illustration through the opening explanation;
    # resume its existing motion at its original frame, with no reverse jump.
    mapping=max.(mapping,360)
    for track in (1,2)
        c=beatclip(seq,"a1_black_hole",track)
        previous=beatclip(baseline,"a1_black_hole",track)
        VE.invalidateclip!(c)
        c.source.root=VE.SceneProgram(c.source.build);c.source.live=nothing
        for p in VE.findslot(previous,:scene).params
            p.input===nothing || continue
            track==2 && !startswith(String(p.name),"camera.") && continue
            values=[VE.valueat(p.curve[],sf) for sf in mapping]
            all(v->v isa Real,values) || continue
            VE.keyframes!(c,String(p.name),[(n-1,v,:hold) for (n,v) in enumerate(values)];discrete=true)
        end
        if track==1
            before,cache=VE.trackcache(previous),VE.trackcache(c)
            for (n,sf) in enumerate(mapping)
                @assert VE.cachevalid(before,previous.id,sf)
                VE.linkplane!(cache,c.id,n-1,VE.cachefile(before,previous.id,sf))
            end
        end
        VE.bindcacheparams!(c,VE.findslot(c,:scene))
    end
    labels=beatclip(seq,"a1_black_hole",2)
    film=loadfilm()
    built=Base.invokelatest(film.buildscene,(1280,720),labels.source.build["args"])
    paths=film.NATIVE_PATHS[("a1_black_hole",:labels)]
    shift(t)=t+sum(n/fps for (at,n) in holds if at/fps<=t;init=0.0)
    ring=shift(args["starts"][4]+0.55*(args["ends"][4]-args["starts"][4]))
    doppler=shift(args["starts"][5])
    function cue(name,entries)
        VE.keyframes!(labels,paths[name],[(round(Int,t*fps),v,e) for (t,v,e) in entries])
    end
    cue("horizon_mark",[(0.0,0.0,:linear),(1.1,0.0,:linear),(1.5,1.0,:linear),
        (shift(args["starts"][2])-0.8,1.0,:linear),(shift(args["starts"][2])-0.4,0.0,:linear)])
    cue("stars_caption",[(0.0,0.0,:hold)])
    cue("sizes",[(0.0,0.0,:hold)])
    cue("straight_caption",[(0.0,1.0,:linear),(shift(args["starts"][3])-0.4,1.0,:linear),
        (shift(args["starts"][3]),0.0,:linear)])
    cue("shadow_label",[(shift(args["starts"][4]),0.0,:linear),
        (shift(args["starts"][4])+0.5,1.0,:linear),(ring-0.5,1.0,:linear),(ring,0.0,:linear)])
    cue("ring_label",[(ring,0.0,:linear),(ring+0.4,1.0,:linear),(doppler-0.5,1.0,:linear),(doppler,0.0,:linear)])
    VE.bindcacheparams!(labels,VE.findslot(labels,:scene))
    Makie.free(built.scene)
    VE.bindinputs!(seq)
    @assert all(VE.cachevalid(VE.trackcache(beatclip(seq,"a1_black_hole",1)),old.id,n) for n in 0:length(mapping)-1)
    VE.saveproject(FIXED_DELIVERY,seq;checkpoint=false)
    println("CLARIFIED BLACK HOLE: straight-light introduction; sequential highlights; zero new picture renders")
    return seq
end

"Reuse even the unchanged portions of Earth shots and shifted composites."
function reuse_unchanged!(seq)
    baseline=VE.loadproject(BASE_DELIVERY)
    oldbyid=Dict(c.id=>c for c in baseline.clips)
    function unchanged(c,sf)
        beat=c.source.build["args"]["beat"]
        beat=="a1_black_hole" && return false
        beat=="b0_stations" && return sf<189
        beat=="a3_tiny" && return sf<310
        beat=="b4_one_note" && return 329<=sf<1598 || 1771<=sf<2095
        beat in ("a4_giant_telescope","b5_earth_turns","c2_space") && return false
        beat=="b1_recording" && return sf<floor(Int,c.source.build["args"]["starts"][4]*seq.framerate)
        return true
    end
    restored=0
    for c in seq.clips
        c.track==1 || continue
        c.source.build["args"]["beat"] in ("b0_stations","a3_tiny","b4_one_note") || continue
        old=oldbyid[c.id]; before=VE.trackcache(old);cache=VE.trackcache(c)
        for sf in c.src_in:c.src_out-1
            unchanged(c,sf) && VE.cachevalid(before,old.id,sf) || continue
            VE.linkplane!(cache,c.id,sf,VE.cachefile(before,old.id,sf));restored+=1
        end
    end
    composites=0
    for n in 0:VE.seqlength(seq)-1
        clips=VE.frameclips(seq,n)
        isempty(clips) && continue
        all(c->unchanged(c,VE.sourceframe(c,n)),clips) || continue
        oldframes=[oldbyid[c.id].start+VE.sourceframe(c,n)-oldbyid[c.id].src_in for c in clips]
        all(==(first(oldframes)),oldframes) || continue
        sf=first(oldframes)
        VE.cachevalid(baseline.compositecache,0,sf) || continue
        VE.linkplane!(seq.compositecache,UInt64(0),n,VE.cachefile(baseline.compositecache,0,sf));composites+=1
    end
    needed=VE.farmneededframes(seq)
    @assert all(n->all(c->!(get(c.source.build["args"],"beat","") in ("a1_black_hole","a2_two_numbers")),VE.frameclips(seq,n)),needed)
    VE.saveproject(FIXED_DELIVERY,seq;checkpoint=false)
    println("REUSE unchanged Earth planes=",restored," shifted composites=",composites," farm-needed=",length(needed))
    return seq
end

"Declare the validated no-grey-fill Earth lighting change, retaining other caches."
function correct_atmosphere_lighting!(seq)
    ranges=Dict("b0_stations"=>[189:581],"a3_tiny"=>[310:447],
        "a4_giant_telescope"=>[0:573],"b4_one_note"=>[0:328,1598:1770],
        "b5_earth_turns"=>[0:559],"c2_space"=>[0:545])
    for (beat,spans) in ranges
        c=beatclip(seq,beat,1)
        VE.invalidateclip!(c;frames=reduce(vcat,collect.(spans)))
        c.source.root=VE.SceneProgram(c.source.build)
        c.source.live=nothing
    end
    # Explicit source mutation above does not touch either black-hole picture.
    for beat in ("a1_black_hole","a2_two_numbers")
        c=beatclip(seq,beat,1)
        @assert all(sf->VE.cachevalid(VE.trackcache(c),c.id,sf),c.src_in:c.src_out-1)
    end
    VE.saveproject(FIXED_DELIVERY,seq;checkpoint=false)
    println("Earth lighting corrected; all black-hole picture planes remain valid")
    return seq
end

"Render review frames into the corrected delivery's OWN native caches."
function review_corrections!(seq, frames)
    dir = joinpath(dirname(FIXED_DELIVERY),"review")
    mkpath(dir)
    engine = VE.FxEngine(Mantle.defaultbackend())
    readers = Dict{String,Any}()
    pixels = zeros(VE.RGB{VE.N0f8},seq.canvas...)
    try
        VE.withfinalscenes(seq) do
            for n in frames
                active = Set(c.id for c in VE.frameclips(seq,n))
                for c in seq.clips
                    c.id in active || c.source.live === nothing || close(c.source)
                end
                VE.renderframe!(pixels,seq,n,readers,engine)
                path=joinpath(dir,string(n;pad=6)*".png")
                VE.PNGFiles.save(path,permutedims(pixels))
                VE.saveproject(FIXED_DELIVERY,seq;checkpoint=false)
                println("REVIEW ",n," ",path);flush(stdout)
            end
        end
    finally
        VE.saveproject(FIXED_DELIVERY,seq;checkpoint=false)
        VE.emptyengine!(engine)
        foreach(close,values(readers))
    end
    return dir
end
