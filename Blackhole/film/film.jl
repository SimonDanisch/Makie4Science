# The film's scene recipe, for VideoEditor's `programscene`: every beat is one
# clip built from this file, `args["beat"]` naming which, and built once. A
# beat exposes native plot attributes and camera properties. The project saves
# their performances as ordinary VideoEditor property tracks.

using Makie, GeometryBasics, FileIO, LinearAlgebra, Random, MeshIO
import Hikari, Raycore
import OIDNRunner # activates the non-destructive VideoEditor extension lazily
using Makie: Colors
using VideoEditor.Performance

"""
Each builder constructs its figure and connects its local construction values
to native plot attributes. `perform(builder, timing)` gives their initial keys
for the narration timing, as `(; picture, labels)`: the keys
the picture layer draws, and those only the labels draw.
"""
const PERFORMED = Dict{String,Function}()

include("common.jl")
include("spacetime.jl")
include(joinpath("..", "science.jl"))
include("data.jl")
include("earth.jl")
include("globe.jl")
include("plateau.jl")
include("blackhole.jl")
include("icons.jl")
for file in sort(readdir(joinpath(@__DIR__, "beats")))
    endswith(file, ".jl") && include(joinpath("beats", file))
end

sceneoptions(builder,args,plasma) = (;)
sceneoptions(::typeof(build_tiny),args,plasma) = (
    shadow_halfheight=Float32(get(args,"shadow_halfheight",480f0)),
)
sceneoptions(::typeof(build_credits),args,plasma) = (
    scientific_note=Bool(get(args,"scientific_note",true)),
)
blackholeoptions(args,plasma) = (
    step_scale=Float32(get(args,"step_scale",1)),
    emission_scale=Float32(get(args,"emission_scale",12)),
    sky_exposure=Float32(get(args,"sky_exposure",BH_SKY_EXPOSURE)),
    animate_plasma=Bool(get(args,"animate_plasma",false)),
    plasma_input=plasma,
)
sceneoptions(::typeof(build_two_numbers),args,plasma) = blackholeoptions(args,plasma)
sceneoptions(::typeof(build_black_hole),args,plasma) = merge(blackholeoptions(args,plasma),(
    disk_label_radius=Float32(get(args,"disk_label_radius",2.8f0)),
    doppler_label_radius=Float32(get(args,"doppler_label_radius",3f0)),
    shadow_label_follow_view=Bool(get(args,"shadow_label_follow_view",true)),
))

"The Earth and station markers stay in the labels layer as invisible native-property owners."
labelowner(name) = name === :earth || startswith(String(name), "site_")

function buildscene(canvas, args)
    layer = Symbol(get(args, "layer", "combined"))
    plasma = Observable{Any}(nothing)
    beat = args["beat"]
    builder = PERFORMED[beat]
    built = buildperformed(builder, canvas; layer, labels = Dict{String,String}(get(args, "labels", Dict())),
        keep_owners = labelowner, extra = (; plasma), sceneoptions(builder, args, plasma)...)
    NATIVE_PATHS[(beat, layer)] = built.paths
    NATIVE[(beat, layer)] = (; built.paths, built.transforms, built.aliases)
    return (scene = built.scene,)
end

"Each beat and layer's native property paths (as tools look them up), and with transforms/aliases."
const NATIVE_PATHS=Dict{Tuple{String,Symbol},Dict{String,String}}()
const NATIVE=Dict{Tuple{String,Symbol},Any}()

"""
    beatkeys(args, fps) -> Vector{(path, keys, discrete)}

Native Makie property tracks from the narration timing:
`("plot.attribute", [(frame, value, ease), ...], discrete)`. The picture layer is keyed with only what it draws, so
frames that differ in their labels alone are the same picture to the editor.
"""
function beatkeys(args, fps)
    builder = PERFORMED[args["beat"]]
    timing = Timing(Float32.(args["starts"]), Float32.(args["ends"]), Float32(args["duration"]))
    performed = perform(builder, timing)
    layer = Symbol(get(args, "layer", "combined"))
    haskey(NATIVE, (args["beat"], layer)) || Makie.free(buildscene((1280, 720), args).scene)
    return performedtracks(performed, NATIVE[(args["beat"], layer)], fps; layer)
end
