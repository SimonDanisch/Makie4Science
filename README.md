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
keys on named plots, the camera and the scene's arguments (stored on the
native plot properties that consume them), so every motion is an editable
keyframe curve in VideoEditor:

```julia
using VideoEditor, RayMakie, Telescope, ScienceFilms
seq = filmsequence(Telescope.FILM)                               # the whole film, narration included
clips = partclips(Telescope.FILM, "b01_telescope"; frames = 900)  # one part
```

`Telescope/tools/make_project.jl` writes the whole film as a project
(`gen/telescope.videoedit`), with the approved narration saved in it, ready
to preview, edit and render on a farm.

## Rendering

A part with a 3D view is two clips: its picture, path traced, and its labels
(text and everything drawn in its overlay), rasterized over it on a clear
background. Each is keyed with what it draws, so with the editor's frame
caches, frames that differ only in their labels are one traced picture. A flat
part is one rasterized clip. `Telescope/tools/render_farm.jl` renders the film
on the LAN farm and encodes it.
Scenes are laid out at 1280×720 and drawn at 1920×1080 (`px_per_unit` 1.5).
A picture is traced into linear HDR and finished by the editor's effects:
OIDN, an exposure grade (`log2(0.6)` stops) and ACES display mapping.

256 samples and up to 24 bounces. Against a 2048 spp reference (depth 64, no
roulette, regularisation or clamp) the denoised frames at 64/256/1024 spp
differ by 0.2–0.6 / 0.2–0.4 / 0.1–0.3 mean levels, the camera-lens cutaway
hardest (`Telescope/tools/glass_study.jl` renders such comparisons). Glass is
spectral, its index from each glass's Cauchy fit; coated faces reflect a
residual tint (MgF₂ purple-blue, the camera's multicoat green), cut faces are
bare, edges have ground bevels and black painted rims, and the studio's two
strip lights draw highlights along curved glass. `showat!(built, keys, t)` puts a built
part where its keys have it at `t` without an editor, for stills and checks.
A film's tests build every part and check that every key names a plot, an
argument or the camera; the editor skips a key that names nothing.
`Telescope/tools/check_takes.jl` checks with Whisper that every approved take
says its part's current lines.

## Data

The Telescope render cache retains graded picture PNGs and transparent label
PNGs separately. `Telescope/tools/render_farm.jl` uses VideoEditor's `hdr=false`
option to omit the large HDR/auxiliary buffers, adopts the returned track layers
into the saved project and exports through the normal compositor. Label edits
and translations reuse the pictures without ray tracing. Create language
versions by editing and saving the existing project, preserving picture clip
IDs and source clocks, rather than calling `filmsequence` again. Save As shares
the immutable cached picture files where the filesystem supports hard links.

The historical Telescope jobs made with `planes=false` contain only finished
composites. They cannot provide clean picture layers for translated labels;
those missing layers have to be rendered once with the corrected retention.

Simulations and recordings are Pkg artifacts, never files in the repository.
A film's `tools/make_artifacts.jl` computes them into its `gen/` folder (not
tracked), packs them and binds them in the film's `Artifacts.toml`, lazily, to
a release of this repository with one tag per film (`telescope-v1`). The code
reads them with `artifact"..."`, which downloads them on first use. Each
version of an artifact is its own tarball, named by its tree hash, so earlier
commits keep downloading what they bound.

## Development

```julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

develops every package from its folder.
