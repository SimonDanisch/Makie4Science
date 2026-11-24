# Include after project.jl. Selected finished frames ONLY, in the final native
# project/cache. No separate sample-cache strategy and no full-movie export.
function sample_blackholes(project; times=(24.0,44.0), spp=256, refresh=true)
    seq=VE.loadproject(project)
    clip=only(filter(c->c.track==1 && get(c.source.build["args"],"beat","")=="a1_black_hole",seq.clips))
    all(t->0<=round(Int,t*seq.framerate)<clip.src_out-clip.src_in,times) ||
        throw(ArgumentError("sample time lies outside the black-hole beat"))
    # Declare recipe changes through the editor, preserving unrelated caches.
    for c in seq.clips
        get(c.source.build["args"],"beat","")=="a1_black_hole" || continue
        refresh && VE.setsceneargs!(c,Dict{String,Any}())
    end
    opts=clip.source.bakescreenopts
    if get(opts,:rasterize,true) || get(opts,:samples,1)!=spp || get(opts,:max_depth,8)!=512
        VE.setrenderconfig!(clip;raytrace=true,samples=spp,max_depth=512,device="Mantle.defaultbackend()")
    end
    engine=VE.FxEngine(Mantle.defaultbackend())
    readers=Dict{String,Any}()
    out=zeros(VE.RGB{VE.N0f8},seq.canvas...)
    results=NamedTuple[]
    try
        VE.withfinalscenes(seq) do
            for t in times
                frame=clip.start+round(Int,t*seq.framerate)
                started=time()
                VE.renderframe!(out,seq,frame,readers,engine)
                seconds=time()-started
                path=joinpath(dirname(project),"blackhole_grmhd_$(round(Int,t))s_$(spp)spp.png")
                save(path,permutedims(out))
                VE.saveproject(project,seq;checkpoint=false)
                push!(results,(;path,seconds,t,spp))
                println(last(results));flush(stdout)
            end
        end
    finally
        VE.emptyengine!(engine)
        foreach(close,values(readers))
        VE.saveproject(project,seq;checkpoint=false)
        for source in unique(c.source for c in seq.clips if c.source isa VE.SceneSource)
            close(source)
        end
    end
    results
end
