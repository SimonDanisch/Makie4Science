# The refractor: an f/10 cemented achromat in a tube, in wavelength units.
#
# Real telescope ~100 mm / f = 1000 mm; here the aperture is 40 wavelengths, so
# the light is drawn about 4500× longer in wavelength than green light.

"""
    achromat(; f, a, x0) -> Vector{Element}

Thin-lens Fraunhofer achromat of focal length `f`: an equiconvex BK7 crown
cemented to an F2 flint whose powers cancel the colour error, thickened to a
rim of semi-diameter `a`.
"""
function achromat(; f = 400f0, a = 22f0, x0 = 0f0, crown = BK7, flint = F2)
    V1, V2 = crown.Vd, flint.Vd
    φ1 = V1 / (V1 - V2) / f
    φ2 = -V2 / (V1 - V2) / f
    R = 2 * (crown.nd - 1) / φ1                  # equiconvex crown
    # flint: cemented front R3 = -R, back from its power
    R4 = 1 / (1 / -R - φ2 / (flint.nd - 1))
    sagR = a^2 / (2R)
    t1 = 2sagR + 1.8f0                           # crown edge 1.8
    t2 = 2f0
    return [Element(x0, R, -R, t1, a, crown), Element(x0 + t1, -R, R4, t2, a, flint)]
end

"""A refractor telescope: its optics and its mechanics."""
struct Refractor
    sys::System
    parts::Vector{Part}
    D::Float32
end

"""
    refractor(; D, f, coating) -> Refractor

`D` the clear aperture, set by the lip of the lens cell; a black-lined tube;
a camera whose sensor sits at the paraxial focus. Everything the light could
bounce off is blackened, and the glass is `coating`-graded, so the only waves
besides the focused one are the ones the aperture edge makes.
"""
function refractor(; D = 30f0, f = 120f0, tube = D / 2 + 4f0, coating = 1.5f0)
    a = D / 2
    lens = achromat(; f, a = a + 1.5f0)
    xb = lens[end].back.x
    xf, _ = paraxial_focus(System(; elements = lens))
    lining = 3f0
    # The camera's bore is wide: with the wavelength this exaggerated, the
    # diffraction pattern at the focus is tens of wavelengths across, and a
    # narrow opening would clip its rings.
    bore = 14f0
    cell = tube + 1.5f0
    parts = [
        # a black baffle in front, outside the lens cell: light that misses the
        # instrument is swallowed instead of running along its outside
        Part(-6f0, -3f0, cell, 60f0; look = nothing, sim = :black, σ = 4f0, ramp = 1.5f0),
        # lens cell: the lip in front is the aperture stop, a metal core with
        # a black front; then the ring around the rims
        Part(-2.5f0, -1f0, a, cell; look = nothing, sim = :black, σ = 6f0, ramp = 1.5f0),
        Part(-2.5f0, 0f0, a, cell; name = :cell_lip, sim = :none),
        Part(-1f0, 0f0, a, cell; look = nothing),
        Part(0f0, xb + 2f0, lens[1].a + 0.05f0, cell; name = :lens_cell),
        # tube, satin aluminium outside, black inside
        # (ending where the back plate begins: drawn parts must not overlap, or
        # their faces on the cut lie in one plane and flicker against each other)
        Part(xb + 2f0, xf - 15f0, tube, tube + 1f0; name = :tube, look = :satin_aluminium, inner = :anodized),
        Part(xb + 2f0, xf - 14f0, tube - lining, tube; look = nothing, sim = :black),
        # back plate, then the camera body (wider than the tube behind a small lens)
        Part(xf - 15f0, xf - 14f0, min(bore, tube), max(bore + 2.5f0, tube + 1f0); name = :back_plate),
        Part(xf - 14f0, xf + 10f0, bore, bore + 2.5f0; name = :camera_body),
        Part(xf + 9f0, xf + 10f0, 0f0, bore; name = :camera_back),
        # the sensor: its face at the focus, absorbing what arrives
        Part(xf, xf + 0.8f0, 0f0, bore - 2f0; name = :sensor, look = :sensor, sim = :none),
        Part(xf, xf + 9f0, 0f0, bore - 0.1f0; look = nothing, sim = :black),
    ]
    metal = Metal[]
    absorbers = Absorber[]
    for p in parts, (y0, y1) in slice_spans(p)
        p.sim === :metal && push!(metal, Metal(p.x0, y0, p.x1, y1))
        p.sim === :black && push!(absorbers, Black(p.x0, y0, p.x1, y1; σ = p.σ, ramp = p.ramp))
    end
    sys = System(; elements = lens, metal, absorbers, sensor = xf, coating)
    return Refractor(sys, parts, Float32(D))
end

"""
    soft_edged(tel; r0, x0, x1, σ) -> Refractor

`tel` with a soft edge: a filter in front of the objective (between `x0` and
`x1`) that lets the light through freely up to radius `r0` and dims it
smoothly to almost nothing at the rim, instead of the lens cell cutting it off
all at once; `σ` is how dark it gets. Drawn as three rings of darker and
darker glass.
"""
function soft_edged(tel::Refractor; r0 = 6f0, x0 = -9f0, x1 = -3f0, σ = 2f0)
    a = tel.D / 2
    step = (a - r0) / 3
    rings = [Part(x0, x1, r0 + (k - 1) * step, r0 + k * step; look = look, sim = :none)
             for (k, look) in enumerate((:filter_light, :filter_mid, :filter_dark))]
    sys = tel.sys
    soft = System(; elements = sys.elements, metal = sys.metal, absorbers = [sys.absorbers; Apodizer(x0, x1, r0, a; σ)],
                  λµm = sys.λµm, sensor = sys.sensor, coating = sys.coating)
    return Refractor(soft, [tel.parts; rings], tel.D)
end
