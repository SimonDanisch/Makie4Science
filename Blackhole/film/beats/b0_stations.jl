# b0 · Telescopes all over the world. It opens on the ground: ALMA's antennas
# on the Chajnantor plateau in Chile, the camera drifting past them. Then the
# globe, turning from Hawaii towards Europe while each site lights up as it is
# named, and the lines between them, the pieces of one Earth-sized dish. (The
# South Pole Telescope is part of the EHT but never sees M87*, so it is not
# among them.)

function build_stations(canvas)
    fig, sc, ov = frame3d(canvas)
    a = (; ground_view = Observable(true), turn = Observable(0f0),
          together = Observable(0f0),
          ground_caption = Observable(0f0), network_caption = Observable(0f0))
    scatter!(sc, starfield(); color = (:white, 0.5), markersize = 3)
    ground = LScene(fig[1, 1]; show_axis = false, scenekw = (; backgroundcolor = RGBf(0.3, 0.45, 0.7), lights = plateau_sky()))
    ps = ground.scene
    cam3d!(ps; center = false)
    antennas!(ps); chajnantor!(ps)
    opening = a.ground_view
    connect!(ps.visible, opening)
    connect!(sc.visible, lift(!, opening))
    look!(ps,Pose((11,-10,1.7),(1.1,1.2,3.4);fov=40))
    caption!(ov, "ALMA: 5000 metres up, in Chile's Atacama desert", a.ground_caption)
    g = globe!(sc, a.turn)
    # Both layers retain the Earth as a native-property owner. A ground mesh
    # would be deleted from the annotation layer, leaving its cut unanimated.
    plotattribute!(g.earth, :ground_view, a.ground_view)
    look!(sc, Pose((0, -4.2, 1.6), (0, 0, 0.1); fov = 40))
    eye = Observable(Vec3f(0, -4.2, 1.6))
    pts = [g.point(p.lat, p.lon; h = 0.012) for p in PLACES]
    sites=Pair{Symbol,Observable}[]
    for (k, (p, place)) in enumerate(zip(pts, PLACES))
        on_ = Observable(0f0)
        push!(sites,Symbol("site",k)=>on_)
        seen = lift((a, q, e) -> a * Float32(facing(q, e)), on_, p, eye)
        marker=scatter!(sc, lift(q -> [q], p); name=Symbol("site_",lowercase(place.name)), color = ACCENT,
            markersize = lift(a -> 18a, on_), strokecolor = :black, strokewidth = 1)
        connect!(on_,lift(size->Float32(size[1]/18),marker.markersize))
        propertypath!(on_,marker,"markersize[1]";scale=18,also=["markersize[2]"])
        callout!(ov, sc, p, (k % 2 == 0 ? (60, 40) : (-60, 50)), place.name, seen; fontsize = 22)
    end
    # the baselines, as arcs above the globe
    together = a.together
    for i in eachindex(PLACES), j in i+1:lastindex(PLACES)
        path = lift((p, q) -> arc(p, q; rise = 0.15f0), pts[i], pts[j])
        lines!(sc, path; color = lift(x -> (RGBf(0.85, 0.5, 1.0), 0.8f0 * x), together), linewidth = 2)
    end
    caption!(ov, "The Event Horizon Telescope: one giant dish, in pieces", a.network_caption)
    return fig, merge(a,(;sites...))
end

function perform(::typeof(build_stations), T::Timing)
    s, e = T.starts, T.ends
    # Spoken country onsets within line 1; kept as editable keys in the project.
    # Kokoro word_onsets, af_heart / 0.95, relative to the 11.021333 s take.
    fractions = Float32.((6.080458, 6.905458, 7.730458, 8.580458, 9.230458, 9.930458, 10.505458) ./ 11.021333)
    named = [s[1] + f * (e[1] - s[1]) for f in fractions]
    cut = named[1] - 0.6f0
    angles = Float32[deg2rad(-90 - p.lon) for p in PLACES]
    # One steady eastward tour, without the former stop/start at every name,
    # reverse swing to Greenland, and second reversal at the end. Greenland's
    # high-latitude callout remains visible from the final European view.
    turns = [(0f0, angles[1], :linear), (named[1], angles[1], :linear),
             (named[6], angles[6], :linear)]
    picture = [
        "ground_view" => [(0f0, true, :hold), (cut, false, :hold)],
        "turn" => turns,
        "together" => ramp(s[2], 1.5f0),
    ]
    for (name, from, to) in (("camera[2].eye", (11, -10, 1.7), (19, -4, 2.4)),
                             ("camera[2].lookat", (1.1, 1.2, 3.4), (-2, 6, 4.2)))
        for i in 1:3
            push!(picture, "$name[$i]" => eased([0 => from[i], cut => to[i]]))
        end
    end
    for k in eachindex(named)
        push!(picture, "site$k" => ramp(named[k], 0.4f0))
    end
    labels = [
        "ground_caption" => inout(s[1] + 0.5f0, cut - 0.3f0; d_out = 0.3f0),
        "network_caption" => ramp(s[2] + 1f0),
    ]
    return (; picture, labels)
end

PERFORMED["b0_stations"] = build_stations
