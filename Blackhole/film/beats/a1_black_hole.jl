# a1 · RayDemo's spacetime medium, rendered by RayMakie/Hikari VolPath.
# Line by line: the hole alone (its edge, the event horizon);
# the disk of gas, first as it would look if light went straight; gravity
# bending light, so the back of the disk shows over and under the hole; the
# shadow, wider than the hole, and the photon ring; the Doppler shift; and the
# view from Earth, almost from above. The camera circles slowly throughout and
# moves, line by line, to where each effect shows best.
#
# Every quantity that changes is an argument the editor keys (see `perform`):
# the camera's orbit, the gas, light bending and Doppler dials, and when each
# label shows.

function build_black_hole(canvas;
                          step_scale=1f0, emission_scale=12f0,
                          sky_exposure=BH_SKY_EXPOSURE,
                          disk_label_radius=2.8f0, doppler_label_radius=3f0,
                          shadow_label_follow_view=true,
                          animate_plasma=false,plasma_input=Observable{Any}(nothing))
    fig, sc, ov = frame3d(canvas; background = :black,
                        lights = blackhole_lights(;exposure=sky_exposure))
    a = (; gas = Observable(0f0), bending = Observable(1f0), doppler = Observable(0f0),
          horizon_mark = Observable(0f0), stars_caption = Observable(0f0), disk_label = Observable(0f0),
          straight_caption = Observable(0f0), bending_caption = Observable(0f0),
          far_side_label = Observable(0f0), other_side_label = Observable(0f0),
          sizes = Observable(0f0), shadow_label = Observable(0f0), ring_label = Observable(0f0),
          doppler_labels = Observable(0f0), earth_caption = Observable(0f0))
    # A broad orbit, rather than a nearly fixed edge-on view: the camera sees
    # the disk from above, crosses its plane, travels below it, and rises to
    # the M87* inclination. The fixed sky makes this travel visible even for
    # the rotationally symmetric hole; its stars lens along the traced rays.
    look!(sc,Pose(32 .* (cosd(28)*cosd(-105),cosd(28)*sind(-105),sind(28)),(0,0,0);fov=30))
    spacetime_blackhole!(sc; a.bending, a.gas, a.doppler, step_scale, emission_scale,
                         animate_plasma, plasma_input)
    camera=cameracontrols(sc)
    cam=lift((eye,target,fov)->BHCamera(Pose(eye,target;fov)),camera.eyeposition,camera.lookat,camera.fov)

    # what is named, where it shows
    centre = lift(k -> screenpoint(k, (0, 0, 0), canvas), cam)
    hole = lift(k -> apparent(k, 1, canvas), cam)
    shadow = lift(k -> apparent(k, PHOTON_RING, canvas), cam)
    # Use this outline ONLY in the explicitly straight-light illustration.
    # The event horizon itself is not a visible little circle inside the lensed
    # shadow. Keeping that schematic on the bent image was misleading.
    lines!(ov, lift((p, r) -> circlepoints(p, r), centre, hole);
           color = lift(x -> (RGBf(1,0.96,0.86), 0.65f0 * x), a.horizon_mark), linewidth = 1.5)
    label!(ov, Point2f(canvas[1]/2, canvas[2]-65), "Event horizon · the point of no return";
           alpha=a.horizon_mark,fontsize=30)
    caption!(ov, "The stars behind it are bent into arcs", a.stars_caption)
    pin!(ov, lift(k -> screenpoint(k, -disk_label_radius * k.right, canvas), cam), (60, -150), "accretion disk: hot, glowing gas",
         a.disk_label)
    caption!(ov, "Illustration with light bending switched off", a.straight_caption)
    caption!(ov, "Gravity bends light", a.bending_caption)
    # The far-side image changes from the upper to the lower arc when the
    # camera crosses the disk. Keep the annotation on that image.
    far_side = lift(eye -> eye[3] < 0 ? -1f0 : 1f0, camera.eyeposition)
    label!(ov,Point2f(canvas[1]/2,canvas[2]-65),"Light from the back of the disk";
           alpha=a.far_side_label,fontsize=30)
    pin!(ov, lift((p, r, side) -> p + Vec2f(0.3f0 * r, -side * 1.1f0 * r), centre, shadow, far_side),
         (150, -70), "another view around the other side", a.other_side_label)
    # The lensed picture gets one feature at a time, without crossing leaders
    # or a fictitious visible event horizon inside the shadow.
    # Keep the old sizes label's slot for saved edits; revised cues disable it.
    label!(ov, Point2f(canvas[1]/2,65), ""; alpha=a.sizes)
    # Name the actual dark area from INSIDE it. A synthetic oval mask or a
    # contour on its bright rim would imply a boundary the image does not show.
    filmtext!(ov,lift((p,r)->p+Vec2f(0,-0.4f0*r),centre,shadow);
        text="shadow",align=(:center,:center),fontsize=26,
        color=faded(RGBf(1,0.96,0.86),a.shadow_label))
    label!(ov,Point2f(canvas[1]/2,65),"Shadow · the larger dark region";
           alpha=a.shadow_label,fontsize=30)
    lines!(ov,lift(k->photon_ring_contour(k,canvas),cam);
        name=:photon_ring_highlight,
        color=lift(x->(RGBf(0.25,0.85,1),0.95f0*x),a.ring_label),linewidth=2)
    label!(ov,Point2f(canvas[1]/2,canvas[2]-65),"Photon ring · light looping around the hole";
           alpha=a.ring_label,fontsize=30)
    # line 5: towards us and away
    pin!(ov, lift(k -> screenpoint(k, -doppler_label_radius * k.right, canvas), cam), (-30, 140), "coming towards us: brighter",
         a.doppler_labels)
    pin!(ov, lift(k -> screenpoint(k, doppler_label_radius * k.right, canvas), cam), (30, 140), "going away: dimmer",
         a.doppler_labels)
    caption!(ov, "M87* as we see it: almost from above", a.earth_caption)
    return fig, a
end

"""
The keys of `build_black_hole`'s arguments for the narration timing `T`: the
camera circles at 5° a second throughout and changes height and distance line
by line; gas, bending and Doppler fade with the lines that introduce them; the
labels show while their line is spoken. Phrase onsets are Kokoro's phoneme
durations fitted to the recorded line lengths: "event horizon" at 83% of line 1,
"photon ring" at 91% of line 4. `picture` are the keys the traced picture draws,
`labels` those only the labels do.
"""
function perform(::typeof(build_black_hole), T::Timing)
    s, e = T.starts, T.ends
    phrase(line, fraction) = s[line] + fraction * (e[line] - s[line])
    picture = [
        # Keys on whole seconds: on a whole frame at any rate, so the orbit's rate stays exact.
        "azimuth" => [(0f0, -105f0, :linear), (ceil(T.duration), -105f0 + 5f0 * ceil(T.duration), :linear)],
        "elevation" => eased([0 => 28, s[2] => 32, s[3] => 40, s[3] + 4 => 4, s[4] => -20, s[4] + 7 => -32,
                              s[5] => -10, s[5] + 5 => 22, s[6] => 35, s[6] + 6 => 73]),
        "distance" => eased([0 => 32, s[2] => 32, s[3] => 30, s[3] + 4 => 28, s[4] => 27, s[4] + 7 => 23,
                             s[5] => 26, s[5] + 5 => 30, s[6] => 30, s[6] + 6 => 28]),
        # Lensed stars around the bare hole first; gravity off for the explicitly
        # hypothetical straight-light explanation, then on again.
        "gas" => dial(s[2], 2.5f0),
        "bending" => eased([s[2] => 1, s[2] + 1.8f0 => 0, s[3] + 0.8f0 => 0, s[3] + 3.8f0 => 1]),
        "doppler" => dial(s[5] + 0.5f0, 2.5f0),
    ]
    orbit=Dict(picture)
    eye(t)=begin
        az=performancevalue(orbit["azimuth"],t);el=performancevalue(orbit["elevation"],t);d=performancevalue(orbit["distance"],t)
        d .* (cosd(el)*cosd(az),cosd(el)*sind(az),sind(el))
    end
    filter!(p->first(p) ∉ ("azimuth","elevation","distance"),picture)
    for i in 1:3
        push!(picture,"camera.eye[$i]"=>sampledkeys(t->eye(t)[i],0,ceil(T.duration)))
    end
    labels = [
        "horizon_mark" => inout(s[2]+2.3f0,s[3];d_in=0.3f0,d_out=0.3f0),
        "stars_caption" => inout(s[1] + 3, s[2]),
        "disk_label" => inout(s[2] + 1.5f0, s[3]),
        "straight_caption" => inout(s[2] + 2, s[3]),
        "bending_caption" => inout(s[3], s[4]),
        "far_side_label" => inout(s[3] + 3.5f0, s[4]),
        "other_side_label" => inout(s[3] + 5, s[4]),
        "sizes" => [(0f0,0f0,:hold)],
        "shadow_label" => inout(s[4] + 1.5f0,phrase(4,0.55f0);d_out=0.3f0),
        "ring_label" => inout(phrase(4,0.55f0),s[5];d_in=0.3f0,d_out=0.3f0),
        "doppler_labels" => inout(s[5] + 1.5f0, s[6]),
        "earth_caption" => ramp(s[6] + 2),
    ]
    return (; picture, labels)
end

PERFORMED["a1_black_hole"] = build_black_hole
