# Animation as data: sparse keys on named scene properties, written the way a
# narration-driven explainer is planned ("the lens label fades in as line 3
# starts"). The editor turns these into ordinary keyframes on the clip; nothing
# here samples a signal.

"""
    Key(t, value, ease = :linear)

One key: `t` seconds into the shot, a value (number, `Vec`/`Point`, colour or
`Bool`), and how the curve leaves it: `:linear` (a constant rate), `:smooth`
(easing in and out, flat at both keys), or `:hold` (a step).
"""
struct Key{T}
    t::Float32
    value::T
    ease::Symbol
end
Key(t::Real, value, ease::Symbol = :linear) = Key(Float32(t), value, ease)

"""
    Timing(starts, ends, duration)

When each narration line of a shot is spoken, in seconds into the shot, and how
long the shot runs.
"""
struct Timing
    starts::Vector{Float32}
    ends::Vector{Float32}
    duration::Float32
end

"""Read a `.timing` file: a cache key, then line starts, line ends and the duration."""
function Timing(path::AbstractString)
    s = readlines(path)
    return Timing(parse.(Float32, split(s[2])), parse.(Float32, split(s[3])), parse(Float32, s[4]))
end

"""
    ramp(t0, t1, from = 0, to = 1; ease = :linear) -> Vector{Key}

A value going from `from` at `t0` to `to` at `t1`, held before and after.
"""
ramp(t0, t1, from = 0f0, to = 1f0; ease = :linear) = [Key(t0, Float32(from), ease), Key(t1, Float32(to), ease)]

"""0 until line `i` starts (plus `delay`), then rising to 1 over `d` seconds: a fade-in on its first word."""
appear(tm::Timing, i; d = 0.6f0, delay = 0f0) = ramp(tm.starts[i] + delay, tm.starts[i] + delay + d)

"""0 until line `i` has been spoken, then rising to 1 over `d` seconds."""
after(tm::Timing, i; d = 0.6f0) = ramp(tm.ends[i], tm.ends[i] + d)

"""How far line `i` (to line `j`) has been spoken: 0 at its start, 1 at the end, eased with `ease`."""
through(tm::Timing, i, j = i; ease = :linear) = ramp(tm.starts[i], tm.ends[j]; ease)

"""A step from `from` to `to` at time `t`."""
switch(t, from, to) = [Key(0f0, from, :hold), Key(Float32(t), to, :hold)]

"""
    valueof(keys, t) -> value

The value a key list has at `t`, as the editor interpolates it: held outside
the keys, linear, smoothstep or held between them.
"""
function valueof(keys::AbstractVector{<:Key}, t)
    t <= keys[1].t && return keys[1].value
    t >= keys[end].t && return keys[end].value
    i = findlast(k -> k.t <= t, keys)
    a, b = keys[i], keys[i+1]
    a.ease === :hold && return a.value
    u = (t - a.t) / (b.t - a.t)
    m0 = a.ease === :smooth ? 0f0 : 1f0
    m1 = b.ease === :smooth ? 0f0 : 1f0
    h = (u^3 - 2u^2 + u) * m0 + (-2u^3 + 3u^2) + (u^3 - u^2) * m1
    return a.value + h * (b.value - a.value)
end

"""
    *(a::Vector{Key}, b::Vector{Key}) -> Vector{Key}

The product of two fades: exact where their ramps do not overlap (one fades in,
later the other fades out), linear between the union of their keys otherwise.
"""
function Base.:*(a::AbstractVector{<:Key{<:Real}}, b::AbstractVector{<:Key{<:Real}})
    ts = sort!(unique(vcat([k.t for k in a], [k.t for k in b])))
    return [Key(t, Float32(valueof(a, t) * valueof(b, t)), :linear) for t in ts]
end
Base.:*(s::Real, a::AbstractVector{<:Key{<:Real}}) = [Key(k.t, Float32(s * k.value), k.ease) for k in a]

"""`1 - fade`: what fades out while `a` fades in."""
Base.:-(x::Real, a::AbstractVector{<:Key{<:Real}}) = [Key(k.t, Float32(x - k.value), k.ease) for k in a]

"""
    posekeys(keys) -> Dict{String, Vector{Key}}

Camera keys from `t => Pose` pairs, eased in and out between poses as the
original films moved: keys for `camera.eye`, `camera.lookat` and `camera.fov`.
"""
function posekeys(keys::AbstractVector{<:Pair})
    ks = [Float32(t) => p for (t, p) in keys]
    return Dict("camera.eye" => [Key(t, p.eye, :smooth) for (t, p) in ks],
                "camera.lookat" => [Key(t, p.lookat, :smooth) for (t, p) in ks],
                "camera.fov" => [Key(t, p.fov, :smooth) for (t, p) in ks])
end

"""
    Animation

A shot's keys: scene property path (as the editor names it: `"camera.eye"`,
`"lens_label.alpha"`, `"args.wave.phase"`) to its keys. Paths with `Bool` or
integer values are discrete and step.
"""
const Animation = Dict{String, Vector{Key}}

"""Merge key sets; a later path replaces an earlier one."""
animation(parts...) = merge(Animation(), (Dict{String, Vector{Key}}(k => Vector{Key}(v) for (k, v) in p) for p in parts)...)
