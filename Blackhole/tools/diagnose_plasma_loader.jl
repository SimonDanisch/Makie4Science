@assert Base.active_project()==normpath(joinpath(@__DIR__,"..","..","Project.toml"))
using Hikari, GRMHDSnapshots
ext=Base.get_extension(Hikari,:HikariGRMHDSnapshotsExt)
bodyname=only(filter(n->startswith(String(n),"#radiative_volume#"),names(ext;all=true)))
body=getproperty(ext,bodyname)
types=Tuple{Float64,Float64,Int,Float32,Nothing,Hikari.EmissionParams,
    typeof(Hikari.radiative_volume),String}
for (ir,_) in code_typed(body,types;optimize=false)
    println("LOADER_LOCAL_TYPES")
    for (name,type) in zip(ir.slotnames,ir.slottypes)
        occursin(r"snap|native|threads",String(name)) && println(name," :: ",type)
    end
end
path=joinpath(@__DIR__,"..","assets","grmhd","torus.out0.05000.h5")
resolutions=get(ENV,"SCIENCE_PLASMA_FULL_RESOLUTION","0")=="1" ? (16,32,32,64,384) : (16,32,32,64)
for n in resolutions
    GC.gc(true)
    result=@timed Hikari.radiative_volume(path;mass_unit=3e24,
        black_hole_mass=6.5e9*1.98847e33,resolution=n,extent=15f0)
    println("LOADER_SAMPLE resolution=",n," seconds=",result.time,
        " bytes=",result.bytes," gc_seconds=",result.gctime)
    flush(stdout)
end
