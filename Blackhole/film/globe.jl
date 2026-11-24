# The Earth as a turning globe (earth.jl draws it), with the Event Horizon
# Telescope's stations and the lines between them. Positions on a unit sphere, z through the North Pole;
# the globe turns about z by an angle Observable.

"""A point on the unit sphere at latitude/longitude (degrees), lifted `h` above the surface."""
sphere_point(lat, lon; h = 0.0) = Point3f((1 + h) .* (cosd(lat) * cosd(lon), cosd(lat) * sind(lon), sind(lat)))

"""
A sphere mesh with explicit texture coordinates for an equirectangular map
(longitude -180..180 left to right, latitude 90..-90 top to bottom).
"""
function globe_mesh(n = 96)
    lats = range(-90, 90; length = n + 1)
    lons = range(-180, 180; length = 2n + 1)
    P = Point3f[]; N = Vec3f[]; UV = Vec2f[]
    for lat in lats, lon in lons
        p = sphere_point(lat, lon)
        push!(P, p); push!(N, Vec3f(p)); push!(UV, Vec2f((lon + 180) / 360, (lat + 90) / 180))
    end
    m = length(lons)
    F = GLTriangleFace[]
    for i in 1:length(lats)-1, j in 1:m-1
        a = (i - 1) * m + j
        push!(F, GLTriangleFace(a, a + 1, a + m + 1), GLTriangleFace(a, a + m + 1, a + m))
    end
    return GeometryBasics.Mesh(P, F; normal = N, uv = UV)
end


"""Rotation by `θ` (radians) about z, for points on the globe."""
spin(p, θ) = Point3f(cos(θ) * p[1] - sin(θ) * p[2], sin(θ) * p[1] + cos(θ) * p[2], p[3])

"""
    globe!(scene, turn; radius) -> NamedTuple

The Earth in `scene`, turned by the Observable `turn` (radians about z).
Returns `point(lat, lon; h)`: an Observable of where a place on it is now.
"""
function globe!(scene, turn::Observable)
    point(lat, lon; h = 0.0) = lift(θ -> spin(sphere_point(lat, lon; h), θ), turn)
    # the maps' rows run from the North Pole down; the tracer samples row 1 at
    # v = 1, which `globe_mesh` gives the North Pole
    earth = labels_only() ? mesh!(scene,Sphere(Point3f(0),1f0);name=:earth,visible=false) :
        mesh!(scene,globe_mesh(256);name=:earth,material=earth_material())
    if !labels_only()
        air = air!(scene)
        # Hiding the planet must also hide its scattering boundary.
        on(earth.visible) do visible
            Makie.update!(air; visible)
        end
    end
    Makie.rotate!(earth,Vec3f(0,0,1),turn[])
    syncing=Ref(false)
    on(turn) do θ
        syncing[] && return
        syncing[]=true
        try
            Makie.rotate!(earth,Vec3f(0,0,1),θ)
        finally
            syncing[]=false
        end
    end
    on(earth.transformation.rotation) do q
        syncing[] && return
        θ=Float32(2atan(q.data[3],q.data[4]))
        syncing[]=true
        try
            isequal(turn[],θ) || (turn[]=θ)
        finally
            syncing[]=false
        end
    end
    propertypath!(turn,earth,"rotation[3]";scale=180/pi)
    return (; earth, point)
end

"""An arc between two places on the globe, rising `lift` above the surface at its middle."""
function arc(a, b; rise = 0.12f0, n = 48)
    va, vb = normalize(Vec3f(a)), normalize(Vec3f(b))
    ω = acos(clamp(dot(va, vb), -1f0, 1f0))
    return map(range(0f0, 1f0; length = n)) do s
        v = ω < 1f-4 ? va : (sin((1 - s) * ω) * va + sin(s * ω) * vb) / sin(ω)
        Point3f((1 + rise * sin(Float32(π) * s)) * v)
    end
end

"""Whether a point on the globe faces the camera at `eye` (for hiding labels on the far side)."""
facing(p, eye) = dot(normalize(Vec3f(p)), normalize(Vec3f(eye) - Vec3f(p))) > 0.05f0

"""The stations that observe M87*, one marker per place (sites on one mountain merged); the South Pole never sees it."""
const PLACES = [(name = "Hawaii", lat = 19.82, lon = -155.48), (name = "Arizona", lat = 32.33, lon = -110.75),
                (name = "Mexico", lat = 18.99, lon = -97.32), (name = "Chile", lat = -23.02, lon = -67.76),
                (name = "Spain", lat = 37.07, lon = -3.39), (name = "France", lat = 44.63, lon = 5.91),
                (name = "Greenland", lat = 76.54, lon = -68.69)]
