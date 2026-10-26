# A VideoEditor scene recipe for tools/check_project.jl: part `args["part"]`
# built as authored and posed where its keys have it at `args["t"]` seconds
# (`showat!`), the reference its keyed clip is compared with.

using Telescope, ScienceFilms

"The part's animation: a beat's placed by its narration, a shot's in its own seconds."
authored(part::Beat, film, data) = part.keys(data, film.timing(part.name))
authored(part::Shot, film, data) = part.keys(data)

function buildscene(canvas, args)
    film = Telescope.FILM
    data = film.data()
    part = film.parts[args["part"]]
    built = part.build(data; size = Tuple(canvas))
    showat!(built, authored(part, film, data), Float32(args["t"]))
    return (scene = built.scene,)
end
