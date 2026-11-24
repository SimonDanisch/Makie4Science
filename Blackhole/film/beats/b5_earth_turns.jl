# b5 · The Earth turns. Left: the globe seen from M87*'s direction, turning
# through one night of observing, with the lines between the sites. Right:
# the note map: each pair's note traced as the night goes on (the real EHT
# sites and M87*'s position), and its mirror image. The night advances at a
# constant angular rate; current notes use the continuous hour angle.
#
# Every quantity that changes is an argument the editor keys (see `perform`):
# how far through the night it is, and the two captions.

"""
The hour angle `u` (0 to 1) of the way through the shown night: time spent
where pairs are listening, so the hours when few pairs see M87* go by faster.
"""
function nightclock(rows, Hs)
    busy = [count(r -> r[3] == H, rows) for H in Hs]
    weight = 0.2 .+ busy ./ maximum(busy)
    elapsed = cumsum(vcat(0.0, (weight[1:end-1] .+ weight[2:end]) ./ 2))
    elapsed ./= elapsed[end]
    return function (u)
        i = clamp(searchsortedlast(elapsed, u), 1, length(Hs) - 1)
        w = (u - elapsed[i]) / (elapsed[i+1] - elapsed[i])
        return Float32(Hs[i] + clamp(w, 0, 1) * (Hs[i+1] - Hs[i]))
    end
end

function build_earth_turns(canvas)
    fig, ov = frame2d(canvas; padding = (20, 40, 100, 40))
    a = (; hour_angle = Observable(Float32(first(night()))), turning_caption = Observable(0f0), night_caption = Observable(0f0))
    ls = LScene(fig[1, 1]; show_axis = false, scenekw = (backgroundcolor = SPACE, lights = sunlight()))
    cam3d!(ls.scene; center = false)
    sc = ls.scene
    ax = Axis(fig[1, 2]; aspect = DataAspect(), backgroundcolor = SPACE, limits = (-9, 9, -9, 9),
              title = "the notes heard", titlecolor = :white, titlesize = 26,
              xlabel = "middle: the coarse shape    far out: the fine details", xlabelcolor = :gray75, xlabelsize = 22,
              xgridcolor = (:white, 0.08), ygridcolor = (:white, 0.08))
    hidexdecorations!(ax; grid = false, label = false); hideydecorations!(ax; grid = false); hidespines!(ax)
    rows = night_notes()
    hour = a.hour_angle
    # seen from the black hole: the Earth turns under it
    δ = deg2rad(M87.dec)
    turn = lift(H -> Float32(H - π / 2), hour)
    g = globe!(sc, turn)
    look!(sc, Pose(4.0f0 .* (0, -cos(δ), sin(δ)), (0, 0, 0); fov = 40))
    pts = [g.point(p.lat, p.lon; h = 0.012) for p in PLACES]
    pairs = unique((r[1], r[2]) for r in rows)
    colours = [Makie.wong_colors()[mod1(k, 7)] for k in eachindex(pairs)]
    pairindex = Dict(p => k for (k, p) in enumerate(pairs))
    # the pairs listening now, as lines between their sites, in their notes' colours
    listening = lift(hour) do H
        # Evaluate the current geometry at the actual continuous hour, not at
        # the last ten-minute sample (which made the markers/arcs jump).
        now = [(i,j) for (i,j) in pairs if
            elevation(EHT[i],H)>deg2rad(15) && elevation(EHT[j],H)>deg2rad(15)]
        line = Point3f[]; cols = RGBAf[]
        drawn = Set{Tuple{String,String}}()
        for pair in now
            places = (EHT[pair[1]].place, EHT[pair[2]].place)
            sitepair = Tuple(sort(collect(places)))
            sitepair in drawn && continue
            push!(drawn, sitepair)
            # The globe is a site-level diagram. Colocated dishes still have
            # distinct measurements in the uv panel, but share one drawn arc.
            pa, pb = (begin
                p = only(filter(p -> p.name == place, PLACES))
                spin(sphere_point(p.lat, p.lon; h = 0.012), Float32(H - π / 2))
            end for place in places)
            c = RGBAf(colours[pairindex[pair]])
            append!(line, arc(pa, pb; rise = 0.08f0)); push!(line, Point3f(NaN))
            append!(cols, fill(c, 49))
        end
        isempty(line) ? (Point3f[Point3f(NaN)], [RGBAf(0, 0, 0, 0)]) : (line, cols)
    end
    lines!(sc, lift(first, listening); color = lift(last, listening), linewidth = 3)
    scatter!(sc, lift((ps...) -> collect(ps), pts...); color = ACCENT, markersize = 14)
    heard = lift(hour) do H
        sel = [r for r in rows if r[3] <= H]
        pts = Point2f[]; cols = RGBAf[]
        for r in sel
            c = colours[pairindex[(r[1], r[2])]]
            push!(pts, Point2f(r[4] / 1e9, r[5] / 1e9), Point2f(-r[4] / 1e9, -r[5] / 1e9))
            push!(cols, RGBAf(c), RGBAf(c))
        end
        isempty(pts) ? (Point2f[Point2f(NaN)], [RGBAf(0, 0, 0, 0)]) : (pts, cols)
    end
    scatter!(ax, lift(first, heard); color = lift(last, heard), markersize = 6)
    # the notes heard right now, larger
    current = lift(hour) do H
        now = [(i,j) for (i,j) in pairs if
            elevation(EHT[i],H)>deg2rad(15) && elevation(EHT[j],H)>deg2rad(15)]
        pts = Point2f[]; cols = RGBAf[]
        for (i,j) in now
            c = RGBAf(colours[pairindex[(i,j)]])
            u,v=uv(EHT[i],EHT[j],H)
            push!(pts, Point2f(u / 1e9, v / 1e9), Point2f(-u / 1e9, -v / 1e9))
            push!(cols, c, c)
        end
        isempty(pts) ? (Point2f[Point2f(NaN)], [RGBAf(0, 0, 0, 0)]) : (pts, cols)
    end
    scatter!(ax, lift(first, current); color = lift(last, current), markersize = 14, strokewidth = 1.5, strokecolor = :white)
    caption!(ov, "As the Earth turns, each pair hears a slowly changing note", a.turning_caption)
    caption!(ov, "One night of notes: most of the music is still missing", a.night_caption)
    return fig, a
end

"""
The keys of `build_earth_turns`'s arguments for narration timing `T`: the
whole night runs at a constant angular rate across the shot. The first caption
runs from 4 s into line 1 until line 2, the second from 2 s into line 2.
"""
function perform(::typeof(build_earth_turns), T::Timing)
    s, e = T.starts, T.ends
    picture = [
        # Physical rotation at one steady rate. Do not speed up and slow down
        # by a factor of nine whenever the number of listening pairs changes.
        "hour_angle" => [(0f0,Float32(first(night())),:linear),
                         (T.duration-1f0/60,Float32(last(night())),:linear)],
    ]
    labels = [
        "turning_caption" => inout(s[1] + 4, s[2]),
        "night_caption" => ramp(s[2] + 2),
    ]
    return (; picture, labels)
end

PERFORMED["b5_earth_turns"] = build_earth_turns
