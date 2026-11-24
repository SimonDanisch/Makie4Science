# a4 · Why you need a giant telescope: the rule from the telescope film, then
# the numbers: a millimetre of radio light, an orange on the Moon, an opening
# as wide as the Earth (a gold circle growing to the globe's size).
#
# Every quantity that changes is an argument the editor keys (see `perform`):
# the globe's turn, the growing circle and when each label shows.

function build_giant_telescope(canvas)
    fig, sc, ov = frame3d(canvas)
    a = (; turn = Observable(-1.6f0), grow = Observable(0f0), rule = Observable(0f0),
          numbers = Observable(0f0), detail = Observable(0f0))
    globe!(sc, a.turn)
    look!(sc, Pose((0, -6.5, 1.2), (0, 0, 0.35); fov = 40))
    eye = Observable(Vec3f(0, -6.5, 1.2))
    ring_on_top!(ov, sc, Point3f(0, 0, 0), 1.0f0, eye; color = lift(g -> (ACCENT, g), a.grow), linewidth = 7)
    heading!(ov, "smallest detail it can see  ≈  wavelength ÷ width of the opening", a.rule)
    label!(ov, Point2f(150, 420), "wavelength:\n1.3 millimetres\n(radio light)"; align = (:left, :center),
           alpha = a.numbers, fontsize = 28)
    label!(ov, Point2f(1130, 420), "detail:\nan orange on the Moon"; align = (:right, :center),
           alpha = a.detail, fontsize = 28)
    caption!(ov, "opening needed: about as wide as the Earth", a.grow)
    return fig, a
end

"""
The keys of `build_giant_telescope`'s arguments for the narration timing `T`:
the globe turns at 0.03 rad a second throughout; the rule shows with line 1,
the numbers with line 2, the circle grows to the Earth's width over three
seconds from 40% of line 2. `picture` are the keys the traced picture draws,
`labels` those only the labels do.
"""
function perform(::typeof(build_giant_telescope), T::Timing)
    s, e = T.starts, T.ends
    picture = [
        # Keys on whole seconds: on a whole frame at any rate, so the turn's rate stays exact.
        "turn" => [(0f0, -1.6f0, :linear), (ceil(T.duration), -1.6f0 + 0.03f0 * ceil(T.duration), :linear)],
    ]
    labels = [
        "grow" => dial(s[2] + 0.4f0 * (e[2] - s[2]), 3f0),
        "rule" => ramp(s[1]),
        "numbers" => ramp(s[2]),
        "detail" => ramp(s[2] + 2f0),
    ]
    return (; picture, labels)
end

PERFORMED["a4_giant_telescope"] = build_giant_telescope
