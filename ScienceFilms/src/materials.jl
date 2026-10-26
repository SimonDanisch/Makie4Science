# Shared materials: the mechanics of instruments, the studio floor, filters.

const MAT = (
    anodized = Hikari.CoatedDiffuse(reflectance = (0.015, 0.015, 0.017), roughness = 0.25),
    paint = Hikari.CoatedDiffuse(reflectance = (0.8, 0.8, 0.78), roughness = 0.08),
    aluminium = Hikari.Conductor(eta = (1.657f0, 0.880f0, 0.521f0), k = (9.224f0, 6.270f0, 4.837f0), roughness = 0.12),
    satin_aluminium = Hikari.Conductor(eta = (1.657f0, 0.880f0, 0.521f0), k = (9.224f0, 6.270f0, 4.837f0), roughness = 0.10,
                                       reflectance = (0.94, 0.92, 0.89)),
    floor = Hikari.Diffuse(Kd = (0.24, 0.205, 0.17)),
    sensor = Hikari.CoatedDiffuse(reflectance = (0.03, 0.02, 0.05), roughness = 0.0),
    rubber = Hikari.Diffuse(Kd = (0.025, 0.025, 0.025)),
    # a filter darkening towards its rim, in three steps
    filter_light = Hikari.Dielectric(Kt = (0.7, 0.7, 0.7), index = 1.5),
    filter_mid = Hikari.Dielectric(Kt = (0.35, 0.35, 0.35), index = 1.5),
    filter_dark = Hikari.Dielectric(Kt = (0.1, 0.1, 0.1), index = 1.5),
)
