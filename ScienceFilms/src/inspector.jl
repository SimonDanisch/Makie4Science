# What a scene offers the editor, collected while it is built.
#
# VideoEditor lists every named plot under its name, with every attribute Makie
# has. For a film that is the wrong list twice over: the parts of one instrument
# are many plots with internal names, and the shading attributes are GLMakie's,
# which a ray-traced scene does not read. A part's build therefore names its
# objects (readable labels, the plots of one object together) and what each
# offers: for a solid, whether it is shown and its material; for a label, its
# words, fade, offset and size. It returns them beside its scene.

"""What the editor offers of a solid object: whether it is shown. Its look is its material."""
const SOLID = ("visible",)

"""What the editor offers of a callout or caption: its words, its fade, where it sits, its size."""
const LABEL = ("text", "alpha", "offset", "fontsize", "visible")

"""
    Inspector()

The inspector groups (`objects`) and material controls (`controls`) a part's
scene offers VideoEditor, filled in by the functions that build it ([`solid!`](@ref),
[`label!`](@ref)) and returned beside the scene:
`(scene = ..., args = ..., objects = inspector.objects, controls = inspector.controls)`.
"""
struct Inspector
    objects::Vector{NamedTuple}
    controls::Vector{NamedTuple}
end
Inspector() = Inspector(NamedTuple[], NamedTuple[])

"""
    solid!(inspector, label, plots...; materials = true) -> inspector

One object of solids: `plots` move together, the first is the pivot; the
editor offers whether it is shown and, with `materials`, per plot with a
constant material, that material ([`materialparams`](@ref)). `nothing` collects
nothing, so a builder can take an optional inspector.
"""
function solid!(ins::Inspector, label::AbstractString, plots::Makie.AbstractPlot...; materials = true)
    pivot = plots[1].name[]
    push!(ins.objects, (; label, plots = [p.name[] for p in plots], attributes = SOLID))
    materials || return ins
    for p in plots
        # `Telescope · tube · material`, and its bore `Telescope · tube · inside material`
        part = chopprefix(String(p.name[]), String(pivot) * "_")
        title = p.name[] === pivot ? "$label · material" : "$label · $(lowercase(partlabel(Symbol(part)))) material"
        control = materialcontrol(pivot, p; label = title)
        control === nothing || push!(ins.controls, control)
    end
    return ins
end
solid!(::Nothing, label, plots...; materials = true) = nothing

"""
    alike!(inspector, name => plot, ...) -> inspector

`plot` takes the material of the plot named `name` whenever the editor changes
it: two halves of one part, drawn as two plots, stay one material.
"""
function alike!(ins::Inspector, pairs::Pair{Symbol}...)
    for (name, plot) in pairs
        i = findfirst(c -> c.name === Symbol(name, :_material), ins.controls)
        i === nothing || push!(ins.controls[i].members, plot)
    end
    return ins
end
alike!(::Nothing, pairs...) = nothing

"""
    label!(inspector, label, plot) -> inspector

One callout or caption: the editor offers its words, fade, offset and size.
"""
function label!(ins::Inspector, label::AbstractString, plot::Makie.AbstractPlot)
    push!(ins.objects, (; label, plots = [plot.name[]], attributes = LABEL))
    return ins
end
label!(::Nothing, label, plot) = nothing

"""A plot name as a label: `lens_cell` reads `Lens cell`."""
partlabel(name::Symbol) = uppercasefirst(replace(String(name), '_' => ' '))

"""
    materialcontrol(object, plot; label) -> control group or nothing

`plot`'s material as editor controls (a VideoEditor recipe `controls` group)
shown with `object`, the pivot of the object `plot` belongs to: the numbers
[`materialparams`](@ref) reads from the material it was built with. Edited, the
material is built again from them and given to `plot` and to the `members`
added with [`alike!`](@ref); unedited, nothing is written. `nothing` for a
material without constant parameters (a texture's glow).
"""
function materialcontrol(object::Symbol, plot::Makie.AbstractPlot; label = "Material")
    original = plot.material[]
    original isa Hikari.Material || return nothing
    params = materialparams(original)
    isempty(params) && return nothing
    members = Makie.AbstractPlot[plot]
    current = Ref(params)
    function apply!(overrides, frame, fps)
        edited = merge(params, NamedTuple(Symbol(k) => v for (k, v) in overrides))
        edited == current[] && return nothing
        current[] = edited
        material = withparams(original, edited)
        foreach(p -> (p.material = material), members)
        return nothing
    end
    return (name = Symbol(plot.name[], :_material), label, sample = (frame, fps) -> params,
            apply! = apply!, object, detail = "Material", members)
end
