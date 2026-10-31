#=
Record the approved direction beat, retaining every other finished frame from
the completed film. Run with the Science4Makie root project, optionally with
`prepare` to verify/save the cut without starting the renderer.

The original saved edit is trimmed and rippled through VideoEditor's clip API;
unchanged clips keep their IDs, source frames and effects. `carryframes!`
validates the explicit timeline mapping and hard-links the finished images.
Only the new beat goes to the ordinary local FarmClient. `encodefarm!` encodes
the resulting job with the revised project's narration. No old cache is deleted.
This historical revision used a flattened source job. It cannot supply clean
layers for localization; use render_farm.jl to build a layered baseline.
=#
using Telescope, ScienceFilms, VideoEditor, JSON, Sockets
import VideoEditor as VE

const FILM_ROOT = normpath(joinpath(@__DIR__, ".."))
const WORKSPACE = realpath(joinpath(FILM_ROOT, "..", "..", ".."))
const GEN = joinpath(FILM_ROOT, "gen")
const ORIGINAL = joinpath(GEN, "farm", "telescope_1080p_20261026g")
const REVISED = joinpath(GEN, "farm", "telescope_1080p_revised_20261028")
const PROJECT = joinpath(GEN, "telescope_revised.videoedit")
const OUTPUT = joinpath(GEN, "telescope_1080p_revised.mp4")

function prepare()
    dirname(Base.active_project()) == WORKSPACE || error("Use the Science4Makie root project")
    reportpath = joinpath(REVISED, "reuse.json")
    if isfile(reportpath)
        return VE.RenderJob(REVISED), JSON.parsefile(reportpath)
    end
    original = VE.RenderJob(ORIGINAL)
    original.planes || error("The original job has no separate picture/label cache; use render_farm.jl to build a layered baseline")
    seq = VE.loadproject(VE.jobproject(original))
    isempty(seq.transitions) || error("Review transition boundaries before changing this cut")
    fps = seq.framerate
    before = Dict(n.label => copy(n.samples) for n in seq.narration)
    takes = Dict(n.label => n for n in seq.narration)
    star = takes["scene_03"]
    window = takes["scene_04"]
    star.anchor === nothing && window.anchor === nothing || error("Expected montage narration")
    starstart, oldstart = round.(Int, (star.at * fps, window.at * fps))
    oldend = minimum(c.start for c in seq.clips if get(c.source.build["args"], "part", "") == "b01_telescope")
    ext = Base.get_extension(ScienceFilms, :ScienceFilmsVideoEditorExt)
    samples, rate = ext.readwav(Telescope.FILM.voice("scene_03"))
    newstart = starstart + round(Int, (length(samples) / rate + Telescope.FILM.parts["scene_03"].tail) * fps)
    newstart < oldstart || error("Expected the approved shortened star montage")
    timing = Telescope.FILM.timing("b00b_direction")
    count = ceil(Int, timing.duration * fps)
    newend = newstart + count
    shift = newend - oldend

    # Remove the replaced window; trim the star montage at its original speed.
    for i in reverse(eachindex(seq.clips))
        c = seq.clips[i]
        if oldstart <= c.start < oldend
            VE.removeclip!(seq, i)
        elseif starstart <= c.start < oldstart && VE.clipend(c) > newstart
            c.src_out = VE.sourceframe(c, newstart)
        elseif c.start >= oldend
            c.start += shift
        end
    end
    resize!(star.samples, length(samples))
    copyto!(star.samples, samples)
    star.rate = rate
    star.text = join(Telescope.FILM.parts["scene_03"].lines, " ")
    filter!(n -> n !== window, seq.narration)
    for n in seq.narration
        n.anchor === nothing && n.at >= oldend / fps && (n.at += shift / fps)
    end
    clips = ScienceFilms.partclips(Telescope.FILM, "b00b_direction"; frames = count,
        canvas = original.canvas, layout = (1280, 720), fps, spp = 256, max_depth = 24)
    for c in clips
        c.start = newstart
        VE.addclip!(seq, c)
    end
    push!(seq.narration, ext.narration(Telescope.FILM, "b00b_direction", [clips], newstart / fps))
    VE.bindinputs!(seq)
    total = VE.seqlength(seq)
    total == original.total + shift || error("Unexpected revised film length")
    for n in seq.narration
        n.label in ("scene_03", "b00b_direction") && continue
        n.samples == before[n.label] || error("Unchanged take changed: $(n.label)")
    end
    VE.enabletrackcache!(seq, PROJECT * ".frames")
    VE.saveproject(PROJECT, seq)
    job = VE.renderjob(PROJECT, REVISED; portable = false, hdr = false)
    mapping = vcat([n => n for n in 0:newstart-1], [n => n - shift for n in newend:total-1])
    carried = VE.carryframes!(job, original; frames = mapping)
    missing = [n for n in 0:total-1 if !VE.farmcomplete(REVISED, n, job.key)]
    missing == collect(newstart:newend-1) || error("Unchanged frames missing; refusing to render")
    all(samefile(VE.farmframepath(REVISED, n), VE.farmframepath(ORIGINAL, old)) for (n, old) in mapping) ||
        error("Expected the existing frames to share storage")
    report = Dict("original_job" => original.key, "job" => job.key,
        "original_frames" => original.total, "total_frames" => total,
        "reused_frames" => length(mapping), "new_frames" => count,
        "replacement_start" => newstart, "replacement_end_exclusive" => newend,
        "original_replaced_end_exclusive" => oldend, "timeline_shift_frames" => shift,
        "hardlinks_verified" => true, "unchanged_narration_verified" => true,
        "project" => PROJECT, "output" => OUTPUT)
    VE.farmwritejson(reportpath, report)
    println("PREPARED ", JSON.json(report), "; newly carried=", carried)
    flush(stdout)
    return job, report
end

function record(job, report; progress = (done, total) -> (println("NEW FRAMES $done/$total"); flush(stdout)))
    job.planes || error("This historical job is flattened; use render_farm.jl with a new directory to retain editable picture/label layers")
    allowed = report["replacement_start"]:report["replacement_end_exclusive"]-1
    # Preparation checks every checksum. On resume, unchanged frames must still
    # be the original hard links; they are never put in the render queue. The
    # ordinary encoder checks every finished frame's checksum again before use.
    for n in 0:job.total-1
        n in allowed && continue
        old = n < first(allowed) ? n : n - report["timeline_shift_frames"]
        path, source = VE.farmframepath(job.directory, n), VE.farmframepath(ORIGINAL, old)
        isfile(path) && isfile(source) && samefile(path, source) || error("An unchanged frame is missing; refusing to render")
    end
    missing = [n for n in allowed if !VE.farmcomplete(job.directory, n, job.key)]
    completed = report["new_frames"] - length(missing)
    progress(completed, report["new_frames"])
    isempty(missing) && return
    server = VE.FarmServer(; port = 0, bind = ip"127.0.0.1")
    log = open(joinpath(REVISED, "client-bosgame.log"), "a")
    client = nothing
    try
        launcher = joinpath(WORKSPACE, "BlackholeImage", "tools", "farm_client.jl")
        cache = joinpath(GEN, "farm", "client-revised-bosgame")
        cmd = `$(Base.julia_cmd()) --startup-file=no --compiled-modules=existing --project=$WORKSPACE $launcher 8060S $("127.0.0.1:$(server.port)") $cache`
        client = run(pipeline(addenv(cmd, "JULIA_NUM_THREADS" => "8", "JULIA_GLFW_PLATFORM" => "null"); stdout = log, stderr = log); wait = false)
        timedwait(() -> !isempty(VE.farmmachines(server)), 300) === :ok || error("Bosgame client did not connect")
        println("RENDERING ", length(missing), " replacement frames on Bosgame; ", report["reused_frames"], " frames reused")
        flush(stdout)
        status = VE.renderfarm!(job, VE.farmworkers(job, server); frames = missing, batchsize = 4,
            progress = (done, total) -> progress(completed + done, report["new_frames"]))
        status["completed"] == status["total"] && !status["paused"] || error("Render incomplete; resume the same job")
    finally
        close(server)
        if client !== nothing && process_running(client)
            kill(client)
            wait(client)
        end
        close(log)
        seq = VE.loadproject(PROJECT)
        VE.adoptfarmcache!(seq, job)
        VE.saveproject(PROJECT, seq)
    end
end

function main(mode = "all")
    job, report = prepare()
    mode == "prepare" && return
    mode in ("all", "encode") || error("Expected prepare, all or encode")
    mode == "all" && record(job, report)
    VE.encodefarm!(job.directory, OUTPUT; crf = 18, preset = "slow")
    println("COMPLETE ", OUTPUT)
    flush(stdout)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS...)
end
