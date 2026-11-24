# julia --project=/path/to/Science4Makie tools/farm_client.jl <gpus> <host:port> [cache-directory]
# This application's workers must never create a package environment per job.
module ScienceFarmLauncher
const PROJECT_ROOT=let project=Base.active_project()
    project===nothing && error("Start this client with --project=/path/to/Science4Makie")
    root=dirname(project)
    basename(root)=="Science4Makie" || error("Use the machine's Science4Makie root project")
    root
end
const EDITOR_SOURCE=Base.find_package("VideoEditor")
EDITOR_SOURCE===nothing && error("Provision VideoEditor in the Science4Makie root first")
include(normpath(joinpath(dirname(EDITOR_SOURCE),"..","FarmClient","src","FarmClient.jl")))

"A soft GC target for small shared hosts, not an image-quality or hard memory limit."
function workerheap(;memory=Sys.total_memory(),explicit=Base.JLOptions().heap_size_hint)
    explicit>0 && return string(explicit)
    memory>64*1024^3 && return nothing
    return string(clamp(Int(memory÷(8*1024^3)),1,4),"G")
end

function client(args;heap_size_hint=workerheap(),compiled_modules="existing")
    length(args) in (2,3) || throw(ArgumentError("usage: farm_client.jl <gpus> <host:port> [cache-directory]"))
    dirname(Base.active_project())==PROJECT_ROOT || error("The application root changed")
    cache=length(args)==3 ? abspath(args[3]) : joinpath(homedir(),".videoeditor","farm")
    c=FarmClient.Client(args[1],args[2];project=PROJECT_ROOT,root=cache)
    compiled_modules in ("yes","no","existing","strict") ||
        throw(ArgumentError("Unknown Julia package-image mode: $compiled_modules"))
    command=[joinpath(Sys.BINDIR,Base.julia_exename()),"--compiled-modules="*compiled_modules]
    if heap_size_hint!==nothing
        # The farm already caches version-specific Julia commands. This is the
        # same installed version, with an explicit GC option inherited by its
        # renderer children. No new package environment or code pin is needed.
        push!(command,"--heap-size-hint="*heap_size_hint)
    end
    # Do not run unrelated ML packages' precompile workloads during worker
    # startup. Existing images are reused; uncached code is loaded normally.
    c.juliacmds[string(VERSION)]=Cmd(command)
    return c
end
"Let child renderers parallelize snapshot preparation; preserve an explicit user setting."
function workerthreads!(env=ENV; cpus=Sys.CPU_THREADS)
    get!(env,"JULIA_NUM_THREADS",string(clamp(cpus÷2,1,8)))
end
"Avoid parallel package-image startup peaks on small shared hosts."
function workerprecompile!(env=ENV;memory=Sys.total_memory())
    haskey(env,"JULIA_NUM_PRECOMPILE_TASKS") && return env["JULIA_NUM_PRECOMPILE_TASKS"]
    memory>64*1024^3 && return nothing
    env["JULIA_NUM_PRECOMPILE_TASKS"]="1"
end
function main(args=ARGS)
    workerthreads!()
    workerprecompile!()
    FarmClient.serve(client(args))
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    ScienceFarmLauncher.main()
end
