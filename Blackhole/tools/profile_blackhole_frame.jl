# Include in a Science4Makie root session after `using VideoEditor, RayMakie,
# GRMHDSnapshots, OIDNRunner`, `const VE = VideoEditor` and
# `VE.usebackend!(RayMakie)`. Diagnostic only: traces samples of one uncached a1
# frame on the standing bake screen the editor builds for it, and writes no cache.

"""
    profile_blackhole_frame(project, n; samples = 4) -> NamedTuple

Where the time of timeline frame `n` of the a1 beat goes, at the project's bake
settings: the first sample (scene build, compile, one sample), the
bounce rounds a sample takes in batches with the rays still live after each,
Mantle's per-pass GPU times for the round graph, and the integrator, for
`profile_rounds`.
"""
function profile_blackhole_frame(project, n; samples = 4)
    seq = VE.loadproject(project)
    clip = only(filter(c -> c.track == 1 && c.source isa VE.SceneSource &&
                            get(c.source.build["args"], "beat", "") == "a1_black_hole", seq.clips))
    sf = VE.sourceframe(clip, n)
    VE.cachedsourceframe(clip, sf) === nothing || error("timeline frame $n is cached; profile an uncached one")
    src = clip.source
    src.mode = :bake
    VE.updatesource!(src, clip, sf)
    first_sample = @elapsed VE.sceneframe!(src, clip, seq.canvas)
    screen = src.live.screen
    vp = only(ss.integrator for ss in screen.scene_states if ss.film !== nothing)
    plans = vp.state.plans
    dev = plans.finalize.graph.dev
    # One sample by hand, as `run_sample_plan!` runs it, timing each batch of
    # rounds and reading the live ray count after it.
    p = plans.sample
    function batches(rounds)
        Mantle.run!(p.setup)
        Mantle.waitidle(dev)
        out = NamedTuple{(:seconds, :live), Tuple{Float64, Int32}}[]
        for _ in 1:p.batches
            t = @elapsed (Mantle.run!(rounds); Mantle.waitidle(dev))
            copyto!(p.hostcounter, p.counter)
            push!(out, (; seconds = t, live = p.hostcounter[1]))
            p.hostcounter[1] == 0 && break
        end
        Mantle.run!(p.accumulate)
        Mantle.waitidle(dev)
        return out
    end
    timeline = batches(p.rounds)
    profiled = Mantle.record!(Mantle.Plan(p.rounds.graph; profile = true))
    for _ in 1:samples
        batches(profiled)
    end
    passes = sort(Mantle.timings(profiled); by = t -> isnan(t.gpu_ms) ? 0.0 : -t.gpu_ms)
    Mantle.free!(profiled)
    return (; frame = n, sourceframe = sf, first_sample, max_batches = p.batches,
            timeline, passes, integrator = vp)
end

"""
    profile_rounds(vp; rounds = 64) -> (; ms, live)

GPU milliseconds per pass, summed over the first `rounds` bounce rounds of one
sample of the frame `vp` last rendered, and the rays still live after each pair
of rounds. The rounds are Hikari's own two-round graph, planned once more with
Mantle's profiler on, between the sample's own setup and accumulate plans.
"""
function profile_rounds(vp; rounds = 64)
    st, ad, pr = vp.state, vp.adapted, vp.perrun
    p = st.plans.sample
    dev = st.plans.finalize.graph.dev
    refs = Hikari.render_refs(ad.accel, ad.media_interfaces, ad.media, ad.materials, ad.lights,
                              pr.camera, pr.initial_medium, pr.filter_params, vp.filter_sampler_gpu,
                              pr.sample_idx, vp.regularize, Int32(vp.samples_per_pixel),
                              vp.max_component_value)
    g = Mantle.Graph(dev)
    Hikari.rounds_passes!(g, st, refs, 2; chit_owns_surface = false, has_media = true,
                          has_lights = length(ad.lights) > 0)
    two = Mantle.record!(Mantle.Plan(g; profile = true))
    prof = two.profiler
    totals = Dict{String, Float64}()
    live = Int32[]
    Mantle.run!(p.setup)
    Mantle.waitidle(dev)
    for _ in 1:(rounds ÷ 2)
        before = length.(prof.gpu_ns)
        Mantle.run!(two)
        Mantle.waitidle(dev)
        Mantle.collect!(prof, dev)
        for (i, name) in enumerate(prof.names)
            length(prof.gpu_ns[i]) > before[i] &&
                (totals[name] = get(totals, name, 0.0) + last(prof.gpu_ns[i]) / 1e6)
        end
        copyto!(p.hostcounter, p.counter)
        push!(live, p.hostcounter[1])
    end
    Mantle.run!(p.accumulate)
    Mantle.waitidle(dev)
    Mantle.free!(two)
    return (; ms = sort!(collect(totals); by = last, rev = true), live)
end

