# b8 · The picture, and the weighing. Line 1: four teams, working separately
# and in secret with their own methods; after seven weeks all four have a ring.
# Lines 2–3: shadow size scales with mass; apparent size and distance give
# physical size. Line 4: simulations calibrate the bright ring against mass.
# Scientific basis: EHT 2019 Paper VI, https://arxiv.org/abs/1906.11243 .
#
# Every quantity that changes is an argument the editor keys (see `perform`):
# the teams' rings revealed, the ruler, and the best match picked out.

"""One team's reconstruction of the ring: a little different in size, width, bright side and blur, with faint blotches."""
function team_picture(s)
    ring = blurred(image(Ring(radius = 21 + randn(s), width = 3.5 + abs(randn(s)), brightness = 0.6 + 0.1randn(s), angle = π + 0.2randn(s)),
                         GRID), GRID, 18.0 + 4rand(s))
    blotches = blurred(rand(s, size(ring)...), GRID, 6.0)
    p = ring ./ maximum(ring) .+ 0.05 .* blotches ./ maximum(blotches)
    return p ./ maximum(p)
end

"""Four reconstructions of the same ring, each a little different (the teams' methods leave different traces)."""
team_pictures() = cached("team_pictures") do
    s = Random.Xoshiro(21)
    [team_picture(s) for _ in 1:4]
end

"""Simulated black holes of different masses and spins: rings of different sizes and bright sides."""
simulated_pictures(n = 40) = cached("simulated_pictures") do
    s = Random.Xoshiro(8)
    [(b = blurred(image(Ring(radius = 12 + 18rand(s), width = 2 + 4rand(s), brightness = rand(s), angle = 2π * rand(s)), GRID), GRID, EHT_BLUR);
      b ./ maximum(b)) for _ in 1:n]
end

function build_imaging(canvas)
    fig, ov = frame2d(canvas; padding = (30, 30, 110, 90))
    ax = Axis(fig[1, 1]; backgroundcolor = SPACE, limits = (0, 16, 0, 9), aspect = DataAspect())
    hidedecorations!(ax); hidespines!(ax)
    write!(x, y, s, alpha; size = 26, align = (:left, :center), colour = :white) =
        filmtext!(ax, x, y; text = s, align, color = faded(colour, alpha), fontsize = size)
    a = (; teams = Observable(0f0), reveal = Observable(0f0), ruler = Observable(0f0),
          physical_size = Observable(0f0), library = Observable(0f0), pick = Observable(0f0))

    # line 1: four teams
    one = a.teams
    reveal = a.reveal
    for (k, p) in enumerate(team_pictures())
        x = 0.5 + 3.9 * (k - 1)
        poly!(ax, Rect2f(x, 1.6, 3.4, 5.2); color = lift(v -> (RGBf(0.1, 0.1, 0.13), v), one), strokecolor = faded(NOTE, one), strokewidth = 2)
        write!(x + 1.7, 6.3, "team $k", one; align = (:center, :center))
        write!(x + 1.7, 3.9, "?", lift((v, r) -> v * (1 - r), one, reveal); align = (:center, :center), size = 80)
        image!(ax, (x + 0.2, x + 3.2), (2.0, 5.0), p; colormap = HOT, colorrange = (0, 1), alpha = lift(*, one, reveal))
    end
    write!(8.0, 8.2, lift(r -> r < 0.5 ? "four teams, in secret, for seven weeks" : "all four found a ring", reveal), one;
           align = (:center, :center), size = 30)

    # Establish the physical ruler before introducing the simulation library.
    ruler = a.ruler
    seen = blurred(model_ring(), GRID, EHT_BLUR)
    image!(ax, (1.0, 7.0), (1.5, 7.5), seen; colormap = HOT, alpha = ruler)
    lines!(ax, [Point2f(1.7, 4.5), Point2f(6.3, 4.5)]; color = faded(NOTE, ruler), linewidth = 2)
    write!(8.2, 6.3, "more mass → a larger shadow", ruler; size = 28)
    three = a.physical_size
    write!(8.2, 4.8, "apparent size + distance", three; size = 28, colour = NOTE)
    write!(8.2, 3.7, "↓", three; size = 34)
    write!(8.2, 2.7, "physical size", three; size = 30)
    # line 4: simulations calibrate the bright ring against shadow and mass.
    two = a.library
    # the library, with the simulation that matches (the model ring itself) in it
    best = 30
    seen = blurred(model_ring(), GRID, EHT_BLUR)
    sims = [k == best ? seen ./ maximum(seen) : p for (k, p) in enumerate(simulated_pictures())]
    pick = a.pick
    for (k, p) in enumerate(sims)
        i, j = mod(k - 1, 8), div(k - 1, 8)
        x, y = 0.4 + 1.18 * i, 6.6 - 1.25 * j
        image!(ax, (x, x + 1.08), (y, y + 1.08), p; colormap = HOT, colorrange = (0, 1),
               alpha = lift((v, f) -> v * (k == best ? 1f0 : 1 - 0.7f0 * f), two, pick))
    end
    bi, bj = mod(best - 1, 8), div(best - 1, 8)
    lines!(ax, outline(Rect2f(0.4 + 1.18 * bi, 6.6 - 1.25 * bj, 1.08, 1.08); pad = 0.06); color = faded(ACCENT, lift(*, two, pick)),
           linewidth = 4)
    write!(0.4, 8.3, "computer simulations of black holes", two; size = 26)
    write!(10.2, 5.2, "best match:", lift(*, two, pick); size = 30)
    write!(10.2, 4.1, "6.5 billion\ntimes the Sun", lift(*, two, pick); size = 40, colour = ACCENT)
    return fig, a
end

"""
The keys of `build_imaging`'s arguments for the narration timing `T`: the four
teams with line 1, their rings revealed at 88% of it; the ruler from line 2
until line 4; the step from apparent to physical size with line 3; the
simulation library with line 4 and its best match picked out at 65% of it.
`picture` are the keys the picture draws, `labels` those only the labels do.
"""
function perform(::typeof(build_imaging), T::Timing)
    s, e = T.starts, T.ends
    within(i, u) = s[i] + u * (e[i] - s[i])
    picture = [
        "teams" => inout(s[1], s[2]; d_out = 0.4f0),
        "reveal" => ramp(within(1, 0.88f0), 0.8f0),
        "ruler" => inout(s[2], s[4]),
        "library" => ramp(s[4]),
        "pick" => dial(within(4, 0.65f0), 1f0),
    ]
    labels = ["physical_size" => inout(s[3], s[4]; d_out = 0.4f0)]
    return (; picture, labels)
end

PERFORMED["b8_imaging"] = build_imaging
