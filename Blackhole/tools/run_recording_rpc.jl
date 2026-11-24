# Persistent coordinator: authenticated relay for startup, native LAN farm wire
# for frame data. No GPU renderer runs in this coordinator process.
# The one-use bootstrap file is private and removed as soon as it is read.
using Serialization, Sockets, Random
root = dirname(Base.active_project())
basename(root) == "Science4Makie" || error("Use the application root")
length(ARGS) == 1 || error("usage: run_recording_rpc.jl PRIVATE_BOOTSTRAP")
bootstrap = deserialize(ARGS[1])
rm(ARGS[1])
include(bootstrap.helper)
BonitoMCPHelper.set_value_relay!(bootstrap.address, bootstrap.token)
using .BonitoMCPHelper
using VideoEditor, RayMakie, GRMHDSnapshots, OIDNRunner
const VE = VideoEditor
include("recording_farm.jl")
include("recording_multigpu.jl")
include("farm_policy.jl")
project = get(bootstrap,:project,joinpath(root,"BlackholeImage","renders","recording_1080p_20261023","film_1080p.videoedit"))
jobdir = get(bootstrap,:jobdir,joinpath(root,"BlackholeImage","renders","farm","recording_1080p_native_20261023"))
output = get(bootstrap,:output,joinpath(dirname(project),"black_hole_1080p.mp4"))
include(joinpath(@__DIR__,"..","farm_bench.jl"))
seq = VE.loadproject(project)
keep = held_masters(seq)
remotes = Pair{String,Any}[]
listener = listen(ip"0.0.0.0",0)
port = Int(getsockname(listener)[2])
host = get(bootstrap,:lanhost,string(getipaddr()))
token = bytes2hex(rand(RandomDevice(),UInt8,32))
for node in bootstrap.nodes
    ScienceFarmPolicy.allowed(node.worker) || error("$(node.worker) is excluded from the render pool")
    session = remote_session(node.worker;env_path=node.root)
    name=node.name
    started=session(node,host,port,token,keep) do node,host,port,token,keep
        serial=Base.require(Base.PkgId(Base.UUID("9e88b42a-f829-5b0c-bbe9-9e923198166b"),"Serialization"))
        root=dirname(Base.active_project())
        app=joinpath(root,"recording-corrections-20261024","application")
        assets=node.worker=="Desktop" ? joinpath(root,"recording-deploy-20261023","application","assets") : joinpath(root,"BlackholeImage","assets")
        private,io=mktemp();chmod(private,0o600)
        serial.serialize(io,(project=joinpath(app,"recording.videoedit"),application=app,assets=assets,
            gpu=node.gpu,host=host,port=port,token=token,name=node.name,keep=keep));close(io)
        logfile=joinpath(root,"BlackholeImage","renders","lan-worker-$(node.gpu).log")
        mkpath(dirname(logfile))
        exe=joinpath(Sys.BINDIR,Base.julia_exename())
        runner=joinpath(app,"tools","recording_lan_runner.jl")
        cmd=Cmd(`$exe --project=$root --compiled-modules=existing --threads=2 $runner $private`;detach=true)
        # Offscreen Vulkan does not require a logged-in X11 desktop. Use
        # GLFW's supported null platform on Linux, as on the coordinator.
        Sys.islinux() && (cmd=addenv(cmd,"JULIA_GLFW_PLATFORM"=>"null"))
        process=run(pipeline(cmd;stdin=devnull,stdout=logfile,stderr=logfile);wait=false)
        (;pid=getpid(process),log=logfile)
    end
    println("STARTED ",name," pid ",started.pid," log ",started.log);flush(stdout)
end
waiting=Dict(n.name=>n for n in bootstrap.nodes)
for _ in bootstrap.nodes
        # Bound startup/handshake so an unreachable LAN never looks like work.
        watchdog=Timer(600) do _
            isopen(listener) && close(listener)
        end
        socket=accept(listener)
        auth,_=VE.receivemessage(socket)
        name=String(get(auth,"name",""))
        if get(auth,"token","")!=token || !haskey(waiting,name) || get(auth,"protocol",0)!=VE.FARM_PROTOCOL
            close(socket)
            error("Unauthenticated farm connection")
        end
        node=pop!(waiting,name)
        close(watchdog)
        VE.sendmessage(socket,Dict("accepted"=>true))
        bytes=rand(UInt8,2_000_000)
        elapsed=@elapsed begin
            VE.sendmessage(socket,Dict("command"=>"ping"),bytes)
            pong,echo=VE.receivemessage(socket)
            get(pong,"pong",false) && echo==bytes || error("LAN integrity probe failed")
        end
        println("LAN ",name," 2 MB round trip ",round(elapsed;digits=4)," s");flush(stdout)
        println("READY ",name," GPU ",node.gpu); flush(stdout)
        push!(remotes,name=>VE.FarmSlot(name,socket))
end
close(listener)
allowed = BitSet(n for n in 0:VE.seqlength(seq)-1 if
    all(c -> !(get(get(c.source.build,"args",Dict()),"beat","") in ("a1_black_hole","a2_two_numbers")),
        VE.frameclips(seq,n)))
# With the restored atmosphere the Earth shots allocate volume queues too.
# The 8 GB Legion helps on raster work; larger GPUs take the traced scenes.
if get(bootstrap,:legion_raster_only,false)
    allowed=BitSet(n for n in allowed if all(c->!VE.traced(c.source),VE.frameclips(seq,n)))
end
println("LAN BATCH FARM START ",first.(remotes)); flush(stdout)
# Black-hole frames on Legion only when explicitly requested for a job.
restrictions = get(bootstrap,:legion_blackhole,false) ? Dict{String,BitSet}() : Dict("legion-boi"=>allowed)
run_recording_farm(project,jobdir,output,remotes;
    restrictions,
    frames=get(bootstrap,:frames,nothing),export_movie=get(bootstrap,:export_movie,true))
