# Include after project.jl and stills.jl. Uses the film's material and editor
# HDR effects, with fresh scenes and no access to the final film's caches.
using Makie, FileIO
import Mantle

function earth_review_scene(film; canvas = (1920, 1080), longitude = -80)
    sc = Makie.Scene(; size = canvas, backgroundcolor = film.SPACE, lights = film.sunlight())
    Makie.cam3d!(sc; center = false)
    earth = Makie.mesh!(sc, film.globe_mesh(256); material = film.earth_material())
    Makie.rotate!(earth, Makie.Vec3f(0, 0, 1), Float32(deg2rad(-90 - longitude)))
    film.air!(sc)
    film.look!(sc, film.Pose((0, -4.2, 1.6), (0, 0, 0.1); fov = 35))
    return sc
end

function earth_review_render(buildscene::Function, prefix; spp = 256)
    be = Mantle.defaultbackend()
    mkpath(dirname(prefix))
    raster = RayMakie.Screen(buildscene(); device = be, rasterize = true)
    try
        save(prefix * "_raster.png", Makie.colorbuffer(raster))
    finally
        close(raster)
    end
    println("Saved ", prefix, "_raster.png"); flush(stdout)

    screen = RayMakie.Screen(buildscene(); device = be, rasterize = false, samples = spp, denoise = false)
    try
        frame = RayMakie.renderbuffers(screen; samples = spp)
        dims = size(frame.color)
        build = VE.scenebuild(:bar, dims)
        clip = VE.sceneclip(VE.buildscene(build); build, frames = 1, canvas = dims)
        denoise = VE.Effect(VE.OIDNDenoiseEffect())
        VE.addslot!(clip, denoise)
        VE.addslot!(clip, VE.Effect(VE.LinearGradeEffect()))
        VE.addslot!(clip, VE.Effect(VE.ToneMapEffect()))
        work = VE.hdrwork!(clip.source, be, dims)
        for (suffix, enabled) in (("raw", false), ("oidn", true))
            denoise.enabled[] = enabled
            picture = Array(VE.hdrpicture!(work, frame, clip, 0))
            # HDR planes are x-by-y; image files are row-by-column.
            save(prefix * "_" * suffix * ".png", permutedims(picture))
            println("Saved ", prefix, "_", suffix, ".png"); flush(stdout)
        end
        close(clip.source)
    finally
        close(screen)
    end
    return nothing
end
