using Test, ScienceFilms, Makie

@testset "keys combine as the fades they are" begin
    tm = Timing(Float32[1, 5], Float32[3, 8], 10f0)
    # a label faded in on line 1 and out on line 2
    shown = appear(tm, 1) * (1f0 - appear(tm, 2))
    @test [valueof(shown, t) for t in (0.5, 1.3, 4, 5.3, 6)] ≈ [0, 0.5, 1, 0.5, 0]
    # where only one of two lists changes, its easing is kept exactly
    eased = ramp(0, 2; ease = :smooth) * constant(2f0)
    @test valueof(eased, 0.5) ≈ 2 * valueof(ramp(0, 2; ease = :smooth), 0.5)
    # a sum shown until a step, then faded in again: `+` of keys, not of arrays
    sums = switch(4, 1f0, 0f0) + appear(tm, 2)
    @test [valueof(sums, t) for t in (3, 4.5, 6)] ≈ [1, 0, 1]
end

@testset "a retimed shot plays faster" begin
    anim = retime(animation(Dict("x.alpha" => ramp(2, 4))), 2)
    @test [k.t for k in anim["x.alpha"]] == [1, 2]
end

@testset "a montage fits its shots to its narration" begin
    m = Montage("m", ["words"], [("a", 0, 10), ("b", 0, 10)]; tail = 1)
    @test fit(m, 19) == (1f0, 20f0)
    @test first(fit(m, 9)) == 1.5f0          # sped up by at most `maxspeed`
    @test first(fit(m, 39)) == 0.5f0         # slowed down to fill the narration
end

# A recipe's `visible` did not reach the plots it draws: a hidden caption stayed
# on screen, and the editor's "visible" checkbox did nothing for a label.
@testset "hidden labels hide what they draw" begin
    fig = Figure(; size = (200, 100))
    ov = Scene(fig.scene; camera = campixel!)
    shown(p) = any(c -> c.visible[] && (isempty(c.plots) || shown(c)), p.plots)
    for p in (caption!(ov, Point2f(100, 20); text = "words"),
              callout!(ov, Point3f(0, 0, 0); text = "label"),
              projectedlines!(ov, [Point3f(0, 0, 0), Point3f(1, 0, 0)]))
        @test shown(p)
        p.visible = false
        @test !shown(p)
    end
end
