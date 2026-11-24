# Compare RADV (Vulkan/Lava) and ROCm machine code and timing for one OIDNRunner
# convolution layer. Include into a FRESH session: the executable-properties
# extension must be requested before the Vulkan device exists.
ENV["DISPLAY"] = get(ENV, "DISPLAY", ":0")
ENV["XAUTHORITY"] = joinpath("/run/user/1000", first(filter(startswith(".mutter-Xwaylandauth"), readdir("/run/user/1000"))))
using Mantle, Lava
Mantle.enable_pipeline_executable_properties!()
using OIDNRunner
import KernelAbstractions as KA
import AMDGPU
const O = OIDNRunner
const vb = Mantle.defaultbackend()
const rb = AMDGPU.ROCBackend()
const ctx = Mantle.vk_context()
const isadir = joinpath(@__DIR__, "..", "renders", "oidn_isa")

function runlayer(be, tiling, W, H, C0, C1, up, CO; n = 10)
    dev(a) = (d = KA.allocate(be, eltype(a), length(a)); copyto!(d, vec(a)); d)
    X0 = dev(Float16.(randn(Float32, C0 * (up ? (W ÷ 2) * (H ÷ 2) : W * H)) .* 0.5f0))
    X1 = C1 == 0 ? nothing : dev(Float16.(randn(Float32, C1 * W * H) .* 0.5f0))
    w = randn(Float32, 3, 3, C0 + C1, CO) .* 0.02f0
    Wt, bias, K = O.packconv(w, zeros(Float32, CO), C0, C0, C1, C1, CO)
    L = O.ConvLayer(C0, C1, up, CO, K, dev(Wt), dev(bias))
    t = O.TileBuffers(be, W, H)
    Y = KA.allocate(be, Float16, CO * O.capacity(W, H, 0))
    O.conv!(be, t, L, Y, X0, X1, 0; tiling); KA.synchronize(be)
    el = @elapsed (for _ in 1:n; O.conv!(be, t, L, Y, X0, X1, 0; tiling); end; KA.synchronize(be))
    O.free!(t)
    return 1000el / n
end

function opcounts(asm)
    ops = Dict{String, Int}()
    for m in eachmatch(r"^\s*((global|ds|buffer|scratch)_\w+|s_waitcnt\w*|s_cbranch\w+|v_add_co_u32\w*|v_cndmask_b32\w*|v_wmma\w+)"m, asm)
        ops[m.captures[1]] = get(ops, m.captures[1], 0) + 1
    end
    return sort(collect(ops); by = last, rev = true)
end

"Time one layer on Vulkan and return RADV's register count, code size and op mix."
function vkisa(tag, tiling, shape)
    ms = runlayer(vb, tiling, shape...)
    name = "conv3x3_" * string(tiling[1]) * "x" * string(tiling[2]) * "_"
    plans = [p for (k, v) in ctx.caches.launchplans for p in v if occursin(name, string(k))]
    pl = plans[argmax([p.world for p in plans])]
    st = Dict(s.name => s.value for s in Mantle.pipeline_exec_stats(ctx, pl.pipeline).raw_stats)
    asm = only(filter(r -> r.name == "Assembly", Mantle.pipeline_exec_ir(ctx, pl.pipeline))).text
    write(joinpath(isadir, "vk_$(tag).txt"), asm)
    return (ms = round(ms; digits = 2), vgprs = st["VGPRs"], code = st["Code size"], ops = opcounts(asm))
end

"Same for ROCm through AMDGPU's GCN dump."
function rocmisa(tag, tiling, shape)
    io = IOBuffer()
    AMDGPU.@device_code_gcn io = io runlayer(rb, tiling, shape...; n = 1)
    asm = String(take!(io))
    write(joinpath(isadir, "rocm_$(tag).asm"), asm)
    ms = runlayer(rb, tiling, shape...)
    vg = match(r"NumVgprs: (\d+)", asm)
    return (ms = round(ms; digits = 2), vgprs = vg === nothing ? -1 : parse(Int, vg[1]), ops = opcounts(asm))
end
