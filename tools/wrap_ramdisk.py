#!/usr/bin/env python3
"""Wrap ramdisk.img into the kernel-less boot-format image that the EMUI8 bootloader loads from the "ramdisk" partition
(mmcblk0p31). Every header field except the sizes/hash is taken from a known-good dump (prebuilt/ramdisk_p31_header.bin).

usage: wrap_ramdisk.py <mkbootimg> <ramdisk.img> <known-good header (2048 bytes)> <out.img>"""
import hashlib, os, struct, subprocess, sys, tempfile

mk, rd, hdr, out = sys.argv[1:5]
old = open(hdr, 'rb').read(2048)
with tempfile.NamedTemporaryFile() as empty:
    subprocess.check_call([sys.executable, mk, '--kernel', empty.name, '--ramdisk', rd, '--cmdline', 'buildvariant=user',
                           '--base', '0x10000000', '--pagesize', '2048', '--kernel_offset', '0x00008000',
                           '--ramdisk_offset', '0x01000000', '--second_offset', '0x00f00000', '--tags_offset', '0x00000100',
                           '--os_version', '9.0.0', '--os_patch_level', '2019-10', '--header_version', '0', '--output', out])
d = bytearray(open(out, 'rb').read())
ks, ka, rs, ra, ss, sa, ta, ps, hv, osv = struct.unpack('<10I', bytes(d[8:48]))
pad = lambda n: (n + ps - 1) // ps * ps
k = bytes(d[ps:ps + ks]); r = bytes(d[ps + pad(ks):ps + pad(ks) + rs]); s = bytes(d[ps + pad(ks) + pad(rs):ps + pad(ks) + pad(rs) + ss])
d[28:32] = old[28:32]   # second_addr
d[44:48] = old[44:48]   # os_version / patch level
h = hashlib.sha1()
for blob, n in ((k, ks), (r, rs), (s, ss)):
    h.update(blob); h.update(struct.pack('<I', n))
d[576:596] = h.digest()
open(out, 'wb').write(bytes(d))
