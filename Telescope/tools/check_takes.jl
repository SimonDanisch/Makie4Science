"""
Does the film's project play every approved take where it belongs, saying its
part's current lines?

    julia --project=<env with Telescope, VideoEditor and RayMakie> Telescope/tools/check_takes.jl [project]

VideoEditor transcribes the edit's audio and compares each narrated part's
lines with what is heard while its take plays (`VideoEditor.checknarration`).
A take of other lines must be spoken again. The project is
`gen/telescope.videoedit` (`make_project.jl`) unless a path is given.
"""

using VideoEditor, RayMakie
import VideoEditor as VE

function main(path = joinpath(@__DIR__, "..", "gen", "telescope.videoedit"))
    VE.installtranscribe!()
    for take in VE.checknarration(VE.loadproject(path))
        println(rpad(take.label, 18), take.differences, " of ", take.words, " words differ")
    end
end

main(ARGS...)
