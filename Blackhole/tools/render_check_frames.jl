# Include in the Science4Makie root session after project.jl/stills.jl, with
# VideoEditor (as VE), RayMakie, GRMHDSnapshots and OIDNRunner loaded. Renders
# timeline frames of a project through VideoEditor's own bake path
# (`renderframe!` under `withfinalscenes`) into its native caches.

"""
    render_check_frames(project, frames; rerender = Int[], dir) -> Vector

Render the timeline `frames` of `project` into its native caches, saving the
project after each, and write every finished picture to `dir` as `<n>.png` with
the seconds it took. A frame in `rerender` is first written as the project has
it now (`<n>_before.png`), then its traced source is invalidated and rendered
again.
"""
function render_check_frames(project, frames; rerender = Int[],
                             dir = joinpath(dirname(project), "stack_check"))
    mkpath(dir)
    seq = VE.loadproject(project)
    engine = VE.FxEngine(Mantle.defaultbackend())
    readers = Dict{String, Any}()
    out = zeros(VE.RGB{VE.N0f8}, seq.canvas...)
    results = NamedTuple[]
    VE.withfinalscenes(seq) do
        for n in rerender
            VE.renderframe!(out, seq, n, readers, engine)
            save(joinpath(dir, "$(n)_before.png"), permutedims(out))
            for c in VE.frameclips(seq, n)
                c.track == 1 && VE.invalidateclip!(c; frames = [VE.sourceframe(c, n)])
            end
        end
        for n in unique([rerender; frames])
            seconds = @elapsed VE.renderframe!(out, seq, n, readers, engine)
            png = joinpath(dir, "$n.png")
            save(png, permutedims(out))
            VE.saveproject(project, seq; checkpoint = false)
            push!(results, (; frame = n, seconds, png))
            println("CHECK FRAME ", n, " ", round(seconds; digits = 1), " s")
            flush(stdout)
        end
    end
    return results
end
