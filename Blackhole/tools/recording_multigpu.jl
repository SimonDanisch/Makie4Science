# Additional processes use the same application root, one process per GPU.
# Frame rendering and HDR retention stay in recording_farm.jl.
using Distributed

struct RecordingGPUTransport{R}
    session::R
    process::Int
end

function (transport::RecordingGPUTransport)(f, args...)
    reply = transport.session(transport.process, f, args) do pid, callback, arguments
        Distributed.remotecall_fetch(pid, callback, arguments) do callback, arguments
            try
                result = Base.invokelatest(callback, arguments...)
                # Keep the relay session free of renderer package types and GPU state.
                result === nothing && return nothing
                map(VE.farmmessage, result)
            catch err
                (error=sprint(showerror,err,catch_backtrace()),)
            end
        end
    end
    reply === nothing && return nothing
    reply isa NamedTuple && hasproperty(reply,:error) && error(reply.error)
    return [VE.farmresult(header,payload) for (header,payload) in reply]
end

function recording_display!()
    Sys.islinux() || return
    # The eval bridge does not inherit the logged-in desktop's display.
    for line in split(read(`systemctl --user show-environment`, String), '\n')
        occursin('=', line) || continue
        name, value = split(line, '='; limit=2)
        name in ("DISPLAY", "XAUTHORITY") && (ENV[name] = value)
    end
end

function recording_slot_expression(project, cache; gpu=nothing, assets=nothing, application=dirname(project))
    source = "/home/sim/Programmieren/Science4Makie/BlackholeImage"
    mapping = Dict(source => application)
    assets === nothing || (mapping[joinpath(source, "assets")] = assets)
    return quote
        using VideoEditor, RayMakie, GRMHDSnapshots, OIDNRunner
        const VE = VideoEditor
        VE.usebackend!(RayMakie)
        if $gpu !== nothing
            device = VE.Mantle.Device(VE.farmapi(); select=$gpu)
            VE.Mantle.defaultdevice!(device)
            println("RECORDING GPU ", VE.Mantle.devicename(device)); flush(stdout)
        end
        sequence = VE.loadproject($project; pathmap=$mapping)
        renderer = VE.farmrenderer(sequence; directory=$cache)
        (; process=getpid(), project=Base.active_project())
    end
end

function start_recording_gpus!(project, gpus; assets=nothing, application=dirname(project))
    root = dirname(Base.active_project())
    basename(root) == "Science4Makie" || error("Use the Science4Makie root")
    recording_display!()
    processes = addprocs(length(gpus); exeflags=["--project=$root",
        "--compiled-modules=existing", "--heap-size-hint=3G", "--threads=4"],
        env=[name => ENV[name] for name in ("DISPLAY", "XAUTHORITY") if haskey(ENV,name)])
    for (pid, gpu) in zip(processes, gpus)
        expression = recording_slot_expression(project,
            joinpath(root,"BlackholeImage","renders","recording-rpc-gpu-$gpu"); gpu, assets, application)
        println("START GPU ",gpu," process ",pid); flush(stdout)
        remotecall_fetch(Core.eval, pid, Main, expression)
    end
    return processes
end
