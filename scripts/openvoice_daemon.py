#!/usr/bin/env python3
import sys
import os
import socket
import struct
import time
import numpy as np
import soundfile as sf
import torch

script_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, script_dir)

from openvoice.api import ToneColorConverter
from openvoice.mel_processing import spectrogram_torch

SOCKET_PATH = "/tmp/openvoice.sock"

def main():
    if os.path.exists(SOCKET_PATH):
        try:
            os.unlink(SOCKET_PATH)
        except OSError:
            pass

    models_dir = os.path.expanduser("~/Library/Application Support/OpenVoiceModels")
    config_path = os.path.join(models_dir, "config.json")
    ckpt_path = os.path.join(models_dir, "checkpoint.pth")
    default_tgt_path = os.path.join(models_dir, "ses", "en-us.pth")
    default_src_path = os.path.join(models_dir, "ses", "en-default.pth")

    print("[OpenVoiceDaemon] Initializing converter...", flush=True)
    converter = ToneColorConverter(config_path, device="cpu", enable_watermark=False)
    converter.load_ckpt(ckpt_path)
    hps = converter.hps
    sr = hps.data.sampling_rate

    # Load default embeddings
    if os.path.exists(default_src_path):
        src_se = torch.load(default_src_path, map_location="cpu")
    else:
        src_se = torch.zeros(1, 256, 1)

    if os.path.exists(default_tgt_path):
        tgt_se = torch.load(default_tgt_path, map_location="cpu")
    else:
        tgt_se = src_se.clone()

    tau = 0.3
    print(f"[OpenVoiceDaemon] Ready on {SOCKET_PATH} (sr={sr})", flush=True)

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET_PATH)
    server.listen(128)

    while True:
        try:
            conn, _ = server.accept()
        except KeyboardInterrupt:
            break

        with conn:
            file_obj = conn.makefile("rwb")
            while True:
                line = file_obj.readline()
                if not line:
                    break
                cmd_line = line.decode("utf-8").strip()
                if not cmd_line:
                    continue

                parts = cmd_line.split(" ", 2)
                cmd = parts[0]

                if cmd == "PING":
                    file_obj.write(b"PONG\n")
                    file_obj.flush()

                elif cmd == "SET_TAU":
                    try:
                        tau = float(parts[1])
                        file_obj.write(b"OK\n")
                    except Exception as e:
                        file_obj.write(f"ERROR {e}\n".encode("utf-8"))
                    file_obj.flush()

                elif cmd == "SET_TARGET":
                    target_arg = parts[1] if len(parts) > 1 else ""
                    try:
                        if target_arg.endswith(".pth") and os.path.exists(target_arg):
                            tgt_se = torch.load(target_arg, map_location="cpu")
                        elif os.path.exists(target_arg):
                            tgt_se = converter.extract_se(target_arg)
                        file_obj.write(b"OK\n")
                    except Exception as e:
                        file_obj.write(f"ERROR {e}\n".encode("utf-8"))
                    file_obj.flush()

                elif cmd == "CONVERT_FILE":
                    # Args: in_path out_path [ref_path]
                    file_args = cmd_line.split(" ")
                    if len(file_args) < 3:
                        file_obj.write(b"ERROR Invalid arguments\n")
                        file_obj.flush()
                        continue
                    in_path = file_args[1]
                    out_path = file_args[2]
                    ref_path = file_args[3] if len(file_args) > 3 else None
                    cur_tgt_se = tgt_se
                    if ref_path and os.path.exists(ref_path):
                        if ref_path.endswith(".pth"):
                            cur_tgt_se = torch.load(ref_path, map_location="cpu")
                        else:
                            cur_tgt_se = converter.extract_se(ref_path)

                    try:
                        t0 = time.time()
                        cur_src_se = converter.extract_se(in_path)
                        converter.convert(
                            audio_src_path=in_path,
                            src_se=cur_src_se,
                            tgt_se=cur_tgt_se,
                            output_path=out_path,
                            tau=tau
                        )
                        dur_ms = int((time.time() - t0) * 1000)
                        file_obj.write(f"OK {dur_ms}\n".encode("utf-8"))
                    except Exception as e:
                        file_obj.write(f"ERROR {e}\n".encode("utf-8"))
                    file_obj.flush()

                elif cmd == "CONVERT_CHUNK":
                    # Binary chunk streaming
                    # Expect: CONVERT_CHUNK <num_bytes> [tau]
                    try:
                        num_bytes = int(parts[1])
                        chunk_tau = float(parts[2]) if len(parts) > 2 else tau
                        tau = chunk_tau
                        raw_data = file_obj.read(num_bytes)
                        samples = np.frombuffer(raw_data, dtype=np.float32)

                        audio_tensor = torch.from_numpy(samples).float().unsqueeze(0)
                        spec = spectrogram_torch(
                            audio_tensor,
                            hps.data.filter_length,
                            hps.data.sampling_rate,
                            hps.data.hop_length,
                            hps.data.win_length,
                            center=False
                        )
                        spec_lengths = torch.LongTensor([spec.size(-1)])

                        with torch.no_grad():
                            audio_out = converter.model.voice_conversion(
                                spec,
                                spec_lengths,
                                sid_src=src_se,
                                sid_tgt=tgt_se,
                                tau=chunk_tau
                            )[0][0, 0].data.cpu().float().numpy()

                        out_bytes = audio_out.astype(np.float32).tobytes()
                        header = f"CHUNK {len(out_bytes)}\n".encode("utf-8")
                        file_obj.write(header)
                        file_obj.write(out_bytes)
                        file_obj.flush()
                    except Exception as e:
                        file_obj.write(f"ERROR {e}\n".encode("utf-8"))
                        file_obj.flush()

                elif cmd == "QUIT":
                    try:
                        file_obj.write(b"BYE\n")
                        file_obj.flush()
                    except Exception:
                        pass
                    server.close()
                    if os.path.exists(SOCKET_PATH):
                        os.unlink(SOCKET_PATH)
                    sys.exit(0)

if __name__ == "__main__":
    main()
