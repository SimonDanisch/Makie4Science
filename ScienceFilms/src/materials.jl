# Shared materials: the mechanics of instruments, the studio floor, filters.

const MAT = (
    anodized = Hikari.CoatedDiffuse(reflectance = (0.015, 0.015, 0.017), roughness = 0.25),
    paint = Hikari.CoatedDiffuse(reflectance = (0.8, 0.8, 0.78), roughness = 0.08),
    aluminium = Hikari.Conductor(eta = (1.657f0, 0.880f0, 0.521f0), k = (9.224f0, 6.270f0, 4.837f0), roughness = 0.12),
    satin_aluminium = Hikari.Conductor(eta = (1.657f0, 0.880f0, 0.521f0), k = (9.224f0, 6.270f0, 4.837f0), roughness = 0.10,
                                       reflectance = (0.94, 0.92, 0.89)),
    floor = Hikari.Diffuse(Kd = (0.24, 0.205, 0.17)),
    sensor = Hikari.CoatedDiffuse(reflectance = (0.03, 0.02, 0.05), roughness = 0.0),
    rubber = Hikari.Diffuse(Kd = (0.025, 0.025, 0.025)),
    # a filter darkening towards its rim, in three steps
    filter_light = Hikari.Dielectric(Kt = (0.7, 0.7, 0.7), index = 1.5),
    filter_mid = Hikari.Dielectric(Kt = (0.35, 0.35, 0.35), index = 1.5),
    filter_dark = Hikari.Dielectric(Kt = (0.1, 0.1, 0.1), index = 1.5),
)

# ── Materials as numbers an editor keys ──────────────────────────────────────

"""
    texnumber(t) -> RGBf, Float32 or nothing

A material parameter's constant value: a colour as `RGBf`, a number as
`Float32`; `nothing` for a texture, which has no single value to edit.
"""
texnumber(t::Hikari.TexHandle) =
    t.kind == Hikari.TexKind.CONST_SPECTRUM ? RGBf(t.rgb.c[1], t.rgb.c[2], t.rgb.c[3]) :
    t.kind == Hikari.TexKind.CONST_FLOAT ? t.f : nothing
texnumber(::Any) = nothing

"The material parameter `v` stands for, stored as `old` was."
texvalue(::Hikari.TexHandle, v::RGBf) = Hikari.TexHandle(Hikari.RGBSpectrum(Point4f(v.r, v.g, v.b, 1f0)))
texvalue(::Hikari.TexHandle, v::Real) = Hikari.TexHandle(Float32(v))

"""
    materialfields(material) -> NamedTuple

The fields of a material an editor offers, by the name it shows: each name sets
one field, or several that move together (`roughness` sets both directions).
"""
materialfields(::Hikari.Diffuse) = (colour = (:Kd,),)
materialfields(::Hikari.CoatedDiffuse) = (colour = (:reflectance,), roughness = (:u_roughness, :v_roughness))
materialfields(::Hikari.Conductor) = (tint = (:reflectance,), roughness = (:roughness,))
materialfields(::Hikari.Dielectric) = (tint = (:Kt,), index = (:index,), roughness = (:u_roughness, :v_roughness))
materialfields(::Hikari.Emissive) = (light = (:Le,),)
materialfields(::Hikari.Material) = (;)

"""
    materialparams(material) -> NamedTuple

The numbers a material's look is made of: colours as `RGBf`, the rest as
`Float32`. Only constant parameters; a textured one has no single number.
"""
function materialparams(m::Hikari.Material)
    found = [name => texnumber(getfield(m, first(fields))) for (name, fields) in pairs(materialfields(m))]
    return NamedTuple(name => v for (name, v) in found if v !== nothing)
end
materialparams(m::Hikari.MediumInterface) = materialparams(m.material)

"""
    withparams(material, params) -> material

`material` with the numbers `params` (as [`materialparams`](@ref) names them)
in place of its own, every other field as it was.
"""
function withparams(m::Hikari.Material, params::NamedTuple)
    fields = materialfields(m)
    new = Dict{Symbol, Any}(f => texvalue(getfield(m, f), v) for (name, v) in pairs(params) for f in fields[name])
    return typeof(m)((get(new, f, getfield(m, f)) for f in fieldnames(typeof(m)))...)
end
withparams(m::Hikari.MediumInterface, params::NamedTuple) =
    Hikari.MediumInterface(withparams(m.material, params); inside = m.inside, outside = m.outside,
                           emission = m.emission)
