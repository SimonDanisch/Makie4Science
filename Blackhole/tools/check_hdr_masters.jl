# Read-only numerical QA; no GPU, scene construction or cache mutation.
using VideoEditor

function check_hdr_master(path; dimensions=(1280,720))
    frame=VideoEditor.readrenderframe(path)
    @assert size(frame.color)==dimensions "Unexpected HDR dimensions: $path"
    for key in (:color,:albedo,:normal,:coverage,:overlay)
        values=reinterpret(Float32,vec(getproperty(frame,key)))
        @assert all(isfinite,values) "Non-finite $key: $path"
    end
    # An escaped sky ray legitimately has positive infinite depth.
    @assert all(d->d>=0 && !isnan(d),frame.depth) "Invalid depth: $path"
    @assert all(c->0<=c<=1,frame.coverage) "Invalid coverage: $path"
    @assert all(c->0<=c.alpha<=1,frame.overlay) "Invalid overlay alpha: $path"
    return nothing
end

function check_hdr_masters(directories; dimensions=(1280,720))
    files=sort!(unique!([joinpath(parent,name)
        for dir in directories for (parent,_,names) in walkdir(dir)
        for name in names if endswith(name,".vehdr")]))
    isempty(files) && error("No HDR masters found")
    for (i,path) in enumerate(files)
        check_hdr_master(path;dimensions)
        i%20==0 && GC.gc(false)
    end
    println("HDR_MASTERS_PASS count=",length(files)," dimensions=",dimensions)
    return length(files)
end

if abspath(PROGRAM_FILE)==@__FILE__
    root=normpath(joinpath(@__DIR__,"..",".."))
    @assert Base.active_project()==joinpath(root,"Project.toml") "Use the Science4Makie root environment"
    check_hdr_masters(ARGS)
end
