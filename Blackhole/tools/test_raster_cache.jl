# Run in Science4Makie with the rendering backend configured.
using Test, Mantle
include(joinpath(@__DIR__, "..", "project.jl"))

@testset "raster review caches survive export and reload" begin
    dir = mktempdir()
    path = joinpath(dir, "review.videoedit")
    build = VE.scenebuild(:bar, (64, 36))
    clip = VE.sceneclip(VE.buildscene(build); build, frames = 3, canvas = (64, 36))
    seq = VE.Sequence([clip], 30)
    seq.canvas = (64, 36)
    VE.enabletrackcache!(seq, path * ".frames")
    VE.saveproject(path, seq)
    exportraster(path, joinpath(dir, "first.mp4"); progress = nothing)
    saved = VE.loadproject(path)
    @test only(saved.clips).id == clip.id
    @test all(f -> VE.cachevalid(saved.compositecache, 0, f), 0:2)
    files = [VE.cachefile(saved.compositecache, 0, f) for f in 0:2]
    times = mtime.(files)
    exportraster(path, joinpath(dir, "second.mp4"); progress = nothing)
    @test mtime.(files) == times
end
