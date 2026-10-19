#!/usr/bin/env python3
"""Standalone userspace reader for Huawei's legacy EROFS "VLE" compressed
inode format (drivers/staging/erofs circa 2017-2018, CONFIG_EROFS_FS_HUAWEI_EXTENSION).

Transcribed as literally as possible from the GPL kernel source
(fs/erofs/{erofs_fs.h,inode.c,unzip_vle.c,unzip_vle_lz4.c,unzip_lz4.c,internal.h})
rather than re-derived, to avoid misinterpreting the backward-chaining
semantics of the Huawei-specific cluster type. Compression itself is
standard LZ4 (fs/erofs/unzip_lz4.c uses generic/lz4.h, a vanilla decoder --
confirmed by inspection; LZ4M, also present in this kernel release, is used
elsewhere, not by EROFS).

Usage: vle_extract.py <image> <nid> <out_file>
"""
import ctypes
import os
import struct
import sys

EROFS_BLKSIZ = 4096
ISLOTBITS = 5           # ffs(sizeof(erofs_inode_v1)=32) - 1
CLUSTERBITS = 12         # = blkszbits; cluster size == 1 block (CLUSTER_PAGE_LIMIT=1)
CLUSTERSIZE = 1 << CLUSTERBITS

PLAIN, HEAD, NONHEAD, HUAWEI_COMPAT = 0, 1, 2, 3

liblz4 = ctypes.CDLL("liblz4.so.1")
liblz4.LZ4_decompress_safe_partial.restype = ctypes.c_int
liblz4.LZ4_decompress_safe_partial.argtypes = [
    ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]


def lz4_decompress_safe(src: bytes, target_len: int) -> bytes:
    # Mirrors the kernel's own __lz4_decompress_safe_partial (generic/lz4.h):
    # stop exactly at target_len, even mid-token, rather than requiring the
    # full final literal/match run -- plain LZ4_decompress_safe can't do
    # that and either overruns into trailing block padding (oversized
    # capacity) or fails outright (exact-sized capacity).
    cap = target_len + CLUSTERSIZE  # dst buffer headroom only, not a target
    buf = ctypes.create_string_buffer(cap)
    n = liblz4.LZ4_decompress_safe_partial(src, buf, len(src), target_len, cap)
    if n < 0:
        raise ValueError(f"LZ4_decompress_safe_partial failed, ret={n}")
    return buf.raw[:n]


class DI:
    __slots__ = ("advise", "clusterofs", "u")

    def __init__(self, advise, clusterofs, u):
        self.advise = advise
        self.clusterofs = clusterofs
        self.u = u  # raw 4 bytes

    @property
    def ctype(self):
        return self.advise & 0x3

    @property
    def blkaddr(self):
        return struct.unpack_from("<I", self.u, 0)[0]

    @property
    def delta0(self):
        return struct.unpack_from("<H", self.u, 0)[0]

    @property
    def huawei_prev(self):
        return (self.clusterofs // CLUSTERSIZE) | (((self.advise >> 4) & 0xF) << 4)


class Image:
    def __init__(self, path):
        self.f = open(path, "rb")
        self._read_superblock()

    def _read_superblock(self):
        self.f.seek(1024)
        sb = self.f.read(128)
        magic = struct.unpack_from("<I", sb, 0)[0]
        if magic != 0xE0F5E1E2:
            raise ValueError(f"bad magic {magic:#x}")
        blkszbits = sb[12]
        assert blkszbits == 12, f"unexpected blkszbits {blkszbits}"
        self.meta_blkaddr = struct.unpack_from("<I", sb, 40)[0]

    def pread(self, offset, size):
        self.f.seek(offset)
        data = self.f.read(size)
        if len(data) != size:
            raise EOFError(f"short read at {offset}, wanted {size} got {len(data)}")
        return data

    def iloc(self, nid):
        return self.meta_blkaddr * EROFS_BLKSIZ + (nid << ISLOTBITS)

    def read_inode(self, nid):
        base = self.iloc(nid)
        hdr = self.pread(base, 32)
        i_advise = struct.unpack_from("<H", hdr, 0)[0]
        version = i_advise & 0x1
        data_mapping_mode = (i_advise >> 1) & 0x7
        if version == 1:  # V2, 64 bytes
            hdr = self.pread(base, 64)
            i_xattr_icount = struct.unpack_from("<H", hdr, 2)[0]
            i_mode = struct.unpack_from("<H", hdr, 4)[0]
            i_size = struct.unpack_from("<Q", hdr, 8)[0]
            inode_isize = 64
        else:  # V1, 32 bytes
            i_xattr_icount = struct.unpack_from("<H", hdr, 2)[0]
            i_mode = struct.unpack_from("<H", hdr, 4)[0]
            i_size = struct.unpack_from("<I", hdr, 8)[0]
            inode_isize = 32
        xattr_isize = 0 if i_xattr_icount == 0 else 12 + 4 * (i_xattr_icount - 1)
        return {
            "nid": nid, "data_mapping_mode": data_mapping_mode,
            "i_size": i_size, "inode_isize": inode_isize,
            "xattr_isize": xattr_isize, "i_mode": i_mode,
        }

    def extent_base(self, inode):
        base = self.iloc(inode["nid"])
        meta_ofs = inode["inode_isize"] + inode["xattr_isize"]
        meta_ofs = (meta_ofs + 7) & ~7
        return base + meta_ofs + 16

    def read_index(self, inode, lcn) -> DI:
        off = self.extent_base(inode) + lcn * 8
        raw = self.pread(off, 8)
        advise, clusterofs = struct.unpack_from("<HH", raw, 0)
        return DI(advise, clusterofs, raw[4:8])

    # --- literal transcription of vle_decompressed_index_clusterofs ---
    def decompressed_index_clusterofs(self, di: DI):
        t = di.ctype
        if t == NONHEAD:
            return CLUSTERSIZE
        if t == HUAWEI_COMPAT:
            if di.huawei_prev:
                return CLUSTERSIZE
            # fallthrough to PLAIN/HEAD
            return di.clusterofs
        if t in (PLAIN, HEAD):
            return di.clusterofs
        raise ValueError(f"bad cluster type {t}")

    # --- literal transcription of vle_get_logical_extent_head ---
    def get_logical_extent_head(self, lcn):
        di = self.read_index(self.inode, lcn)
        t = di.ctype
        if t == NONHEAD:
            delta0 = di.delta0
            if not delta0 or delta0 > lcn:
                raise ValueError(f"invalid NONHEAD delta0={delta0} at lcn {lcn}")
            return self.get_logical_extent_head(lcn - delta0)
        if t == PLAIN:
            pass  # flags ^= ZIPPED in the kernel; irrelevant here, fallthrough
        if t in (PLAIN, HUAWEI_COMPAT):
            if t == HUAWEI_COMPAT:
                lcn = lcn - di.huawei_prev
            # fallthrough to HEAD
        if t in (PLAIN, HUAWEI_COMPAT, HEAD):
            ofs = (lcn << CLUSTERBITS) + (di.clusterofs & (CLUSTERSIZE - 1))
            pblk = di.blkaddr
            return ofs, pblk, (t == PLAIN)
        raise ValueError(f"unknown cluster type {t} at lcn {lcn}")

    # --- literal transcription of z_erofs_map_blocks_iter (initial-call only) ---
    def map_blocks_initial(self, ofs):
        lcn = ofs // CLUSTERSIZE
        ofs_rem = ofs % CLUSTERSIZE
        di = self.read_index(self.inode, lcn)
        logical_cluster_ofs = self.decompressed_index_clusterofs(di)
        t = di.ctype
        end = (lcn + 1) * CLUSTERSIZE
        is_plain_result = False

        if t == PLAIN:
            is_plain_result = True
            # ofs_rem(0) >= logical_cluster_ofs -> toggle zipped off; harmless here
            # fallthrough to HUAWEI_COMPAT/HEAD check below
        if t in (PLAIN, HUAWEI_COMPAT):
            prev = di.huawei_prev if t == HUAWEI_COMPAT else 0
            if t == HUAWEI_COMPAT and prev:
                end = (lcn + 1) * CLUSTERSIZE
                lcn2 = lcn - 1
                ofs, pblk, is_plain_result = self.get_logical_extent_head(lcn2)
                return ofs, end - ofs, pblk, is_plain_result
            # fallthrough to HEAD
        if t in (PLAIN, HUAWEI_COMPAT, HEAD):
            if ofs_rem == logical_cluster_ofs:
                pblk = di.blkaddr
                return ofs, end - ofs, pblk, is_plain_result  # m_la unchanged (exact_hitted)
            if ofs_rem > logical_cluster_ofs:
                new_ofs = (lcn * CLUSTERSIZE) | logical_cluster_ofs
                pblk = di.blkaddr
                return new_ofs, end - new_ofs, pblk, is_plain_result
            if lcn == 0:
                raise ValueError("invalid logical cluster 0")
            end = (lcn * CLUSTERSIZE) | logical_cluster_ofs
            lcn2 = lcn - 1
            new_ofs, pblk, is_plain_result = self.get_logical_extent_head(lcn2)
            return new_ofs, end - new_ofs, pblk, is_plain_result
        if t == NONHEAD:
            lcn2 = lcn - 1
            ofs, pblk, is_plain_result = self.get_logical_extent_head(lcn2)
            return ofs, end - ofs, pblk, is_plain_result
        raise ValueError(f"unknown cluster type {t}")

    def extract_inline(self, inode):
        # Inline data sits immediately after the inode + xattr region, no
        # 8-byte rounding and no extent header (unlike COMPRESSION layout;
        # see fs/erofs/inode.c fill_inline_data).
        base = self.iloc(inode["nid"]) + inode["inode_isize"] + inode["xattr_isize"]
        return self.pread(base, inode["i_size"])

    def extract_compressed(self, inode):
        self.inode = inode
        i_size = inode["i_size"]
        out = bytearray(i_size)
        ofs = 0
        while ofs < i_size:
            la, llen, pblk, is_plain = self.map_blocks_initial(ofs)
            cur_end = la + llen

            # Mirror the kernel's "!initial" extension: keep growing this
            # same mapping (same la/pblk) while subsequent, cluster-aligned
            # logical clusters are pure continuations, instead of ever
            # re-deriving pblk for them via a fresh top-level query (which
            # -- as this format's HUAWEI_COMPAT type reuses clusterofs for
            # both heads and continuations -- can otherwise resolve
            # ambiguously for clusters that are mid-chain).
            while cur_end < i_size and cur_end % CLUSTERSIZE == 0:
                next_lcn = cur_end // CLUSTERSIZE
                di = self.read_index(inode, next_lcn)
                if self.decompressed_index_clusterofs(di) != CLUSTERSIZE:
                    break
                cur_end += CLUSTERSIZE
            llen = cur_end - la

            phys = self.pread(pblk * EROFS_BLKSIZ, EROFS_BLKSIZ)
            # The decompressed (or literal) buffer's byte 0 always
            # corresponds exactly to file offset `la` -- clusterofs only
            # ever adjusts where `la` itself lands, it is not a separate
            # read offset into this buffer.
            if is_plain:
                sliced = phys[:llen]
            else:
                sliced = lz4_decompress_safe(phys, llen)

            if len(sliced) < llen:
                raise ValueError(
                    f"short decompression at ofs={ofs} la={la} llen={llen} "
                    f"pblk={pblk}: got {len(sliced)} bytes, needed {llen}")
            end = min(len(out), la + len(sliced))
            take = end - la
            if take > 0:
                out[la:end] = sliced[:take]
            ofs = cur_end
        return bytes(out)


S_IFMT = 0xF000
S_IFLNK = 0xA000


def extract_one(image_path, nid, outpath):
    """Returns (ok: bool, message: str). Never raises."""
    try:
        img = Image(image_path)
        inode = img.read_inode(nid)
        mode = inode["data_mapping_mode"]
        if mode == 2:  # INLINE
            data = img.extract_inline(inode)
            if (inode["i_mode"] & S_IFMT) == S_IFLNK:
                target = data.decode("utf-8", "surrogateescape")
                if os.path.islink(outpath) or os.path.exists(outpath):
                    os.remove(outpath)
                os.symlink(target, outpath)
                return True, f"symlink -> {target}"
            with open(outpath, "wb") as f:
                f.write(data)
            return True, f"{len(data)} bytes (inline)"
        if mode != 1:  # not COMPRESSION either
            return False, f"unhandled layout mode={mode}"
        data = img.extract_compressed(inode)
        with open(outpath, "wb") as f:
            f.write(data)
        return True, f"{len(data)} bytes"
    except Exception as e:
        return False, f"{type(e).__name__}: {e}"


def main():
    image, nid_s, outpath = sys.argv[1], sys.argv[2], sys.argv[3]
    ok, msg = extract_one(image, int(nid_s), outpath)
    if ok:
        print(f"OK: {msg} -> {outpath}")
    else:
        print(f"FAILED: {msg}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
