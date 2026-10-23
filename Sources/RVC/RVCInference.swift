
import Foundation
import MLX
import MLXRandom
import MLXNN

    @MainActor
    public class RVCInference: ObservableObject {
        public static let bundle = Bundle.main
        @Published public var status: String = "Idle"
        
        // Callback for logging to UI
        public var onLog: ((String) -> Void)?
        
        var hubertModel: HubertModel?
        var synthesizer: Synthesizer?
        var rmvpe: RMVPE?
        var crepe: CREPE?
        var dspPitch: DSPPitchExtractor?
        var indexManager: IndexManager?
        var indexRate: Float = 0.75
        var modelSampleRate: Int = 40000  // Detected from model config
        
        private func log(_ message: String) {
            print(message) // Keep console output
            DispatchQueue.main.async {
                self.onLog?(message)
            }
        }
        
        public init() {
            log("RVCInference: Initializing...")
            #if targetEnvironment(simulator)
            MLX.Device.setDefault(device: Device.cpu)
            log("RVCInference: Running on Simulator, forced CPU device.")
            #endif
        }

        /// Unload all models to free memory
        public func unloadModels() {
            log("RVCInference: Unloading models...")
            hubertModel = nil
            synthesizer = nil
            rmvpe = nil
            crepe = nil
            dspPitch = nil
            indexManager?.unload()
            indexManager = nil
            status = "Idle"
            log("RVCInference: Models unloaded.")
        }

        /// Load index vectors for speaker embedding retrieval.
        ///
        /// The index file should be a .safetensors file created by
        /// `tools/convert_index_for_ios.py` from a FAISS .index file.
        ///
        /// - Parameters:
        ///   - url: URL to the index .safetensors file
        ///   - rate: Index blending rate (0.0-1.0, default 0.75)
        public func loadIndex(url: URL, rate: Float = 0.75) throws {
            log("RVCInference: Loading index from \(url.lastPathComponent)")
            let manager = IndexManager()
            
            // Capture self strongly or weakly? 
            // Since this is synchronous (load throws), we can just pass the closure.
            // But log is on MainActor? No, print is safe. 
            // Our internal log dispatches to main async.
            try manager.load(url: url, logger: { [weak self] msg in
                self?.log(msg)
            })
            
            self.indexManager = manager
            self.indexRate = rate
            log("RVCInference: Index loaded with \(manager.count) vectors, rate=\(rate)")
        }

        /// Unload the index to free memory.
        public func unloadIndex() {
            indexManager?.unload()
            indexManager = nil
            log("RVCInference: Index unloaded.")
        }

        public func loadWeights(hubertURL: URL, modelURL: URL, rmvpeURL: URL? = nil, crepeURL: URL? = nil) async throws {
            DispatchQueue.main.async { self.status = "Loading models..." }
            
            // 1. Load Hubert
            log("RVCInference: Loading Hubert from \(hubertURL.lastPathComponent)")
            let hubertWeights = try MLX.loadArrays(url: hubertURL)
            
            self.hubertModel = HubertModel(config: HubertConfig())
            var newParams: [String: MLXArray] = [:]
            for (k, v) in hubertWeights {
                var newKey = k
                
                // Remap encoder.layers.X to encoder.lX (Swift model uses l0, l1, etc.)
                // Supports both standard HF format and ContentVec format
                if newKey.hasPrefix("encoder.layers.") {
                    let parts = newKey.components(separatedBy: ".")
                    if parts.count >= 3, let idx = Int(parts[2]) {
                        var rest = parts.dropFirst(3).joined(separator: ".")
                        if rest.hasPrefix("self_attn.") {
                            rest = "attention." + rest.dropFirst(10)
                        } else if rest.hasPrefix("self_attn_layer_norm.") {
                            rest = "layer_norm." + rest.dropFirst(21)
                        } else if rest.hasPrefix("fc1.") {
                            rest = "feed_forward.intermediate_dense." + rest.dropFirst(4)
                        } else if rest.hasPrefix("fc2.") {
                            rest = "feed_forward.output_dense." + rest.dropFirst(4)
                        }
                        newKey = "encoder.l\(idx)." + rest
                    }
                }
                
                // Remap feature_extractor.conv_layers.X to feature_extractor.lX
                if newKey.hasPrefix("feature_extractor.conv_layers.") {
                    let parts = newKey.components(separatedBy: ".")
                    if parts.count >= 3, let idx = Int(parts[2]) {
                        var rest = parts.dropFirst(3).joined(separator: ".")
                        if rest.hasPrefix("norm.") {
                            rest = "layer_norm." + rest.dropFirst(5)
                        }
                        newKey = "feature_extractor.l\(idx)." + rest
                    }
                }

                // Remap feature projection layers
                if newKey.hasPrefix("layer_norm.") {
                    newKey = "feature_projection.layer_norm." + newKey.dropFirst(11)
                }
                if newKey.hasPrefix("post_extract_proj.") {
                    newKey = "feature_projection.projection." + newKey.dropFirst(18)
                }

                // Positional embedding bias
                if newKey == "encoder.pos_conv.layers.0.module.bias" {
                    newKey = "encoder.pos_conv_embed.conv.bias"
                }

                var val = v
                // Transpose 1D convolution weights ONLY if in PyTorch layout (Out, In, Kernel) where Kernel is axis 2
                // In MLX layout (Out, Kernel, In): kernel size (10, 3, 2) is at axis 1!
                if newKey.contains("feature_extractor.") && newKey.hasSuffix(".conv.weight") && val.ndim == 3 {
                    if val.shape[2] == 10 || (val.shape[2] <= 3 && val.shape[1] == 512) {
                        val = val.transposed(axes: [0, 2, 1])
                    }
                }
                
                newParams[newKey] = val
            }
            
            // Fix HuBERT PosConv Weight Norm:
            // Case A: ContentVec format (encoder.pos_conv.layers.0.g and .v in MLX layout [768, 128, 48])
            if let weight_g = hubertWeights["encoder.pos_conv.layers.0.g"],
               let weight_v = hubertWeights["encoder.pos_conv.layers.0.v"] {
                let v_sqr = weight_v * weight_v
                let v_sum = v_sqr.sum(axes: [0, 2], keepDims: true) // (1, 128, 1)
                let v_norm = sqrt(v_sum + 1e-12)
                let weight_fused = weight_g * (weight_v / v_norm) // (768, 128, 48)
                newParams["encoder.pos_conv_embed.conv.weight"] = weight_fused
                log("RVCInference: Fused ContentVec PosConv weights (MLX layout: [768, 128, 48])")
            }
            // Case B: Standard / PyTorch format (weight_g, weight_v or parametrizations)
            else {
                let gKey = newParams["encoder.pos_conv_embed.conv.weight_g"] != nil ? "encoder.pos_conv_embed.conv.weight_g" : "encoder.pos_conv_embed.conv.parametrizations.weight.original0"
                let vKey = newParams["encoder.pos_conv_embed.conv.weight_v"] != nil ? "encoder.pos_conv_embed.conv.weight_v" : "encoder.pos_conv_embed.conv.parametrizations.weight.original1"
                
                if let weight_g_raw = newParams[gKey], let weight_v_raw = newParams[vKey] {
                    // PyTorch layout: (768, 48, 128) and (1, 1, 128)
                    let weight_v = (weight_v_raw.shape[1] == 128) ? weight_v_raw : weight_v_raw.transposed(axes: [0, 2, 1])
                    let weight_g = (weight_g_raw.shape[1] == 128) ? weight_g_raw : weight_g_raw.transposed(axes: [0, 2, 1])
                    let v_sqr = weight_v * weight_v
                    let v_sum = v_sqr.sum(axes: [0, 2], keepDims: true)
                    let v_norm = sqrt(v_sum + 1e-12)
                    let weight_fused = weight_g * (weight_v / v_norm)
                    newParams["encoder.pos_conv_embed.conv.weight"] = weight_fused
                    newParams.removeValue(forKey: gKey)
                    newParams.removeValue(forKey: vKey)
                    log("RVCInference: Fused PyTorch HuBERT PosConv weights")
                }
            }
            log("RVCInference: Loaded \(newParams.count) HuBERT weights")
            log("RVCInference: HuBERT sample keys: \(Array(newParams.keys.prefix(5)))")
            self.hubertModel?.update(parameters: ModuleParameters.unflattened(newParams))
            
            // 2. Load Synthesizer (TextEncoder + Flow + Generator)
            log("RVCInference: Loading Synthesizer from \(modelURL.lastPathComponent)")
            let modelWeights = try MLX.loadArrays(url: modelURL)

            // Note: The Python conversion script already transposes all weights to MLX format
            // No additional transposition needed here!
            log("RVCInference: Loaded \(modelWeights.count) weights (already in MLX format)")

            // DEBUG: Print all dec.* keys to understand weight naming
            let decKeys = modelWeights.keys.filter { $0.hasPrefix("dec.") }.sorted()
            log("RVCInference: Generator weight keys: \(decKeys.prefix(20))...")  // Show first 20

            // Read model config for architecture parameters
            var detectedSR = self.modelSampleRate
            var detectedUpsRates = [10, 10, 2, 2]
            var detectedKernelSizes = [16, 16, 4, 4]

            let configURL = modelURL.deletingPathExtension().appendingPathExtension("json")
            if FileManager.default.fileExists(atPath: configURL.path) {
                log("RVCInference: Found config at \(configURL.lastPathComponent)")
                if let data = try? Data(contentsOf: configURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                    if json.count > 17, let sr = json[17] as? Int {
                        detectedSR = sr
                        log("RVCInference: Detected Sample Rate \(detectedSR)Hz")
                    }
                    if json.count > 12, let uArr = json[12] as? [Any] {
                        let u = uArr.compactMap { $0 as? Int }
                        if !u.isEmpty {
                            detectedUpsRates = u
                            log("RVCInference: Detected Upsample Rates \(detectedUpsRates)")
                        }
                    }
                    if json.count > 14, let kArr = json[14] as? [Any] {
                        let k = kArr.compactMap { $0 as? Int }
                        if !k.isEmpty {
                            detectedKernelSizes = k
                            log("RVCInference: Detected Kernel Sizes \(detectedKernelSizes)")
                        }
                    }
                }
            } else {
                log("RVCInference: No config JSON found, detecting from weights...")
            }

            // CRITICAL: Detect/verify kernel sizes from actual weight shapes
            // This ensures we use correct architecture even if JSON is missing or wrong
            for i in 0..<4 {
                let candidateKeys = [
                    "dec.ups.\(i).weight_v",
                    "dec.up_\(i).weight_v",
                    "dec.ups.\(i).weight",
                    "dec.up_\(i).weight"
                ]
                for upKey in candidateKeys {
                    if let upWeight = modelWeights[upKey] {
                        let detectedK: Int
                        if upWeight.ndim == 3 {
                            // PyTorch layout: (In, Out, K) -> shape[2]
                            // MLX layout: (Out, K, In) -> shape[1]
                            if upWeight.shape[1] == 24 || upWeight.shape[1] == 20 || upWeight.shape[1] == 16 || upWeight.shape[1] == 4 {
                                detectedK = upWeight.shape[1]
                            } else {
                                detectedK = upWeight.shape[2]
                            }
                        } else {
                            detectedK = detectedKernelSizes[i]
                        }

                        if detectedK != detectedKernelSizes[i] {
                            log("RVCInference: ⚠️ Kernel mismatch for up_\(i): config=\(detectedKernelSizes[i]), weight=\(detectedK). Using weight value.")
                            detectedKernelSizes[i] = detectedK
                        }

                        // Infer stride from kernel size for HiFi-GAN patterns:
                        // kernel=24 -> stride=12 (48kHz models)
                        // kernel=20 -> stride=10
                        // kernel=16 -> stride=10 (original 32kHz models)
                        // kernel=4  -> stride=2
                        let inferredStride: Int
                        switch detectedK {
                        case 24: inferredStride = 12
                        case 20: inferredStride = 10
                        case 16: inferredStride = 10
                        case 4: inferredStride = 2
                        default: inferredStride = detectedUpsRates[i]
                        }
                        if inferredStride != detectedUpsRates[i] {
                            log("RVCInference: ⚠️ Inferring stride for up_\(i) from kernel=\(detectedK): stride=\(inferredStride)")
                            detectedUpsRates[i] = inferredStride
                        }
                        break
                    }
                }
            }

            // Calculate exact sample rate from the product of all upsample rates (100 fps base rate * totalUpsample)
            detectedSR = 100 * detectedUpsRates.reduce(1, *)
            log("RVCInference: Final architecture - upsampleRates=\(detectedUpsRates), kernelSizes=\(detectedKernelSizes), sampleRate=\(detectedSR)")

            // Initialize Synthesizer with architecture from config
            self.synthesizer = Synthesizer(
                interChannels: 192,
                hiddenChannels: 192,
                filterChannels: 768,
                nHeads: 2,
                nLayers: 6,
                kernelSize: 3,
                pDropout: 0.0,
                embeddingDim: 768,
                speakerEmbedDim: 256,
                ginChannels: 256,
                useF0: true,
                upsampleRates: detectedUpsRates,
                upsampleKernelSizes: detectedKernelSizes,
                sampleRate: detectedSR
            )
            
            // Store sample rate for use during inference
            self.modelSampleRate = detectedSR
            
            // Remap keys for Synthesizer
            // RVC V2 PyTorch Weights:
            // enc_p.* -> TextEncoder
            // dec.* -> Generator
            // flow.flows.0, 2, 4, 6 -> Flow (indices 0, 1, 2, 3)
            // emb_g.weight -> Speaker Embedding

            // Helper: Check if a key needs .conv inserted (for Conv1d wrapper classes)
            func needsConvInsertion(_ key: String) -> Bool {
                // Generator Conv1d wrappers (NOT ConvTranspose1d - now using native)
                if key.hasPrefix("dec.conv_pre.") || key.hasPrefix("dec.conv_post.") { return true }
                // dec.up_* uses native ConvTransposed1d, no .conv wrapper
                if key.contains("dec.noise_conv_") { return true }
                if key.contains("dec.resblock_") && (key.contains(".c1_") || key.contains(".c2_")) { return true }
                return false
            }

            // Helper: Check if this is a ConvTranspose1d weight that needs kernel flip
            // Handle both naming conventions: dec.up_0.weight OR dec.ups.0.weight
            func isConvTransposeWeight(_ key: String) -> Bool {
                let isUpWeight = (key.contains("dec.up_") || key.contains("dec.ups.")) && key.hasSuffix(".weight")
                return isUpWeight
            }

            var synthParams: [String: MLXArray] = [:]
            for (k, v) in modelWeights {
                var newK = k
                let newV = v

                // 1. Remap Flow keys: flow.flows.0, 2, 4, 6 -> flow.flow_0, 1, 2, 3
                // Also remap in_layers.X -> in_layer_X and res_skip_layers.X -> res_skip_layer_X
                if newK.hasPrefix("flow.flows.") {
                    let parts = newK.components(separatedBy: ".")
                    if parts.count >= 4, let flowIdx = Int(parts[2]) {
                        let realIdx = flowIdx / 2
                        let prefix = "flow.flow_\(realIdx)"
                        var rest = parts[3...].joined(separator: ".")
                        if let regex = try? NSRegularExpression(pattern: "in_layers\\.(\\d+)") {
                            let range = NSRange(rest.startIndex..., in: rest)
                            rest = regex.stringByReplacingMatches(in: rest, range: range, withTemplate: "in_layer_$1")
                        }
                        if let regex = try? NSRegularExpression(pattern: "res_skip_layers\\.(\\d+)") {
                            let range = NSRange(rest.startIndex..., in: rest)
                            rest = regex.stringByReplacingMatches(in: rest, range: range, withTemplate: "res_skip_layer_$1")
                        }
                        newK = "\(prefix).\(rest)"
                    }
                }

                // 2. Remap PyTorch-style Generator keys to match Swift structure
                // dec.ups.X -> dec.up_X
                if newK.contains("dec.ups.") {
                    newK = newK.replacingOccurrences(of: "dec.ups.", with: "dec.up_")
                }
                // dec.noise_convs.X -> dec.noise_conv_X
                if newK.contains("dec.noise_convs.") {
                    newK = newK.replacingOccurrences(of: "dec.noise_convs.", with: "dec.noise_conv_")
                }
                // dec.resblocks.X.convs1.Y -> dec.resblock_X.c1_Y
                if newK.contains("dec.resblocks.") {
                    newK = newK.replacingOccurrences(of: "dec.resblocks.", with: "dec.resblock_")
                    newK = newK.replacingOccurrences(of: ".convs1.", with: ".c1_")
                    newK = newK.replacingOccurrences(of: ".convs2.", with: ".c2_")
                }

                // 3. Remap LayerNorm parameters: gamma -> weight, beta -> bias
                if newK.hasSuffix(".gamma") {
                    newK = String(newK.dropLast(6)) + ".weight"
                } else if newK.hasSuffix(".beta") {
                    newK = String(newK.dropLast(5)) + ".bias"
                }

                // 4. Remap TextEncoder encoder keys if needed
                if newK.contains("enc_p.encoder.") {
                    for i in 0..<6 {
                        newK = newK.replacingOccurrences(of: "encoder.attn_\(i).", with: "encoder.attn_layers.\(i).")
                        newK = newK.replacingOccurrences(of: "encoder.norm1_\(i).", with: "encoder.norm_layers_1.\(i).")
                        newK = newK.replacingOccurrences(of: "encoder.ffn_\(i).", with: "encoder.ffn_layers.\(i).")
                        newK = newK.replacingOccurrences(of: "encoder.norm2_\(i).", with: "encoder.norm_layers_2.\(i).")
                    }
                }

                // 5. Insert .conv for Conv1d wrapper classes in Generator
                if needsConvInsertion(newK) && !newK.contains(".conv.") {
                    if newK.hasSuffix(".weight") {
                        newK = String(newK.dropLast(7)) + ".conv.weight"
                    } else if newK.hasSuffix(".bias") {
                        newK = String(newK.dropLast(5)) + ".conv.bias"
                    }
                }

                synthParams[newK] = newV
            }

            log("RVCInference: Remapped \(synthParams.count) parameters before weight fusion")

            // 6. Generic Weight Normalization Fusion for all weight_g + weight_v pairs
            let preFusionKeys = Array(synthParams.keys)
            var fusedCount = 0
            for gKey in preFusionKeys {
                guard gKey.hasSuffix(".weight_g") else { continue }
                let base = String(gKey.dropLast(9))
                let vKey = base + ".weight_v"
                guard let weight_g = synthParams[gKey], let weight_v = synthParams[vKey] else { continue }

                let v_sqr = weight_v * weight_v
                let v_norm: MLXArray
                if weight_v.ndim == 3 {
                    let v_sum = v_sqr.sum(axes: [1, 2], keepDims: true)
                    v_norm = sqrt(v_sum + 1e-12)
                } else {
                    let v_sum = v_sqr.sum(axes: [1], keepDims: true)
                    v_norm = sqrt(v_sum + 1e-12)
                }
                var weight_fused = weight_g * (weight_v / v_norm)

                let targetKey: String
                if base.contains("dec.up_") {
                    // ConvTranspose1d: PyTorch [In, Out, K] -> MLX [Out, K, In]
                    weight_fused = weight_fused.transposed(axes: [1, 2, 0])
                    targetKey = "\(base).weight"
                } else if base.contains("dec.resblock_") {
                    // ResBlock Conv1d wrapper: PyTorch [Out, In, K] -> MLX [Out, K, In]
                    weight_fused = weight_fused.transposed(axes: [0, 2, 1])
                    targetKey = "\(base).conv.weight"
                } else {
                    // General Conv1d (e.g. flow.flow_X.enc.in_layer_Y, flow.flow_X.enc.cond_layer, res_skip_layer)
                    if weight_fused.ndim == 3 {
                        weight_fused = weight_fused.transposed(axes: [0, 2, 1])
                    }
                    targetKey = "\(base).weight"
                }

                synthParams[targetKey] = weight_fused
                synthParams.removeValue(forKey: gKey)
                synthParams.removeValue(forKey: vKey)
                fusedCount += 1
            }
            log("RVCInference: Fused \(fusedCount) weight normalization layers across Dec and Flow")

            // 7. Transpose non-fused standard Conv1d weights from PyTorch [Out, In, K] to MLX [Out, K, In]
            for (k, v) in Array(synthParams) {
                guard v.ndim == 3 && !k.contains("emb") && !k.contains("dec.up_") else { continue }
                if k.contains("noise_conv") {
                    // noise_conv in PyTorch format has [Out, In=1, K]: transpose to [Out, K, In=1]
                    if v.shape[1] == 1 && v.shape[2] > 1 {
                        synthParams[k] = v.transposed(axes: [0, 2, 1])
                        log("RVCInference: Transposed noise_conv \(k) from \(v.shape) to \(synthParams[k]!.shape)")
                    }
                } else {
                    // General Conv1d layers: PyTorch format has [Out, In, K] where K <= In
                    if v.shape[2] <= v.shape[1] {
                        synthParams[k] = v.transposed(axes: [0, 2, 1])
                    }
                }
            }

            log("RVCInference: Final synthesized parameters to load: \(synthParams.count)")
            log("RVCInference: Generator up_0 weight shape in file: \(synthParams["dec.up_0.weight"]?.shape ?? [])")

            // DEBUG: Check emb_phone weight in synthParams BEFORE loading
            if let embPhoneWeight = synthParams["enc_p.emb_phone.weight"] {
                MLX.eval(embPhoneWeight)
                log("DEBUG: synthParams[enc_p.emb_phone.weight] BEFORE update: shape=\(embPhoneWeight.shape), range=[\(embPhoneWeight.min().item(Float.self))...\(embPhoneWeight.max().item(Float.self))]")
            } else {
                log("DEBUG: synthParams[enc_p.emb_phone.weight] NOT FOUND!")
            }

            // DEBUG: Check NSF module weights BEFORE loading
            if let nsfWeight = synthParams["dec.m_source.l_linear.weight"] {
                MLX.eval(nsfWeight)
                log("DEBUG: synthParams[dec.m_source.l_linear.weight] BEFORE update: shape=\(nsfWeight.shape), range=[\(nsfWeight.min().item(Float.self))...\(nsfWeight.max().item(Float.self))]")
            } else {
                log("DEBUG: synthParams[dec.m_source.l_linear.weight] NOT FOUND - NSF will use init weights!")
            }
            if let nsfBias = synthParams["dec.m_source.l_linear.bias"] {
                MLX.eval(nsfBias)
                log("DEBUG: synthParams[dec.m_source.l_linear.bias] BEFORE update: shape=\(nsfBias.shape), value=\(nsfBias.asArray(Float.self))")
            } else {
                log("DEBUG: synthParams[dec.m_source.l_linear.bias] NOT FOUND - NSF will use init bias!")
            }

            self.synthesizer?.update(parameters: ModuleParameters.unflattened(synthParams))
            self.synthesizer?.train(false)  // CRITICAL: Set to eval mode (disables Dropout, uses BatchNorm running stats)
            log("RVCInference: Successfully loaded Synthesizer with \(synthParams.count) weight keys")

            // DEBUG: Verify weights are loaded correctly
            if let synth = self.synthesizer {
                // Check TextEncoder weights
                let emb_phone = synth.enc_p.emb_phone.weight
                log("DEBUG: enc_p.emb_phone.weight: shape=\(emb_phone.shape), range=[\(emb_phone.min().item(Float.self))...\(emb_phone.max().item(Float.self))]")
                if let emb_pitch = synth.enc_p.emb_pitch {
                    let w = emb_pitch.weight
                    log("DEBUG: enc_p.emb_pitch.weight: shape=\(w.shape), range=[\(w.min().item(Float.self))...\(w.max().item(Float.self))]")
                }

                // Check Generator resblock weights - CRITICAL for detecting weight loading issues
                let w0 = synth.dec.resblock_0.c1_0.conv.weight
                MLX.eval(w0)
                log("DEBUG: resblock_0.c1_0.conv.weight (kernel=3): shape=\(w0.shape), range=[\(w0.min().item(Float.self))...\(w0.max().item(Float.self))], mean=\(w0.mean().item(Float.self))")
                log("DEBUG: EXPECTED from Drake.safetensors: shape=(256, 3, 256), range=[-0.44, 0.66], mean=-0.0013")

                // Compare with what was in synthParams before loading
                if let fileW0 = synthParams["dec.resblock_0.c1_0.conv.weight"] {
                    MLX.eval(fileW0)
                    log("DEBUG: synthParams key found! File weight range=[\(fileW0.min().item(Float.self))...\(fileW0.max().item(Float.self))]")
                } else {
                    log("DEBUG: WARNING - synthParams[dec.resblock_0.c1_0.conv.weight] NOT FOUND! Weights may not be loading correctly!")
                    log("DEBUG: Available dec.resblock_0 keys: \(synthParams.keys.filter { $0.contains("resblock_0.c1_0") }.sorted())")
                }

                // Check Flow weights are loaded
                let flowCondW = synth.flow.flow_0.enc.cond_layer?.weight
                if let w = flowCondW {
                    log("DEBUG: flow.flow_0.enc.cond_layer.weight: shape=\(w.shape), range=[\(w.min().item(Float.self))...\(w.max().item(Float.self))]")
                } else {
                    log("DEBUG: flow.flow_0.enc.cond_layer is nil!")
                }
                let flowIn0W = synth.flow.flow_0.enc.in_layer_0.weight
                log("DEBUG: flow.flow_0.enc.in_layer_0.weight: shape=\(flowIn0W.shape), range=[\(flowIn0W.min().item(Float.self))...\(flowIn0W.max().item(Float.self))]")

                // DEBUG: Check NSF module weights AFTER loading
                let nsfW = synth.dec.m_source.l_linear.weight
                MLX.eval(nsfW)
                log("DEBUG: dec.m_source.l_linear.weight AFTER load: shape=\(nsfW.shape), values=\(nsfW.asArray(Float.self))")
                if let nsfB = synth.dec.m_source.l_linear.bias {
                    MLX.eval(nsfB)
                    log("DEBUG: dec.m_source.l_linear.bias AFTER load: shape=\(nsfB.shape), values=\(nsfB.asArray(Float.self))")
                } else {
                    log("DEBUG: dec.m_source.l_linear.bias is nil (no bias)")
                }
            }
            
            // 3. Load RMVPE (Optional)
            if let rmvpeURL = rmvpeURL {
                do {
                    log("RVCInference: Loading RMVPE from \(rmvpeURL.lastPathComponent)")
                    let rmvpeWeights = try MLX.loadArrays(url: rmvpeURL)
                    self.rmvpe = RMVPE()
                    
                    // Remap RMVPE weight keys (Python MLX format -> Swift)
                    var remappedRMVPE: [String: MLXArray] = [:]
                    for (k, v) in rmvpeWeights {
                        var newKey = k
                        var val = v
                        
                        // Skip batch tracking stats
                        if newKey.contains("num_batches_tracked") {
                            continue
                        }
                        
                        // Strip 'model.' prefix from HuggingFace/PyTorch safetensors
                        if newKey.hasPrefix("model.") {
                            newKey = String(newKey.dropFirst("model.".count))
                        }

                        // Remap BiGRU keys from PyTorch/SafeTensors format
                        if newKey.hasPrefix("bigru.gru_forward.") {
                            let subKey = String(newKey.dropFirst("bigru.gru_forward.".count))
                            switch subKey {
                            case "Wx":
                                newKey = "bigru.fwd0.weight_ih"
                            case "Wh":
                                newKey = "bigru.fwd0.weight_hh"
                            case "b":
                                newKey = "bigru.fwd0.bias_ih"
                            case "bhn":
                                // Candidate hidden bias: pad to 768 by prepending 512 zeros
                                let zeros = MLX.zeros([512])
                                val = concatenated([zeros, val], axis: 0)
                                newKey = "bigru.fwd0.bias_hh"
                            default: break
                            }
                        } else if newKey.hasPrefix("bigru.gru_backward.") {
                            let subKey = String(newKey.dropFirst("bigru.gru_backward.".count))
                            switch subKey {
                            case "Wx":
                                newKey = "bigru.bwd0.weight_ih"
                            case "Wh":
                                newKey = "bigru.bwd0.weight_hh"
                            case "b":
                                newKey = "bigru.bwd0.bias_ih"
                            case "bhn":
                                // Candidate hidden bias: pad to 768 by prepending 512 zeros
                                let zeros = MLX.zeros([512])
                                val = concatenated([zeros, val], axis: 0)
                                newKey = "bigru.bwd0.bias_hh"
                            default: break
                            }
                        } else if newKey.hasPrefix("fc.bigru.forward_grus.0.") {
                            newKey = "bigru.fwd0." + String(newKey.dropFirst("fc.bigru.forward_grus.0.".count))
                        } else if newKey.hasPrefix("fc.bigru.backward_grus.0.") {
                            newKey = "bigru.bwd0." + String(newKey.dropFirst("fc.bigru.backward_grus.0.".count))
                        }
                        
                        // Remap fc.linear -> linear
                        if newKey.hasPrefix("fc.linear.") {
                            newKey = "linear." + String(newKey.dropFirst("fc.linear.".count))
                        }
                        
                        // Remap .layers.X. -> .lX. and conv_blocks -> bX
                        for i in 0...4 {
                            newKey = newKey.replacingOccurrences(of: ".layers.\(i).", with: ".l\(i).")
                            newKey = newKey.replacingOccurrences(of: ".conv_blocks.\(i).", with: ".b\(i).")
                            newKey = newKey.replacingOccurrences(of: ".blocks.\(i).", with: ".b\(i).")
                            newKey = newKey.replacingOccurrences(of: "decoder.l\(i).bn.", with: "decoder.l\(i).bn1.")
                        }

                        // Remap decoder conv_transpose -> conv1Trans.convTranspose
                        newKey = newKey.replacingOccurrences(of: ".conv_transpose.", with: ".conv1Trans.convTranspose.")
                        
                        // Remap BatchNorm running stats & gamma/beta
                        newKey = newKey.replacingOccurrences(of: ".running_mean", with: ".runningMean")
                        newKey = newKey.replacingOccurrences(of: ".running_var", with: ".runningVar")
                        if newKey.hasSuffix(".gamma") {
                            newKey = String(newKey.dropLast(6)) + ".weight"
                        } else if newKey.hasSuffix(".beta") {
                            newKey = String(newKey.dropLast(5)) + ".bias"
                        }
                        
                        remappedRMVPE[newKey] = val
                    }
                    
                    log("RVCInference: RMVPE sample keys after remapping: \(Array(remappedRMVPE.keys.prefix(5)))")

                    // Check if running stats are in the remapped dict
                    let bnRunningKeys = remappedRMVPE.keys.filter { $0.contains("encoder.bn.running") }
                    log("RVCInference: BN running stat keys to load: \(bnRunningKeys)")
                    if let rmKey = remappedRMVPE["unet.encoder.bn.runningMean"] {
                        log("RVCInference: encoder.bn.runningMean value: \(rmKey.asArray(Float.self))")
                    }
                    if let rvKey = remappedRMVPE["unet.encoder.bn.runningVar"] {
                        log("RVCInference: encoder.bn.runningVar value: \(rvKey.asArray(Float.self))")
                    }

                    self.rmvpe?.update(parameters: ModuleParameters.unflattened(remappedRMVPE))
                    self.rmvpe?.setTrainingMode(false)  // CRITICAL: Set to eval mode for correct inference

                    log("RVCInference: ✅ RMVPE loaded with CustomBatchNorm (\(remappedRMVPE.count) keys)")
                } catch {
                    log("RVCInference: Failed to load RMVPE: \(error). Using fallback F0.")
                    self.rmvpe = nil
                }
            } else {
                log("RVCInference: No RMVPE URL provided. Using fallback F0.")
            }

            // 4. Load CREPE (Optional)
            if let crepeURL = crepeURL {
                do {
                    log("RVCInference: Loading CREPE from \(crepeURL.lastPathComponent)")
                    self.crepe = try CREPE(weightsURL: crepeURL, modelType: "full")
                    log("RVCInference: ✅ CREPE loaded successfully")
                } catch {
                    log("RVCInference: Failed to load CREPE: \(error). CREPE will not be available.")
                    self.crepe = nil
                }
            } else {
                log("RVCInference: No CREPE URL provided. CREPE will not be available.")
            }

            // Also set HuBERT to eval mode
            self.hubertModel?.train(false)
            
            DispatchQueue.main.async { self.status = "Models Loaded" }
        }
        
        public func infer(
            audioURL: URL,
            outputURL: URL,
            pitchShift: Int = 0,           // Semitones (-12 to +12)
            f0Method: String = "rmvpe",    // F0 extraction method
            indexRate: Float = 0.75,       // Feature retrieval blend
            volumeEnvelope: Float = 1.0
        ) async {
            do {
                DispatchQueue.main.async { self.status = "Loading Audio..." }
                
                // Load whole audio (Float array size is fine, just not tensors)
                let (audioArray, _) = try AudioProcessor.shared.loadAudio(url: audioURL)
                // audioArray: [TotalSamples]
                
                let totalSamples = audioArray.size
                log("RVCInference: Processing \(totalSamples) samples (\(Float(totalSamples)/16000.0)s at 16kHz)")
                
                DispatchQueue.main.async { self.status = "Processing..." }
                
                // Process entire audio in one pass (simpler, avoids chunk boundary artifacts)
                // For iOS memory constraints, we limit to ~30s audio for now
                let maxSamples = 16000 * 30  // 30 seconds at 16kHz
                var audioToProcess = audioArray
                if totalSamples > maxSamples {
                    log("RVCInference: Audio too long (\(totalSamples) samples), truncating to \(maxSamples)")
                    audioToProcess = audioArray[0..<maxSamples]
                }
                
                // Apply high-pass filter (Butterworth 5th order, 48Hz)
                // Matches Python: signal.butter(5, 48, btype="high", fs=16000) + filtfilt
                audioToProcess = applyButterworthHighPass(audioToProcess)
                
                // Add padding for model context (1s each side, reflect mode)
                // Matches Python: np.pad(audio, (16000, 16000), mode="reflect")
                let padSamples = 1600
                let audioPadded = padReflect(audioToProcess, padding: padSamples)
                
                // Run inference on full audio
                let outputPadded = try await inferChunk(
                    chunk: audioPadded,
                    pitchShift: pitchShift,
                    f0Method: f0Method,
                    indexRate: indexRate
                )
                MLX.eval(outputPadded)
                
                // Calculate crop to remove padding from output
                // Input is at 16kHz, output is at model sample rate
                let outputRatio: Float = Float(self.modelSampleRate) / 16000.0
                let cropSamples = Int(Float(padSamples) * outputRatio)
                
                let outputLen = outputPadded.shape[1]
                let coreStart = cropSamples
                let coreEnd = outputLen - cropSamples
                
                var finalOutput: MLXArray
                if coreEnd > coreStart {
                    finalOutput = outputPadded[0..., coreStart..<coreEnd, 0...].squeezed(axes: [0, 2])
                } else {
                    // Fallback if output is too short
                    finalOutput = outputPadded.squeezed(axes: [0, 2])
                }
                
                MLX.eval(finalOutput)

                // Apply volume envelope scaling
                if volumeEnvelope != 1.0 {
                    finalOutput = finalOutput * volumeEnvelope
                    MLX.eval(finalOutput)
                }

                let outputSampleRate: Double = Double(self.modelSampleRate)

                log("RVCInference: Saving \(finalOutput.size) samples to \(outputURL.path)")
                try AudioProcessor.shared.saveAudio(array: finalOutput, url: outputURL, sampleRate: outputSampleRate)
                
                log("RVCInference: Done!")
                DispatchQueue.main.async { self.status = "Done!" }
                
            } catch {
                log("RVCInference Error: \(error)")
                DispatchQueue.main.async { self.status = "Error: \(error.localizedDescription)" }
            }
        }
        
        public func inferChunk(
            chunk: MLXArray,
            pitchShift: Int,
            f0Method: String,
            indexRate: Float
        ) async throws -> MLXArray {
            // chunk: [T] - 16kHz
            
            // 1. Hubert Feature Extraction (16kHz -> 50fps)
            let audioInput = chunk.expandedDimensions(axis: 0) // [1, T]
            guard let hubertModel = hubertModel else {
                throw NSError(domain: "RVCInference", code: 1, userInfo: [NSLocalizedDescriptionKey: "Hubert model missing"])
            }
            let hubertFeatures = hubertModel(audioInput) // [1, Frames, 768]
            MLX.eval(hubertFeatures)
            MLX.Memory.clearCache()  // MEMORY FIX: Clear after HuBERT
            log("DEBUG: HuBERT output shape: \(hubertFeatures.shape)")
            
            // DEBUG: Log first HuBERT frame's first 5 features
            let hubertSlice = hubertFeatures[0, 0, 0..<5].asType(Float.self)
            MLX.eval(hubertSlice)
            let hubertSamples = hubertSlice.asArray(Float.self)
            log("DEBUG: HuBERT[0,0,:5]: \(hubertSamples)")


            // 2. F0 Estimation (16kHz -> 100fps)
            // Dispatch to appropriate F0 method
            var f0: MLXArray
            switch f0Method.lowercased() {
            case "crepe", "crepe-full":
                if let crepe = crepe {
                    f0 = crepe.getF0(audio: chunk, f0Min: 50.0, f0Max: 1100.0, threshold: 0.1)
                    log("DEBUG: CREPE F0 shape: \(f0.shape)")
                } else {
                    // Fallback to RMVPE if CREPE not loaded
                    log("WARN: CREPE not loaded, falling back to RMVPE")
                    if let rmvpe = rmvpe {
                        f0 = rmvpe.infer(audio: chunk, thred: 0.03)
                    } else {
                        let frames = hubertFeatures.shape[1] * 2
                        f0 = MLX.full([1, frames, 1], values: MLXArray(200.0))
                    }
                }

            case "crepe-tiny":
                // CREPE tiny variant (same interface, just different weights)
                if let crepe = crepe {
                    f0 = crepe.getF0(audio: chunk, f0Min: 50.0, f0Max: 1100.0, threshold: 0.1)
                    log("DEBUG: CREPE-tiny F0 shape: \(f0.shape)")
                } else {
                    log("WARN: CREPE-tiny not loaded, falling back to RMVPE")
                    if let rmvpe = rmvpe {
                        f0 = rmvpe.infer(audio: chunk, thred: 0.03)
                    } else {
                        let frames = hubertFeatures.shape[1] * 2
                        f0 = MLX.full([1, frames, 1], values: MLXArray(200.0))
                    }
                }

            case "rmvpe":
                if let rmvpe = rmvpe {
                    f0 = rmvpe.infer(audio: chunk, thred: 0.03)
                } else {
                    log("WARN: RMVPE not loaded, using fallback F0")
                    let frames = hubertFeatures.shape[1] * 2
                    f0 = MLX.full([1, frames, 1], values: MLXArray(200.0))
                }

            case "dio":
                // Initialize DSP extractor if needed
                if dspPitch == nil {
                    dspPitch = DSPPitchExtractor(sampleRate: 16000, hopSize: 160)
                }
                f0 = dspPitch!.dio(audio: chunk, f0Min: 50.0, f0Max: 1100.0)
                log("DEBUG: DIO F0 shape: \(f0.shape)")

            case "pm":
                if dspPitch == nil {
                    dspPitch = DSPPitchExtractor(sampleRate: 16000, hopSize: 160)
                }
                f0 = dspPitch!.pm(audio: chunk, f0Min: 50.0, f0Max: 1100.0)
                log("DEBUG: PM F0 shape: \(f0.shape)")

            case "harvest":
                if dspPitch == nil {
                    dspPitch = DSPPitchExtractor(sampleRate: 16000, hopSize: 160)
                }
                f0 = dspPitch!.harvest(audio: chunk, f0Min: 50.0, f0Max: 1100.0)
                log("DEBUG: HARVEST F0 shape: \(f0.shape)")

            default:
                // Unknown method - use RMVPE
                log("WARN: Unknown F0 method '\(f0Method)', using RMVPE")
                if let rmvpe = rmvpe {
                    f0 = rmvpe.infer(audio: chunk, thred: 0.03)
                } else {
                    let frames = hubertFeatures.shape[1] * 2
                    f0 = MLX.full([1, frames, 1], values: MLXArray(200.0))
                }
            }
            MLX.eval(f0)
            MLX.Memory.clearCache()  // MEMORY FIX: Clear after F0 estimation
            
            // 3. Upsample Hubert Features to match F0 (100fps)
            let N = hubertFeatures.shape[0]
            let L = hubertFeatures.shape[1]
            let C = hubertFeatures.shape[2]
            
            // Simple repeat upsampling: [1, L, 768] -> [1, L, 2, 768] -> [1, L*2, 768]
            let expanded = hubertFeatures.expandedDimensions(axis: 2)
            let broadcasted = MLX.broadcast(expanded, to: [N, L, 2, C])
            var phone = broadcasted.reshaped([N, L * 2, C])
            log("DEBUG: Upsampled phone shape: \(phone.shape)")

            // 3b. Apply index retrieval if loaded (speaker embedding blending)
            if let indexManager = indexManager, indexRate > 0 {
                phone = indexManager.search(features: phone, indexRate: indexRate)
                log("DEBUG: Applied index retrieval with rate=\(indexRate)")
            }

            // 4. Coarse Pitch calculation (Hz -> Bucket 1-255)
            var f0Hz = f0.squeezed(axes: [2]) // [1, L_f0]

            // 4a. Apply pitch shift: f0_shifted = f0 * 2^(semitones/12)
            if pitchShift != 0 {
                let multiplier = pow(2.0, Float(pitchShift) / 12.0)
                f0Hz = f0Hz * multiplier
                log("DEBUG: Applied pitch shift of \(pitchShift) semitones (multiplier: \(multiplier))")
            }

            let f0_min: Float = 50.0
            let f0_max: Float = 1100.0
            let f0_mel_min = 1127.0 * Darwin.log(1.0 + Double(f0_min) / 700.0)
            let f0_mel_max = 1127.0 * Darwin.log(1.0 + Double(f0_max) / 700.0)
            
            // MLX Mel calculation: 1127 * ln(1 + f/700)
            let f0_mel = 1127.0 * MLX.log(1.0 + f0Hz / 700.0)
            
            // Bucket quantization
            var pitch = (f0_mel - f0_mel_min) * (254.0 / (f0_mel_max - f0_mel_min)) + 1.0
            pitch = MLX.where(f0Hz .<= f0_min, MLXArray(1.0), pitch) 
            pitch = MLX.maximum(pitch, 1.0)
            pitch = MLX.minimum(pitch, 255.0)
            let pitchBuckets = pitch.asType(Int32.self)
            
            // 5. Sync lengths
            let p_len_val = min(phone.shape[1], f0Hz.shape[1])
            phone = phone[0..., 0..<p_len_val, 0...]
            let nsff0 = f0Hz[0..., 0..<p_len_val].expandedDimensions(axis: 2)
            let pitchFinal = pitchBuckets[0..., 0..<p_len_val]
            let phoneLengths = MLXArray([Int32(p_len_val)])
            
            // LOGGING FOR PARITY CHECK: Disabled in production to prevent GPU stalls
            if false {
                log("DEBUG DATA DUMP:")
                
                // 1. F0 (Raw Hz) - use asArray to avoid .item() precondition failure
                let f0Slice = nsff0[0, 0..<min(20, p_len_val), 0].asType(Float.self)
                MLX.eval(f0Slice)
                let f0Values = f0Slice.asArray(Float.self)
                let f0Str = "F0 (First 20): [\(f0Values.map { String(format: "%.4f", $0) }.joined(separator: ", "))]"
                log(f0Str)
                
                // 2. Pitch (Buckets)
                let pitchSlice = pitchFinal[0, 0..<min(20, p_len_val)].asType(Int32.self)
                MLX.eval(pitchSlice)
                let pitchValues = pitchSlice.asArray(Int32.self)
                let pitchStr = "Pitch (First 20): [\(pitchValues.map { String($0) }.joined(separator: ", "))]"
                log(pitchStr)
                
                // 3. Phone (First feature of first 20 frames)
                let phoneSlice = phone[0, 0..<min(20, p_len_val), 0].asType(Float.self)
                MLX.eval(phoneSlice)
                let phoneValues = phoneSlice.asArray(Float.self)
                let phoneStr = "Phone[0] (First 20): [\(phoneValues.map { String(format: "%.4f", $0) }.joined(separator: ", "))]"
                log(phoneStr)
            }
            
            // 6. Synthesizer Inference
            guard let synthesizer = synthesizer else {
                throw NSError(domain: "RVCInference", code: 1, userInfo: [NSLocalizedDescriptionKey: "Synthesizer missing"])
            }
            
            let sid = MLXArray([Int32(0)]) // Default speaker 0

            log("DEBUG: Before Synthesizer - phone: \(phone.shape), pitch: \(pitchFinal.shape), nsff0: \(nsff0.shape)")

            let audioOut = synthesizer.infer(
                phone: phone,
                phoneLengths: phoneLengths,
                pitch: pitchFinal,
                nsff0: nsff0,
                sid: sid
            )
            
        return audioOut // [1, T_out, 1]
        }

        /// Run benchmark: perform inference and compare with reference audio
        public func runBenchmark(audioURL: URL, referenceURL: URL?, outputURL: URL) async throws -> String {
            // Run inference
            await infer(audioURL: audioURL, outputURL: outputURL)

            // If reference provided, compare using Python script
            guard let refURL = referenceURL else {
                return "Inference completed. No reference provided for comparison."
            }

            #if os(macOS)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            task.arguments = [
                "tools/compare_wavs.py",
                refURL.path,
                outputURL.path
            ]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return "Failed to read comparison output"
            }

            return output
            #else
            // Process is not available on iOS
            return "Inference completed. Reference comparison not available on iOS (reference: \(refURL.lastPathComponent))."
            #endif
        }
        
        /// Apply high-pass filter: Butterworth 5th order, 48Hz cut-off, 16kHz sample rate
        /// Matches scipy.signal.butter(5, 48, btype='high', fs=16000)
        /// Uses forward-backward filtering (filtfilt) for zero phase shift
        private func applyButterworthHighPass(_ audio: MLXArray) -> MLXArray {
            // Coefficients for butter(5, 48, fs=16000)
            let b: [Double] = [0.9699606451838447, -4.849803225919223, 9.699606451838447, -9.699606451838447, 4.849803225919223, -0.9699606451838447]
            let a: [Double] = [1.0, -4.939001819168364, 9.757863526739543, -9.639544849413458, 4.761506797356209, -0.9408236532054606]
            
            // Extract samples to CPU and convert to Double for precision
            MLX.eval(audio)
            let samplesFloat = audio.asArray(Float.self)
            let samples = samplesFloat.map { Double($0) }
            
            // Helper for simple Direct Form II filtering
            func filter(_ x: [Double]) -> [Double] {
                var y = [Double](repeating: 0, count: x.count)
                
                // Direct Form I difference equation:
                // y[n] = b0*x[n] + ... + b5*x[n-5] - a1*y[n-1] - ... - a5*y[n-5]
                // Assumes a[0] = 1.0
                
                for n in 0..<x.count {
                    // Feedforward
                    var val = b[0] * x[n]
                    if n > 0 { val += b[1] * x[n-1] }
                    if n > 1 { val += b[2] * x[n-2] }
                    if n > 2 { val += b[3] * x[n-3] }
                    if n > 3 { val += b[4] * x[n-4] }
                    if n > 4 { val += b[5] * x[n-5] }
                    
                    // Feedback
                    if n > 0 { val -= a[1] * y[n-1] }
                    if n > 1 { val -= a[2] * y[n-2] }
                    if n > 2 { val -= a[3] * y[n-3] }
                    if n > 3 { val -= a[4] * y[n-4] }
                    if n > 4 { val -= a[5] * y[n-5] }
                    
                    y[n] = val
                }
                return y
            }
            
            // Forward pass
            let y_fwd = filter(samples)
            
            // Backward pass (reverse, filter, reverse)
            let y_rev = Array(y_fwd.reversed())
            let y_back = filter(y_rev)
            let y_final = Array(y_back.reversed())
            
            // Convert back to Float
            let resultFloat = y_final.map { Float($0) }
            return MLXArray(resultFloat)
        }
        
        /// Manual reflect padding matching numpy.pad(mode='reflect')
        /// Pads with the reflection of the vector mirrored on the first and last values of the vector
        private func padReflect(_ audio: MLXArray, padding: Int) -> MLXArray {
            MLX.eval(audio)
            let samples = audio.asArray(Float.self)
            let n = samples.count
            
            guard n > 1 else { return audio }
            
            // Left pad: reverse of samples[1...padding]
            // If padding > n, this simple logic fails, but we assume padding < n (16000 < 30s audio)
            // Python: pad=2, [0,1,2] -> [2,1, 0,1,2]
            
            var leftPad: [Float] = []
            if padding > 0 {
                // indices: 1 to padding
                let start = 1
                let end = min(padding, n - 1)
                if end >= start {
                    leftPad = Array(samples[start...end].reversed())
                }
            }
            
            var rightPad: [Float] = []
            if padding > 0 {
                // indices: (n-1-padding) to (n-2)
                // Python: pad=2, [0,1,2] -> [0,1,2, 1,0]
                // indices reflected around last element (2): 1, 0
                // indices: n-2 down to n-1-padding
                
                let start = max(0, n - 1 - padding)
                let end = n - 2
                if end >= start {
                    rightPad = Array(samples[start...end].reversed())
                }
            }
            
            let result = leftPad + samples + rightPad
            return MLXArray(result)
        }
    }
