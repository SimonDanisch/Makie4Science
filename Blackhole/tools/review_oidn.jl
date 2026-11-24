# Review OIDN on consecutive film frames using independent low-resolution caches.
using VideoEditor, RayMakie, Mantle, OIDNRunner
import VideoEditor as VE
function reviewoidn(project; dir = joinpath(dirname(project), "renders", "oidn_review"), canvas = (480, 270), samples = 8)
    VE.usebackend!(RayMakie);mkpath(dir)
    original = VE.loadproject(project)
    engine = VE.FxEngine(Mantle.defaultbackend());readers = Dict{String, Any}()
    out = zeros(VE.RGB{VE.N0f8}, canvas...)
    try
        for (beat, firstframe) in (("b0_stations", 60), ("a4_giant_telescope", 90))
            clip = VE.copyclip(only(filter(c -> c.track == 1 && get(c.source.build["args"], "beat", "") == beat, original.clips)))
            clip.start = 0;clip.source.width = canvas[1];clip.source.height = canvas[2]
            seq = VE.Sequence([clip], original.framerate);seq.canvas = canvas
            VE.enabletrackcache!(seq, joinpath(dir, beat * ".frames"))
            VE.setrenderconfig!(clip; raytrace = true, samples, device = "Mantle.defaultbackend()", fxaa = false)
            # Preserve grade/display transforms; insert OIDN ahead of them.
            old = copy(clip.effects)
            VE.removeeffects!(clip, VE.HDRDenoiseEffect)
            VE.removeeffects!(clip, VE.OIDNDenoiseEffect)
            effect = VE.Effect(VE.OIDNDenoiseEffect());VE.addslot!(clip, effect)
            current = copy(clip.effects)
            ordered = vcat(
                filter(f -> f.kind === :scene, current), [effect],
                filter(f -> f.kind !== :scene && f !== effect, current)
            )
            empty!(clip.effects);append!(clip.effects, ordered);VE.dirtygraph!(clip)
            for frame in firstframe:(firstframe + 2)
                effect.enabled[] = false
                VE.renderframe!(out, seq, frame, readers, engine)
                VE.PNGFiles.save(joinpath(dir, "$(beat)_$(frame)_raw.png"), permutedims(out))
                count = VE.sourcecache(clip).renders
                file = VE.cachefile(VE.sourcecache(clip), clip.id, frame);before = read(file)
                effect.enabled[] = true
                seconds = @elapsed VE.renderframe!(out, seq, frame, readers, engine)
                @assert VE.sourcecache(clip).renders == count
                @assert read(file) == before
                VE.PNGFiles.save(joinpath(dir, "$(beat)_$(frame)_oidn.png"), permutedims(out))
                println(beat, " frame ", frame, ": OIDN ", round(seconds; digits = 3), "s; no source rerender");flush(stdout)
            end
            close(clip.source)
        end
    finally
        VE.emptyengine!(engine);foreach(close, values(readers))
    end
    return dir
end
