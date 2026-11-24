# Run only in the corresponding machine's Science4Makie root.
using TOML, Pkg
function provision_recording_deployment!(stage)
    root = dirname(Base.active_project())
    basename(root) == "Science4Makie" || error("Use the application root")
    backup = joinpath(root,"farm-root-backups","recording_1080p_20261024")
    mkpath(backup)
    for file in ("Project.toml", "Manifest.toml", "LocalPreferences.toml")
        src = joinpath(root,file)
        isfile(src) && !isfile(joinpath(backup,file)) && cp(src,joinpath(backup,file))
    end
    manifest = TOML.parsefile(joinpath(stage,"Manifest.toml"))
    deployment = TOML.parsefile(joinpath(stage,"deployment.toml"))["developed"]
    for (name,path) in deployment
        only(manifest["deps"][name])["path"] = relpath(joinpath(stage,path),root)
    end
    cp(joinpath(stage,"Project.toml"),joinpath(root,"Project.toml");force=true)
    open(io -> TOML.print(io,manifest),joinpath(root,"Manifest.toml"),"w")
    isfile(joinpath(stage,"LocalPreferences.toml")) &&
        cp(joinpath(stage,"LocalPreferences.toml"),joinpath(root,"LocalPreferences.toml");force=true)
    ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
    Pkg.instantiate(;allow_autoprecomp=false)
    assets = joinpath(stage,"application","assets")
    ispath(assets) || symlink(joinpath(stage,"requiredassets"),assets)
    println("RECORDING ROOT READY ",root); flush(stdout)
end
