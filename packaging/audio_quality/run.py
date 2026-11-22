import argparse
import importlib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import engine as engine_module
import harness

SUITE_MODULES = ["transparency", "response", "imaging", "dynamics", "robustness", "surround", "filters", "spatialextras", "realmusic"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--only", default=None)
    parser.add_argument("--source", default=None)
    parser.add_argument("--update-baseline", action="store_true")
    parser.add_argument("-v", "--verbose", action="store_true")
    parser.add_argument("--music", default=None)
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--report", default=str(engine_module.BUILD / "report.json"))
    args = parser.parse_args()
    for name in SUITE_MODULES:
        importlib.import_module("suites." + name)
    if args.list:
        for item in harness.REGISTRY:
            print("%-14s %-40s %s" % (item["suite"], item["name"], "quick" if item["quick"] else "full"))
        return 0
    if args.music:
        import signals
        names = signals.build_music_cache(args.music)
        print("cached %d real tracks from %s: %s" % (len(names), args.music, ", ".join(names)))
    source = Path(args.source) if args.source else engine_module.assemble_source(engine_module.BUILD / "source")
    engine = engine_module.Engine(source)
    context = harness.Context(engine, args.quick, args.update_baseline, source, args.verbose)
    seconds = harness.run(context, args.only)
    return harness.summarize(context, seconds, args.report)


if __name__ == "__main__":
    sys.exit(main())
