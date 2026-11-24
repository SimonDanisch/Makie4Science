# ROOT project only; include after project.jl and continuous_blackhole_edit.jl.
import Mantle, Makie, OIDNRunner
const REGRESSION_VOICE_MODEL=Ref{Any}(nothing)
const STRIPE_INTRO_PARTS=[
    "start with just two telescopes, looking at the same patch of sky.",
    "light arrives as a wave.",
    "from straight ahead, each wavefront reaches both telescopes together.",
    "their recordings line up.",
    "now look a little to one side.",
    "the light travels farther to one telescope.",
    "that extra distance delays its recording, so the two waves no longer line up.",
]

function regression_voice(text,name;letters=false,speed=0.92)
    root=abspath(joinpath(@__DIR__,"..","voice_revision2_20261024"));mkpath(root)
    wav=joinpath(root,name*".wav");stamp=joinpath(root,name*".txt")
    signature=repr((text,letters,speed))
    if isfile(wav) && isfile(stamp) && read(stamp,String)==signature
        return collect(reinterpret(Float32,read(`$(VE.FFMPEG_jll.ffmpeg()) -v error -i $wav -f f32le -ac 1 -ar 24000 pipe:1`)))
    end
    REGRESSION_VOICE_MODEL[]===nothing && (REGRESSION_VOICE_MODEL[]=VE.KokoroRunner.Kokoro(;backend=Mantle.defaultbackend()))
    k=REGRESSION_VOICE_MODEL[]
    spoken=text
    if letters
        # The built-in G2P deliberately treats even capital A as an article.
        # Override specific placeholder tokens, NEVER the indefinite article.
        for (letter,phonemes) in (("A","ˈA"),("B","bˈi"),("C","sˈi"))
            token="StationLetter"*letter
            VE.KokoroRunner.pronounce!(k,token=>phonemes)
            spoken=replace(spoken,Regex("\\b"*letter*"\\b")=>token)
        end
    end
    phonemes=VE.KokoroRunner.phonemize(k,spoken)
    samples=Float32.(vec(Array(VE.KokoroRunner.speak(k;phonemes,voice="af_heart",speed))))
    open(`$(VE.FFMPEG_jll.ffmpeg()) -v error -y -f f32le -ar 24000 -ac 1 -i pipe:0 -c:a pcm_f32le $wav`,"w") do io
        write(io,samples)
    end
    write(stamp,signature)
    println("VOICE ",name," ",round(length(samples)/24000;digits=2),"s; ",phonemes);flush(stdout)
    return samples
end

regclip(seq,beat,track)=only(c for c in seq.clips if c.track==track && c.source.build["args"]["beat"]==beat)

function regression_label_paths(seq,beat;rekey=false)
    c=regclip(seq,beat,2);film=loadfilm()
    built=Base.invokelatest(Base.invokelatest(getproperty,film,:buildscene),seq.canvas,c.source.build["args"])
    paths=copy(Base.invokelatest(getproperty,film,:NATIVE_PATHS)[(beat,:labels)])
    if rekey
        keys=Base.invokelatest(Base.invokelatest(getproperty,film,:beatkeys),c.source.build["args"],seq.framerate)
        filter!(p->p.input!==nothing,VE.findslot(c,:scene).params)
        for (path,entries,discrete) in keys
            VE.keyframes!(c,path,entries;discrete)
        end
    end
    Makie.free(built.scene)
    VE.invalidateclip!(c);c.source.root=VE.SceneProgram(c.source.build);c.source.live=nothing
    return paths
end

function regression_cue!(c,path,start,stop;fade=0.4,fps=30)
    a,b=round(Int,start*fps),round(Int,stop*fps);d=min(round(Int,fade*fps),fld(b-a-1,2))
    keys=[(0,0.,:linear),(max(1,a),0.,:linear),(a+d,1.,:linear),(b-d,1.,:linear),(b,0.,:linear)]
    VE.keyframes!(c,path,keys)
end

function prepare_bh_regression!(seq,original,takes)
    old=regclip(original,"a1_black_hole",1);fps=seq.framerate;a=old.source.build["args"]
    f(t)=round(Int,t*fps)
    # CUT to actual full-gas, zero-bending cached pictures, rather than
    # pretending the bare-hole opening already contains luminous gas.
    firstgas,laststraight=345,524
    span(i)=length(takes[i])/24000+0.95
    cut=firstgas+round(Int,(laststraight-firstgas)*span(2)/(span(2)+span(3)))
    ranges=[(0,f(a["starts"][2])),(firstgas,cut),(cut,laststraight),
        (laststraight,f(a["starts"][3]+3.8)),(f(a["starts"][3]+3.8),f(a["starts"][4])),
        (f(a["starts"][4]),f(a["starts"][4]+0.55*(a["ends"][4]-a["starts"][4]))),
        (f(a["starts"][4]+0.55*(a["ends"][4]-a["starts"][4])),f(a["starts"][5])),
        (f(a["starts"][5]),f(a["starts"][6])),(f(a["starts"][6]),old.src_out)]
    mapping=Int[];samples=Float32[];segments=NamedTuple[]
    for (i,(lo,hi)) in enumerate(ranges)
        lead=i==1 ? 0.5 : 0.25
        tail=i in (6,7) ? 0.9 : 0.7
        n=max(ceil(Int,(length(takes[i])/24000+lead+tail)*fps),ceil(Int,(hi-lo)/0.85))
        (hi-lo)/n>=0.5 || error("Cached motion would repeat >2 frames in phase $i")
        start=length(mapping);append!(mapping,[lo+fld(j*(hi-lo),n) for j in 0:n-1])
        append!(samples,zeros(Float32,round(Int,lead*24000)));append!(samples,takes[i])
        resizecount=round(Int,n/fps*24000)-round(Int,lead*24000)-length(takes[i])
        append!(samples,zeros(Float32,resizecount))
        push!(segments,(;index=i,start,stop=length(mapping),voice_start=start/fps+lead,
            voice_end=start/fps+lead+length(takes[i])/24000,source_start=lo,source_stop=hi,rate=(hi-lo)/n))
    end
    lines=copy(BH_CONTINUOUS_LINES)
    lines[1]="A black hole traps even light. Here, the stars behind it are stretched into arcs. This simulation shows how gravity changes the light that reaches us."
    lines[2]="Hot gas glows around the hole."
    remap_regression_clip!(seq,original,"a1_black_hole",mapping;samples,text=join(lines," "),labels_changed=true)
    for t in (1,2)
        c=regclip(seq,"a1_black_hole",t)
        c.source.build["args"]["editorial_segments"]=[Dict(string(k)=>v for (k,v) in pairs(s)) for s in segments]
        c.source.build["args"]["editorial_version"]="revision2_20261024"
    end
    paths=regression_label_paths(seq,"a1_black_hole")
    c=regclip(seq,"a1_black_hole",2)
    for path in values(paths)
        VE.keyframes!(c,path,[(0,0.,:hold)])
    end
    for (name,i) in (("stars_caption",1),("disk_label",2),("horizon_mark",3),
        ("bending_caption",4),("far_side_label",5),("shadow_label",6),
        ("ring_label",7),("doppler_labels",8),("earth_caption",9))
        s=segments[i];regression_cue!(c,paths[name],(s.start+1)/fps,(s.stop-1)/fps)
    end
    regression_cue!(c,paths["straight_caption"],(segments[2].start+1)/fps,(segments[3].stop-1)/fps)
    VE.bindcacheparams!(c,VE.findslot(c,:scene));VE.bindinputs!(seq)
    return (;mapping,samples,segments)
end

function prepare_stripe_regression!(seq,before,parts)
    voice=Float32[];onsets=Float64[]
    for part in parts
        push!(onsets,length(voice)/24000);append!(voice,part)
        append!(voice,zeros(Float32,round(Int,0.55*24000)))
    end
    old=regclip(before,"b4_one_note",1);take=only(n for n in before.narration if n.anchor===old.source)
    oldline="Here's why. Light is a wave. From straight ahead, it reaches both telescopes together. From a slightly different direction, it travels farther to one telescope, shifting the two wiggles out of step."
    text=replace(take.text,oldline=>join(STRIPE_INTRO_PARTS," "))
    text!=take.text || error("Expected saved stripe sentence was not found")
    edit=replace_regression_line!(seq,before,"b4_one_note",2,voice,text;labels_changed=true)
    paths=regression_label_paths(seq,"b4_one_note";rekey=true)
    c=regclip(seq,"b4_one_note",2);s=edit.starts;e=edit.ends;fps=seq.framerate
    cue(name,on,off)=regression_cue!(c,paths[name],on,off)
    cue("receivers",s[2],s[5])
    cue("wavefronts",s[2]+onsets[2],s[5])
    cue("light_paths",s[2]+onsets[3],s[5])
    cue("recordings",s[2]+onsets[4],s[5])
    cue("delay_mark",s[2]+onsets[6],s[5])
    # First show identical paths/recordings. Only change direction AFTER that
    # representation is understood; expose the extra path at its spoken cue.
    VE.keyframes!(c,paths["source_angle"],[(0,0.,:linear),
        (round(Int,(s[2]+onsets[5])*fps),0.,:smooth),
        (round(Int,(s[2]+onsets[6]+0.8)*fps),asin(0.5/3),:linear),
        (round(Int,(s[3]+0.35*(e[3]-s[3]))*fps),asin(0.5/3),:smooth),
        (round(Int,(s[3]+0.75*(e[3]-s[3]))*fps),asin(1/3),:linear),
        (round(Int,s[5]*fps),asin(1/3),:linear)])
    VE.bindcacheparams!(c,VE.findslot(c,:scene));VE.bindinputs!(seq)
    return (;edit,onsets)
end

"Retain exact native footage/keys; ripple every later clip and cached composite."
function remap_regression_clip!(seq,before,beat,mapping;samples=nothing,text=nothing,labels_changed=false)
    picture=regclip(seq,beat,1);oldpic=regclip(before,beat,1)
    fps=seq.framerate;cut=VE.clipend(picture);extra=length(mapping)-VE.srclength(picture)
    shifted=[(n,VE.cachefile(seq.compositecache,0,n)) for n in cut:VE.seqlength(seq)-1 if VE.cachevalid(seq.compositecache,0,n)]
    for c in seq.clips
        c.start>=cut && (c.start+=extra)
    end
    # Source cache roots must be independent: callers clone the last saved
    # delivery first; `before` is always the immutable previous saved edition.
    for track in (1,2)
        c=regclip(seq,beat,track);old=regclip(before,beat,track)
        VE.invalidateclip!(c)
        c.source.nframes=length(mapping);c.src_in=0;c.src_out=length(mapping);c.rate=1.0
        c.source.build["args"]["duration"]=length(mapping)/fps
        filter!(p->p.input!==nothing,VE.findslot(c,:scene).params)
        for p in VE.findslot(old,:scene).params
            p.input===nothing || continue
            values=[VE.valueat(p.curve[],sf) for sf in mapping]
            all(v->v isa Real,values) || continue
            VE.keyframes!(c,String(p.name),[(n-1,v,:hold) for (n,v) in enumerate(values)];discrete=true)
        end
        c.source.root=VE.SceneProgram(c.source.build);c.source.live=nothing
        VE.bindcacheparams!(c,VE.findslot(c,:scene))
        if track==1 || !labels_changed
            @assert all(VE.cachevalid(VE.trackcache(old),old.id,sf) for sf in mapping)
            for (n,sf) in enumerate(mapping)
                VE.linkplane!(VE.trackcache(c),c.id,n-1,VE.cachefile(VE.trackcache(old),old.id,sf))
            end
        end
    end
    for (n,file) in sort(shifted;by=first,rev=extra>0)
        VE.linkplane!(seq.compositecache,UInt64(0),n+extra,file)
    end
    VE.invalidatecomposite!(seq,picture.start:VE.clipend(picture)-1)
    if !labels_changed
        for (n,sf) in enumerate(mapping)
            VE.linkplane!(seq.compositecache,UInt64(0),picture.start+n-1,
                VE.cachefile(before.compositecache,0,oldpic.start+sf))
        end
    end
    if samples!==nothing
        take=only(n for n in seq.narration if n.anchor===picture.source)
        empty!(take.samples);append!(take.samples,samples)
        length(take.samples)<=round(Int,length(mapping)/fps*take.rate) || error("Voice outside clip")
        text===nothing || (take.text=text)
    end
    VE.bindinputs!(seq)
    return picture
end

"Replace one recorded line, retaining every other approved sample and native plane."
function replace_regression_line!(seq,before,beat,line,voice,newtext;labels_changed=false)
    old=regclip(before,beat,1);args=old.source.build["args"];fps=seq.framerate
    take=only(n for n in before.narration if n.anchor===old.source)
    rate=take.rate;start=Float64(args["starts"][line]);stop=Float64(args["ends"][line])
    lo,hi=round(Int,start*fps),round(Int,stop*fps)
    frames=ceil(Int,length(voice)/rate*fps);delta=frames-(hi-lo)
    mapping=[collect(0:lo-1);[lo+min(hi-lo-1,fld(n*(hi-lo),frames)) for n in 0:frames-1];collect(hi:old.src_out-1)]
    # Splice at exact saved audio boundaries; pad only AFTER the new sentence.
    prefix=round(Int,start*rate);suffix=round(Int,stop*rate)+1
    wanted=(length(mapping)/fps)*rate
    # Build with an explicit initialized zero tail at the video-frame boundary.
    core=[take.samples[1:prefix];voice;zeros(Float32,max(0,round(Int,frames/fps*rate)-length(voice)));take.samples[suffix:end]]
    samples=zeros(Float32,round(Int,wanted));copyto!(samples,1,core,1,min(length(core),length(samples)))
    remap_regression_clip!(seq,before,beat,mapping;samples,text=newtext,labels_changed)
    starts=Float64.(args["starts"]);ends=Float64.(args["ends"])
    ends[line]=start+length(voice)/rate
    for i in line+1:length(starts)
        starts[i]+=delta/fps;ends[i]+=delta/fps
    end
    for track in (1,2)
        c=regclip(seq,beat,track)
        c.source.build["args"]["starts"]=starts;c.source.build["args"]["ends"]=ends
        c.source.root=VE.SceneProgram(c.source.build);c.source.live=nothing
    end
    return (;mapping,starts,ends,start,delta)
end

function review_regression_frames!(project,moments)
    VE.usebackend!(RayMakie)
    seq=VE.loadproject(project);engine=VE.FxEngine(Mantle.defaultbackend())
    readers=Dict{String,Any}();pixels=zeros(VE.RGB{VE.N0f8},seq.canvas...)
    dir=joinpath(dirname(project),"review");mkpath(dir);files=String[]
    try
        VE.withfinalscenes(seq) do
            for (beat,time,label) in moments
                picture=regclip(seq,beat,1);n=picture.start+round(Int,time*seq.framerate)
                0<=n-picture.start<VE.cliplength(picture) || error("Review outside $beat")
                # No accidental black-hole tracing is allowed, ever.
                beat=="a1_black_hole" && @assert VE.cachevalid(VE.trackcache(picture),picture.id,n-picture.start)
                for c in seq.clips
                    c.source.live===nothing || c.id in Set(q.id for q in VE.frameclips(seq,n)) || close(c.source)
                end
                VE.renderframe!(pixels,seq,n,readers,engine)
                file=joinpath(dir,label*".png");VE.PNGFiles.save(file,permutedims(pixels));push!(files,file)
                VE.saveproject(project,seq;checkpoint=false)
                println("CUE REVIEW ",label," ",file);flush(stdout)
            end
        end
    finally
        VE.emptyengine!(engine);foreach(close,values(readers))
        VE.saveproject(project,seq;checkpoint=false)
        foreach(c->c.source.live===nothing || close(c.source),seq.clips)
    end
    return files
end

"Export one explicitly bounded review excerpt; never export the full film."
function export_regression_excerpt!(project,beat;firstframe=0,lastframe=nothing,name=beat)
    VE.usebackend!(RayMakie)
    seq=VE.loadproject(project);picture=regclip(seq,beat,1)
    lastframe=something(lastframe,picture.src_out)
    0<=firstframe<lastframe<=picture.src_out || error("Invalid review bounds")
    if beat=="a1_black_hole"
        all(VE.cachevalid(VE.trackcache(picture),picture.id,sf) for sf in firstframe:lastframe-1) ||
            error("Refusing review: a black-hole picture would need raytracing")
    end
    fullcache=seq.compositecache
    fullstart=picture.start
    # Detach BEFORE changing placement: clip setters invalidate their owning
    # sequence's composites, and must not dirty the full-film receipts we reuse.
    seq.compositecache=VE.TrackCache(joinpath(dirname(project),"review",name*"_composite"))
    # Keep the native cache/source-frame addresses and anchored narration. Only
    # trim the timeline window; the ordinary audio mixer performs the same cut.
    filter!(c->c.source.build["args"]["beat"]==beat,seq.clips)
    filter!(n->n.anchor===picture.source,seq.narration)
    for c in seq.clips
        c.start=0;c.src_in=firstframe;c.src_out=lastframe
    end
    # Existing valid composites need only be encoded, not recomposited. Keep
    # their native receipts and shift only the bounded preview's frame address.
    for sf in firstframe:lastframe-1
        VE.cachevalid(fullcache,UInt64(0),fullstart+sf) || continue
        VE.linkplane!(seq.compositecache,UInt64(0),sf-firstframe,
            VE.cachefile(fullcache,UInt64(0),fullstart+sf))
    end
    movie=joinpath(dirname(project),"review",name*".mp4")
    try
        VE.exportvideo(movie,seq;encoder_options=(crf=18,preset="medium"),
            progress=(done,total)->(done%150==1 && (println("REVIEW ",name," ",done,"/",total);flush(stdout))))
        verify_continuous_movie(movie,lastframe-firstframe)
    finally
        whole=VE.loadproject(project)
        empty!(whole.trackcaches);merge!(whole.trackcaches,seq.trackcaches)
        adopt_regression_excerpt!(whole,beat,firstframe,lastframe,seq.compositecache)
        VE.saveproject(project,whole;checkpoint=false)
        foreach(c->c.source.live===nothing || close(c.source),seq.clips)
    end
    return movie
end

"Adopt real preview composites at their full-film timeline addresses."
function adopt_regression_excerpt!(seq,beat,firstframe,lastframe,preview)
    picture=regclip(seq,beat,1)
    for sf in firstframe:lastframe-1
        # Trust this run's native receipts, never leftover files from an older
        # excerpt (including after an interrupted export with different cuts).
        VE.cachevalid(preview,UInt64(0),sf-firstframe) || continue
        file=VE.cachefile(preview,UInt64(0),sf-firstframe)
        VE.linkplane!(seq.compositecache,UInt64(0),picture.start+sf,file)
    end
    return nothing
end
