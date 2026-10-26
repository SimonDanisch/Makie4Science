"""
Render chosen frames through VideoEditor's bake path (traced HDR, OIDN, grade,
display transform) with different trace settings, to choose the film's render
settings and to judge its glass.

    julia --project=<env with Telescope, VideoEditor and RayMakie> -i Telescope/tools/glass_study.jl
    julia> glass_study("gen/glass_study", "spp256"; samples = 256, max_depth = 24)

Each setting is its own study project in `dir/name`, with its own caches; the
film's project is not touched. Further integrator settings (`options`, such as
`russian_roulette_depth`, `regularize`, `max_component_value`) go to the bake.
Against a 2048 spp reference (depth 64, no roulette, regularisation or clamp)
OIDN's output at 64/256/1024 spp differed by 0.2–0.6 / 0.2–0.4 / 0.1–0.3 mean
levels; 256 spp at depth 24 is the film's setting.
"""

using Telescope, ScienceFilms, VideoEditor, RayMakie
import Mantle
import VideoEditor as VE

"The study frames: a beat and a moment of its narration timing, named."
const STUDY_FRAMES = [
    ("lens_closeup", "a0_intro", t -> t.starts[4] + 3f0),
    ("instruments", "a0_intro", t -> t.starts[6] + 1f0),
    ("telescope_cut", "b01_telescope", t -> t.starts[6] + 1.5f0),
    ("camera_lenses", "c3_lenses", t -> t.starts[5] + 1f0),
]

"""
    glass_study(dir, name; samples, max_depth, frames = STUDY_FRAMES, options...) -> Vector{(frame, seconds, png)}

Render every study frame with these trace settings into `dir/name`.
"""
function glass_study(dir, name; samples, max_depth, frames = STUDY_FRAMES, fps = 30, options...)
    film = Telescope.FILM
    out = mkpath(joinpath(dir, name))
    VE.usebackend!(RayMakie)
    seq = VE.Sequence(VE.Clip[], fps)
    seq.canvas = (1920, 1080)
    starts = Dict{String, Int}()
    for beat in unique(f[2] for f in frames)
        starts[beat] = VE.seqlength(seq)
        clips = partclips(film, beat; frames = ceil(Int, film.timing(beat).duration * fps), fps, spp = samples,
                          max_depth)
        foreach(clip -> (clip.start = starts[beat]; VE.addclip!(seq, clip)), clips)
        merge!(first(clips).source.bakescreenopts, Dict{Symbol, Any}(options))
    end
    VE.enabletrackcache!(seq, joinpath(out, "study.videoedit.frames"))
    VE.saveproject(joinpath(out, "study.videoedit"), seq)
    engine = VE.FxEngine(Mantle.defaultbackend())
    readers = Dict{String, Any}()
    pixels = zeros(VE.RGB{VE.N0f8}, seq.canvas...)
    results = Tuple{String, Float64, String}[]
    try
        VE.withfinalscenes(seq) do
            for (label, beat, moment) in frames
                n = starts[beat] + round(Int, moment(film.timing(beat)) * fps)
                seconds = @elapsed VE.renderframe!(pixels, seq, n, readers, engine)
                png = joinpath(out, label * ".png")
                VE.PNGFiles.save(png, permutedims(pixels))
                push!(results, (label, seconds, png))
                println("STUDY ", name, " ", label, " ", round(seconds; digits = 1), " s")
                flush(stdout)
            end
        end
    finally
        VE.emptyengine!(engine)
        foreach(close, values(readers))
        foreach(c -> c.source.live === nothing || close(c.source), seq.clips)
    end
    return results
end
