# After project.jl, in the one application root. Checks the actual saved edit.
using Test
function test_final_edit(project; voice_root=joinpath(@__DIR__,"..","voice_v6"))
    seq=VE.loadproject(project)
    pictures=sort(filter(c->c.track==1,seq.clips);by=c->c.start)
    @testset "complete final edit, narration and quality" begin
        @test seq.canvas==(1280,720)
        @test seq.framerate==30
        @test first(pictures).start==0
        @test all(VE.clipend(a)==b.start for (a,b) in zip(pictures,pictures[2:end]))
        @test length(pictures)==length(BEATS)+1
        for (name,lines) in BEATS
            picture=only(filter(c->get(c.source.build["args"],"beat","")==name,pictures))
            labels=only(filter(c->c.track==2 && get(c.source.build["args"],"beat","")==name,seq.clips))
            @test (picture.start,picture.src_in,picture.src_out)==(labels.start,labels.src_in,labels.src_out)
            take=only(filter(n->n.anchor===picture.source,seq.narration))
            @test take.text==join(plain.(lines)," ")
            @test !isempty(take.samples) && all(isfinite,take.samples)
            @test take.samples==read_voice(name;root=voice_root)
            fingerprint=parse(UInt64,first(readlines(joinpath(voice_root,name*".timing"))))
            # The legacy sharpness/voice! cache includes synthesis settings;
            # voice_en_v6 records the script hash alone. Both are in this film.
            @test fingerprint in (hash(lines),hash((lines,0.45f0,"af_heart",0.95,0.8f0,1.5f0)))
            @test length(take.samples)/take.rate<=VE.cliplength(picture)/seq.framerate+1/seq.framerate
        end
        for name in ("a1_black_hole","a2_two_numbers")
            c=only(filter(c->get(c.source.build["args"],"beat","")==name,pictures))
            # The plasma is sampled on the simulation's own grid.
            @test all(ref.loader==:native_radiative_volume && ref.options["normalization"]==1.1162966f-20
                      for fx in c.effects for p in fx.params if p.input!==nothing
                      for ref in p.input.inputs if ref isa VE.FileSeriesRef)
            @test c.source.build["args"]["step_scale"]==1.5f0
            @test c.source.build["args"]["sky_exposure"]==0.8f0
            @test c.source.bakescreenopts[:samples]==256
            @test c.source.bakescreenopts[:max_depth]==1024
        end
        @test last(pictures).source.build["args"]["beat"]=="c4_credits"
        @test VE.cliplength(last(pictures))/seq.framerate>=12
    end
    return nothing
end
