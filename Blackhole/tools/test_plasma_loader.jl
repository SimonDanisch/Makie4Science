# Run in Science4Makie ROOT. Compare against fields captured before relocation.
using Test, Serialization
function test_plasma_loader(paths,baseline_path)
    @testset "upstream snapshot reader and Hikari radiative adapter" begin
        baseline=deserialize(baseline_path)
        ref=VE.FileSeriesRef(paths,[0.,2.,5.];package="Hikari",
            loader=:radiative_volume,requires=["GRMHDSnapshots"],
            options=Dict("resolution"=>16,"mass_unit"=>3e24,"black_hole_mass"=>6.5e9*1.98847e33))
        series=VE.FileSeries(ref)
        blend=VE.sampleinput(series,1.)
        G=Base.require(Main,:GRMHDSnapshots)
        @test !isdefined(G,:radiative_volume)
        @test !isdefined(G,:synchrotron_jν)
        @test Base.get_extension(Hikari,:HikariGRMHDSnapshotsExt)!==nothing
        @test blend.weight==0.5f0
        @test VE.sampleinput(series,0.).a===blend.a
        for (i,t) in enumerate((0.,2.,5.))
            b=VE.sampleinput(series,t)
            actual=i==3 ? b.b : b.a
            for field in (:density,:absorption,:velocity,:max_absorption,:emissivity_peak,:extent)
                @test getproperty(actual,field)==getproperty(baseline[i],field)
            end
        end
        @test length(series.loaded)==2
        decoded=VE.inputreffromdict(VE.inputrefdict(ref))
        @test decoded.requires==["GRMHDSnapshots"]
        @test VE.inputpackages(decoded)==["Hikari","GRMHDSnapshots"]
        fixed=Base.invokelatest(Hikari.radiative_volume,paths[2];resolution=16,normalization=baseline[1].emissivity_peak,
            mass_unit=3e24,black_hole_mass=6.5e9*1.98847e33)
        @test fixed.absorption==baseline[2].absorption
        @test fixed.velocity==baseline[2].velocity
        @test fixed.emissivity_peak==baseline[2].emissivity_peak
        @test fixed.density ≈ baseline[2].density .* (baseline[2].emissivity_peak/baseline[1].emissivity_peak)
    end
end
