#!/usr/bin/env python3
"""Summarize xctrace's exported time-profile XML; inclusive stacks overlap."""
import argparse
from collections import Counter
import json
import pathlib
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--start-seconds", type=float, default=0)
    parser.add_argument("--end-seconds", type=float)
    args = parser.parse_args()
    root = ET.parse(args.input).getroot()
    identifiers = {element.attrib["id"]: element for element in root.iter() if "id" in element.attrib}

    def resolve(element):
        return identifiers[element.attrib["ref"]] if "ref" in element.attrib else element

    inclusive = Counter()
    own = Counter()
    total = main_thread = samples = 0
    for row in root.findall(".//row"):
        backtrace = row.find("tagged-backtrace")
        if backtrace is None:
            continue
        timestamp = int(resolve(row.find("sample-time")).text) / 1e9
        if timestamp < args.start_seconds or (args.end_seconds is not None and timestamp > args.end_seconds):
            continue
        weight = int(resolve(row.find("weight")).text)
        names = [resolve(frame).get("name", "unknown") for frame in resolve(backtrace).findall("frame")]
        samples += 1
        total += weight
        if "Main Thread" in resolve(row.find("thread")).get("fmt", ""):
            main_thread += weight
        for name in set(names):
            inclusive[name] += weight
        if names:
            own[names[0]] += weight
    if not total:
        raise ValueError("No weighted time-profile samples; inspect the trace recording issues")

    def entries(counts):
        return [{"symbol": symbol, "sampled_seconds": value / 1e9, "percent": value / total * 100}
                for symbol, value in counts]

    relevant = [(name, value) for name, value in inclusive.most_common()
                if any(key in name for key in ["ChatTimelineCollectionCell", "SelectableChatText", "ChatTimelineStore"])]
    result = {"samples": samples, "sampled_seconds": total / 1e9,
              "start_seconds": args.start_seconds, "end_seconds": args.end_seconds,
              "main_thread_sampled_seconds": main_thread / 1e9,
              "note": "Statistical CPU samples, not elapsed time. Inclusive symbols overlap; do not add percentages.",
              "relevant_inclusive": entries(relevant),
              "top_inclusive": entries(inclusive.most_common(30)), "top_own": entries(own.most_common(20))}
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({key: result[key] for key in ["samples", "sampled_seconds", "main_thread_sampled_seconds"]}, indent=2))


if __name__ == "__main__":
    main()
