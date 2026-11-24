"""Benchmark released OIDN against the actual immutable VEHDR comparison frame.

This is a measurement tool only; the film's Julia pipeline is unchanged.
"""
import argparse
import ctypes as C
import json
import pathlib
import statistics
import time

import numpy as np


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--library", required=True)
    p.add_argument("--models", type=pathlib.Path, required=True)
    p.add_argument("--frame", type=pathlib.Path, required=True)
    p.add_argument("--device", choices=["cpu", "hip"], required=True)
    p.add_argument("--output", type=pathlib.Path, required=True)
    args = p.parse_args()
    with args.frame.open("rb") as f:
        assert f.read(7) == b"VEHDR1\n"
        n = int.from_bytes(f.read(4), "little")
        header = json.loads(f.read(n))
        w, h = header["dims"]
        images = {
            k: np.frombuffer(f.read(w * h * 12), dtype="<f4").copy().reshape(h, w, 3)
            for k in ("color", "albedo", "normal")
        }
    lib = C.CDLL(args.library)
    ptr, size = C.c_void_p, C.c_size_t
    signatures = {
        "oidnNewDevice": (ptr, [C.c_int]),
        "oidnCommitDevice": (None, [ptr]),
        "oidnNewFilter": (ptr, [ptr, C.c_char_p]),
        "oidnSetFilterInt": (None, [ptr, C.c_char_p, C.c_int]),
        "oidnSetFilterBool": (None, [ptr, C.c_char_p, C.c_bool]),
        "oidnSetSharedFilterData": (None, [ptr, C.c_char_p, ptr, size]),
        "oidnNewBufferWithStorage": (ptr, [ptr, size, C.c_int]),
        "oidnSetFilterImage": (None, [ptr, C.c_char_p, ptr, C.c_int, size, size, size, size, size]),
        "oidnWriteBuffer": (None, [ptr, size, size, ptr]),
        "oidnReadBuffer": (None, [ptr, size, size, ptr]),
        "oidnCommitFilter": (None, [ptr]),
        "oidnExecuteFilter": (None, [ptr]),
        "oidnReleaseFilter": (None, [ptr]),
        "oidnReleaseBuffer": (None, [ptr]),
        "oidnReleaseDevice": (None, [ptr]),
        "oidnGetDeviceError": (C.c_int, [ptr, C.POINTER(C.c_char_p)]),
    }
    for name, (restype, argtypes) in signatures.items():
        fn = getattr(lib, name)
        fn.restype, fn.argtypes = restype, argtypes
    dev = lib.oidnNewDevice(4 if args.device == "hip" else 1)

    def check():
        msg = C.c_char_p()
        err = lib.oidnGetDeviceError(dev, C.byref(msg))
        if err:
            raise RuntimeError((err, msg.value))

    lib.oidnCommitDevice(dev)
    check()
    nbytes = w * h * 12
    buffers = {k: lib.oidnNewBufferWithStorage(dev, nbytes, 2) for k in
               ("color", "albedo", "normal", "filtered_albedo", "filtered_normal", "output")}
    check()
    weights = []

    def make(kind, inputs):
        filt = lib.oidnNewFilter(dev, b"RT")
        blob = (args.models / (kind + ".tza")).read_bytes()
        weight = C.create_string_buffer(blob)
        weights.append(weight)
        lib.oidnSetSharedFilterData(filt, b"weights", weight, len(blob))
        lib.oidnSetFilterInt(filt, b"quality", 6)
        lib.oidnSetFilterBool(filt, b"hdr", kind.startswith("rt_hdr"))
        lib.oidnSetFilterBool(filt, b"cleanAux", True)
        for name, key in inputs.items():
            lib.oidnSetFilterImage(filt, name.encode(), buffers[key], 3, w, h, 0, 12, w * 12)
        lib.oidnCommitFilter(filt)
        check()
        return filt

    filters = [
        make("rt_alb_large", {"albedo": "albedo", "output": "filtered_albedo"}),
        make("rt_nrm_large", {"normal": "normal", "output": "filtered_normal"}),
        make("rt_hdr_calb_cnrm_large", {"color": "color", "albedo": "filtered_albedo",
                                      "normal": "filtered_normal", "output": "output"}),
    ]
    out = np.empty((h, w, 3), dtype=np.float32)
    runs = []
    for i in range(5):
        start = time.perf_counter()
        for key, image in images.items():
            lib.oidnWriteBuffer(buffers[key], 0, nbytes, image.ctypes.data)
        stages = []
        for filt in filters:
            t = time.perf_counter()
            lib.oidnExecuteFilter(filt)
            stages.append(time.perf_counter() - t)
        lib.oidnReadBuffer(buffers["output"], 0, nbytes, out.ctypes.data)
        elapsed = time.perf_counter() - start
        check()
        assert np.isfinite(out).all()
        runs.append({"total_s": elapsed, "stages_s": stages})
        print(args.device, "run", i, json.dumps(runs[-1]), flush=True)
    report = {"device": args.device, "resolution": [w, h], "models": "large, high quality",
              "prefilter": True, "includes_host_transfers": True,
              "median_warm_s": statistics.median(r["total_s"] for r in runs[1:]), "runs": runs}
    args.output.write_text(json.dumps(report, indent=2))
    np.save(args.output.with_suffix(".npy"), out)
    print(json.dumps(report), flush=True)
    for filt in filters:
        lib.oidnReleaseFilter(filt)
    for buf in buffers.values():
        lib.oidnReleaseBuffer(buf)
    lib.oidnReleaseDevice(dev)


if __name__ == "__main__":
    main()
