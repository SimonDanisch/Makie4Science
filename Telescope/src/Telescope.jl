"""
"What makes a picture sharp?": a telescope explainer.

Its data is the simulated steady states of its telescopes and the approved
narration, both Pkg artifacts on this repository's `telescope-v1` release
(`tools/make_artifacts.jl` builds them). Its parts are scenes built from that
data with WaveOptics and ScienceFilms; `FILM` is what VideoEditor assembles
(`ScienceFilms.partclip(Telescope.FILM, name; ...)`).
"""
module Telescope

using Makie, GeometryBasics, Hikari, LinearAlgebra, JSON
using LazyArtifacts
import WaveOptics
using WaveOptics: device, CameraLens, Continuous, FarSource, GLOW, Grid, Instruments, Leftover, Medium,
                  NearSource, PLOT_GAP, PlaneWave, Refraction, Refractor, W, Wave, Wavelets, amplitude, blank,
                  bundle_spot, cooke_camera, cutaway!, glow, hide_source!, inside, landing, lens_section,
                  light_profile, light_up!, outer_radius, outline_mask!, phase_field, place, rasterize, ray_fans,
                  refraction_field, refractor, rim_mask, show_lens!, simulate, singlet_camera, steady,
                  telescope_meshes, toimage, w3, ys
using ScienceFilms: Beat, Film, PALETTE, Pose, SECONDARY_LIGHT, SUNLIGHT, Shot, Timing, animation, appear,
                    buildpart, callout!, ease, frame3d, posekeys, ramp, viewof, Inspector, solid!, label!,
                    alike!, partlabel

include("data.jl")
include("film.jl")

end
