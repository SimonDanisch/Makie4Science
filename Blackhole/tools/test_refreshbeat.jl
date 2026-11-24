# Run in the configured Science4Makie environment, with the populated review
# project as ARGS[1]. This edits only an in-memory copy; it never saves it.
using Test
include(joinpath(@__DIR__, "..", "project.jl"))

function test_refreshbeat(path)
    seq = VE.loadproject(path)
    ids = getproperty.(seq.clips, :id)
    anchors = getproperty.(seq.narration, :anchor)
    before = VE.seqlength(seq)
    unaffected = first(seq.clips)
    cache = VE.trackcache(unaffected)
    valid = [VE.cachevalid(cache, unaffected.id, f) for f in unaffected.src_in:(unaffected.src_out - 1)]
    @testset "refresh keeps source identities and unaffected native caches" begin
        @test all(valid)
        extendbeat!(seq, "b7_cleaning", 3 / seq.framerate)
        @test VE.seqlength(seq) == before + 3
        refreshbeat!(seq, "b7_cleaning")
        @test getproperty.(seq.clips, :id) == ids
        @test all(n.anchor === a for (n, a) in zip(seq.narration, anchors))
        @test VE.seqlength(seq) == before  # refresh ripples the extra tail away
        @test [VE.cachevalid(cache, unaffected.id, f) for f in unaffected.src_in:(unaffected.src_out - 1)] == valid
        pictures = sort(filter(c -> c.track == 1, seq.clips); by = c -> c.start)
        @test all(VE.clipend(a) == b.start for (a, b) in zip(pictures[1:end-1], pictures[2:end]))
        pair = filter(c -> get(c.source.build["args"], "beat", "") == "b7_cleaning", seq.clips)
        @test length(pair) == 2
        @test all(c -> length(c.source.build["args"]["starts"]) == 7, pair)
    end
end

isempty(ARGS) || test_refreshbeat(first(ARGS))
