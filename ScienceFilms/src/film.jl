# A film: named parts, each a scene built once from the film's data and
# animated by keys, narrated beats placed by when each line is spoken.

"""
    Beat(name, lines, build, keys)

A narrated part: `lines` are the narration, one spoken line each. `build(data;
size)` makes its scene once and returns `(scene = ..., args = ..., objects = ...)`,
`args` the Observables its keys name; `keys(data, timing)` its animation, from
when each line is spoken.
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
    Montage(name, lines, shots; tail = 1.2, maxspeed = 1.5, speed = nothing)

A narrated stretch of film shown with shots: `shots` are `(shot, from, to)`,
seconds of each [`Shot`](@ref), played one after the other, sped up (by at most
`maxspeed`) or slowed down together to last as long as the narration `lines`
and `tail` seconds after it, and cut there if they still run longer. A fixed
`speed` plays them at that speed instead, cut where the narration ends: a
shortened narration that keeps the pictures of a cut already rendered.
"""
struct Montage
    name::String
    lines::Vector{String}
    shots::Vector{Tuple{String,Float32,Float32}}
    tail::Float32
    maxspeed::Float32
    speed::Union{Nothing,Float32}
end
Montage(name, lines, shots; tail = 1.2f0, maxspeed = 1.5f0, speed = nothing) =
    Montage(name, collect(String, lines), [(String(s), Float32(a), Float32(b)) for (s, a, b) in shots],
            Float32(tail), Float32(maxspeed), speed === nothing ? nothing : Float32(speed))

"""
    fit(montage, seconds) -> (speed, length)

How fast a montage plays its shots to fill `seconds` of narration plus its
tail, and how long it then runs (seconds).
"""
function fit(m::Montage, seconds)
    target = Float32(seconds) + m.tail
    return playspeed(m.speed, sum(b - a for (_, a, b) in m.shots) / target, m.maxspeed), target
end

"The speed a montage plays at: fitted to its narration (at most `maxspeed`), or the one it was given."
playspeed(::Nothing, fitted, maxspeed) = min(fitted, maxspeed)
playspeed(speed::Float32, fitted, maxspeed) = speed

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
returns to the editor, its scene and inspector groups, its keyed arguments
bound to the native plot properties that consume them. `args["layer"]`, if
given, keeps only the `"picture"` or the `"labels"` of a part with a 3D view.
Defined when VideoEditor is loaded.
"""
function buildpart end

"""
    partclips(film, name; frames, src_in, speed, canvas, layout, fps, spp, max_depth, timing) -> clips

The VideoEditor clips of part `name` of `film`, with its keys: a traced part's
picture and labels, a flat one as one clip. Defined when VideoEditor is loaded.
"""
function partclips end

"""
    filmsequence(film; canvas, layout, fps, spp, max_depth) -> VideoEditor sequence

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
            arg = getproperty(built.args, Symbol(rest))
            arg[] = convert(eltype(arg), v)
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
