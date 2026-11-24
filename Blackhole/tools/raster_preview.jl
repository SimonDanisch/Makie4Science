# Include in a Science4Makie root session with VideoEditor (as VE) and RayMakie
# loaded. A review video of the whole cut through RayMakie's raster path.

"""
    raster_sequence(project) -> Sequence
    raster_sequence(job::VE.RenderJob) -> Sequence

A cut drawn by RayMakie's raster path, held in memory only: a project file, or a
farm job's snapshot opened the way a farm worker opens it. Its track caches are
dropped, so nothing cached is read or written, and its traced clips are switched
to raster. Nothing is saved from it.
"""
raster_sequence(project::AbstractString) = (VE.usebackend!(RayMakie); raster!(VE.loadproject(project)))
function raster_sequence(job::VE.RenderJob)
    VE.usebackend!(RayMakie)
    snapshot = VE.jobsnapshot(job)
    pathmap = Dict(source => joinpath(snapshot, relative) for (source, relative) in job.relocations)
    return raster!(VE.loadproject(VE.jobproject(job); pathmap))
end

function raster!(seq)
    empty!(seq.trackcaches)
    seq.compositecache = nothing
    for clip in seq.clips
        s = clip.source
        s isa VE.SceneSource || continue
        get(s.bakescreenopts, :rasterize, true) && get(s.bakescreenopts, :samples, 1) == 1 && continue
        options = filter(p -> first(p) ∉ (:rasterize, :samples), s.bakescreenopts)
        VE.setrenderconfig!(clip; backend = s.backend, raytrace = false, options...)
    end
    return seq
end

"""
    export_raster_preview(source, out) -> out

Export `raster_sequence(source)` to `out` with the narration. Every 30 frames it
prints the frames per second of that stretch and how many standing screens the
scene sources have built so far: one per scene clip, never one per frame.
"""
function export_raster_preview(source, out)
    seq = raster_sequence(source)
    mkpath(dirname(out))
    screens = Base.IdSet{Any}()
    previous = Ref((0, time()))
    function progress(done, total)
        for c in seq.clips
            s = c.source
            s isa VE.SceneSource && s.live !== nothing && push!(screens, s.live.screen)
        end
        now = time()
        fps = (done - previous[][1]) / max(now - previous[][2], 1e-9)
        previous[] = (done, now)
        println("RASTER ", done, "/", total, "  ", round(fps; digits = 1), " fps  screens built: ", length(screens))
        flush(stdout)
    end
    VE.exportvideo(out, seq; encoder_options = (crf = 18, preset = "medium"), progress)
    return out
end
