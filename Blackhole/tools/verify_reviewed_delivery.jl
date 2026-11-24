# Independent post-recording validation; no renderer or alternate environment.
root=dirname(something(Base.active_project(),""))
realpath(root)==realpath(joinpath(@__DIR__,"..","..")) || error("Use the Science4Makie root project")
length(ARGS)==2 || error("usage: verify_reviewed_delivery.jl PROJECT SERVICE")
project,service=ARGS
using VideoEditor, RayMakie
const VE=VideoEditor
include("continuous_blackhole_edit.jl")
while strip(read(ignorestatus(`systemctl --user is-active $service`),String)) in ("active","activating")
    sleep(30)
end
movie=joinpath(dirname(project),"black_hole_1080p.mp4")
logfile=joinpath(dirname(project),"farm_coordinator.log")
isfile(logfile) && occursin("DONE $movie",read(logfile,String)) || error("Recording ended without a completed export")
seq=VE.loadproject(project)
verify_continuous_movie(movie,VE.seqlength(seq))
println("DELIVERY VERIFIED ",movie)
