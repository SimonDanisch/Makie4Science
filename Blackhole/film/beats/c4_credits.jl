# A quiet, legible end card, built and composited by the same Makie pipeline.
# Nothing in it changes, so it has no arguments for the editor to key.
function build_credits(canvas; scientific_note=true)
    fig, ov = frame2d(canvas; padding = (0, 0, 0, 0))
    ax = picture_axis(fig[1, 1])
    limits!(ax, 0, 1280, 0, 720)
    logo = rotr90(load(joinpath(@__DIR__, "..", "..", "assets", "makie_logo.png")))
    image!(ax, 370..550, 430..610, logo)
    scale = Float32(canvas[2] / 720)
    point(x,y) = Point2f(x * canvas[1] / 1280, y * canvas[2] / 720)
    function credit(text, x, y, size; color = :white, align = (:center, :center))
        filmtext!(ov, point(x,y); text, fontsize=size*scale, color, align)
    end
    credit("Makie", 575, 520, 76; align=(:left,:center))
    credit("Everything rendered with Makie", 640, 387, 32)
    credit("makie.org", 640, 350, 20; color=:gray70)
    credit("RENDERING & EDITING", 640, 318, 17; color=:gray70)
    credit("RayMakie · Hikari · Mantle · VideoEditor", 640, 282, 25)
    credit("Julia · KernelAbstractions · Lava / Vulkan · Metal", 640, 245, 22)
    credit("Open Image Denoise · FFmpeg · Kokoro", 640, 208, 22)
    credit("SCIENCE & DATA", 640, 153, 17; color=:gray70)
    credit("After Paul Tiede: Imaging Black Holes with Julia", 640, 119, 21)
    credit("GRMHDSnapshots · Illinois v3 / Dhruv et al. (2025), CC BY 4.0", 640, 85, 18)
    credit("NASA Earth & star maps · ALMA: NRAO/AUI/NSF, CC BY 4.0", 640, 53, 18)
    scientific_note && credit("Plasma: fast-light Schwarzschild transfer; radio intensity shown in false colour.",
                              640, 21, 14; color=:gray70)
    return fig, (;)
end

"The end card holds still: no keys."
perform(::typeof(build_credits), T::Timing) =
    (; picture = Pair{String, Vector{Tuple{Float32, Float32, Symbol}}}[],
       labels = Pair{String, Vector{Tuple{Float32, Float32, Symbol}}}[])

PERFORMED["c4_credits"] = build_credits
