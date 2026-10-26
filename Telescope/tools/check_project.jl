"""
Check the clips the editor makes of the telescope film against the film as authored.

    julia --project=<env with Telescope, VideoEditor and RayMakie> -i Telescope/tools/check_project.jl
    julia> keycoverage()                       # keys the editor cannot store: should be empty
    julia> compareframes("gen/check_project")  # keyed clips against the parts posed by `showat!`

A part's keys on its arguments are stored on the native plot properties that
consume them; a key that finds no such property is not stored, and its motion
would stand still without an error anywhere. `keycoverage` lists them.
`compareframes` renders frames of every part's keyed clip through the editor
and the same part built as authored and posed at the same moment
(`posed_part.jl`), both rasterized as the editor previews them, and returns
how much they differ; frames differing much are written to `dir`. Keys sit on
whole frames in the editor, so a fade differs slightly at its edges.
"""

using Telescope, ScienceFilms, VideoEditor, RayMakie
import ScienceFilms as SF
import VideoEditor as VE
import Mantle

include("posed_part.jl")

const EXT = Base.get_extension(ScienceFilms, :ScienceFilmsVideoEditorExt)
const FILM = Telescope.FILM
const LAYOUT = (1280, 720)
const CANVAS = (1920, 1080)
const FPS = 30

"The parts the editor makes clips of: beats and shots (a montage is shots)."
editorparts() = sort!([n for (n, p) in FILM.parts if !(p isa SF.Montage)])

"How long a part runs, in its own seconds."
seconds(part::SF.Beat) = FILM.timing(part.name).duration
seconds(part::SF.Shot) = part.seconds

"The `buildpart` arguments of each clip the editor makes of part `name`."
layerargs(name) = EXT.hasview(FILM, name, LAYOUT) ?
    [Dict{String, Any}("part" => name, "layer" => layer) for layer in ("picture", "labels")] :
    [Dict{String, Any}("part" => name)]

"""
    keycoverage() -> Vector{(part, path)}

Every key path of every part that none of the part's clips stores as a native
property track.
"""
function keycoverage()
    data = FILM.data()
    unstored = Tuple{String, String}[]
    for name in editorparts()
        anim = authored(FILM.parts[name], FILM, data)
        builts = [SF.buildpart(FILM, LAYOUT, args) for args in layerargs(name)]
        for (path, keys) in anim
            isempty(keys) && continue
            one = SF.Animation(path => keys)
            any(b -> !isempty(EXT.nativetracks(one, b, FPS)), builts) || push!(unstored, (name, path))
        end
        foreach(b -> Makie.free(b.scene), builts)
    end
    return unstored
end

"A rasterized clip of the editor at the film's canvas."
function flatclip!(clip)
    EXT.render!(clip, Val(:flat); spp = 1, max_depth = 1)
    return EXT.drawat!(clip, CANVAS, LAYOUT)
end

"""
    compareframes(dir; samples = 6, threshold = 2.0) -> Vector{(part, t, mean, changed)}

`samples` frames of every part, keyed by the editor and posed as authored:
their mean difference (0–255 levels) and the fraction of pixels differing by
more than 40 levels. Pairs whose mean exceeds `threshold` are written to `dir`.
"""
function compareframes(dir; samples = 6, threshold = 2.0)
    VE.usebackend!(RayMakie)
    mkpath(dir)
    data = FILM.data()
    engine = VE.FxEngine(Mantle.defaultbackend())
    readers = Dict{String, Any}()
    pixels = zeros(VE.RGB{VE.N0f8}, CANVAS...)
    results = NamedTuple[]
    try
        for name in editorparts()
            part = FILM.parts[name]
            nsource = ceil(Int, seconds(part) * FPS)
            built = SF.buildpart(FILM, LAYOUT, Dict{String, Any}("part" => name))
            tracks = EXT.nativetracks(authored(part, FILM, data), built, FPS)
            Makie.free(built.scene)
            seq = VE.Sequence(VE.Clip[], FPS)
            seq.canvas = CANVAS
            frames = round.(Int, range(10, nsource - 11; length = samples))
            for (k, sf) in enumerate(frames)
                keyed = EXT.sceneclip(FILM, name, :flat, nsource; canvas = CANVAS, layout = LAYOUT, fps = FPS,
                                      spp = 1, max_depth = 1)
                for (path, keys, discrete) in tracks
                    VE.keyframes!(keyed, path, keys; discrete)
                end
                keyed.src_in, keyed.src_out, keyed.start = sf, sf + 1, 2(k - 1)
                VE.addclip!(seq, keyed)
                build = VE.programscene(joinpath(@__DIR__, "posed_part.jl");
                                        args = Dict{String, Any}("part" => name, "t" => sf / FPS))
                posed = flatclip!(VE.sceneclip(VE.buildscene(build); build, frames = 1, canvas = LAYOUT,
                                               framerate = FPS, backend = :RayMakie))
                posed.start = 2(k - 1) + 1
                VE.addclip!(seq, posed)
            end
            for (k, sf) in enumerate(frames)
                VE.renderframe!(pixels, seq, 2(k - 1), readers, engine)
                a = copy(pixels)
                VE.renderframe!(pixels, seq, 2(k - 1) + 1, readers, engine)
                b = copy(pixels)
                diff = [maximum(abs.(Float32.((x.r, x.g, x.b)) .- Float32.((y.r, y.g, y.b)))) * 255 for (x, y) in zip(a, b)]
                mean = sum(diff) / length(diff)
                changed = count(>(40), diff) / length(diff)
                push!(results, (part = name, t = sf / FPS, mean, changed))
                println(rpad(name, 16), " t = ", rpad(round(sf / FPS; digits = 2), 6), " mean ", round(mean; digits = 2),
                        "  changed ", round(100changed; digits = 2), " %")
                flush(stdout)
                if mean > threshold
                    VE.PNGFiles.save(joinpath(dir, "$(name)_$(sf)_keyed.png"), permutedims(a))
                    VE.PNGFiles.save(joinpath(dir, "$(name)_$(sf)_posed.png"), permutedims(b))
                end
            end
            foreach(c -> c.source.live === nothing || close(c.source), seq.clips)
            GC.gc()
        end
    finally
        VE.emptyengine!(engine)
        foreach(close, values(readers))
    end
    return results
end
