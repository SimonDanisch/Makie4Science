# Include after project.jl and stills.jl in the ONE Science4Makie root session.
# Diagnostic variants only: never change the final project or its source masters.
# All pictures use the existing a1 scene, RayMakie/Hikari transport and VE HDR.
function check_blackhole_convergence(project; kwargs...)
    film=loadfilm()
    return Base.invokelatest(_check_blackhole_convergence,project,film;kwargs...)
end

function _check_blackhole_convergence(project,film; time=54.0, spp=256,
        variants=((192,1f0,1024),(192,0.5f0,1024),(384,0.5f0,1024)))
    seq=VE.loadproject(project)
    clip=only(filter(c->c.track==1 && get(c.source.build["args"],"beat","")=="a1_black_hole",seq.clips))
    sf=round(Int,time*seq.framerate)
    original=VE.cachedsourceframe(clip,sf)
    original === nothing && error("A cached final master is required for this comparison")
    dir=joinpath(dirname(project),"diagnostics")
    mkpath(dir)
    reference_peak=Base.invokelatest(film.grmhd_plasma).emissivity_peak
    effects=(;effects=filter(fx->fx.kind!=:oidndenoise,clip.effects))
    work=VE.HDRWork(Mantle.defaultbackend(),seq.canvas...)
    function saveviews(raw,stem)
        device=VE.uploadmaster!(work,raw)
        for (suffix,fx) in (("raw",effects),("oidn",clip))
            image=Array(VE.hdrpicture!(work,device,fx,sf))
            save(joinpath(dir,stem*"_"*suffix*".png"),permutedims(image))
        end
    end
    results=NamedTuple[]
    try
        saveviews(original,"faceon_$(round(Int,time))s_final_192_step1_depth512")
        for (resolution,step_scale,max_depth) in variants
            stem="faceon_$(round(Int,time))s_grid$(resolution)_step$(step_scale)_depth$(max_depth)_$(spp)spp"
            master=joinpath(dir,stem*".vehdr")
            started=Base.time()
            if isfile(master)
                raw=VE.readrenderframe(master)
            else
                plasma=Base.invokelatest(film.grmhd_plasma;resolution)
                # Changing the sampling grid must not silently change exposure.
                emission_scale=12f0*plasma.emissivity_peak/reference_peak
                args=clip.source.build["args"]
                build=VE.programscene(joinpath(@__DIR__,"..","film","film.jl");
                    args=merge(args,Dict("step_scale"=>step_scale,"emission_scale"=>emission_scale,"layer"=>"picture")))
                variant=VE.sceneclip(VE.buildscene(build);build,frames=clip.source.nframes,canvas=seq.canvas,framerate=seq.framerate)
                keybeat!(variant,film)
                scene,target=VE.realize(variant.source.root,seq.canvas)
                variant.source.live=VE.LiveScene(scene,nothing,target,seq.canvas,:RayMakie,variant.source.root,Dict{Symbol,Any}(),Any[])
                VE.updatesceneprogram!(target,variant.source,variant,sf,seq.framerate;reset=true)
                VE.applysceneparams!(variant.source,variant,sf)
                screen=RayMakie.Screen(scene;device=Mantle.defaultbackend(),rasterize=false,
                    samples=spp,denoise=false,max_depth)
                try
                    frame=Base.invokelatest(RayMakie.renderbuffers,screen;samples=spp)
                    raw=merge(NamedTuple{VE.HDR_PLANES}(map(k->Array(getproperty(frame,k)),VE.HDR_PLANES)),
                        (;metadata=merge(frame.metadata,Dict("diagnostic_grid"=>resolution,
                            "diagnostic_step_scale"=>step_scale,"diagnostic_max_depth"=>max_depth,
                            "diagnostic_spp"=>spp,"diagnostic_time"=>time,
                            "emissivity_reference_peak"=>reference_peak))))
                    VE.writerenderframe(master,raw)
                finally
                    close(screen)
                end
            end
            saveviews(raw,stem)
            push!(results,(;resolution,step_scale,max_depth,spp,seconds=Base.time()-started,master))
            println(last(results));flush(stdout)
        end
    finally
        VE.freework!(work)
    end
    results
end

# Analysis of existing masters only; no tracing, cache mutations or sharpening.
function blackhole_convergence_report(project; time=54.0)
    seq=VE.loadproject(project)
    clip=only(filter(c->c.track==1 && get(c.source.build["args"],"beat","")=="a1_black_hole",seq.clips))
    original=VE.cachedsourceframe(clip,round(Int,time*seq.framerate))
    dir=joinpath(dirname(project),"diagnostics")
    paths=sort(filter(p->endswith(p,".vehdr"),readdir(dir;join=true)))
    frames=[VE.readrenderframe(p) for p in paths]
    lum(c)=0.2126*Float64(c.r)+0.7152*Float64(c.g)+0.0722*Float64(c.b)
    function compare(a,b)
        numerator=0.0;denominator=0.0; signed=0.0; count=0
        w,h=size(a)
        for y in 1:h,x in 1:w
            hypot(x-(w+1)/2,y-(h+1)/2)<=180 || continue
            v=lum(a[x,y]);u=lum(b[x,y])
            numerator+=abs(u-v);denominator+=abs(v);signed+=u-v;count+=1
        end
        (;relative_l1=numerator/denominator,relative_flux_change=signed/denominator,
          bit_identical=a==b,pixels=count)
    end
    function profile(a)
        sums=zeros(Float64,181);counts=zeros(Int,181)
        w,h=size(a)
        for y in 1:h,x in 1:w
            r=round(Int,hypot(x-(w+1)/2,y-(h+1)/2))
            0<=r<=180 || continue
            sums[r+1]+=lum(a[x,y]);counts[r+1]+=1
        end
        values=sums./max.(counts,1)
        peak=argmax(@view values[111:151])+110
        (;ring_peak_radius_px=peak-1,ring_peak_mean_luminance=values[peak],radial_luminance=values)
    end
    comparisons=[(;path=paths[i],metadata=frames[i].metadata,
        vs_original=compare(original.color,frames[i].color),profile=profile(frames[i].color)) for i in eachindex(paths)]
    pairs=[(;a=paths[i],b=paths[j],difference=compare(frames[i].color,frames[j].color))
        for i in eachindex(paths) for j in i+1:length(paths)]
    report=(;time,original_profile=profile(original.color),comparisons,pairs,
        note="Differences include Monte Carlo noise. No uncertainty estimate or external GRRT validation is implied.")
    path=joinpath(dir,"convergence_report.json")
    open(io->VE.JSON.print(io,report),path,"w")
    println("Report: ",path)
    for c in comparisons
        println((;file=basename(c.path),c.vs_original...,peak_radius=c.profile.ring_peak_radius_px,
                  peak_luminance=c.profile.ring_peak_mean_luminance))
    end
    for pair in pairs
        println((;a=basename(pair.a),b=basename(pair.b),pair.difference...))
    end
    report
end
