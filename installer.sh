#!/bin/sh
set -e
### Config #########################
DISK="$1"
POOLNAME=${POOLNAME:-"sys"}
BENAME=${BENAME:-"stable9"}
SWAPSIZE=${SWAPSIZE:-"4G"}
BOOTSIZE=${$BOOTSIZE:-"1G"}
TMP=${TMP:-"/tmp"}
TMP_ROOT=${TMP_ROOT:-"/tmp/$POOLNAME"}

R="$POOLNAME/ROOT/$BENAME"  # boot enviroment
L="$POOLNAME/LOCAL"         # local/shared datasets

### Check params ###################
[ -c "$DISK" ] || {
	echo "usage: $0 /dev/(clean_bsdslice)";
	echo "	$0 /dev/ada0s4";
	exit 1;
}

tmpfree="`df -m /tmp | tail -1 | awk '{ print $3; }'`";
neededspace="150"; # about~ , both in MB
[ $tmpfree -ge $neededspace ] || {
	echo "Your /tmp has only ${tmpfree}MB of free space avaliable,";
	echo "at least ${neededspace}MB is needed for install files.";
	echo "try:";
	[ `mount | grep '/tmp ' | wc -l | awk '{ print $1; }'` -eq 1 ] || \
		echo "	umount -f /tmp";
	echo "	mount -o size=${neededspace}M -t tmpfs /tmp";
	exit 1;
} >&2;


##### Filesystems ####################
[ -c ${DISK}a ] || {
	### Avaliable options ##############
	RO="-o readonly=on";
	ATIME="-o atime=on";
	COMPR="-o compression=on";
	NOCOMPR="-o compression=off";
	NOMNT="-o mountpoint=none";
	LEGACYMNT="-o mountpoint=legacy";
	NOSUID="-o setuid=off";
	DEV="-o devices=on";
	EXEC="-o exec=on";
	NOEXEC="-o exec=off";

	echo "Creating BOOT on ${DISK}a";
	gpart add -t freebsd-ufs -i 1 -s $BOOTSIZE $DISK;
	newfs -L BOOT ${DISK}a;
}
[ -c ${DISK}b ] || gpart add -t freebsd-swap -i 2 -s $SWAPSIZE $DISK;
[ -c ${DISK}d ] || {
	echo "Creating zpool $POOLNAME on ${DISK}d"
	gpart add -t freebsd-zfs $DISK
	gpart bootcode -b /boot/boot $DISK
	zpool create -f \
	             -O utf8only=on \
	             -O devices=off \
	             -O mountpoint=none \
	             -O checksum=fletcher4 \
	             -O atime=off \
	             -m none $POOLNAME ${DISK}d
	
	### Datasets #######################
	echo -n "Creating datasets "
	zfs_create() {
		zfs create $*;
		echo -n .
	}
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
	echo " done"
	
	### Result #########################
	echo; echo "Finished creating datasets, results:"
	zfs list -t all -o \
		name,compression,exec,setuid,readonly,atime,devices,mountpoint
}

### Download #######################
FTP_PREFIX=${FTP_PREFIX:-"ftp://ftp.freebsd.org/pub/FreeBSD/snapshots/amd64/amd64/9.1-STABLE/"}
FILES=${FILES:-"base.txz kernel.txz lib32.txz doc.txz"}
{
	cd /tmp;
	[ -f ${FTP_PREFIX}MANIFEST ] || ftp ${FTP_PREFIX}MANIFEST;
	for file in $FILES
	do
		[ -f $file ] || ftp ${FTP_PREFIX}${file};
	done
	cd -;
} || { echo "Failed to fetch install files." >&2; exit 1; };

### Installation ###################
verify_checksum() {
	local file=$1;
	local sum=$2;
	local filesum=`sha256 /tmp/${file} | cut -d'=' -f 2 | tr -d ' 	'`;
	echo "sha256 $file -> expected: ${filesum}	=	downloaded: ${sum}";
	[ ${sum} = ${filesum} ] || {
		echo "Checksum mismatch for /tmp/${file}, exiting. Please delete the file and try again." >&2;
		exit 1;
	}
}
verify_file_checksum() {
	local line=`cat /tmp/MANIFEST | cut -f 1-2 | grep "$1"`;
	verify_checksum $line;
}

for tarball in $FILES
do
	install_log="/tmp/${tarball}-install.log";
	[ -f $install_log ] || {
		verify_file_checksum $tarball;
		echo "tar --unlink -xvpJf /tmp/${tarball} -C $TMP_ROOT > $install_log";
		tar --unlink -xvpJf /tmp/${tarball} -C $TMP_ROOT > $install_log;
	}
done

