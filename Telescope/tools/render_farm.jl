"""
Render the film's project on the LAN farm and export it.

    julia --project=<Science4Makie root> Telescope/tools/render_farm.jl <project> <job directory> <output.mp4> <machines>

The job is a snapshot of the project (`VideoEditor.renderjob`, `portable = false`:
each developed package pinned by its code). Every machine offers its GPUs with a
farm client in its own application root, which must hold the same code:

    VIDEOEDITOR_FARM_PROJECT=<root> julia --project=<root> -e 'include("<VideoEditor>/FarmClient/src/FarmClient.jl");
        FarmClient.serve(FarmClient.Client(ARGS[1], ARGS[2]))' <gpus> <this host>:7600

Once `machines` clients are connected, the farm renders every distinct traced
picture once; the project adopts the frames' planes and the editor's own export
composes the film with its narration. Run again to resume: the same project
resumes its job, keeping every committed frame.
"""

using VideoEditor, RayMakie, Telescope
import VideoEditor as VE

function main(project, jobdir, output, machines; timeout = 3600)
    VE.usebackend!(RayMakie)
    job = VE.renderjob(project, jobdir; portable = false)
    delivery = VE.loadproject(project)
    server = VE.farmserver()
    try
        waited = 0
        while length(VE.farmmachines(server)) < machines
            waited < timeout || error("only $(length(VE.farmmachines(server))) of $machines farm clients connected")
            sleep(5)
            waited += 5
        end
        println("MACHINES ", join((m.name for m in VE.farmmachines(server)), ", "))
        flush(stdout)
        status = VE.renderfarm!(job, VE.farmworkers(job, server); reuse = delivery,
                                progress = (done, total) -> (println("FARM $done/$total"); flush(stdout)))
        (status["paused"] || status["completed"] < status["total"]) && return status
    finally
        VE.adoptfarmcache!(delivery, job)
        VE.saveproject(project, delivery; checkpoint = false)
        close(server)
    end
    VE.exportvideo(output, delivery; encoder_options = (crf = 18, preset = "medium"))
    VE.saveproject(project, delivery; checkpoint = false)
    println("DONE ", output)
    return output
end

main(ARGS[1:3]..., parse(Int, ARGS[4]))
