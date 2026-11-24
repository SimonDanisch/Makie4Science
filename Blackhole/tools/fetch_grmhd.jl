# Run ONLY in the Science4Makie root environment. The 144-MB public snapshot
# is a checked input asset, not a vendored package or a large Git blob.
using Downloads, SHA

function fetch_grmhd()
    project=Base.active_project()
    project!==nothing && basename(dirname(project))=="Science4Makie" ||
        error("Use the single Science4Makie root Julia environment")
    path=normpath(joinpath(@__DIR__,"..","assets","grmhd","torus.out0.05000.h5"))
    expected="3a8460de564c3d5099f6c3c823f2e93be9ce8e2bcfc7dc1dd89a9c6208b74cd7"
    checksum(p)=bytes2hex(open(SHA.sha256,p))
    if isfile(path)
        checksum(path)==expected || error("Existing GRMHD asset has a different checksum; not overwriting: $path")
        return path
    end
    mkpath(dirname(path))
    temp,io=mktemp(dirname(path));close(io)
    try
        Downloads.download("https://thz.astro.illinois.edu/v3_grmhd/MAD/a0/288x128x128/torus.out0.05000.h5",temp)
        checksum(temp)==expected || error("Downloaded GRMHD snapshot failed SHA-256 verification")
        mv(temp,path) # no overwrite if another process installed the asset
    finally
        isfile(temp) && rm(temp) # only our own temporary download, never an input
    end
    path
end
