"""
Speak a beat's lines as its take: the WAV and the `.timing` of its lines.

    julia --project=<env with Telescope and KokoroRunner> Telescope/tools/speak_take.jl <beat> ...

Each line is spoken on its own by Kokoro, in the voice and at the speed of the
approved takes (`af_heart`, 0.95), `GAP` seconds apart, after `LEAD` seconds of
silence and before `TAIL`: the line timing is then exact, so the beat's keys
land on the words they show. Written to `gen/narration/<beat>.wav` and
`.timing`, which `make_artifacts.jl telescope-narration` packs. The text is
read as the approved takes read it (`speakable`): numbers spelled out, hyphens
split, words Kokoro's lexicon lacks reworded, stress marks kept.
"""

using Telescope, KokoroRunner

const ROOT = normpath(joinpath(@__DIR__, ".."))
const VOICE, SPEED = "af_heart", 0.95
const LEAD, GAP, TAIL = 0.8, 0.45, 1.5

const SPOKEN_NUMBERS = Dict("2" => "two", "8" => "eight", "10" => "ten", "16" => "sixteen", "25" => "twenty-five")

"""Words Kokoro's lexicon lacks, said another way."""
const REWORDED = Dict("blurrier" => "more blurry")

"""A stretch of narration without stress marks, as it is read aloud."""
function speakable_plain(text)
    t = replace(text, '"' => "", '“' => "", '”' => "")
    t = replace(t, r"f/(\d+)" => s -> "F " * SPOKEN_NUMBERS[s[3:end]])
    t = replace(t, r"\b(\d+)\b" => s -> get(SPOKEN_NUMBERS, s, s))
    t = replace(t, r"(?<=\w)-(?=\w)" => " ")
    for (word, said) in REWORDED
        t = replace(t, word => said)
    end
    return t
end

"""A line as it is read aloud, its stress marks (`[word](+2)`) kept for Kokoro."""
function speakable(text)
    out = IOBuffer()
    cursor = firstindex(text)
    for m in eachmatch(KokoroRunner.STRESS_LINK, text)
        m.offset > cursor && print(out, speakable_plain(SubString(text, cursor, prevind(text, m.offset))))
        print(out, '[', speakable_plain(m.captures[1]), "](", m.captures[2], ')')
        cursor = m.offset + ncodeunits(m.match)
    end
    cursor <= lastindex(text) && print(out, speakable_plain(SubString(text, cursor)))
    return String(take!(out))
end

silence(seconds) = zeros(Float32, round(Int, seconds * KokoroRunner.SAMPLERATE))

"""Write mono samples (-1..1) as a 16-bit PCM WAV file."""
function write_wav(path, x::AbstractVector{<:Real}, sr::Integer)
    pcm = round.(Int16, clamp.(x, -1, 1) .* 32767)
    open(path, "w") do io
        n = 2 * length(pcm)
        write(io, b"RIFF", UInt32(36 + n), b"WAVE")
        write(io, b"fmt ", UInt32(16), UInt16(1), UInt16(1), UInt32(sr), UInt32(2sr), UInt16(2), UInt16(16))
        write(io, b"data", UInt32(n))
        write(io, pcm)
    end
    return path
end

"""Speak beat `name` into `gen/narration`; returns the line starts, ends and the take's length (seconds)."""
function speak_take(k::Kokoro, name::AbstractString; dir = joinpath(ROOT, "gen", "narration"))
    lines = Telescope.FILM.parts[name].lines
    rate = KokoroRunner.SAMPLERATE
    audio = silence(LEAD)
    starts, ends = Float64[], Float64[]
    for (i, line) in enumerate(lines)
        i > 1 && append!(audio, silence(GAP))
        push!(starts, length(audio) / rate)
        append!(audio, Vector{Float32}(speak(k, speakable(line); voice = VOICE, speed = SPEED)))
        push!(ends, length(audio) / rate)
    end
    append!(audio, silence(TAIL))
    duration = length(audio) / rate
    write_wav(joinpath(dir, name * ".wav"), audio, rate)
    write(joinpath(dir, name * ".timing"), join(["lines-$(VOICE)-$(SPEED)", join(starts, " "), join(ends, " "), string(duration)], "\n"))
    return (; starts, ends, duration)
end

if abspath(PROGRAM_FILE) == @__FILE__
    k = Kokoro()
    for name in ARGS
        t = speak_take(k, name)
        println(name, ": ", length(t.starts), " lines, ", round(t.duration; digits = 2), " s")
    end
end
