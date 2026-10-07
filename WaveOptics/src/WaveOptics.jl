"""
Light and lenses for films: the physics, and the pictures it makes.

Optical systems in the meridional plane drive a GPU scalar wave solver, a ray
tracer and 3D models of the same instruments. Analytic fields (stars, far
sources, Huygens wavelets, Airy patterns) need no simulation. What the films
show of them, glowing cuts through the optics in a studio, is built here too.
"""
module WaveOptics

using Makie, GeometryBasics, Hikari, LinearAlgebra, Random
using Makie: VecTypes
using GeometryBasics: origin
import KernelAbstractions as KA
using KernelAbstractions: @kernel, @index, @Const
import Mantle
using ScienceFilms: PALETTE, SUNLIGHT, SECONDARY_LIGHT, MAT, Pose, studio!, solid!, partlabel

"The GPU the simulations run on."
device() = Mantle.defaultbackend()

include("optics.jl")
include("wave.jl")
include("huygens.jl")
include("refractor.jl")
include("cameralens.jl")
include("skew.jl")
include("geometry/revolve.jl")
include("geometry/optics_meshes.jl")
include("geometry/instruments.jl")
include("glow.jl")
include("cutaway.jl")
include("airy.jl")
include("sources.jl")
include("refraction.jl")

export device
export Grid, Medium, Wave, PlaneWave, Continuous, simulate, steady, amplitude, rasterize, xs, ys
export Refractor, refractor, CameraLens, cooke_camera, singlet_camera, ray_fans, bundle_spot
export Wavelets, FarSource, NearSource, Refraction, refraction_field, landing, light_profile
export Instruments, optics_meshes, telescope_meshes, cutaway!, glow, toimage

end
