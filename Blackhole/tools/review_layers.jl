# Raster contact review of the complete edit, isolated from final trace caches.
using VideoEditor, RayMakie, Mantle
import VideoEditor as VE

function reviewlayers(project; dir = joinpath(dirname(project), "renders", "layer_review"))
    VE.usebackend!(RayMakie)
    seq = VE.loadproject(project)
    empty!(seq.trackcaches); seq.compositecache = nothing
    VE.enabletrackcache!(seq, joinpath(dir, "frames"))
    mkpath(dir)
    for clip in seq.clips
        VE.setrenderconfig!(clip; raytrace = false, device = "Mantle.defaultbackend()", fxaa = clip.track != 2)
    end
    canvas = VE.canvassize(seq)
    out = zeros(VE.RGB{VE.N0f8}, canvas...)
    engine = VE.FxEngine(Mantle.defaultbackend())
    readers = Dict{String, Any}()
    files = String[]
    try
        for clip in filter(c -> c.track == 1, seq.clips)
            name = clip.source.build["args"]["beat"]
            for f in (0.3, 0.75)
                n = clip.start + round(Int, f * (VE.cliplength(clip) - 1))
                VE.renderframe!(out, seq, n, readers, engine)
                path = joinpath(dir, "$(name)_$(f).png")
                VE.PNGFiles.save(path, permutedims(out)); push!(files, path)
                label = only(filter(c -> c.track == 2 && c.start == clip.start, seq.clips))
                plane = VE.cachedtrackframe(label, VE.sourceframe(label, n))
                minimum(VE.alpha.(plane)) == 0 || error("label background is opaque in $name")
            end
            println("reviewed ", name); flush(stdout)
            for c in filter(c -> c.start == clip.start, seq.clips)
                c.source.live === nothing && continue
                close(c.source.live.screen); c.source.live = nothing
            end
        end
    finally
        VE.emptyengine!(engine)
        foreach(close, values(readers))
    end
    return files
end
