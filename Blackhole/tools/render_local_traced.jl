# Include after project.jl. Uses the editor's native Save As, frame caches,
# finished-output mode and export path; never changes the raster review.
function render_local_traced(review, project, output; spp = 256)
    tracedbeats = ("a1_black_hole", "a2_two_numbers", "a3_tiny", "a4_giant_telescope", "b0_stations", "b4_one_note", "b5_earth_turns", "c2_space")
    VE.usebackend!(RayMakie)
    seq = VE.loadproject(isfile(project) ? project : review)
    traced = filter(c -> c.track == 1 && get(c.source.build["args"], "beat", "") in tracedbeats, seq.clips)
    length(traced) == length(tracedbeats) || error("missing traced picture clips")
    for c in traced
        opts = c.source.bakescreenopts
        if get(opts, :rasterize, true) || get(opts, :samples, 1) != spp
            rest = filter(p -> first(p) ∉ (:rasterize, :samples), opts)
            if get(c.source.build["args"], "beat", "") in ("a1_black_hole", "a2_two_numbers")
                rest[:max_depth] = 512
            end
            VE.setrenderconfig!(c; backend = c.source.backend, raytrace = true, samples = spp, rest...)
        end
    end
    mkpath(dirname(project))
    VE.saveproject(project, seq)
    frames = sum(c.src_out - c.src_in for c in traced)
    println("TRACED FRAMES: ", frames, "; HDR storage approximately ", round(frames * 55.3e6 / 2.0^30; digits = 1), " GiB")
    flush(stdout)

    # Measure actual finished-output frames, retaining them in the final cache.
    engine = VE.FxEngine(Mantle.defaultbackend())
    readers = Dict{String, Any}()
    out = zeros(VE.RGB{VE.N0f8}, seq.canvas...)
    estimate = 0.0
    try
        VE.withfinalscenes(seq) do
            for c in traced
                n = c.src_out - c.src_in
                samples = Float64[]
                for fraction in (0.5, 0.7)
                    frame = c.start + round(Int, fraction * (n - 1))
                    # A resumed project's already cached frame is not a trace benchmark.
                    VE.cachevalid(VE.trackcache(c), c.id, VE.sourceframe(c, frame)) && continue
                    t = time()
                    VE.renderframe!(out, seq, frame, readers, engine)
                    push!(samples, time() - t)
                end
                seconds = isempty(samples) ? 0.0 : last(samples)
                estimate += n * seconds
                println("BENCH ", c.source.build["args"]["beat"], ": ", n, " frames; ", round(seconds; digits = 2), " s/frame; first ", isempty(samples) ? "cached" : round(first(samples); digits = 1))
                VE.saveproject(project, seq; checkpoint = false)
                flush(stdout)
            end
        end
    finally
        VE.emptyengine!(engine)
        foreach(close, values(readers))
        VE.saveproject(project, seq; checkpoint = false)
    end
    println("ESTIMATED TRACING HOURS: ", round(estimate / 3600; digits = 2), " (plus composition/encoding; scene-dependent)")
    flush(stdout)
    started = time()
    progress = function (done, total)
        if done == total || (done - 1) % 60 == 0
            VE.saveproject(project, seq; checkpoint = false)
        end
        if done == total || (done - 1) % 300 == 0
            println("EXPORT ", done, "/", total, "; elapsed ", round((time() - started) / 60; digits = 1), " min")
            flush(stdout)
        end
    end
    try
        VE.exportvideo(output, seq; encoder_options = (crf = 18, preset = "medium"), progress)
    finally
        VE.saveproject(project, seq)
    end
    return output
end
