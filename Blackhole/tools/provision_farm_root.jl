# Run ONLY in the machine's corresponding Science4Makie root environment.
# Published checkouts are separate from existing dirty dev trees; no user
# checkout is reset, stashed, overwritten or committed by this provisioner.
using Pkg, TOML

function provision_farm_root!(pins; root=dirname(Base.active_project()))
    abspath(Base.active_project())==joinpath(abspath(root),"Project.toml") ||
        error("Provision only the active Science4Makie root")
    basename(root)=="Science4Makie" || error("Not the required application root")
    mkpath(root)
    paths=Dict{String,String}()
    # A JLL is pinned by its release tag (`<Name>-v<version>`), which
    # `farmenvironment` derives from the registered version a root resolved. A
    # root keeps it registered, so it gets that exact version, not a source.
    jllcompat=Dict{String,Any}()
    checkouts=Dict{Tuple{String,String},String}()
    for (name,source) in sort!(collect(pins["sources"]);by=first)
        url,rev=source["url"],source["rev"]
        if !occursin(r"^[0-9a-f]{40}$",rev)
            tag=match(r"-v(\d+\.\d+\.\d+)(\+\d+)?$",rev)
            (endswith(name,"_jll") && tag!==nothing) || error("Expected an immutable commit for $name, got $rev")
            jllcompat[name]="="*tag.captures[1]
            continue
        end
        checkout=get!(checkouts,(url,rev)) do
            path=joinpath(root,"dev","farm-pinned",name*"-"*rev[1:10])
            if !isdir(joinpath(path,".git"))
                mkpath(path)
                run(`git -C $path init --quiet`)
                run(`git -C $path remote add origin $url`)
            end
            current=readchomp(`git -C $path rev-parse --verify --quiet HEAD` |> ignorestatus)
            if current!=rev
                isempty(readchomp(`git -C $path status --porcelain`)) || error("Published checkout has edits: $path")
                println("FETCH ",name," ",rev[1:10]);flush(stdout)
                run(`git -C $path fetch --depth=1 origin $rev:refs/remotes/origin/farm-pinned`)
                run(`git -C $path checkout --quiet --detach $rev`)
            end
            path
        end
        paths[name]=joinpath(checkout,get(source,"subdir",""))
    end
    projectpath=joinpath(root,"Project.toml")
    project=isfile(projectpath) ? TOML.parsefile(projectpath) : Dict{String,Any}()
    merge!(get!(()->Dict{String,Any}(),project,"deps"),pins["deps"])
    merge!(get!(()->Dict{String,Any}(),project,"compat"),pins["compat"],jllcompat)
    sources=get!(()->Dict{String,Any}(),project,"sources")
    for (name,path) in paths
        sources[name]=Dict("path"=>relpath(path,root))
    end
    # This is the application's sole Project.toml, never a job environment.
    open(io->TOML.print(io,project),projectpath,"w")
    prefsfile=joinpath(root,"LocalPreferences.toml")
    prefs=isfile(prefsfile) ? TOML.parsefile(prefsfile) : Dict{String,Any}()
    merge!(prefs,get(pins,"preferences",Dict()))
    isempty(prefs) || open(io->TOML.print(io,prefs),prefsfile,"w")
    ENV["JULIA_PKG_PRECOMPILE_AUTO"]="0"
    # No copies of the root's files: a failed step is fixed by running again,
    # and the fetched checkouts stay for that retry.
    Pkg.Registry.update()
    Pkg.develop([Pkg.PackageSpec(;path) for path in values(paths)])
    Pkg.instantiate()
    open(io->TOML.print(io,Dict("packages"=>paths)),joinpath(root,"farm-root-state.toml"),"w")
    println("ROOT READY ",root);flush(stdout)
    return paths
end
