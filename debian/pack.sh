#!/bin/bash

set -e

TMPMNT=mnt
APTSRC=https://mirrors.tuna.tsinghua.edu.cn/debian/

if [ $(whoami) != root ]; then
	echo 'error, you must be root'
	exit 1
fi

echo '================================================================================'
echo 'please enter the block device name:'
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
		FSNAME=debian_"$DEBALIAS"_source
		HTTPSRC=http://mirrors.ustc.edu.cn/debian/
		;;
	2)	DEBALIAS=stretch
		FSNAME=debian_"$DEBALIAS"_source
		HTTPSRC=http://mirrors.ustc.edu.cn/debian/
		;;
	3)	DEBALIAS=jessie
		FSNAME=debian_"$DEBALIAS"_source
		HTTPSRC=http://mirrors.ustc.edu.cn/debian/
		;;
	4)	DEBALIAS=jessie
		FSNAME=debian_"$DEBALIAS"_linaro_source
		HTTPSRC=https://releases.linaro.org/debian/images/alip-armhf/17.02/linaro-jessie-alip-20161117-32.tar.gz
		;;
	*)	echo 'error, you typed a wrong number'
		exit 1
esac

echo '================================================================================'
echo 'please enter the path to hold the filesystem:'
read FSPATH

echo '================================================================================'
echo 'preparing misc...'
rm -rf $FSPATH
mkdir -p $FSPATH 
FSPATH=$FSPATH/$FSNAME

rm -rf $TMPMNT
mkdir -p $TMPMNT
umount $BLKDEV
mount $BLKDEV $TMPMNT

echo '================================================================================'
echo 'processing the linaro debian...'
if [ $DEBVER -eq 4 ]; then
	wget $HTTPSRC $FSPATH/

	exit 0
fi

echo '================================================================================'
echo 'processing the official debian...'
apt-get install binfmt-support qemu qemu-user-static debootstrap
debootstrap --arch=armel --foreign $DEBALIAS $FSPATH $HTTPSRC
cp /usr/bin/qemu-arm-static $FSPATH/usr/bin
DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANGUAGE=C LANG=C chroot $FSPATH debootstrap/debootstrap --second-stage
#debootstrap --second-stage

echo "proc /proc proc defaults 0 0" >> $FSPATH/etc/fstab
mkdir -p $FSPATH/usr/share/man/man1/
mknod $FSPATH/dev/console c 5 1

cp $FSPATH/etc/apt/source.list $FSPATH/etc/apt/source.list.bak
echo "deb $APTSRC buster main" > $FSPATH//etc/apt/sources.list

cat > $FSPATH/init_fs.sh << EOF
#!bin/sh
passwd root
apt-get update
apt-get install wpasupplicant udhcpc net-tools
echo 'these packages is recommanded:'
echo '    openssh-server git build-essential samba samba-common-bin nfs-kernel-server'
echo '    xinetd tftp tftpd xfce4 dos2unix vim ctags'
echo 'now you should install softwares you need by apt-get then exit'
EOF
chmod +x $FSPATH/init_fs.sh

echo 'now typing ./init_fs.sh'
chroot $FSPATH

echo 'done'
