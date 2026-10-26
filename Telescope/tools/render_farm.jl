"""
Render the film's project on the LAN farm and export it.

    julia --project=<Science4Makie root> Telescope/tools/render_farm.jl <project> <job directory> <output.mp4> <machine>...

The job is a snapshot of the project (`VideoEditor.renderjob`, `portable = false`:
each developed package pinned by its code). Every machine offers its GPUs with a
farm client in its own application root, which must hold the same code:

    VIDEOEDITOR_FARM_PROJECT=<root> julia --project=<root> -e 'include("<VideoEditor>/FarmClient/src/FarmClient.jl");
        FarmClient.serve(FarmClient.Client(ARGS[1], ARGS[2]))' <gpus> <this host>:7600

Once a client of every named machine is connected (as the farm server names
them: its host, with its address where hosts share a name), the farm renders
every frame on those alone, and `VideoEditor.encodefarm!` encodes them with the
narration. Run again to resume the job in `job directory`, keeping every
committed frame; a changed edit needs a new one. `main(...; frames)` renders
only those timeline frames (a sample before the whole film) and exports nothing.
"""

using VideoEditor, RayMakie, Telescope
import VideoEditor as VE

function main(project, jobdir, output, machines::AbstractVector{<:AbstractString}; frames = nothing, timeout = 3600)
    VE.usebackend!(RayMakie)
    job = VE.renderjob(project, jobdir; portable = false)
    server = VE.FarmServer()   # its own, closed when done (`farmserver()` is the session's)
    try
        connected() = [m.name for m in VE.farmmachines(server)]
        waited = 0
        while !issubset(machines, connected())
            waited < timeout || error("farm clients missing: $(join(setdiff(machines, connected()), ", "))")
            sleep(5)
            waited += 5
        end
        others = setdiff(connected(), machines)
        println("MACHINES ", join(machines, ", "), isempty(others) ? "" : "; left out: " * join(others, ", "))
        flush(stdout)
        status = VE.renderfarm!(job, VE.farmworkers(job, server; exclude = others); frames,
                                progress = (done, total) -> (println("FARM $done/$total"); flush(stdout)))
        (frames !== nothing || status["paused"] || status["completed"] < status["total"]) && return status
    finally
        close(server)
    end
    VE.encodefarm!(jobdir, output; crf = 18, preset = "slow")
    println("DONE ", output)
    return output
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS[1:3]..., ARGS[4:end])
end
