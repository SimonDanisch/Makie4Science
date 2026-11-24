# julia --project=/path/to/Science4Makie tools/run_hd_farm.jl JOBDIR PROJECT OUTPUT MACHINES [FRAMES [PORT]]
#
# The farm coordinator as a process of its own, started detached from a root
# session so that it outlives the session (a coordinator running inside one died
# with it, twice). Starts the farm server, waits for MACHINES clients, then
# resumes the job in JOBDIR for PROJECT (only the timeline FRAMES when given, a
# comma-separated list of frames and FIRST:LAST ranges, `all` for every frame)
# and exports OUTPUT once nothing is missing. On PORT, only the clients started
# for it join: every other client offers itself on the default port.
root = dirname(something(Base.active_project(), ""))
basename(root) == "Science4Makie" || error("Use the machine's Science4Makie root --project")
length(ARGS) in 4:6 || error("usage: run_hd_farm.jl JOBDIR PROJECT OUTPUT MACHINES [FRAMES [PORT]]")
using VideoEditor, RayMakie, GRMHDSnapshots, OIDNRunner
const VE = VideoEditor
VE.usebackend!(RayMakie)
include(joinpath(@__DIR__, "resume_hd_farm.jl"))

jobdir, project, output = ARGS[1], ARGS[2], ARGS[3]
machines = parse(Int, ARGS[4])
frame_range(r) = occursin(':', r) ? (:)(parse.(Int, split(r, ':'))...) : [parse(Int, r)]
frames = length(ARGS) >= 5 && ARGS[5] != "all" ? mapreduce(frame_range, vcat, split(ARGS[5], ',')) : nothing
server = length(ARGS) == 6 ? VE.farmserver(; port = parse(Int, ARGS[6])) : VE.farmserver()
# A client that connects after the job is handed out does not get it.
deadline = time() + 3600
while count(m->ScienceFarmPolicy.allowed(m.name),VE.farmmachines(server)) < machines && time() < deadline
    sleep(10)
end
println("FARM MACHINES ", [m.name for m in VE.farmmachines(server)])
flush(stdout)
result = resume_hd_farm!(jobdir, project, output; server, frames)
println("FARM DONE ", result)
flush(stdout)
