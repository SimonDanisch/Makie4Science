# What a scene offers the editor, collected while it is built.
#
# VideoEditor lists every named plot under its name, with every attribute Makie
# has. For a film that is the wrong list twice over: the parts of one instrument
# are many plots with internal names, and the shading attributes are GLMakie's,
# which a ray-traced scene does not read. A part's build therefore names its
# objects (readable labels, the plots of one object together) and what each
# offers: for a solid, whether it is shown; for a label, its words, fade, offset
# and size. It returns them beside its scene.

"""What the editor offers of a solid object: whether it is shown."""
const SOLID = ("visible",)

"""What the editor offers of a callout or caption: its words, its fade, where it sits, its size."""
const LABEL = ("text", "alpha", "offset", "fontsize", "visible")

"""
    Inspector()

The inspector groups (`objects`) a part's scene offers VideoEditor, filled in
by the functions that build it ([`solid!`](@ref), [`label!`](@ref),
[`object!`](@ref)) and returned beside the scene:
`(scene = ..., args = ..., objects = inspector.objects)`.
"""
struct Inspector
    objects::Vector{NamedTuple}
end
Inspector() = Inspector(NamedTuple[])

"""
    solid!(inspector, label, plots...) -> inspector

One object of solids: `plots` move together, the first is the pivot; the
editor offers whether it is shown. `nothing` collects nothing, so a builder
can take an optional inspector.
"""
function solid!(ins::Inspector, label::AbstractString, plots::Makie.AbstractPlot...)
    push!(ins.objects, (; label, plots = [p.name[] for p in plots], attributes = SOLID))
    return ins
end
solid!(::Nothing, label, plots...) = nothing

"""
    label!(inspector, label, plot) -> inspector

One callout or caption: the editor offers its words, fade, offset and size.
"""
function label!(ins::Inspector, label::AbstractString, plot::Makie.AbstractPlot)
    push!(ins.objects, (; label, plots = [plot.name[]], attributes = LABEL))
    return ins
end
label!(::Nothing, label, plot) = nothing

"""What the editor offers of a drawn line or shape: its colour, fade, width and whether it is shown."""
const DRAWING = ("color", "alpha", "linewidth", "visible")

"""
    object!(inspector, label, plots...; attributes = DRAWING) -> inspector

One object of a flat picture (a curve, a grid, an image): `plots` move
together, the editor offers `attributes` of them. `nothing` collects nothing.
"""
function object!(ins::Inspector, label::AbstractString, plots::Makie.AbstractPlot...; attributes = DRAWING)
    push!(ins.objects, (; label, plots = [p.name[] for p in plots], attributes))
    return ins
end
object!(::Nothing, label, plots...; attributes = DRAWING) = nothing

"""A plot name as a label: `lens_cell` reads `Lens cell`."""
partlabel(name::Symbol) = uppercasefirst(replace(String(name), '_' => ' '))
