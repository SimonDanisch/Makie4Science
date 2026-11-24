using Test, Makie
function test_terrain(film)
    @testset "terrain utilities survive independent-renderer removal" begin
        # Golden Float32 values from the terrain helper in project commit25e5465.
        @test Base.invokelatest(film.fbm,Vec3f(0),Int32(1))===0.41269132f0
        @test Base.invokelatest(film.fbm,Vec3f(-17.5,-3,0.37),Int32(4))===0.41639996f0
        @test Base.invokelatest(film.fbm,Vec3f(0.37,0.5,1.2),Int32(11))===0.43439135f0
        @test Base.invokelatest(film.hash01,Int32(0),Int32(0),Int32(0),Int32(9))===0.83732784f0
        for (x,y) in ((0f0,0f0),(100f0,200f0),(-5000f0,7000f0))
            h=Base.invokelatest(film.ground_height,x,y)
            @test isfinite(h)
            @test all(isfinite,Base.invokelatest(film.ground_colour,x,y,h))
        end
        @test !isfile(joinpath(@__DIR__,"..","film","relativity.jl"))
    end
    return nothing
end
