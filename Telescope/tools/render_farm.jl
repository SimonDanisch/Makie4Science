#=
Render the film's project on the LAN farm and export it.

    julia --project=<Science4Makie root> Telescope/tools/render_farm.jl <project> <job directory> <output.mp4> [--carry=<earlier job directory>] <machine>...

The job is a snapshot of the project (`VideoEditor.renderjob`, `portable = false`:
each developed package pinned by its code; `hdr = false`: workers retain graded
picture PNGs and transparent label PNGs, without the large HDR/auxiliary buffers).
Every machine offers its GPUs with a
farm client in its own application root, which must hold the same code:

    VIDEOEDITOR_FARM_PROJECT=<root> julia --project=<root> -e 'include("<VideoEditor>/FarmClient/src/FarmClient.jl");
        FarmClient.serve(FarmClient.Client(ARGS[1], ARGS[2]))' <gpus> <this host>:7600

Once a client of every named machine is connected (as the farm server names
them: its host, with its address where hosts share a name), the farm renders
missing picture on those alone, adopts the layers into the saved project, and
exports through VideoEditor's compositor with the narration. Label translations
reuse cached pictures. Run again to resume the job in `job directory`, keeping every
committed frame; a changed edit needs a new one. Code changed (a fix deployed
to every machine) makes a new job of the same edit: `--carry` takes the frames
an earlier job of it committed (`VideoEditor.carryframes!`), so none is
rendered twice. `main(...; frames)` renders
only those timeline frames (a sample before the whole film) and exports nothing.
=#

using VideoEditor, RayMakie, Telescope
import VideoEditor as VE

function main(project, jobdir, output, machines::AbstractVector{<:AbstractString}; frames = nothing, carry = nothing,
              timeout = 3600)
    VE.usebackend!(RayMakie)
    seq = VE.loadproject(project)
    if isempty(seq.trackcaches)
        VE.enabletrackcache!(seq, project * ".frames")
        VE.saveproject(project, seq)
    end
    job = VE.renderjob(project, jobdir; portable = false, hdr = false)
    carry === nothing || println("CARRIED ", VE.carryframes!(job, VE.RenderJob(carry)), " frames from ", carry)
    needed = VE.farmneededframes(seq; frames = something(frames, 0:VE.seqlength(seq)-1))
    server = isempty(needed) ? nothing : VE.FarmServer()
    status = Dict("paused"=>false, "completed"=>0, "total"=>0)
    try
        if server !== nothing
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
            status = VE.renderfarm!(job, VE.farmworkers(job, server; exclude = others); frames, reuse = seq,
                                    progress = (done, total) -> (println("FARM $done/$total"); flush(stdout)))
        end
    finally
        server === nothing || close(server)
        VE.adoptfarmcache!(seq, job)
        VE.saveproject(project, seq)
    end
    (frames !== nothing || status["paused"] || status["completed"] < status["total"]) && return status
    isempty(VE.farmneededframes(seq)) || error("Clean picture layers are missing; a finished composite is not an editable picture cache")
    VE.exportvideo(output, seq; encoder_options = (crf = 18, preset = "slow"))
    println("DONE ", output)
    return output
end

if abspath(PROGRAM_FILE) == @__FILE__
    carried = [chopprefix(a, "--carry=") for a in ARGS[4:end] if startswith(a, "--carry=")]
    main(ARGS[1:3]..., filter(a -> !startswith(a, "--carry="), ARGS[4:end]); carry = isempty(carried) ? nothing : only(carried))
end
