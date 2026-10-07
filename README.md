# Makie4Science

Science explainer films made of ordinary Makie scenes, edited and rendered with
VideoEditor and RayMakie. Every film lives here, next to the packages the
films share.

## Layout

| Folder | What it is |
|---|---|
| `ScienceFilms/` | The film toolkit: colour language, materials, framing and studio, keys placed by narration timing, callouts and captions, and the `Film` that VideoEditor assembles into clips. No physics. |
| `WaveOptics/` | Light and lenses: optical systems, a GPU scalar wave solver, ray tracing, analytic fields, 3D instrument models and the glowing cutaways that show them. |
| `Telescope/` | The film "What makes a picture sharp?": its data, its scenes and keys, and the tool that builds its artifacts. |
| `tools/` | Helpers for porting films from other projects. |

A package that a second film could use belongs in its own folder at the top.
Everything only one film needs stays in that film's folder.

## A film

A film is a package in its own folder. It defines its parts, each a `Beat`
(narrated, keyed by when each line is spoken) or a `Shot`, a `Film` value named
`FILM`, and `part(canvas, args) = buildpart(FILM, canvas, args)`, the scene
recipe a VideoEditor project names:

```julia
using VideoEditor, Telescope, ScienceFilms
clip = partclip(Telescope.FILM, "b01_telescope"; frames = 900)
```

## Data

Simulations and recordings are Pkg artifacts, never files in the repository.
A film's `tools/make_artifacts.jl` computes them into its `gen/` folder (not
tracked), packs them and binds them in the film's `Artifacts.toml`, lazily, to
a release of this repository with one tag per film (`telescope-v1`). The code
reads them with `artifact"..."`, which downloads them on first use.

## Development

```julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

develops every package from its folder.
