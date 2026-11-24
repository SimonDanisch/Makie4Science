# Shared scene geometry, colours and labels, plus performance helpers used
# only when generating the editor's keyframe tracks.

"""A camera pose: where it is, what it looks at, its vertical field of view."""
struct Pose
    eye::Vec3f
    lookat::Vec3f
    fov::Float32
end
Pose(eye, lookat; fov = 40) = Pose(Vec3f(eye), Vec3f(lookat), Float32(fov))
Base.:*(s::Real, p::Pose) = Pose(s * p.eye, s * p.lookat, s * p.fov)
Base.:+(a::Pose, b::Pose) = Pose(a.eye + b.eye, a.lookat + b.lookat, a.fov + b.fov)
mix(a, b, t) = (1 - ease(t)) * a + ease(t) * b

# A beat's animation belongs to the editor: builders make Observables, `perform`
# gives their keys from the narration timing (VideoEditor.Performance helpers).

"""Point a 3D scene's camera at `pose`."""
function look!(scene, pose::Pose; up = Vec3f(0, 0, 1))
    update_cam!(scene, pose.eye, pose.lookat, up)
    cameracontrols(scene).fov[] = pose.fov
    update_cam!(scene, cameracontrols(scene))
    return scene
end

# ── colours ─────────────────────────────────────────────────────────────────

const SPACE = RGBf(0.01, 0.01, 0.02)
const HOT = cgrad([RGBf(0, 0, 0), RGBf(0.35, 0.05, 0.01), RGBf(0.85, 0.3, 0.05), RGBf(1, 0.7, 0.3), RGBf(1, 0.97, 0.85)])
const ACCENT = RGBf(1.0, 0.78, 0.35)
const NOTE = RGBf(0.55, 0.75, 1.0)
const LABEL_BG = RGBf(0.06, 0.06, 0.07)

# ── frames ──────────────────────────────────────────────────────────────────

"""A full-frame 3D picture: figure, 3D scene (sunlit, for the Earth), and a pixel-space overlay for labels."""
function frame3d(canvas; background = SPACE, lights = sunlight())
    fig = Figure(; size = canvas, backgroundcolor = background, figure_padding = 0)
    ls = LScene(fig[1, 1]; show_axis = false, scenekw = (; backgroundcolor = background, lights))
    cam3d!(ls.scene; center = false)
    return fig, ls.scene, overlay(fig)
end

"""
A pixel-space overlay on `fig`, drawn over the figure's content whenever that
was created: lifted towards the camera, which is how Makie says "on top"
(`Menu` does the same), since a scene created before an axis is otherwise
covered by the axis' pictures.
"""
function overlay(fig)
    ov = labelscene!(Scene(fig.scene; camera = campixel!, clear = false))
    translate!(ov, 0, 0, 1000)
    return ov
end

"""A flat picture: a figure and a pixel-space overlay."""
function frame2d(canvas; background = SPACE, padding = (40, 40, 110, 40))
    fig = Figure(; size = canvas, backgroundcolor = background, figure_padding = padding, fontsize = 24)
    return fig, overlay(fig)
end

"""An axis with no decorations, for pictures."""
function picture_axis(pos; title = "", titlesize = 26, titlecolor = :white)
    ax = Axis(pos; aspect = DataAspect(), backgroundcolor = SPACE, title=filmtext(title), titlecolor, titlesize)
    hidedecorations!(ax); hidespines!(ax)
    return ax
end

# ── labels ──────────────────────────────────────────────────────────────────

"""A label on a dark backing; `pos`, `text` and `alpha` may be Observables."""
function label!(ov, pos, text; align = (:center, :center), fontsize = 26, alpha)
    plot=textlabel!(ov, pos; text=filmtext(text), text_align=align, fontsize,
        text_color=:white, text_alpha=alpha, background_color=(LABEL_BG,0.9f0),
        alpha, strokecolor=(:white,0.35f0), stroke_alpha=alpha,
        strokewidth=1,padding=(10,10,7,7),cornerradius=4)
    # Derived fades remain outputs of their authored controls, not independent
    # native inputs. Only a primary scalar may own an editable alpha control.
    alpha isa Observable && isempty(alpha.inputs) && plotattribute!(plot,:text_alpha,alpha)
    return plot
end

"""Where `p` (data or world coordinates) shows in `scene`, in figure pixels."""
function screen_position(scene, p)
    clip = scene.camera.projectionview[] * Vec4f(p[1], p[2], length(p) > 2 ? p[3] : 0f0, 1f0)
    ndc = Vec2f(clip[1], clip[2]) / clip[4]
    vp = Makie.viewport(scene)[]
    return Point2f(Vec2f(GeometryBasics.origin(vp)) .+ (ndc .+ 1f0) ./ 2f0 .* Vec2f(widths(vp)))
end

"""
    callout!(ov, scene, anchor, offset, text, alpha)

A dot on `anchor` (a point in `scene`, or an Observable of one), a leader and a
label `offset` pixels away, re-placed whenever the camera moves; faded by `alpha`.
"""
function callout!(ov, scene, anchor, offset, text, alpha::Observable; fontsize = 26)
    anchor = anchor isa Observable ? anchor : Observable(anchor)
    a = lift((p, _...) -> screen_position(scene, p), anchor, scene.camera.projectionview, Makie.viewport(scene))
    return pin!(ov, a, offset, text, alpha; fontsize)
end

"""A dot on the pixel position `at` (an Observable), a leader and a label `offset` pixels away; faded by `alpha`."""
function pin!(ov, at::Observable, offset, text, alpha::Observable; fontsize = 26)
    o = Vec2f(offset)
    t = lift(p -> p + o, at)
    lines!(ov, lift((p, q) -> [p, q], at, t); color = lift(x -> (:white, 0.9f0 * x), alpha), linewidth = 2)
    scatter!(ov, lift(p -> [p], at); color = lift(x -> (:white, x), alpha), markersize = 9)
    align = (o[1] >= 0 ? :left : :right, o[2] > 0 ? :bottom : o[2] < 0 ? :top : :center)
    label!(ov, lift(q -> q + Vec2f(sign(o[1]) * 6, sign(o[2]) * 4), t), text; align, alpha, fontsize)
    return ov
end

"""A circle of `radius` pixels around `centre` (Observables), as a closed line."""
circlepoints(centre, radius; n = 120) = [centre + radius * Vec2f(cos(θ), sin(θ)) for θ in range(0, 2π; length = n)]

"""A caption at the bottom of the frame (`line` counts up for a second one); `text` may be an Observable."""
caption!(ov, text, alpha::Observable; line = 0, fontsize = 32) =
    label!(ov, lift(vp -> Point2f(widths(vp)[1] / 2, 34 + 1.7f0 * fontsize * line), ov.viewport), text;
           align = (:center, :bottom), fontsize, alpha)

"""A heading at the top of the frame."""
heading!(ov, text, alpha::Observable; fontsize = 36) =
    label!(ov, lift(s -> Point2f(s[1] / 2, s[2] - 40), lift(widths, ov.viewport)), text;
           align = (:center, :top), fontsize, alpha)

"""Colour `c` at opacity `a`, for colour attributes driven by an alpha Observable."""
faded(c, alpha::Observable) = lift(a -> (c, a), alpha)

"""The corners of rectangle `r`, grown by `pad`, as a closed line."""
function outline(r; pad = 0)
    o, w = Vec2f(GeometryBasics.origin(r)) .- pad, Vec2f(widths(r)) .+ 2pad
    return Point2f[o, o + Vec2f(w[1], 0), o + w, o + Vec2f(0, w[2]), o]
end
