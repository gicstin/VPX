import json
import time
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
BASELINE_PATH = HERE / "baseline.json"
REGISTRY = []


def check(suite, name, quick=True):
    def wrap(fn):
        REGISTRY.append({"suite": suite, "name": name, "quick": quick, "fn": fn})
        return fn
    return wrap


class Context:
    def __init__(self, engine, quick, update_baseline, source_dir, verbose=False):
        self.verbose = verbose
        self.engine = engine
        self.quick = quick
        self.update_baseline = update_baseline
        self.source_dir = source_dir
        self.results = []
        self.current = None
        self.baseline = json.loads(BASELINE_PATH.read_text()) if BASELINE_PATH.exists() else {}
        self.baseline_new = {}
        self.metrics = {}

    def clips(self, synthetic_seconds=12, peak_db=-6.0):
        import signals
        count = 2 if self.quick else 6
        real = signals.real_clips(count)
        self.real_count = len(real)
        return [("synthetic program", signals.program(synthetic_seconds, peak_db=peak_db))] + real

    def real(self):
        import signals
        return signals.real_clips(2 if self.quick else 6)

    def seconds(self, full, quick):
        return quick if self.quick else full

    def _record(self, label, value, ok, limit_text):
        self.results.append({"check": self.current, "label": label, "value": value, "ok": bool(ok), "limit": limit_text})
        if self.verbose:
            print("      %s %-60s %s (need %s)" % ("ok  " if ok else "FAIL", label, _fmt(value), limit_text))
        self.metrics[self.current + " :: " + label] = value

    def le(self, label, value, limit, unit=""):
        self._record(label, float(value), float(value) <= limit, "<= %g%s" % (limit, unit))

    def ge(self, label, value, limit, unit=""):
        self._record(label, float(value), float(value) >= limit, ">= %g%s" % (limit, unit))

    def between(self, label, value, low, high, unit=""):
        self._record(label, float(value), low <= float(value) <= high, "in [%g, %g]%s" % (low, high, unit))

    def near(self, label, value, target, tolerance, unit=""):
        self._record(label, float(value), abs(float(value) - target) <= tolerance, "%g +/- %g%s" % (target, tolerance, unit))

    def true(self, label, condition, detail=""):
        self._record(label, detail if detail != "" else bool(condition), bool(condition), "true")

    def golden(self, key, value, tolerance, unit=""):
        value = float(value)
        if self.update_baseline:
            self.baseline_new[key] = value
            self._record(key, value, True, "recorded")
            return
        if key not in self.baseline:
            self._record(key + " (no baseline; run with --update-baseline)", value, False, "baseline")
            return
        reference = self.baseline[key]
        self._record(key, value, abs(value - reference) <= tolerance, "%g +/- %g%s" % (reference, tolerance, unit))


def run(context, selection=None, suites=None):
    started = time.time()
    selected = [item for item in REGISTRY
                if (not context.quick or item["quick"])
                and (suites is None or item["suite"] in suites)
                and (selection is None or selection in item["suite"] + "/" + item["name"])]
    for item in selected:
        context.current = item["suite"] + "/" + item["name"]
        begin = time.time()
        before = len(context.results)
        try:
            item["fn"](context)
        except Exception:
            context._record("exception", traceback.format_exc(limit=4).strip().splitlines()[-1], False, "no exception")
            print(traceback.format_exc())
        local = context.results[before:]
        failed = [r for r in local if not r["ok"]]
        print("%s %-48s %3d checks  %5.1fs" % ("FAIL" if failed else "ok  ", context.current, len(local), time.time() - begin), flush=True)
        for r in failed:
            print("      FAIL %s = %s (need %s)" % (r["label"], _fmt(r["value"]), r["limit"]), flush=True)
    if context.update_baseline:
        merged = dict(context.baseline)
        merged.update(context.baseline_new)
        BASELINE_PATH.write_text(json.dumps(merged, indent=1, sort_keys=True) + "\n")
    return time.time() - started


def _fmt(value):
    if isinstance(value, float):
        return "%.4g" % value
    return str(value)


def summarize(context, seconds, report_path):
    failures = [r for r in context.results if not r["ok"]]
    print("\nchecks=%d failures=%d time=%.1fs" % (len(context.results), len(failures), seconds))
    Path(report_path).parent.mkdir(parents=True, exist_ok=True)
    Path(report_path).write_text(json.dumps({"results": context.results, "failures": len(failures)}, indent=1, default=str))
    return 1 if failures else 0
