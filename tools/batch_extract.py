#!/usr/bin/env python3
"""Batch-fill gaps in extract_full/<partition>/ using the VLE+LZ4 decoder,
for every file the earlier mount+rsync pass (desktop kernel's generic
erofs.ko, which lacks Huawei's out-of-tree legacy-format support) failed on.

For each partition: walk the full path listing (<partition>_tree.txt),
and for every regular file missing (or zero-byte) under extract_full/,
resolve its NID via dump.erofs --path and decode it with vle_extract.
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import vle_extract as vle

WORK = "/home/tobim6/AGS2_LOS16/work"
DUMP = f"{WORK}/erofs-utils/dump/dump.erofs"

NID_RE = re.compile(r"NID:\s*(\d+)")


def get_nid(image, path):
    r = subprocess.run([DUMP, f"--path={path}", image],
                        capture_output=True, text=True)
    m = NID_RE.search(r.stdout)
    if not m:
        return None
    return int(m.group(1))


def run(partition, image_rel):
    image = f"{WORK}/{image_rel}"
    tree_file = f"{WORK}/{partition}_tree.txt"
    out_root = f"{WORK}/extract_full/{partition}"
    fail_log = open(f"{WORK}/{partition}_batch_fail.log", "w")

    done = skip = fail = 0
    with open(tree_file) as f:
        paths = [l.rstrip("\n") for l in f if not l.rstrip("\n").endswith("/")]

    for p in paths:
        local = os.path.join(out_root, p.lstrip("/"))
        if os.path.exists(local) and os.path.getsize(local) > 0:
            skip += 1
            continue
        nid = get_nid(image, p)
        if nid is None:
            fail_log.write(f"NO_NID\t{p}\n")
            fail += 1
            continue
        os.makedirs(os.path.dirname(local), exist_ok=True)
        ok, msg = vle.extract_one(image, nid, local)
        if ok:
            done += 1
        else:
            fail_log.write(f"{msg}\t{p}\n")
            fail += 1
            if os.path.exists(local) and os.path.getsize(local) == 0:
                os.remove(local)

    fail_log.close()
    print(f"{partition}: extracted={done} already_had={skip} failed={fail}")


if __name__ == "__main__":
    for partition, image_rel in (("vendor", "vendor.raw.img"),
                                  ("product", "product.raw.img"),
                                  ("odm", "odm.raw.img"),
                                  ("system", "system.raw.img")):
        run(partition, image_rel)
