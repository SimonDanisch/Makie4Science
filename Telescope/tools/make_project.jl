"""
Write the telescope film as a VideoEditor project.

    julia --project=<env with Telescope, VideoEditor and RayMakie> Telescope/tools/make_project.jl [path]

Every part of `Telescope.FILM.cut` as clips with their keys, and the approved
narration laid under them, saved in the project: a render farm uses that
performance and loads no speech model. Previews draw with RayMakie's raster
mode; a bake or an export path-traces with `spp` samples. Written to
`gen/telescope.videoedit` unless a path is given.
"""

using Telescope, ScienceFilms, VideoEditor, RayMakie

const ROOT = normpath(joinpath(@__DIR__, ".."))

function main(path = joinpath(ROOT, "gen", "telescope.videoedit"); spp = 64)
    mkpath(dirname(path))
    seq = filmsequence(Telescope.FILM; canvas = (1280, 720), fps = 30, spp)
    VideoEditor.saveproject(path, seq)
    frames = VideoEditor.seqlength(seq)
    println(path, ": ", length(seq.clips), " clips, ", frames, " frames (", round(frames / 30 / 60; digits = 1),
            " min), ", length(seq.narration), " narrated parts")
    return path
end

main(ARGS...)
