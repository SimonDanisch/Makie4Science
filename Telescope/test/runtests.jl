# Every part of the film builds, and every key of its animation names something
# of what was built: a plot with that attribute, an argument or the camera. The
# editor skips a key that names nothing, so a misspelt path would leave a label
# hidden or a motion still without an error anywhere.
#
# Needs a GPU (the arrival beat runs its simulation on one) and the film's
# artifacts, which it downloads on first use.

using Test, Telescope, ScienceFilms
import ScienceFilms as SF

const FILM = Telescope.FILM
const DATA = Telescope.telescope_data()

"""The key paths of `anim` that name nothing of the built part `built`."""
function unresolved(built, anim)
    return filter(collect(keys(anim))) do path
        head, rest = split(path, '.'; limit = 2)
        head == "camera" && return SF.findcamera3d(built.scene) === nothing
        head == "args" && return !hasproperty(built.args, Symbol(first(split(rest, '.'))))
        plot = SF.findplot(built.scene, Symbol(head))
        return plot === nothing || !haskey(plot.attributes, Symbol(rest))
    end
end

"""How long part `name` runs, in its own seconds."""
duration(name, part::Beat) = Telescope.narration_timing(name).duration
duration(name, part::Shot) = part.seconds

@testset "the cut" begin
    for name in FILM.cut
        @test haskey(FILM.parts, name)
        @test isfile(FILM.voice(name))
    end
    for part in values(FILM.parts)
        part isa Montage || continue
        @test all(((shot, a, b),) -> FILM.parts[shot] isa Shot && 0 <= a < b <= FILM.parts[shot].seconds, part.shots)
    end
end

@testset "$name" for name in sort!([n for (n, p) in FILM.parts if !(p isa Montage)])
    part = FILM.parts[name]
    built = part.build(DATA; size = (640, 360))
    anim = part isa Beat ? part.keys(DATA, Telescope.narration_timing(name)) : part.keys(DATA)
    @test isempty(unresolved(built, anim))
    # what the editor lists names plots of the scene
    @test all(n -> SF.findplot(built.scene, Symbol(n)) !== nothing, (n for o in built.objects for n in o.plots))
    for t in range(0, duration(name, part); length = 4)
        showat!(built, anim, t)
    end
end
