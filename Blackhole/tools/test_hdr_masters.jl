using Test
include("check_hdr_masters.jl")

@testset "HDR numerical QA" begin
    V=VideoEditor
    mktempdir() do dir
        path=joinpath(dir,"test.vehdr")
        frame=(color=fill(V.RGB{Float32}(0.1,0.2,0.3),2,2),
            albedo=fill(V.RGB{Float32}(0.2,0.3,0.4),2,2),
            normal=fill(V.Vec3f(0,0,1),2,2),depth=fill(Inf32,2,2),
            coverage=zeros(Float32,2,2),overlay=fill(V.RGBA{Float32}(0,0,0,0),2,2),
            metadata=Dict{String,Any}())
        V.writerenderframe(path,frame)
        @test isnothing(check_hdr_master(path;dimensions=(2,2)))
        @test_throws AssertionError check_hdr_master(path;dimensions=(3,3))
        for key in (:color,:albedo,:normal,:coverage,:overlay)
            values=reinterpret(Float32,vec(getproperty(frame,key)))
            old=values[1]
            values[1]=NaN32
            V.writerenderframe(path,frame)
            @test_throws AssertionError check_hdr_master(path;dimensions=(2,2))
            values[1]=old
        end
        frame.depth[1]=-Inf32
        V.writerenderframe(path,frame)
        @test_throws AssertionError check_hdr_master(path;dimensions=(2,2))
        frame.depth[1]=Inf32
        frame.coverage[1]=1.01f0
        V.writerenderframe(path,frame)
        @test_throws AssertionError check_hdr_master(path;dimensions=(2,2))
        frame.coverage[1]=0
        frame.overlay[1]=V.RGBA{Float32}(0,0,0,1.1)
        V.writerenderframe(path,frame)
        @test_throws AssertionError check_hdr_master(path;dimensions=(2,2))
    end
end
