#!/usr/bin/env python3
import sys
import os
import argparse
import time

# Ensure scripts directory is in path
script_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, script_dir)

import torch
import soundfile as sf
from openvoice.api import ToneColorConverter

def main():
    parser = argparse.ArgumentParser(description="OpenVoice V2 ToneColor Voice Converter")
    parser.add_argument("--input", "-i", type=str, default="/tmp/input_audio.wav", help="Input source speech audio file")
    parser.add_argument("--reference", "-r", type=str, default=os.path.join(script_dir, "openvoice", "example_reference.mp3"), help="Target reference voice clip (3s+)")
    parser.add_argument("--output", "-o", type=str, default="/tmp/output_audio_openvoice.wav", help="Output converted audio file")
    parser.add_argument("--tau", "-t", type=float, default=0.3, help="Tone color conversion temperature (default 0.3)")
    parser.add_argument("--device", "-d", type=str, default="cpu", help="Compute device: cpu or mps")
    args = parser.parse_args()

    models_dir = os.path.expanduser("~/Library/Application Support/OpenVoiceModels")
    config_path = os.path.join(models_dir, "config.json")
    ckpt_path = os.path.join(models_dir, "checkpoint.pth")

    if not os.path.exists(config_path) or not os.path.exists(ckpt_path):
        print(f"❌ OpenVoice models missing in {models_dir}")
        sys.exit(1)

    print("=======================================================")
    print("🎙️ OPENVOICE V2 TONE COLOR CONVERTER")
    print("=======================================================")
    print(f"  • Input Audio:      {args.input}")
    print(f"  • Reference Voice:  {args.reference}")
    print(f"  • Output Path:      {args.output}")
    print(f"  • Temperature Tau:  {args.tau}")
    print(f"  • Device:           {args.device}")

    t0 = time.time()
    converter = ToneColorConverter(config_path, device=args.device, enable_watermark=False)
    converter.load_ckpt(ckpt_path)
    print(f"  ✅ Converter loaded in {time.time()-t0:.2f}s")

    t_ext = time.time()
    print("  ⏳ Extracting source tone color embedding (src_se)...")
    src_se = converter.extract_se(args.input)
    print("  ⏳ Extracting target reference tone color embedding (tgt_se)...")
    tgt_se = converter.extract_se(args.reference)
    print(f"  ✅ Tone color embeddings extracted in {time.time()-t_ext:.2f}s (dim: {src_se.shape})")

    t_conv = time.time()
    print("  ⚡ Running tone color conversion flow...")
    converter.convert(
        audio_src_path=args.input,
        src_se=src_se,
        tgt_se=tgt_se,
        output_path=args.output,
        tau=args.tau
    )
    conv_duration = time.time() - t_conv
    total_duration = time.time() - t0

    data, sr = sf.read(args.output)
    rms = ((data**2).mean())**0.5
    print("-------------------------------------------------------")
    print(f"🎉 SUCCESS: OpenVoice conversion completed in {conv_duration:.2f}s (Total: {total_duration:.2f}s)")
    print(f"   Output file: {args.output}")
    print(f"   Sample Rate: {sr} Hz, Samples: {len(data)}, Peak: {abs(data).max():.4f}, RMS: {rms:.4f}")
    print("=======================================================")

if __name__ == "__main__":
    main()
