#!/usr/bin/env python3
import sys
import os
import socket
import struct
import time
import threading
import warnings
import numpy as np
import soundfile as sf
import torch

warnings.filterwarnings("ignore")

script_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, script_dir)

from openvoice.api import ToneColorConverter
from openvoice.mel_processing import spectrogram_torch

SOCKET_PATH = "/tmp/openvoice.sock"
PRE_PAD_SAMPLES = 1536  # 6 hops of 256 samples (~70ms) for receptive-field context continuity

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

    device = "mps" if torch.backends.mps.is_available() else "cpu"
    print(f"[OpenVoiceDaemon] Initializing Tone Color Converter on {device}...", flush=True)

    converter = ToneColorConverter(config_path, device=device, enable_watermark=False)
    converter.load_ckpt(ckpt_path)
    hps = converter.hps
    sr = hps.data.sampling_rate

    # Load default embeddings onto target device
    if os.path.exists(default_src_path):
        base_src_se = torch.load(default_src_path, map_location=device)
    else:
        base_src_se = torch.zeros(1, 256, 1, device=device)

    if os.path.exists(default_tgt_path):
        tgt_se = torch.load(default_tgt_path, map_location=device)
    else:
        tgt_se = base_src_se.clone()

    running_src_se = None
    context_tail = None
    tau = 0.3

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET_PATH)
    server.listen(128)

    # Pre-warm GPU shaders to eliminate initial chunk latency
    print(f"[OpenVoiceDaemon] Pre-warming GPU on {device}...", flush=True)
    try:
        dummy_audio = torch.zeros(1, 5120, device=device)
        dummy_spec = spectrogram_torch(
            dummy_audio,
            hps.data.filter_length,
            hps.data.sampling_rate,
            hps.data.hop_length,
            hps.data.win_length,
            center=False
        )
        dummy_len = torch.LongTensor([dummy_spec.size(-1)]).to(device)
        with torch.inference_mode():
            _ = converter.model.ref_enc(dummy_spec.transpose(1, 2))
            _ = converter.model.voice_conversion(
                dummy_spec,
                dummy_len,
                sid_src=base_src_se,
                sid_tgt=tgt_se,
                tau=0.2
            )
            if device == "mps":
                torch.mps.synchronize()
        print("[OpenVoiceDaemon] GPU pre-warming complete.", flush=True)
    except Exception as e:
        print(f"[OpenVoiceDaemon] GPU pre-warming warning: {e}", flush=True)

    print(f"[OpenVoiceDaemon] Ready on {SOCKET_PATH} (sr={sr}, device={device})", flush=True)

    model_lock = threading.Lock()

    def handle_client(conn):
        nonlocal tgt_se, tau, running_src_se, context_tail
        try:
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
                        continue

                    with model_lock:
                        if cmd == "SET_TAU":
                            try:
                                tau = float(parts[1])
                                file_obj.write(b"OK\n")
                            except Exception as e:
                                file_obj.write(f"ERROR {e}\n".encode("utf-8"))
                            file_obj.flush()

                        elif cmd == "SET_TARGET":
                            target_arg = cmd_line[len("SET_TARGET"):].strip()
                            if target_arg.startswith('"') and target_arg.endswith('"'):
                                target_arg = target_arg[1:-1]
                            try:
                                if target_arg.endswith(".pth") and os.path.exists(target_arg):
                                    tgt_se = torch.load(target_arg, map_location=device)
                                    file_obj.write(b"OK\n")
                                elif os.path.exists(target_arg):
                                    tgt_se = converter.extract_se(target_arg).to(device)
                                    file_obj.write(b"OK\n")
                                else:
                                    file_obj.write(f"ERROR File not found: {target_arg}\n".encode("utf-8"))
                            except Exception as e:
                                file_obj.write(f"ERROR {e}\n".encode("utf-8"))
                            file_obj.flush()

                        elif cmd == "RESET_CONTEXT":
                            context_tail = None
                            running_src_se = None
                            file_obj.write(b"OK\n")
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
                                    cur_tgt_se = torch.load(ref_path, map_location=device)
                                else:
                                    cur_tgt_se = converter.extract_se(ref_path).to(device)

                            try:
                                t0 = time.time()
                                cur_src_se = converter.extract_se(in_path).to(device)
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

                                audio_tensor = torch.from_numpy(samples).float().unsqueeze(0).to(device)
                                chunk_len = audio_tensor.size(-1)

                                # Context pre-padding to preserve receptive field boundary continuity
                                if context_tail is not None and context_tail.size(-1) == PRE_PAD_SAMPLES:
                                    padded_audio = torch.cat([context_tail, audio_tensor], dim=-1)
                                    has_context = True
                                else:
                                    padded_audio = audio_tensor
                                    has_context = False

                                # Update rolling context tail for next chunk
                                if chunk_len >= PRE_PAD_SAMPLES:
                                    context_tail = audio_tensor[:, -PRE_PAD_SAMPLES:].clone()
                                else:
                                    context_tail = None

                                spec = spectrogram_torch(
                                    padded_audio,
                                    hps.data.filter_length,
                                    hps.data.sampling_rate,
                                    hps.data.hop_length,
                                    hps.data.win_length,
                                    center=False
                                )
                                spec_lengths = torch.LongTensor([spec.size(-1)]).to(device)

                                with torch.inference_mode():
                                    # Fast GPU live speaker embedding extraction
                                    chunk_se = converter.model.ref_enc(spec.transpose(1, 2)).unsqueeze(-1)
                                    if running_src_se is None:
                                        running_src_se = chunk_se
                                    else:
                                        running_src_se = 0.82 * running_src_se + 0.18 * chunk_se

                                    # Timbre vector steering on speaker latent space
                                    s = float(np.clip(chunk_tau, 0.0, 1.0))
                                    interp_se = (1.0 - s) * running_src_se + s * tgt_se
                                    norm_se = interp_se / (interp_se.norm(dim=1, keepdim=True) + 1e-6) * tgt_se.norm(dim=1, keepdim=True)

                                    # Gentle posterior temperature clamp (prevents white noise hiss)
                                    stoch_tau = min(0.20, max(0.06, chunk_tau * 0.20))

                                    raw_out = converter.model.voice_conversion(
                                        spec,
                                        spec_lengths,
                                        sid_src=running_src_se,
                                        sid_tgt=norm_se,
                                        tau=stoch_tau
                                    )[0][0, 0]

                                    if has_context:
                                        raw_out = raw_out[PRE_PAD_SAMPLES:]

                                    # Match chunk length exactly
                                    if raw_out.size(-1) > chunk_len:
                                        raw_out = raw_out[:chunk_len]
                                    elif raw_out.size(-1) < chunk_len:
                                        pad_deficit = chunk_len - raw_out.size(-1)
                                        raw_out = torch.nn.functional.pad(raw_out, (0, pad_deficit))

                                    audio_out = raw_out.data.cpu().float().numpy()

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
                            os._exit(0)
        except Exception:
            pass

    while True:
        try:
            conn, _ = server.accept()
        except KeyboardInterrupt:
            break
        except Exception:
            break
        t = threading.Thread(target=handle_client, args=(conn,), daemon=True)
        t.start()

if __name__ == "__main__":
    main()
