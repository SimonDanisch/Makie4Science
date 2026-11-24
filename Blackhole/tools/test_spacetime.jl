# Include in the Science4Makie ROOT session after project.jl/stills.jl.
using Test, LinearAlgebra

function test_spacetime(film)
    @testset "Spacetime medium: physical data and transport" begin
        G = Hikari
        @test G.electron_density(G.MagneticEtaNe(0.01),10.,1.,1.,2.5,10.) ≈
            0.01 * 10^2/(8π) * 0.5/(1.5 * G.MEC2 * 10)
        @test G.synchrotron_jν(1e5,10.,2.5,2.3e11,10.,1e5) ≈ 1.212181764287848e-18 rtol=1e-6
        a = G.synchrotron_αν(1e5,10.,2.5,2.3e11,10.,1e5)
        @test isfinite(a) && a > 0
        @test G.synchrotron_αν(2e5,10.,2.5,2.3e11,10.,1e5) ≈ 2a
        @test G.synchrotron_αν(1e5,20.,2.5,2.3e11,10.,1e5) ≈ 2^2.25 * a
        @test G.synchrotron_αν(1e5,10.,2.5,4.6e11,10.,1e5) ≈ 2^-3.25 * a
        plasma = film.grmhd_plasma()
        @test all(isfinite,plasma.density) && all(>=(0),plasma.density)
        @test all(isfinite,plasma.absorption) && all(>=(0),plasma.absorption)
        @test maximum(norm,plasma.velocity) < 1
        # Hikari stores a source function: sigma_a*Le must scale linearly
        # with the physical emissivity, not accidentally square the density.
        tab=Hikari.get_srgb_table(); wl=Hikari.sample_wavelengths_visible(0.3f0)
        # One uniform cell between r = 1 and r = 10.
        uniform(j)=(; density=fill(j,2,2,2), absorption=fill(0.01f0,2,2,2), velocity=fill(Vec3f(0),2,2,2),
            theta=Float32[0 π; 0 π], log_r0=0f0, dlog_r=Float32(log(10)), phi0=0f0, dphi=Float32(π))
        m1=film.SpacetimeMedium(uniform(0.1f0);doppler=0f0)
        m2=film.SpacetimeMedium(uniform(0.2f0);doppler=0f0)
        p=Point3f(4,0,0); d=Vec3f(0,1,0)
        mp1=Hikari.sample_point(m1,nothing,tab,p,wl,d)
        mp2=Hikari.sample_point(m2,nothing,tab,p,wl,d)
        @test all(isapprox.((mp2.σ_a*mp2.Le).data,2 .* (mp1.σ_a*mp1.Le).data;rtol=1f-5))
        # Bounds around the test rays: outside its bounds the medium does not bend.
        reach = Hikari.Bounds3(Point3f(-61), Point3f(61))
        m = film.SpacetimeMedium(plasma; bounds=reach)
        function orbit(b; h=0.01f0)
            p=Point3f(-60,b,0); d=Vec3f(1,0,0)
            for _ in 1:30000
                chord=Hikari.medium_start_direction(m,p,d,h)
                p=Point3f(p+h*chord)
                norm(p)<1 && return :captured
                d=Hikari.medium_end_direction(m,p,chord,h,h)
                isapprox(norm(d),1;atol=2f-6) || error("non-unit direction")
                norm(p)>61 && return :escaped
            end
            :unfinished
        end
        @test orbit(2.4f0) === :captured
        @test orbit(2.8f0) === :escaped
        @test orbit(2.4f0;h=0.005f0) === :captured
        @test orbit(2.8f0;h=0.005f0) === :escaped
        # Test the PRODUCTION adaptive step, not just tiny reference steps.
        # Critical impact from infinity is 3sqrt(3)/2; starting at r=60 adds
        # less than 0.01%. The drift-then-kick prototype missed this by ~5%.
        function adaptive(b)
            p=Point3f(-60,b,0);d=Vec3f(1,0,0)
            for _ in 1:2000
                h=Hikari.medium_step_limit(m,p,d)
                chord=Hikari.medium_start_direction(m,p,d,h)
                p=Point3f(p+h*chord)
                norm(p)<1 && return :captured
                d=Hikari.medium_end_direction(m,p,chord,h,h)
                norm(p)>61 && return :escaped
            end
            :unfinished
        end
        @test adaptive(2.59f0) === :captured
        @test adaptive(2.61f0) === :escaped
        @test film.native_value(film.native_stencil(m,m.theta,m.theta_lut,Vec3f(100)),m.cells) == zero(film.PlasmaCell)
        @test Hikari.medium_step_limit(m,Point3f(2,0,0),Vec3f(1,0,0)) <
              Hikari.medium_step_limit(m,Point3f(10,0,0),Vec3f(1,0,0))
        fine = film.SpacetimeMedium(plasma; bounds=reach, step_scale=0.5f0)
        @test Hikari.medium_step_limit(film.SpacetimeMedium(plasma),Point3f(20,0,0),Vec3f(1,0,0)) == Inf32
        @test Hikari.medium_step_limit(fine,Point3f(2,0,0),Vec3f(1,0,0)) ==
              0.5f0 * Hikari.medium_step_limit(m,Point3f(2,0,0),Vec3f(1,0,0))
        @test_throws ArgumentError film.SpacetimeMedium(plasma;step_scale=0f0)
        @test isfinite(plasma.emissivity_peak) && plasma.emissivity_peak > 0
    end
end
