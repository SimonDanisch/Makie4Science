# Run after project.jl in the single Science4Makie root. No new Pkg environment.
using Test
function test_credits(project)
    seq = VE.loadproject(project)
    original = [(c.id,c.start,c.src_in,c.src_out) for c in seq.clips]
    takes = [(n.text,copy(n.samples)) for n in seq.narration]
    tail = maximum(VE.clipend, seq.clips)
    @testset "native end credits preserve the edit" begin
        appendcredits!(seq)
        @test [(c.id,c.start,c.src_in,c.src_out) for c in seq.clips[1:length(original)]] == original
        @test [(n.text,n.samples) for n in seq.narration] == takes
        @test length(seq.clips) == length(original)+2
        @test all(c.start==tail && VE.cliplength(c)==round(Int,12seq.framerate) for c in seq.clips[end-1:end])
        @test [c.track for c in seq.clips[end-1:end]] == [1,2]
        @test all(c.sequence===seq for c in seq.clips[end-1:end])
        ids = [c.id for c in seq.clips]
        appendcredits!(seq)
        @test [c.id for c in seq.clips] == ids
        @test isfile(joinpath(@__DIR__,"..","assets","makie_logo.png"))
    end
    return seq
end
