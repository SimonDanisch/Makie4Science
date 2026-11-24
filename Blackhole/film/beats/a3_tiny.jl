# a3 · Tiny in the sky. Line 1: the shadow of M87* to scale against our solar
# system (Neptune's orbit, 30 AU, against a shadow some 660 AU across). Line
# 2: the Earth, the Moon, and an orange on it (drawn far bigger than it looks).
#
# Every quantity that changes is an argument the editor keys (see `perform`):
# the shadow and the orbits fading in, the switch to the Earth and Moon, the
# zoom onto the orange (the field of view, and how far the aim has turned from
# the Moon's centre to the orange), and when each label shows.

function build_tiny(canvas; shadow_halfheight=480f0)
    fig, ov = frame2d(canvas; padding = (0, 0, 0, 0))
    a = (; shadow = Observable(0f0), orbits = Observable(0f0), earth_view = Observable(false),
          heading = Observable(0f0), orbits_label = Observable(0f0), distance_caption = Observable(0f0),
          earth_label = Observable(0f0), orange_label = Observable(0f0), orange_caption = Observable(0f0))
    # line 1, flat: the shadow and our solar system to scale
    # Keep the complete 330-AU shadow inside the title/caption safe area.
    halfwidth=shadow_halfheight*canvas[1]/canvas[2]
    ax = Axis(fig[1, 1]; aspect = DataAspect(), backgroundcolor = SPACE,
              limits = (-halfwidth,halfwidth,-shadow_halfheight,shadow_halfheight))
    hidedecorations!(ax); hidespines!(ax)
    # the 3D Earth and Moon, over the same cell, for line 2
    ls = LScene(fig[1, 1]; show_axis = false, scenekw = (backgroundcolor = SPACE, lights = sunlight()))
    # fixed clip planes: the camera looks 60 units out past an Earth 3.5 units away,
    # and clip planes relative to that distance cut the Earth off
    cam3d!(ls.scene; center = false, clipping_mode = :static, near = 0.05f0, far = 500f0)
    connect!(ls.scene.visible, a.earth_view)
    # the whole block: its background is drawn in the blockscene, not in ax.scene
    connect!(ax.blockscene.visible, lift(!, a.earth_view))
    shadow_r = 330.0                                       # AU: √27 GM/c² for 6.5 billion suns
    θ = range(0, 2π; length = 200)
    ringpts = [Point2f(shadow_r * cos(t), shadow_r * sin(t)) for t in θ]
    poly!(ax, ringpts; color = lift(x -> (:black, x), a.shadow))
    lines!(ax, ringpts; color = lift(x -> (RGBf(1, 0.6, 0.2), x), a.shadow), linewidth = 6)
    for (r, name) in ((1.0, "Earth"), (5.2, "Jupiter"), (30.1, "Neptune"))
        lines!(ax, [Point2f(r * cos(t), r * sin(t)) for t in θ]; color = lift(x -> (NOTE, x), a.orbits), linewidth = 2)
    end
    label!(ov, Point2f(640, 360 + 48), "our solar system, to scale"; align = (:center, :bottom), alpha = a.orbits_label,
           fontsize = 24)
    heading!(ov, "The shadow of M87*: bigger than our solar system", a.heading)
    caption!(ov, "55 million light-years away", a.distance_caption)
    # line 2: Earth, Moon, orange
    sc = ls.scene
    turn = Observable(-1.2f0)
    earth=globe!(sc, turn).earth
    labels_only() || plotattribute!(earth,:visible,a.earth_view)
    moon_at = Point3f(60, 0, 0)
    mesh!(sc, Sphere(moon_at, 0.27f0); color = RGBf(0.6, 0.6, 0.58))
    orange_at = moon_at + Point3f(-0.27f0, 0, 0) * 0.995f0 + Point3f(0, 0, 0.012)
    mesh!(sc, Sphere(orange_at, 0.012f0); color = RGBf(1, 0.5, 0.05))
    # From one place near the Earth: narrowing onto the Moon, then turning from
    # its centre onto the orange.
    eye = Point3f(-3.2, -1.5, 0.6)
    look!(sc,Pose(eye,moon_at;fov=40))
    callout!(ov, sc, Point3f(-0.4, -0.75, 0.3), (-40, -120), "the Earth", a.earth_label)
    callout!(ov, sc, orange_at, (80, 90), "an orange on the Moon\n(drawn far bigger than it would look)", a.orange_label)
    caption!(ov, "Seen from Earth, M87* looks as small as an orange on the Moon", a.orange_caption)
    return fig, a
end

"""
The keys of `build_tiny`'s arguments for the narration timing `T`: the shadow
with line 1 and our solar system's orbits 3 s later, line 1's labels leaving
over 0.3 s as line 2 starts; then the Earth and Moon, the view narrowing onto
the Moon in 1.4 s and turning onto the orange in another 1.4 s, where it holds
(line 2 is short), and each label as its part is shown. `picture` are the keys
the traced picture draws, `labels` those only the labels do.
"""
function perform(::typeof(build_tiny), T::Timing)
    s = T.starts
    picture = [
        "shadow" => ramp(s[1]),
        "orbits" => ramp(s[1] + 3),
        "earth_view" => [(0f0, false, :hold), (s[2], true, :hold)],
        "fov" => eased([s[2] => 40, s[2] + 1.4f0 => 3, s[2] + 2.8f0 => 0.4f0]),
        "aim" => eased([s[2] + 1.4f0 => 0, s[2] + 2.8f0 => 1]),
    ]
    motion=Dict(picture)
    fov=motion["fov"];aim=motion["aim"]
    filter!(p->first(p) ∉ ("fov","aim"),picture)
    push!(picture,"camera.fov"=>fov)
    moon=Point3f(60,0,0);orange=moon+Point3f(-0.27f0,0,0)*0.995f0+Point3f(0,0,0.012)
    for i in 1:3
        push!(picture,"camera.lookat[$i]"=>[(t,moon[i]+v*(orange[i]-moon[i]),e) for (t,v,e) in aim])
    end
    labels = [
        "heading" => inout(s[1], s[2]; d_out = 0.3f0),
        "orbits_label" => inout(s[1] + 3, s[2]; d_out = 0.3f0),
        "distance_caption" => inout(s[1] + 6, s[2]; d_out = 0.3f0),
        "earth_label" => inout(s[2], s[2] + 0.8f0; d_out = 0.4f0),
        "orange_label" => ramp(s[2] + 2.8f0, 0.5f0),
        "orange_caption" => ramp(s[2] + 1),
    ]
    return (; picture, labels)
end

PERFORMED["a3_tiny"] = build_tiny
