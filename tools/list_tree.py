#!/usr/bin/env python3
"""Recursively list every path in an EROFS image using dump.erofs --ls,
independent of whether file content can be decoded. Prints one path per
line, directories suffixed with /."""
import subprocess
import sys
import re

DUMP = "/home/tobim6/AGS2_LOS16/work/erofs-utils/dump/dump.erofs"
LS_ROW = re.compile(r"^\s*(\d+)\s+(\d+)\s+(.+)$")

def list_dir(image, path):
    r = subprocess.run([DUMP, f"--path={path}", "--ls", image],
                        capture_output=True, text=True)
    if r.returncode != 0 or "<E>" in r.stdout + r.stderr:
        return None
    entries = []
    in_table = False
    for line in r.stdout.splitlines():
        if line.strip().startswith("NID"):
            in_table = True
            continue
        if in_table:
            m = LS_ROW.match(line)
            if m:
                nid, typ, name = m.groups()
                entries.append((name.strip(), int(typ)))
    return entries

def walk(image, path, out):
    entries = list_dir(image, path)
    if entries is None:
        print(f"UNREADABLE_DIR\t{path}", file=sys.stderr)
        return
    for name, typ in entries:
        if name in (".", ".."):
            continue
        childpath = path.rstrip("/") + "/" + name
        if typ == 2:
            out.write(childpath + "/\n")
            walk(image, childpath, out)
        else:
            out.write(childpath + "\n")

if __name__ == "__main__":
    image, outpath = sys.argv[1], sys.argv[2]
    with open(outpath, "w") as out:
        walk(image, "/", out)
    print("done")
