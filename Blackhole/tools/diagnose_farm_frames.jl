# Diagnostic only: existing native renderer, unchanged quality, no project adoption.
root=dirname(something(Base.active_project(),""))
basename(root)=="Science4Makie" || error("Use the machine's Science4Makie root")
length(ARGS)==3 || error("usage: diagnose_farm_frames.jl JOB FRAME[,FRAME...] OUTPUT_DIRECTORY")
using VideoEditor, RayMakie, Hikari, GRMHDSnapshots, OIDNRunner
const VE=VideoEditor
VE.usebackend!(RayMakie)
device_index=parse(Int,get(ENV,"SCIENCE_FARM_GPU","1"))
device=VE.Mantle.Device(VE.farmapi();select=device_index)
VE.Mantle.defaultdevice!(device)
println("DIAGNOSTIC_GPU index=",device_index," name=",VE.Mantle.devicename(device))
job=VE.RenderJob(ARGS[1])
frames=parse.(Int,split(ARGS[2],','))
1<=length(frames)<=8 || error("Use a bounded diagnostic batch")
output=abspath(ARGS[3])
mkpath(output)
function checkpoint(label)
    rss=Sys.islinux() ? join(filter(l->startswith(l,"VmRSS:")||startswith(l,"VmHWM:"),
        readlines("/proc/self/status"))," ") : strip(read(`ps -o rss= -p $(getpid())`,String))
    println("CHECKPOINT ",label," rss=",rss," maxrss=",Sys.maxrss(),
        " live_bytes=",Base.gc_live_bytes()," time=",time())
    flush(stdout)
end
println("DIAGNOSTIC_ONLY job=",job.key," frames=",frames," project=",Base.active_project())
checkpoint("packages_loaded")
renderer=VE.farmrenderer(job)
checkpoint("renderer_open")
try
    # Explicit diagnostic A/B only: replace this one method in the loaded
    # recipe module, never edit an immutable job snapshot or create receipts.
    sampler_source=get(ENV,"SCIENCE_FARM_DIAGNOSTIC_SAMPLER","")
    if !isempty(sampler_source)
        source=read(sampler_source,String)
        a=first(findfirst("@inline function sample_density(",source))
        b=first(findnext("\nfunction Hikari.sample_point(",source,a))
        definition=Meta.parse(source[a:prevind(source,b)])
        count=0
        for clip in renderer.sequence.clips
            clip.source isa VE.SceneSource || continue
            program=clip.source.root
            program isa VE.SceneProgram || continue
            get(program.args,"beat","")=="a1_black_hole" || continue
            builder=Base.invokelatest(VE.programbuilder!,program)
            Core.eval(parentmodule(builder),definition)
            count+=1
        end
        count>0 || error("No a1 recipe module patched for diagnostic")
        println("DIAGNOSTIC_SAMPLER_OVERRIDE modules=",count," source=",sampler_source)
        flush(stdout)
    end
    for frame in frames
        checkpoint("before_frame_"*string(frame))
        measured=@timed only(Base.invokelatest(VE.farmframes!,renderer,[frame]))
        result=measured.value
        checkpoint("after_frame_"*string(frame))
        println("FRAME_DONE frame=",frame," seconds=",measured.time,
            " allocated_bytes=",measured.bytes," gc_seconds=",measured.gctime)
        # Keep the native bytes for inspection; this is NOT a committed farm receipt.
        path=joinpath(output,lpad(frame,6,'0')*".wire")
        isfile(path) && error("Refusing to overwrite diagnostic result: $path")
        header,payload=VE.farmmessage(result)
        header["job"]=job.key
        open(path,"w") do io
            VE.sendmessage(io,header,payload)
        end
        result=nothing; measured=nothing; header=nothing; payload=nothing
        if get(ENV,"SCIENCE_FARM_DEBUG_GC","0")=="1"
            GC.gc(true)
            checkpoint("after_gc_"*string(frame))
        end
    end
catch
    # A postprocess can fail after tracing has already completed. Save As uses
    # the editor's native cache transfer before closefarm! clears its temporary
    # planes, retaining the expensive HDR master for a normal resumed export.
    recovery=joinpath(output,"interrupted.videoedit")
    VE.saveproject(recovery,renderer.sequence)
    println("DIAGNOSTIC_RECOVERY_PROJECT ",recovery)
    flush(stdout)
    rethrow()
finally
    VE.closefarm!(renderer)
end
checkpoint("finished")
