# Include after project.jl and review_regressions.jl in the ROOT project.
using Test, LinearAlgebra

function test_review_regressions(project,before,original)
    seq=VE.loadproject(project)
    value(c,path,n)=VE.valueat(only(p for p in VE.findslot(c,:scene).params if String(p.name)==path).curve[],n)
    changed=Set(["a1_black_hole","b4_one_note","b5_earth_turns","b7_cleaning","c2_space"])
    @testset "Revision2 content and cache regression gate" begin
        @test seq.canvas==(1920,1080) && seq.framerate==30
        pictures=sort(filter(c->c.track==1,seq.clips);by=c->c.start)
        @test all(VE.clipend(a)==b.start for (a,b) in zip(pictures,pictures[2:end]))
        for c in pictures
            beat=c.source.build["args"]["beat"]
            labels=regclip(seq,beat,2)
            @test (c.start,c.src_in,c.src_out,c.rate)==(labels.start,labels.src_in,labels.src_out,labels.rate)
            beat in changed && continue
            old=regclip(before,beat,1)
            @test c.source.build==old.source.build
            nt=filter(n->n.anchor===c.source,seq.narration)
            ot=filter(n->n.anchor===old.source,before.narration)
            @test length(nt)==length(ot)
            @test all(a.samples==b.samples && a.text==b.text for (a,b) in zip(nt,ot))
            # ALL unchanged composites, not only midpoint examples, must be the
            # exact immutable delivered files despite the timeline ripple.
            @test all(VE.cachevalid(seq.compositecache,0,c.start+sf) &&
                Base.Filesystem.samefile(VE.cachefile(seq.compositecache,0,c.start+sf),
                    VE.cachefile(before.compositecache,0,old.start+sf)) for sf in 0:c.src_out-1)
        end
        pic=regclip(seq,"a1_black_hole",1);lab=regclip(seq,"a1_black_hole",2)
        old=regclip(original,"a1_black_hole",1)
        segments=pic.source.build["args"]["editorial_segments"]
        mapping=Int[]
        for s in segments
            n=s["stop"]-s["start"];lo=s["source_start"];hi=s["source_stop"]
            append!(mapping,[lo+fld(j*(hi-lo),n) for j in 0:n-1])
            @test 0.5<=s["rate"]<=0.85
        end
        @test length(mapping)==pic.src_out
        @test issorted(mapping)
        @test maximum(count(==(sf),mapping) for sf in unique(mapping))<=2
        @test all(VE.cachevalid(VE.trackcache(pic),pic.id,n-1) &&
            Base.Filesystem.samefile(VE.cachefile(VE.trackcache(pic),pic.id,n-1),
                VE.cachefile(VE.trackcache(old),old.id,sf)) for (n,sf) in enumerate(mapping))
        # Every cached picture retains the source camera, gas and GRMHD clock.
        for p in VE.findslot(old,:scene).params
            p.input===nothing || continue
            @test all(isequal(value(pic,String(p.name),n-1),VE.valueat(p.curve[],sf)) for (n,sf) in enumerate(mapping))
        end
        for i in (2,3), n in segments[i]["start"]:segments[i]["stop"]-1
            @test value(pic,"plasma_volume.lensing_strength",n)==0
            @test 345<=mapping[n+1]<=523
        end
        # Deliberate breaths (up to 1.5 s), with moving cached footage rather
        # than the old multi-second frozen-picture/silent holds.
        @test all(b["voice_start"]-a["voice_end"]<=1.5 for (a,b) in zip(segments,segments[2:end]))
        nt=only(n for n in seq.narration if n.anchor===pic.source)
        @test !occursin("disk of hot, glowing gas",first(split(nt.text,"This simulation")))
        @test occursin("Hot gas glows around the hole.",nt.text)
        earth=regclip(seq,"b5_earth_turns",1)
        hp=only(p for p in VE.findslot(earth,:scene).params if occursin("rotation",String(p.name)) || occursin("hour_angle",String(p.name)))
        delta=diff([VE.valueat(hp.curve[],n) for n in 0:earth.src_out-1])
        @test minimum(delta)>0
        @test maximum(delta)/minimum(delta)<1.0001
        stripe=regclip(seq,"b4_one_note",1)
        st=only(n for n in seq.narration if n.anchor===stripe.source)
        @test !occursin("Here's why",st.text)
        @test occursin("start with just two telescopes",st.text)
        # The seven short clauses must introduce their own visuals in order.
        stripe_labels=regclip(seq,"b4_one_note",2)
        t=stripe.source.build["args"]["starts"][2]
        @test value(stripe_labels,"poly_1.diagram",round(Int,(t+1)*30))>0.99
        @test value(stripe_labels,"lines_3.receivers",round(Int,(t+1)*30))>0.99
        @test value(stripe_labels,"lines_1.wavefronts",round(Int,(t+1)*30))==0
        @test value(stripe_labels,"lines_11.alpha",round(Int,(t+1)*30))==0
        @test value(stripe_labels,"lines_8.delay_mark",round(Int,(t+1)*30))==0
        @test value(stripe_labels,"lines_1.source_angle",round(Int,(t+10)*30))==0
        @test value(stripe_labels,"lines_1.source_angle",round(Int,(t+16)*30))>0
        # Closure repair is speech-only: no geometry/picture regeneration.
        closure=regclip(seq,"b7_cleaning",1)
        @test all(VE.cachevalid(VE.trackcache(closure),closure.id,n) for n in 0:closure.src_out-1)
        ct=only(n for n in seq.narration if n.anchor===closure.source)
        @test occursin("A",ct.text) && occursin("B",ct.text) && occursin("C",ct.text)
        @test all(n->all(isfinite,n.samples),seq.narration)
    end
    @testset "Native combined-control TextLabel visibility" begin
        film=loadfilm();P=VE.Performance
        latest(name,args...)=Base.invokelatest(Base.invokelatest(getproperty,film,name),args...)
        fig,a,paths=P.with(P.CONTEXT=>P.BuildContext(:labels,Dict{String,String}())) do
            fig,a=latest(:build_one_note,(1280,720))
            P.splitlayer!(fig.scene,:labels)
            fig,a,P.sceneattributes!(fig.scene,a).paths
        end
        try
            plots=P.namedplots(fig.scene)
            owner=only(p for p in plots if String(Makie.to_value(p.name))==first(split(paths["diagram"],'.')))
            labels=filter(p->Makie.to_value(p.name) in (:textlabel_1,:textlabel_2),plots)
            for (shown,diagram,reconstruction) in ((1f0,0f0,0f0),(1f0,1f0,0f0),(1f0,0.5f0,0f0),(1f0,0f0,1f0),(0f0,0f0,0f0))
                Makie.update!(owner;shown,diagram,reconstruction)
                @test all(Makie.to_value(p.text_alpha)≈shown*(1-diagram)*(1-reconstruction) for p in labels)
                @test all(Makie.to_value(p.alpha)≈shown*(1-diagram)*(1-reconstruction) for p in labels)
            end
        finally
            Makie.free(fig.scene)
        end
    end
    @testset "Native current notes move between observing bins" begin
        film=loadfilm();P=VE.Performance
        latest(name,args...)=Base.invokelatest(Base.invokelatest(getproperty,film,name),args...)
        fig,a,paths=P.with(P.CONTEXT=>P.BuildContext(:labels,Dict{String,String}())) do
            fig,a=latest(:build_earth_turns,(1280,720))
            fig,a,P.sceneattributes!(fig.scene,a).paths
        end
        try
            plots=P.namedplots(fig.scene)
            current=only(p for p in plots if p isa Makie.Scatter && Makie.to_value(p.strokewidth)==1.5)
            path=split(paths["hour_angle"],'.')
            owner=only(p for p in plots if String(Makie.to_value(p.name))==first(path))
            samples=[]
            for H in (0.4f0,0.4001f0)
                Makie.update!(owner;NamedTuple{(Symbol(last(path)),)}((H,))...)
                rows=latest(:night_notes)
                stations=Base.invokelatest(getproperty,film,:EHT)
                active=filter(unique((r[1],r[2]) for r in rows)) do pair
                    all(latest(:elevation,stations[i],H)>deg2rad(15) for i in pair)
                end
                expected=Makie.Point2f[]
                for (i,j) in active
                    u,v=latest(:uv,stations[i],stations[j],H)
                    push!(expected,Makie.Point2f(u/1e9,v/1e9),Makie.Point2f(-u/1e9,-v/1e9))
                end
                actual=copy(Makie.to_value(current[1]))
                @test !isempty(expected)
                @test actual≈expected
                push!(samples,actual)
            end
            @test length(samples[1])==length(samples[2])
            distances=[LinearAlgebra.norm(b-a) for (a,b) in zip(samples...)]
            @test any(>(0),distances) # zero baselines may legitimately stay put
            @test all(<(0.01),distances)
        finally
            Makie.free(fig.scene)
        end
    end
    nothing
end
