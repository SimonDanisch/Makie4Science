# Decode and inspect native diagnostic bytes; never create a farm receipt.
@assert basename(dirname(Base.active_project()))=="Science4Makie"
length(ARGS) in (1,2) || error("usage: check_farm_probe.jl RESULT.wire [QA_DIRECTORY]")
using VideoEditor
include("check_hdr_masters.jl")
const VE=VideoEditor
function check_farm_probe(path; output=path*".qa")
header,payload=open(VE.receivemessage,path)
result=VE.farmresult(header,payload)
pixels=VE.PNGFiles.load(IOBuffer(result.png))
@assert size(pixels)==(720,1280)
@assert any(p->p.r>0 || p.g>0 || p.b>0,pixels)
ispath(output) && error("Refusing to overwrite QA outputs: $output")
mkpath(output)
write(joinpath(output,"frame.png"),result.png)
masters=0
for layer in result.layers
    isempty(layer.hdr) && continue
    path=joinpath(output,"track-$(layer.track)-$(layer.id)-$(layer.frame).vehdr")
    write(path,layer.hdr)
    check_hdr_master(path)
    masters+=1
end
@assert masters>0 "Probe did not return a linear HDR master"
println("NATIVE_PROBE_QA_PASS frame=",result.frame," seconds=",result.seconds,
    " masters=",masters," output=",output)
return output
end
check_farm_probe(ARGS[1];output=length(ARGS)==2 ? ARGS[2] : ARGS[1]*".qa")
