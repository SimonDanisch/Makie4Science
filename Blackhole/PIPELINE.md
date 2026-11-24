# Layered film workflow

All 20 beats animate native Makie property tracks saved in the `.videoedit`
project: plot attributes, transforms, camera properties and lights. Scene
builders return only the scene. There is no film `args.*` animation interface,
time cue, frame updater or `static` opt-in. The initial tracks are generated
from narration timing; playback and farm workers evaluate the saved tracks.
The GRMHD file-series node targets `plasma_volume.snapshot` on the actual medium
boundary plot. Picture tracks omit changes used only by the annotation layer.

The migrated full edit is `renders/keyframed_20261023/film.videoedit`: 40 clips,
248 animated native properties and 18,587 frames. Timing, clip/source identities,
render settings and recorded narration are preserved. Its caches belong to this
edition. `tools/keyframe_project.jl INPUT OUTPUT` migrates other saved edits;
older project files need that migration before using the updated scene builders.

## Narration

The VideoEditor project owns its narration text and approved rendered takes.
Use VideoEditor's narration controls and speech provider for future voice
rendering. Keep existing approved takes and timing when migrating an edit;
neither the property-track migration nor farm export should synthesize them again.

`read_voice` and `read_timing` in `project.jl` import the existing WAV/timing
files when building or refreshing an edit. The removed top-level `voice.jl`
and `voice_de.jl` scripts are not required for normal editor narration.
`tools/voice_en_v6.jl` remains as a historical regeneration/import utility for
that edition, rather than the normal voice-rendering workflow.

The English v6 project has two Makie scene tracks: **pictures** (track 1) and
**transparent labels/annotations** (track 2). Every scene defaults to RayMakie
raster rendering. `setrenderconfig!` explicitly enables tracing on the selected
picture clips. Label clips stay raster, with glyph antialiasing and FXAA off.

Each track owns an immutable linear-HDR source cache and a disposable cache of RGBA planes, keyed by stable clip id and absolute
source frame. The final RGB composite is cached separately. Mutation APIs record
dirty frames immediately; no render-history, timestamp or document-diff comparison
decides whether a track frame is valid. PNGs and dirty-frame metadata survive
saving/reopening the project. Cached frames go into `<project>.frames/`.

Raytraced source masters are lossless Float32 `.vehdr` files containing linear
sRGB radiance, albedo, world-space normals, depth, coverage, and a separate
display-referred raster overlay. Highlights above 1 and negative values are
preserved. RayMakie's renderer-side denoising is disabled for these captures.
Raster-only scenes are display-referred, not falsely labelled HDR.

The current master format is uncompressed: about 55 MB per 1280×720 frame
including all six planes. Reserve substantial disk space before the full
baseline render. Lossless compression/EXR interoperability is not implemented
yet; do not confuse small preview PNGs with the storage cost of the HDR master.

The clip's **OIDN HDR denoise**, **Linear HDR grade** and **HDR display
transform** are non-destructive VideoEditor effects. The float operations run
before the SDR GPU effects and composition. The source master never changes.
Effect mutations dirty only derived planes/composites; explicit scene mutations
also dirty the source master. Native OIDN runs before grading, using the official
v2.5.1 high-quality large models and albedo/normal prefiltering. The older spatial
reference effect remains available as a fallback.

Hikari extracts material/texture albedo and unit world-space shading normals.
Those guides skip null boundaries and alpha below 0.5. Diffuse/base reflectance
and bounded material mixtures are evaluated; specular/unknown materials use
the conventional white guide. Depth retains its nearest-geometry meaning for
overlay/volume coverage. Guides are deterministic centre rays, not
sample-averaged antialiased buffers.

Obsolete guides remain flagged invalid and OIDN refuses them. Upgrade with
`VE.refreshguides!(clip,sourceframe)`: it traces primary rays only and preserves
the stored radiance and coverage. No beauty-path samples are added.

Loading `OIDNRunner` activates the editor extension. Its model artifact must
be installed on each worker. The models are hosted on JuliaVision's existing
`assets-v1` release and verified by the artifact hashes; workers do not need a
private local artifact copy. Full-film temporal quality remains a separate
check from validating individual GPU frames.

For example, `VE.seteffect!(clip, VE.LinearGradeEffect(exposure=-2))` or
`VE.seteffect!(clip, VE.ToneMapEffect(mode=1))` updates the derived output only.
HDR operations must precede the display-transform operation. Existing
`ColorEffect` remains a display-referred SDR grade.

## Build and review

All Julia/Pkg operations, tests and data preparation MUST use the single
Science4Makie root environment, including when loading sibling packages.
There is no film, test, temporary, or VolumePlots execution environment.

### Black-hole scenes

`film/spacetime.jl` adapts `RayDemo/BlackHole`'s Hikari medium. RayMakie/VolPath
owns ray generation, intersections, sampling and reconstruction; VideoEditor
owns HDR/OIDN/grading, overlays and caches. The independent `relativity.jl`
image renderer was removed, not retained as a preview/final shortcut.

`film/grmhd.jl` loads the Illinois v3 MAD spin-zero snapshot (288×128×128).
The unmodified upstream `GRMHDSnapshots` package supplies snapshot reading,
coordinates and fluid quantities. Hikari owns the synchrotron model and its
optional `HikariGRMHDSnapshotsExt` prepares the radiative volume. VideoEditor's
generic file node names Hikari's loader and explicitly requires GRMHDSnapshots
to activate that extension, including on farm workers. No snapshot fork is needed.
Emission, absorption and fluid velocity are sampled into reusable
Float32 volume fields once per scene, not regenerated as images per frame.
Snapshot coordinates are in r_g; film coordinates use r_s=2r_g.

The present approximation is a frozen/fast-light, non-spinning model with
nonthermal power-law electrons, scalar-|B| synchrotron coefficients and
unpolarized transfer. Orange represents 230-GHz radio intensity in false
colour; display exposure is not an M87 flux fit. See `assets/grmhd/README.md`
for provenance, license and physical normalization. Do not describe it as
Kerr transport, a visible-light plasma spectrum, or a live GRMHD simulation.

Hikari traces bounded curved chords using staggered half-kicks around the
ordinary geometry query. Null collisions sample emission along that chord;
they do not each create another bend/intersection round. Surface shading and
environment lookup use the recovered physical endpoint direction. All
requested samples per pixel still apply to these scenes.

`tools/sample_blackholes.jl` renders selected finished frames into the final
project's native caches, declaring recipe changes via editor mutation APIs.
It does not export a full movie. `tools/test_spacetime.jl` checks physical
coefficients and capture/escape at the production adaptive step; Hikari's
`test_curved_transport.jl` checks null-event/vacuum continuations and ordinary
GPU media. The ~60-second RTX 4000 Ada frame budget still requires measurement
on that machine; Bosgame timings are not a substitute for it.

### Black-hole image diagnostics (2026-10-21)

`tools/check_blackhole_convergence.jl` compares the existing 54-second source
master with diagnostic variants of the SAME a1 scene. It uses RayMakie capture
and VideoEditor's ordinary HDR effects; it never edits the final project/cache.
Run `check_blackhole_convergence(project)` and then
`blackhole_convergence_report(project)` in the single root Julia environment.
The `.vehdr`, raw/OIDN PNGs and JSON measurements live under the final render's
`diagnostics/` directory. These are controlled diagnostic variants, not a
replacement final-film sample cache. Production scene defaults remain unchanged.

Results at 720p/256 spp: increasing the transport budget from 512 to 1024 was
bit-identical in linear HDR. Halving the integration step left the radial rim
peak at 126 pixels and changed its height by about 0.36%. At the same smaller
step, doubling the plasma grid from 192³ to 384³ changed near-horizon structure
visibly and reduced the radial rim peak by about 14%, with exposure normalization
held fixed. The ragged inner boundary exists before OIDN, but its coarse detail
was affected by volume resolution. The 192³ image is NOT resolution-converged;
one finer grid does not establish convergence of the 384³ image either.

The diagnostic `step_scale` multiplies the existing medium's adaptive step; it
does not change its curvature law or introduce another integrator. An additional
volume metadata field records the emissivity normalization so different grids
can be compared at the same physical scale. The film's focused checks now pass
21/21. No independent GRRT photometry validation or Ada timing is implied.

Run in the Science4Makie environment (its `Project.toml`, with the `dev/`
checkouts of every package):

```julia
include("tools/voice_en_v6.jl")
voice_en_v6() # generates only the revised opener and telescope question
include("project.jl")
p = buildproject("film_v6_en.videoedit"; voice_root="voice_v6")
```

The new narration is spoken at its natural pace. Its measured duration sets the
new shot length; existing English takes are reused. The opening starts directly
with a visible ring and a question. It labels the image as an illustration rather
than claiming it is the original observation. The telescope beat introduces its
own question instead of referring viewers to a previous video.

## Edit cheaply

```julia
# Replace label text without invalidating the picture track.
editlabels!(p.sequence, "b0_stations",
    Dict("ALMA: 5000 metres up, in Chile's Atacama desert" =>
         "ALMA · Chile · altitude 5000 m"))

# Declare a genuinely frame-local scene mutation.
VE.mutateframe!(p.sequence, 2, 42) do
    # mutate the label scene's frame-42 data here
end

# Change one discrete parameter frame; hold/linear curves only.
VE.setframevalue!(parameter, 42, new_value)

# Continue the shot for another two seconds. The existing animation starts,
# ends and camera keys stay fixed, so its existing frames remain valid.
extendbeat!(p.sequence, "b0_stations", 2)

VE.saveproject(p.path, p.sequence)
VE.exportvideo("renders/blackhole_v6_en.mp4", p.sequence;
    backend=Mantle.defaultbackend())
VE.saveproject(p.path, p.sequence) # persists newly populated frame indices
```

`editlabels!` accepts `frames=first:last` in **source frames** if the edit only
affects that span. Its default dirties the label clip's full span. A text change
visible throughout a shot cannot correctly invalidate only one frame. Ordinary
interpolated key edits invalidate the adjacent segments; a single-frame override
uses guard keys to preserve the other discrete frames. Bézier overrides are
refused rather than silently altering the rest of the curve.

Moving a clip keeps its source-frame planes and dirties its old/new composition
spans. Extending the out-point dirties only added composite frames; missing track
frames render on demand. An edit arriving during a render advances the frame's
mutation revision, so the in-flight result cannot mark that frame clean.

Changing a script, asset, renderer setting, or procedural input must be reported
through the corresponding mutation API (`setsceneargs!`, `setrenderconfig!`, or
`invalidateclip!`). Raw filesystem writes and direct mutation of nested arrays
do not emit editor events. No hidden file-history comparison substitutes for that
declaration. Spatial effects, interpolated keys and dependent parameter inputs
can affect more than one frame and must invalidate their full affected span.

## Farm rendering

`farm.jl`'s `renderfilm!` renders on every GPU a farm client offers. Each machine,
this one included, uses `tools/farm_client.jl` with its Science4Makie root
`--project`, a GPU selector and the coordinator's address. Do not use the generic
client's per-job package environment here. A job
pins its code as the Project.toml of the dev packages at their commits, so they
must be committed and pushed first. Workers render into caches of their own and
return each frame's track planes and traced HDR sources; the coordinator keeps
them in `trackframes/` with checksummed receipts, and `renderfilm!` adopts them
into the project before it is edited again:

```julia
VE.adoptfarmcache!(p.sequence, job)
VE.saveproject(p.path, p.sequence)
```

Adoption checks recorded mutation revisions and does not overwrite a frame
changed since the job was created. Nothing a worker writes lands in the job's
snapshot, so the job keeps its key and resumes.

For an already-created job, resume the immutable `VE.RenderJob(directory)`;
do not recreate its snapshot from the subsequently saved/adopted project.
Pass `reuse=seq` to `VE.renderfarm!`: native composite, track and HDR caches
skip work even across different farm snapshots. Returned planes are adopted
atomically, and repeat adoption of the same hard-linked master is idempotent.
Newer label-only edits retain their cached traced picture and are composed by
the ordinary `VE.exportvideo` path; do not manually splice movie sections or
encode the farm's older burned-in label composites as the final edit.

### HD delivery project

Current 1080p recording (2026-10-23):
`renders/recording_1080p_20261023/film_1080p.videoedit`, from the native-keyframed
edition, preserves all 18,587 frames, narration and credits. Source dimensions
are 1920×1080, with `px_per_unit=1.5` retaining the original 1280×720 logical
layout and rendering text natively. Surface shots use 256 spp + OIDN; a1/a2 use
8 spp + OIDN with the emission march and unchanged physical transport settings.
`tools/record_1080p.jl` records through ordinary VE composition and export,
checkpoints finished native frames, and retains only the newest intermediate
HDR master per clip to bound disk use. Earlier delivery/study caches are not
modified. The output is `black_hole_1080p.mp4` beside that project; progress is
in `recording.log`. The first pass ran locally on Bosgame; Desktop was excluded
at that stage and was subsequently authorized on 24 October.
The initial local loop has been handed off to native `VE.renderfarm!` via
`tools/recording_farm.jl`, with existing `remote_session` RPC transports.
The active job is `renders/farm/recording_1080p_native_20261023`; its
`status.json` is authoritative for worker counts/errors. Bosgame, Laptop and
MacBook accept all frames; Legion is restricted to non-black-hole shots because
the 1080p/384³ black-hole scene exceeds its 8 GB GPU budget. Mac passed actual
1080p telescope and black-hole frames on Metal before joining. All roots use the
same deployed package sources and manifest versions (their former root files
are retained under `farm-root-backups/recording_1080p_20261023`). No alternate
Julia environment is used. The farm streams finished planes
back and retains HDR masters for held-picture groups; ordinary VE export fills
the held frames and muxes the approved narration. Farm progress/encoding is in
`farm_coordinator.log` beside the delivery project. The MP4 is complete only
after that log reports `DONE` and the file is verified.

### Remote-eval handoff, 24 October

### Corrections and cached black-hole edit, 24 October

### Opening buildup revision, 25 October

The user likes revision2 but rejected its abrupt opening gas cut. They requested
dark silhouette → gradual gas appearance (bending OFF) → gradual bending ON,
and authorized new frames if needed. The former edit explicitly skipped source
271–344; the original fade also mixed gas-up with bending-down. Do not restore
that overlapping transition or merely crossfade finished pictures.

tools/buildup_opening.jl extends the existing native scene/edit implementation.
New project: renders/buildup_1080p_20261025/film_1080p.videoedit; prior delivered
movie is untouched. Three newly cached voice takes match the staged order.
Stages are 247 bare frames, 198 gas-reveal frames, 246 unchanged horizon frames,
207 new bending frames; the unchanged later footage starts at new frame 898
(old revision2 frame 760). New tracing: exactly 652 pictures. The complete
rest of the movie and its cached composites/narration are hardlink-reused.
4890 tests pass after rendering, including monotone independent ramps, full gas before any
bending, bounded camera steps, exact unchanged-cache reuse and unchanged takes.

First gate: eight final-quality samples on the Desktop's two GPUs, native
batched-LAN farm, s4m-buildup-samples-20261025.service. Job directory
renders/farm/buildup_1080p_20261025. export_movie=false prevents a full export;
frames is an explicit bounded native renderfarm! selection. First inspect
these, then build a bounded moving opening review. No full-film replacement
has been requested/started for this revision. Bosgame remains excluded; its
GPU could not initialize today, so voice synthesis used llvmpipe and new
picture tracing is remote. All Julia processes use their Science4Makie roots.

Completed: eight sample pictures were visually inspected, then all remaining
644 new pictures finished successfully on Desktop Ada/Radeon, Laptop and Mac;
the preview service exited with Result=success and ExecMainStatus=0. Native
cache adoption completed without a full-film export. The 1081-frame (36.03 s)
1080p/30 AAC preview is review/buildup_opening.mp4 under the new project.
Full decode passed; six extracted encoded frames were visually inspected
(bare, partial/full gas, horizon, partial/full bending). Adjacent-frame checks
at joins 445/691/898 showed no large discontinuity (mean 8-bit changes under
2.1). Encoded narration correlations against saved takes are .9967/.9958/.9953.
The bounded exporter reuses valid full-film composites before recompositing.
All 4890 assertions pass again after preview adoption. Prior delivery remains
untouched; await preview acceptance before replacing the complete movie.
Preview share: https://agent.bonito.sh/s/e7e8f292e3dcbe6268b91129bec5fe65/

#### Context-first narration revision, 25 October

The 16k celestial star-map asset is downloaded separately from
[NASA SVS Deep Star Maps 2020](https://svs.gsfc.nasa.gov/4851/): choose
`starmap_2020_16k.exr` and save it as `assets/starmap_2020_16k.exr`.
It is excluded from Git along with generated voice takes and render caches;
the native generation scripts and voice-cache signatures remain in source.

User approved defining a black hole before its consequences, and explaining
where the gas/plasma comes from instead of saying "now add". BUILDUP_LINES in
tools/buildup_opening.jl now contains the accepted definition and gas context.
New voice takes are buildup_explained_20261025_1/2, 9.5291/10.1956 seconds,
af_heart speed .92. explain_buildup! reuses the already traced staged opening:
319 definition frames, 339 gas frames, then all prior footage/audio unchanged.
No source frame repeats more than twice; no long frozen holds or generated
intermediates. Lead .25 s, trailing breathing room >=.85 s per replacement.
New project: renders/buildup_explained_1080p_20261025/film_1080p.videoedit.
It has 19,747 frames, 658.2333 s. Earlier deliveries/projects remain intact.

The 1294-frame opening review passed complete 1080p30/AAC decode. Seven encoded
frames were visually inspected: definition, emerging gas, plasma, straight
light, horizon, partial bending, far-side lensing. Encoded audio matches all
five opening takes at saved cue times (correlations .9953–.9966). Join checks
319/658/904/1111 show no large image jump (mean 8-bit change <=2.4).
17,276 assertions pass before save, after reload, and before full export:
exact native picture/label states and caches, independent gas/bending stages,
new audio samples and breathing room, byte-identical unchanged narration,
unchanged other scenes, all later clip starts rippled correctly, no farm work.

A final check caught preview placement setters invalidating the fullcache
before seeding: detach the preview compositecache BEFORE setting c.start.
Fixed in export_regression_excerpt!. All 1294 unnecessarily recomposited
PNGs were compared pixel-for-pixel to their originals, passed, and relinked
through native linkplane!; tests passed again. No raytracing was repeated.
export_continuous_film! now accepts adopt_section=false when the full native
composite cache is already complete, plus the ordinary export backend option.
Full export r36 started from all 19,747 valid composites, using the supported
host backend to avoid llvmpipe round trips. CRF18/medium unchanged. Await its
full decode and audio checks before sharing the complete movie.

Completed: r36 passed full decode at 19,747 frames, 1920x1080/30, AAC,
658.2333 seconds. All 19 narration cue spot-checks match the native audio mixer
at their rippled full-film positions (minimum correlation .9954); the 17,276
edit/cache assertions pass after export. Full movie share:
https://agent.bonito.sh/s/c3840b3038ab0161a2131bb9ade19bbe/

Publication audit, 25 October: 661 targeted checks pass in the root project:
93 staged Julia syntax checks, 449 emission-integral checks, 15 rendered-plan
invalidation/reuse checks, 18 bounded/streaming farm checks, 34 native-cache
reuse checks, 39 native property/save checks, 13 recording-LAN checks.
The LAN fixture requires Main.renderer, so it was rerun successfully in its
documented fresh root-project process after an unsuitable module-wrapped run.
These are targeted checks, not a claim that entire package suites ran.
Hikari 8980695 and VideoEditor 50ede39 were committed and pushed on their
existing sd/film-native-grmhd and sd/scene-overlay-wip branches respectively.
RayMakie/Makie, Mantle, Raycore and JuliaVision had no local source changes or
unpushed commits; their live remote branches already contain the local heads.

#### Open regression checklist after user review, 24 October

#### Cadence audit after full-film review, 25 October — correction pending

The user noticed stutter and the unintroduced term "light bending". The current
delivered movie really is encoded at 30 fps, but repeated cached motion states
reduce the a1 stages to 23.23, 17.52, 16.34, 30.00, 25.25, 25.45, 22.22,
21.59 and 25.46 distinct picture states/second respectively. A decoded-video
audit confirms near-identical adjacent frames, notably ~41% in the gas/horizon
stages. Inode checks alone MISSED earlier repetitions because some composites
were separately written from the same picture state. Count native states and
check encoded motion, not just file fps or composite inode identity. A maximum
repeat run of two is not a sufficient smoothness criterion.

Earth-turning and satellite picture parameters change every frame; this audit
does not prove perfect playback or eliminate all other causes of stutter.
Do not equate intentionally static diagrams with a failed motion cadence.
BUILDUP_LINES[1] now introduces gravity bending light before explaining escape
and the straight-light illustration. This script change is NOT yet synthesized
or applied to a new delivered movie. Proper smooth slowdown needs newly traced
intermediate scene states through the existing renderer, preserving unchanged
caches; do not stretch the cached first two stages yet again or synthesize
optical-flow images of scientific footage. No new farm job/export started.

#### True 30 fps re-time, 25 October evening

User-approved lines in BUILDUP_LINES (no "so ... so"; gas line without the
repeated "without light bending"; horizon line no longer repeats "even light
cannot escape"). Takes voice_revision2_20261024/buildup_smooth_20261025_1..3,
13.83/7.09/5.17 s. `smooth_buildup!` (tools/buildup_opening.jl) collapses the
saved a1 edit to its 1846 distinct rendered states and advances through them
at a Hermite-eased per-segment rate (speed continuous across segments; segment
4, already one state per frame, is kept as is). In-between frames interpolate
the keyed parameters: camera along its orbit (radius/azimuth/elevation),
plasma clock, gas, bending, Doppler. Labels re-cued per segment. Only frames
landing exactly on a rendered state reuse its plane (216); 2222 new pictures,
all a1. Project renders/smooth_1080p_20261025/film_1080p.videoedit (19,738
frames, 657.93 s), cloned with hard-linked caches; `test_smooth_buildup`
passes 5307 checks before and after reload. Prior deliveries untouched.

USER ORDER: nothing renders on the Desktop any more (farm_policy.jl excludes
it). Bosgame stays excluded. The user wants legion-boi in the pool: the old
"8 GB too small for 1080p black holes" note was never measured, and Legion's
RTX 3070 Laptop does commit 1080p a1 frames (first: 1639/1640, inspected).
run_recording_rpc.jl used to bar Legion from a1/a2 unconditionally; bootstrap
`legion_blackhole=true` now lifts that. Pool = Laptop + MacBook + legion-boi.
Deployed project: recording-corrections-20261024/application/recording.videoedit
on all three, sha256 cb92bed3995e…; film code, Hikari/RayMakie/Raycore/Mantle/Lava/
OIDN/GRMHD/Makie sources hash-identical to Bosgame; their VideoEditor differs
only in coordinator-side farmnet/renderfarm batching. Job
renders/farm/smooth_1080p_20261025. Sample gate (8 frames) passed: mean 8-bit
change across reused↔new joins 3.62/1.72/1.65 vs new↔new 3.73/1.80, i.e. no
pops; gas-reveal and horizon samples inspected. Full render service
s4m-smooth-render-20261025 (export_movie=false), log beside the project, sleep
inhibitors on all three tied to the LAN worker pids (current service: s4m-smooth-render-20261025c after two pause/resume restarts, no frames lost). After it finishes:
export_regression_excerpt! for a1, check encoded cadence, then
export_continuous_film!(adopt_section=false) and full decode/audio checks.

COMPLETED 25 October ~22:00. Farm: 2222/2222 new pictures, zero errors/incidents
(final run c: Laptop 565, legion-boi 569, MacBook 176; earlier runs Laptop/Mac).
Warm costs: unlensed ~3-5 s (Laptop), lensed ~11 s Laptop/Legion, ~35 s Mac.
CAUTION: an earlier test version called regression_label_paths (it invalidates
the label clip) before the first save, so a1 labels/composites were saved stale;
the export redrew them (raster only). The test now reads label paths from keys.
Section review review/smooth_black_hole.mp4: 2438 frames verified; decoded
cadence 30.0 distinct pictures/s in all nine segments (old edit measured the
same way: 23.2/17.6/16.9/30/26.2/25.4/22.9/22.3/25.7); minimum adjacent change
0.56 levels (old 0.0); largest local change spike 1.41x (old 3.26x), joins
<=1.26x. Encoded narration .9951-.9973 per segment. Full film
black_hole_1080p.mp4: 19,738 frames, 657.93 s, 1080p30 AAC, complete decode;
all 19 takes correlate >=.9962 at their positions. Share (hard link
Science4Makie/black-hole-smooth-20261025.mp4):
https://agent.bonito.sh/s/49fb4d5553ee5782e3613f4e6a6756a7/

PRODUCTION COMPLETE, 24 October 21:28: the user-authorized revision2 recording
finished successfully. Farm: 985/985 committed, 18,411 timeline frames reused,
zero errors/incidents; no BH picture rerender, no Bosgame farm worker. Native
source caches have zero remaining expensive frames. The coordinator and its
independent verifier both exited successfully (status 0).

Final film: renders/revision2_1080p_20261024/black_hole_1080p.mp4,
131,933,074 bytes, 646.533333 seconds, 19,396 frames, 1920x1080, 30 fps,
AAC narration. Complete decode passed; receipt is the adjacent
black_hole_1080p.mp4.validation.txt. Final-MP4 gas/ring/wave/satellite cue
frames were extracted and visually inspected in review/final_*.png. The
final stripe and closure audio match the saved corrected takes with waveform
correlations 0.9976 and 0.9958, respectively. Prior deliveries remain intact.
Share: https://agent.bonito.sh/s/ec2eb8b60f0fef12b8380645fa3fc46d/

USER APPROVAL, 24 October: after delivery of the four reviewed revision2
clips and test results, the user said "so let's record?". Production recording
of this revision is now authorized. Use the existing native batched-LAN farm,
five approved remote slots only, Legion raster-only, no Bosgame worker. The
985 missing expensive frames are b5 (440) and c2 (545); BH frames remain cached.
Production service: s4m-revision2-1080p-20261024b (headless
JULIA_GLFW_PLATFORM=null); service log farm_service_b.log beside the project.
The first service attempt lacked an X display and failed BEFORE dispatch;
the supported GLFW null platform resolves startup without a desktop session.
All five approved slots completed authenticated LAN handshakes. Queue status:
985 pending expensive frames, 18,411 reused, batch size 16, no initial errors.
Four traced-capable slots are active; Legion has no eligible raster work.
Job directory:
renders/farm/revision2_1080p_20261024. Service startup alone is not completion.

Previous USER GATE: Do not start another full render, export, or farm run until the
revision has passed content/regression review. The user explicitly rejected
starting a new run while regressions remain. No new farm/full export has been
started for revision2. Restrict further work to diagnosis, code/metadata fixes,
tests and bounded review material; obtain approval of reviewed clips before
the next production run. Do not claim an absolute guarantee from decode or
midpoint-frame tests.

Earlier review checkpoint: revision2 was UNAPPROVED pending encoded-clip review. The b4
native-binding bug is fixed by owning shared controls on the existing schematic
backdrop rather than a TextLabel whose derived alpha changes in the same
native transaction. New rendered receivers/wavefronts/recordings/extra-path
cue frames were inspected: Arizona/strength labels no longer leak. The
native-update regression test passes (10 checks). The common.jl conditional
binding alone did NOT fix it; the old claim that connect! detached parents was
incorrect and has been removed.

c2's old moving callout was baked into its cached picture. Both c2 tracks were
invalidated in revision2 only. A newly regenerated late-orbit frame was viewed:
the moving callout is gone, the fixed heading stays bounded, and the atmosphere
is present. These affected pictures need native regeneration, NOT the BH frames.
The content/cache suite passes 775 checks, including all unchanged composite
files remaining hardlinks to the delivered edition, exact BH source values and
cache reuse, aligned picture/label cuts, steady Earth hour-angle steps, and
revised narration text. Deliberate BH breaths are 0.95–1.49 s with continuing
motion (not frozen holds). Seven additional native tests prove current uv
markers move between observing bins; 111 production-ray geometry tests pass.
Total: 903 automated checks, plus a bounded cache-adoption check rejecting
stale files without native receipts. These tests are NOT perceptual approval.
Four review clips are encoded and fully decoded: black_hole_revised.mp4
(2096 frames), wave_explanation_revised.mp4 (707), earth_motion_revised.mp4
(120), letter_names_revised.mp4 (605), all 1920x1080/30 with AAC narration.
Cue frames extracted from encoded BH/wave/Earth/closure clips were inspected;
the before/after b4 globe/reconstruction views also pass visual inspection.
Native preview planes and completed composites were retained in the project.
No jobs remain active and no full/farm run has started. Remaining expensive
picture work is 985/19396 frames: b5 440 and c2 545. Thus 94.9% of timeline
frames require no new expensive picture render; zero BH tracing is needed.
Bosgame stays excluded by tools/farm_policy.jl.

Review links (not a new full-film delivery):
- BH: https://agent.bonito.sh/s/709209247528581b30fcc486ea8f9b67/
- Waves: https://agent.bonito.sh/s/e48bf588a8af68255f7704d1d96901c3/
- Earth: https://agent.bonito.sh/s/b19326766f0af6433de7494565fe4893/
- Letters: https://agent.bonito.sh/s/42c98ae0189381e369308de2bc9b77eb/
Prior movies remain intact. Revision2 is saved under
renders/revision2_1080p_20261024.

The continuous delivery passed technical tests but FAILED the user's content
review. Do not call that version content-approved. These items are OPEN:

- [x] Opening: gas visible at its spoken introduction; reuse verified original
  full-gas / zero-bending frames 345–523 (179 valid cached pictures). Introduce
  the event horizon in this unbent illustration before explaining lensing.
- [x] Photon-ring cue: a complete accurately projected ring that is visibly
  distinguishable from the bright disk in the ENCODED video, not just in code.
- [x] Replace the wrongly emphasized saved “Here's why” stripe take (the saved
  take differs from current lines.jl); fix every spoken A/B/C letter name in
  the three-telescope closure explanation without changing indefinite articles.
- [x] Fix “the notes heard” motion: replaced >9x angular-step variation with a
  constant angular rate; native current uv positions move smoothly between
  observing bins. Final-quality motion preview encoded and decoded.
- [x] Satellite: replace/reposition the orbit-following callout so it stays
  in frame, avoids the Earth/right panel, and remains readable throughout.
- [x] More time to understand concepts: slower narration/visual pacing and
  deliberate breaths; stage telescope receivers, wavefronts, paths, recordings,
  extra delay and stripe pattern as they are introduced, not all at once.
- [x] Review affected encoded sections against narration, at cue-specific
  before/during/after moments, BEFORE another full export. Keep all existing
  movies, valid caches, Earth/atmosphere/path fixes; no new BH raytracing;
  Bosgame excluded from farm. Validate the eventual delivery and share it.

These tasks are also saved in the shared BonitoAgents to-do list. Static
midpoint samples and decode tests alone are NOT sufficient acceptance checks.

#### Continuous narrated re-edit, later 24 October

The user requested finishing the whole pacing edit, not just the ring test.
`tools/continuous_blackhole_edit.jl` replaces the frozen/silent a1 edit with
nine naturally spoken explanation beats and a monotonic cached-frame mapping.
The revised script/takes are cached under `voice_continuous_20261024`; the
actual audio samples and all camera/medium/plasma-clock keys are saved in
`renders/continuous_1080p_20261024/film_1080p.videoedit`. The earlier completed
movie and project are untouched. The new a1 is 2,019 frames / 67.3 seconds,
using EVERY one of the original 1,673 finished beauty pictures, in order,
at 0.748–0.9x source speed. No picture is repeated for more than two output
frames; no optical flow or new beauty rendering. Short breaths between ideas
are under 1.05 seconds; the only encoded silence longer than 1.1 seconds is
the intentional 1.32-second tail after the final spoken sentence.

The event horizon appears only during the moving, straight-light illustration,
before gravity bends the image again. Bending, the back of the disk, shadow,
photon ring, Doppler contrast and the near-polar M87 view have separate cues.
The far-side crossing leader is replaced with a plain caption. The horizon
outline is now the same thin ivory style; the shadow label sits inside the
actual dark region without a fake circular boundary. The full photon-ring
contour remains the numerically checked production critical-curve projection.
Nine native samples were actually rendered and visually inspected in `review/`.
`tools/test_continuous_blackhole.jl` passes 236 assertions: exact original
camera/medium/plasma-time values, horizon only at zero bending, disjoint
shadow/ring cues, natural narration, contiguous edit, unchanged other takes
and frame-cache validity, and hard-linked unchanged composites at sampled
positions in every other beat. The Earth/atmosphere/labels/rotation/path and
recording-voice corrections from the earlier delivery are all retained.

The complete revised section is `black_hole_explanation_1080p.mp4` in the new
directory: verified 2,019 frames, 1920x1080, 30 fps, AAC, full decode passed.
Encoded freeze detection found no freezes of 0.3 seconds or longer. A
post-export metadata-save bug (assigning the const trackcaches dictionary)
was fixed; the rendered section and native caches were recovered and tested,
not re-rendered. Its composites were adopted into the full native timeline.
The full movie `black_hole_1080p.mp4` is COMPLETE, exported from ALL 18,959
cached composites with zero picture/annotation renders during that export.
Its `.validation.txt` confirms 18,959 decoded frames, 1920x1080 at 30 fps,
AAC narration and a successful complete decode. This is the current delivery;
the earlier corrected movie remains preserved alongside it in its old folder.
No farm job was launched for this cache-only re-edit, and Bosgame remains excluded.

#### Photon-ring review revision, afternoon 24 October

The bracket highlight was rejected. `film/beats/a1_black_hole.jl` now draws
one complete, thin ivory contour (linewidth=1.5, 0.65 maximum alpha), without the
black backing or the old 4% radius inflation. `photon_ring_contour` in
`film/spacetime.jl` projects the critical incoming-ray cone, accounting for
the radius-18 medium boundary and finite-distance perspective. It marks the
critical curve approached by the photon subrings, not the broad glowing disk.
`tools/test_photon_ring.jl` checks capture/escape using the existing production
medium callbacks and the projection at 36 camera poses; 111 assertions pass
at each of step_scale=1 and the delivered 1.5. Geometry agrees within 0.15 px
at 1080p (test threshold), rather than using a hand-fitted enlarged circle.

The completed delivery below is preserved. A hard-linked saved-as review is
`renders/ring_review_1080p_20261024/film_1080p.videoedit`; all 2,093 a1 beauty
planes remain valid, with only the annotation/composite caches invalidated.
Three actually rendered and visually inspected samples are in its `review/`
directory. `tools/review_photon_ring.jl` reproduces those samples and a short
motion test from the ORIGINAL pre-hold cache. `motion.videoedit` and
`photon_ring_08x.mp4` contain 197 original pictures at native :sample 0.8x
speed: 246 output frames / 8.2 seconds / 1080p30, no inserted holds, optical
flow, new beauty renders, or narration. This is a visual motion test, NOT a
completed narration/timing revision or a replacement full-film export.
The star map has no independent animation in the scene: apparent movement
comes from the camera orbit and the changing lensing geometry.

The completed overnight baseline and MP4 remain under
`renders/recording_1080p_20261023`. The corrected delivery is
`renders/corrections_1080p_20261024/film_1080p.videoedit`; its native caches
were initially hard-linked from the baseline (writers publish by atomic rename).
`tools/correct_delivery.jl` contains the preparation, retiming and native review
helpers. It inserts 5/2/5/2-second silent holds after complete black-hole voice
sentences, retaining the original speech samples. The straight-light introduction
reuses original a1 source frame 360 until the existing animation reaches it.
All picture parameters, including the native plasma clock, are sampled from the
original mapped source frames. `VE.linkplane!` reuses their actual valid finished
planes; no farm receipts are fabricated, and no black-hole picture is retraced.
The independent raster annotation track now explains horizon, shadow and photon
ring sequentially, with the horizon outline confined to the explicitly marked
straight-light illustration. Native cached review frames are in `review/` beside
the corrected project. The ring uses contrasting brackets, and the dark region
is labelled inside it rather than outlined by an arbitrary circle.

The Earth atmosphere boundary is now visible to the tracer (its NullMaterial
surface remains transparent); its visibility follows the planet. The labels
layer retains invisible Earth/station native-property owners, and the stations'
missing reveal tracks are written again. The station tour has one monotonic
rotation, without the former per-site stops and reversals. b5 draws one arc per
geographic site pair while retaining every telescope's uv measurement. The b1
voice replaces only the final recording sentence, explicitly referring to the
spinning disks used for the observations; its first 811,913 approved samples are
preserved. Natural speech extends that raster beat by 26 frames. The corrected
timeline therefore contains 19,033 frames at 30 fps.

Unchanged portions of the Earth shots are also reused: the ground opening of b0,
the hidden-Earth section of a3 and the diagram/reconstruction sections of b4.
That recovers 2,092 picture planes and 13,903 shifted composites. Initial farm
selection is 2,107 distinct frames, with 16,926 timeline frames reused. Neither
black-hole beat is in the render queue. The new immutable job is
`renders/farm/corrections_1080p_20261024` (key
`5457c19a7c2afa58823b70eb69f8c566db10b939085a5ffcb79e0af39b15c41d`).

The persistent coordinator is `s4m-corrections-1080p-20261024.service`; its log
is `farm_service.log` beside the corrected project, with normal farm/export
progress in `farm_coordinator.log`. It uses the existing RecordingGPUTransport
and recording_farm helpers and the single Science4Makie root on every machine.
All six GPU slots initialized: Bosgame, Laptop, MacBook, Legion and both Desktop
GPUs. Legion is restricted to raster frames because restoring volume scattering
also adds volume queues to the Earth shots. Deployment is under each remote
root's `recording-corrections-20261024/application`, using the existing verified
assets. This paragraph records startup, not completion: check status.json and
the final DONE/export validation before reporting a corrected movie as finished.

The first correction job was paused after 252 committed frames to remove a
newly noticed grey atmosphere boundary. A full-resolution native A/B render
showed that uniform ambient escape radiance exposed the null volume boundary;
the physical sun/scattering atmosphere itself was not missing or truncated.
Earth's shared sunlight helper now uses zero ambient fill. The native production
review `review/003951.png` was rerendered and visually inspected: blue scattering
remains and the grey outer disk is absent. Only visible Earth source ranges were
invalidated; all black-hole picture planes were asserted valid. Adopted raster
corrections and unrelated caches remain reusable.

The replacement immutable job is
`renders/farm/corrections_1080p_20261024_atmosphere`, run by
`s4m-corrections-1080p-20261024b.service`, with startup/error output in
`farm_service_atmosphere.log`. The old job must not be resumed with changed
lighting. Mac's old in-flight child was deliberately stopped before restarting
as process 3; its old-job error is expected, not a failure of this new job.
`s4m-corrections-verify-20261024b.service` waits for export, then checks frame
count, size, fps, narration and complete decode. Completion still requires its
`validation.txt`, not merely successful startup.

### Batched direct-LAN dispatch and Bosgame exclusion, 24 October

The atmosphere job drained cleanly at 437 committed frames before the transport
switch. Its snapshot and receipts are preserved; this is a dispatch change, not
a scene/quality change. The former RPC path returned one frame before asking
for the next. Radeon frames rendered in ~3.2 s but committed ~45 s apart; Ada
frames rendered in ~6.2 s but committed ~50 s apart. A separate relay probe took
3–4 s for 2 MB and was not a LAN bandwidth test. Local GPU rendering also shared
the coordinator's scheduling thread. Neither overhead is an image-quality cost.

VideoEditor's normal renderfarm! now leases up to 16 adjacent missing compatible
frames by default. foreachfarmresult streams native FarmSlot results, commits
each verified frame immediately and retries only uncommitted lease members.
status.json includes batch metrics plus an incident history, separate from
unresolved errors. Pause drains a bounded lease; resume retains durable prefixes.
farmbatch.jl and tools/test_recording_lan.jl pass 31 CPU-only regression checks
in the sole root environment (with the session's DISPLAY/XAUTHORITY inherited).

tools/recording_lan.jl reuses the existing native farm wire. A separate transfer
parent sends results while its GPU child renders into a bounded two-result disk
queue. Both live in the same machine's Science4Makie root; no new renderer or
project environment is used. tools/recording_lan_runner.jl detaches these workers
from the interactive control session. The relay is used only for startup; frame
data goes directly over the authenticated LAN connections. Each connection gets
a measured 2 MB echo/integrity probe before receiving frames.

tools/farm_policy.jl excludes Bosgame/sim-bosgame until explicitly re-enabled.
Both normal project launchers and the correction launcher apply it. There is no
implicit local GPU worker in recording_farm.jl. The intended pool is Desktop's
Ada and Radeon, Laptop, MacBook and raster-only Legion. Bosgame may coordinate
and perform the final export, but is not a frame-rendering worker.

The first replacement startup failed because its relay address belonged to a
previous control session. No completed frames were lost. Current replacement
startup is s4m-corrections-1080p-20261024e.service, with output in
farm_service_batched_lan_e.log. Check actual READY lines and status.json before
calling the farm active; startup and passed tests are not completion receipts.

The repaired persistent coordinator is now
`s4m-corrections-1080p-20261024e.service`, log
`farm_service_batched_lan_e.log`. It launches detached native-wire transfer
parents with `recording_lan_runner.jl`, each owning a separate GPU child; a chat
control session restart cannot terminate them. A syntax/startup issue in the
intermediate d attempt was corrected before any frames were leased. e connected
all five approved slots and resumed the SAME atmosphere job/key. Its queue is
1,602 frames with 17,431 timeline frames reused (including the 437 adopted
commits), not a loss/reset of those commits. No Bosgame slot is present.

Live measurements: 2 MB echo round trips were 0.0345/0.0352 s for Desktop's two
slots, 0.1773 s Mac, 0.2337 s Laptop and 0.1827 s Legion. A warm Radeon batch of
16 frames took 51.07 s end-to-end versus 50.17 s rendering: roughly 3.2 s/frame,
not the previous ~45 s/frame cadence. A Legion batch took 5.50 s for 16 frames,
versus 5.39 s rendering. Ada's first batch included a 250 s cold first frame;
do not misreport that compilation/setup time as network overhead. All five
slots had returned frames by the 265-new-frame checkpoint, with no errors.
At 293 new frames Legion had finished its 161 eligible raster frames and left
the active pool normally; the remaining four slots continue the traced Earth
frames. Its idle GPU is not an outstanding lease or transfer stall.
The independent e verifier is waiting for export, and a timed failure/stall
watch is active. The corrected movie is NOT yet complete or validated.

### Earlier handoff

Desktop is now authorized on both discrete GPUs. Its current Vulkan indices
are **1 = RTX 4000 Ada**, **2 = Radeon RX 7900 XTX**, reversing the old inventory
below. `tools/recording_multigpu.jl` starts one Distributed child per GPU with
the same Science4Makie root, existing package images, four threads and a 3 GiB
soft GC target. The remote-eval session relays the ordinary VideoEditor wire
messages; rendering, retained HDR selection and inactive-scene cleanup still
use `tools/recording_farm.jl`. No additional renderer or Julia environment is
introduced. Desktop's child ranks are 2 (Ada) and 3 (7900 XTX); each renderer's
canvas is verified as 1920×1080.

The earlier native-client coordinator failed before dispatch on a stale
`coordinator.lock`. With no coordinator alive, that empty directory was moved
to `coordinator.lock.stale-20261024`; saved frames and the immutable snapshot
were retained. The resumed coordinator is the persistent user service
`s4m-recording-rpc-20261024d.service`, running `tools/run_recording_rpc.jl` in
the Bosgame root. Its log is
`renders/recording_1080p_20261023/s4m-recording-rpc-20261024d.log`.
It uses the authenticated remote-eval relay, without SSH. Its one-use private
relay bootstrap file is removed at startup. The original `status.json` remains
the authoritative production status, and `farm_coordinator.log` records frame
progress and final encoding.

All six workers joined: Bosgame, Laptop, Legion, Mac and both Desktop GPUs.
Legion excludes `a1_black_hole` and `a2_two_numbers` as before. This handoff
preserved 893 committed frames and 4,039 reused frames; Bosgame and Mac have
already returned new frames. Desktop's root files were backed up under
`farm-root-backups/recording_1080p_20261024` before deployment; its deployed
code and assets are under `recording-deploy-20261023`. All required assets,
including all 32 snapshots, match Bosgame's SHA-256 hashes. The application
asset symlink is required because scene builders use native relative paths.
Initial missing-link errors were corrected while the workers were retrying.
Both Desktop GPUs then returned a committed production frame successfully;
the checkpoint was 908/14,548 committed, 4,039 reused, all six workers active,
and no recorded errors. Registration alone is not proof of a returned frame.
The first Desktop receipts are frame 1540 (Ada, 227.81 s including cold work)
and 1541 (7900 XTX, 196.83 s including cold work). Both committed PNGs passed
1920×1080 dimensions and nonempty-image checks. Background run `r48` watches
worker errors, service exit, a 30-minute progress stall and final completion.

Recovery on 24 October, after the remote eval hosts restarted: the `d` service
survived and continued on Bosgame, but its five remote connections were lost.
All deployments and all 32 snapshots were already present; no new full source
transfer was needed. Remote renderers were restored using the existing
`recording-control/recording_multigpu.jl`, then `pause.requested` let the old
coordinator finish its in-flight frame, adopt caches and exit successfully.
It stopped at 1,531 committed frames. The same immutable job now runs under
`s4m-recording-rpc-20261024e.service`, with its corresponding `e.log` beside
the project. Its initial counters are 5,570 reused and 13,017 remaining;
the increased reuse includes the adopted 1,531 frames from the previous run.
All six workers registered at 1920×1080 with no startup errors. These initial
counts do not establish that each worker has returned a new frame yet.

The remote root paths are Desktop `/sim/Programmieren/Science4Makie`, Laptop
`/home/simon/Programmieren/Science4Makie`, MacBook
`/Users/simon/Programmieren/Science4Makie`, and Legion
`/home/sim/programmieren/Science4Makie`. Desktop loads
`recording-deploy-20261023/application/recording.videoedit`; the others load
`BlackholeImage/recording.videoedit` in their root. Each has child rank 2;
Desktop also has rank 3 for the Radeon. Sleep inhibitors were started on all
five machines, tied to the current coordinator or remote eval process.
All six workers subsequently returned new production frames: the recovery
checkpoint was 32/13,017 completed, 5,570 reused, with no errors. Their returned
counts were Bosgame 14, Ada 2, Radeon 2, Laptop 1, Mac 7 and Legion 6.
Background root run `r50` watches the `e` service, worker errors, a 30-minute
progress stall and final completion. The service still performs the native
cache adoption and ordinary VideoEditor export automatically after dispatch.
During subsequent monitoring, Mac frame 3218 (`a4_giant_telescope`) completed
in 772.53 seconds. While it ran, a process sample showed Metal command-buffer
completion waiting, AGX reported 100% GPU utilization, and system memory
pressure was healthy. This long interval was actual GPU work, not a lost
connection. Do not infer a dead worker from several quiet minutes on that
scene alone. At 383 new frames the queue still had all six workers active and
no errors; Bosgame had about 268 GiB free disk space and all hosts had healthy
memory availability/pressure.

`renders/final_20261021_720p_256spp/film_720p_256spp.videoedit` is the native
final project: 1280×720, 30 fps, 256 spp, 18,587 frames including twelve seconds
of silent Makie/software/science credits. Its black-hole scenes use 384³ fields,
half-size transport steps and a 1024 transport-depth budget. The a1 volume
animation uses 32 real snapshot inputs through the native file-series node.
This is fast-light, non-spinning radio transfer, not a claim of converged GRRT.

The full-render job is `renders/farm/full_hd_720p_256spp_fixed_20261022`.
At launch, native cache reuse excluded 10,758 timeline frames and left 7,829
for farm processing. The target final export is
`renders/final_20261021_720p_256spp/black_hole_full_720p_256spp.mp4`.
These are job/project addresses, not a claim that the MP4 has finished.
The first new Bosgame frame took 284.3 seconds including cold costs; the
approximately one-minute RTX 4000 Ada budget is still unmet/unverified at these
settings. Do not substitute Bosgame timings for Ada measurements.

Additional Ada measurements at the same 384³/256-spp settings: frame 2078 took
341.94 s cold and was committed through the normal FarmWorker wire/result path
into the final cache. Regular warm frames 523/526 took 147.39/146.53 s, so the
one-minute budget is NOT met. The worker subsequently disconnected with EPIPE;
its GPU log had no Julia exception, while the host's global OOM-kill counter had
risen to 39. This is evidence of host pressure, not proof of that PID's cause.

The application launcher now supplies an explicit 1–4 GiB soft GC target based
on detected host memory (and preserves an explicit parent heap setting). It does
not reduce sampling or physics quality. One guarded Ada retry uses the log
`farm-client-hd-heap4g-retry1-20261022.log`; do not repeatedly restart that worker
if this attempt also exits. The larger-memory Bosgame keeps its original GC
configuration. Launcher/root/child-option tests pass 16/16.

The one guarded Ada retry started on 22 October after two memory-headroom
checks. Its renderer command actually contains `--heap-size-hint=3G` (the
detected capacity is below 32 GiB), not the 4 GiB upper bound. Parent PID 827593
and first child PID 829514 belong to this retry. Do not start another retry if
it fails. Native pause/adoption saved all 24 frames of the previous batch;
run r553 resumed the same immutable job with 10,816 reused timeline frames and
7,771 remaining. The final ordinary export is chained after that render, but
the MP4 is not yet complete. Read-only numerical QA passed for 62 saved HD
masters at this checkpoint.

That guarded Ada retry returned one frame, then disconnected with EOF. The
host's OOM counter rose from its retry baseline of 40 to 41, and swap was nearly
exhausted. This does not identify the killed PID conclusively, but the renderer
was gone; only our verified parent client (827593) was stopped. No further Ada
restart is allowed for this delivery attempt. Run r553 continues on Bosgame and
the RTX 3070; the returned Ada frame is committed and unfinished work requeued.

Metal remains unvalidated for this full scene. A fresh root-only native probe
stopped making progress before producing a master. Its macOS process sample is
`~/.videoeditor/farm/probes/5a7c36432c80-frame2077.sample.txt` and shows a wait in
Apple's compute-pipeline compiler (`MTLCompilerScheduler` / dispatch queue).
Only our diagnostic process was stopped; keep Metal out of the production farm
unless a complete native frame is successfully verified.

## Additional worker debugging, 22 October

The user requested debugging unavailable machines while Bosgame and legion-boi
continue production run r553. Do not pause that run just to investigate another
host. No additional worker is production-validated yet.

- Desktop has both a Radeon 7900 XTX (Vulkan index 1) and RTX 4000 Ada (index 2).
  Old standalone probes hard-coded index 1: their timings are not Ada timings.
  The native FarmClient selected Ada correctly. Both probe helpers now accept
  `SCIENCE_FARM_GPU` and print the actual device name. At 06:53 the Desktop had
  only 3.1 GB available RAM, essentially exhausted swap, and unrelated jobs
  occupying about 15 GB of Ada memory. Do not kill those jobs or start another
  full-size probe without sufficient headroom.
- A bounded startup probe directly observed unrelated MatAnyoneRunner and
  SAM2Runner precompilation growing to approximately 8.7 and 7.2 GB RSS.
  The launcher now reuses existing package images (`--compiled-modules=existing`)
  and limits small-host precompile concurrency. Uncached code still loads in the
  same application root; no separate Pkg environment is created. VideoEditor's
  child launcher now actually respects `JULIA_NUM_THREADS` (fork commit bfe387d),
  rather than overriding the application's cap with `--threads=auto`.
- A systemd scope's advertised MemoryMax was NOT enforced: this host's user
  cgroup tree only delegates the pids controller. Do not claim a hard memory
  cap. Diagnostic watchdogs monitor actual RSS/headroom and clean up only their
  own isolated process group. No global cgroup configuration was changed.
- Hikari's captured-module lookup in threaded GRMHD sampling was replaced with
  constant module references (6699f83). Thirty-two comparisons preserve every
  physical field bit-for-bit. A fresh 384-cubed CPU preparation took 8.28 seconds;
  this is not a GPU frame time. The existing published Metal texture fix #44 was
  backported as 41355bf, with 2089 texture/differential checks passing. Both
  commits are on the existing sd/lava-refactor branch in SimonDanisch/Trace.jl;
  the advanced JuliaGraphics origin branch was not overwritten.
- Mac diagnostic PID 52685 still spent minutes in Apple's shader optimizer after
  that published fix. Its associated MTLCompilerService consumed 100% of a CPU;
  this is not evidence of an idle worker or a proven deadlock. Saved native AIR
  has 2481 basic blocks and an inlined `trace_shadow_transmittance`, despite the
  source's noinline annotation. Debug locations identify our `sample_density`
  array-bound exception paths inside that shadow transport.
- The plasma interpolation stencil now explicitly checks finite coordinates,
  dimensions and grid shape before unchecked device reads and finite coordinate
  conversion. 8241 tests cover bit-identical scalar/vector interpolation,
  boundaries, malformed grids and non-finite positions. This is not yet proof
  that Metal compilation or a whole frame succeeds. A/B probe PID 54581 uses
  `metal-guarded-sampler.log` and `metal-guarded-sampler-dumps` under the Mac farm
  probes folder. Its explicit diagnostic-only method override does not alter
  immutable job files, write production receipts, or qualify bytes for adoption.
  The guarded sampler reduced the largest dumped shader to 1797 basic blocks
  (3.91 MB AIR text), and a fresh process sample now shows GPU command execution
  and waitUntilCompleted, not MTLCompilerScheduler. A complete frame remains
  required before production admission.
- Desktop subsequently recovered over 9 GiB RAM headroom and 17 GiB free Ada
  memory as unrelated jobs exited. Run r675 is a bounded diagnostic on explicit
  Vulkan index 2, not another unattended production restart. Its own process
  group is stopped if available RAM falls below 4 GiB, RSS exceeds 8 GiB or
  elapsed time reaches 900 seconds. It uses existing package images and a 3 GiB
  soft heap hint; the latter is not a hard allocation limit.
  That probe selected Ada correctly but was stopped after 152 seconds when
  available RAM fell to 3.44 GB; no frame was completed. Its termination trace
  locates boxed arithmetic in HikariGRMHDSnapshotsExt.jl's majorant-cell loop,
  not an NVIDIA driver error. EmissionParams.p is untyped, so its invariant
  exponent was recalculated dynamically per cell. Hoisting the Float32 exponent
  preserves all five physical outputs bit-for-bit in 42 comparisons, including
  two non-default electron indices. Fork commit a7985bc reduces fresh 384-cubed
  CPU preparation from 8.88 GB allocated / 8.28 s to 1.69 GB / 3.61 s on Bosgame
  with two Julia threads. These are CPU preparation figures, not GPU timings.
  A subsequent admission check (r687) did not launch because headroom had
  fallen; a ten-minute wait (r689) never observed the stricter 10 GiB admission
  threshold either. Do not report these as completed Ada frames or GPU errors.
- The extra Laptop's single root has Project.toml but no Manifest.toml, only
  2.7 GB free writable storage, and its spacious Windows volume is read-only.
  Provisioning cannot fit the input bundle; do not remount or delete user data.

The Mac guarded-sampler probe subsequently completed tracing but failed at
OIDN's first convolution: the specialised kernel assumed 16x16 cooperative
matrices, while Metal advertises 8x8. JuliaVision 81eadec parameterises that
existing convolution by the device tile size, including scalar half views of
Metal shared staging; fp16 inputs/weights and fp32 accumulation stay unchanged.
All 14 tilings plus two capability checks passed on both Metal and Vulkan, and
the Mac's complete device-side OIDN pipeline passed 3/3 checks. The concurrent
origin changes were merged without overwriting them; b21c9f5 adds compatibility
with this root's dictionary-based Mantle staging API. Another 196 compatibility,
atomic-reduction and chunked-convolution checks passed on Bosgame. Published on
the existing sd/mantle-dev branch, not a new branch.

Mac PID 58928 (`metal-matrix8-fullframe.log`) is the new full 720p/256-spp
diagnostic with Hikari a7985bc and JuliaVision b21c9f5. It still uses the explicit
guarded-sampler override, so is not a receipt from the original immutable job.
A complete image must pass QA before production admission. The earlier failed
probe's temporary HDR cache was removed by closefarm!; do not claim it was
retained. The diagnostic now calls native saveproject on failure before closing,
which copies valid cache entries to an interrupted.videoedit project through
VideoEditor's ordinary Save As path, without constructing receipts or splicing.

Mac full-frame probe 2077 now passes: native frame time 643.02 seconds, 720p,
256 spp, linear HDR plus OIDN, one returned master passing numerical QA. The
decoded image was visually inspected with the plasma, lensed sky and labels
present. This is an Apple M5 measurement, not an Ada measurement or a claim to
meet the one-minute Ada budget. Upstream OIDN comparison on Metal has relative
RMS 0.001244 (limit 0.005). Native production HDR QA also passed for 183 masters.

Desktop r705 finally admitted one bounded test with the hoisted exponent. Its
peak RSS fell to 3.73 GB, but other host workloads consumed the remaining RAM:
the watchdog stopped it at 144 seconds when availability dropped below 4 GiB.
No Ada frame was returned. The NVIDIA Vulkan device initialized successfully;
do not label this watchdog termination a GPU driver failure. Stop further
render retries until the shared host has genuinely stable memory headroom.

Production job 5a7c36432c80 remains immutable with its original package pins.
Prepare a new native snapshot only after a corrected worker passes verification;
adopt saved native caches normally, never fabricate receipts or edit old pins.

## Limits

The v5 movie and farm PNGs already contain burned-in text. They cannot become
clean picture planes automatically: the first layered render is a one-time
baseline render. Thereafter label edits and tail extensions reuse that baseline.

An extension only preserves old frames if their animation is unchanged. Altering
an earlier camera move, reveal, lighting or line timing correctly dirties the
frames affected by that edit. Retiming a language should not normalize every
camera path against the new total duration.

Flow-interpolated clips currently bypass the per-source-frame plane cache,
because their output also depends on fractional time. These clips still use the
composite cache. The English film uses ordinary sampled scene clips.

Raster review exports use an independent cache (or no cache). They must not
populate the final raytraced cache with preview-quality frames.

Keep one persistent raster review project and edit it in place. `exportraster`
now saves that project's raster settings and native track/composite caches,
including checkpoints during export; it does not clear caches or recreate clip
identities. Use `setsceneargs!` for changed recipe inputs, `invalidateclip!` for
external recipe edits, and the clip placement setters for a longer narration.
Moving later clips preserves their source-frame caches. An MP4 from the old
uncached helper does not contain editable track caches and is not spliced into
the new export.

For a revised script take, `refreshbeat!(seq, name; voice_root)` applies the new
cue timing to both picture and labels, replaces the source-anchored narration,
and ripples later clips through the editor's placement setters. It preserves
clip/source identities and untouched source-frame caches; save the same project
before calling `exportraster` again. `tools/test_refreshbeat.jl` checks these
invariants against a populated review project without saving its test edits.
