# "What makes a picture sharp?": a telescope explainer, as Makie scenes
# animated by sparse keys. Every part is built once by a function of the film's
# data; its motion is an `Animation`, keys on named plots, the camera and the
# scene's arguments, placed by the narration's line timing. VideoEditor turns
# each part into clips whose keys are ordinary, editable keyframes.

"The approved narration: a WAV per narrated part and each beat's line timing."
narration_dir() = artifact"telescope-narration"

"When each line of beat `name` is spoken."
narration_timing(name::AbstractString) = Timing(joinpath(narration_dir(), name * ".timing"))

"The narration of part `name`, as approved."
narration_voice(name::AbstractString) = joinpath(narration_dir(), name * ".wav")

"Every part of the film by name: its beats, its shots and its montages."
const TELESCOPE_PARTS = Dict{String, Union{Beat, Shot, Montage}}(p.name => p for p in (
    beat_intro(), beat_wave(), beat_telescope(), beat_refraction(), beat_arrival(), beat_spot(), beat_adding(),
    beat_centre(), beat_dimmer(), beat_dark(), beat_rule(), beat_opening(), beat_colours(), beat_formula(),
    beat_window_again(), beat_lenses(), beat_lens_colours(), beat_zoom(), beat_limits(),
    shot_star(), shot_window(), shot_airy(), shot_blur(), shot_two_stars(), shot_sorting(),
    montage_rings(), montage_star(), montage_sky(), montage_direction(), montage_detail(), montage_simple(),
    montage_outro(),
))

"""
The film's narrated parts in order, as the approved cut (v8) has them: the
cold open and what light is, the star and the window, act 1 from the
telescope to the f-number, how detail is lost and why telescopes can be
simple, act 2, the outro.
"""
const TELESCOPE_CUT = [
    "a0_intro", "b00_wave", "scene_02", "scene_03", "scene_04",
    "b01_telescope", "b02_refraction", "b03_lens", "b04_spot", "b05_rings", "b06_adding", "b07_centre",
    "b08_dimmer", "b09_dark", "b10_rule", "b11_opening", "b12_colours", "b13_formula",
    "scene_10", "scene_12",
    "c1_window_again", "c3_lenses", "c4_colours", "c5_zoom", "c6_limits",
    "scene_17",
]

"The film, as the editor assembles it (`partclip`, `filmsequence`)."
const FILM = Film(@__MODULE__, TELESCOPE_PARTS, telescope_data, narration_timing, narration_voice, TELESCOPE_CUT)

"""
    part(canvas, args) -> NamedTuple

The scene recipe a VideoEditor project names (`VideoEditor.packagescene`):
the part `args["part"]`, a beat or a shot, built at `canvas`.
"""
part(canvas, args) = buildpart(FILM, canvas, args)
