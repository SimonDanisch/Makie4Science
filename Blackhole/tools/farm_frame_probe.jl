# Exercise the existing farm renderer in a fresh root-environment process.
# Keep its normal wire result so the coordinator can commit/adopt the frame
# through FarmWorker/renderfarm!, without retracing or constructing receipts.
root=dirname(something(Base.active_project(),""))
basename(root)=="Science4Makie" || error("Use the machine's Science4Makie root --project")
length(ARGS)==4 || error("usage: farm_frame_probe.jl JOB FRAME RESULT EXPECTED_KEY")
isfile(ARGS[3]) && error("Refusing to overwrite a completed probe result")

using VideoEditor
const VE=VideoEditor
VE.checkfarmroot(joinpath(ARGS[1],"job","environment","Project.toml"))
using RayMakie, GRMHDSnapshots, OIDNRunner
VE.usebackend!(RayMakie)
device_index=parse(Int,get(ENV,"SCIENCE_FARM_GPU","1"))
device=VE.Mantle.Device(VE.farmapi();select=device_index)
VE.Mantle.defaultdevice!(device)
println("FARM_PROBE_GPU index=",device_index," name=",VE.Mantle.devicename(device))
job=VE.RenderJob(ARGS[1])
job.key==ARGS[4] || error("Probe snapshot differs from the coordinator job")
frame=parse(Int,ARGS[2])
println("FARM_PROBE_START frame=",frame," job=",job.key)
flush(stdout)
renderer=VE.farmrenderer(job)
try
    # Match farmchild: opening the job can load newer scene/extension methods.
    result=only(Base.invokelatest(VE.farmframes!,renderer,[frame]))
    header,payload=VE.farmmessage(result)
    header["job"]=job.key
    mkpath(dirname(abspath(ARGS[3])))
    temporary,io=mktemp(dirname(abspath(ARGS[3])))
    try
        VE.sendmessage(io,header,payload)
        close(io)
        mv(temporary,ARGS[3])
    finally
        isopen(io) && close(io)
        isfile(temporary) && rm(temporary)
    end
    println("FARM_PROBE_PASS frame=",frame," seconds=",result.seconds,
        " bytes=",filesize(ARGS[3]))
    flush(stdout)
finally
    VE.closefarm!(renderer)
end
