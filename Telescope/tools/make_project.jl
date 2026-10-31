#=
Write the telescope film as a VideoEditor project.

    julia --project=<env with Telescope, VideoEditor and RayMakie> Telescope/tools/make_project.jl [path]

Every part of `Telescope.FILM.cut` as clips with their keys, and the approved
narration laid under them, saved in the project: a render farm uses that
performance and loads no speech model. 1920×1080 from scenes laid out at
1280×720, 30 fps. Previews rasterize; a bake or an export traces every 3D
picture with `spp` samples and up to `max_depth` bounces, denoised, graded and
display-mapped by the editor, with its labels drawn over it. Written to
`gen/telescope.videoedit` unless a path is given. Track caches retain separate
graded pictures and transparent labels; the farm uses `hdr=false` so the large
HDR/auxiliary buffers are not retained. For another language, edit a saved
project rather than rebuilding the sequence and losing its clip identities.
=#

using Telescope, ScienceFilms, VideoEditor, RayMakie

const ROOT = normpath(joinpath(@__DIR__, ".."))

function main(path = joinpath(ROOT, "gen", "telescope.videoedit"); spp = 256, max_depth = 24)
    mkpath(dirname(path))
    VideoEditor.usebackend!(RayMakie)
    seq = filmsequence(Telescope.FILM; canvas = (1920, 1080), layout = (1280, 720), fps = 30, spp, max_depth)
    VideoEditor.enabletrackcache!(seq, path * ".frames")
    VideoEditor.saveproject(path, seq)
    frames = VideoEditor.seqlength(seq)
    println(path, ": ", length(seq.clips), " clips, ", frames, " frames (", round(frames / 30 / 60; digits = 1),
            " min), ", length(seq.narration), " narrated parts")
    return path
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS...)
end
