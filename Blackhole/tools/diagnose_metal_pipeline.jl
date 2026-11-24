# Compile saved native shader bytes only; no scene/image renderer or cache writes.
basename(dirname(something(Base.active_project(),"")))=="Science4Makie" || error("Use the application root")
length(ARGS) in (2,3) || error("usage: diagnose_metal_pipeline.jl ARTIFACT_BASE private|visible [MAX_THREADS]")
using Metal, Mantle
using Metal.ObjectiveC.Foundation: NSArray
const MTL=Metal.MTL
mode=ARGS[2]
mode in ("private","visible") || error("Unknown linked-function mode")
dev=Mantle.Device(Mantle.MetalAPI())
Mantle.ensure_traversal_linked!(dev)
lib=MTL.MTLLibraryFromData(dev.dev,read(ARGS[1]*".metallib"))
fun=MTL.MTLFunction(lib,"mantle__gpu_workqueue_map_kernel_")
desc=MTL.MTLComputePipelineDescriptor()
desc.computeFunction=fun
desc.supportIndirectCommandBuffers=true
length(ARGS)==3 && (desc.maxTotalThreadsPerThreadgroup=parse(UInt64,ARGS[3]))
linked=Metal.linked_functions_for(dev.dev)
lf=MTL.MTLLinkedFunctions()
mode=="private" ? (lf.privateFunctions=NSArray(linked)) : (lf.functions=NSArray(linked))
desc.linkedFunctions=lf
desc.maxCallStackDepth=4
println("PIPELINE_BEGIN mode=",mode," max_threads=",desc.maxTotalThreadsPerThreadgroup,
    " functions=",[String(f.name) for f in linked])
flush(stdout)
elapsed=@elapsed pipeline=MTL.MTLComputePipelineState(dev.dev,desc)
println("PIPELINE_PASS mode=",mode," seconds=",elapsed)
flush(stdout)
