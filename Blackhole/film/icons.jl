# Flat drawings the explanation beats share: a radio dish, a labelled box, a
# plane, a hard drive, a wave with its samples. Each takes an `alpha`
# Observable so it can fade in and out with the narration.

"""A radio dish as a simple outline: a bowl on a stand, at `p`, `s` across."""
function dish!(ax, p, s, alpha)
    θ = range(-0.85π, -0.15π; length = 40)
    bowl = [Point2f(p[1] + s / 2 * cos(t), p[2] + 0.6s + s / 2 * sin(t)) for t in θ]
    lines!(ax, bowl; color = faded(:white, alpha), linewidth = 4)
    lines!(ax, [Point2f(p[1], p[2] + 0.1s), Point2f(p[1], p[2] + 0.6s - s / 2 * sin(0.5π))]; color = faded(:white, alpha), linewidth = 3)
    poly!(ax, Point2f[(p[1] - 0.25s, p[2]), (p[1] + 0.25s, p[2]), (p[1] + 0.1s, p[2] + 0.15s), (p[1] - 0.1s, p[2] + 0.15s)];
          color = faded(:white, alpha))
end

"""A box with a title inside, at `r`."""
function box!(ax, r::Rect2f, title, alpha; colour = NOTE, fontsize = 26)
    poly!(ax, r; color = lift(a -> (colour, 0.18f0 * a), alpha), strokecolor = faded(colour, alpha), strokewidth = 2)
    filmtext!(ax, GeometryBasics.origin(r)[1] + widths(r)[1] / 2, GeometryBasics.origin(r)[2] + widths(r)[2] / 2; text = title,
          align = (:center, :center), color = faded(:white, alpha), fontsize)
end

"""A small plane outline at `p`, pointing right, `s` long."""
plane(p, s) = Point2f[p .+ s .* q for q in ((0.5, 0), (0.25, 0.06), (0.05, 0.06), (-0.1, 0.32), (-0.2, 0.32), (-0.08, 0.06),
                                             (-0.35, 0.06), (-0.45, 0.18), (-0.52, 0.18), (-0.46, 0), (-0.52, -0.18), (-0.45, -0.18),
                                             (-0.35, -0.06), (-0.08, -0.06), (-0.2, -0.32), (-0.1, -0.32), (0.05, -0.06), (0.25, -0.06))]

"""A hard drive seen from above, `s` wide, at `p` (its lower left): case, platter, and the arm with its head."""
function drive!(ax, p, s, alpha; colour = RGBf(0.75, 0.75, 0.78))
    poly!(ax, Rect2f(p, Vec2f(s, 1.3s)); color = lift(a -> (RGBf(0.2, 0.2, 0.22), a), alpha), strokecolor = faded(colour, alpha),
          strokewidth = 1.5)
    c = Point2f(p) + Vec2f(0.5s, 0.75s)
    poly!(ax, Circle(c, 0.42f0 * s); color = lift(a -> (RGBf(0.55, 0.55, 0.6), a), alpha))
    lines!(ax, [Point2f(p) + Vec2f(0.88s, 0.12s), c + Vec2f(0.08s, -0.18s)]; color = faded(colour, alpha), linewidth = 3)
end

"""Points along `amplitude * sin(2π f x + phase)` for x in `xs`, placed at `origin` (data units)."""
wave(xs, f; amplitude = 1, phase = 0, origin = Point2f(0, 0)) = [origin + Point2f(x, amplitude * sin(2π * f * x + phase)) for x in xs]
