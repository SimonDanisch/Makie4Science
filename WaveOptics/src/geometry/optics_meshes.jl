# 3D models of optics: lens elements and mechanics, cut open, in a studio.

"""Profile of a part: an annulus, or a disc when it reaches the axis."""
part_profile(p::Part) = iszero(p.r0) ? disc(p.x0, p.x1, p.r1) : annulus(p.x0, p.x1, p.r0, p.r1)

"""
The material a glass is drawn in: its own index, crowns clear, flints (the
dispersive, lead-bearing ones, Abbe number below 50) faintly yellow.
"""
glass_material(g::Glass) = Hikari.Dielectric(Kt = g.Vd < 50 ? (0.95, 0.96, 0.9) : (0.9, 0.97, 1.0), index = g.nd)

"""
    optics_meshes(elements, parts; φ) -> Vector{(; name, mesh, material)}

Meshes (in the system's units) of lens elements and mechanics, the half
between the angles `φ` (the bottom half by default), each named for what it is:
`lens_1`, `lens_2` front to back, then each part by its `name`. An element
cemented to the one before gets a hair of air, so the two glass solids do not
share a surface. A part with an `inner` look gets its bore as a separate mesh
in that material, named `name_inside`. Parts left with the default name are
numbered (`part_3`), so every name is unique.
"""
function optics_meshes(elements, parts; φ = (π, 2π))
    out = @NamedTuple{name::Symbol, mesh::Any, material::Any}[]
    for (k, e) in enumerate(elements)
        cemented = k > 1 && elements[k-1].back == e.front
        push!(out, (name = Symbol(:lens_, k), mesh = revolve(profile(e; gap = cemented ? 0.02f0 : 0f0); φ),
                    material = glass_material(e.glass)))
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
