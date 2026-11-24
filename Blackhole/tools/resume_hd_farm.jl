# Run in the Science4Makie root session after `using VideoEditor, RayMakie,
# GRMHDSnapshots, OIDNRunner` and `const VE = VideoEditor`. Resumes an existing
# farm job directory (never makes a new snapshot), adopts what the workers
# returned into the final project and exports once no frame is missing.

isdefined(@__MODULE__,:ScienceFarmPolicy) || include("farm_policy.jl")

"""
    resume_hd_farm!(jobdir, project, output; server = VE.farmserver(), frames = nothing) -> status

Dispatch the frames of the job in `jobdir` that `project` still needs (of
`frames`, or all) to every GPU of the farm clients connected to `server` now,
then adopt the returned planes and save `project`. Exports `output` only when
`project` needs no further frames; otherwise returns the job's status so the
remaining frames can be resumed.
"""
function resume_hd_farm!(jobdir, project, output; server = VE.farmserver(), frames = nothing)
    seq = VE.loadproject(project)
    job = VE.RenderJob(jobdir)
    isempty(VE.farmmachines(server)) && error("no farm client is connected to port $(server.port)")
    isempty(VE.farmneededframes(seq)) || VE.renderfarm!(job,
        VE.farmworkers(job, server;exclude=ScienceFarmPolicy.excluded); reuse = seq, frames)
    VE.adoptfarmcache!(seq, job)
    VE.saveproject(project, seq)
    missing = VE.farmneededframes(seq)
    isempty(missing) || return (; missing = length(missing), status = VE.JSON.parsefile(joinpath(jobdir, "status.json")))
    VE.exportvideo(output, seq)
    return (; missing = 0, output)
end
