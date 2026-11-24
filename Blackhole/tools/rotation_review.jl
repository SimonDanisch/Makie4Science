# Include after project.jl and stills.jl, in the ONE root Julia environment.
# A standard VideoEditor project/export, with native HDR/track/composite caches.
# The 128-spp review never overwrites the separate 256-spp final masters.
function prepare_rotation_review(project; from=41.0, duration=3.0, fps=10, spp=128,
                                 density_resolution=384, sky_exposure=0.8f0)
    if isfile(project)
        seq=VE.loadproject(project)
        @assert VE.seqlength(seq)==round(Int,duration*fps)
        @assert seq.framerate==fps
        return seq
    end
    film=loadfilm()
    reference=Base.invokelatest(film.grmhd_plasma).emissivity_peak
    plasma=Base.invokelatest(film.grmhd_plasma;resolution=density_resolution)
    emission_scale=12f0*plasma.emissivity_peak/reference
    p=buildproject(project;canvas=(1280,720),fps,spp,beats=["a1_black_hole"],
                   voice_root=joinpath(@__DIR__,"..","voice_v6"))
    seq=p.sequence
    firstframe=round(Int,from*fps)
    lastframe=firstframe+round(Int,duration*fps)
    for clip in seq.clips
        clip.src_in=firstframe
        clip.src_out=lastframe
        clip.start=0
        VE.setsceneargs!(clip,Dict("density_resolution"=>density_resolution,
            "step_scale"=>0.5f0,"emission_scale"=>emission_scale,
            "sky_exposure"=>sky_exposure))
        if clip.track==1
            VE.setrenderconfig!(clip;raytrace=true,samples=spp,max_depth=1024,
                                device="Mantle.defaultbackend()")
            VE.seteffect!(clip,VE.LinearGradeEffect(exposure=-1.5))
        end
    end
    @assert VE.seqlength(seq)==round(Int,duration*fps)
    VE.saveproject(project,seq)
    return seq
end

# Include plasma_inputs.jl before this helper. Use the same native file-input
# graph as the final edit, not a private per-frame volume loader. Three nearby
# snapshots suffice for this bounded review; their playback rate matches the
# full 32-snapshot, 55.75375-second black-hole beat.
function prepare_animated_rotation_review(project; from=41.0, duration=3.0,
                                          fps=10, spp=128, density_resolution=384)
    seq=prepare_rotation_review(project;from,duration,fps,spp,density_resolution)
    picture=only(filter(c->c.track==1,seq.clips))
    @assert picture.source.bakescreenopts[:samples]==spp
    @assert picture.source.build["args"]["density_resolution"]==density_resolution
    refs=[ref for fx in picture.effects for p in fx.params if p.input!==nothing
          for ref in p.input.inputs if ref isa VE.FileSeriesRef]
    if !isempty(refs)
        ref=only(refs)
        @assert ref.package=="Hikari" && ref.loader==:radiative_volume
        @assert length(ref.paths)==3 && ref.options["resolution"]==density_resolution
        @assert "GRMHDSnapshots" in ref.requires
        return seq
    end
    bind_plasma_inputs!(seq;first=5000,last=5002,resolution=density_resolution,
                        start=from,duration=55.75375*2/31)
    for clip in seq.clips
        clip.track==1 && VE.invalidateclip!(clip)
    end
    VE.saveproject(project,seq;checkpoint=false)
    return seq
end

function render_rotation_review(project,output; limit=nothing)
    seq=VE.loadproject(project)
    engine=VE.FxEngine(Mantle.defaultbackend())
    readers=Dict{String,Any}()
    out=zeros(VE.RGB{VE.N0f8},seq.canvas...)
    count=min(something(limit,VE.seqlength(seq)),VE.seqlength(seq))
    try
        VE.withfinalscenes(seq) do
            for frame in 0:count-1
                started=time()
                VE.renderframe!(out,seq,frame,readers,engine)
                # Save every frame: an interruption loses no cache index state.
                VE.saveproject(project,seq;checkpoint=false)
                if frame==0
                    save(joinpath(dirname(output),"first_frame.png"),permutedims(out))
                end
                println("ROTATION ",frame+1,"/",VE.seqlength(seq),"; ",
                        round(time()-started;digits=2)," s");flush(stdout)
            end
        end
    finally
        VE.emptyengine!(engine)
        foreach(close,values(readers))
        VE.saveproject(project,seq;checkpoint=false)
        foreach(c->close(c.source),seq.clips)
    end
    count==VE.seqlength(seq) || return project
    # Normal editor export now reuses the completed native caches.
    VE.exportvideo(output,seq;audio=false,encoder_options=(crf=18,preset="medium"))
    VE.saveproject(project,seq;checkpoint=false)
    return output
end
