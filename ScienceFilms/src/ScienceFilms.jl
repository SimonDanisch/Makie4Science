"""
The film toolkit every Makie4Science film shares.

A film is a set of Makie scenes, each built once and animated by sparse keys on
named plot attributes, the camera and the scene's declared arguments, so every
motion is editable in VideoEditor. This package has what that needs and no
physics: the colour language and materials, framing and a studio, keys placed
by narration timing, callouts and captions, and the `Film` the editor
assembles. Load VideoEditor to turn a film's parts into editable clips.
"""
module ScienceFilms

using Makie, GeometryBasics, Hikari, LinearAlgebra
using Makie: VecTypes
using GeometryBasics: origin

include("palette.jl")
include("materials.jl")
include("inspector.jl")
include("scene.jl")
include("keys.jl")
include("annotations.jl")
include("film.jl")

export PALETTE, SUNLIGHT, SECONDARY_LIGHT, MAT
export Pose, frame3d, flat, look!, studio!, softbox!, Keyframes
export Key, Timing, Animation, animation, ramp, appear, through, posekeys
export Callout, Caption, callout, callout!, caption, caption!, viewof
export Beat, Shot, Film, buildpart, partclip, animate!
export Inspector, solid!, label!, alike!, materialparams, withparams

end
