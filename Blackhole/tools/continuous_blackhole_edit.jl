# Include after project.jl, in the sole Science4Makie root environment.
# Re-edit finished native footage. Never changes or regenerates beauty pixels.
import Mantle, Makie, OIDNRunner

const BH_CONTINUOUS_LINES = [
    "A black hole traps even light. We see it through the light around it: stars behind it, and a disk of hot, glowing gas. This simulation shows how gravity changes what we see.",
    "First, switch off light bending.",
    "This dark sphere marks the event horizon: the point of no return. Inside this boundary, even light cannot escape.",
    "Now, gravity bends the light on its way to us.",
    "Light from the back of the disk bends over the hole and under it, bringing the far side into view.",
    "The larger dark region is the shadow. It is not the event horizon. Light sent into this part of our view falls into the hole.",
    "Close to the shadow's edge, some light loops around the hole before escaping. This creates the thin photon ring, highlighted here.",
    "The gas moves at close to half the speed of light. Material coming towards us looks brighter. Material moving away looks dimmer. That contrast comes from the motion of the gas.",
    "We see the black hole in M eighty seven almost from above. Its hot gas appears as a glowing ring around a dark centre.",
]

function continuous_bh_voice!(root)
    mkpath(root)
    k=VE.KokoroRunner.Kokoro(;backend=Mantle.defaultbackend())
    takes=Vector{Float32}[]
    for (i,line) in enumerate(BH_CONTINUOUS_LINES)
        wav=joinpath(root,"line_$(i).wav")
        # Explicit per-line cache; never accidentally reuse another script.
        txt=joinpath(root,"line_$(i).txt")
        if isfile(wav) && isfile(txt) && read(txt,String)==line
            command=`$(VE.FFMPEG_jll.ffmpeg()) -v error -i $wav -f f32le -ar 24000 -ac 1 pipe:1`
            samples=collect(reinterpret(Float32,read(command)))
        else
            samples=Float32.(vec(Array(VE.KokoroRunner.speak(k,line;voice="af_heart",speed=0.95))))
            command=`$(VE.FFMPEG_jll.ffmpeg()) -v error -y -f f32le -ar 24000 -ac 1 -i pipe:0 -c:a pcm_f32le $wav`
            open(command,"w") do io
                write(io,samples)
            end
            write(txt,line)
        end
        push!(takes,samples)
        println("VOICE ",i," ",round(length(samples)/24000;digits=3),"s ",line);flush(stdout)
    end
    return takes
end

"Render representative frames through the ordinary final compositing pipeline."
function review_continuous_bh!(project)
    VE.usebackend!(RayMakie)
    seq=VE.loadproject(project);picture=bhclip(seq,1)
    segments=picture.source.build["args"]["editorial_segments"]
    frames=[picture.start+round(Int,(s["start"]+s["stop"])/2) for s in segments]
    engine=VE.FxEngine(Mantle.defaultbackend());readers=Dict{String,Any}()
    pixels=zeros(VE.RGB{VE.N0f8},seq.canvas...)
    dir=joinpath(dirname(project),"review");mkpath(dir);files=String[]
    try
        VE.withfinalscenes(seq) do
            for (i,n) in enumerate(frames)
                @assert VE.cachevalid(VE.trackcache(picture),picture.id,VE.sourceframe(picture,n))
                VE.renderframe!(pixels,seq,n,readers,engine)
                file=joinpath(dir,"phase_$(i)_$(n).png")
                VE.PNGFiles.save(file,permutedims(pixels));push!(files,file)
                println("REVIEW ",file);flush(stdout)
            end
        end
    finally
        VE.emptyengine!(engine);foreach(close,values(readers))
        VE.saveproject(project,seq;checkpoint=false)
        foreach(c->c.source.live===nothing || close(c.source),seq.clips)
    end
    return files
end

"Export the actual revised section, with its new natural narration."
function export_continuous_bh_preview!(project)
    VE.usebackend!(RayMakie)
    seq=VE.loadproject(project);picture=bhclip(seq,1)
    offset=picture.start
    filter!(c->get(c.source.build["args"],"beat","")=="a1_black_hole",seq.clips)
    filter!(n->n.anchor===picture.source,seq.narration)
    foreach(c->c.start-=offset,seq.clips)
    # Composite frames use timeline addresses; track planes use source frames.
    # Retain the actual full-film track caches and a separate preview composite.
    seq.compositecache=VE.TrackCache(joinpath(dirname(project),"section_composite"))
    output=joinpath(dirname(project),"black_hole_explanation_1080p.mp4")
    try
        VE.exportvideo(output,seq;encoder_options=(crf=18,preset="medium"),
            progress=(done,total)->(done%300==1 && (println("SECTION ",done,"/",total);flush(stdout))))
    finally
        # Track-plane validity is persisted on the full edit, never save the
        # trimmed section over it or move its cache directories with Save As.
        whole=VE.loadproject(project)
        empty!(whole.trackcaches);merge!(whole.trackcaches,seq.trackcaches)
        VE.saveproject(project,whole;checkpoint=false)
        foreach(c->c.source.live===nothing || close(c.source),seq.clips)
    end
    return output
end

"Adopt the finished section composites and export the full native edit from cache."
function export_continuous_film!(project;adopt_section=true,backend=Mantle.defaultbackend())
    VE.usebackend!(RayMakie)
    seq=VE.loadproject(project);picture=bhclip(seq,1)
    if adopt_section
        section=VE.TrackCache(joinpath(dirname(project),"section_composite"))
        for n in 0:VE.srclength(picture)-1
            file=VE.cachefile(section,UInt64(0),n)
            isfile(file) || error("Section composite missing: $n; finish the section export first")
            VE.linkplane!(seq.compositecache,UInt64(0),picture.start+n,file)
        end
    end
    total=VE.seqlength(seq)
    @assert all(VE.cachevalid(seq.compositecache,0,n) for n in 0:total-1)
    @assert all(VE.cachevalid(VE.trackcache(c),c.id,sf) for c in seq.clips if c.track==1 for sf in c.src_in:c.src_out-1)
    VE.saveproject(project,seq;checkpoint=false)
    output=joinpath(dirname(project),"black_hole_1080p.mp4")
    println("FULL EXPORT: all ",total," composites cached; zero picture or annotation renders needed");flush(stdout)
    try
        VE.exportvideo(output,seq;backend,encoder_options=(crf=18,preset="medium"),
            progress=(done,count)->(done%900==1 && (println("FULL ENCODE ",done,"/",count);flush(stdout))))
    finally
        VE.saveproject(project,seq;checkpoint=false)
        foreach(c->c.source.live===nothing || close(c.source),seq.clips)
    end
    verify_continuous_movie(output,total)
    return output
end

function verify_continuous_movie(movie,frames)
    ff=VE.FFMPEG_jll
    probe=strip(read(`$(ff.ffprobe()) -v error -count_frames -select_streams v:0 -show_entries stream=width,height,r_frame_rate,nb_read_frames -of csv=p=0 $movie`,String))
    split(probe,',')==["1920","1080","30/1",string(frames)] || error("Unexpected video metadata: $probe")
    audio=strip(read(`$(ff.ffprobe()) -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 $movie`,String))
    audio=="aac" || error("Missing narration audio")
    run(`$(ff.ffmpeg()) -v error -xerror -i $movie -f null -`)
    report="VERIFIED $frames frames; 1920x1080; 30 fps; AAC narration; complete decode passed\n$movie\n"
    write(movie*".validation.txt",report)
    println(report);flush(stdout)
    return nothing
end

bhclip(seq,track)=only(c for c in seq.clips if c.track==track && get(c.source.build["args"],"beat","")=="a1_black_hole")

"Create a moving, voice-led mapping through every original black-hole picture."
function continuous_bh_plan(old,takes,fps)
    a=old.source.build["args"]
    # These are the existing, FINISHED source phases. The horizon is marked
    # only between the two native zero-bending keys; not in a lensed image.
    f(t)=round(Int,t*fps)
    boundaries=[old.src_in,f(a["starts"][2]),f(a["starts"][2]+1.8),
        f(a["starts"][3]+0.8),f(a["starts"][3]+3.8),f(a["starts"][4]),
        f(a["starts"][4]+0.55*(a["ends"][4]-a["starts"][4])),
        f(a["starts"][5]),f(a["starts"][6]),old.src_out]
    mapping=Int[];audio=Float32[];segments=NamedTuple[]
    for i in eachindex(takes)
        firstsource,lastsource=boundaries[i],boundaries[i+1]
        count=lastsource-firstsource
        speech=takes[i]
        # Natural voice, a short breath between thoughts, and continuously
        # advancing native frames. No optical flow or newly rendered picture.
        lead=i==1 ? 0.45 : 0.18
        tail=i==length(takes) ? 0.8 : 0.35
        frames=max(ceil(Int,(length(speech)/24000+lead+tail)*fps),ceil(Int,count/0.9))
        rate=count/frames
        rate>=0.60 || error("Voice segment $i is too long for smooth cached motion (rate=$rate); shorten its script")
        start=length(mapping)
        append!(mapping,[firstsource+fld(n*count,frames) for n in 0:frames-1])
        # Film is 30 fps and voice 24 kHz, so every video frame is exactly 800
        # samples; quantize segment and cue boundaries once, never drift.
        samplecount=round(Int,frames/fps*24000)
        leadcount=round(Int,lead*24000)
        append!(audio,zeros(Float32,leadcount));append!(audio,speech)
        append!(audio,zeros(Float32,samplecount-leadcount-length(speech)))
        push!(segments,(;index=i,start,stop=length(mapping),
            voice_start=start/fps+lead,voice_end=start/fps+lead+length(speech)/24000,
            source_start=firstsource,source_stop=lastsource,rate))
    end
    @assert first(mapping)==old.src_in && last(mapping)==old.src_out-1
    @assert all(d->d in (0,1),diff(mapping))
    @assert length(unique(mapping))==VE.srclength(old)
    @assert maximum(count(==(sf),mapping) for sf in unique(mapping))<=2
    return (;mapping,audio,segments)
end

function prepare_continuous_bh!(project,baseline,takes)
    VE.usebackend!(RayMakie)
    seq=VE.loadproject(project);original=VE.loadproject(baseline)
    old=bhclip(original,1);picture=bhclip(seq,1);labels=bhclip(seq,2)
    fps=seq.framerate;plan=continuous_bh_plan(old,takes,fps)
    cut=VE.clipend(picture);extra=length(plan.mapping)-VE.srclength(picture)
    # Preserve shifted composites for EVERY unrelated beat before mutation.
    unchanged=[(n,VE.cachefile(seq.compositecache,0,n)) for n in cut:VE.seqlength(seq)-1
               if VE.cachevalid(seq.compositecache,0,n)]
    before=VE.trackcache(old)
    @assert all(VE.cachevalid(before,old.id,sf) for sf in plan.mapping)
    for c in seq.clips
        c.start>=cut && (c.start+=extra)
    end
    for c in (picture,labels)
        VE.invalidateclip!(c)
        c.source.nframes=length(plan.mapping);c.src_in=0;c.src_out=length(plan.mapping);c.rate=1.0
        c.source.build["args"]["duration"]=length(plan.mapping)/fps
        c.source.build["args"]["editorial_version"]="continuous_bh_20261024"
        c.source.build["args"]["editorial_segments"]=[Dict(string(k)=>v for (k,v) in pairs(s)) for s in plan.segments]
        previous=bhclip(original,c.track)
        filter!(p->p.input!==nothing,VE.findslot(c,:scene).params)
        for p in VE.findslot(previous,:scene).params
            p.input===nothing || continue
            c.track==2 && !startswith(String(p.name),"camera.") && continue
            values=[VE.valueat(p.curve[],sf) for sf in plan.mapping]
            all(v->v isa Real,values) || continue
            VE.keyframes!(c,String(p.name),[(n-1,v,:hold) for (n,v) in enumerate(values)];discrete=true)
        end
        c.source.root=VE.SceneProgram(c.source.build);c.source.live=nothing
    end
    film=loadfilm()
    built=Base.invokelatest(Base.invokelatest(getproperty,film,:buildscene),seq.canvas,labels.source.build["args"])
    paths=Base.invokelatest(getproperty,film,:NATIVE_PATHS)[("a1_black_hole",:labels)]
    for path in values(paths)
        VE.keyframes!(labels,path,[(0,0.0,:hold)])
    end
    function cue(name,firstframe,lastframe;fade=12)
        lastframe-firstframe>2fade || error("Cue too short: $name")
        VE.keyframes!(labels,paths[name],[(0,0.0,:linear),(firstframe,0.0,:linear),
            (firstframe+fade,1.0,:linear),(lastframe-fade,1.0,:linear),(lastframe,0.0,:linear)])
    end
    s=plan.segments
    cue("stars_caption",s[1].start+30,s[1].stop-4)
    cue("horizon_mark",s[3].start+3,s[3].stop-3)
    cue("straight_caption",s[3].start+3,s[3].stop-3)
    cue("bending_caption",s[4].start+3,s[4].stop-3)
    cue("far_side_label",s[5].start+3,s[5].stop-3)
    # No crossing leaders. The explanatory caption accompanies the changing
    # far-side image; shadow and ring each get their own long, separate beat.
    cue("shadow_label",s[6].start+3,s[6].stop-3)
    cue("ring_label",s[7].start+3,s[7].stop-3;fade=18)
    cue("doppler_labels",s[8].start+3,s[8].stop-3)
    cue("earth_caption",s[9].start+3,s[9].stop-3)
    Makie.free(built.scene)
    for c in (picture,labels)
        VE.bindcacheparams!(c,VE.findslot(c,:scene))
    end
    VE.bindinputs!(seq)
    # `plasma_time` was retimed with the numeric parameters above. The native
    # snapshot ParamInput still samples that clock, not its own `nothing` curve.
    # Snapshot filenames before publishing links: source and destination have
    # independent cache roots (the original baseline stays immutable).
    for (n,sf) in enumerate(plan.mapping)
        VE.linkplane!(VE.trackcache(picture),picture.id,n-1,VE.cachefile(before,old.id,sf))
    end
    take=only(n for n in seq.narration if n.anchor===picture.source)
    empty!(take.samples);append!(take.samples,plan.audio)
    take.text=join(BH_CONTINUOUS_LINES," ")
    # Publish shifted cached composites in safe order so links never read an
    # overwritten same-directory source frame.
    ordered=sort(unchanged;by=first,rev=extra>0)
    for (n,file) in ordered
        VE.linkplane!(seq.compositecache,UInt64(0),n+extra,file)
    end
    VE.invalidatecomposite!(seq,picture.start:VE.clipend(picture)-1)
    VE.saveproject(project,seq;checkpoint=false)
    println("CONTINUOUS EDIT ",length(plan.mapping)," frames; ",round(length(plan.mapping)/fps;digits=2),
        "s; ripple ",extra," frames; ",length(unique(plan.mapping))," original beauty pictures reused")
    foreach(s->println(s),plan.segments)
    return seq,plan
end
