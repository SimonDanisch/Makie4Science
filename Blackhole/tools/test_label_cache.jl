# Verify the real final project's label-only edit against its immutable farm job.
using Test
function test_label_cache(seq,job;frame=846)
    picture=only(filter(c->c.track==1 && get(c.source.build["args"],"beat","")=="a1_black_hole",seq.clips))
    labels=only(filter(c->c.track==2 && get(c.source.build["args"],"beat","")=="a1_black_hole",seq.clips))
    sf=VE.sourceframe(picture,frame)
    raw=VE.sourcecache(picture)
    ink=VE.trackcache(labels)
    @testset "label correction retains traced farm masters" begin
        @test VE.cachevalid(raw,picture.id,sf)
        @test VE.cachevalid(ink,labels.id,sf)
        masterhash=VE.filehash(VE.cachefile(raw,picture.id,sf))
        labelhash=VE.filehash(VE.cachefile(ink,labels.id,sf))
        receipt=VE.JSON.parsefile(VE.farmreceiptpath(job.directory,frame))
        oldlabels=only(filter(l->l["track"]==2,receipt["layers"]))
        @test labelhash!=oldlabels["sha256"]
        VE.adoptfarmcache!(seq,job)
        @test VE.filehash(VE.cachefile(raw,picture.id,sf))==masterhash
        @test VE.filehash(VE.cachefile(ink,labels.id,sf))==labelhash
        @test labels.source.build["args"]["disk_label_radius"]==2.8f0
        @test labels.source.build["args"]["doppler_label_radius"]==3f0
    end
    return nothing
end
