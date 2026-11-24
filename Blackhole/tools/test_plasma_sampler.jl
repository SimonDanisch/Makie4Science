# Run only in the Science4Makie application root, after project.jl/stills.jl,
# with `film = loadfilm()` and GRMHDSnapshots loaded.
@assert basename(dirname(Base.active_project()))=="Science4Makie"
using Test, Random, Hikari, GeometryBasics, GRMHDSnapshots, LinearAlgebra

# The medium samples the snapshot's own grid with GRMHDSnapshots' stencil,
# rewritten for device arrays. It must reproduce `sample_field` everywhere the
# gas is not faded out, and stay safe for any input.
function test_plasma_sampler(film)
    @testset "native stencil reproduces GRMHDSnapshots" begin
        units=(; M_unit=3e24, MBH=6.5e9*1.98847e33)
        snap=GRMHDSnapshots.load_snapshot(film.GRMHD_FILE; units...)
        reference=Hikari.emissivity_grid(snap,Hikari.EmissionParams())
        plasma=Hikari.native_radiative_volume(film.GRMHD_FILE;normalization=nothing,
            mass_unit=units.M_unit,black_hole_mass=units.MBH)
        m=film.SpacetimeMedium(plasma)
        rng=Xoshiro(3)
        scale=maximum(reference)*1e-6
        worst=0.0
        for _ in 1:20000
            q=Vec3f(normalize(randn(rng,Vec3f))*(1f0+9.8f0*rand(rng,Float32)))
            ours=film.native_value(film.native_stencil(m,m.theta,m.theta_lut,q),m.cells)[1]*plasma.emissivity_peak
            theirs=GRMHDSnapshots.sample_field(snap,reference,(2 .* Float64.(q))...)
            worst=max(worst,abs(ours-theirs)/(abs(theirs)+scale))
        end
        @test worst<1e-3
        for q in (Vec3f(0),Vec3f(NaN32),Vec3f(Inf32),Vec3f(-Inf32),Vec3f(0.5f0,0,0),Vec3f(100,0,0))
            @test film.native_stencil(m,m.theta,m.theta_lut,q).w==0f0
            @test film.native_value(film.native_stencil(m,m.theta,m.theta_lut,q),m.cells)==zero(film.PlasmaCell)
        end
        # The lookup brackets every colatitude as a binary search does, also
        # exactly at the grid's colatitudes and at the poles.
        ntheta=size(m.theta,2)
        for i in 1:size(m.theta,1)
            row=m.theta[i,:]
            for θ in [rand(rng,Float32,200).*Float32(π); row; prevfloat.(row); 0f0; Float32(π)]
                @test first(film.theta_bracket(m.theta,m.theta_lut,i,θ,ntheta))==clamp(searchsortedlast(row,θ),1,ntheta-1)
            end
        end
    end
end
