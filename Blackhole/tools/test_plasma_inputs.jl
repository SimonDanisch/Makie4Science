# Focused tests in the ONE application environment, after project.jl/stills.jl.
using Test
"""
A random native plasma pair on a small grid out to `extent`: shells from inside
the horizon, colatitude rows that shift from shell to shell like FMKS ones, sparse
emission, speeds up to 0.97c, and inside the horizon the radial infall at the
0.999c cap that `Hikari.native_radiative_volume` gives it.
"""
function native_fixture(rng; nphi=8, ntheta=7, nr=9, extent=6f0)
    log_r0=log(0.9f0); dlog_r=Float32(log(extent/0.9f0)/(nr-1))
    theta=Float32[π*((j-0.5f0)/ntheta+0.03f0*sin(1.7f0*i)*sin(π*(j-0.5f0)/ntheta)/ntheta) for i in 1:nr,j in 1:ntheta]
    grid=(; theta, log_r0, dlog_r, phi0=0.1f0, dphi=Float32(2π/nphi), extent=Float32(extent))
    function speed(k,j,i)
        exp(log_r0+(i-1)*dlog_r)>1f0 && return Vec3f(normalize(randn(rng,Vec3f))*0.97f0*rand(rng,Float32))
        θ,φ=theta[i,j],grid.phi0+(k-1)*grid.dphi
        return -0.999f0*Vec3f(sin(θ)*cos(φ),sin(θ)*sin(φ),cos(θ))
    end
    state()=merge(grid,(; density=rand(rng,Float32,nphi,ntheta,nr).*(rand(rng,Float32,nphi,ntheta,nr).>0.6f0),
        absorption=rand(rng,Float32,nphi,ntheta,nr).^4,
        velocity=[speed(k,j,i) for k in 1:nphi,j in 1:ntheta,i in 1:nr]))
    return state(),state()
end

function test_plasma_medium(film)
    @testset "space-time medium interpolated inputs" begin
        a,b=native_fixture(film.Random.Xoshiro(3))
        function medium(w)
            film.SpacetimeMedium(a;next=b,time_mix=w,snapshot_key=UInt64(1),next_snapshot_key=UInt64(2),doppler=0f0)
        end
        p=Point3f(2.5f0,0.3f0,0.2f0);d=Vec3f(0,1,0)
        tab=Hikari.get_srgb_table();wl=Hikari.sample_wavelengths_visible(0.3f0)
        properties(w)=Hikari.sample_point(medium(w),nothing,tab,p,wl,d)
        x,y,m=properties(0f0),properties(1f0),properties(0.5f0)
        @test x.σ_a[1]!=y.σ_a[1]
        @test all(isapprox.(m.σ_a.data,(x.σ_a.data .+ y.σ_a.data)./2;rtol=1f-5))
        @test_throws ArgumentError medium(2f0)
        smaller=merge(a,(;density=a.density[2:end,:,:],absorption=a.absorption[2:end,:,:],velocity=a.velocity[2:end,:,:]))
        @test_throws DimensionMismatch film.SpacetimeMedium(film.pack_cells(a);cells_next=film.pack_cells(smaller),
            a.theta,a.log_r0,a.dlog_r)
        @test_throws DimensionMismatch film.SpacetimeMedium(merge(a,(;theta=a.theta[1:end-1,:])))
        # Existing Raycore slots must be retained for the lifetime of the scene.
        storage=Raycore.MultiTypeSet(Mantle.defaultbackend())
        key=push!(storage,medium(0f0))
        arrays=copy(storage.texture_gpu_arrays)
        Raycore.update!(storage,key,medium(0.5f0))
        @test storage[key].time_mix==0.5f0
        @test length(storage.texture_gpu_arrays)==length(arrays)
        @test all(x===y for (x,y) in zip(arrays,storage.texture_gpu_arrays))
        @test storage[key].snapshot_key==1
    end
    @testset "majorant grid bounds the shader's absorption" begin
        # A random relativistic plasma pair: every point of every cell, at any
        # time mix, direction, Doppler weight and gas scale, must stay under its
        # cell's majorant, right down to the horizon.
        rng=film.Random.Xoshiro(7)
        a,b=native_fixture(rng)
        E=a.extent; res=5
        cells=film.grmhd_pair_cells(a,b;res)
        tab=Hikari.get_srgb_table();wl=Hikari.sample_wavelengths_visible(0.3f0)
        worst=0f0; tightest=0f0; uncovered=0
        for gas in (1f0,0.3f0), dop in (1f0,0.4f0)
            voxels=film.majorant_voxels(cells,gas,0.5f0)
            # Without emission sampling: the absorption bound alone.
            absorption=film.majorant_voxels(cells,gas,0.5f0;floor_fraction=Inf32)
            for w in (0f0,0.4f0,1f0)
                m=film.SpacetimeMedium(a;next=b,time_mix=w,density_bounds=Hikari.Bounds3(Point3f(-E),Point3f(E)),
                    bounds=Hikari.Bounds3(Point3f(-E-1),Point3f(E+1)),gas_scale=gas,doppler=dop)
                for t in 1:4000
                    r=isodd(t) ? 1f0+0.2f0*rand(rng,Float32) : 1f0+(E-1f0)*rand(rng,Float32)
                    p=Point3f(normalize(randn(rng,Vec3f))*r)
                    d=normalize(randn(rng,Vec3f))
                    σ=Hikari.sample_point(m,nothing,tab,p,wl,d).σ_a[1]
                    c=clamp.(floor.(Int,(p .+ E) ./ (2E) .* res),0,res-1)
                    i=1+c[1]+res*(c[2]+res*c[3])
                    if absorption[i]>0
                        worst=max(worst,σ/voxels[i],σ/absorption[i])
                        tightest=max(tightest,σ/absorption[i])
                    else
                        uncovered+=σ>0
                    end
                end
            end
        end
        @test worst<=1f0
        @test uncovered==0
        @test tightest>0.05f0  # the absorption bound is not vacuous
        # Empty space takes no samples at all.
        @test all(iszero,film.majorant_voxels((;absorption=zeros(Float32,2,2,2),emission=zeros(Float32,2,2,2)),1f0,0.5f0))
        @test all(iszero,film.grmhd_pair_cells(film.empty_plasma(),film.empty_plasma();res=3).absorption)
    end
    @testset "a stencil's box holds its sector" begin
        rng=film.Random.Xoshiro(5)
        for _ in 1:200
            r0=0.5+10rand(rng); r1=r0*(1+0.3rand(rng))
            θ0=π*rand(rng); θ1=min(π,θ0+0.5rand(rng))
            φ0=4π*rand(rng)-2π; φ1=φ0+0.8rand(rng)
            lo,hi=film.sector_box((r0,r1),(θ0,θ1),(φ0,φ1))
            for _ in 1:50
                r=r0+(r1-r0)rand(rng); θ=θ0+(θ1-θ0)rand(rng); φ=φ0+(φ1-φ0)rand(rng)
                p=r .* (sin(θ)cos(φ),sin(θ)sin(φ),cos(θ))
                @test all(lo .- 1e-12 .<= p .<= hi .+ 1e-12)
            end
        end
    end
end

function test_plasma_render(project; frames=(0,5,10))
    seq=VE.loadproject(project)
    VE.usebackend!(RayMakie)
    engine=VE.FxEngine(Mantle.defaultbackend())
    readers=Dict{String,Any}()
    out=zeros(VE.RGB{VE.N0f8},seq.canvas...)
    clip=only(filter(c->c.track==1,seq.clips))
    # Exercise the actual loader/device path, not a previous successful master.
    VE.invalidateclip!(clip;frames=[VE.sourceframe(clip,n) for n in frames])
    target=nothing;screen=nothing;arrays=nothing;media=nothing
    @testset "persistent animated plasma scene" begin
        try
            VE.withfinalscenes(seq) do
                for frame in frames
                    VE.renderframe!(out,seq,frame,readers,engine)
                    @test any(c->c.r>0 || c.g>0 || c.b>0,out)
                    if target===nothing
                        target=clip.source.live.target;screen=clip.source.live.screen
                        state=only(filter(s->s.hikari_scene!==nothing && !isempty(s.hikari_scene.media),screen.scene_states))
                        media=state.hikari_scene.media
                        arrays=copy(media.texture_gpu_arrays)
                    else
                        @test clip.source.live.target===target
                        @test clip.source.live.screen===screen
                        @test length(media.texture_gpu_arrays)==length(arrays)
                        @test all(x===y for (x,y) in zip(arrays,media.texture_gpu_arrays))
                    end
                    # Hikari owns a single adapted media set per scene state.
                    # Model-level tests above verify its texture-slot reuse.
                    VE.saveproject(project,seq;checkpoint=false)
                    save(joinpath(dirname(project),"frame_$(frame).png"),permutedims(out))
                    println("PLASMA INPUT FRAME ",frame," rendered");flush(stdout)
                end
            end
        finally
            VE.emptyengine!(engine)
            foreach(close,values(readers))
            foreach(c->close(c.source),seq.clips)
        end
    end
    return nothing
end
