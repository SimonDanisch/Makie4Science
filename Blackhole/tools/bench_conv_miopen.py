"""Time OIDN-large 3x3 conv+bias+ReLU layer shapes through PyTorch/MIOpen (fp16)."""
import time, torch
torch.backends.cudnn.benchmark = True
shapes = [(1920, 1088, 9, 64), (1920, 1088, 64, 64), (960, 544, 64, 96), (960, 544, 96, 96),
          (480, 272, 128, 128), (960, 544, 192, 96), (1920, 1088, 105, 64), (1920, 1088, 64, 3)]
for fmt in (torch.contiguous_format, torch.channels_last):
    for W, H, ci, co in shapes:
        conv = torch.nn.Conv2d(ci, co, 3, padding=1).half().cuda().to(memory_format=fmt)
        x = torch.randn(1, ci, H, W, device="cuda", dtype=torch.half).to(memory_format=fmt)
        with torch.no_grad():
            for _ in range(5): torch.relu(conv(x))
            torch.cuda.synchronize(); n = 20; t = time.perf_counter()
            for _ in range(n): torch.relu(conv(x))
            torch.cuda.synchronize(); ms = 1000 * (time.perf_counter() - t) / n
        print(f"{'NHWC' if fmt is torch.channels_last else 'NCHW'} {W}x{H} {ci:>3}->{co:<3} {ms:7.2f} ms {2*W*H*9*ci*co/ms/1e9:6.1f} TFLOPS", flush=True)
