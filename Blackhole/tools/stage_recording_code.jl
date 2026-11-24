# Export the existing root's developed packages, not another Pkg environment.
using TOML
root=dirname(Base.active_project())
stage=joinpath(root,"BlackholeImage","renders","deploy_1080p_20261023")
mkpath(stage)
m=TOML.parsefile(joinpath(root,"Manifest.toml"))
paths=Dict{String,String}()
for (name,entries) in m["deps"]
    entry=only(entries)
    haskey(entry,"path") || continue
    source=abspath(root,entry["path"])
    target=joinpath(stage,"packages",name)
    mkpath(target)
    run(`rsync -a --exclude=.git --exclude=.bonitoAgents --exclude=test --exclude=tests --exclude=docs --exclude=examples --exclude=benchmark --exclude=benchmarks --exclude=renders --exclude=results --exclude=videos $source/ $target/`)
    paths[name]=joinpath("packages",name)
end
for name in ("Project.toml","Manifest.toml","LocalPreferences.toml")
    isfile(joinpath(root,name)) && cp(joinpath(root,name),joinpath(stage,name);force=true)
end
open(io->TOML.print(io,Dict("developed"=>paths)),joinpath(stage,"deployment.toml"),"w")
app=joinpath(stage,"application")
mkpath(app)
run(`rsync -a --exclude=.git --exclude=.bonitoAgents --exclude=renders --exclude=assets '--exclude=voice*' --exclude=Manifest.toml --exclude=Project.toml $(joinpath(root,"BlackholeImage"))/ $app/`)
cp(joinpath(root,"BlackholeImage","renders","recording_1080p_20261023","film_1080p.videoedit"),joinpath(app,"recording.videoedit");force=true)
println(stage)
