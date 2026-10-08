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

A film is a package in its own folder. It defines its parts: `Beat`s
(narrated, keyed by when each line is spoken), `Shot`s (animated pictures in
their own seconds) and `Montage`s (narration shown with shots, fitted to it);
its cut, the narrated parts in order; a `Film` value named `FILM`; and
`part(canvas, args) = buildpart(FILM, canvas, args)`, the scene recipe a
VideoEditor project names. Every part is a scene built once whose motion is
keys on named plots, the camera and the scene's arguments, so every motion is
an editable keyframe curve in VideoEditor:

```julia
using VideoEditor, RayMakie, Telescope, ScienceFilms
seq = filmsequence(Telescope.FILM)                            # the whole film, narration included
clip = partclip(Telescope.FILM, "b01_telescope"; frames = 900)  # one part
```

`Telescope/tools/make_project.jl` writes the whole film as a project
(`gen/telescope.videoedit`), with the approved narration saved in it, ready
to preview, edit and render on a farm. `showat!(built, keys, t)` puts a built
part where its keys have it at `t` without an editor, for stills and checks.
A film's tests build every part and check that every key names a plot, an
argument or the camera; the editor skips a key that names nothing.

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
