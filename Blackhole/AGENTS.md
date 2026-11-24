# Existing implementations first

## Mandatory single Julia environment

ALL Julia and Pkg execution for this project uses
`/home/sim/Programmieren/Science4Makie` as `env_path` / active project.
This is a hard requirement, including tests, data preparation, examples and
dependency installation. Never activate or instantiate a sibling project's,
package's, test's or temporary environment. Existing packages found under `../`
must be integrated into this one environment; a dependency conflict is not
permission to use another environment. Reading sibling source is allowed.

Farm clients must use `tools/farm_client.jl`, started with Julia's
`--project=/path/to/Science4Makie` for that machine. This launcher explicitly
sets the client's application project; the generic client's per-job environment
mode is not allowed here. An optional third argument reuses an existing cache.

## Reuse before implementation

Before implementing a feature, read the relevant saved project notes, inspect
the project, then search sibling projects under `/home/sim/Programmieren`.
When the user names an implementation, use it as the starting point; do not
silently replace it with a new architecture. Only after that search, identify
any concrete gap and extend the existing implementation where appropriate.
Do not build a renderer unless the user explicitly asks for a new renderer.

The black-hole scenes must use the setup from `RayDemo/BlackHole`: a Hikari
medium rendered by RayMakie/VolPath. Sampling, linear HDR, OIDN, grading and
display transforms must use the ordinary VideoEditor pipeline. No kernel that
renders a separate image and embeds it in the scene; no private tonemapper.

Keep animation driven by Observables in an existing scene. Render requested
sample frames into the final project's native cache so exports can reuse them.
A request for samples or an estimate does not authorize a full-film render.
