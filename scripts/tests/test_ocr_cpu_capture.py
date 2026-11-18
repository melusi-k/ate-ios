from pathlib import Path
import unittest,hashlib
ROOT=Path(__file__).resolve().parents[2]
class OCRCPUCaptureContracts(unittest.TestCase):
    def test_only_observation_changes(self):
        s=(ROOT/"Ate/Services/OnDeviceBackend.swift").read_text()
        self.assertEqual(s.count('\n#if DEBUG\nextension PhotoImportDiagnostics {\n    /// Two actual OCR unit fixtures opt in via their already-supplied diagnostic.\n    /// Per-worker six-point maximum, no polling or synchronization/timeout decision.\n    func cpuCapture() -> OCRCPUPhaseCapture { OCRCPUPhaseCapture(trace: id) }\n}\n\nstruct OCRCPUPhaseCapture {\n    let trace: String\n    private let started = ProcessInfo.processInfo.systemUptime\n    private let startedCPU = clock()\n    private static let logger = Logger(subsystem: "com.melusik.ate", category: "photo-import-cpu")\n    func mark(_ phase: String) {\n        let wall = ProcessInfo.processInfo.systemUptime - started\n        let cpu = Double(clock() - startedCPU) / Double(CLOCKS_PER_SEC)\n        let info = ProcessInfo.processInfo\n        // CPU is THIS PROCESS aggregate, not Vision service or host CPU. Ratios\n        // are diagnostic only, never proof of contention or an optimization verdict.\n        Self.logger.notice("trace=\\(trace, privacy: .public) phase=\\(phase, privacy: .public) wall_s=\\(wall, privacy: .public) process_cpu_s=\\(cpu, privacy: .public) active_cpus=\\(info.activeProcessorCount, privacy: .public) thermal=\\(info.thermalState.rawValue, privacy: .public) uptime=\\(info.systemUptime, privacy: .public)")\n    }\n}\n#endif\n'),1)
        s=s.replace('\n#if DEBUG\nextension PhotoImportDiagnostics {\n    /// Two actual OCR unit fixtures opt in via their already-supplied diagnostic.\n    /// Per-worker six-point maximum, no polling or synchronization/timeout decision.\n    func cpuCapture() -> OCRCPUPhaseCapture { OCRCPUPhaseCapture(trace: id) }\n}\n\nstruct OCRCPUPhaseCapture {\n    let trace: String\n    private let started = ProcessInfo.processInfo.systemUptime\n    private let startedCPU = clock()\n    private static let logger = Logger(subsystem: "com.melusik.ate", category: "photo-import-cpu")\n    func mark(_ phase: String) {\n        let wall = ProcessInfo.processInfo.systemUptime - started\n        let cpu = Double(clock() - startedCPU) / Double(CLOCKS_PER_SEC)\n        let info = ProcessInfo.processInfo\n        // CPU is THIS PROCESS aggregate, not Vision service or host CPU. Ratios\n        // are diagnostic only, never proof of contention or an optimization verdict.\n        Self.logger.notice("trace=\\(trace, privacy: .public) phase=\\(phase, privacy: .public) wall_s=\\(wall, privacy: .public) process_cpu_s=\\(cpu, privacy: .public) active_cpus=\\(info.activeProcessorCount, privacy: .public) thermal=\\(info.thermalState.rawValue, privacy: .public) uptime=\\(info.systemUptime, privacy: .public)")\n    }\n}\n#endif\n','',1)
        self.assertEqual(s.count('                        #if DEBUG\n                        cpuCapture?.mark("perform-error")\n                        #endif\n'),1)
        s=s.replace('                        #if DEBUG\n                        cpuCapture?.mark("perform-error")\n                        #endif\n','',1)
        self.assertEqual(s.count('                        #if DEBUG\n                        cpuCapture?.mark("candidates-extracted")\n                        #endif\n'),1)
        s=s.replace('                        #if DEBUG\n                        cpuCapture?.mark("candidates-extracted")\n                        #endif\n','',1)
        self.assertEqual(s.count('                        let handler = VNImageRequestHandler(cgImage: cg)\n                        #if DEBUG\n                        cpuCapture?.mark("handler-created-perform-enter")\n                        #endif\n                        try handler.perform([req])\n                        #if DEBUG\n                        cpuCapture?.mark("perform-return")\n                        #endif\n'),1)
        s=s.replace('                        let handler = VNImageRequestHandler(cgImage: cg)\n                        #if DEBUG\n                        cpuCapture?.mark("handler-created-perform-enter")\n                        #endif\n                        try handler.perform([req])\n                        #if DEBUG\n                        cpuCapture?.mark("perform-return")\n                        #endif\n','                        try VNImageRequestHandler(cgImage: cg).perform([req])\n',1)
        self.assertEqual(s.count('                    #if DEBUG\n                    cpuCapture?.mark("request-configured")\n                    #endif\n'),1)
        s=s.replace('                    #if DEBUG\n                    cpuCapture?.mark("request-configured")\n                    #endif\n','',1)
        self.assertEqual(s.count('                    #if DEBUG\n                    let cpuCapture = suppliedDiagnostic?.cpuCapture()\n                    cpuCapture?.mark("request-create-enter")\n                    #endif\n'),1)
        s=s.replace('                    #if DEBUG\n                    let cpuCapture = suppliedDiagnostic?.cpuCapture()\n                    cpuCapture?.mark("request-create-enter")\n                    #endif\n','',1)
        self.assertEqual(s.count('#if DEBUG\nimport Darwin\n#endif\n'),1)
        s=s.replace('#if DEBUG\nimport Darwin\n#endif\n','',1)
        # fix/import-source-fidelity: remove only its exact reviewed wiring delta, then the
        # original reviewed remainder hash below must still hold.
        self.assertEqual(s.count('\n        /// Pre-model source recognition shared by every extraction input (pasted recipe,\n        /// social caption, fetched page): verified structure binds generation below, and\n        /// recognizable-but-unverifiable structure fails closed instead of reaching a demo\n        /// fallback or creative generation.\n        var structuredSource: SourceRecipeFidelity.Contract?\n        var unverifiableSource = false\n        if request.mode == .prompt {\n            switch SourceRecipeFidelity.extraction(request.text ?? "") {\n            case .verified(let contract): structuredSource = contract\n            case .unverifiable: unverifiableSource = true\n            case .none: break\n            }\n        }'),1)
        s=s.replace('\n        /// Pre-model source recognition shared by every extraction input (pasted recipe,\n        /// social caption, fetched page): verified structure binds generation below, and\n        /// recognizable-but-unverifiable structure fails closed instead of reaching a demo\n        /// fallback or creative generation.\n        var structuredSource: SourceRecipeFidelity.Contract?\n        var unverifiableSource = false\n        if request.mode == .prompt {\n            switch SourceRecipeFidelity.extraction(request.text ?? "") {\n            case .verified(let contract): structuredSource = contract\n            case .unverifiable: unverifiableSource = true\n            case .none: break\n            }\n        }','',1)
        self.assertEqual(s.count('\n            switch SourceRecipeFidelity.extraction(caption) {\n            case .verified(let contract): structuredSource = contract\n            case .unverifiable: unverifiableSource = true\n            case .none: break\n            }'),1)
        s=s.replace('\n            switch SourceRecipeFidelity.extraction(caption) {\n            case .verified(let contract): structuredSource = contract\n            case .unverifiable: unverifiableSource = true\n            case .none: break\n            }','',1)
        self.assertEqual(s.count("\n            // Bind the creative pass to the page's own explicit ingredients and method when\n            // it has them: the model must not rename the dish, swap listed ingredients or\n            // rewrite written times, and an altered extraction fails closed instead of\n            // reaching the review sheet.\n            switch SourceRecipeFidelity.extraction(String(Self.htmlToText(html).prefix(3500))) {\n            case .verified(let contract): structuredSource = contract\n            case .unverifiable: unverifiableSource = true\n            case .none: break\n            }"),1)
        s=s.replace("\n            // Bind the creative pass to the page's own explicit ingredients and method when\n            // it has them: the model must not rename the dish, swap listed ingredients or\n            // rewrite written times, and an altered extraction fails closed instead of\n            // reaching the review sheet.\n            switch SourceRecipeFidelity.extraction(String(Self.htmlToText(html).prefix(3500))) {\n            case .verified(let contract): structuredSource = contract\n            case .unverifiable: unverifiableSource = true\n            case .none: break\n            }",'',1)
        self.assertEqual(s.count('            if structuredSource != nil {\n                throw BackendError(message: "On-device AI isn\'t available to extract this recipe. No demo recipe was substituted; keep the source and enter it manually or try again when the model is ready.")\n            }\n            if unverifiableSource {\n                throw BackendError(message: "On-device AI isn\'t available and this recipe\'s ingredients and method could not be verified. No demo recipe was substituted; enter it manually or try again when the model is ready.")\n            }'),1)
        s=s.replace('            if structuredSource != nil {\n                throw BackendError(message: "On-device AI isn\'t available to extract this recipe. No demo recipe was substituted; keep the source and enter it manually or try again when the model is ready.")\n            }\n            if unverifiableSource {\n                throw BackendError(message: "On-device AI isn\'t available and this recipe\'s ingredients and method could not be verified. No demo recipe was substituted; enter it manually or try again when the model is ready.")\n            }','            if SourceRecipeFidelity.inlineCaption(socialCaption ?? request.text ?? "") != nil {\n                throw BackendError(message: "On-device AI isn\'t available to extract this recipe. No demo recipe was substituted; keep the source and enter it manually or try again when the model is ready.")\n            }',1)
        self.assertEqual(s.count('\n        // A recognizable recipe structure that could not be verified is refused honestly;\n        // it never falls through to ungated creative generation.\n        if unverifiableSource {\n            throw BackendError(message: "Ate couldn\'t verify this recipe\'s ingredients and method. No recipe was generated. Enter it manually or paste the recipe in a clearer Ingredients and Method layout.")\n        }'),1)
        s=s.replace('\n        // A recognizable recipe structure that could not be verified is refused honestly;\n        // it never falls through to ungated creative generation.\n        if unverifiableSource {\n            throw BackendError(message: "Ate couldn\'t verify this recipe\'s ingredients and method. No recipe was generated. Enter it manually or paste the recipe in a clearer Ingredients and Method layout.")\n        }','',1)
        self.assertEqual(s.count('fidelity = structuredSource\n            if let fidelity {'),1)
        s=s.replace('fidelity = structuredSource\n            if let fidelity {','fidelity = SourceRecipeFidelity.inlineCaption(text)\n            if let fidelity {',1)
        self.assertEqual(s.count('contextSource = socialCaption!  // short dish-defining source\n            fidelity = structuredSource\n'),1)
        s=s.replace('contextSource = socialCaption!  // short dish-defining source\n            fidelity = structuredSource\n','contextSource = socialCaption!  // short dish-defining source\n            fidelity = SourceRecipeFidelity.inlineCaption(socialCaption!)\n',1)
        self.assertEqual(s.count('\n            fidelity = structuredSource ?? SourceRecipeFidelity.structuredRecipe(page)'),1)
        s=s.replace('\n            fidelity = structuredSource ?? SourceRecipeFidelity.structuredRecipe(page)','',1)
        # fix/import-source-fidelity: htmlToText now preserves list/br/block boundaries as
        # newlines for defensible item boundaries; inverse-restore the original body before
        # the reviewed remainder hash below.
        self.assertEqual(s.count(r'''    static func htmlToText(_ html: String) -> String {
        var s = html
        for p in ["<script[\\s\\S]*?</script>", "<style[\\s\\S]*?</style>"] {
            s = s.replacingOccurrences(of: p, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        // Item boundaries must survive into the text: list items, line breaks and block
        // ends become newlines BEFORE the remaining tags are stripped, so a recipe
        // page's ingredient list keeps one line per item. Without an explicit boundary
        // the import refuses to verify a collapsed multi-item line rather than guessing
        // where one name ends and the next item starts.
        for p in ["<br[^>]*>", "<li[^>]*>", "</(?:li|p|div|h[1-6]|tr|ul|ol)>"] {
            s = s.replacingOccurrences(of: p, with: "\n", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: [.regularExpression, .caseInsensitive])
        for (a, b) in ["&amp;": "&", "&nbsp;": " ", "&#39;": "'", "&quot;": "\"", "&lt;": "<", "&gt;": ">"] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        // Collapse spaces/tabs within each line; newlines survive, empty lines drop.
        return s.components(separatedBy: .newlines).map {
            $0.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }.joined(separator: "\n")
    }'''),1)
        s=s.replace(r'''    static func htmlToText(_ html: String) -> String {
        var s = html
        for p in ["<script[\\s\\S]*?</script>", "<style[\\s\\S]*?</style>"] {
            s = s.replacingOccurrences(of: p, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        // Item boundaries must survive into the text: list items, line breaks and block
        // ends become newlines BEFORE the remaining tags are stripped, so a recipe
        // page's ingredient list keeps one line per item. Without an explicit boundary
        // the import refuses to verify a collapsed multi-item line rather than guessing
        // where one name ends and the next item starts.
        for p in ["<br[^>]*>", "<li[^>]*>", "</(?:li|p|div|h[1-6]|tr|ul|ol)>"] {
            s = s.replacingOccurrences(of: p, with: "\n", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: [.regularExpression, .caseInsensitive])
        for (a, b) in ["&amp;": "&", "&nbsp;": " ", "&#39;": "'", "&quot;": "\"", "&lt;": "<", "&gt;": ">"] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        // Collapse spaces/tabs within each line; newlines survive, empty lines drop.
        return s.components(separatedBy: .newlines).map {
            $0.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }.joined(separator: "\n")
    }''',r'''    static func htmlToText(_ html: String) -> String {
        var s = html
        for p in ["<script[\\s\\S]*?</script>", "<style[\\s\\S]*?</style>", "<[^>]+>"] {
            s = s.replacingOccurrences(of: p, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        for (a, b) in ["&amp;": "&", "&nbsp;": " ", "&#39;": "'", "&quot;": "\"", "&lt;": "<", "&gt;": ">"] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }''',1)
        self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),'66c479d5fc1510505c1a9478ae0411ce05ade7665b0e7e9c16d89f81ee2e70f1')
