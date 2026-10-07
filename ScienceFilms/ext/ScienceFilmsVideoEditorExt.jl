module ScienceFilmsVideoEditorExt

using ScienceFilms, VideoEditor
import ScienceFilms as SF
import VideoEditor as VE

"""
    animate!(clip, animation; fps = clip.source.framerate) -> clip

Write an `Animation` as the clip's keyframes: each path's keys become an
ordinary, editable keyframe curve on the clip's scene effect. Key times are
seconds into the scene, placed on the nearest source frame; two keys landing
on one frame keep the later one.
"""
function SF.animate!(clip::VE.Clip, anim::SF.Animation; fps = clip.source.framerate)
    for (path, keys) in anim
        isempty(keys) && continue
        byframe = Dict{Int, Tuple{Int, Any, Symbol}}()
        for k in keys
            f = round(Int, k.t * fps)
            byframe[f] = (f, k.value, k.ease)
        end
        entries = sort!(collect(values(byframe)); by = first)
        discrete = first(keys).value isa Union{Bool, Integer}
        VE.keyframes!(clip, path, entries; discrete)
    end
    return clip
end

"""
    partclip(film, name; frames, src_in = 0, rate = 1, canvas, fps, spp, timing) -> Clip

A clip of part `name` of `film` (a beat or a shot) with its keys. The scene
recipe is the film package's `part`, loaded from the package in the environment
that opens or renders the project. Previews use RayMakie's raster mode;
finished frames are path traced with `spp` samples. A beat's keys are placed by
`timing`, by default the film's narration timing for `name`.
"""
function SF.partclip(film::SF.Film, name::AbstractString; frames::Integer, src_in::Integer = 0, rate::Real = 1,
                     canvas = (1280, 720), fps = 30, spp = 64, timing = nothing)
    part = film.parts[name]
    build = VE.packagescene(film.mod, :part; args = Dict{String, Any}("part" => name),
                            markers = [Dict{String, Any}("frame" => 0, "label" => name)])
    nsource = part isa SF.Shot ? round(Int, part.seconds * fps) : frames
    clip = VE.sceneclip(VE.buildscene(build); build, frames = nsource, canvas, framerate = fps, backend = :RayMakie)
    clip.src_in = src_in
    clip.src_out = min(nsource, src_in + ceil(Int, frames * rate))
    clip.rate = Float64(rate)
    src = clip.source
    src.screenopts = Dict{Symbol, Any}(:device => "Mantle.defaultbackend()", :rasterize => true, :samples => 1,
                                       :exposure => 0.6f0, :tonemap => :aces, :gamma => 2.2f0,
                                       :max_component_value => 10f0)
    src.bakewith = :RayMakie
    src.bakescreenopts = Dict{Symbol, Any}(:rasterize => false, :samples => spp, :max_depth => 12, :denoise => false)
    data = film.data()
    anim = part isa SF.Beat ? part.keys(data, something(timing, film.timing(name))) : part.keys(data)
    SF.animate!(clip, anim; fps)
    return clip
end

end
