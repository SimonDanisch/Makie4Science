# Illinois v3 MAD a=0, Dhruv et al. 2025. Snapshot-by-snapshot fast-light
# transport, not slow-light transfer through evolving gas along a ray.
# Coordinates below are Schwarzschild
# radii; the snapshot uses r_g, so every spatial query is scaled by TWO.
const GRMHD_FILE = joinpath(@__DIR__, "..", "assets", "grmhd", "torus.out0.05000.h5")
const GRMHD_PLASMA = Ref{Any}(nothing)
# The film's exposure: the emissivity shown at full scale. It is snapshot 5000's
# peak as its 384³ Cartesian resampling saw it, the reference every approved
# frame was exposed with. The native grid's own peak lies inside the horizon.
const GRMHD_EXPOSURE = 1.1162966f-20

function grmhd_plasma(; path=GRMHD_FILE, normalization=GRMHD_EXPOSURE)
    cached=GRMHD_PLASMA[]
    if cached!==nothing && cached.path==abspath(path) && cached.normalization==normalization
        return cached
    end
    result=Hikari.native_radiative_volume(path;normalization,
        mass_unit=3e24,black_hole_mass=6.5e9*1.98847e33)
    GRMHD_PLASMA[]=result
    result
end

"A plasma state without gas, on the smallest native grid."
empty_plasma(; extent=15f0) = (; density=zeros(Float32,2,2,2), absorption=zeros(Float32,2,2,2),
    velocity=fill(zero(Hikari.SVector{3,Float32}),2,2,2), theta=Float32[0 π; 0 π],
    log_r0=0f0, dlog_r=Float32(log(extent)), phi0=0f0, dphi=Float32(π), extent=Float32(extent))

"Validated consecutive outputs; use the actual dump timestamps, not filename cadence."
function grmhd_sequence(; first=5000, last=5031)
    first < last || throw(ArgumentError("a sequence needs at least two snapshots"))
    paths=[joinpath(dirname(GRMHD_FILE),"torus.out0."*lpad(i,5,'0')*".h5") for i in first:last]
    H=GRMHDSnapshots.HDF5
    times=Float64[]
    reference=nothing
    # The full coordinate prescription, resolution and primitive ordering must
    # agree. Unit conversion is explicitly the same for every load above.
    for path in paths
        isfile(path) || error("Missing GRMHD sequence input: $path")
        H.h5open(path,"r") do f
            header=Dict(k=>read(f["header/"*k]) for k in
                ("a","gam","n1","n2","n3","prim_names"))
            geom=f["header/geom"]
            function readtree(group)
                Dict(k => (group[k] isa H.Group ? readtree(group[k]) : read(group[k])) for k in keys(group))
            end
            header["geom"]=readtree(geom)
            header["a"]==0 || error("Sequence requires Schwarzschild/spin-zero transport")
            isnothing(reference) ? (reference=header) :
                isequal(reference,header) || error("Incompatible snapshot grid/header: $path")
            push!(times,Float64(read(f["t"])))
        end
    end
    all(isfinite,times) && all(>(0),diff(times)) || error("Snapshot times must increase strictly")
    return (; paths,times)
end

function grmhd_bracket(times,t)
    isfinite(t) || throw(ArgumentError("non-finite simulation time"))
    i=clamp(searchsortedlast(times,t),1,length(times)-1)
    return i,Float32(clamp((t-times[i])/(times[i+1]-times[i]),0,1))
end

"The product interval of two intervals."
interval_product((a0,a1),(b0,b1)) = extrema((a0*b0,a0*b1,a1*b0,a1*b1))

"Whether the angles `φ0..φ1` reach `angle`, modulo 2π."
reaches(φ0,φ1,angle) = angle+2π*ceil((φ0-angle)/2π) <= φ1

"""
    sector_box(radii, colatitudes, azimuths) -> (lo, hi)

The Cartesian bounding box of the points whose radius, colatitude and azimuth lie
in the three given ranges. Each coordinate is a product of independent factors,
so interval arithmetic gives the exact box.
"""
function sector_box((r0,r1),(θ0,θ1),(φ0,φ1))
    sinθ=(min(sin(θ0),sin(θ1)), θ0<=π/2<=θ1 ? 1.0 : max(sin(θ0),sin(θ1)))
    cosφ=(reaches(φ0,φ1,π) ? -1.0 : min(cos(φ0),cos(φ1)), reaches(φ0,φ1,0) ? 1.0 : max(cos(φ0),cos(φ1)))
    sinφ=(reaches(φ0,φ1,3π/2) ? -1.0 : min(sin(φ0),sin(φ1)), reaches(φ0,φ1,π/2) ? 1.0 : max(sin(φ0),sin(φ1)))
    ρ=interval_product((r0,r1),sinθ)
    x=interval_product(ρ,cosφ); y=interval_product(ρ,sinφ); z=interval_product((r0,r1),(cos(θ1),cos(θ0)))
    return (Vec3(x[1],y[1],z[1]), Vec3(x[2],y[2],z[2]))
end

"Raise every cell of `grid` (over `±extent`) that the box `(lo, hi)` overlaps to `value`."
function splat!(grid,(lo,hi),extent,value)
    n=size(grid,1)
    cell(x)=clamp(floor(Int,(x+extent)/(2extent)*n)+1,1,n)
    for z in cell(lo[3]):cell(hi[3]),y in cell(lo[2]):cell(hi[2]),x in cell(lo[1]):cell(hi[1])
        grid[x,y,z]=max(grid[x,y,z],value)
    end
    return grid
end

"""
    grmhd_pair_cells(a, b; res=32, electron_index=2.5f0) -> (; absorption, emission)

Conservative bounds per cell of a `res³` grid over `±a.extent`, for any
interpolation in space and time between the native plasma states `a` and `b`:
the shifted absorption the majorant has to cover, and the shifted emissivity
that decides how densely a cell is sampled for emission.

Between shells `i` and `i+1` the medium reads, at a point, the colatitude
bracket the point falls into on either shell and the two azimuth columns around
it. Each such stencil covers a range of radius, colatitude and azimuth, and its
bound goes to every cell its Cartesian box overlaps. There the shader's shift
`√f·D^doppler` is at most `√f(r₁)·D(v)`, `r₁` the outer shell and `D` the
Doppler factor `√((1+v)/(1-v))` of the fastest corner, for `doppler` in [0, 1].
"""
function grmhd_pair_cells(a,b; res=32, electron_index=2.5f0)
    grid(s)=(size(s.absorption),s.theta,s.log_r0,s.dlog_r,s.phi0,s.dphi,s.extent)
    grid(a)==grid(b) || error("Incompatible plasma grids")
    nphi,ntheta,nr=size(a.absorption)
    ea,ej=(electron_index+2)/2,(electron_index+3)/2
    extent=a.extent
    # Float32 rounding of the shader's radius and angles stays inside the pad.
    shells=exp.(a.log_r0 .+ a.dlog_r .* (0:nr-1))
    pad=1e-4
    lower(i,j)=j==1 ? 0.0 : Float64(a.theta[i,j])
    upper(i,j)=j==ntheta-1 ? Float64(π) : Float64(a.theta[i,j+1])
    tasks=map(Iterators.partition(1:nphi,cld(nphi,Threads.nthreads()))) do columns
        Threads.@spawn begin
            absorption=zeros(Float32,res,res,res); emission=zeros(Float32,res,res,res)
            for k in columns, i in 1:nr-1
                kp=mod(k,nphi)+1
                radii=(shells[i]*(1-pad),shells[i+1]*(1+pad))
                azimuths=(a.phi0+(k-1)*a.dphi-pad,a.phi0+k*a.dphi+pad)
                f=sqrt(max(1-1/radii[2],1e-5))
                ja=jb=1
                while ja<ntheta && jb<ntheta
                    lo=max(lower(i,ja),lower(i+1,jb)); hi=min(upper(i,ja),upper(i+1,jb))
                    if lo<=hi
                        alpha=0f0; j=0f0; v2=0f0
                        for s in (a,b),(shell,bracket) in ((i,ja),(i+1,jb)),jj in (bracket,bracket+1),kk in (k,kp)
                            alpha=max(alpha,s.absorption[kk,jj,shell])
                            j=max(j,s.density[kk,jj,shell])
                            v2=max(v2,Float32(sum(abs2,s.velocity[kk,jj,shell])))
                        end
                        if alpha>0 || j>0
                            v=sqrt(min(v2,0.99999f0))
                            shift=f*sqrt((1+v)/(1-v))
                            box=sector_box(radii,(max(lo-pad,0.0),min(hi+pad,Float64(π))),azimuths)
                            splat!(absorption,box,extent,Float32(alpha*shift^ea))
                            splat!(emission,box,extent,Float32(j*shift^ej))
                        end
                    end
                    ua,ub=upper(i,ja),upper(i+1,jb)
                    ua<=ub && (ja+=1)
                    ub<=ua && (jb+=1)
                end
            end
            (absorption,emission)
        end
    end
    parts=fetch.(tasks)
    return (; absorption=reduce((x,y)->max.(x,y),first.(parts)),
              emission=reduce((x,y)->max.(x,y),last.(parts)))
end

"""
    majorant_voxels(cells, gas_scale, padding; floor_fraction=1f-4) -> Vector{Float32}

The majorant per cell, flattened in Hikari's `MajorantGrid` order: the cell's
absorption bound, the shader's absorption floor where it has gas, and emission
sampling that follows the cell's emissivity. Cells emitting at least
`floor_fraction` of the brightest one keep the global sampling rate (the
largest absorption plus `padding`); dimmer ones are sampled in proportion,
which bounds what a single sample of theirs can add; empty cells are skipped.
"""
function majorant_voxels(cells, gas_scale, padding; floor_fraction=1f-4)
    rate=maximum(cells.absorption)*gas_scale+padding
    jref=floor_fraction*maximum(cells.emission)
    vec(map(cells.absorption,cells.emission) do alpha,j
        alpha*gas_scale+(j>0 ? 1f-6 : 0f0)+(jref>0 ? rate*min(1f0,j/jref) : 0f0)
    end)
end
