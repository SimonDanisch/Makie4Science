using VideoEditor, OIDNRunner, Mantle
import VideoEditor as VE

function benchmark_oidn_native(dir; repeats = 6, backend = Mantle.defaultbackend(), tag = "native_optimized")
    source = joinpath(dir, "alma.frames", "track-1", "source")
    files = [joinpath(root, file) for (root, _, names) in walkdir(source) for file in names if endswith(file, ".vehdr")]
    frame = VE.readrenderframe(only(files))
    d = OIDNDenoiser(; backend)
    runs = Float64[]
    try
        result = nothing
        for i in 1:repeats
            t = @elapsed result = denoise(d, frame.color; albedo = frame.albedo, normal = frame.normal)
            push!(runs, t)
            @assert all(isfinite, result)
            println("Native run ", i, ": ", round(t; digits = 4), "s")
            flush(stdout)
        end
        open(joinpath(dir, tag * ".f32"), "w") do io
            write(io, permutedims(result, (3, 1, 2)))
        end
        warm = sort(runs[2:end]); n = length(warm)
        median = (warm[(n + 1) ÷ 2] + warm[(n + 2) ÷ 2]) / 2
        report = Dict(
            "resolution" => collect(size(frame.color)), "precision" => string(d.precision),
            "backend" => string(typeof(backend)), "tilesize" => d.tilesize, "fuseconv" => d.fuseconv, "prefilter" => true, "runs_s" => runs,
            "median_warm_s" => median,
        )
        open(joinpath(dir, tag * ".json"), "w") do io
            write(io, VE.JSON.json(report))
        end
        return report
    finally
        OIDNRunner.release!(d)
    end
end
