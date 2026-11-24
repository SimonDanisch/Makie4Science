# Run in the Science4Makie root session after project.jl; no image rendering.
using Test, LinearAlgebra
import Hikari

function test_photon_ring(film;step_scale=1f0)
    @testset "Photon-ring annotation follows production critical rays" begin
        uniform=(;density=fill(0.1f0,2,2,2),absorption=fill(0.01f0,2,2,2),
            velocity=fill(film.Vec3f(0),2,2,2),theta=Float32[0 π;0 π],
            log_r0=0f0,dlog_r=Float32(Base.log(10)),phi0=0f0,dphi=Float32(π))
        m=film.SpacetimeMedium(uniform;step_scale,
            bounds=Hikari.Bounds3(film.Point3f(-18),film.Point3f(18)))
        # Enter the existing spherical medium, then use exactly the native
        # production integrator callbacks, without a second ray/image renderer.
        function captured(b)
            p=film.Point3f(-sqrt(18f0^2-b^2)+1f-5,b,0)
            d=film.Vec3f(1,0,0)
            for _ in 1:8000
                h=Hikari.medium_step_limit(m,p,d)
                chord=Hikari.medium_start_direction(m,p,d,h)
                p=film.Point3f(p+h*chord)
                norm(p)<1 && return true
                d=Hikari.medium_end_direction(m,p,chord,h,h)
                norm(p)>18 && return false
            end
            error("Critical-ray check did not terminate")
        end
        lo,hi=2.58f0,2.62f0
        @test captured(lo)
        @test !captured(hi)
        for _ in 1:16
            mid=(lo+hi)/2
            captured(mid) ? (lo=mid) : (hi=mid)
        end
        impact=(Float64(lo)+hi)/2
        predicted=inv(sqrt(inv(Float64(film.PHOTON_RING)^2)+inv(18.0^3)))
        println("Critical incoming impact: production=",impact," analytic=",predicted)
        @test abs(impact-predicted)<0.001
        for distance in (23.,26.,28.,32.), elevation in (-32.,4.,73.), azimuth in (-105.,0.,85.)
            eye=distance .* (cosd(elevation)*cosd(azimuth),cosd(elevation)*sind(azimuth),sind(elevation))
            cam=film.BHCamera(film.Pose(eye,(0,0,0);fov=30))
            contour=film.photon_ring_contour(cam,(1920,1080))
            radii=[norm(p-film.Point2f(960,540)) for p in contour]
            expected=540/cam.tanhalf*impact/sqrt(distance^2-impact^2)
            @test first(contour)≈last(contour) atol=0.001
            @test maximum(radii)-minimum(radii)<0.001
            @test maximum(abs.(radii.-expected))<0.15 # production agreement at 1080p
        end
    end
end
