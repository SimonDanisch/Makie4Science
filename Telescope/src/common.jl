# What several parts of the film share: the telescope cut open with its light,
# two telescopes side by side, the dark axes of the flat explanations, and
# labels hidden until a key fades them in.

"""Height (pixels) of the band below a split frame that holds its subtitles."""
const SUBTITLES = 112

"""The grey of a panel's title on the studio's beige: light grey could hardly be read there."""
const ON_BEIGE = RGBf(0.12, 0.11, 0.10)

"""A colour (a palette tuple, a name or a colour) as RGBA, at opacity `a`."""
rgba(c::NTuple{3}, a = 1) = RGBAf(c..., a)
rgba(c, a = 1) = (rgb = RGBf(Makie.to_color(c)); RGBAf(rgb.r, rgb.g, rgb.b, a))

"""A colour faded by an `Observable` opacity: for what has no `alpha` of its own (an axis title)."""
faded(c, alpha::Observable) = lift(a -> rgba(c, a), alpha)

"""A text in a flat picture, named `name`, hidden until keyed, offered to the editor as `Text · <text>`."""
function words!(ins, ax, name::Symbol, pos, text; alpha = 0, color = :white, kw...)
    p = text!(ax, textposition(pos); text, color, alpha, name, kw...)
    label!(ins, "Text · " * first(split(String(text), '\n')), p)
    return p
end

"""Where a text sits: a point, or an `Observable` one for a text that moves."""
textposition(p) = Point2f(p)
textposition(p::Observable) = p

"""
A horizontal bracket from `a` to `b` at height `y` of axis `ax`, hidden until
keyed (`name.alpha`), with `label` beside its left end.
"""
function bracket!(ins, ax, name::Symbol, a, b, y, label, color; alpha = 0)
    p = lines!(ax, [Point2f(a, y - 0.25f0), Point2f(a, y), Point2f(b, y), Point2f(b, y - 0.25f0)];
               color = rgba(color), linewidth = 2, alpha, name)
    object!(ins, "Bracket · " * (isempty(label) ? String(name) : label), p)
    isempty(label) || words!(ins, ax, Symbol(name, :_text), (a - 0.05f0, y), label; color = rgba(color),
                             fontsize = 16, align = (:right, :center), alpha)
    return p
end

# ── the telescope, cut open ──────────────────────────────────────────────────

"""
    telescope!(scene, tel, g, tex; name, inspector, offset, studio) -> sheet plot

The telescope `tel` cut open, with the glow `tex` (an `Observable` of a texture
over grid `g`, grid layout) on its cut: [`cutaway!`](@ref) with its meshes,
centred on its sensor.
"""
telescope!(sc, tel::Refractor, g::Grid, tex::Observable; name = :telescope, inspector = nothing, offset = Vec3f(0),
           studio = true) =
    cutaway!(sc, telescope_meshes(tel), g, tex, tel.sys.sensor / 2; name, inspector, offset, studio)

"""
The steady glow of a telescope's light at phase `φ` (periods): its crests over
its intensity, the source side dark.
"""
steady_glow(A, I, g, φ; tint = SUNLIGHT) = hide_source!(glow(phase_field(A, φ), I; GLOW..., tint), g, -14f0)

"""The sensor bars of a steady state: pixel centres and values scaled to the brightest."""
function readout(g::Grid, I, xf)
    cs, vs = sensor_pixels(g, I, xf - 0.3f0)
    return cs, vs ./ maximum(vs)
end

"""Where a bar of the readout (pixel at height `y`, value `v` of the brightest) ends: a callout's anchor."""
bar_tip(xf, cs, v, y) = (k = argmin(abs.(cs .- y)); w3(xf + 1.5f0 + 17f0 * v[k], cs[k]))

# ── two telescopes side by side ──────────────────────────────────────────────

"""Where the two telescopes of a comparison stand: one above the other in the picture."""
const PAIR_OFFSETS = [Vec3f(0, 3.6, 0), Vec3f(0, -3.6, 0)]

"""One telescope of a comparison: its optics, grid and steady state, and the colour of its light."""
struct Setup
    tel::Refractor
    g::Grid
    A::Matrix{ComplexF32}
    I::Matrix{Float32}
    tint::NTuple{3,Float32}
end

"""
The glow of a comparison's telescope at phase `φ`: its light within its
outline, its sensor bars, and with `paths` > 0 the paths from its lens's two
edges to the pixel at height `y`, which `highlight` frames.
"""
function pair_glow(s::Setup, φ; y = 0f0, paths = 0f0, highlight = false)
    tel, g = s.tel, s.g
    xf = tel.sys.sensor
    tex = outline_mask!(steady_glow(s.A, s.I, g, φ; tint = s.tint), g, tel.parts)
    cs, v = readout(g, s.I, xf)
    readout_glow!(tex, g, xf, cs, [(v, s.tint)]; highlight = highlight ? y : nothing)
    if paths > 0
        xe = tel.sys.elements[end].back.x + 0.3f0
        wl = Wavelets([Point2f(xe, tel.D / 2), Point2f(xe, -tel.D / 2)], Point2f(xf, 0))
        for (i, col) in ((1, ORANGE), (2, BLUE))
            path_glow!(tex, g, wl, i, Point2f(xf, y), φ, col; width = 0.25f0, gain = Float32(paths))
        end
    end
    return tex
end

"""
Two telescopes side by side in `sc`, named `upper` and `lower`, each with the
glow `textures[k]` (`Observable`s) on its cut; the studio is the upper one's.
"""
function pair!(sc, ins, setups, textures; names = (:upper, :lower))
    for (k, (s, tex, off)) in enumerate(zip(setups, textures, PAIR_OFFSETS))
        telescope!(sc, s.tel, s.g, tex; name = names[k], inspector = ins, offset = off, studio = k == 1)
    end
    return sc
end
