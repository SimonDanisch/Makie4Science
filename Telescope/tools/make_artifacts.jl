"""
Pack the telescope film's data into artifacts and bind them.

    julia --project=<env with Telescope> Telescope/tools/make_artifacts.jl

`telescope-fields`: the simulated steady states (`Telescope.field_names()`),
computed on the GPU into `gen/fields` when missing. Every machine renders from
these same numbers instead of simulating on its own GPU.

`telescope-narration`: the approved narration takes, one WAV per narrated part,
and the `.timing` of each beat's lines (when each line starts and ends), which
places the beat's keys. Copied into `gen/narration` from the original project.

For each, this creates the artifact in the local store, archives it to
`gen/artifacts/<name>.tar.gz` and writes `Artifacts.toml` with `lazy = true` and
the URL of this film's release, `telescope-v1`: one tag per film, since every
film in the repository publishes its data there. The binding works locally at once. Uploading the tarballs is
what makes it work anywhere else; the command is printed, not run.
"""

using Pkg.Artifacts, SHA, Telescope

const ROOT = normpath(joinpath(@__DIR__, ".."))
const GEN = joinpath(ROOT, "gen")
const REPO = "SimonDanisch/Makie4Science"
const TAG = "telescope-v1"

function stage_fields(dir)
    src = joinpath(GEN, "fields")
    if !isfile(joinpath(src, "fields.json"))
        fields = Telescope.FieldSet(name => Telescope.compute_field(name) for name in Telescope.field_names())
        Telescope.savefields(src, fields)
    end
    for f in readdir(src)
        cp(joinpath(src, f), joinpath(dir, f))
    end
end

function stage_narration(dir)
    src = joinpath(GEN, "narration")
    for f in readdir(src)
        endswith(f, ".wav") || endswith(f, ".timing") || continue
        cp(joinpath(src, f), joinpath(dir, f))
    end
end

const ARTIFACTS = ["telescope-fields" => stage_fields, "telescope-narration" => stage_narration]

function main()
    toml = joinpath(ROOT, "Artifacts.toml")
    out = mkpath(joinpath(GEN, "artifacts"))
    for (name, stage!) in ARTIFACTS
        hash = create_artifact(stage!)
        tarball = joinpath(out, name * ".tar.gz")
        sha = archive_artifact(hash, tarball)
        bind_artifact!(toml, name, hash; force = true, lazy = true,
                       download_info = [("https://github.com/$REPO/releases/download/$TAG/$name.tar.gz", sha)])
        println(rpad(name, 22), bytes2hex(hash.bytes), "  ", round(filesize(tarball) / 2^20; digits = 1), " MiB")
    end
    println("\nTo publish (needs at least one pushed commit):")
    println("  gh release create $TAG --repo $REPO --title \"Telescope film data\" --notes \"Artifacts of the Telescope film\" ",
            join((joinpath(out, n * ".tar.gz") for (n, _) in ARTIFACTS), " "))
end

main()
