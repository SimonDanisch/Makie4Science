# Run in the Science4Makie environment after project.jl and farm_bench.jl
# (`scene_inputs`): renders the film on every GPU the connected farm clients
# offer. Each machine that renders, this one included, runs
#
#     julia -m FarmClient all <this machine>:7600
#
# (VideoEditor's FarmClient, docs/renderfarm.md). A job pins its code as the
# Project.toml of the packages it loads at their commits, so every dev
# repository it uses must be committed and pushed before `renderfilm!`.

isdefined(@__MODULE__,:ScienceFarmPolicy) || include("tools/farm_policy.jl")

"""
    renderfilm!(project; name) -> RenderJob

Render `project` in `renders/farm/<name>` on every connected GPU, then take the
track planes and traced HDR sources the workers returned into the project's
caches, so grading, denoising and label edits after it reuse the traced frames.
Resumes a job that was stopped; an edit since makes a new one (a new `name`).
"""
function renderfilm!(project; name = splitext(basename(project))[1])
    seq = VE.loadproject(project)
    job = VE.renderjob(project, joinpath(@__DIR__, "renders", "farm", name); inputs = scene_inputs(), root=@__DIR__)
    isempty(VE.farmneededframes(seq)) || VE.renderfarm!(job,
        VE.farmworkers(job;exclude=ScienceFarmPolicy.excluded);reuse=seq)
    VE.adoptfarmcache!(seq, job)
    VE.saveproject(project, seq)
    return job
end
