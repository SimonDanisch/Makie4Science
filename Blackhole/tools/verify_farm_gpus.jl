# Include after project.jl and farm_bench.jl, in the ONE application root.
# Diagnostic jobs only: every connected GPU must render, not merely connect.
function verify_farm_gpus(project,directory;server=VE.farmserver())
    expected=length(VE.farmmachines(server)) # clients select one hardware GPU each
    inputs=scene_inputs()
    root=dirname(dirname(@__FILE__))
    discovery=VE.renderjob(project,joinpath(directory,"discovery");inputs,root)
    workers=VE.FarmWorker[]
    results=Dict{String,Any}()
    report_lock=ReentrantLock()
    try
        # Separate ordinary job coordinators let the slow first Metal compile
        # run concurrently without blocking the other GPUs' verification.
        @sync for worker in VE.farmworkers(discovery,server)
            push!(workers,worker)
            # Arrival order can change on resume. Never credit a previous
            # machine's receipt to the GPU which happens to arrive first now.
            id=bytes2hex(VE.SHA.sha256(worker.name))[1:16]
            job=VE.renderjob(project,joinpath(directory,"gpu-$id");inputs,root)
            job.key==discovery.key || error("Diagnostic snapshots differ")
            @async begin
                try
                    status=VE.renderfarm!(job,[worker];frames=[1],retries=1)
                    receipt=VE.JSON.parsefile(VE.farmreceiptpath(job.directory,1))
                    receipt["worker"]==worker.name || error("Receipt belongs to another GPU")
                    pixels=VE.PNGFiles.load(VE.farmframepath(job.directory,1))
                    any(p->p.r>0 || p.g>0 || p.b>0,pixels) || error("GPU returned an empty picture")
                    result=Dict("gpu"=>worker.name,"completed"=>status["completed"],
                        "seconds"=>receipt["seconds"],"directory"=>job.directory)
                    println("VERIFIED GPU ",worker.name," ",receipt["seconds"]," s");flush(stdout)
                catch e
                    result=Dict("gpu"=>worker.name,"error"=>sprint(showerror,e))
                    println("GPU ERROR ",worker.name,": ",sprint(showerror,e));flush(stdout)
                end
                lock(report_lock) do
                    results[worker.name]=result
                    open(io->VE.TOML.print(io,Dict("verification"=>collect(values(results)))),
                        joinpath(directory,"gpu-verification.toml"),"w")
                end
            end
        end
    finally
        foreach(w->try VE.closeworker!(w) catch end,workers)
    end
    isempty(workers) && error("No farm GPU opened")
    any(r->haskey(r,"error"),values(results)) && error("A GPU failed verification; see gpu-verification.toml")
    length(workers)>=expected || error("Only $(length(workers)) of $expected clients opened a GPU; inspect client startup logs")
    return results
end
