# Two bounded raster frames through ordinary VE composition, in the migrated
# project's native cache. No full-film export and no renderer overrides.
include(joinpath(@__DIR__,"..","project.jl"))
using FileIO

function check_native_tracks_render(project)
    VE.usebackend!(RayMakie)
    seq=VE.loadproject(project)
    clip=only(filter(c->c.track==1 && get(c.source.build["args"],"beat","")=="c3_outro",seq.clips))
    @assert get(clip.source.bakescreenopts,:rasterize,true)
    engine=VE.FxEngine(VE.Mantle.defaultbackend())
    readers=Dict{String,Any}()
    out=zeros(VE.RGB{VE.N0f8},seq.canvas...)
    try
        for sf in unique(min.([100,360],clip.src_out-1))
            n=clip.start+sf-clip.src_in
            VE.renderframe!(out,seq,n,readers,engine)
            @assert maximum(c->max(c.r,c.g,c.b),out)>0.2
            file=joinpath(dirname(project),"native_outro_$sf.png")
            save(file,permutedims(out))
            println("Rendered native-track frame ",n," -> ",file)
        end
        VE.saveproject(project,seq;checkpoint=false)
    finally
        VE.emptyengine!(engine)
        foreach(close,values(readers))
        foreach(c->close(c.source),seq.clips)
    end
end

length(ARGS)==1 && check_native_tracks_render(only(ARGS))
