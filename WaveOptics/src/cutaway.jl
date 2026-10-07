# Cutaways: optics cut open in a studio, with a sheet in the cut glowing with
# the light simulated in it. The meshes are built once; only the glow follows
# an Observable.

"""World units per wavelength in the telescope cutaways."""
const W = 0.1f0
w3(x, y) = Point3f(W * x, W * y, 0)

"""A flat rectangle in z = `z` over `rect` (world units), uv spanning it."""
function sheet(rect::Rect2f, z)
    lo, hi = minimum(rect), maximum(rect)
    P = Point3f[(lo[1], lo[2], z), (hi[1], lo[2], z), (hi[1], hi[2], z), (lo[1], hi[2], z)]
    uv = Vec2f[(0, 0), (1, 0), (1, 1), (0, 1)]
    F = GLTriangleFace[(1, 2, 3), (1, 3, 4)]
    return GeometryBasics.Mesh(P, F; normal = fill(Vec3f(0, 0, 1), 4), uv = uv)
end

"""See-through emitter: no surface at all, only the texture's glow where a ray crosses it."""
wave_material(tex; scale = 1f0) = Hikari.MediumInterface(
    Hikari.NullMaterial();
    emission = Hikari.Emissive(Le = Hikari.Texture(tex), scale = scale, two_sided = true))

"""
    cutaway!(scene, meshes, g, tex, xmid; S, scale, offset, studio, name, inspector) -> sheet plot

Put `meshes` (in the optics' units, scaled by `S` into world units) and a sheet
glowing with the texture `tex` (an `Observable` of an RGBSpectrum matrix over
grid `g`, in grid layout, or with `imagelayout` already in the image layout
`toimage` makes, which saves a copy per change) into `scene`, shifted by `offset`; with `studio`, the floor and lights
centred on `xmid` (optics units). Each part is named `name_` and its own
name (`telescope_tube`), the sheet `name_sheet`; the meshes are built once, only
the glow follows `tex`. The sheet is not `inspectable`: it covers the whole cut,
and a click on a part should find the part.

With an `inspector` (see `ScienceFilms.Inspector`) each part is offered to the
editor as one object (`Telescope · tube`, its bore with it), with its material,
and the sheet as `Telescope · light on the cut`.
"""
function cutaway!(scene, meshes, g::Grid, tex::Observable, xmid; S = W, scale = 2f0,
                  offset = Vec3f(0), studio = true, name = :cutaway, visible = true, inspector = nothing,
                  imagelayout = false)
    plots = [part.name => mesh!(scene, place(part.mesh, S, offset); material = part.material,
                                name = Symbol(name, "_", part.name), visible)
             for part in meshes]
    title = partlabel(name)
    for (part, plot) in plots
        endswith(String(part), "_inside") && continue
        inside = [p for (n, p) in plots if n === Symbol(part, :_inside)]
        solid!(inspector, string(title, " · ", lowercase(partlabel(part))), plot, inside...)
    end
    studio && studio!(scene, offset[1] + S * xmid; floor = studio_floor(meshes, S, offset), inspector)
    b = bounds(g)
    lo = S * minimum(b)
    # Hikari samples textures in image layout.
    glow = mesh!(scene, sheet(Rect2f(lo + Vec2f(offset[1], offset[2]), S * widths(b)), offset[3] + 0.01f0);
                 material = lift(t -> wave_material(imagelayout ? t : toimage(t); scale), tex), name = Symbol(name, "_sheet"),
                 visible, inspectable = false)
    solid!(inspector, string(title, " · light on the cut"), glow)
    return glow
end
