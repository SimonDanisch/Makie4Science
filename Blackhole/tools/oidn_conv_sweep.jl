# Tile/wave configuration sweep for OIDNRunner's 3x3 convolution. Generates
# one kernel per configuration (literal unroll counts) into `Main`; measured
# against the layer shapes of the large U-Net at 1080p.
using OIDNRunner, Mantle
import KernelAbstractions as KA
const O = OIDNRunner
const KI = Mantle.KI
using Mantle.KI: AcceleratedMatrix, MatrixA, MatrixB, Accumulator

# (BO, BP, WO, WP, BK, EPI): workgroup tile BO x BP, WO x WP waves, reduction
# step BK, EPI = :direct (matrix store) or :lds (shuffle through shared memory
# into 16-byte stores) or :none (ablation: never stores).
const SWEEP = Dict{Any, Any}()
function genconv(cfg)
    haskey(SWEEP, cfg) && return SWEEP[cfg]
    BO, BP, WO, WP, BK, EPI = cfg
    NT = 32 * WO * WP
    TO = BO ÷ WO ÷ 16; TP = BP ÷ WP ÷ 16
    KG = BK ÷ 8                         # 8-half groups per k-row
    AV = cld(BO * KG, NT); BV = cld(BP * KG, NT)  # vec8 groups staged per thread
    RS = NT ÷ KG                                   # rows between a thread's groups
    AG = AV * NT != BO * KG; BG = BV * NT != BP * KG   # the last group needs a guard
    LD = BK + 8
    fname = Symbol("conv_", join(string.(cfg), "_"), "!")
    ex = quote
        function $fname(Y, X0, X1, Wt, bias, ::Val{V}, ::Val{W}, ::Val{H}, ::Val{C0}, ::Val{C1},
                        ::Val{UP}, ::Val{CO}, ::Val{K}, ::Val{RELU}) where {V, W, H, C0, C1, UP, CO, K, RELU}
            T = eltype(X0)
            NV = 8 ÷ V
            LDV = $LD ÷ V
            sA = KI.localmemory(T, Val((LDV * $BO,)), Val(1))
            sB = KI.localmemory(T, Val((LDV * $BP,)), Val(2))
            tid = Int32(KI.get_local_id().x - 1)
            blk = Int32(KI.get_group_id().x - 1)
            nO = Int32(CO ÷ $BO)
            o0 = (blk % nO) * Int32($BO)
            p0 = (blk ÷ nO) * Int32($BP)
            s = tid ÷ Int32(32)
            wo = (s % Int32($WO)) * Int32($(BO ÷ WO))
            wp = (s ÷ Int32($WO)) * Int32($(BP ÷ WP))
            kq = tid % Int32($KG)
            pp = tid ÷ Int32($KG)
            M = Int32(W * H)
            Base.Cartesian.@nexprs $BV r -> begin
                P_r = p0 + min(pp + Int32($RS * (r - 1)), Int32($BP - 1))
                y_r = P_r ÷ Int32(W); x_r = P_r - y_r * Int32(W)
                y_r = ifelse(P_r < M, y_r, Int32(-2))
            end
            # weight rows staged by this thread: o = pp + (NT/KG)*(r-1)
            wa = Int32(1) + (kq * Int32(8) + (o0 + pp) * Int32(K)) ÷ Int32(V)
            Base.Cartesian.@nexprs $AV r -> (wr_r = min(pp + Int32($RS * (r - 1)), Int32($BO - 1)) - pp)
            bp = pointer(bias)
            Base.Cartesian.@nexprs $TO i -> Base.Cartesian.@nexprs $TP j ->
                c_i_j = Mantle.accinit(bias, bp, Int32(1) + o0 + wo + Int32(16 * (i - 1)))
            Base.Cartesian.@nexprs $BV r -> begin
                (g_r, ok_r, f_r) = O.gatheraddr(x_r, y_r, kq * Int32(8), Val(V), Val(W), Val(H), Val(C0), Val(C1), Val(UP))
                Base.Cartesian.@nexprs 2 q -> (q <= NV && (b_r_q = O.gather(X0, X1, g_r, f_r, Val(C1), Val(q - 1))))
            end
            Base.Cartesian.@nexprs $AV r -> Base.Cartesian.@nexprs 2 q ->
                (q <= NV && (a_r_q = @inbounds Wt[wa + wr_r * Int32(K ÷ V) + Int32(q - 1)]))
            nk = Int32(K ÷ $BK)
            for kb in Int32(0):(nk - Int32(1))
                Base.Cartesian.@nexprs $AV r -> Base.Cartesian.@nexprs 2 q ->
                    (q <= NV && (!$AG || r < $AV || pp + Int32($RS * (r - 1)) < Int32($BO)) &&
                     (@inbounds sA[Int32(1) + kq * Int32(NV) + (pp + Int32($RS * (r - 1))) * Int32(LDV) + Int32(q - 1)] = a_r_q))
                Base.Cartesian.@nexprs $BV r -> Base.Cartesian.@nexprs 2 q ->
                    (q <= NV && (!$BG || r < $BV || pp + Int32($RS * (r - 1)) < Int32($BP)) &&
                     (@inbounds sB[Int32(1) + kq * Int32(NV) + (pp + Int32($RS * (r - 1))) * Int32(LDV) + Int32(q - 1)] = O.padded(b_r_q, ok_r)))
                KI.barrier()
                if kb + Int32(1) < nk
                    k = (kb + Int32(1)) * Int32($BK) + kq * Int32(8)
                    Base.Cartesian.@nexprs $BV r -> begin
                        (g_r, ok_r, f_r) = O.gatheraddr(x_r, y_r, k, Val(V), Val(W), Val(H), Val(C0), Val(C1), Val(UP))
                        Base.Cartesian.@nexprs 2 q -> (q <= NV && (b_r_q = O.gather(X0, X1, g_r, f_r, Val(C1), Val(q - 1))))
                    end
                    wk = wa + (kb + Int32(1)) * Int32($BK ÷ V)
                    Base.Cartesian.@nexprs $AV r -> Base.Cartesian.@nexprs 2 q ->
                        (q <= NV && (a_r_q = @inbounds Wt[wk + wr_r * Int32(K ÷ V) + Int32(q - 1)]))
                end
                Base.Cartesian.@nexprs $(BK ÷ 16) u -> begin
                    Base.Cartesian.@nexprs $TO i -> (a_i = AcceleratedMatrix{Float16, 16, 16, MatrixA}(
                        sA, Int32(1) + Int32(16 * (u - 1) ÷ V) + (wo + Int32(16 * (i - 1))) * Int32(LDV), Int32(LDV), Val(true)))
                    Base.Cartesian.@nexprs $TP j -> begin
                        b = AcceleratedMatrix{Float16, 16, 16, MatrixB}(
                            sB, Int32(1) + Int32(16 * (u - 1) ÷ V) + (wp + Int32(16 * (j - 1))) * Int32(LDV), Int32(LDV))
                        Base.Cartesian.@nexprs $TO i -> (c_i_j = muladd(a_i, b, c_i_j))
                    end
                end
                KI.barrier()
            end
            $(EPI === :lds ? quote
                # Shuffle through shared memory: fp16 tile [o, p] with o fastest,
                # then 16-byte rows along o into HWC.
                sC = KI.localmemory(Float16, Val(($(BO + 8) * $BP,)), Val(3))
                Base.Cartesian.@nexprs $TO i -> Base.Cartesian.@nexprs $TP j -> begin
                    v = RELU ? O.relu16(c_i_j) : c_i_j
                    h = convert(AcceleratedMatrix{Float16, 16, 16, Accumulator}, v)
                    copyto!(sC, Int32(1) + wo + Int32(16 * (i - 1)) + (wp + Int32(16 * (j - 1))) * Int32($(BO + 8)), Int32($(BO + 8)), h)
                end
                KI.barrier()
                Yv = Y
                Base.Cartesian.@nexprs $(BO * BP ÷ 8 ÷ NT) r -> begin
                    e = tid + Int32($NT * (r - 1))
                    oq = e % Int32($(BO ÷ 8)); p = e ÷ Int32($(BO ÷ 8))
                    src = Int32(1) + oq * Int32(8) + p * Int32($(BO + 8))
                    dst = Int32(1) + o0 + oq * Int32(8) + (p0 + p) * Int32(CO)
                    Base.Cartesian.@nexprs 8 z -> (@inbounds Yv[dst + Int32(z - 1)] = sC[src + Int32(z - 1)])
                end
            end : EPI === :none ? quote
                if o0 < Int32(0)
                    Base.Cartesian.@nexprs $TO i -> Base.Cartesian.@nexprs $TP j -> begin
                        h = convert(AcceleratedMatrix{Float16, 16, 16, Accumulator}, c_i_j)
                        copyto!(pointer(Y), Int32(1) + o0 + wo + Int32(16 * (i - 1)) + (p0 + wp + Int32(16 * (j - 1))) * Int32(CO), Int32(CO), h)
                    end
                end
            end : quote
                Base.Cartesian.@nexprs $TO i -> Base.Cartesian.@nexprs $TP j -> begin
                    v = RELU ? O.relu16(c_i_j) : c_i_j
                    h = convert(AcceleratedMatrix{Float16, 16, 16, Accumulator}, v)
                    copyto!(pointer(Y), Int32(1) + o0 + wo + Int32(16 * (i - 1)) + (p0 + wp + Int32(16 * (j - 1))) * Int32(CO), Int32(CO), h)
                end
            end)
            return nothing
        end
    end
    f = Core.eval(Main, ex)
    return SWEEP[cfg] = f
end

function sweepconv(be, cfg, W, H, C0, C1, up, CO; n = 20)
    BO, BP, WO, WP = cfg
    S = O.stagevec(be); V = O.halves(S)
    f = genconv(cfg)
    X0 = KA.allocate(be, Float16, C0 * (up ? (W ÷ 2) * (H ÷ 2) : W * H)); copyto!(X0, Float16.(randn(Float32, length(X0)) .* 0.5f0))
    X1 = C1 == 0 ? X0 : (a = KA.allocate(be, Float16, C1 * W * H); copyto!(a, Float16.(randn(Float32, length(a)) .* 0.5f0)); a)
    K = cld(9 * (C0 + C1), cfg[5]) * cfg[5]
    Wt = KA.allocate(be, Float16, K * CO); copyto!(Wt, Float16.(randn(Float32, K * CO) .* 0.02f0))
    b = KA.allocate(be, Float32, CO); fill!(b, 0f0)
    M = W * H; Mp = cld(M, 256) * 256
    Y = KA.allocate(be, Float16, CO * Mp)
    nblk = (CO ÷ BO) * cld(Mp, BP)
    args = (Y, reinterpret(S, X0), reinterpret(S, X1), reinterpret(S, Wt), b, Val(V), Val(W), Val(H), Val(C0), Val(C1), Val(up), Val(CO), Val(K), Val(true))
    launch() = Base.invokelatest(Mantle.kilaunch!, be, f, args...; ndrange = nblk * 32 * WO * WP, workgroupsize = 32 * WO * WP)
    launch(); launch(); KA.synchronize(be)
    t = @elapsed (for _ in 1:n; launch(); end; KA.synchronize(be))
    ms = 1000t / n
    foreach(KA.unsafe_free!, C1 == 0 ? (X0, Wt, b, Y) : (X0, X1, Wt, b, Y))
    return (ms = round(ms; digits = 2), tflops = round(2 * M * 9 * (C0 + C1) * CO / ms / 1e9; digits = 1))
end
