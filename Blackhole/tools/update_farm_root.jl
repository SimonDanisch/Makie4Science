# Run in a machine's Science4Makie root session. Moves the root's developed
# checkouts to the commits a farm job pins, fetched from the branch they are
# published on, so the job's environment check passes on this machine.
using TOML

"""
    update_farm_root!(pins; root = dirname(Base.active_project()))

`pins` maps a package name to `(url, branch, rev)`. Every checkout that develops
one of them is pointed at `url`, fetches `branch` into its remote ref and checks
out `rev`. The remote ref is forced: it only mirrors that branch, which may have
been published elsewhere before. A checkout with edits is refused. Prints each
checkout's new commit.
"""
function update_farm_root!(pins; root = dirname(Base.active_project()))
    manifest = TOML.parsefile(joinpath(root, "Manifest.toml"))["deps"]
    done = Set{String}()
    for (name, (url, branch, rev)) in pins
        path = normpath(joinpath(root, only(manifest[name])["path"]))
        top = readchomp(`git -C $path rev-parse --show-toplevel`)
        top in done && continue
        isempty(readchomp(`git -C $top status --porcelain --untracked-files=no`)) ||
            error("$name checkout has edits: $top")
        run(`git -C $top remote set-url origin $url`)
        run(`git -C $top fetch --quiet origin +$branch:refs/remotes/origin/$branch`)
        run(`git -C $top checkout --quiet --detach $rev`)
        push!(done, top)
        println(rpad(name, 12), readchomp(`git -C $top rev-parse --short HEAD`), "  ", top)
    end
end
