# Run in the Science4Makie environment after project.jl: how long the farm takes
# per frame of each beat, measured through the farm's own frame path (the
# project's bake settings, compositing and PNG encoding), on this machine's GPU.

"""Everything a worker needs besides the packages: the recipe, its includes and data, the assets it loads."""
scene_inputs(root = @__DIR__) = vcat(
    [joinpath(root, "film", f) for f in readdir(joinpath(root, "film")) if endswith(f, ".jl")],
    [joinpath(root, "film", "beats", f) for f in readdir(joinpath(root, "film", "beats")) if endswith(f, ".jl")],
    [joinpath(root, "science.jl")],
    [joinpath(root, "data", f) for f in readdir(joinpath(root, "data")) if endswith(f, ".jls")],
    [joinpath(root, "assets", f) for f in ("starmap_2020_16k.exr", "alma.glb", "keynote_cats.png", "makie_logo.png")],
    # Static scenes use the baseline; animated sequences declare their own
    # remaining snapshots through FileSeriesRef in the saved project.
    [joinpath(root,"assets","grmhd","torus.out0.05000.h5")],
    [joinpath(root, "assets", "earth", f) for f in readdir(joinpath(root, "assets", "earth"))])

"""
    farmbench(project, directory; at = (0.3, 0.7)) -> Vector of (beat, frames, seconds)

Each beat rendered at the fractions `at` of its length after one warm-up frame
(scene build and compilation); `seconds` is the mean of the measured frames.
"""
function farmbench(project, directory; at = (0.3, 0.7))
    VE.usebackend!(RayMakie)
    job = VE.renderjob(project, directory; inputs = scene_inputs(), root=@__DIR__)
    renderer = VE.farmrenderer(job)
    names = first.(BEATS)
    results = map(zip(names, filter(c -> c.track==1,renderer.sequence.clips))) do (name, clip)
        n = clip.src_out - clip.src_in
        frame(f) = clip.start + round(Int, f * (n - 1))
        warm = VE.farmframes!(renderer, [frame(0.5)])[1].seconds
        measured = [r.seconds for r in VE.farmframes!(renderer, [frame(f) for f in at])]
        println(rpad(name, 22), lpad(n, 6), " frames  ", round(sum(measured) / length(measured); digits = 2), " s/frame  (first: ",
                round(warm; digits = 1), " s)")
        flush(stdout)
        (beat = name, frames = n, seconds = sum(measured) / length(measured))
    end
    VE.closefarm!(renderer)
    return results
end
