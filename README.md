# nervoussystemprotect (Model NSP-1)

A native Apple Silicon macOS application combining **real-time CoreAudio DSP pitch modulation** and **pure Swift Apple MLX Neural Voice Conversion (RVC)** with zero Python, ONNX, or Core ML dependencies.

---

## 🎛 Operating Modes

### 1. 🎛 CoreAudio Analog DSP Mode
* **Vectorized SIMD CoreAudio Engine**: The exact pitch shifting algorithm used in GarageBand (`kAudioUnitSubType_NewTimePitch`).
* **Rotary Potentiometers**: Continuous semitone pitch knob (`-12` to `+12 st`), fine cents tuning (`-100` to `+100 ¢`), Butterworth warmth/low-pass filter (`1 kHz` – `20 kHz`), dry/wet mix, and master gain.
* **Dual Level VU Ladder**: Real-time 16-segment stereo hardware LED meter.

### 2. 🧠 MLX RVC Neural Voice Converter Mode
* **100% Native Apple Silicon MLX**: Pure Swift implementation ported from the `Acelogic/Retrieval-based-Voice-Conversion-MLX` framework.
* **Full Pipeline on Device**:
  * **HuBERT**: 16 kHz acoustic feature representation extraction.
  * **RMVPE**: High-precision robust voice pitch tracking.
  * **FAISS Index Vector Search**: Speaker embedding feature retrieval.
  * **Synthesizer**: TextEncoder, Flow, and Multi-Period / Multi-Scale Generator.
* **Voice Character Selector**: Dynamic swapping of `.safetensors` model weights and `.index` files (pre-configured with *Drake*, *Eminem*, and *Anime Heroine*).
* **Live Performance Sliders**:
  * **Pitch Shift ($f_0$)**: `-12` to `+12` semitones.
  * **Index Retrieval Rate**: `0.0` to `1.0`.
* **Low-Latency Real-Time Audio Bridge**: Captures microphone audio in ~0.35s windows, converts directly between `AVAudioPCMBuffer` and `MLXArray`, and streams back to your output device with zero cloud latency.

---

## 🚀 How to Launch

Launch directly from Finder or Terminal:
```bash
open nervoussystemprotect.app
```

Rebuild from source anytime:
```bash
./build_app.sh
```

---

## 🧪 Audio Channel Verification Suite

All offered input and output channels are tested and verified end-to-end to guarantee zero-silence, low-latency audio routing. Faulty or non-functional devices (such as `ZoomAudioDevice`, which outputs digital silence when Zoom is not in an active meeting) are automatically filtered out of the offered device list.

Run the test suite on any branch or commit:
```bash
./scripts/test_audio_channels.sh
```

Or run directly via CLI flag:
```bash
# Test packaged application:
./nervoussystemprotect.app/Contents/MacOS/nervoussystemprotect --test-all-channels

# Or test via Swift Package Manager:
swift run nervoussystemprotect --test-all-channels
```

### What is verified:
1. **Acoustic Roundtrip (Speakers $\rightarrow$ Room Air $\rightarrow$ Physical Mic)**: Emits an 880 Hz acoustic tone over MacBook Pro Speakers, physically captures it through the room air via the internal microphone diaphragm, routes it through the DSP engine, and verifies active VU meter levels.
2. **BlackHole 2ch Loopback**: Validates virtual driver routing with sub-millisecond roundtrip latency.
3. **MacBook Pro Speakers Process Tap**: Intercepts audio streams destined for the built-in speakers in real time.
4. **Global System Audio Tap**: Intercepts audio across all running applications.
5. **Microsoft Teams Loopback**: Verifies loopback driver routing (if installed).
6. **MLX RVC Neural Pipeline**: Validates live microphone capture, 16 kHz downsampling, HuBERT feature extraction, RMVPE pitch tracking, and neural synthesis with CoreAudio IOProc.
7. **System Integrity**: Validates idiot-safe auto-start on device selection, real-time DSP parameter adjustments (pitch, warmth filter, mix, volume, bypass), and glitchless output device switching / clock re-synchronization.

## 📂 Model Weights Location for Custom Characters

To load custom RVC models, place your `.safetensors` model weights and `.index` files in:
```
~/Library/Application Support/RVCModels/
```
Required base files:
- `hubert_base.safetensors`
- `rmvpe.safetensors`
- `<character_name>.safetensors`
- `<character_name>.index`
