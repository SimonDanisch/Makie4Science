"""
Does every approved take say its part's current lines?

    julia --project=<env with Telescope and VideoEditor> Telescope/tools/check_takes.jl

Whisper transcribes each narrated part's take; its words are compared with the
part's lines (stress marks, punctuation and case removed). Whisper writes
numbers as digits and some words in US spelling, so a few differences are
normal; more than a tenth of the words means the take says other lines and must
be spoken again.
"""

using Telescope, VideoEditor
import Mantle
import VideoEditor as VE

"The words as said: stress marks, punctuation and case removed."
words(s) = filter(!isempty, split(lowercase(replace(replace(s, r"\[([^\[\]]+)\]\([^)]*\)" => s"\1"), r"[^A-Za-z' ]" => " "))))

"Word-level edit distance."
function editdistance(a, b)
    d = collect(0:length(b))
    for i in eachindex(a)
        prev = d[1]; d[1] = i
        for j in eachindex(b)
            tmp = d[j+1]
            d[j+1] = min(d[j+1] + 1, d[j] + 1, prev + (a[i] == b[j] ? 0 : 1))
            prev = tmp
        end
    end
    return d[end]
end

function main(film = Telescope.FILM; tolerance = 0.1)
    model = VE.WhisperRunner.whisper(; backend = Mantle.defaultbackend())
    for name in film.cut
        audio = collect(reinterpret(Float32, read(
            `$(VE.FFMPEG_jll.ffmpeg()) -v error -i $(film.voice(name)) -f f32le -ar 16000 -ac 1 pipe:1`)))
        heard = first(VE.WhisperRunner.transcribe(model, audio))
        expected = words(join(film.parts[name].lines, " "))
        d = editdistance(expected, words(heard))
        println(rpad(name, 18), d, " of ", length(expected), " words differ")
        d <= tolerance * length(expected) || error("the take of $name does not say its lines: $heard")
    end
end

main()
