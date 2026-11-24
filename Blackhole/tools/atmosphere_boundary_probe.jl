# Diagnostic scene variant, rendered by the ordinary RayMakie/VideoEditor path.
# No alternate renderer, tonemapper, or Julia environment.
module BoundaryProbeFilm
    include(joinpath(@__DIR__,"..","film","film.jl"))
end
function buildscene(canvas,args)
    built=BoundaryProbeFilm.buildscene(canvas,args)
    function darkspace!(scene)
        BoundaryProbeFilm.Makie.set_ambient_light!(scene,BoundaryProbeFilm.RGBf(0,0,0))
        foreach(darkspace!,scene.children)
    end
    darkspace!(built.scene)
    return built
end
