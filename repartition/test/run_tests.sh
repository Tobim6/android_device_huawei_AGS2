#!/bin/bash
# Exercises repartition.sh against disk images built from the tablet's real primary GPT, with the shipped aarch64 parted run through
# qemu-aarch64-static (binfmt). Nothing here touches a real device.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); S=$HERE/../repartition.sh; W=$(mktemp -d)
cp "$HERE/../parted" "$W/parted_arm64"; chmod +x "$W/parted_arm64"
printf '#!/bin/sh\nexec qemu-aarch64-static %s/parted_arm64 "$@"\n' "$W" > "$W/parted_q"; chmod +x "$W/parted_q"
export TEST=1 PARTED=$W/parted_q BACKUP_DIR=$W/bk
mkimg() { rm -f "$1"; truncate -s $((30777344*512)) "$1"; dd if="$HERE/primary_gpt_real.bin" of="$1" bs=512 conv=notrunc 2>/dev/null; }
tbl() { "$PARTED" -m -s "$1" unit s print 2>/dev/null | sed 1,2d | cut -d: -f1-4,6; }
pass=0; fail=0
t() { if [ "$1" = "$2" ]; then echo "ok   $3"; pass=$((pass+1)); else echo "FAIL $3 (got $1, want $2)"; fail=$((fail+1)); fi; }
run() { DISK=$1 sh "$S" "$2" "$3" >/dev/null 2>&1; echo $?; }
mkimg "$W/stock.img"
cp "$W/stock.img" "$W/a.img"; t "$(run $W/a.img 2095 473)" 0 "stock table is repartitioned"
t "$(tbl $W/a.img | sed -n '52,54p' | tr '\n' ' ')" "52:2097152s:6387711s:4290560s:system 53:6387712s:7356415s:968704s:vendor 54:7356416s:30775295s:23418880s:userdata " "new layout 52/53/54"
t "$(tbl $W/a.img | sed -n 1,51p | md5sum)" "$(tbl $W/stock.img | sed -n 1,51p | md5sum)" "partitions 1..51 unchanged"
h=$(md5sum < $W/a.img)
t "$(run $W/a.img 2095 473)" 0 "same sizes again: skipped"; t "$(md5sum < $W/a.img)" "$h" "  disk untouched"
t "$(run $W/a.img 2000 400)" 0 "smaller images: skipped"; t "$(md5sum < $W/a.img)" "$h" "  disk untouched"
t "$(run $W/a.img 2300 473)" 1 "images too big for the existing partitions: abort"; t "$(md5sum < $W/a.img)" "$h" "  disk untouched"
for n in 52 53 56 57 59; do cp "$W/stock.img" "$W/m.img"; "$PARTED" -s "$W/m.img" rm $n 2>/dev/null; hm=$(md5sum < $W/m.img)
  t "$(run $W/m.img 2095 473)" 1 "stock table with partition $n missing: abort"; t "$(md5sum < $W/m.img)" "$hm" "  disk untouched"; done
cp "$W/stock.img" "$W/m.img"; "$PARTED" -s "$W/m.img" unit s rm 59 mkpart userdata 11796480s 30775295s 2>/dev/null; hm=$(md5sum < $W/m.img)
t "$(run $W/m.img 2095 473)" 1 "userdata one MiB short: abort"; t "$(md5sum < $W/m.img)" "$hm" "  disk untouched"
t "$(run $W/stock.img abc 473)" 1 "bad argument: abort"; t "$(run $W/stock.img 100 473)" 1 "implausible size: abort"
truncate -s $((30000000*512)) "$W/stock2.img"; dd if="$HERE/primary_gpt_real.bin" of="$W/stock2.img" bs=512 conv=notrunc 2>/dev/null
t "$(run $W/stock2.img 2095 473)" 1 "different disk size: abort"
cp "$W/stock.img" "$W/r.img"; run $W/r.img 2095 473 >/dev/null; dd if="$W/bk/ags2_gpt_primary_before_repartition.bin" of="$W/r.img" bs=512 count=34 conv=notrunc 2>/dev/null
t "$(tbl $W/r.img | md5sum)" "$(tbl $W/stock.img | md5sum)" "saved GPT restores the stock table"
rm -rf "$W"; echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
