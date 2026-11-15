from pathlib import Path
import hashlib,subprocess,unittest,yaml
ROOT=Path(__file__).resolve().parents[2]
BASE="379d96fc855a8a54e58e2caa25fb5a96199963ad"
PAIRS={'Ate/App/AteApp.swift': [('        .onPreferenceChange(BottomChromeMinYKey.self) { value in\n            #if DEBUG\n            QA8DetailLayoutDiagnostic.event("root-chrome-min-y", value: value.map { Double($0) },\n                previous: bottomChromeMinY.map { Double($0) })\n            #endif\n            bottomChromeMinY = value\n        }\n', '        .onPreferenceChange(BottomChromeMinYKey.self) { bottomChromeMinY = $0 }\n'), ('        QA8DetailLayoutDiagnostic.beginExit()\n', ''), ('        QA8DetailLayoutDiagnostic.event("exit-return")\n', '')], 'Ate/Views/RecipeDetailView.swift': [('        .onPreferenceChange(RecipeDetailHostBottomYKey.self) { value in\n            #if DEBUG\n            QA8DetailLayoutDiagnostic.event("detail-host-bottom", value: value.map { Double($0) },\n                previous: hostBottomY.map { Double($0) }, reserve: Double(footerChromeReserve))\n            #endif\n            hostBottomY = value\n        }\n', '        .onPreferenceChange(RecipeDetailHostBottomYKey.self) { hostBottomY = $0 }\n'), ('            #if DEBUG\n            let gaps = QA8DetailLayoutDiagnostic.quality { RecipeQuality.issues(recipe) }\n            #else\n', ''), ('            #endif\n', ''), ('\n#if DEBUG\n/// Numeric-only, bounded instrumentation for the existing QA8 Exit diagnostic.\n/// No observable state, recipe content, new geometry queries, tasks or timers.\n@MainActor\nenum QA8DetailLayoutDiagnostic {\n    private static var counts: [String: Int] = [:]\n    private static var rows: [String] = []\n    private static var armed = false\n    private static var qualityMaxMS = 0.0\n    private static var enabled: Bool {\n        AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains("-qaQA8ExitFileDiagnostic")\n    }\n    static func beginExit() {\n        guard enabled else { return }\n        armed = true\n        counts = [:]\n        rows = []\n        qualityMaxMS = 0\n        event("exit-enter")\n    }\n    static func quality<T>(_ calculate: () -> T) -> T {\n        guard enabled, armed else { return calculate() }\n        event("quality-begin")\n        let started = ProcessInfo.processInfo.systemUptime\n        let result = calculate()\n        let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000\n        qualityMaxMS = max(qualityMaxMS, elapsed)\n        event("quality-end", value: elapsed, previous: qualityMaxMS)\n        return result\n    }\n    static func event(_ phase: String, value: Double? = nil, previous: Double? = nil, reserve: Double? = nil) {\n        guard enabled, armed, rows.count < 64 else { return }\n        let count = (counts[phase] ?? 0) + 1\n        counts[phase] = count\n        // First four then powers of two: bounded disk writes even if layout churns.\n        guard count <= 4 || count & (count - 1) == 0 else { return }\n        func number(_ value: Double?) -> String { value.map { String($0) } ?? "nil" }\n        rows.append("pid=\\(ProcessInfo.processInfo.processIdentifier) phase=\\(phase) count=\\(count) uptime=\\(ProcessInfo.processInfo.systemUptime) value=\\(number(value)) previous=\\(number(previous)) reserve=\\(number(reserve))")\n        guard let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }\n        do {\n            try Data((rows.joined(separator: "\\n") + "\\n").utf8).write(\n                to: cache.appendingPathComponent("qa8-detail-layout-\\(ProcessInfo.processInfo.processIdentifier).txt"), options: .atomic)\n        } catch {\n            // A numeric marker in the existing test log, not recipe/private values.\n            print("QA8-DETAIL numeric-file-write-failed")\n        }\n    }\n}\n#endif\n', '')], '.github/workflows/dogfood-qualification.yml': [('          # Bounded numeric layout/quality events share the existing QA8 diagnostic flag.\n          mkdir -p qa8-target-sample\n          if [ -n "${data_container:-}" ]; then\n            for evidence in "$data_container"/Library/Caches/qa8-detail-layout-*.txt; do\n              if [ -f "$evidence" ]; then cp "$evidence" qa8-target-sample/; fi\n            done\n          fi\n', '')]}

def restore_detail_capture(test, text, file):
    for new,old in PAIRS[file]:
        test.assertEqual(text.count(new),1,(file,new[:100]))
        text=text.replace(new,old,1)
    return text

class DetailLayoutCaptureTests(unittest.TestCase):
    def test_exact_original_product_and_workflow_survive(self):
        for file in PAIRS:
            baseline=subprocess.check_output(['git','show',BASE+':'+file],cwd=ROOT,text=True)
            self.assertEqual(restore_detail_capture(self,(ROOT/file).read_text(),file),baseline)
    def test_quality_once_and_no_cache_or_async_work(self):
        source=(ROOT/'Ate/Views/RecipeDetailView.swift').read_text()
        s=source.split('enum QA8DetailLayoutDiagnostic {',1)[1]
        for token in ['AppConfig.isUITesting','-qaQA8ExitFileDiagnostic','rows.count < 64','count <= 4 || count & (count - 1) == 0','armed = true','counts = [:]','qualityMaxMS = 0','let result = calculate()','return result','.atomic']:
            self.assertIn(token,s)
        for token in ['@State','Task','Timer','GeometryReader','NSRegularExpression','UserDefaults','sleep','async','recipeID','instruction']:
            self.assertNotIn(token,s)
        self.assertEqual(s.count('let result = calculate()'),1)
        self.assertEqual(source.count('let gaps = QA8DetailLayoutDiagnostic.quality { RecipeQuality.issues(recipe) }'),1)
        start=s.index('let started = ProcessInfo.processInfo.systemUptime')
        finish=s.index('let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000')
        self.assertEqual(s[start:finish].count('event('),0)
    def test_no_test_or_logic_or_budget_edits(self):
        for folder in ['AteUITests','AteTests','Ate/Logic']:
            self.assertEqual(subprocess.check_output(['git','diff',BASE,'--',folder],cwd=ROOT),b'')
        source=(ROOT/'.github/workflows/dogfood-qualification.yml').read_text()
        for job in yaml.safe_load(source)['jobs'].values():
            for step in job.get('steps',[]):
                if 'run' in step:
                    result=subprocess.run(['bash','-n'],input=step['run'],text=True,capture_output=True)
                    self.assertEqual(result.returncode,0,result.stderr)
    def test_row_decimation_is_bounded(self):
        phases=['quality-begin','quality-end','detail-host-bottom','root-chrome-min-y']
        counts={};rows=[]
        for _ in range(10000):
            for phase in phases:
                if len(rows)>=64:continue
                n=counts.get(phase,0)+1;counts[phase]=n
                if n<=4 or n & (n-1)==0:rows.append((phase,n))
        self.assertLessEqual(len(rows),64)
        self.assertIn(('quality-end',1024),rows)
