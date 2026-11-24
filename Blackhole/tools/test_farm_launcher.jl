# Run in the ONE Science4Makie root, never tools/ or a package test environment.
using Test
include("farm_client.jl")
@testset "application farm clients retain the sole environment" begin
    mktempdir() do cache
        c=ScienceFarmLauncher.client(["all","127.0.0.1:7600",cache])
        @test c.project==dirname(Base.active_project())
        @test c.root==cache
        @test c.gpus=="all"
        @test c.port==7600
        @test_throws ArgumentError ScienceFarmLauncher.client(String[])
    end
end
@testset "small-host GC target is explicit and inherited by child commands" begin
    @test ScienceFarmLauncher.workerheap(;memory=32*1024^3,explicit=0)=="4G"
    @test ScienceFarmLauncher.workerheap(;memory=8*1024^3,explicit=0)=="1G"
    @test ScienceFarmLauncher.workerheap(;memory=128*1024^3,explicit=0)===nothing
    @test ScienceFarmLauncher.workerheap(;memory=32*1024^3,explicit=6*1024^3)==string(6*1024^3)
    mktempdir() do cache
        c=ScienceFarmLauncher.client(["all","127.0.0.1:7600",cache];heap_size_hint="4G")
        @test collect(c.juliacmds[string(VERSION)])==[
            joinpath(Sys.BINDIR,Base.julia_exename()),"--compiled-modules=existing","--heap-size-hint=4G"]
        @test c.project==dirname(Base.active_project())
        code="print(Base.JLOptions().heap_size_hint,\"\\n\",Base.active_project())"
        observed=split(read(`$(c.juliacmds[string(VERSION)]) --startup-file=no --project=$(c.project) -e $code`,String),'\n')
        @test observed==[string(4*1024^3),Base.active_project()]
        @test read(`$(c.juliacmds[string(VERSION)]) --startup-file=no --project=$(c.project) -e "print(Base.JLOptions().use_compiled_modules)"`,String)=="2"
        @test_throws ArgumentError ScienceFarmLauncher.client(["all","127.0.0.1:7600",cache];compiled_modules="invalid")
    end
end
@testset "snapshot preparation uses bounded CPU parallelism" begin
    env=Dict{String,String}()
    @test ScienceFarmLauncher.workerthreads!(env;cpus=32)=="8"
    @test ScienceFarmLauncher.workerthreads!(Dict{String,String}();cpus=4)=="2"
    @test ScienceFarmLauncher.workerthreads!(Dict{String,String}();cpus=1)=="1"
    @test ScienceFarmLauncher.workerthreads!(Dict("JULIA_NUM_THREADS"=>"3,1");cpus=32)=="3,1"
end
@testset "small-host precompile concurrency preserves explicit settings" begin
    @test ScienceFarmLauncher.workerprecompile!(Dict{String,String}();memory=32*1024^3)=="1"
    large=Dict{String,String}()
    @test ScienceFarmLauncher.workerprecompile!(large;memory=128*1024^3)===nothing
    @test !haskey(large,"JULIA_NUM_PRECOMPILE_TASKS")
    @test ScienceFarmLauncher.workerprecompile!(Dict("JULIA_NUM_PRECOMPILE_TASKS"=>"3");memory=32*1024^3)=="3"
end
