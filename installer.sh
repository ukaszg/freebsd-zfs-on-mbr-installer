#!/bin/sh
set -e
### Settings (overridable) ######### # {{{
DISK="$1"
POOLNAME=${POOLNAME:-"sys"}
BENAME=${BENAME:-"stable9"}
SWAPSIZE=${SWAPSIZE:-"4G"}
BOOTSIZE=${BOOTSIZE:-"1G"}
TMP=${TMP:-"/tmp"}
TMP_ROOT=${TMP_ROOT:-"/tmp/$POOLNAME"}

R="$POOLNAME/ROOT/$BENAME"  # boot enviroment
L="$POOLNAME/LOCAL"         # local/shared datasets
# }}}
### Checking params ################ # {{{
[ -c "$DISK" ] || { # {{{
	echo "usage: $0 /dev/(clean_bsdslice)";
	echo "	$0 /dev/ada0s4";
	exit 1;
} # }}}
tmpfree="`df -m /tmp | tail -1 | awk '{ print $3; }'`";
neededspace="150"; # about~ , both in MB
[ $tmpfree -ge $neededspace ] || { # {{{
	echo "Your /tmp has only ${tmpfree}MB of free space avaliable,";
	echo "at least ${neededspace}MB is needed for install files.";
	echo "try:";
	[ `mount | grep '/tmp ' | wc -l | awk '{ print $1; }'` -eq 1 ] || \
		echo "	umount -f /tmp";
	echo "	mount -o size=${neededspace}M -t tmpfs /tmp";
	exit 1;
} >&2; # }}}
# }}}
### Filesystems #################### # {{{
[ -c ${DISK}a ] || { # {{{
	echo "Creating BOOT on ${DISK}a";
	gpart add -t freebsd-ufs -i 1 -s $BOOTSIZE $DISK || {
		echo "You might not have created a scheme on $DISK";
		exit 1;
	} >&2;
	newfs -L BOOT ${DISK}a;
} # }}}
[ -c ${DISK}b ] || gpart add -t freebsd-swap -i 2 -s $SWAPSIZE $DISK;
[ -c ${DISK}d ] || { # {{{
	### Avaliable options ##############
	ATIME="-o atime=on";
	COMPR="-o compression=on";
	NOCOMPR="-o compression=off";
	NOMNT="-o mountpoint=none";
	LEGACYMNT="-o mountpoint=legacy";
	NOSUID="-o setuid=off";
	DEV="-o devices=on";
	EXEC="-o exec=on";
	NOEXEC="-o exec=off";

	echo "Creating zpool $POOLNAME on ${DISK}d"
	gpart add -t freebsd-zfs -i 4 $DISK;
	gpart bootcode -b /boot/boot $DISK;
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
	zfs_create $COMPR   $EXEC   $NOSUID  $R/tmp
	zfs_create          $EXEC   $NOSUID  $R/compat
	
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
	zfs_create          $NOEXEC $NOSUID  $R/var/empty
	zfs_create $COMPR   $NOEXEC          $R/var/log
	zfs_create $COMPR   $NOEXEC $ATIME   $R/var/mail
	zfs_create          $NOEXEC          $R/var/run
	zfs_create $COMPR   $EXEC            $R/var/tmp
	
	zfs_create $NOMNT           $NOSUID  $L
	zfs_create                           $L/home
	zfs_create $COMPR   $NOEXEC          $L/home/pub
	zpool set bootfs=$R $POOLNAME
	zfs set mountpoint=legacy $R;
	echo " done"
} # }}}
# }}}
### Download ####################### # {{{
FTP_PREFIX=${FTP_PREFIX:-"ftp://ftp.freebsd.org/pub/FreeBSD/snapshots/amd64/amd64/9.1-STABLE/"}
FILES=${FILES:-"base.txz kernel.txz lib32.txz doc.txz"}
{
	cd /tmp;
	[ -f /tmp/MANIFEST ] || ftp ${FTP_PREFIX}MANIFEST;
	for file in $FILES
	do
		[ -f $file ] || ftp ${FTP_PREFIX}${file};
	done
	cd -;
} || { echo "Failed to fetch install files." >&2; exit 1; }; # }}}
### Installation ################### #{{{
verify_checksum() { # {{{
	_file="$1";
	_sum="$2";
	_filesum=`sha256 /tmp/$_file | cut -d'=' -f 2 | tr -d ' 	'`;
	[ ${_sum} = ${_filesum} ] || {
		echo "sha256 $_file -> ";
		echo " expected:   $_sum";
		echo " downloaded: $_filesum";
		echo "Checksum mismatch for /tmp/$_file, exiting.";
		echo " Please delete the file and try again.";
		exit 1;
	} >&2;
} # }}}
verify_file_checksum() { #{{{
	_line=`cat /tmp/MANIFEST | grep "$1" | cut -f 1-2`;
	verify_checksum $_line;
} # }}}
gen_mountpoint() { # {{{
	_prefix=$1;
	_zfs_datasets=`zfs list -H -d 1 -o name $R $L | egrep "($R|$L)/"`;
	_zfs=/rescue/zfs;
	echo '#!/bin/sh';
	echo 'set -e';
	echo;
	echo "mkdir -p $_prefix/dev";
	echo "mount -t devfs none $_prefix/dev || true";
	for dataset in $_zfs_datasets
	do
		_m=${dataset##*/};
		echo "$_zfs set mountpoint=$_prefix/$_m $dataset;";
	done
	echo "echo \"Dataset mounts prefix set to '$_prefix'\"";
	echo 'exit 0;'; 
} # }}}
umount_zfs(){ # {{{
	zfs umount -a;
	umount $TMP_ROOT/dev || true;
	umount $TMP_ROOT;
} # }}}
mount_zfs() { # {{{
	echo "Mounting $R -> $TMP_ROOT";
	mkdir -p $TMP_ROOT;
	mount -t zfs $R $TMP_ROOT;
	gen_mountpoint $TMP_ROOT | sh;
} # }}}

mount_zfs;
mkdir -p ${TMP_ROOT}/var/log;
for tarball in $FILES # do install{{{
do
	install_log="${TMP_ROOT}/var/log/install-${tarball}.log";
	[ -f $install_log ] || {
		verify_file_checksum $tarball && \
			echo "Installing $tarball, log at [$TMP_ROOT]/var/log/install-${tarball}.log";
		tar --unlink -v -xpJf /tmp/${tarball} -C $TMP_ROOT;
	} 2> $install_log || {
		echo "error during installation of: ${tarball}";
		cat $install_log;
		exit 1;
	} >&2;
done # }}}
# }}}
### Config generation ############## # {{{
[ -d ${TMP_ROOT}/broot ] || { # config already exists if we made broot
# etcfiles {{{
file_is(){
	F=$1;
	echo "Creating $F" | sed -e "s,${TMP_ROOT},[${TMP_ROOT}],";
}
file_is ${TMP_ROOT}/etc/rc.conf.local;
[ -f $F ] || cat > $F <<EOF
hostname="${BENAME}"
keymap="pl_PL.UTF-8.kbd"
wlans_iwn0="wlan0"
ifconfig_wlan0="WPA DHCP"
ifconfig_wlan0_ipv6="inet6 accept_rtadv"
moused_enable="YES"
powerd_enable="YES"
zfs_enable="YES"

# disable Sendmail
sendmail_enable="NO"
sendmail_submit_enable="NO"
sendmail_outbound_enable="NO"
sendmail_msp_queue_enable="NO"

# Set dumpdev to "AUTO" to enable crash dumps, "NO" to disable
dumpdev="NO"
EOF

file_is ${TMP_ROOT}/boot/loader.conf;
[ -f $F ] || cat > $F <<EOF
loader_color="YES"
coretemp_load="YES"
ahci_load="YES"
aio_load="YES"
zfs_load="YES"
vfs.root.mountfrom="zfs:$R"
EOF

file_is ${TMP_ROOT}/etc/malloc.conf;
[ -f $F ] || echo dM > $F;

file_is ${TMP_ROOT}/etc/make.conf;
[ -f $F ] || cat > $F <<EOF
WITH_NEW_XORG="YES"
WITH_KMS="YES"
WITH_LCD_FILTERING="YES"
WITH_CLANG="YES"
WITH_BSD_GREP="YES"
WITH_PKGNG="YES"
WITH_NCURSES_BASE="YES"
#WITH_CLANG_EXTRAS="YES"

## uncomment for less GNU
#WITH_CLANG_IS_CC="YES"
#WITHOUT_GCC="YES"
#CC=clang
#CXX=clang++
#CPP=clang-cpp
#NO_WERROR=
#WERROR=

WITHOUT_ASSERT_DEBUG="YES"
WITHOUT_BIND="YES"
WITHOUT_CVS="YES"
WITHOUT_DICT="YES"
WITHOUT_DYNAMIC_ROOT="YES"
WITHOUT_FLOPPY="YES"
WITHOUT_GAMES="YES"
WITHOUT_KERBEROS="YES"
WITHOUT_LOCATE="YES"
WITHOUT_MAIL="YES"
WITHOUT_NLS="YES"
WITHOUT_NLS_CATALOGS="YES"
WITHOUT_NOUVEAU="YES"
WITHOUT_PAM="YES"
WITHOUT_QUOTAS="YES"
WITHOUT_RCMDS="YES"
WITHOUT_RCS="YES"
WITHOUT_TCSH="YES"
EOF

file_is ${TMP_ROOT}/etc/src.conf;
[ -f $F ] || cat > $F <<EOF
MALLOC_PRODUCTION=1
CC=clang
CXX=clang++
CPP=clang-cpp
#NO_WERROR=
#WERROR=
EOF
# }}}

zfs set readonly=on $R/var/empty;

{ cd $TMP_ROOT; # broot/boot -> boot {{{
	mkdir broot;
	mount ${DISK}a broot;
	mv boot broot/;
	ln -s broot/boot boot;
	chflags sunlink boot;
	umount broot;
	cd -; }
# }}}
file_is $TMP_ROOT/etc/fstab; # {{{
echo "${DISK}a /broot ufs rw 1 1" > $F;
echo "${DISK}b none swap sw 0 0" >> $F; # }}}
} ## config END }}}
### ZFS before-boot fixes ########## # {{{
gen_mountpoint > $TMP_ROOT/fixmounts.sh;
chmod +x $TMP_ROOT/fixmounts.sh;
[ -f $TMP_ROOT/boot/zfs/zpool.cache ] || { # {{{
	cd /;
	umount_zfs;
	zpool export sys && zpool import sys;
	mount_zfs; # leave it as you found it
	umount $TMP_ROOT/dev;
	mount ${DISK}a $TMP_ROOT/broot;
	mkdir -p $TMP_ROOT/boot/zfs;
	cp -f /boot/zfs/zpool.cache $TMP_ROOT/boot/zfs/zpool.cache;
	umount $TMP_ROOT/broot;
	echo "Created [${TMP_ROOT}]/boot/zfs/zpool.cache";
} # }}}
umount $TMP_ROOT/dev 2>/dev/null || true;
chroot $TMP_ROOT /fixmounts.sh;
umount_zfs;
# }}}
echo All done.
