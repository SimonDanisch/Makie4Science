@assert Base.active_project()==normpath(joinpath(@__DIR__,"..","..","Project.toml"))
using Test, Hikari, GRMHDSnapshots
ext=Base.get_extension(Hikari,:HikariGRMHDSnapshotsExt)
repo=dirname(dirname(Base.find_package("Hikari")))
# Reintroduce only the captured-module lookup in the current physical formula,
# so this fixture keeps working after the fix is committed or shallow-cloned.
reference=read(joinpath(repo,"ext","HikariGRMHDSnapshotsExt.jl"),String)
@assert count("GRMHDSnapshots.sample_field",reference)==3
reference=replace(reference,"GRMHDSnapshots.sample_field"=>"G.sample_field")
reference=replace(reference,"    majorant_exponent = Float32((ep.p+2)/4)\n"=>"",
    "^majorant_exponent"=>"^Float32((ep.p+2)/4)")
module_expr=only(filter(x->x isa Expr && x.head===:module,Meta.parseall(reference).args))
definition=deepcopy(only(filter(x->x isa Expr && x.head===:function &&
    occursin("Hikari.radiative_volume",string(x.args[1])),module_expr.args[3].args)))
definition.args[1].args[1]=:legacy_radiative_volume
Core.eval(ext,definition)
legacy=getproperty(ext,:legacy_radiative_volume)
path=joinpath(@__DIR__,"..","assets","grmhd","torus.out0.05000.h5")
@testset "Type-stable snapshot interpolation preserves physical fields" begin
    for normalization in (nothing,3.4f0), n in (16,32,64)
        GC.gc(true)
        old=@timed Base.invokelatest(legacy,path;mass_unit=3e24,
            black_hole_mass=6.5e9*1.98847e33,resolution=n,extent=15f0,normalization)
        GC.gc(true)
        new=@timed Hikari.radiative_volume(path;mass_unit=3e24,
            black_hole_mass=6.5e9*1.98847e33,resolution=n,extent=15f0,normalization)
        for key in (:density,:absorption,:velocity,:max_absorption,:emissivity_peak)
            @test isequal(getproperty(old.value,key),getproperty(new.value,key))
        end
        println("LOADER_COMPARE resolution=",n," old_seconds=",old.time,
            " new_seconds=",new.time," old_bytes=",old.bytes," new_bytes=",new.bytes)
        n==64 && @test new.bytes<old.bytes
    end
    for p in (2.25,3.5)
        emission_params=Hikari.EmissionParams(;p)
        old=Base.invokelatest(legacy,path;mass_unit=3e24,
            black_hole_mass=6.5e9*1.98847e33,resolution=32,emission_params)
        new=Hikari.radiative_volume(path;mass_unit=3e24,
            black_hole_mass=6.5e9*1.98847e33,resolution=32,emission_params)
        for key in (:density,:absorption,:velocity,:max_absorption,:emissivity_peak)
            @test isequal(getproperty(old,key),getproperty(new,key))
        end
    end
end
