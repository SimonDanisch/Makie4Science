# Persistent transfer parent; independent of the interactive eval/control session.
using Serialization
root=dirname(Base.active_project())
basename(root)=="Science4Makie" || error("Use the sole Science4Makie root")
length(ARGS)==1 || error("Expected a private one-use worker bootstrap")
config=deserialize(only(ARGS));rm(only(ARGS))
include("recording_multigpu.jl")
include("recording_lan.jl")
slots=start_recording_gpus!(config.project,[config.gpu];assets=config.assets,application=config.application)
try
    for pid in slots
        remotecall_fetch(Core.eval,pid,Main,:(include($(joinpath(@__DIR__,"recording_lan.jl")))))
    end
    println("LAN WORKER READY GPU ",config.gpu);flush(stdout)
    RecordingLAN.serve!(only(slots),config.host,config.port,config.token,config.name,config.keep)
finally
    rmprocs(slots)
end
