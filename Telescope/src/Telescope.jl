"""
"What makes a picture sharp?": a telescope explainer.

Its data is the simulated steady states of its telescopes and the approved
narration, both Pkg artifacts on this repository's `telescope-v1` release
(`tools/make_artifacts.jl` builds them). Its parts are scenes built from that
data with WaveOptics and ScienceFilms; `FILM` is what VideoEditor assembles:
`ScienceFilms.filmsequence(Telescope.FILM)` is the whole film,
`ScienceFilms.partclip(Telescope.FILM, name; ...)` one part of it.
"""
module Telescope

using Makie, GeometryBasics, Hikari, LinearAlgebra, JSON
using GeometryBasics: origin
using LazyArtifacts
import WaveOptics
using WaveOptics: device, AiryProfile, CameraLens, Continuous, DARK, FarSource, Fog, GLASS_TINT, GLOW, Grid,
                  Instruments, Leftover, Medium, NearSource, PLOT_GAP, PlaneWave, Refraction, Refractor,
                  SeekableWave, Star, W, Wave, Wavelets, along_sensor, amplitude, blank, blurred, bounds,
                  bundle_spot, cluster, collected, cooke_camera, crest_shells, cutaway!, delay, dim, energy, field,
                  glow, glow_pixels, hide_source!, inside, landing, lens_section, light_profile, light_up!,
                  optical_phase, optics_meshes, outer_radius, outline_mask!, pair_window_glow, path_glow!,
                  phase_field, place, rasterize, ray_fans, ray_glow, ray_glow!, readout_glow!, refracted,
                  refraction_field,
                  refractor, rim_mask, seek!, sensor_image, sensor_pixels, sheet, show_lens!, simulate,
                  singlet_camera, slip, smoothstep, spot_pixel_tiles, star_glow, star_on_pixels, steady,
                  telescope_meshes, toimage, truncate_path, w3, wave_material, window_glow, xs, ys, zoom_plot!
using ScienceFilms: Beat, Film, Montage, PALETTE, Pose, SECONDARY_LIGHT, SUNLIGHT, Shot, Timing, Key, animation,
                    appear, after, through, switch, constant, ramp, ease, frame3d, flat, look!, posekeys, studio!,
                    softbox!, buildpart, callout!, caption!, projectedlines!, viewof, screen_position, Inspector,
                    solid!, label!, alike!, object!, partlabel

include("data.jl")
include("common.jl")
include("intro.jl")
include("act1.jl")
include("paths.jl")
include("shots.jl")
include("act2.jl")
include("film.jl")

end
