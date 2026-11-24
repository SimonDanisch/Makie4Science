# ROOT project; include after project.jl and review_regressions.jl.
using LinearAlgebra, Test

const BUILDUP_LINES=[
    "Everything with mass bends the path of light a little. A black hole forms when matter is packed so densely that nothing can escape its gravity, not even light. To understand how it looks, let's first switch that bending off.",
    "Gas falling towards a black hole heats up into glowing plasma. This glow is what we see, not the black hole itself.",
    "This dark sphere marks the event horizon. Whatever crosses it can never come back out.",
    "Now slowly turn on light bending. Watch how gravity changes the paths that light takes to reach us.",
]

"Revise the first explanation using the already rendered staged opening."
function explain_buildup!(seq,before,voices)
    old=regclip(before,"a1_black_hole",1)
    prior=old.source.build["args"]["editorial_segments"]
    take=only(n for n in before.narration if n.anchor===old.source)
    fps=seq.framerate;@assert fps==30 && take.rate==24000
    mapping=Int[];samples=Float32[];segments=Dict{String,Any}[]
    for i in 1:2
        s=prior[i];lo,hi=Int(s["start"]),Int(s["stop"])
        # Natural voice plus an explicit lead and breathing room; never speed
        # up narration to fit the earlier, inadequate sentence's duration.
        n=max(hi-lo,ceil(Int,(length(voices[i])/24000+1.1)*fps))
        n<=2*(hi-lo) || error("Opening needs more motion frames, not frozen holds in stage $i")
        start=length(mapping)
        append!(mapping,[lo+fld(j*(hi-lo),n) for j in 0:n-1])
        append!(samples,zeros(Float32,6000));append!(samples,voices[i])
        append!(samples,zeros(Float32,n*800-6000-length(voices[i])))
        push!(segments,Dict("index"=>i,"start"=>start,"stop"=>length(mapping),
            "voice_start"=>start/fps+0.25,
            "voice_end"=>start/fps+0.25+length(voices[i])/24000,
            "new_trace"=>false))
    end
    oldtail=Int(prior[3]["start"]);newtail=length(mapping);delta=newtail-oldtail
    append!(mapping,oldtail:old.src_out-1)
    append!(samples,take.samples[oldtail*800+1:end])
    for s in prior[3:end]
        t=Dict{String,Any}(s)
        for k in ("start","stop");t[k]=Int(t[k])+delta;end
        for k in ("voice_start","voice_end");t[k]=Float64(t[k])+delta/fps;end
        t["new_trace"]=false;push!(segments,t)
    end
    text=join([BUILDUP_LINES;BH_CONTINUOUS_LINES[5:end]]," ")
    remap_regression_clip!(seq,before,"a1_black_hole",mapping;samples,text,labels_changed=false)
    for track in (1,2)
        c=regclip(seq,"a1_black_hole",track)
        c.source.build["args"]["editorial_segments"]=deepcopy(segments)
        c.source.build["args"]["editorial_version"]="buildup_explained_20261025"
        c.source.root=VE.SceneProgram(c.source.build);c.source.live=nothing
    end
    VE.bindinputs!(seq)
    return (;mapping,segments,oldtail,newtail,delta)
end

function test_explained_buildup(seq,before,plan,voices)
    pic=regclip(seq,"a1_black_hole",1);old=regclip(before,"a1_black_hole",1)
    value(c,path,n)=VE.valueat(only(p for p in VE.findslot(c,:scene).params if String(p.name)==path).curve[],n)
    take=only(n for n in seq.narration if n.anchor===pic.source)
    prior=only(n for n in before.narration if n.anchor===old.source)
    @testset "Context before gas; natural speech; no rerender or unrelated change" begin
        @test take.text==join([BUILDUP_LINES;BH_CONTINUOUS_LINES[5:end]]," ")
        @test !occursin("Now add",take.text) && !occursin("traps even light",take.text)
        for i in 1:2
            s=plan.segments[i]
            @test s["voice_start"]==s["start"]/30+0.25
            @test s["stop"]/30-s["voice_end"]>=0.85-1e-8
            onset=round(Int,s["voice_start"]*24000)
            @test take.samples[onset+1:onset+length(voices[i])]==voices[i]
        end
        @test take.samples[plan.newtail*800+1:end]==prior.samples[plan.oldtail*800+1:end]
        @test all(count(==(sf),plan.mapping)<=2 for sf in unique(plan.mapping))
        for (n,sf) in enumerate(plan.mapping)
            @test Base.Filesystem.samefile(VE.cachefile(seq.compositecache,0,pic.start+n-1),VE.cachefile(before.compositecache,0,old.start+sf))
            for track in (1,2)
                c=regclip(seq,"a1_black_hole",track);o=regclip(before,"a1_black_hole",track)
                @test VE.cachevalid(VE.trackcache(c),c.id,n-1)
                @test Base.Filesystem.samefile(VE.cachefile(VE.trackcache(c),c.id,n-1),VE.cachefile(VE.trackcache(o),o.id,sf))
                @test all(value(c,String(p.name),n-1)==VE.valueat(p.curve[],sf)
                    for p in VE.findslot(o,:scene).params if p.input===nothing && VE.valueat(p.curve[],sf) isa Real)
            end
        end
        gas=[value(pic,"plasma_volume.gas_scale",n) for n in 0:pic.src_out-1]
        lens=[value(pic,"plasma_volume.lensing_strength",n) for n in 0:pic.src_out-1]
        @test all(==(0),gas[1:plan.segments[1]["stop"]])
        @test all(==(0),lens[1:plan.segments[3]["stop"]])
        @test all(g==1 for (g,l) in zip(gas,lens) if l>0)
        for c in seq.clips
            beat=c.source.build["args"]["beat"];beat=="a1_black_hole" && continue
            o=regclip(before,beat,c.track)
            @test c.source.build==o.source.build && c.src_out==o.src_out
            @test c.start==o.start+(o.start>=VE.clipend(old) ? plan.delta : 0)
            @test all(VE.cachevalid(seq.compositecache,0,c.start+sf) &&
                Base.Filesystem.samefile(VE.cachefile(seq.compositecache,0,c.start+sf),VE.cachefile(before.compositecache,0,o.start+sf)) for sf in 0:c.src_out-1)
            if c.track==1
                nt=filter(n->n.anchor===c.source,seq.narration);ot=filter(n->n.anchor===o.source,before.narration)
                @test length(nt)==length(ot) && all(a.samples==b.samples for (a,b) in zip(nt,ot))
            end
        end
        @test isempty(VE.farmneededframes(seq))
    end
end

function prepare_buildup!(seq,before,voices)
    old=regclip(before,"a1_black_hole",1);fps=seq.framerate
    take=only(n for n in before.narration if n.anchor===old.source)
    @assert fps==30 && take.rate==24000
    prior=old.source.build["args"]["editorial_segments"]
    ranges=[(0,327),(327,409),(409,655),(655,760)]
    counts=[ceil(Int,(length(voices[1])/24000+1)*fps),
        max(150,ceil(Int,(length(voices[2])/24000+1)*fps)),246,
        max(180,ceil(Int,(length(voices[3])/24000+1)*fps))]
    mapping=Int[];samples=Float32[];segments=Dict{String,Any}[]
    for i in 1:4
        lo,hi=ranges[i];n=counts[i];start=length(mapping)
        append!(mapping,[lo+fld(j*(hi-lo),n) for j in 0:n-1])
        if i==3
            append!(samples,take.samples[lo*800+1:hi*800])
            vs,ve=prior[3]["voice_start"]-lo/fps,prior[3]["voice_end"]-lo/fps
        else
            voice=voices[i==4 ? 3 : i];vs=0.25;ve=vs+length(voice)/24000
            append!(samples,zeros(Float32,6000));append!(samples,voice)
            append!(samples,zeros(Float32,n*800-6000-length(voice)))
        end
        push!(segments,Dict("index"=>i,"start"=>start,"stop"=>length(mapping),
            "voice_start"=>start/fps+vs,"voice_end"=>start/fps+ve,"new_trace"=>i!=3))
    end
    prefix=length(mapping);append!(mapping,760:old.src_out-1)
    append!(samples,take.samples[760*800+1:end])
    delta=prefix-760
    for s in prior[5:end]
        t=Dict{String,Any}(s)
        for k in ("start","stop");t[k]=Int(t[k])+delta;end
        for k in ("voice_start","voice_end");t[k]=Float64(t[k])+delta/fps;end
        t["new_trace"]=false;push!(segments,t)
    end
    text=join([BUILDUP_LINES;BH_CONTINUOUS_LINES[5:end]]," ")
    remap_regression_clip!(seq,before,"a1_black_hole",mapping;samples,text,labels_changed=true)
    pic=regclip(seq,"a1_black_hole",1);lab=regclip(seq,"a1_black_hole",2)
    val(path,n)=VE.valueat(only(p for p in VE.findslot(old,:scene).params if String(p.name)==path).curve[],n)
    smooth(u)=begin x=clamp(u,0.,1.);x*x*(3-2x) end
    newframes=BitSet([collect(0:sum(counts[1:2])-1);collect(sum(counts[1:3]):prefix-1)])
    # Match the unchanged horizon footage and the later lensed footage exactly.
    # Interpolate spherical camera coordinates, never a chord through the hole.
    for (newlo,newhi,oldlo,oldhi) in ((0,sum(counts[1:2]),0,409),
            (sum(counts[1:3]),prefix,655,760))
        p0=[val("camera.eye[$k]",oldlo) for k in 1:3]
        p1=[val("camera.eye[$k]",oldhi) for k in 1:3]
        r0,r1=norm(p0),norm(p1);az0,az1=atan(p0[2],p0[1]),atan(p1[2],p1[1])
        az1=az0+mod(az1-az0+pi,2pi)-pi
        el0,el1=asin(p0[3]/r0),asin(p1[3]/r1)
        for track in (1,2)
            c=regclip(seq,"a1_black_hole",track)
            for k in 1:3
                p=only(p for p in VE.findslot(c,:scene).params if String(p.name)=="camera.eye[$k]")
                values=[VE.valueat(p.curve[],n) for n in 0:c.src_out-1]
                for n in newlo:newhi-1
                    u=(n-newlo)/(newhi-newlo);v=smooth(u)
                    az=az0+(az1-az0)*u;el=el0+(el1-el0)*v;r=r0+(r1-r0)*v
                    values[n+1]=(r*cos(el)*cos(az),r*cos(el)*sin(az),r*sin(el))[k]
                end
                VE.keyframes!(c,"camera.eye[$k]",[(n-1,v,:hold) for (n,v) in enumerate(values)];discrete=true)
            end
        end
        p=only(p for p in VE.findslot(pic,:scene).params if p.name==:plasma_time)
        times=[VE.valueat(p.curve[],n) for n in 0:pic.src_out-1]
        for n in newlo:newhi-1
            times[n+1]=val("plasma_time",oldlo)+(val("plasma_time",oldhi)-val("plasma_time",oldlo))*(n-newlo)/(newhi-newlo)
        end
        VE.keyframes!(pic,"plasma_time",[(n-1,v,:hold) for (n,v) in enumerate(times)];discrete=true)
    end
    for path in ("plasma_volume.gas_scale","plasma_volume.lensing_strength")
        p=only(p for p in VE.findslot(pic,:scene).params if String(p.name)==path)
        values=[VE.valueat(p.curve[],n) for n in 0:pic.src_out-1]
        for n in 0:prefix-1
            values[n+1]=path=="plasma_volume.gas_scale" ?
                smooth((n-counts[1])/(counts[2]-1)) :
                smooth((n-sum(counts[1:3]))/(counts[4]-1))
        end
        VE.keyframes!(pic,path,[(n-1,v,:hold) for (n,v) in enumerate(values)];discrete=true)
    end
    paths=regression_label_paths(seq,"a1_black_hole")
    for name in ("stars_caption","disk_label","horizon_mark","straight_caption","bending_caption")
        VE.keyframes!(lab,paths[name],[(0,0.,:hold)])
    end
    for (name,i) in (("disk_label",2),("horizon_mark",3),("bending_caption",4))
        s=segments[i];regression_cue!(lab,paths[name],(s["start"]+1)/fps,(s["stop"]-1)/fps)
    end
    regression_cue!(lab,paths["straight_caption"],1/fps,(segments[3]["stop"]-1)/fps)
    for c in (pic,lab)
        c.source.build["args"]["editorial_segments"]=segments
        c.source.build["args"]["editorial_version"]="buildup_20261025"
        VE.bindcacheparams!(c,VE.findslot(c,:scene))
    end
    # Reuse ONLY genuine unchanged planes/composites. New medium/camera states
    # must never borrow a cached picture just because the frame number matches.
    for n in 0:pic.src_out-1
        if n in newframes
            VE.dirtyframes!(VE.trackcache(pic),pic.id,[n])
            continue
        end
        sf=mapping[n+1]
        for track in (1,2)
            c=regclip(seq,"a1_black_hole",track);o=regclip(before,"a1_black_hole",track)
            VE.cachevalid(VE.trackcache(o),o.id,sf) && VE.linkplane!(VE.trackcache(c),c.id,n,VE.cachefile(VE.trackcache(o),o.id,sf))
        end
        VE.linkplane!(seq.compositecache,UInt64(0),pic.start+n,VE.cachefile(before.compositecache,0,old.start+sf))
    end
    VE.bindinputs!(seq)
    return (;prefix,counts,mapping,newframes,segments)
end

function test_buildup(seq,before,plan;rendered=false)
    pic=regclip(seq,"a1_black_hole",1);lab=regclip(seq,"a1_black_hole",2)
    val(c,path,n)=VE.valueat(only(p for p in VE.findslot(c,:scene).params if String(p.name)==path).curve[],n)
    @testset "Dark silhouette → gas → lensing; exact unchanged-cache reuse" begin
        gas=[val(pic,"plasma_volume.gas_scale",n) for n in 0:plan.prefix-1]
        lens=[val(pic,"plasma_volume.lensing_strength",n) for n in 0:plan.prefix-1]
        @test all(==(0),gas[1:plan.counts[1]])
        @test all(==(0),lens[1:sum(plan.counts[1:3])])
        @test all(diff(gas).>=0) && all(diff(lens).>=0)
        @test maximum(diff(gas))<0.012 && maximum(diff(lens))<0.012
        @test all(g==1 for (g,b) in zip(gas,lens) if b>0)
        @test length(unique(gas))>100 && length(unique(lens))>100
        @test gas[end]==lens[end]==1
        eyes=[[val(pic,"camera.eye[$k]",n) for k in 1:3] for n in 0:plan.prefix]
        @test maximum(norm(b-a) for (a,b) in zip(eyes,eyes[2:end]))<0.3
        @test all(VE.cachevalid(VE.trackcache(pic),pic.id,n)==rendered for n in plan.newframes)
        take=only(n for n in seq.narration if n.anchor===pic.source)
        oldpic=regclip(before,"a1_black_hole",1)
        oldtake=only(n for n in before.narration if n.anchor===oldpic.source)
        @test take.samples[plan.prefix*800+1:end]==oldtake.samples[760*800+1:end]
        for c in seq.clips
            beat=c.source.build["args"]["beat"];beat=="a1_black_hole" && continue
            o=regclip(before,beat,c.track)
            @test c.source.build==o.source.build
            @test c.src_out==o.src_out
            @test all(VE.cachevalid(seq.compositecache,0,c.start+sf) &&
                Base.Filesystem.samefile(VE.cachefile(seq.compositecache,0,c.start+sf),
                    VE.cachefile(before.compositecache,0,o.start+sf)) for sf in 0:c.src_out-1)
            if c.track==1
                nt=filter(n->n.anchor===c.source,seq.narration)
                ot=filter(n->n.anchor===o.source,before.narration)
                @test all(a.samples==b.samples for (a,b) in zip(nt,ot))
            end
        end
        for n in 0:pic.src_out-1
            n in plan.newframes && continue
            sf=plan.mapping[n+1];o=regclip(before,"a1_black_hole",1)
            @test Base.Filesystem.samefile(VE.cachefile(VE.trackcache(pic),pic.id,n),VE.cachefile(VE.trackcache(o),o.id,sf))
            @test all(val(pic,"camera.eye[$k]",n)==val(lab,"camera.eye[$k]",n) for k in 1:3)
            @test all(val(pic,String(p.name),n)==VE.valueat(p.curve[],sf)
                for p in VE.findslot(o,:scene).params if p.input===nothing)
        end
        @test all(VE.frameclips(seq,n)[1].source.build["args"]["beat"]=="a1_black_hole" for n in VE.farmneededframes(seq))
    end
end

"Old frames where `clip` shows a new picture state, with those states."
function native_states(clip,names)
    curves=[only(p for p in VE.findslot(clip,:scene).params if String(p.name)==name).curve[] for name in names]
    frames=Int[];states=Vector{Any}[]
    for n in 0:VE.srclength(clip)-1
        s=Any[VE.valueat(c,n) for c in curves]
        (isempty(states) || s!=states[end]) && (push!(frames,n);push!(states,s))
    end
    return frames,states
end

"Cubic Hermite time warp on [0,1] with end slopes `m0`, `m1` (1 = constant rate)."
hermite_warp(u,m0,m1)=(u^3-2u^2+u)*m0+(3u^2-2u^3)+(u^3-u^2)*m1

"Camera position between two orbit samples: radius, azimuth and elevation, never a chord."
function orbit_lerp(p0,p1,t)
    t==0 && return p0
    r0,r1=norm(p0),norm(p1);az0,az1=atan(p0[2],p0[1]),atan(p1[2],p1[1])
    az1=az0+mod(az1-az0+pi,2pi)-pi
    el0,el1=asin(p0[3]/r0),asin(p1[3]/r1)
    r,az,el=r0+(r1-r0)*t,az0+(az1-az0)*t,el0+(el1-el0)*t
    return [r*cos(el)*cos(az),r*cos(el)*sin(az),r*sin(el)]
end

"""
Plan a true 30 fps re-time of the black-hole explanation. Segment `k` advances
through its rendered picture states at an eased rate; `keep` segments already
show one new state per frame and stay unchanged. Each output frame is
`(a, b, t)`: the state between old frames `a` and `b`, `t=0` meaning exactly `a`.
"""
function smooth_plan(old,counts;keep=(4,))
    prior=old.source.build["args"]["editorial_segments"]
    names=[String(p.name) for p in VE.findslot(old,:scene).params if p.input===nothing]
    frames,states=native_states(old,names);M=length(frames)
    owner(n)=searchsortedlast(frames,n)
    K=length(prior);a=[owner(Int(s["start"])) for s in prior]
    span=[k<K ? a[k+1]-a[k] : M-a[k] for k in 1:K]
    denom=[k<K ? counts[k] : counts[k]-1 for k in 1:K]
    rate=span./denom
    for k in keep
        rate[k]==1 && counts[k]==Int(prior[k]["stop"])-Int(prior[k]["start"]) || error("Segment $k is not an unchanged 30 fps segment")
    end
    edge(k)=k==1 ? rate[1] : k==K+1 ? rate[K] : k in keep ? rate[k] : k-1 in keep ? rate[k-1] : (rate[k-1]+rate[k])/2
    blend=Tuple{Int,Int,Float64}[];positions=Float64[]
    for k in 1:K
        m0,m1=k in keep ? (1.0,1.0) : (edge(k)/rate[k],edge(k+1)/rate[k])
        0<m0<=3 && 0<m1<=3 || error("Segment $k needs a non-monotone warp ($m0, $m1)")
        for j in 0:counts[k]-1
            x=a[k]+span[k]*hermite_warp(j/denom[k],m0,m1)
            abs(x-round(x))<1e-6 && (x=round(x))
            i=clamp(floor(Int,x),1,M);t=x-i
            push!(positions,x);push!(blend,t==0 ? (frames[i],frames[i],0.0) : (frames[i],frames[i+1],t))
        end
    end
    all(>(0),diff(positions)) || error("Re-timed states must advance every frame")
    return (;blend,positions,rate,states=M)
end

"Retain exact native pictures where a frame lands on one; key in-between states elsewhere."
function blend_regression_clip!(seq,before,beat,blend;samples,text)
    picture=regclip(seq,beat,1);fps=seq.framerate
    cut=VE.clipend(picture);extra=length(blend)-VE.srclength(picture)
    shifted=[(n,VE.cachefile(seq.compositecache,0,n)) for n in cut:VE.seqlength(seq)-1 if VE.cachevalid(seq.compositecache,0,n)]
    for c in seq.clips
        c.start>=cut && (c.start+=extra)
    end
    lerp(x,y,t)=t==0 ? x : x+(y-x)*t
    for track in (1,2)
        c=regclip(seq,beat,track);old=regclip(before,beat,track)
        VE.invalidateclip!(c)
        c.source.nframes=length(blend);c.src_in=0;c.src_out=length(blend);c.rate=1.0
        c.source.build["args"]["duration"]=length(blend)/fps
        filter!(p->p.input!==nothing,VE.findslot(c,:scene).params)
        curves=Dict(String(p.name)=>p.curve[] for p in VE.findslot(old,:scene).params if p.input===nothing)
        eye(n)=[VE.valueat(curves["camera.eye[$k]"],n) for k in 1:3]
        eyes=[orbit_lerp(eye(a),eye(b),t) for (a,b,t) in blend]
        for (name,curve) in curves
            values=startswith(name,"camera.eye[") ? [e[parse(Int,name[end-1])] for e in eyes] :
                [lerp(VE.valueat(curve,a),VE.valueat(curve,b),t) for (a,b,t) in blend]
            VE.keyframes!(c,name,[(n-1,v,:hold) for (n,v) in enumerate(values)];discrete=true)
        end
        c.source.root=VE.SceneProgram(c.source.build);c.source.live=nothing
        VE.bindcacheparams!(c,VE.findslot(c,:scene))
    end
    old=regclip(before,beat,1)
    for (n,(a,_,t)) in enumerate(blend)
        t==0 && VE.linkplane!(VE.trackcache(picture),picture.id,n-1,VE.cachefile(VE.trackcache(old),old.id,a))
    end
    for (n,file) in sort(shifted;by=first,rev=extra>0)
        VE.linkplane!(seq.compositecache,UInt64(0),n+extra,file)
    end
    VE.invalidatecomposite!(seq,picture.start:VE.clipend(picture)-1)
    take=only(n for n in seq.narration if n.anchor===picture.source)
    empty!(take.samples);append!(take.samples,samples);take.text=text
    length(take.samples)<=round(Int,length(blend)/fps*take.rate) || error("Voice outside clip")
    VE.bindinputs!(seq)
    return picture
end

"Re-time the explanation at a true 30 fps with the revised first three lines."
function smooth_buildup!(seq,before,voices;tails=(0.85,0.85,1.25),lead=0.25)
    old=regclip(before,"a1_black_hole",1);fps=seq.framerate
    take=only(n for n in before.narration if n.anchor===old.source)
    @assert fps==30 && take.rate==24000
    prior=old.source.build["args"]["editorial_segments"]
    names=[String(p.name) for p in VE.findslot(old,:scene).params if p.input===nothing]
    frames,_=native_states(old,names);owner(n)=searchsortedlast(frames,n)
    counts=[Int(s["stop"])-Int(s["start"]) for s in prior]
    for i in 1:3
        # Natural voice, lead and breathing room; never faster than rendered.
        steps=owner(Int(prior[i+1]["start"]))-owner(Int(prior[i]["start"]))
        counts[i]=max(steps,ceil(Int,(length(voices[i])/24000+lead+tails[i])*fps))
    end
    plan=smooth_plan(old,counts)
    samples=Float32[];segments=Dict{String,Any}[];start=0
    for (i,s) in enumerate(prior)
        t=Dict{String,Any}(s);t["start"]=start;t["stop"]=start+counts[i]
        if i<=3
            append!(samples,zeros(Float32,round(Int,lead*24000)));append!(samples,voices[i])
            append!(samples,zeros(Float32,counts[i]*800-round(Int,lead*24000)-length(voices[i])))
            t["voice_start"]=start/fps+lead;t["voice_end"]=start/fps+lead+length(voices[i])/24000
        else
            shift=(start-Int(s["start"]))/fps
            t["voice_start"]=Float64(s["voice_start"])+shift;t["voice_end"]=Float64(s["voice_end"])+shift
        end
        t["native_rate"]=plan.rate[i];t["new_trace"]=i!=4
        push!(segments,t);start+=counts[i]
    end
    append!(samples,take.samples[Int(prior[4]["start"])*800+1:end])
    text=join([BUILDUP_LINES;BH_CONTINUOUS_LINES[5:end]]," ")
    blend_regression_clip!(seq,before,"a1_black_hole",plan.blend;samples,text)
    pic=regclip(seq,"a1_black_hole",1);lab=regclip(seq,"a1_black_hole",2)
    paths=regression_label_paths(seq,"a1_black_hole")
    for path in values(paths)
        VE.keyframes!(lab,path,[(0,0.,:hold)])
    end
    for (name,i) in (("disk_label",2),("horizon_mark",3),("bending_caption",4),("far_side_label",5),
            ("shadow_label",6),("ring_label",7),("doppler_labels",8),("earth_caption",9))
        s=segments[i];regression_cue!(lab,paths[name],(s["start"]+1)/fps,(s["stop"]-1)/fps)
    end
    regression_cue!(lab,paths["straight_caption"],1/fps,(segments[3]["stop"]-1)/fps)
    for c in (pic,lab)
        c.source.build["args"]["editorial_segments"]=deepcopy(segments)
        c.source.build["args"]["editorial_version"]="smooth_30fps_20261025"
        c.source.root=VE.SceneProgram(c.source.build);c.source.live=nothing
        VE.bindcacheparams!(c,VE.findslot(c,:scene))
    end
    # Exact native states keep their labels and composites only if the labels
    # are unchanged too; everything else is composed again from its planes.
    oldlab=regclip(before,"a1_black_hole",2)
    labelvalues(c,n)=[VE.valueat(p.curve[],n) for p in sort(filter(p->p.input===nothing,VE.findslot(c,:scene).params);by=p->p.name)]
    reused=0
    for (n,(a,_,t)) in enumerate(plan.blend)
        t==0 && labelvalues(lab,n-1)==labelvalues(oldlab,a) || continue
        VE.linkplane!(VE.trackcache(lab),lab.id,n-1,VE.cachefile(VE.trackcache(oldlab),oldlab.id,a))
        VE.linkplane!(seq.compositecache,UInt64(0),pic.start+n-1,VE.cachefile(before.compositecache,0,old.start+a))
        reused+=1
    end
    VE.bindinputs!(seq)
    return (;plan...,counts,segments,reused)
end

function test_smooth_buildup(seq,before,plan,voices;rendered=false)
    pic=regclip(seq,"a1_black_hole",1);lab=regclip(seq,"a1_black_hole",2)
    old=regclip(before,"a1_black_hole",1);oldlab=regclip(before,"a1_black_hole",2)
    value(c,path,n)=VE.valueat(only(p for p in VE.findslot(c,:scene).params if String(p.name)==path).curve[],n)
    names=[String(p.name) for p in VE.findslot(old,:scene).params if p.input===nothing]
    take=only(n for n in seq.narration if n.anchor===pic.source)
    prior=only(n for n in before.narration if n.anchor===old.source)
    seg=plan.segments;oldseg=old.source.build["args"]["editorial_segments"]
    N=VE.srclength(pic)
    @testset "True 30 fps explanation: a new state every frame, unchanged rest" begin
        states=[Any[value(pic,nm,n) for nm in names] for n in 0:N-1]
        @test all(states[i]!=states[i-1] for i in 2:N)
        steps=diff(plan.positions)
        @test all(>(0),steps) && maximum(abs.(diff(steps))./steps[1:end-1])<0.02
        eyes=[[value(pic,"camera.eye[$k]",n) for k in 1:3] for n in 0:N-1]
        @test maximum(norm(b-a) for (a,b) in zip(eyes,eyes[2:end]))<0.3
        @test all(eyes[n+1]==[value(lab,"camera.eye[$k]",n) for k in 1:3] for n in 0:N-1)
        gas=[value(pic,"plasma_volume.gas_scale",n) for n in 0:N-1]
        lens=[value(pic,"plasma_volume.lensing_strength",n) for n in 0:N-1]
        @test all(==(0),gas[1:seg[1]["stop"]]) && all(==(0),lens[1:seg[3]["stop"]])
        @test all(g==1 for (g,l) in zip(gas,lens) if l>0) && gas[end]==lens[end]==1
        @test issorted(gas[1:seg[3]["stop"]]) && issorted(lens[1:seg[4]["stop"]])
        # Exact rendered states only: shared pictures carry identical parameters.
        for (n,(a,b,t)) in enumerate(plan.blend)
            if t==0
                @test states[n]==Any[value(old,nm,a) for nm in names]
                @test samefile(VE.cachefile(VE.trackcache(pic),pic.id,n-1),VE.cachefile(VE.trackcache(old),old.id,a))
            else
                @test b>a && 0<t<1
                @test VE.cachevalid(VE.trackcache(pic),pic.id,n-1)==rendered
            end
        end
        # The already true-30 fps bending segment reuses every picture unchanged.
        for n in seg[4]["start"]:seg[4]["stop"]-1
            o=Int(oldseg[4]["start"])+n-seg[4]["start"]
            @test samefile(VE.cachefile(VE.trackcache(pic),pic.id,n),VE.cachefile(VE.trackcache(old),old.id,o))
        end
        # Later labels keep their exact cue values; only their frame address moved.
        # (Read paths from the keyed parameters: regression_label_paths invalidates.)
        labelpaths=[String(p.name) for p in VE.findslot(lab,:scene).params if startswith(String(p.name),"textlabel")]
        for i in 4:9, path in labelpaths
            lo=seg[i]["start"];olo=Int(oldseg[i]["start"])
            @test all(value(lab,path,lo+j)==value(oldlab,path,olo+j) for j in 0:seg[i]["stop"]-lo-1)
        end
        @test take.text==join([BUILDUP_LINES;BH_CONTINUOUS_LINES[5:end]]," ")
        for i in 1:3
            onset=round(Int,seg[i]["voice_start"]*24000)
            @test take.samples[onset+1:onset+length(voices[i])]==voices[i]
            @test seg[i]["stop"]/30-seg[i]["voice_end"]>=0.85-1e-8
            @test all(iszero,take.samples[seg[i]["start"]*800+1:onset])
        end
        @test take.samples[seg[4]["start"]*800+1:end]==prior.samples[Int(oldseg[4]["start"])*800+1:end]
        delta=N-VE.srclength(old)
        for c in seq.clips
            beat=c.source.build["args"]["beat"];beat=="a1_black_hole" && continue
            o=regclip(before,beat,c.track)
            @test c.source.build==o.source.build && c.src_out==o.src_out
            @test c.start==o.start+(o.start>=VE.clipend(old) ? delta : 0)
            @test all(VE.cachevalid(seq.compositecache,0,c.start+sf) &&
                samefile(VE.cachefile(seq.compositecache,0,c.start+sf),VE.cachefile(before.compositecache,0,o.start+sf)) for sf in 0:c.src_out-1)
            if c.track==1
                nt=filter(n->n.anchor===c.source,seq.narration);ot=filter(n->n.anchor===o.source,before.narration)
                @test length(nt)==length(ot) && all(a.samples==b.samples for (a,b) in zip(nt,ot))
            end
        end
        need=sort(collect(VE.farmneededframes(seq)))
        @test need==(rendered ? Int[] : [pic.start+n-1 for (n,(_,_,t)) in enumerate(plan.blend) if t!=0])
    end
end
