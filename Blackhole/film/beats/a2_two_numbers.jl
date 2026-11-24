# a2 · A staged comparison with the same Hikari spacetime medium as a1.
# Spin is a labelled property, not a fictitious change to this Schwarzschild
# renderer or an animation of the gas masquerading as black-hole spin.
# Every quantity that changes is an argument the editor keys (see `perform`).
function build_two_numbers(canvas;
                           step_scale=1f0, emission_scale=12f0,
                           sky_exposure=BH_SKY_EXPOSURE,
                           animate_plasma=false,plasma_input=Observable{Any}(nothing))
    fig, sc, ax = frame3d(canvas; background = :black,
                        lights = blackhole_lights(;exposure=sky_exposure))
    scale = canvas[2] / 720
    a = (; cats = Observable(0f0), hole = Observable(0f0), gas = Observable(0f0), bending = Observable(0f0),
          horizon = Observable(false), hole_headline = Observable(false),
          item1 = Observable(0f0), item2 = Observable(0f0), item3 = Observable(0f0),
          item4 = Observable(0f0), item5 = Observable(0f0), item6 = Observable(0f0),
          mass = Observable(0f0), spin = Observable(0f0))
    ink(col, alpha) = lift(x -> (col, x), alpha)
    words(x, y, str, alpha; size = 30, color = :white, align = (:left, :center)) =
        filmtext!(ax, x * scale, y * scale; text = str, color = ink(color, alpha), fontsize = size * scale, align)

    spacetime_blackhole!(sc; step_scale, emission_scale, animate_plasma, plasma_input,
                         a.gas, a.bending, horizon_visible = a.horizon)
    look!(sc, Pose((0, -32, 17), (11, 0, 0); fov = 40))
    # The unaltered photo from keynote slides 3 and 4, fitted without cropping
    # either Niki or Nala. Image matrices have rows down; Makie images are x,y up.
    photo = load(joinpath(@__DIR__, "..", "..", "assets", "keynote_cats.png"))
    catframe = fill(RGBf(0, 0, 0), round(Int, 640scale), round(Int, 480scale))
    ph = size(catframe, 2)
    pw = round(Int, ph * size(photo, 2) / size(photo, 1))
    x0 = (size(catframe, 1)-pw) ÷ 2
    for y in 1:ph, x in 1:pw
        row = clamp(round(Int, (ph-y+0.5)*size(photo,1)/ph), 1, size(photo,1))
        col = clamp(round(Int, (x-0.5)*size(photo,2)/pw), 1, size(photo,2))
        catframe[x0+x,y] = RGBf(photo[row,col])
    end
    cat_scene = Scene(fig.scene; camera = campixel!, clear = false)
    translate!(cat_scene, 0, 0, 100)
    image!(cat_scene, (55scale, 55scale + size(catframe, 1)),
           (115scale, 115scale + size(catframe, 2)), catframe;
           alpha = a.cats, visible = lift(!, a.horizon))

    words(375, 85, "Credit: Niki & Nala", a.cats; size = 18,
          color = RGBf(0.65,0.65,0.68), align = (:center,:center))
    # One text object: overlapping transparent headings can still depth-occlude
    # glyphs in the overlay backend, even when their colour has zero alpha.
    headline = lift(h -> h ? "A black hole needs just two numbers" : "Describing a cat", a.hole_headline)
    headline_alpha = lift(max, a.cats, a.hole)
    filmtext!(ax, 70scale, 647scale; text = headline, color = ink(:white, headline_alpha),
          fontsize = 38*scale, align = (:left, :center))
    items = ["Colour", "Size", "Weight", "Personality", "Favourite food", "…"]
    for (k, (item, alpha)) in enumerate(zip(items, (a.item1, a.item2, a.item3, a.item4, a.item5, a.item6)))
        words(760, 510 - 58*(k-1), item, alpha; size = 32,
              color = k==6 ? ACCENT : RGBf(0.88, 0.88, 0.9))
    end
    for (title, detail, y, alpha) in (("MASS", "How heavy it is", 470, a.mass), ("SPIN", "How fast it turns", 280, a.spin))
        words(760, y+40, title, alpha; size = 25, color = ACCENT)
        words(760, y-10, detail, alpha; size = 34)
        lines!(ax, [Point2f(760scale, (y-55)*scale), Point2f(1185scale, (y-55)*scale)];
               color = ink(RGBf(0.25,0.25,0.28), alpha), linewidth = 2*scale)
    end
    return fig, a
end

"""
The keys of `build_two_numbers`'s arguments for the narration timing `T`: the
cats and the list describing them with line 1, each item as it is spoken; then
the hole, its gas and its bending fading in after line 2 starts, and mass and
spin as they are named. `picture` are the keys the traced picture draws (the
photo is part of it), `labels` those only the labels do.
"""
function perform(::typeof(build_two_numbers), T::Timing)
    s, e = T.starts, T.ends
    item(k) = inout(s[1] + (0.45f0 + 0.09f0 * k) * (e[1] - s[1]), s[2]; d_in = 0.4f0, d_out = 0.5f0)
    picture = [
        "cats" => inout(s[1], s[2]; d_out = 0.5f0),
        "gas" => ramp(s[2] + 0.6f0),
        "bending" => ramp(s[2] + 0.6f0),
        "horizon" => [(0f0, false, :hold), (s[2], true, :hold)],
    ]
    labels = [
        "hole" => ramp(s[2] + 0.6f0, 0.8f0),
        "hole_headline" => [(0f0, false, :hold), (s[2] + 0.6f0, true, :hold)],
        ("item$k" => item(k) for k in 1:6)...,
        "mass" => ramp(s[2] + 1.4f0),
        "spin" => ramp(s[2] + 4.3f0),
    ]
    return (; picture, labels)
end

PERFORMED["a2_two_numbers"] = build_two_numbers
