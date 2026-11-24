# CPU-only protocol/backpressure tests in the sole Science4Makie root.
using Test, Distributed, VideoEditor
const VE=VideoEditor
include("recording_lan.jl")
include("farm_policy.jl")

struct TransferFixture
    sequence::VE.Sequence
    png::Vector{UInt8}
    fail::Int
end
function VE.farmframes!(r::TransferFixture,frames)
    [(n==r.fail && error("injected render failure");
      (frame=n,png=r.png,seconds=0.01,layers=VE.FarmLayer[])) for n in frames]
end
io=IOBuffer();VE.PNGFiles.save(io,fill(VE.RGB{VE.N0f8}(0,0,0),4,4));png=take!(io)
fixture=TransferFixture(VE.Sequence(VE.Clip[],30),png,-1)
keep=Set{Tuple{UInt64,Int}}()

@testset "transfer parent is lightweight and policy excludes Bosgame" begin
    @test !isdefined(RecordingLAN,:VideoEditor)
    @test !ScienceFarmPolicy.allowed("Bosgame")
    @test !ScienceFarmPolicy.allowed("sim-bosgame (lan host)")
    @test ScienceFarmPolicy.allowed("Desktop")
end
@testset "producer queue is bounded and cancellation stops it" begin
  mktempdir() do spool
    producer=@async RecordingLAN.produce!(spool,0:7,keep,2,fixture)
    @test timedwait(()->count(endswith(".ready"),readdir(spool))==2,10)==:ok
    sleep(.05)
    @test count(endswith(".ready"),readdir(spool))==2
    @test !istaskdone(producer)
    touch(joinpath(spool,"cancel"));wait(producer)
    @test istaskdone(producer)
  end
end
@testset "batch streams in order and propagates rendering failure" begin
    global renderer=fixture # this test is run in a fresh process, never a live renderer session
    wire=IOBuffer()
    RecordingLAN.streambatch!(wire,myid(),collect(0:7),keep)
    seekstart(wire)
    @test [first(RecordingLAN.receivemessage(wire))["frame"] for _ in 0:7]==collect(0:7)
    @test eof(wire)
    global renderer=TransferFixture(fixture.sequence,png,3)
    partial=IOBuffer()
    @test_throws Exception RecordingLAN.streambatch!(partial,myid(),collect(0:7),keep)
    seekstart(partial)
    @test [first(RecordingLAN.receivemessage(partial))["frame"] for _ in 0:2]==collect(0:2)
    @test eof(partial)
end
