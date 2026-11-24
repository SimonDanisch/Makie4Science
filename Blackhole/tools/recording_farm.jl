# Native VideoEditor FarmWorkers: explicit process-isolated LAN slots only.
# Include after project.jl and farm_bench.jl in the Science4Makie root session.
struct RecordingFrameFilter{W}
    worker::W
    allowed::BitSet
end
(worker::RecordingFrameFilter)(frames)=worker.worker(frames)
Base.close(worker::RecordingFrameFilter)=close(worker.worker)
VE.acceptsfarmframe(worker::RecordingFrameFilter,job,frame::Integer)=frame in worker.allowed
VE.foreachfarmresult(accept,worker::RecordingFrameFilter,frames)=VE.foreachfarmresult(accept,worker.worker,frames)

function held_masters(seq)
    keep=Set{Tuple{UInt64,Int}}()
    for clip in seq.clips
        VE.traced(clip.source) || continue
        groups=Dict{Any,Vector{Int}}()
        for sf in clip.src_in:clip.src_out-1
            push!(get!(() -> Int[],groups,VE.framekey(clip,sf)),sf)
        end
        for frames in values(groups)
            length(frames)>1 && union!(keep,((clip.id,sf) for sf in frames))
        end
    end
    return keep
end

function run_recording_farm(project,jobdir,output,remotes;workerpool=nothing,restrictions=Dict{String,BitSet}(),
                            frames=nothing,export_movie=true)
    VE.usebackend!(RayMakie)
    job=isfile(joinpath(jobdir,"job","job.toml")) ? VE.RenderJob(jobdir) :
        VE.renderjob(project,jobdir;inputs=scene_inputs(),root=dirname(@__DIR__),portable=false)
    # No implicit local renderer: coordination must remain responsive to I/O.
    # Bosgame is excluded; only explicitly supplied GPU slots render.
    workers=VE.FarmWorker[]
    for (name,session) in remotes
        session isa VE.FarmSlot || error("Expected a native streaming FarmSlot, not a synchronous per-frame RPC")
        resource=session
        haskey(restrictions,name) && (resource=RecordingFrameFilter(resource,restrictions[name]))
        push!(workers,VE.FarmWorker(name,resource))
    end
    pool=workerpool===nothing ? workers : workerpool
    workerpool===nothing || foreach(w->put!(pool,w),workers)
    logfile=joinpath(dirname(project),"farm_coordinator.log")
    logline(message)=open(io->println(io,message),logfile,"a")
    # farmrenderer owns independent worker caches, not the delivery caches.
    delivery=VE.loadproject(project)
    try
        status=VE.renderfarm!(job,pool;reuse=delivery,frames,
            progress=(done,total)->logline("FARM $done/$total"))
        (status["paused"] || status["completed"]<status["total"]) && return status
    catch err
        logline(sprint(showerror,err,catch_backtrace()))
        rethrow()
    finally
        VE.adoptfarmcache!(delivery,job)
        VE.saveproject(project,delivery;checkpoint=false)
    end
    if !export_movie
        logline("Requested review frames complete; no full-film export requested")
        return jobdir
    end
    logline("Farm complete; normal VE export fills held frames and muxes narration")
    VE.exportvideo(output,delivery;encoder_options=(crf=18,preset="medium"),
        progress=(done,total)->(done%300==1 && (VE.saveproject(project,delivery;checkpoint=false);
            logline("ENCODE $done/$total"))))
    VE.saveproject(project,delivery;checkpoint=false)
    logline("DONE $output")
    return output
end
