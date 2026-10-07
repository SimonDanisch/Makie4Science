# A film: named parts, each a scene built once from the film's data and
# animated by keys, narrated beats placed by when each line is spoken.

"""
    Beat(name, lines, build, keys)

A narrated part: `lines` are the narration, one spoken line each. `build(data;
size)` makes its scene once and returns `(scene = ..., args = ...)`;
`keys(data, timing)` its animation, from when each line is spoken.
"""
struct Beat
    name::String
    lines::Vector{String}
    build::Any
    keys::Any
end

"""
    Shot(name, seconds, build, keys)

An animated shot without narration of its own, cut into the film's scenes:
`keys(data)` places its animation in its own seconds.
"""
struct Shot
    name::String
    seconds::Float32
    build::Any
    keys::Any
end

"""
    Film(mod, parts, data, timing)

What the editor needs of a film: the package `mod` its scenes are loaded from,
which defines `part(canvas, args)` (the recipe a project names, see
[`buildpart`](@ref)); its `parts` by name; `data()`, everything the parts are
built from, loaded once; and `timing(name)`, when each line of the narrated part
`name` is spoken.
"""
struct Film{D,T}
    mod::Module
    parts::Dict{String,Union{Beat,Shot}}
    data::D
    timing::T
end

"""
    buildpart(film, canvas, args) -> NamedTuple

Part `args["part"]` of `film`, built at `canvas`: what a film's `part` recipe
returns to the editor.
"""
function buildpart(film::Film, canvas, args)
    p = film.parts[args["part"]]
    return p.build(film.data(); size = Tuple(canvas))
end

"""
    animate!(clip, animation; fps) -> clip

Write an `Animation` as a VideoEditor clip's keyframes. Defined when
VideoEditor is loaded.
"""
function animate! end

"""
    partclip(film, name; frames, src_in, rate, canvas, fps, spp, timing) -> clip

A VideoEditor clip of part `name` of `film`, with its keys. Defined when
VideoEditor is loaded.
"""
function partclip end
