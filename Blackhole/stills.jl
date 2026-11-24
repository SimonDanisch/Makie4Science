# Run in the Science4Makie environment after project.jl: single raster stills
# of a beat at chosen moments, with that beat's real narration timing, for
# review before a whole export.

using FileIO

"""
    beatstill(film, name, ts; canvas, dir) -> file names

Beat `name` built once, with the narration timing in `voice_root`, drawn at
each time in `ts` (seconds into the beat) and saved as `dir/<name>_<t>.png`.
"""
function beatstill(film, name, ts; canvas = (1280, 720), dir = joinpath(@__DIR__, "renders", "checks"),
                   voice_root = joinpath(@__DIR__, "voice_v6"))
    t = read_timing(name; root = voice_root)
    args = Dict("beat" => name, "starts" => t.starts, "ends" => t.ends, "duration" => t.duration)
    build = VE.programscene(joinpath(@__DIR__, "film", "film.jl"); args)
    clip = VE.sceneclip(VE.buildscene(build); build, frames=ceil(Int,t.duration*30), canvas, framerate=30, backend=:RayMakie)
    keybeat!(clip, film)
    seq = VE.Sequence([clip], 30); seq.canvas = canvas
    mkpath(dir)
    VE.enabletrackcache!(seq, joinpath(dir, name * ".frames"))
    engine = VE.FxEngine(VE.Mantle.defaultbackend())
    readers = Dict{String,Any}()
    out = zeros(VE.RGB{VE.N0f8}, canvas...)
    try
        return map(ts) do s
            VE.renderframe!(out, seq, round(Int,s*30), readers, engine)
            file = "$(name)_$(round(s; digits=1)).png"
            save(joinpath(dir,file), permutedims(out))
            file
        end
    finally
        VE.emptyengine!(engine)
        close(clip.source)
    end
end
