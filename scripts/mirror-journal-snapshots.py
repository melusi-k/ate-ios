#!/usr/bin/env python3
"""Mirror retained Journal PNG attachments after XCTest, without runner stdout writes."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re


def mirror(raw_directory: Path, output: Path) -> int:
    raw = raw_directory.resolve()
    manifest = json.loads((raw / "manifest.json").read_text())
    output.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    # Output is a separate retained file, never the console or an in-flight test log.
    with output.open("w", encoding="utf-8") as stream:
        for case in manifest:
            if "JournalOpenStateUITests/" not in case.get("testIdentifier", ""):
                continue
            for attachment in case.get("attachments", []):
                filename = attachment["exportedFileName"]
                if Path(filename).suffix.lower() != ".png":
                    continue
                path = (raw / filename).resolve()
                if path.parent != raw:
                    raise ValueError("Attachment is outside the raw export directory")
                payload = path.read_bytes()
                if not payload.startswith(b"\x89PNG\r\n\x1a\n"):
                    raise ValueError("Expected retained PNG attachment: " + filename)
                suggested = attachment.get("suggestedHumanReadableName") or filename
                name = suggested.split("_0_", 1)[0]
                if name == suggested:
                    name = Path(suggested).stem
                name = re.sub(r"\s+", "_", name)
                encoded = base64.b64encode(payload).decode("ascii")
                stream.write("SNAPSHOT-SOURCE " + json.dumps({
                    "test": case["testIdentifier"], "exported_file": filename,
                    "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()
                }, sort_keys=True) + "\n")
                stream.write(f"SNAPSHOT-BEGIN {name} {len(encoded)}\n")
                for index in range(0, len(encoded), 4000):
                    stream.write(f"SNAPSHOT-CHUNK {name} {encoded[index:index + 4000]}\n")
                stream.write(f"SNAPSHOT-END {name}\n")
                count += 1
    if count == 0:
        raise ValueError("No JournalOpenStateUITests PNGs were exported; mirror is not established")
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-directory", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    count = mirror(args.raw_directory, args.output)
    print(f"Retained {count} exact Journal PNG mirrors in {args.output}; XCTest is already finished.")


if __name__ == "__main__":
    main()
