# Migrate an existing edit in the Science4Makie root environment. No rendering.
include(joinpath(@__DIR__,"..","project.jl"))

function keyframe_project(input,output)
    VE.usebackend!(RayMakie)
    seq=VE.loadproject(input)
    edit=[(c.id,c.start,c.src_in,c.src_out,c.track,c.rate) for c in seq.clips]
    takes=[(n.text,copy(n.samples),n.rate) for n in seq.narration]
    # This is the native-track edition, with its own caches. The existing
    # delivery's cached frames keep their original ownership and validity.
    empty!(seq.trackcaches);seq.compositecache=nothing
    VE.enabletrackcache!(seq,output*".frames")
    keyproject!(seq)
    @assert [(c.id,c.start,c.src_in,c.src_out,c.track,c.rate) for c in seq.clips]==edit
    @assert [(n.text,n.samples,n.rate) for n in seq.narration]==takes
    @assert all(!startswith(String(p.name),"args.") for c in seq.clips for fx in c.effects if fx.kind===:scene for p in fx.params)
    VE.saveproject(output,seq)
    reopened=VE.loadproject(output)
    @assert VE.seqlength(reopened)==VE.seqlength(seq)
    count=sum(length(p.curve[].keys)>1 for c in reopened.clips for fx in c.effects if fx.kind===:scene for p in fx.params)
    println("Saved ",output,"; ",length(reopened.clips)," clips; ",count," animated native properties; ",VE.seqlength(reopened)," frames")
    return reopened
end

length(ARGS)==2 && keyframe_project(ARGS...)
