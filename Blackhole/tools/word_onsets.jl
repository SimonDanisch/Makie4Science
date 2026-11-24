# Include in the Science4Makie root session with VideoEditor loaded as VE.
# When each word of a narration line is spoken, for cues that follow the voice.
# Kokoro's duration predictor is deterministic (only the vocoder adds noise), so
# the frames it gives each phoneme are those of the recorded take.

const KR = VE.KokoroRunner

"""
    word_onsets(k, line; voice = "af_heart", speed = 0.95) -> Vector{(word, seconds)}

The onset of every word of `line`, in seconds from the start of its trimmed take,
as `voice_en_v6` speaks it with the model `k` (`KR.Kokoro()`). Words are the
line's own, stress marks removed, matched one to one with the spoken phoneme
words.
"""
function word_onsets(k, line; voice = "af_heart", speed = 0.95)
    spoken = replace(line, r"(?<=\w)-(?=\w)" => " ")
    phonemes = KR.phonemize(k, spoken)
    ids = KR.tokenize(k, phonemes)
    _, _, duration = KR.DNNKernels.call(k.model, "kokorotext", KR.DNNKernels.toback(k.backend, reshape(ids, :, 1)),
                                         KR.refstyle(k, voice, length(phonemes)); dims = (t = length(ids),))
    frames = cumsum([max(1, round(Int, d / speed)) for d in vec(Array(duration))])
    raw = vec(Array(KR.speak(k; phonemes, voice, speed, trim = false)))
    per = length(raw) / last(frames)                 # samples per duration frame
    lead = findfirst(v -> abs(v) > 1e-3, raw) - 1     # what the take's trim cut
    onset(token) = ((token == 1 ? 0 : frames[token - 1]) * per - lead) / KR.SAMPLERATE
    # Token 1 is the start pad; characters outside the vocabulary are not tokens.
    starts = Float64[]
    token = 1; inword = false
    for c in phonemes
        haskey(k.vocab, c) || continue
        token += 1
        if c == ' '
            inword = false
        elseif !inword && !ispunct(c)
            push!(starts, onset(token)); inword = true
        end
    end
    words = split(replace(spoken, r"\[([^\]]*)\]\(\+\d\)" => s"\1"))
    length(words) == length(starts) ||
        error("$(length(words)) words but $(length(starts)) spoken words in: $phonemes")
    return [(String(w), t) for (w, t) in zip(words, starts)]
end
