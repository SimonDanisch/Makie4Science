# Native cached review after the farm's missing frames have been adopted.
# All pictures, labels and composition are the ordinary VideoEditor pipeline.
function review_cached_final(seq,frames;dir,project=nothing)
    wanted=sort!(unique(Int.(collect(frames))))
    missing=VE.farmneededframes(seq;frames=wanted)
    isempty(missing) || error("Final preflight still needs farm frames: $missing")
    mkpath(dir)
    counters=IdDict(c.source=>c.source.renders for c in values(seq.trackcaches) if c.source!==nothing)
    engine=VE.FxEngine(Mantle.defaultbackend())
    readers=Dict{String,Any}()
    pixels=zeros(VE.RGB{VE.N0f8},seq.canvas...)
    paths=String[]
    try
        VE.withfinalscenes(seq) do
            for n in wanted
                VE.renderframe!(pixels,seq,n,readers,engine)
                path=joinpath(dir,string(n;pad=6)*".png")
                VE.PNGFiles.save(path,permutedims(pixels))
                push!(paths,path)
            end
        end
        all(cache.renders==before for (cache,before) in counters) ||
            error("Cached review unexpectedly captured a new HDR master")
    finally
        VE.emptyengine!(engine)
        foreach(close,values(readers))
        project===nothing || VE.saveproject(project,seq)
    end
    return paths
end

"Makie-rendered contact sheets of the native review PNGs, for layout inspection."
function final_contact_sheets(seq,paths;dir)
    mkpath(dir)
    outputs=String[]
    for first in 1:6:length(paths)
        fig=Makie.Figure(size=(1920,830),backgroundcolor=:black,figure_padding=16)
        for (k,path) in enumerate(paths[first:min(first+5,length(paths))])
            n=parse(Int,splitext(basename(path))[1])
            clip=only(filter(c->c.track==1,VE.frameclips(seq,n)))
            name=clip.source.build["args"]["beat"]
            seconds=round(VE.sourceframe(clip,n)/seq.framerate;digits=1)
            ax=Makie.Axis(fig[(k-1)÷3+1,(k-1)%3+1];aspect=Makie.DataAspect(),
                title="$name @ $(seconds)s",titlecolor=:white,titlesize=18,backgroundcolor=:black)
            Makie.hidedecorations!(ax);Makie.hidespines!(ax)
            Makie.image!(ax,rotr90(VE.PNGFiles.load(path)))
        end
        screen=RayMakie.Screen(fig.scene;rasterize=true)
        path=joinpath(dir,"sheet_$(lpad((first-1)÷6+1,2,'0')).png")
        try
            FileIO.save(path,Makie.colorbuffer(screen))
        finally
            close(screen)
        end
        push!(outputs,path)
    end
    outputs
end
