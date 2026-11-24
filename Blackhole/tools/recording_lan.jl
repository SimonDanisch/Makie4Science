# Existing VideoEditor farm wire, with persistent GPU processes in the sole
# Science4Makie root. Parent transfers while its GPU child renders ahead.
module RecordingLAN
using Distributed, Sockets, Serialization, TOML
# The transfer parent needs only the existing standard-library wire codec, not
# a second GPU/package stack. The GPU child already has VideoEditor loaded.
include(joinpath(dirname(dirname(Base.find_package("VideoEditor"))),"FarmClient","src","wire.jl"))

readyfile(spool,n) = joinpath(spool,lpad(string(n),8,'0')*".ready")

function produce!(spool, frames, keep, bound, renderer=Main.renderer)
    VE = Main.VideoEditor
    for n in frames
        while count(f -> endswith(f,".ready"),readdir(spool)) >= bound
            isfile(joinpath(spool,"cancel")) && return nothing
            sleep(0.01)
        end
        isfile(joinpath(spool,"cancel")) && return nothing
        active=Set(c.id for c in VE.frameclips(renderer.sequence,n))
        for c in renderer.sequence.clips
            c.id in active && continue
            c.source.live===nothing && continue
            VE.close(c.source)
            c.source.hdr===nothing || (VE.freework!(c.source.hdr);c.source.hdr=nothing)
        end
        r=only(Base.invokelatest(VE.farmframes!,renderer,[n]))
        layers=[VE.FarmLayer(l.track,l.id,l.frame,l.png,
            (l.id,l.frame) in keep ? l.hdr : UInt8[]) for l in r.layers]
        message=VE.farmmessage((;r.frame,r.png,r.seconds,layers))
        file=readyfile(spool,n)
        serialize(file*".part",message)
        mv(file*".part",file)
        # Permit control/cleanup I/O between frames, not only at a GC pause.
        sleep(0.001)
    end
    return nothing
end

function streambatch!(socket, pid, frames, keep; bound=2)
    isempty(frames) && return nothing
    spool=mktempdir(;prefix="science4makie-farm-batch-")
    future=remotecall(produce!,pid,spool,frames,keep,bound)
    try
        for n in frames
            file=readyfile(spool,n)
            while !isfile(file)
                if isready(future)
                    fetch(future)
                    error("batch ended without frame $n")
                end
                sleep(0.005)
            end
            header,payload=deserialize(file)
            sendmessage(socket,header,payload)
            rm(file)
        end
        fetch(future)
    finally
        touch(joinpath(spool,"cancel"))
        # Do not remove the producer's directory while it can still write.
        try
            wait(future)
        catch
        end
        rm(spool;recursive=true)
    end
    return nothing
end

function serve!(pid, host, port, token, name, keep)
    socket=connect(host,port)
    try
        sendmessage(socket,Dict("token"=>token,"name"=>name,"protocol"=>FARM_PROTOCOL))
        ack,_=receivemessage(socket)
        get(ack,"accepted",false) || error("farm connection was not accepted")
        while !eof(socket)
            header,payload=receivemessage(socket)
            command=header["command"]
            command=="close" && break
            if command=="ping"
                sendmessage(socket,Dict("pong"=>true),payload)
                continue
            end
            command=="frames" || error("unknown farm command $command")
            try
                streambatch!(socket,pid,Int.(header["frames"]),keep)
            catch err
                sendmessage(socket,Dict("error"=>sprint(showerror,err)))
                rethrow()
            end
        end
    finally
        close(socket)
        try
            remotecall_fetch(pid) do
                Base.invokelatest(Main.VideoEditor.closefarm!,Main.renderer)
            end
        catch err
            @warn "GPU renderer cleanup" pid exception=(err,catch_backtrace())
        end
    end
    return nothing
end
end
