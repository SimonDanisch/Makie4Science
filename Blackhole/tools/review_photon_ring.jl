# Include after project.jl, using only the Science4Makie root environment.
# The caller supplies a saved-as project sharing the completed native caches.
import Mantle, Makie, OIDNRunner

function review_photon_ring!(project; fractions=(0.2,0.5,0.8))
    VE.usebackend!(RayMakie)
    seq=VE.loadproject(project)
    beat(c)=get(c.source.build["args"],"beat","")=="a1_black_hole"
    picture=only(c for c in seq.clips if c.track==1 && beat(c))
    labels=only(c for c in seq.clips if c.track==2 && beat(c))
    @assert all(VE.cachevalid(VE.trackcache(picture),picture.id,sf)
                for sf in picture.src_in:picture.src_out-1)
    film=loadfilm()
    built=Base.invokelatest(Base.invokelatest(getproperty,film,:buildscene),seq.canvas,labels.source.build["args"])
    try
        path=Base.invokelatest(getproperty,film,:NATIVE_PATHS)[("a1_black_hole",:labels)]["ring_label"]
        param=only(p for p in VE.findslot(labels,:scene).params if String(p.name)==path)
        lit=[sf for sf in labels.src_in:labels.src_out-1 if VE.valueat(param.curve[],sf)>0.99]
        @assert !isempty(lit)
        frames=[labels.start+lit[clamp(round(Int,1+f*(length(lit)-1)),1,length(lit))] for f in fractions]
        # Only the raster annotation recipe changed. Never invalidate beauty.
        VE.invalidateclip!(labels)
        labels.source.root=VE.SceneProgram(labels.source.build)
        labels.source.live=nothing
        VE.bindcacheparams!(labels,VE.findslot(labels,:scene))
        VE.saveproject(project,seq;checkpoint=false)
        dir=joinpath(dirname(project),"review");mkpath(dir)
        pixels=zeros(VE.RGB{VE.N0f8},seq.canvas...)
        readers=Dict{String,Any}()
        engine=VE.FxEngine(Mantle.defaultbackend())
        files=String[]
        try
            VE.withfinalscenes(seq) do
                for n in frames
                    sf=VE.sourceframe(picture,n)
                    @assert VE.cachevalid(VE.trackcache(picture),picture.id,sf)
                    VE.renderframe!(pixels,seq,n,readers,engine)
                    file=joinpath(dir,"photon_ring_$(n).png")
                    VE.PNGFiles.save(file,permutedims(pixels));push!(files,file)
                    println("RING REVIEW ",file);flush(stdout)
                end
            end
        finally
            VE.emptyengine!(engine);foreach(close,values(readers))
            VE.saveproject(project,seq;checkpoint=false)
        end
        @assert all(VE.cachevalid(VE.trackcache(picture),picture.id,sf)
                    for sf in picture.src_in:picture.src_out-1)
        println("Reused all ",VE.srclength(picture)," black-hole beauty planes; no beauty invalidated")
        return files
    finally
        Makie.free(built.scene)
        for c in seq.clips
            c.source isa VE.SceneSource && c.source.live!==nothing && close(c.source)
        end
    end
end

"Short, silent 0.8× motion test: native cached pictures, no holds or interpolation."
function photon_ring_motion!(baseline,project)
    VE.usebackend!(RayMakie)
    seq=VE.loadproject(baseline)
    filter!(c->get(c.source.build["args"],"beat","")=="a1_black_hole",seq.clips)
    empty!(seq.narration);empty!(seq.captions);empty!(seq.transitions)
    picture=only(c for c in seq.clips if c.track==1)
    labels=only(c for c in seq.clips if c.track==2)
    # Original footage during the photon-ring explanation, before any frozen
    # editorial holds were inserted into the corrected delivery.
    args=picture.source.build["args"]
    firstframe=round(Int,(args["starts"][4]+0.55*(args["ends"][4]-args["starts"][4]))*seq.framerate)
    lastframe=round(Int,args["starts"][5]*seq.framerate)
    before=VE.trackcache(picture)
    files=Dict(sf=>VE.cachefile(before,picture.id,sf) for sf in firstframe:lastframe-1)
    @assert all(VE.cachevalid(before,picture.id,sf) for sf in keys(files))
    for c in seq.clips
        c.src_in=firstframe;c.src_out=lastframe;c.start=0;c.rate=0.8;c.timeinterp=:sample
    end
    # Keep the original camera keys. Replace only the annotation performance.
    film=loadfilm()
    built=Base.invokelatest(Base.invokelatest(getproperty,film,:buildscene),seq.canvas,labels.source.build["args"])
    paths=Base.invokelatest(getproperty,film,:NATIVE_PATHS)[("a1_black_hole",:labels)]
    filter!(p->startswith(String(p.name),"camera."),VE.findslot(labels,:scene).params)
    for (name,path) in paths
        VE.keyframes!(labels,path,[(0,name=="ring_label" ? 1.0 : 0.0,:hold)])
    end
    Makie.free(built.scene)
    labels.source.root=VE.SceneProgram(labels.source.build);labels.source.live=nothing
    empty!(seq.trackcaches);seq.compositecache=nothing
    mkpath(dirname(project));VE.enabletrackcache!(seq,project*".frames")
    VE.bindcacheparams!(labels,VE.findslot(labels,:scene))
    for (sf,file) in files
        VE.linkplane!(VE.trackcache(picture),picture.id,sf,file)
    end
    VE.saveproject(project,seq;checkpoint=false)
    output=joinpath(dirname(project),"photon_ring_08x.mp4")
    try
        VE.withfinalscenes(seq) do
            VE.exportvideo(output,seq;encoder_options=(crf=18,preset="medium"))
        end
    finally
        VE.saveproject(project,seq;checkpoint=false)
        foreach(c->c.source.live===nothing || close(c.source),seq.clips)
    end
    @assert all(VE.cachevalid(VE.trackcache(picture),picture.id,sf) for sf in keys(files))
    println("MOTION REVIEW ",output,"; ",length(files)," original cached pictures, 0.8x, sample-only")
    return output
end
