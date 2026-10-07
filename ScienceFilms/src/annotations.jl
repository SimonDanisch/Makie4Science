# On-screen text as plots with keyable attributes: labels pointing at parts of a
# 3D scene, and captions. Drawn in a pixel overlay on top of the scene they
# describe; a callout reads that scene's camera, so it stays on its anchor
# however the (keyed) camera moves, and `alpha` fades all of it.

const LABEL_BACKGROUND = RGBf(0.06, 0.06, 0.07)

"""
    callout(anchor; text, offset, alpha, fontsize, projectionview, viewport)

A label for the point `anchor` of another scene: a dot on it, a thin leader,
and `text` set `offset` pixels away on a dark, see-through backing. Plot it into
a pixel overlay, connected to the described scene's camera:

```julia
callout!(overlay, Point3f(1, 0, 2); text = "lens", offset = Vec2f(-60, 90),
         projectionview = scene.camera.projectionview, viewport = scene.viewport)
```

`alpha` fades dot, leader and label together; it is what a narration keys.
"""
@recipe Callout (anchor,) begin
    "The label's text."
    text = ""
    "Where the label sits, in pixels from the anchor."
    offset = Vec2f(0, 60)
    "Opacity of the whole callout, 0 (gone) to 1."
    alpha = 1.0
    "The label's font size in pixels."
    fontsize = 24
    "The described scene's `projectionview`, which places the anchor on screen."
    projectionview = Mat4f(I)
    "The described scene's viewport in figure pixels."
    viewport = Rect2f(0, 0, 1, 1)
    Makie.mixin_generic_plot_attributes()...
end

Makie.convert_arguments(::Type{<:Callout}, p::VecTypes{2}) = (Point3f(p[1], p[2], 0),)
Makie.convert_arguments(::Type{<:Callout}, p::VecTypes{3}) = (Point3f(p),)

"Where the world point `p` shows on screen, in figure pixels, for a camera and viewport."
function screen_position(projectionview::AbstractMatrix, viewport::Rect2, p)
    clip = Mat4f(projectionview) * Vec4f(p[1], p[2], p[3], 1f0)
    ndc = Vec2f(clip[1], clip[2]) / clip[4]
    return Point2f(Vec2f(origin(viewport)) .+ (ndc .+ 1f0) ./ 2f0 .* Vec2f(widths(viewport)))
end
screen_position(scene::Scene, p) = screen_position(scene.camera.projectionview[], scene.viewport[], p)

"Text alignment for a label set `offset` away from its anchor."
label_align(offset) = (offset[1] >= 0 ? :left : :right, offset[2] > 0 ? :bottom : offset[2] < 0 ? :top : :center)

function Makie.plot!(p::Callout)
    map!(screen_position, p, [:projectionview, :viewport, :anchor], :dot)
    map!((d, o) -> [d, d + o], p, [:dot, :offset], :leader)
    map!((d, o) -> d + o + Vec2f(sign(o[1]) * 6, sign(o[2]) * 4), p, [:dot, :offset], :labelpos)
    map!(label_align, p, :offset, :align)
    map!(a -> RGBAf(1, 1, 1, 0.9a), p, :alpha, :linecolor)
    map!(a -> RGBAf(1, 1, 1, a), p, :alpha, :dotcolor)
    map!(d -> [d], p, :dot, :dots)
    lines!(p, p.leader; color = p.linecolor, linewidth = 2)
    scatter!(p, p.dots; color = p.dotcolor, markersize = 9)
    label!(p, :labelpos, :text, :alpha, p.align, p.fontsize)
    return p
end

"""
A label's text on a dark, see-through backing, readable over bright waves as
over the dark studio. `position`, `text` and `alpha` name nodes of the parent
plot's compute graph; the label's colours are derived there.
"""
function label!(parent, position, text, alpha, align, fontsize)
    map!(a -> RGBAf(1, 1, 1, a), parent, alpha, :label_textcolor)
    map!(a -> RGBAf(LABEL_BACKGROUND.r, LABEL_BACKGROUND.g, LABEL_BACKGROUND.b, 0.9a), parent, alpha, :label_background)
    map!(a -> RGBAf(1, 1, 1, 0.35a), parent, alpha, :label_stroke)
    map!(q -> [q], parent, position, :label_positions)
    map!(t -> [t], parent, text, :label_texts)
    return textlabel!(parent, parent.label_positions; text = parent.label_texts, text_align = align, fontsize,
                      text_color = parent.label_textcolor, background_color = parent.label_background,
                      strokecolor = parent.label_stroke, strokewidth = 1, padding = (9, 9, 6, 6), cornerradius = 4)
end

"""
    caption(; text, alpha, line, centre, fontsize)

One statement at the bottom of the frame, as a subtitle sits: centred at
`centre` (figure pixels), `line` counting up from the bottom for a second line
above it. `alpha` fades it in and out.
"""
@recipe Caption () begin
    "The caption's text."
    text = ""
    "Opacity, 0 (gone) to 1."
    alpha = 1.0
    "Which line, counting up from the bottom of the frame."
    line = 0
    "Horizontal centre in figure pixels."
    centre = 640
    "Font size in pixels."
    fontsize = 30
    Makie.mixin_generic_plot_attributes()...
end

function Makie.plot!(p::Caption)
    map!((l, c, f) -> Point2f(c, 30 + 1.6f0 * f * l), p, [:line, :centre, :fontsize], :position)
    label!(p, :position, :text, :alpha, (:center, :bottom), p.fontsize)
    return p
end

"""
    viewof(scene) -> NamedTuple

The callout attributes that place a label by `scene`'s camera: splat into
`callout!(overlay, anchor; text, viewof(scene)...)`. Its projection and viewport
follow the scene, so the label follows a moving camera.
"""
viewof(scene::Scene) = (projectionview = scene.camera.projectionview, viewport = scene.viewport)
