# Shared materials: the mechanics of instruments, the studio floor, filters.

const MAT = (
    anodized = Hikari.CoatedDiffuse(reflectance = (0.015, 0.015, 0.017), roughness = 0.25),
    paint = Hikari.CoatedDiffuse(reflectance = (0.8, 0.8, 0.78), roughness = 0.08),
    aluminium = Hikari.Conductor(ior = (1.657f0, 0.880f0, 0.521f0), extinction = (9.224f0, 6.270f0, 4.837f0), roughness = 0.12),
    satin_aluminium = Hikari.Conductor(reflectance = (0.94, 0.92, 0.89), roughness = 0.10),
    floor = Hikari.Diffuse(color = (0.24, 0.205, 0.17)),
    sensor = Hikari.CoatedDiffuse(reflectance = (0.03, 0.02, 0.05), roughness = 0.0),
    rubber = Hikari.Diffuse(color = (0.025, 0.025, 0.025)),
    # a filter darkening towards its rim, in three steps
    filter_light = Hikari.Glass(color = (0.7, 0.7, 0.7), ior = 1.5),
    filter_mid = Hikari.Glass(color = (0.35, 0.35, 0.35), ior = 1.5),
    filter_dark = Hikari.Glass(color = (0.1, 0.1, 0.1), ior = 1.5),
)
