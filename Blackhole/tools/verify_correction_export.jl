# Durable post-export verification, in the sole Science4Makie root environment.
root=dirname(something(Base.active_project(),""))
basename(root)=="Science4Makie" || error("Use the Science4Makie root project")
directory=joinpath(root,"BlackholeImage","renders","corrections_1080p_20261024")
service=get(ARGS,1,"s4m-corrections-1080p-20261024.service")
jobname=get(ARGS,2,"corrections_1080p_20261024")
while success(`systemctl --user is-active --quiet $service`)
    sleep(30)
end
log=joinpath(directory,"farm_coordinator.log")
isfile(log) && occursin("DONE ",read(log,String)) || error("Coordinator ended without completing export")
movie=joinpath(directory,"black_hole_1080p.mp4")
using TOML
metadata=TOML.parsefile(joinpath(root,"BlackholeImage","renders","farm",jobname,"job","job.toml"))
expected=metadata["total"]
ff=Base.require(Base.PkgId(Base.UUID("b22a6f82-2f65-5046-a5b2-351ab43fb4e5"),"FFMPEG_jll"))
probe=strip(read(`$(ff.ffprobe()) -v error -count_frames -select_streams v:0 -show_entries stream=width,height,r_frame_rate,nb_read_frames -of csv=p=0 $movie`,String))
fields=split(probe,',')
fields==["1920","1080","30/1",string(expected)] || error("Unexpected video metadata: $probe")
audio=strip(read(`$(ff.ffprobe()) -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 $movie`,String))
audio=="aac" || error("Expected narration audio; found $audio")
run(`$(ff.ffmpeg()) -v error -xerror -i $movie -f null -`)
report="VERIFIED $expected frames; 1920x1080; 30 fps; AAC audio; complete decode passed\n$movie\n"
open(io->write(io,report),joinpath(directory,"validation.txt"),"w")
println(report)
