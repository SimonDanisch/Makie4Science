# Run only with --project=/home/sim/Programmieren/Science4Makie.
using Test
include(joinpath(@__DIR__, "..", "project.jl"))

function test_keyframed_beats(film; beats = sort!(collect(keys(film.PERFORMED))))
    @test length(film.PERFORMED) == 20
    recipe = joinpath(@__DIR__, "..", "film", "film.jl")
    @testset "native film properties" begin
    @testset "native file-backed attribute retains its declared type" begin
        fig,axis,plot=VE.Makie.scatter([VE.Makie.Point2f(0,0)])
        value=VE.Makie.Observable{Any}(nothing)
        try
            Base.invokelatest(film.plotattribute!,plot,:snapshot,value)
            data=(density=Float32[1,2],)
            VE.Makie.update!(plot;snapshot=data)
            @test value[]===data
            VE.Makie.update!(plot;snapshot=nothing)
            @test value[]===nothing
        finally
            VE.Makie.free(fig.scene)
        end
    end
    for name in beats
        @testset "$name" begin
            t = name == "c4_credits" ? (; starts = [0f0], ends = [12f0], duration = 12f0) :
                read_timing(name; root = joinpath(@__DIR__, "..", "voice_v6"))
            args = Dict{String,Any}("beat" => name, "starts" => t.starts,
                "ends" => t.ends, "duration" => t.duration)
            # Build through the same editor recipe boundary used by playback/farm.
            build = VE.programscene(recipe; args)
            clip = VE.sceneclip(VE.buildscene(build); build, frames = ceil(Int, t.duration * 30),
                canvas = (1280, 720), framerate = 30, backend = :RayMakie)
            clip.source.root.builder = film.buildscene
            keybeat!(clip, film)
            scene, target = VE.realize(clip.source.root, (1280, 720))
            try
                @test !hasfield(typeof(target), :update!)
                @test !hasfield(typeof(target),:args)
                clip.source.live=VE.LiveScene(scene,nothing,target,(1280,720),:RayMakie,clip.source.root,Dict{Symbol,Any}(),Any[])
                VE.updatesceneprogram!(target,clip.source,clip,0,30;reset=true)
                paths = Set(row.path for section in VE.sceneattributes(clip.source) for row in section.rows)
                keyed = Base.invokelatest(film.beatkeys, args, 30)
                @test all(!startswith(path,"args.") for (path,_,_) in keyed)
                @test all(Symbol(path) in paths for (path, _, _) in keyed)
                tfilm=Base.invokelatest(film.Timing,t.starts,t.ends,t.duration)
                performed=Base.invokelatest(film.perform,film.PERFORMED[name],tfilm)
                addresses=film.NATIVE_PATHS[(name,:combined)]
                missing=[name for (name,_) in [performed.picture;performed.labels] if !haskey(addresses,name) && !startswith(name,"camera")]
                @test isempty(missing)
                fx = VE.findslot(clip, :scene)
                # Seeking backwards/forwards must give identical argument values.
                frames = unique([0, clip.src_out ÷ 2, clip.src_out - 1])
                samples = Dict{Int,Any}()
                for frame in [frames; reverse(frames)]
                    VE.updatesceneprogram!(target,clip.source,clip,frame,30;reset=true)
                    VE.applysceneparams!(clip.source,clip,frame)
                    values = [VE.scenevalue(clip.source,Symbol(path)) for (path,_,_) in keyed]
                    for ((path,_,_),value) in zip(keyed,values)
                        expected=VE.valueat(VE.param(fx,Symbol(path)),frame)
                        if occursin(".rotation[",path)
                            @test abs(mod(value-expected+180,360)-180)<1e-3
                        else
                            @test value≈expected atol=1e-4 rtol=1e-5
                        end
                    end
                    haskey(samples, frame) ? (@test isequal(samples[frame], values)) : (samples[frame] = values)
                end
                if name == "a2_two_numbers"
                    pictureargs = merge(args, Dict("layer" => "picture"))
                    pbuild = VE.programscene(recipe; args = pictureargs)
                    pc = VE.sceneclip(VE.buildscene(pbuild); build = pbuild, frames = clip.source.nframes,
                        canvas = (1280, 720), framerate = 30)
                    keybeat!(pc, film)
                    @test VE.framekey(pc, pc.src_out - 1) == VE.framekey(pc, pc.src_out - 2)
                    @test length(unique(VE.framekey(pc, f) for f in 0:pc.src_out-1)) < pc.src_out ÷ 2
                end
            finally
                VE.Makie.free(scene)
            end
            GC.gc()
        end
    end
    end
end

let options = isempty(ARGS) ? (;) : (; beats = ARGS)
    Base.invokelatest(test_keyframed_beats, loadfilm(); options...)
end
