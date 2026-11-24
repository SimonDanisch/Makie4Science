# Existing VE composition/encoding, with an isolated resumable output cache.
ENV["JULIA_GLFW_PLATFORM"]="null"
include(joinpath(@__DIR__,"..","project.jl"))
using FileIO
import Mantle, OIDNRunner

const RECORD_DIR=normpath(joinpath(@__DIR__,"..","renders","recording_1080p_20261023"))
const RECORD_PROJECT=joinpath(RECORD_DIR,"film_1080p.videoedit")
const RECORD_OUTPUT=joinpath(RECORD_DIR,"black_hole_1080p.mp4")

function prepare_recording()
    isfile(RECORD_PROJECT) && return VE.loadproject(RECORD_PROJECT)
    seq=VE.loadproject(joinpath(@__DIR__,"..","renders","keyframed_20261023","film.videoedit"))
    empty!(seq.trackcaches);seq.compositecache=nothing
    seq.canvas=(1920,1080)
    for clip in seq.clips
        src=clip.source
        src isa VE.SceneSource || continue
        resize!(src,(1920,1080))
        src.screenopts[:px_per_unit]=1.5
        src.bakescreenopts[:px_per_unit]=1.5
        beat=get(src.build["args"],"beat","")
        if !get(src.bakescreenopts,:rasterize,true)
            src.bakescreenopts[:samples]=beat in ("a1_black_hole","a2_two_numbers") ? 8 : 256
        end
        clip.bake=nothing
        clip.graph=nothing
    end
    VE.enabletrackcache!(seq,RECORD_PROJECT*".frames")
    VE.saveproject(RECORD_PROJECT,seq;checkpoint=false)
    return seq
end

# Finished planes retain every frame. Only this NEW recording's intermediate
# masters are rolling: keep the newest one per clip for exact still reuse.
function trim_recording_hdr!(seq)
    for clip in seq.clips
        cache=VE.sourcecache(clip)
        cache===nothing && continue
        frames=get(cache.valid,clip.id,BitSet())
        length(frames)<=1 && continue
        keep=last(frames)
        for sf in collect(frames)
            sf==keep && continue
            file=VE.cachefile(cache,clip.id,sf)
            startswith(abspath(file),abspath(RECORD_PROJECT*".frames")*"/") || error("cache outside recording")
            rm(file;force=true)
            delete!(frames,sf)
            delete!(get(cache.dirty,clip.id,BitSet()),sf)
            delete!(cache.revisions,(clip.id,sf))
        end
    end
end

function record_1080p(;preflight=false)
    mkpath(RECORD_DIR)
    VE.usebackend!(RayMakie)
    seq=prepare_recording()
    engine=VE.FxEngine(Mantle.defaultbackend())
    readers=Dict{String,Any}()
    out=zeros(VE.RGB{VE.N0f8},1920,1080)
    started=time()
    active=Set{UInt64}()
    frames=preflight ? [1330,18160] : (0:VE.seqlength(seq)-1)
    try
        VE.withfinalscenes(seq) do
            for n in frames
                current=Set(c.id for c in VE.frameclips(seq,n))
                for c in seq.clips
                    c.id in active && !(c.id in current) || continue
                    close(c.source)
                end
                active=current
                VE.renderframe!(out,seq,n,readers,engine)
                @assert size(out)==(1920,1080)
                if preflight
                    for c in VE.frameclips(seq,n)
                        c.source.live===nothing && continue
                        @assert c.source.live.canvas==(1280,720)
                    end
                    @assert maximum(c->max(c.r,c.g,c.b),out)>0.15
                    save(joinpath(RECORD_DIR,"preflight_$n.png"),permutedims(out))
                end
                trim_recording_hdr!(seq)
                if preflight || n%30==0
                    VE.saveproject(RECORD_PROJECT,seq;checkpoint=false)
                    println("RECORD ",n+1,"/",VE.seqlength(seq)," elapsed_min=",round((time()-started)/60;digits=1));flush(stdout)
                end
                if n%300==0
                    GC.gc();yield()
                    Sys.free_memory()>8*1024^3 || error("Stopped safely: system memory below 8 GiB")
                    Base.Filesystem.diskstat(RECORD_DIR).available>16*1024^3 || error("Stopped safely: disk space below 16 GiB")
                end
                yield()
            end
        end
    finally
        VE.saveproject(RECORD_PROJECT,seq;checkpoint=false)
        VE.emptyengine!(engine)
        foreach(close,values(readers))
        foreach(c->close(c.source),seq.clips)
    end
    preflight && return RECORD_PROJECT
    println("All frames recorded; exporting with original narration");flush(stdout)
    VE.exportvideo(RECORD_OUTPUT,seq;encoder_options=(crf=18,preset="medium"),
        progress=(done,total)->(done%300==1 && (println("ENCODE ",done,"/",total);flush(stdout))))
    VE.saveproject(RECORD_PROJECT,seq;checkpoint=false)
    println("DONE ",RECORD_OUTPUT);flush(stdout)
    return RECORD_OUTPUT
end

if abspath(PROGRAM_FILE)==@__FILE__
    record_1080p(;preflight="--preflight" in ARGS)
end
