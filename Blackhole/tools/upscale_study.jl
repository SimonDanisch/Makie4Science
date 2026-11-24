# Include in the Science4Makie root session after project.jl, with VideoEditor
# (as VE), RayMakie, GRMHDSnapshots, OIDNRunner and Mantle loaded.
# Which resolution and sample count, denoised and brought to 4k, comes closest
# to a 4k reference in a fixed render time per frame.

"""
    study_renders!(project, frame, configs; dir) -> Vector

Build the a1 black hole picture at timeline `frame` once, as VideoEditor stands
its scene up (one preview sample), then trace that scene at each
`(px_per_unit, samples)` in `configs`: the film's 1280×720 layout at that pixel
density, with its albedo, normal and depth guides. Each is denoised and
displayed through the clip's own HDR effects (`hdrpicture!`), and its master and
display image are kept in `dir` as `<w>x<h>_<samples>.vehdr` / `.png`. `bake` adds
screen options to the clip's bake options (`max_component_value`, for one).
Returns `(; width, height, samples, render, denoise, master, png)` each, the
render and denoise times in seconds; a new density first traces one sample and
denoises once, so the timed passes are not the ones that size the films and
plans. Give the largest density first: each smaller one fits where it was.
"""
function study_renders!(project, frame, configs; dir, bake = Dict{Symbol, Any}())
    mkpath(dir)
    seq = VE.loadproject(project)
    clip = only(filter(c -> c.track == 1 && c.source isa VE.SceneSource &&
                            get(c.source.build["args"], "beat", "") == "a1_black_hole", seq.clips))
    sf = VE.sourceframe(clip, frame)
    src = clip.source
    merge!(src.bakescreenopts, bake)
    src.mode = :bake
    VE.updatesource!(src, clip, sf)
    VE.sceneframe!(src, clip, seq.canvas)          # stands the scene up: one preview sample
    screen = src.live.screen
    backend = VE.getbackend(VE.renderwith(src))
    results = NamedTuple[]
    VE.onthread(VE.renderthread(backend)) do; lock(VE.SCENELOCK) do
        for (density, samples) in configs
            trace(n) = Base.invokelatest(RayMakie.renderbuffers, screen; clear = true, samples = n, px_per_unit = density)
            trace(1)
            render = @elapsed (raw = trace(samples); VE.KA.synchronize(VE.KA.get_backend(raw.color)))
            work = VE.hdrwork!(src, VE.KA.get_backend(raw.color), size(raw.color))
            # The first pass at a size builds the denoiser's plans for it.
            img = VE.hdrpicture!(work, raw, clip, sf)
            denoise = @elapsed (img = VE.hdrpicture!(work, raw, clip, sf); VE.KA.synchronize(VE.KA.get_backend(img)))
            w, h = size(raw.color)
            base = joinpath(dir, "$(w)x$(h)_$(samples)")
            VE.writerenderframe(base * ".vehdr", raw)
            save(base * ".png", permutedims(VE.RGB{VE.N0f8}.(Array(img))))
            push!(results, (; width = w, height = h, samples, render, denoise, master = base * ".vehdr", png = base * ".png"))
            println("STUDY ", w, "x", h, " ", samples, " spp: render ", round(render; digits = 1),
                    " s, denoise+display ", round(denoise; digits = 2), " s")
            flush(stdout)
        end
    end; end
    return results
end

using GPUFiltering: warp!, fitmatrix, gaussianblur!
using VideoEditor: RGB, N0f8

"""
    study_picture(master, clip, sf) -> device matrix of RGB{Float32}

The display picture of a kept master: the clip's HDR effects (its OIDN with the
master's guides, unless `denoise = false`) and display transform, as the bake
applies them, on the device.
"""
function study_picture(master, clip, sf; backend = Mantle.defaultbackend(), denoise = true)
    raw = VE.readrenderframe(master)
    work = VE.HDRWork(backend, size(raw.color)...)
    oidn = [fx for fx in clip.effects if VE.renderable(fx) && VE.op(fx, sf) isa VE.OIDNDenoiseEffect]
    foreach(fx -> fx.enabled[] = denoise, oidn)
    img = VE.hdrpicture!(work, VE.uploadmaster!(work, raw), clip, sf)
    foreach(fx -> fx.enabled[] = true, oidn)
    picture = map(p -> RGB{Float32}(p.r, p.g, p.b), img)
    VE.freework!(work)
    return picture
end

"`picture` resampled to `dims` with GPUFiltering's bicubic (Catmull-Rom) warp."
function bicubic_upscale(picture, dims)
    out = similar(picture, dims)
    warp!(out, picture, fitmatrix((0, 0, 1, 1), size(picture), dims))
    return out
end

luma(c) = 0.2126f0 * c.r + 0.7152f0 * c.g + 0.0722f0 * c.b

"PSNR in dB of the luminance of `a` against `b`, display values in [0, 1]."
psnr(a, b) = 10 * log10(length(a) / sum(abs2, luma.(a) .- luma.(b)))

"Mean SSIM of the luminance of `a` against `b`, Gaussian windows of σ = 1.5 px."
function ssim(a, b; σ = 1.5f0)
    x, y = luma.(a), luma.(b)
    moments = RGB{Float32}.(x, y, x .* x)
    products = RGB{Float32}.(y .* y, x .* y, 0f0)
    m1, m2 = similar(moments), similar(products)
    gaussianblur!(m1, moments, σ)
    gaussianblur!(m2, products, σ)
    c1, c2 = 0.01f0^2, 0.03f0^2
    s = map(m1, m2) do p, q
        μx, μy = p.r, p.g
        vx, vy, cxy = p.b - μx^2, q.r - μy^2, q.g - μx * μy
        ((2μx * μy + c1) * (2cxy + c2)) / ((μx^2 + μy^2 + c1) * (vx + vy + c2))
    end
    return sum(s) / length(s)
end

"""
    study_compare(reference, candidates, clip, sf; dir, upscale = bicubic_upscale) -> Vector

Every candidate master's picture brought to the reference's size by `upscale`
and measured against the reference's picture: luminance PSNR and SSIM. The
upscaled pictures go to `dir`.
"""
function study_compare(reference, candidates, clip, sf; dir, upscale = bicubic_upscale, tag = "bicubic", denoise = true)
    mkpath(dir)
    ref = study_picture(reference, clip, sf)
    save(joinpath(dir, "reference.png"), permutedims(RGB{N0f8}.(Array(ref))))
    map(candidates) do master
        picture = study_picture(master, clip, sf; denoise)
        up = size(picture) == size(ref) ? picture : upscale(picture, size(ref))
        name = first(splitext(basename(master)))
        save(joinpath(dir, "$(name)_$(tag).png"), permutedims(RGB{N0f8}.(Array(up))))
        (; name, psnr = psnr(up, ref), ssim = ssim(up, ref))
    end
end
