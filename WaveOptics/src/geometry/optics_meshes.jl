# 3D models of optics: lens elements and mechanics, cut open, in a studio.

"""Profile of a part: an annulus, or a disc when it reaches the axis."""
part_profile(p::Part) = iszero(p.r0) ? disc(p.x0, p.x1, p.r1) : annulus(p.x0, p.x1, p.r0, p.r1)

"""A glass's index of refraction across the visible spectrum (nm), from the Cauchy fit the simulation uses."""
ior_spectrum(g::Glass) = Hikari.PiecewiseLinearSpectrum(Tuple(Float32.(360:10:830)),
                                                        Tuple(Float32[refractive_index(g, λ / 1000) for λ in 360:10:830]))

"""
What an anti-reflection coating leaves of bare glass's reflection, per colour:
a single magnesium fluoride layer is weakest in the green, so reflections look
purple-blue; a camera lens's multilayer coating leaves a faint green.
"""
const COATINGS = (mgf2 = (0.45, 0.30, 0.55), multi = (0.06, 0.12, 0.05), none = (1, 1, 1))

"""
The material a glass is drawn in: its own dispersion, so white light splits at
its surfaces; flints (the dispersive, lead-bearing ones, Abbe number below 50)
faintly yellow; the residual reflection of its `coating`.
"""
glass_material(g::Glass; coating = :mgf2) = Hikari.Dielectric(; index = ior_spectrum(g),
    Kt = g.Vd < 50 ? (0.97, 0.97, 0.93) : (1, 1, 1), Kr = getfield(COATINGS, coating))

"A lens's ground bevels: frosted, not polished."
const GROUND_GLASS = Hikari.Dielectric(; index = 1.52f0, roughness = 0.4f0)
"A lens's rim, blackened against stray light as on real optics."
const EDGE_PAINT = Hikari.CoatedDiffuse(reflectance = (0.02, 0.02, 0.022), roughness = 0.5)

"""
    lens_meshes(e, name; φ, caps, gap, chamfer, coating, n, radial) -> Vector{(; name, mesh, material)}

A lens element between the angles `φ`: its polished surfaces (`name`) in its
glass with `coating`; with `caps`, the cut faces (`name_cut`), bare as a sawn
face is; its ground bevels (`name_bevel`) and its rim painted black
(`name_rim`). `n` segments around, `radial` points along each surface.
"""
function lens_meshes(e::Element, name::Symbol; φ = (π, 2π), caps = true, gap = 0f0,
                     chamfer = clamp(0.012f0 * e.a, 0f0, 0.6f0), coating = :mgf2, n = 512, radial = 128)
    prof = profile(e; gap, chamfer, n = radial)
    bevelled = chamfer > 0
    faces, bevels, rim = bevelled ? ([2, 6], [3, 5], [4]) : ([2, 4], Int[], [3])
    out = @NamedTuple{name::Symbol, mesh::Any, material::Any}[
        (; name, mesh = revolve(prof; φ, n, caps = false, sweep = faces), material = glass_material(e.glass; coating)),
        (name = Symbol(name, :_rim), mesh = revolve(prof; φ, n, caps = false, sweep = rim), material = EDGE_PAINT)]
    bevelled && push!(out, (name = Symbol(name, :_bevel), mesh = revolve(prof; φ, n, caps = false, sweep = bevels),
                            material = GROUND_GLASS))
    caps && push!(out, (name = Symbol(name, :_cut), mesh = revolve(prof; φ, n, caps = true, sweep = Int[]),
                        material = glass_material(e.glass; coating = :none)))
    return out
end

"""
    optics_meshes(elements, parts; φ) -> Vector{(; name, mesh, material)}

Meshes (in the system's units) of lens elements and mechanics, the half
between the angles `φ` (the bottom half by default), each named for what it is:
`lens_1`, `lens_2` front to back (with their cut faces, bevels and rims, see
[`lens_meshes`](@ref)), then each part by its `name`. An element
cemented to the one before gets a hair of air, so the two glass solids do not
share a surface. A part with an `inner` look gets its bore as a separate mesh
in that material, named `name_inside`. Parts left with the default name are
numbered (`part_3`), so every name is unique.
"""
function optics_meshes(elements, parts; φ = (π, 2π))
    out = @NamedTuple{name::Symbol, mesh::Any, material::Any}[]
    for (k, e) in enumerate(elements)
        cemented = k > 1 && elements[k-1].back == e.front
        append!(out, lens_meshes(e, Symbol(:lens_, k); φ, gap = cemented ? 0.02f0 : 0f0))
    end
    for (k, p) in enumerate(parts)
        p.look === nothing && continue
        name = p.name === :part ? Symbol(:part_, k) : p.name
        prof = part_profile(p)
        if p.inner === nothing
            push!(out, (; name, mesh = revolve(prof; φ), material = MAT[p.look]))
        else
            # annulus runs: 1 bore, 2 back, 3 outside, 4 front
            push!(out, (; name, mesh = revolve(prof; φ, sweep = 2:4), material = MAT[p.look]))
            push!(out, (name = Symbol(name, :_inside), mesh = revolve(prof; φ, sweep = 1:1, caps = false),
                        material = MAT[p.inner]))
        end
    end
    allunique(m.name for m in out) || error("two parts share a name: $(join((m.name for m in out), ", "))")
    return out
end

telescope_meshes(t::Refractor; φ = (π, 2π)) = optics_meshes(t.sys.elements, t.parts; φ)

"""Keep the floor below all visible geometry, including larger telescope apertures."""
studio_floor(meshes, S, offset) = min(-3.5f0, offset[3] + S * minimum(p[3] for m in meshes for p in coordinates(m.mesh)) - 0.35f0)
