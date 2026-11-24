# Run in the Science4Makie environment after project.jl: seconds per frame of
# each traced beat, through the editor's own frame path (trace, HDR source
# capture, OIDN, grade, labels, composite), at a given sample count.
# What the farm estimate is made from: on this machine's GPU, or on a farm
# client's when run there.

"""
    benchtraced(project; spp, at, cache) -> Vector of (beat, frames, seconds)

Each traced beat's frames at the fractions `at` of its length, after one
warm-up frame (scene build and compilation), at `spp` samples per pixel, at the
project's size; `seconds` is their mean. Frames are written to track caches in
`cache`, a folder of its own, so the project's caches are untouched.
"""
function benchtraced(project; spp = 256, at = (0.3, 0.7),
                     cache = joinpath(@__DIR__, "..", "renders", "bench_traced"))
    VE.usebackend!(RayMakie)
    seq = VE.loadproject(project)
    empty!(seq.trackcaches)
    seq.compositecache = nothing
    rm(cache; recursive = true, force = true)
    VE.enabletrackcache!(seq, cache)
    traced = filter(c -> c.track == 1 && !get(c.source.bakescreenopts, :rasterize, true), seq.clips)
    for c in traced
        c.source.bakescreenopts = merge(c.source.bakescreenopts, Dict{Symbol, Any}(:samples => spp))
    end
    engine = VE.FxEngine(Mantle.defaultbackend())
    readers = Dict{String, Any}()
    out = zeros(VE.RGB{VE.N0f8}, seq.canvas...)
    results = map(traced) do clip
        n = clip.src_out - clip.src_in
        frame(f) = clip.start + round(Int, f * (n - 1))
        draw(m) = (t = time(); VE.renderframe!(out, seq, m, readers, engine); time() - t)
        warm = draw(frame(0.5))
        seconds = sum(draw(frame(f)) for f in at) / length(at)
        name = clip.source.build["args"]["beat"]
        println(rpad(name, 22), lpad(n, 6), " frames  ", round(seconds; digits = 2), " s/frame  (first: ",
                round(warm; digits = 1), " s)")
        flush(stdout)
        (beat = name, frames = n, seconds)
    end
    VE.emptyengine!(engine)
    foreach(close, values(readers))
    return results
end
