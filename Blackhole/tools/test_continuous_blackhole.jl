# Include after project.jl / continuous_blackhole_edit.jl in the ROOT project.
using Test

function test_continuous_blackhole(project,baseline,corrected,plan)
    seq=VE.loadproject(project);original=VE.loadproject(baseline);before=VE.loadproject(corrected)
    picture=bhclip(seq,1);labels=bhclip(seq,2);old=bhclip(original,1)
    oldbyid=Dict(c.id=>c for c in before.clips)
    @testset "Continuous native cached black-hole edit" begin
        @test seq.canvas==(1920,1080) && seq.framerate==30
        @test length(unique(plan.mapping))==VE.srclength(old)
        @test all(d->d in (0,1),diff(plan.mapping))
        @test maximum(count(==(sf),plan.mapping) for sf in unique(plan.mapping))<=2
        @test all(0.6<=s.rate<=0.9 for s in plan.segments)
        @test all(b.voice_start-a.voice_end<1.05 for (a,b) in zip(plan.segments,plan.segments[2:end]))
        @test picture.src_out==labels.src_out==length(plan.mapping)
        @test (picture.start,picture.src_in,picture.rate)==(labels.start,labels.src_in,labels.rate)
        take=only(n for n in seq.narration if n.anchor===picture.source)
        @test take.samples==plan.audio
        @test take.rate==24000
        @test take.text==join(BH_CONTINUOUS_LINES," ")
        @test all(isfinite,take.samples) && maximum(abs,take.samples)<=1
        @test length(take.samples)/take.rate==VE.srclength(picture)/seq.framerate
        # Camera, lensing, gas, Doppler and native GRMHD clock all remain EXACT
        # source-frame values. Overlay camera follows that same saved mapping.
        for p in VE.findslot(old,:scene).params
            p.input===nothing || continue
            new=only(q for q in VE.findslot(picture,:scene).params if q.name==p.name)
            @test all(isequal(VE.valueat(new.curve[],n-1),VE.valueat(p.curve[],sf)) for (n,sf) in enumerate(plan.mapping))
            if startswith(String(p.name),"camera.")
                label=only(q for q in VE.findslot(labels,:scene).params if q.name==p.name)
                @test all(isequal(VE.valueat(label.curve[],n-1),VE.valueat(p.curve[],sf)) for (n,sf) in enumerate(plan.mapping))
            end
        end
        lens=only(p for p in VE.findslot(picture,:scene).params if String(p.name)=="plasma_volume.lensing_strength")
        horizon=only(p for p in VE.findslot(labels,:scene).params if String(p.name)=="textlabel_1.text_alpha")
        @test all(VE.valueat(horizon.curve[],n)<=0 || VE.valueat(lens.curve[],n)==0 for n in 0:picture.src_out-1)
        shadow=only(p for p in VE.findslot(labels,:scene).params if String(p.name)=="textlabel_9.text_alpha")
        ring=only(p for p in VE.findslot(labels,:scene).params if String(p.name)=="textlabel_10.text_alpha")
        @test all(!(VE.valueat(shadow.curve[],n)>0 && VE.valueat(ring.curve[],n)>0) for n in 0:picture.src_out-1)
        for c in seq.clips
            c in (picture,labels) && continue
            oldclip=oldbyid[c.id]
            # A few unused label planes already lack a cache underneath valid
            # completed composites. Preserve their state; don't invent receipts.
            @test [VE.cachevalid(VE.trackcache(c),c.id,sf) for sf in c.src_in:c.src_out-1]==
                  [VE.cachevalid(VE.trackcache(oldclip),oldclip.id,sf) for sf in oldclip.src_in:oldclip.src_out-1]
            @test (c.src_in,c.src_out,c.rate,c.source.build)==(oldclip.src_in,oldclip.src_out,oldclip.rate,oldclip.source.build)
            oldtake=findfirst(n->n.anchor===oldclip.source,before.narration)
            if oldtake!==nothing
                newtake=only(n for n in seq.narration if n.anchor===c.source)
                @test newtake.samples==before.narration[oldtake].samples
            end
        end
        pictures=sort([c for c in seq.clips if c.track==1];by=c->c.start)
        @test all(VE.clipend(a)==b.start for (a,b) in zip(pictures,pictures[2:end]))
        for c in pictures
            c===picture && continue
            oldclip=oldbyid[c.id]
            for sf in unique([c.src_in,fld(c.src_in+c.src_out-1,2),c.src_out-1])
                n=c.start+sf-c.src_in
                previous=oldclip.start+sf-oldclip.src_in
                @test VE.cachevalid(seq.compositecache,0,n)
                @test Base.Filesystem.samefile(VE.cachefile(seq.compositecache,0,n),
                                               VE.cachefile(before.compositecache,0,previous))
            end
        end
        needed=VE.farmneededframes(seq)
        @test all(picture.start<=n<VE.clipend(picture) for n in needed)
        @test all(VE.cachevalid(VE.trackcache(picture),picture.id,sf) for sf in 0:picture.src_out-1)
    end
    nothing
end
