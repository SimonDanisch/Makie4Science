# Only changed narration is generated. Preserve all existing voice takes and
# use natural speech duration to set the new shot lengths (no time compression).
# Pacing as voice.jl: lead, gap between lines, tail, speed; stress marks such
# as [word](+2) are passed to Kokoro, which speaks them stressed.
using VideoEditor, Mantle
using VideoEditor: FFMPEG_jll
const KokoroRunner = VideoEditor.KokoroRunner
const FILM_ROOT = normpath(joinpath(@__DIR__, ".."))
module EnglishScript
    include(joinpath(@__DIR__, "..", "film", "lines.jl"))
end
const EN_VOICE_MODEL = Ref{Any}(nothing)

function voice_en_v6(; root = joinpath(FILM_ROOT, "voice_v6"), beats = ("b1_recording", "b4_one_note", "b7_cleaning"),
                     lead = 0.8, gap = 0.45, tail = 1.5, speed = 0.95)
    mkpath(root)
    original = joinpath(FILM_ROOT, "voice")
    for name in readdir(original)
        dest = joinpath(root, name)
        isfile(dest) || cp(joinpath(original, name), dest)
    end
    EN_VOICE_MODEL[] === nothing && (EN_VOICE_MODEL[] = KokoroRunner.Kokoro(; backend = Mantle.defaultbackend()))
    k = EN_VOICE_MODEL[]
    rate = 24000
    for name in beats
        text = Dict(EnglishScript.BEATS)[name]
        samples = Float32[]; starts = Float32[]; ends = Float32[]
        append!(samples, zeros(Float32, round(Int, lead * rate)))
        for (i, line) in enumerate(text)
            i == 1 || append!(samples, zeros(Float32, round(Int, gap * rate)))
            push!(starts, length(samples) / rate)
            # hyphenated words as separate words, as voice.jl speaks them: Kokoro has no "thirty-two"
            spoken = replace(line, r"(?<=\w)-(?=\w)" => " ")
            voice = vec(Array(KokoroRunner.speak(k, spoken; voice = "af_heart", speed)))
            append!(samples, voice)
            push!(ends, length(samples) / rate)
        end
        append!(samples, zeros(Float32, round(Int, tail * rate)))
        pcm = round.(Int16, clamp.(samples, -1.0f0, 1.0f0) .* 32767)
        wav = joinpath(root, name * ".wav")
        command = `$(FFMPEG_jll.ffmpeg()) -v error -y -f s16le -ar $rate -ac 1 -i pipe:0 -c:a pcm_s16le $wav`
        open(command, "w") do io
            write(io, pcm)
        end
        open(joinpath(root, name * ".timing"), "w") do io
            println(io, hash(text)); println(io, join(starts, " "))
            println(io, join(ends, " ")); println(io, length(samples) / rate)
        end
        println(name, " ", round(length(samples) / rate; digits = 2), " seconds, natural pace")
        flush(stdout)
    end
    return root
end
