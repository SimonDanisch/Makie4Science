"""
Pack the telescope film's data into artifacts and bind them.

    julia --project=<env with Telescope> Telescope/tools/make_artifacts.jl [name ...]

`telescope-fields`: the simulated steady states (`Telescope.field_names()`),
computed on the GPU into `gen/fields` when missing. Every machine renders from
these same numbers instead of simulating on its own GPU.

`telescope-narration`: the approved narration takes, one WAV per narrated part,
and the `.timing` of each beat's lines (when each line starts and ends), which
places the beat's keys. Copied into `gen/narration` from the original project.

For each named artifact (all without names), this creates the artifact in the
local store and, if its contents changed, archives it to
`gen/artifacts/<name>-<tree hash>.tar.gz` and writes `Artifacts.toml` with
`lazy = true` and the URL of this film's release, `telescope-v1`: one tag per
film, since every film in the repository publishes its data there, and one
tarball per version, so earlier commits still download what they bound. The
binding works locally at once. Uploading the tarballs is what makes it work
anywhere else; the command is printed, not run.
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

function main(names = first.(ARTIFACTS))
    toml = joinpath(ROOT, "Artifacts.toml")
    out = mkpath(joinpath(GEN, "artifacts"))
    made = String[]
    for (name, stage!) in ARTIFACTS
        name in names || continue
        hash = create_artifact(stage!)
        if hash == artifact_hash(name, toml)
            println(rpad(name, 22), "unchanged")
            continue
        end
        file = name * "-" * bytes2hex(hash.bytes)[1:12] * ".tar.gz"
        tarball = joinpath(out, file)
        sha = archive_artifact(hash, tarball)
        bind_artifact!(toml, name, hash; force = true, lazy = true,
                       download_info = [("https://github.com/$REPO/releases/download/$TAG/$file", sha)])
        println(rpad(name, 22), bytes2hex(hash.bytes), "  ", round(filesize(tarball) / 2^20; digits = 1), " MiB")
        push!(made, tarball)
    end
    isempty(made) && return
    println("\nTo publish (after pushing the commit that binds them):")
    println("  gh release upload $TAG --repo $REPO ", join(made, " "))
end

main(isempty(ARGS) ? first.(ARTIFACTS) : ARGS)
