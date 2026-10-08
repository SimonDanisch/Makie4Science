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
    Montage(name, lines, shots; tail = 1.2, maxspeed = 1.5)

A narrated stretch of film shown with shots: `shots` are `(shot, from, to)`,
seconds of each [`Shot`](@ref), played one after the other, sped up (by at most
`maxspeed`) or slowed down together to last as long as the narration `lines`
and `tail` seconds after it, and cut there if they still run longer.
"""
struct Montage
    name::String
    lines::Vector{String}
    shots::Vector{Tuple{String,Float32,Float32}}
    tail::Float32
    maxspeed::Float32
end
Montage(name, lines, shots; tail = 1.2f0, maxspeed = 1.5f0) =
    Montage(name, collect(String, lines), [(String(s), Float32(a), Float32(b)) for (s, a, b) in shots],
            Float32(tail), Float32(maxspeed))

"""
    fit(montage, seconds) -> (speed, length)

How fast a montage plays its shots to fill `seconds` of narration plus its
tail, and how long it then runs (seconds).
"""
function fit(m::Montage, seconds)
    target = Float32(seconds) + m.tail
    total = sum(b - a for (_, a, b) in m.shots)
    return min(total / target, m.maxspeed), target
end

"""
    Film(mod, parts, data, timing, voice, cut)

What the editor needs of a film: the package `mod` its scenes are loaded from,
which defines `part(canvas, args)` (the recipe a project names, see
[`buildpart`](@ref)); its `parts` by name (beats, shots and montages); `data()`,
everything the parts are built from, loaded once; `timing(name)`, when each
line of the narrated part `name` is spoken; `voice(name)`, the narration's
audio file; and `cut`, the narrated parts in the order the film shows them.
"""
struct Film{D,T,V}
    mod::Module
    parts::Dict{String,Union{Beat,Shot,Montage}}
    data::D
    timing::T
    voice::V
    cut::Vector{String}
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

"""
    filmsequence(film; canvas, fps, spp) -> VideoEditor sequence

The whole film as one VideoEditor sequence: every part of `film.cut` in order,
as clips with their keys, and its narration laid under them. Defined when
VideoEditor is loaded.
"""
function filmsequence end

"""
    showat!(built, animation, t) -> built

Put a built part (what its `build` returned) where its `animation` has it `t`
seconds in, without an editor: the camera, the arguments and the keyed plot
attributes, interpolated as the editor interpolates its keyframes. For stills
and checks of a part.
"""
function showat!(built, anim::Animation, t)
    camera = Dict{String, Any}()
    for (path, keys) in anim
        v = valueof(keys, t)
        head, rest = split(path, '.'; limit = 2)
        if head == "camera"
            camera[rest] = v
        elseif head == "args"
            setarg!(built.args, split(rest, '.'), v)
        else
            plot = findplot(built.scene, Symbol(head))
            plot === nothing && error("no plot named $head in the part's scene")
            setproperty!(plot, Symbol(rest), v)
        end
    end
    if !isempty(camera)
        scene = findcamera3d(built.scene)
        cam = cameracontrols(scene)
        # the camera's own up: a part looking straight down has north up, not world z
        look!(scene, Pose(get(camera, "eye", cam.eyeposition[]), get(camera, "lookat", cam.lookat[]),
                          get(camera, "fov", cam.fov[])); up = get(camera, "up", cam.upvector[]))
    end
    return built
end

"""Set the argument at `fields` of `args` (a field of a struct an Observable holds is replaced, the struct rebuilt)."""
function setarg!(args, fields, v)
    obs = getproperty(args, Symbol(fields[1]))
    obs[] = withfield(obs[], fields[2:end], v)
    return obs
end
function withfield(old, fields::AbstractVector, v)
    isempty(fields) && return old isa Real ? convert(typeof(old), v) : v
    f = Symbol(fields[1])
    T = typeof(old)
    return T((n == f ? withfield(getfield(old, n), fields[2:end], v) : getfield(old, n) for n in fieldnames(T))...)
end

"""The top-level plot named `name` in `scene` or any scene below it, or `nothing`."""
function findplot(scene::Scene, name::Symbol)
    for p in scene.plots
        haskey(p.attributes, :name) && p.name[] === name && return p
    end
    for c in scene.children
        p = findplot(c, name)
        p === nothing || return p
    end
    return nothing
end

"""The first scene below `scene` (or it) with a 3D camera."""
function findcamera3d(scene::Scene)
    cameracontrols(scene) isa Camera3D && return scene
    for c in scene.children
        s = findcamera3d(c)
        s === nothing || return s
    end
    return nothing
end
