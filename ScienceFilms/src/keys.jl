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
    t = Float32(t)
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
    combine(op, a, b) -> Vector{Key}

Two key lists combined value by value, `op(a(t), b(t))`, keyed at the times of
both. Between two of those times at most one list changes when fades follow
one another (one fades in, later the other fades out); the result then eases
into and out of each key as that list does, so its easing is kept exactly.
Where both change at once it is linear between the keys.
"""
function combine(op, a::AbstractVector{<:Key{<:Real}}, b::AbstractVector{<:Key{<:Real}})
    ts = sort!(unique(vcat([k.t for k in a], [k.t for k in b])))
    return [Key(t, Float32(op(valueof(a, t), valueof(b, t))), keyease(a, b, ts, i)) for (i, t) in enumerate(ts)]
end

"""Which of `a` and `b` changes between `t0` and `t1`: one of them, or `nothing` if neither or both do."""
function changing(a, b, t0, t1)
    da = valueof(a, t0) != valueof(a, t1)
    db = valueof(b, t0) != valueof(b, t1)
    return da == db ? nothing : da ? a : b
end

"""The ease of `keys`' key at `t` (the last one before it)."""
easeat(keys, t) = (i = findlast(k -> k.t <= t, keys); i === nothing ? :linear : keys[i].ease)

"""
How the combination of `a` and `b` passes its key `i` (at `ts[i]`): as the list
that changes after it does, or, when nothing changes after it, as the list that
changed before it arrives there. A key's ease shapes both the segment it ends
and the one it starts, the editor's way.
"""
function keyease(a, b, ts, i)
    after = i < length(ts) ? changing(a, b, ts[i], ts[i+1]) : nothing
    after === nothing || return easeat(after, ts[i])
    before = i > 1 ? changing(a, b, ts[i-1], ts[i]) : nothing
    return before === nothing ? :linear : easeat(before, ts[i])
end

"""
The product of two fades: one shown while another is, a label faded in and later
out. `Vector`, not `AbstractVector`: Base's `+(::Array, ::Array...)` is more
specific than an abstract vector of keys, and added them key by key.
"""
Base.:*(a::Vector{<:Key{<:Real}}, b::Vector{<:Key{<:Real}}) = combine(*, a, b)
Base.:+(a::Vector{<:Key{<:Real}}, b::Vector{<:Key{<:Real}}) = combine(+, a, b)
Base.:-(a::Vector{<:Key{<:Real}}, b::Vector{<:Key{<:Real}}) = combine(-, a, b)
Base.:*(s::Real, a::AbstractVector{<:Key{<:Real}}) = [Key(k.t, Float32(s * k.value), k.ease) for k in a]
Base.:+(x::Real, a::AbstractVector{<:Key{<:Real}}) = [Key(k.t, Float32(x + k.value), k.ease) for k in a]

"""`1 - fade`: what fades out while `a` fades in."""
Base.:-(x::Real, a::AbstractVector{<:Key{<:Real}}) = [Key(k.t, Float32(x - k.value), k.ease) for k in a]

"""A constant: one key."""
constant(v) = [Key(0f0, v, :hold)]

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

"""
    retime(animation, speed) -> Animation

The same motion played `speed` times as fast: every key time divided by `speed`.
A shot fitted to a narration is retimed, so every frame shows its own moment of
the shot rather than a frame shown twice or skipped.
"""
retime(anim::Animation, speed::Real) =
    Animation(path => Key[Key(k.t / Float32(speed), k.value, k.ease) for k in ks] for (path, ks) in anim)
