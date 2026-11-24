# Terrain-only utility preserved from this project's pre-GRMHD film code
# (25e5465). It is not a renderer and is never used for the black-hole plasma.
@inline function terrain_hash01(x::Int32, y::Int32, z::Int32, s::Int32)
    h = (x % UInt32) * 0x27d4eb2d + (y % UInt32) * 0x165667b1 + (z % UInt32) * 0x9e3779b9 + (s % UInt32) * 0x85ebca6b
    h = xor(h, h >> 15) * 0x2c1b3c6d
    h = xor(h, h >> 12) * 0x297a2d39
    h = xor(h, h >> 15)
    Float32(h >> 8) * (1f0 / 16777216f0)
end
# Existing terrain colour/experiment code also uses the scalar hash directly.
@inline hash01(x::Int32,y::Int32,z::Int32,s::Int32) = terrain_hash01(x,y,z,s)
@inline terrain_fade(t) = t * t * t * (t * (t * 6f0 - 15f0) + 10f0)
@inline function terrain_vnoise(p::Vec3f, s::Int32)
    fx, fy, fz = floor(p[1]), floor(p[2]), floor(p[3])
    ix, iy, iz = unsafe_trunc(Int32, fx), unsafe_trunc(Int32, fy), unsafe_trunc(Int32, fz)
    u, v, w = terrain_fade(p[1] - fx), terrain_fade(p[2] - fy), terrain_fade(p[3] - fz)
    a = terrain_hash01(ix, iy, iz, s); b = terrain_hash01(ix + Int32(1), iy, iz, s)
    c = terrain_hash01(ix, iy + Int32(1), iz, s); d = terrain_hash01(ix + Int32(1), iy + Int32(1), iz, s)
    e = terrain_hash01(ix, iy, iz + Int32(1), s); f = terrain_hash01(ix + Int32(1), iy, iz + Int32(1), s)
    g = terrain_hash01(ix, iy + Int32(1), iz + Int32(1), s)
    h = terrain_hash01(ix + Int32(1), iy + Int32(1), iz + Int32(1), s)
    x1 = a + u * (b - a); x2 = c + u * (d - c)
    x3 = e + u * (f - e); x4 = g + u * (h - g)
    y1 = x1 + v * (x2 - x1); y2 = x3 + v * (x4 - x3)
    y1 + w * (y2 - y1)
end
"Four octaves of deterministic terrain noise, in 0..1."
@inline function fbm(p::Vec3f, s::Int32)
    n = 0.5f0 * terrain_vnoise(p, s)
    n += 0.25f0 * terrain_vnoise(2.03f0 * p + Vec3f(17.1f0, 3.7f0, 9.2f0), s)
    n += 0.125f0 * terrain_vnoise(4.01f0 * p + Vec3f(5.3f0, 21.9f0, 1.1f0), s)
    n += 0.0625f0 * terrain_vnoise(8.05f0 * p + Vec3f(11.7f0, 7.3f0, 30.5f0), s)
    n * (1f0 / 0.9375f0)
end
