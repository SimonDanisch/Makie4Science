# Target the package's existing convolution reference tests, in the one app root.
@assert basename(dirname(Base.active_project()))=="Science4Makie"
using Test, Mantle, OIDNRunner
using .OIDNRunner.DNNKernels
path=joinpath(dirname(dirname(Base.find_package("OIDNRunner"))),"test","runtests.jl")
statements=Meta.parseall(read(path,String)).args
reference=only(filter(x->x isa Expr && x.head==:function &&
    x.args[1] isa Expr && x.args[1].args[1]===:refconv,statements))
targeted=only(filter(x->x isa Expr && x.head==:macrocall &&
    any(==("every convolution tiling matches a CPU reference"),x.args),statements))
Core.eval(@__MODULE__,reference)
Core.eval(@__MODULE__,targeted)
