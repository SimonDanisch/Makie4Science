# ROOT environment only, after project.jl/stills.jl. Data dependencies live in
# VideoEditor's saved input graph, not a private scene-recipe sequence loader.

"Move saved legacy loader addresses without changing paths, clocks or quality."
function migrate_plasma_loader!(sequence)
    changed=0
    for clip in sequence.clips
        touched=false
        for fx in clip.effects, p in fx.params
            p.input===nothing && continue
            for (i,ref) in enumerate(p.input.inputs)
                ref isa VE.FileSeriesRef || continue
                ref.package=="GRMHDSnapshots" && ref.loader==:radiative_volume || continue
                p.input.inputs[i]=VE.FileSeriesRef(ref.paths,ref.times;package="Hikari",
                    loader=:radiative_volume,options=merge(Dict("mass_unit"=>3e24,
                        "black_hole_mass"=>6.5e9*1.98847e33),ref.options),
                    requires=unique([ref.requires;"GRMHDSnapshots"]))
                touched=true
                changed+=1
            end
        end
        touched && VE.invalidateclip!(clip)
    end
    VE.bindinputs!(sequence)
    return changed
end

"""
    native_plasma_inputs!(sequence; step_scale=1.5f0) -> number of inputs moved

Load the black hole's GRMHD snapshots on their own grid
(`Hikari.native_radiative_volume`) instead of the Cartesian resampling, with the
same snapshots, clock and exposure; bend light with the fourth-order chords at
`step_scale` (1.5 is more accurate than the second-order chords at 0.5, with a
third of them); and mark every traced black-hole picture stale: the static one
of `a2_two_numbers` changes with it.
"""
function native_plasma_inputs!(sequence; step_scale=1.5f0)
    moved=0
    for clip in sequence.clips, fx in clip.effects, p in fx.params
        p.input===nothing && continue
        for (i,ref) in enumerate(p.input.inputs)
            ref isa VE.FileSeriesRef && ref.package=="Hikari" && ref.loader==:radiative_volume || continue
            options=filter(((k,v),)->k!="resolution",ref.options)
            p.input.inputs[i]=VE.FileSeriesRef(ref.paths,ref.times;package="Hikari",
                loader=:native_radiative_volume,options,requires=ref.requires)
            moved+=1
        end
    end
    for clip in sequence.clips
        clip.track==1 && clip.source isa VE.SceneSource || continue
        get(clip.source.build["args"],"beat","") in ("a1_black_hole","a2_two_numbers") || continue
        VE.setsceneargs!(clip,Dict("step_scale"=>Float32(step_scale)))
    end
    VE.bindinputs!(sequence)
    return moved
end

function bind_plasma_inputs!(sequence; first=5000,last=5031,
                             start=0.0,duration=31.0)
    isfinite(duration) && duration>0 || throw(ArgumentError("duration must be positive"))
    film=loadfilm()
    inputs=Base.invokelatest(film.grmhd_sequence;first,last)
    ref=VE.FileSeriesRef(inputs.paths,inputs.times;package="Hikari",requires=["GRMHDSnapshots"],
        loader=:native_radiative_volume,options=Dict("normalization"=>film.GRMHD_EXPOSURE,
            "mass_unit"=>3e24,"black_hole_mass"=>6.5e9*1.98847e33))
    count=0
    for clip in sequence.clips
        clip.track==1 || continue
        get(clip.source.build["args"],"beat","")=="a1_black_hole" || continue
        VE.setsceneargs!(clip,Dict("animate_plasma"=>true))
        fx=VE.findslot(clip,:scene)
        clock=VE.Param(:plasma_time,"Simulation time",inputs.times[1];
            curve=VE.AnimCurve{Float64}([
                VE.Keyframe(round(Int,start*sequence.framerate),inputs.times[1],:linear),
                VE.Keyframe(round(Int,(start+duration)*sequence.framerate),inputs.times[end],:linear)],:linear))
        input=VE.ParamInput(:sample,ref,VE.ParamRef(:plasma_time))
        data=VE.Param{Any}(Symbol("plasma_volume.snapshot"),"GRMHD volume sequence",
            Makie.Observable(VE.AnimCurve{Any}([VE.Keyframe{Any}(0,nothing,:hold)],:hold)),
            Makie.Observable(false),nothing,input,nothing)
        filter!(p->p.name ∉ (:plasma_time,Symbol("args.plasma"),Symbol("plasma_volume.snapshot")),fx.params)
        append!(fx.params,[clock,data])
        VE.bakedirty!(clip)
        count+=1
    end
    count>0 || error("No black-hole picture clip in this sequence")
    VE.bindinputs!(sequence)
    return ref
end
