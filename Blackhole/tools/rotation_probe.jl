# Isolate a failing frame with the existing RayMakie/Hikari pipeline, one
# synchronized sample at a time. Does not write to the review's native caches.
function probe_rotation_frame(project; sourceframe=422,samples=128,hw_accel=true)
    film=loadfilm()
    Base.invokelatest(_probe_rotation_frame,project,film,sourceframe,samples,hw_accel)
end
function _probe_rotation_frame(project,film,sourceframe,samples,hw_accel)
    seq=VE.loadproject(project)
    clip=only(filter(c->c.track==1,seq.clips))
    keybeat!(clip,film)
    scene,target=VE.realize(clip.source.root,seq.canvas)
    clip.source.live=VE.LiveScene(scene,nothing,target,seq.canvas,:RayMakie,clip.source.root,Dict{Symbol,Any}(),Any[])
    VE.updatesceneprogram!(target,clip.source,clip,sourceframe,seq.framerate;reset=true)
    VE.applysceneparams!(clip.source,clip,sourceframe)
    screen=RayMakie.Screen(scene;device=Mantle.defaultbackend(),rasterize=false,
        samples,denoise=false,max_depth=1024,hw_accel)
    isempty(screen.scene_states) && RayMakie.init_scene!(screen,screen.scene)
    for sample in 1:samples
        started=time()
        RayMakie.trace!(screen;clear=sample==1,samples=1)
        # Flush the plan's own queue. Waiting on the backend/context alone
        # does not submit a plan recording still held in that queue's batch.
        for ss in screen.scene_states
            ss.film === nothing && continue
            ss.integrator.state === nothing && continue
            Mantle.waitidle(ss.integrator.state.plans.finalize.graph.dev)
        end
        println("PROBE SAMPLE ",sample,"/",samples,"; ",round(time()-started;digits=3)," s");flush(stdout)
    end
    println("PROBE BEAUTY COMPLETE; capturing guides/planes");flush(stdout)
    raw=RayMakie.renderbuffers(screen;clear=false,samples=0)
    @assert any(ss->ss.film !== nothing && ss.film.iteration_index[]==samples,screen.scene_states)
    @assert maximum(c->max(c.r,c.g,c.b),Array(raw.color))>0
    VE.writerenderframe(joinpath(dirname(project),"probe_frame$(sourceframe).vehdr"),raw)
    println("PROBE CAPTURE COMPLETE");flush(stdout)
    close(screen)
    nothing
end
