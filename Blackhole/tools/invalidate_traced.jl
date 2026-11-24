# Include in the Science4Makie root session with VideoEditor loaded as VE.

"""
    invalidate_traced!(project; keep = Int[]) -> Dict(beat => frames)

Mark every cached traced picture of `project` stale, except at the timeline
frames in `keep`, and save the project. A farm job made with `reuse` of the
project then renders them again; nothing is deleted.
"""
function invalidate_traced!(project; keep = Int[])
    seq = VE.loadproject(project)
    counts = Dict{String, Int}()
    for c in seq.clips
        (c.track == 1 && c.source isa VE.SceneSource) || continue
        get(c.source.bakescreenopts, :rasterize, true) && continue
        cache = VE.sourcecache(c)
        cache === nothing && continue
        kept = Set(VE.sourceframe(c, n) for n in keep if c.start <= n < VE.clipend(c))
        stale = [sf for sf in c.src_in:(c.src_out - 1) if !(sf in kept) && VE.cachevalid(cache, c.id, sf)]
        isempty(stale) && continue
        VE.invalidateclip!(c; frames = stale)
        counts[get(c.source.build["args"], "beat", "?")] = length(stale)
    end
    VE.saveproject(project, seq; checkpoint = false)
    return counts
end
