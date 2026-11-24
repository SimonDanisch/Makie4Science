# Bounded temporal comparison through the normal VideoEditor pipeline.
# Run only in the Science4Makie root project. Preserve the saved film's native
# camera tracks and effects; isolate both review projects and their HDR caches.
include(joinpath(@__DIR__, "..", "project.jl"))
include(joinpath(@__DIR__, "rotation_review.jl"))
using FileIO
import Mantle
import OIDNRunner # register HDR denoising before entering the render loop

function prepare_telescope_flicker_review(input, directory; spp, firstframe=30, frames=60)
    project=joinpath(directory,"telescope_$(spp)spp.videoedit")
    isfile(project) && return project
    original=VE.loadproject(input)
    clip=only(filter(c->c.track==1 && get(c.source.build["args"],"beat","")=="b0_stations",original.clips))
    clip.src_in=firstframe
    clip.src_out=firstframe+frames
    clip.start=0
    clip.bake=nothing
    resize!(clip.source,(1920,1080))
    VE.setrenderconfig!(clip;raytrace=true,samples=spp,device="Mantle.defaultbackend()")
    seq=VE.Sequence([clip],original.framerate)
    seq.canvas=(1920,1080)
    @assert seq.framerate==30 && VE.seqlength(seq)==frames
    @assert any(fx->fx.kind===:oidndenoise && fx.enabled[],clip.effects)
    @assert all(!startswith(String(p.name),"args.") for fx in clip.effects if fx.kind===:scene for p in fx.params)
    VE.enabletrackcache!(seq,project*".frames")
    VE.saveproject(project,seq)
    return project
end

function telescope_flicker_review(input,directory)
    mkpath(directory)
    for spp in (256,512)
        project=prepare_telescope_flicker_review(input,directory;spp)
        output=joinpath(directory,"telescope_$(spp)spp_oidn.mp4")
        println("TELESCOPE REVIEW ",spp," spp, 1920x1080, 60 frames at 30 fps");flush(stdout)
        render_rotation_review(project,output)
        # Keep one still per sample count for visual checks as well as the videos.
        cp(joinpath(directory,"first_frame.png"),joinpath(directory,"first_frame_$(spp)spp.png");force=true)
    end
    return directory
end
