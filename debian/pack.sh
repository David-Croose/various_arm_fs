#!/bin/bash

set -e

TMPMNT=mnt
APTSRC=http://ftp2.cn.debian.org/debian

if [ $(whoami) != root ]; then
	echo 'error, you must be root'
	exit 1
fi

echo '================================================================================'
echo "please enter the block device name or inputing 'Enter' directly if you don't"
echo "need to burn the block device:"
echo '    e.g. /dev/sdb2'
read BLKDEV

echo '================================================================================'
echo 'please enter the filesystem type:'
echo '    1: official debian 10 buster'
echo '    2: official debian 9 stretch'
echo '    3: official debian 8 jessie'
echo '    4: linaro debian 8 jessie'
read DEBVER

case $DEBVER in
	1)	DEBALIAS=buster
		FSNAME=debian_10_"$DEBALIAS"_source
		HTTPSRC=http://mirrors.ustc.edu.cn/debian/
		;;
	2)	DEBALIAS=stretch
		FSNAME=debian_9_"$DEBALIAS"_source
		HTTPSRC=http://mirrors.ustc.edu.cn/debian/
		;;
	3)	DEBALIAS=jessie
		FSNAME=debian_8_"$DEBALIAS"_source
		HTTPSRC=http://mirrors.ustc.edu.cn/debian/
		;;
	4)	DEBALIAS=jessie
		FSNAME=debian_8_"$DEBALIAS"_linaro_source
		HTTPSRC=https://releases.linaro.org/debian/images/alip-armhf/17.02/linaro-jessie-alip-20161117-32.tar.gz
		;;
	*)	echo 'error, you typed a wrong number'
		exit 1
esac

echo '================================================================================'
echo 'please enter the path to hold the filesystem:'
read FSPATH

echo '================================================================================'
echo 'clearing items...'
set +e
rm -rf $FSPATH
mkdir -p $FSPATH 
FSPATH=$FSPATH/$FSNAME

if [ -n "$BLKDEV" ]; then
	rm -rf $TMPMNT
	mkdir -p $TMPMNT
	umount $BLKDEV
	mount $BLKDEV $TMPMNT
fi
set -e

if [ $DEBVER -eq 4 ]; then
	echo '================================================================================'
	echo "sorry, this function is still being developing"
	#echo 'processing the linaro debian...'
	#wget $HTTPSRC $FSPATH/
	exit 0
fi

echo '================================================================================'
echo 'installing essential packages...'
apt-get install binfmt-support qemu qemu-user-static debootstrap multistrap

echo '================================================================================'
echo 'retrieving the official debian...'
# ignore this log:
# W: Cannot check Release signature; keyring file not available /usr/share/keyrings/debian-archive-keyring.gpg
debootstrap --arch=armel --foreign $DEBALIAS $FSPATH $HTTPSRC

echo '================================================================================'
echo 'debootstrap the official debian, this could take a big while...'
cp /usr/bin/qemu-arm-static $FSPATH/usr/bin
DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANGUAGE=C LANG=C chroot $FSPATH debootstrap/debootstrap --second-stage --verbose

echo '================================================================================'
echo 'creating essential files for official debian...'
echo "proc /proc proc defaults 0 0" >> $FSPATH/etc/fstab
mkdir -p $FSPATH/usr/share/man/man1/
mknod $FSPATH/dev/console c 5 1
cat > $FSPATH/init_fs.sh << EOF
#!bin/sh
echo 'enter new root password:'
passwd root

cp /etc/apt/sources.list /etc/apt/sources.list.bak
echo "deb $APTSRC buster main" > /etc/apt/sources.list
apt-get update
apt-get install wpasupplicant udhcpc net-tools openssh-server

echo 'now you should install softwares you need by apt-get then exit'
echo 'these packages is recommended:'
echo '    git build-essential samba samba-common-bin nfs-kernel-server'
echo '    xinetd tftp tftpd xfce4 dos2unix vim ctags unzip p7zip unrar e2fsprogs dosfstools'
EOF
chmod +x $FSPATH/init_fs.sh

echo '================================================================================'
echo 'now typing ./init_fs.sh'
chroot $FSPATH

rm -f $FSPATH/init_fs.sh

if [ -n "$BLKDEV" ]; then
	umount $BLKDEV
	rm -rf $TMPMNT
	sync
fi

echo 'done'
