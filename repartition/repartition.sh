#!/system/bin/sh
# AGS2: repartition mmcblk0 from "preas" on. Runs from the install zip (updater-script) before anything is flashed.
#
#   repartition.sh <SYSTEM_MIB> <VENDOR_MIB>
#
# Partitions 1..51 are never touched. Everything from "preas" on (preas preavs system cust version vendor product userdata) is
# deleted and replaced by
#   52 system   <SYSTEM_MIB> MiB   (filesystem used space + 300 MiB for GApps, sized by the build)
#   53 vendor   <VENDOR_MIB> MiB   (filesystem used space + 50 MiB, sized by the build)
#   54 userdata everything that is left
# preas, preavs, cust, version and product are not recreated.
#
# Decision, in this order:
#   * the last partitions already are system/vendor/userdata (52/53/54, nothing after) and system/vendor are big enough for the
#     images in this zip      -> nothing is repartitioned, exit 0
#   * the table is exactly the stock layout for "preas" and everything after it (sectors compared with the verified
#     `parted print`)       -> repartition
#   * anything else (other layout, or already repartitioned but too small) -> abort without writing
# Exit status 0 = the partition layout is OK for the images that follow, anything else aborts the install.
#
# Test hooks (never set on the device): DISK PARTED TEST=1 (no unmount/rereadpt/zip checks) DRY_RUN=1 (print, do not write)

DISK=${DISK:-/dev/block/mmcblk0}
PARTED=${PARTED:-/tmp/install/bin/parted}
BYNAME=${BYNAME:-/dev/block/bootdevice/by-name}
BACKUP_DIR=${BACKUP_DIR:-/cache}
TEST=${TEST:-0}
DRY_RUN=${DRY_RUN:-0}

SYS_MIB=$1
VEN_MIB=$2

SPM=2048                        # sectors per MiB
FIRST=2097152                   # first sector of "preas" (1 GiB)
DISK_SECTORS_REF=30777344

say() { echo "ags2-repart: $*"; echo "ui_print $*"; }
fail() { say "ABORT: $*"; exit 1; }

case "$SYS_MIB$VEN_MIB" in ''|*[!0-9]*) fail "usage: repartition.sh <system MiB> <vendor MiB>";; esac
[ "$SYS_MIB" -ge 512 ] && [ "$VEN_MIB" -ge 64 ] || fail "implausible sizes: system $SYS_MIB MiB, vendor $VEN_MIB MiB"
[ -x "$PARTED" ] || fail "$PARTED is missing"

# ---- the partition table -------------------------------------------------------------------------------------------------
table() { "$PARTED" -m -s "$DISK" unit s print 2>/dev/null | tr -d '\r'; }
# part <n> <field>   field: 2 start, 3 end, 4 size, 6 name (sectors without the trailing "s")
part() { table | awk -F: -v n="$1" -v f="$2" '$1==n { v=$f; if (f<6) sub(/s$/,"",v); print v }'; }
disk_sectors() { table | awk -F: 'NR==2 { v=$2; sub(/s$/,"",v); print v }'; }
numbers() { table | awk -F: '$1 ~ /^[0-9]+$/ { print $1 }'; }
last_number() { numbers | sort -n | tail -1; }

# Partitions that parted adds to the running kernel have no PARTNAME (parted's BLKPG call does not pass the GPT name), so ueventd cannot
# create the by-name links for them; only a full re-read of the table would, and that needs every partition of the disk unmounted. Make the
# links ourselves, but only for partitions the kernel really has at the planned place. A later boot reads the GPT and names them itself.
ensure_links() {
  [ "$TEST" = 1 ] && return 0
  dir=$(readlink -f "$BYNAME")
  [ -d "$dir" ] || fail "$BYNAME is not a directory"
  for n in 52:system 53:vendor 54:userdata; do
    num=${n%%:*}; name=${n##*:}
    want="${DISK}p$num"
    [ -b "$want" ] || fail "$want does not exist (the kernel does not know the new table). Reboot recovery and install again."
    if [ "$(readlink -f "$dir/$name" 2>/dev/null)" != "$want" ]; then
      rm -f "$dir/$name"
      ln -s "$want" "$dir/$name" || fail "cannot create $dir/$name"
      say "linked $dir/$name -> $want"
    fi
  done
  KS=$(cat "/sys/block/${DISK##*/}/${DISK##*/}p52/start" 2>/dev/null)
  [ "$KS" = "$(part 52 2)" ] || fail "the kernel sees system at ${KS:-?}, the table says $(part 52 2). Reboot recovery and install again."
}

# userdata: f2fs, android feature set, WITHOUT extra_attr/project_quota (this 4.4 kernel panics on those)
format_userdata() {
  MKF=$(command -v make_f2fs || ls /system/bin/make_f2fs /sbin/make_f2fs 2>/dev/null | head -1)
  if [ -n "$MKF" ]; then
    "$MKF" -g android "$BYNAME/userdata" >/dev/null 2>&1 && say "userdata formatted (f2fs)" || say "WARNING: formatting userdata failed; format Data in TWRP"
  else
    say "WARNING: make_f2fs not found; format Data in TWRP (Wipe -> Format Data)"
  fi
}
# a freshly (re)partitioned userdata has no filesystem yet; one that has an f2fs superblock (magic F2F52010 at 0x400) is left alone
ensure_userdata_fs() {
  [ "$TEST" = 1 ] && return 0
  m=$(dd if="$BYNAME/userdata" bs=1 skip=1024 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')
  [ "$m" = "1020f5f2" ] && { say "userdata already has an f2fs filesystem, left alone"; return 0; }
  format_userdata
}

TABLE_BEFORE=$(table)
[ -n "$TABLE_BEFORE" ] || fail "cannot read the partition table of $DISK"
DISK_SECTORS=$(disk_sectors)
[ "$DISK_SECTORS" = "$DISK_SECTORS_REF" ] || fail "disk has $DISK_SECTORS sectors, expected $DISK_SECTORS_REF"

# ---- the plan --------------------------------------------------------------------------------------------------------------
SYS_S=$FIRST
SYS_E=$((SYS_S + SYS_MIB * SPM - 1))
VEN_S=$((SYS_E + 1))
VEN_E=$((VEN_S + VEN_MIB * SPM - 1))
USR_S=$((VEN_E + 1))
LAST_USABLE=$((DISK_SECTORS - 34))                 # room for the backup GPT
USR_E=$(( (LAST_USABLE + 1) / SPM * SPM - 1 ))     # MiB aligned
[ $((USR_E - USR_S)) -gt $((1024 * SPM)) ] || fail "system+vendor leave no room for userdata"

# ---- 1) already repartitioned? ----------------------------------------------------------------------------------------------
if [ "$(last_number)" = "54" ] && [ "$(part 52 6)" = "system" ] && [ "$(part 53 6)" = "vendor" ] && [ "$(part 54 6)" = "userdata" ] \
   && [ "$(part 52 2)" = "$FIRST" ] && [ "$(part 53 2)" = "$(( $(part 52 3) + 1 ))" ] && [ "$(part 54 2)" = "$(( $(part 53 3) + 1 ))" ]; then
  HAVE_SYS=$(part 52 4); HAVE_VEN=$(part 53 4)
  if [ "$HAVE_SYS" = "$((SYS_MIB * SPM))" ] && [ "$HAVE_VEN" = "$((VEN_MIB * SPM))" ] && [ "$(part 54 3)" = "$USR_E" ]; then
    say "the partition table already matches the target (system $SYS_MIB MiB, vendor $VEN_MIB MiB, userdata the rest): not repartitioning"
    ensure_links
    ensure_userdata_fs
    exit 0
  fi
  if [ "$HAVE_SYS" -ge $((SYS_MIB * SPM)) ] && [ "$HAVE_VEN" -ge $((VEN_MIB * SPM)) ]; then
    say "already repartitioned (system $((HAVE_SYS / SPM)) MiB, vendor $((HAVE_VEN / SPM)) MiB); both are large enough for this zip: not repartitioning"
    ensure_links
    ensure_userdata_fs
    exit 0
  fi
  fail "already repartitioned, but system/vendor ($((HAVE_SYS / SPM))/$((HAVE_VEN / SPM)) MiB) are smaller than this zip needs ($SYS_MIB/$VEN_MIB MiB). Nothing was changed."
fi

# ---- 2) rule 7: the stock layout of "preas" and everything after it must match exactly -------------------------------------
check() { # n name start end
  [ "$(part "$1" 6)" = "$2" ] && [ "$(part "$1" 2)" = "$3" ] && [ "$(part "$1" 3)" = "$4" ]
}
REF_OK=1
for ref in "52 preas 2097152 4063231" "53 preavs 4063232 4128767" "54 system 4128768 9338879" "55 cust 9338880 9732095" \
           "56 version 9732096 9797631" "57 vendor 9797632 11403263" "58 product 11403264 11796479" "59 userdata 11796480 30777343"; do
  # shellcheck disable=SC2086
  check $ref || { say "partition mismatch: expected $ref, found $(part "${ref%% *}" 6) $(part "${ref%% *}" 2)-$(part "${ref%% *}" 3)"; REF_OK=0; }
done
[ "$(last_number)" = "59" ] || { say "the table has partitions after 59 (last is $(last_number))"; REF_OK=0; }
[ "$REF_OK" = 1 ] || fail "the partition table is neither the stock layout nor an already repartitioned one. Nothing was changed."
say "verified: preas and all later partitions match the stock layout exactly"

say "plan: 52 system ${SYS_S}s-${SYS_E}s ($SYS_MIB MiB), 53 vendor ${VEN_S}s-${VEN_E}s ($VEN_MIB MiB), 54 userdata ${USR_S}s-${USR_E}s ($(( (USR_E - USR_S + 1) / SPM )) MiB)"
say "DELETING preas, preavs, system, cust, version, vendor, product and userdata (all user data and internal storage)"

# ---- 3) the install zip must not live on a partition that is about to disappear -------------------------------------------
if [ "$TEST" != 1 ]; then
  ZIP=$(tr '\0' '\n' < /proc/$PPID/cmdline 2>/dev/null | grep -i '\.zip$' | tail -1)
  if [ -z "$ZIP" ] || [ ! -e "$ZIP" ]; then
    fail "cannot tell where the install zip is. Install it from the SD card (/external_sd): internal storage is deleted by this step."
  fi
  ZDEV=$(df "$ZIP" 2>/dev/null | tail -1 | awk '{print $1}')
  ZREAL=$(readlink -f "$ZDEV" 2>/dev/null)
  case "$ZREAL$ZDEV" in
    *mmcblk0p5[2-9]*|*/by-name/userdata*|*/by-name/system*|*/by-name/vendor*|*/by-name/cust*|*/by-name/product*|*/by-name/preas*)
      fail "the install zip ($ZIP) is on $ZDEV, which this step deletes. Copy it to the SD card (/external_sd) and install it from there. Nothing was changed.";;
  esac
  case "$ZIP" in /data/*|/sdcard/*|/system/*|/vendor/*) fail "the install zip ($ZIP) is on a partition this step deletes. Install it from the SD card. Nothing was changed.";; esac
  say "install zip: $ZIP (on $ZDEV), safe"

  # ---- 4) nothing from the deleted partitions may stay mounted --------------------------------------------------------------
  for i in 1 2 3; do
    awk '{print $1" "$2}' /proc/mounts | while read -r dev mp; do
      r=$(readlink -f "$dev" 2>/dev/null)
      case "$r" in /dev/block/mmcblk0p5[2-9]) umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null;; esac
    done
  done
  BUSY=$(awk '{print $1" "$2}' /proc/mounts | while read -r dev mp; do r=$(readlink -f "$dev" 2>/dev/null); case "$r" in /dev/block/mmcblk0p5[2-9]) echo "$mp";; esac; done)
  [ -z "$BUSY" ] || fail "still mounted: $BUSY. Unmount Data/System/Vendor in TWRP (Mount) and install again. Nothing was changed."
fi

# ---- 5) keep the old GPT (rollback) ------------------------------------------------------------------------------------------
if [ "$DRY_RUN" != 1 ]; then
  mkdir -p "$BACKUP_DIR" 2>/dev/null
  dd if="$DISK" of="$BACKUP_DIR/ags2_gpt_primary_before_repartition.bin" bs=512 count=34 2>/dev/null || fail "cannot back up the GPT to $BACKUP_DIR"
  echo "$TABLE_BEFORE" > "$BACKUP_DIR/ags2_parted_before_repartition.txt"
  [ "$(dd if="$BACKUP_DIR/ags2_gpt_primary_before_repartition.bin" bs=512 skip=1 count=1 2>/dev/null | head -c 8)" = "EFI PART" ] || fail "the GPT backup is not a GPT"
  say "old partition table saved in $BACKUP_DIR (ags2_gpt_primary_before_repartition.bin)"
fi

# ---- 6) repartition ------------------------------------------------------------------------------------------------------------
CMD="rm 59 rm 58 rm 57 rm 56 rm 55 rm 54 rm 53 rm 52 mkpart system ext4 ${SYS_S}s ${SYS_E}s mkpart vendor ext4 ${VEN_S}s ${VEN_E}s mkpart userdata ${USR_S}s ${USR_E}s set 52 msftdata on set 53 msftdata on set 54 msftdata on"
if [ "$DRY_RUN" = 1 ]; then
  say "DRY RUN: $PARTED -s -a none $DISK unit s $CMD"
  exit 0
fi
# shellcheck disable=SC2086
"$PARTED" -s -a none "$DISK" unit s $CMD || fail "parted failed. Check the partition table before doing anything else (old GPT: $BACKUP_DIR/ags2_gpt_primary_before_repartition.bin)"
sync

# ---- 7) verify the result ------------------------------------------------------------------------------------------------------
HEAD_BEFORE=$(echo "$TABLE_BEFORE" | awk -F: '$1 ~ /^[0-9]+$/ && $1 < 52')
HEAD_AFTER=$(table | awk -F: '$1 ~ /^[0-9]+$/ && $1 < 52')
[ "$HEAD_BEFORE" = "$HEAD_AFTER" ] || fail "PARTITIONS BEFORE preas CHANGED. Restore the old GPT from $BACKUP_DIR (dd if=ags2_gpt_primary_before_repartition.bin of=$DISK bs=512 count=34) and do not flash."
check 52 system "$SYS_S" "$SYS_E" && check 53 vendor "$VEN_S" "$VEN_E" && check 54 userdata "$USR_S" "$USR_E" && [ "$(last_number)" = "54" ] \
  || fail "the new table differs from the plan: $(table | tail -4)"
say "new table verified; partitions 1..51 are unchanged"

if [ "$TEST" != 1 ]; then
  ensure_links

  format_userdata
fi
say "repartition done"
exit 0
