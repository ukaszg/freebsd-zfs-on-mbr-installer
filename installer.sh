#!/bin/sh
set -e
### Config #########################
POOLNAME="sys"
BENAME="stable9"
BRANCH="stable/9"
SWAPSIZE="4G"
DISK="$1"

### Check params ###################
[ -c "$DISK" ] || {
	echo "usage: $0 /dev/(disk|slice)";
	echo "	$0 /dev/ada0s4a";
	exit 1;
}

### Avaliable options ##############
RO="-o readonly=on"
ATIME="-o atime=on"
COMPR="-o compression=on"
NOCOMPR="-o compression=off"
NOMNT="-o mountpoint=none"
LEGACYMNT="-o mountpoint=legacy"
NOSUID="-o setuid=off"
DEV="-o devices=on"
EXEC="-o exec=on"
NOEXEC="-o exec=off"

### Pool ###########################
echo "Creating zpool $POOLNAME on $DISK"
zpool create -O utf8only=on \
             -O devices=off \
             -O mountpoint=none \
             -O checksum=fletcher4 \
             -O atime=off \
             -m none $POOLNAME $DISK

### Datasets #######################
echo -n "Creating datasets "
zfs_create() {
	zfs create $*;
	echo -n .
}
R="$POOLNAME/ROOT/$BENAME"  # boot enviroment
L="$POOLNAME/LOCAL"         # local/shared datasets
#          _OPTIONS_________________ _PATH_________________
zfs_create $NOMNT                    $POOLNAME/ROOT
zfs_create                           $R
zfs_create $DEV                      $R/dev
zfs_create $COMPR   $EXEC   $NOSUID  $R/tmp
zfs_create          $EXEC   $NOSUID  $R/compat
zfs_create $COMPR   $EXEC   $NOSUID  $R/etc

zfs_create                           $R/usr
zfs_create $COMPR   $NOEXEC $NOSUID  $R/usr/src
zfs_create                  $NOSUID  $R/usr/obj
zfs_create $COMPR           $NOSUID  $R/usr/ports
zfs_create $NOCOMPR $NOEXEC          $R/usr/ports/distfiles
zfs_create $NOCOMPR $NOEXEC          $R/usr/ports/packages
zfs_create                           $R/usr/local
zfs_create $COMPR           $NOSUID  $R/usr/local/etc

zfs_create                  $NOSUID  $R/var
zfs_create          $NOEXEC          $R/var/db
zfs_create $COMPR                    $R/var/db/ports
zfs_create                           $R/var/db/portsnap
zfs_create $COMPR   $EXEC            $R/var/db/pkg
zfs_create $COMPR   $NOEXEC          $R/var/crash
zfs_create          $NOEXEC $RO      $R/var/empty
zfs_create $COMPR   $NOEXEC          $R/var/log
zfs_create $COMPR   $NOEXEC $ATIME   $R/var/mail
zfs_create          $NOEXEC          $R/var/run
zfs_create $COMPR   $EXEC            $R/var/tmp

zfs_create $NOMNT           $NOSUID  $L
zfs_create                           $L/home
zfs_create $COMPR   $NOEXEC          $L/home/pub
#zfs_create -V $SWAPSIZE \
#           -o org.freebsd:swap=on \
#           -o checksum=off \
#           -o sync=disabled \
#           -o primarycache=none \
#           -o secondarycache=none    $L/swap

zpool set bootfs=$R $POOLNAME
echo " done"

### Mounting #######################
echo -n "Setting mount properties ";
zfs set mountpoint=legacy $R;
zfs list -o name -H | grep "$R/" | while read dataset
do
	zfs set mountpoint=none $dataset;
	echo -n .;
done

### Result #########################
echo; echo "$0 finished, results:"
zfs list -t all -o \
	name,compression,exec,setuid,readonly,checksum,utf8only,atime,devices,sync
