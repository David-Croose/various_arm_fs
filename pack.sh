#!/bin/bash

# buildroot
CONFIG_BUILDROOT_ENABLE=y
CONFIG_BUILDROOT_OUTPUT=output/buildrootfs.tar

# ubuntu
CONFIG_UBUNTU_ENABLE=
CONFIG_UBUNTU_APT_SOURCE=http://mirrors.ustc.edu.cn/ubuntu-ports/
CONFIG_UBUNTU_DEFAULT_SW='sudo ssh net-tools wireless-tools ifupdown network-manager iputils-ping bash-completion wpasupplicant udhcpc'
CONFIG_UBUNTU_ALIAS=xenial
CONFIG_UBUNTU=ubuntu-base-16.04.6-base-armhf.tar.gz
CONFIG_UBUNTU_SRC=http://cdimage.ubuntu.com/ubuntu-base/releases/16.04.1/release/$CONFIG_UBUNTU
CONFIG_UBUNTU_FOLDER=tmp/ubuntu-base-16.04.6
CONFIG_UBUNTU_DL=dl/$CONFIG_UBUNTU
CONFIG_UBUNTU_OUTPUT=output/ubuntu-base-16.04.6-base-armhf.tar.bz2

# debian
CONFIG_LINARO_DEBIAN_ENABLE=
CONFIG_LINARO_DEBIAN=linaro-jessie-alip-20161117-32.tar.gz
CONFIG_LINARO_DEBIAN_SRC=https://releases.linaro.org/debian/images/alip-armhf/17.02/$CONFIG_LINARO_DEBIAN
CONFIG_LINARO_DEBIAN_FOLDER=tmp/linaro-jessie-alip-20161117-32
CONFIG_LINARO_DEBIAN_DL=dl/$CONFIG_LINARO_DEBIAN
CONFIG_LINARO_DEBIAN_OUTPUT=output/$CONFIG_LINARO_DEBIAN

CONFIG_OFFICIAL_DEBIAN_ENABLE=
CONFIG_OFFICIAL_DEBIAN_ALIAS=stretch  # 10:buster 9:stretch 8:jessie
CONFIG_OFFICIAL_DEBIAN_FOLDER=tmp/debian_$CONFIG_OFFICIAL_DEBIAN_ALIAS
CONFIG_OFFICIAL_DEBIAN_SRC=http://mirrors.ustc.edu.cn/debian/
CONFIG_OFFICIAL_DEBIAN_OUTPUT=output/debian_$CONFIG_OFFICIAL_DEBIAN_ALIAS.tar.bz2

CONFIG_DEBIAN_APT_SOURCE=http://mirrors.ustc.edu.cn/debian/  # debian may not support https
CONFIG_DEBIAN_DEFAULT_SW=$CONFIG_UBUNTU_DEFAULT_SW

# users
CONFIG_ROOT_PASSWD=123

# outputs
CONFIG_ROOTFS_BLKDEV=
###########################################################################################

mnt2()
{
    echo "MOUNTING"
    mount -t proc  /proc    ${1}/proc
    mount -t sysfs /sys     ${1}/sys
    mount -o bind  /dev     ${1}/dev
    mount -o bind  /dev/pts ${1}/dev/pts
}

umnt2()
{
    echo "UNMOUNTING"
    umount ${1}/proc
    umount ${1}/sys
    umount ${1}/dev/pts
    umount ${1}/dev
}

umout_all()
{
	set +e

	df | grep $CONFIG_ROOTFS_BLKDEV 2>&1 1>/dev/null
	if [ $? == 0 ]; then
		umount $CONFIG_ROOTFS_BLKDEV
	fi

	set -e
}

debian_modify()
{
	local TYPE=$1	# official or linaro
	local DESTFOLDER=$2	# debian source path

	echo 'installing essential packages...'
	apt --yes install binfmt-support qemu qemu-user-static debootstrap multistrap

	if [ "$TYPE" = official ]; then
		echo "retrieving official-debian fs..."
		rm -rf $DESTFOLDER
		# ignore this log:
		# W: Cannot check Release signature; keyring file not available /usr/share/keyrings/debian-archive-keyring.gpg
		debootstrap --arch=armel --foreign $CONFIG_OFFICIAL_DEBIAN_ALIAS $DESTFOLDER $CONFIG_OFFICIAL_DEBIAN_SRC

		echo "debootstrap the official debian, this could take a big while..."
		cp /usr/bin/qemu-arm-static $DESTFOLDER/usr/bin
		DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANGUAGE=C LANG=C chroot $DESTFOLDER debootstrap/debootstrap --second-stage --verbose

		echo "creating essential files for official debian..."
		echo "proc /proc proc defaults 0 0" >> $DESTFOLDER/etc/fstab
		mkdir -p $DESTFOLDER/usr/share/man/man1/
		mknod $DESTFOLDER/dev/console c 5 1
	else
		cp /usr/bin/qemu-arm-static $DESTFOLDER/usr/bin
	fi

	echo "generating apt source.list in china..."
	cp $DESTFOLDER/etc/apt/sources.list $DESTFOLDER/etc/apt/sources.list.bak
	if [ "$TYPE" = official ]; then
		echo "deb $CONFIG_DEBIAN_APT_SOURCE $CONFIG_OFFICIAL_DEBIAN_ALIAS main" > $DESTFOLDER/etc/apt/sources.list
	else
		TMP_APT_SOURCE=$(echo $CONFIG_DEBIAN_APT_SOURCE | sed 's/\//\\\//g')
		sed -i /security/d $DESTFOLDER/etc/apt/sources.list
		sed -i "s/http:\/\/http.debian.net\/debian\//$TMP_APT_SOURCE/g" $DESTFOLDER/etc/apt/sources.list
	fi

	echo "chroot into debian fs, this could take a big while..."
	mnt2 $DESTFOLDER
	chroot $DESTFOLDER /bin/bash <<- EOT
		passwd root <<- EOF
			$CONFIG_ROOT_PASSWD
			$CONFIG_ROOT_PASSWD
		EOF
		apt update
		apt --yes install $CONFIG_DEBIAN_DEFAULT_SW
	EOT
	umnt2 $DESTFOLDER

	echo "setting logging permission of root in ssh..."
	echo "PermitRootLogin yes" >> $DESTFOLDER/etc/ssh/sshd_config

	echo "removing useless files..."
	rm -f $DESTFOLDER/usr/bin/qemu-arm-static
}

extract_rootfs()
{
	if [ -n "$CONFIG_ROOTFS_BLKDEV" ]; then
		local SRC=$1
		local DESTPATH=$2

		tar -xf $SRC -C $DESTPATH
	fi
}

###########################################################################################

HOME=$PWD
USERCONFIG=config
TMPMNT=mnt

test -f $USERCONFIG && source $USERCONFIG

set -e

echo "====================================================================================="
echo "checking configurations..."
if [ $(whoami) != root ]; then
	echo "error, you must be root."
	exit 1
fi

if [ "$CONFIG_BUILDROOT_ENABLE$CONFIG_UBUNTU_ENABLE$CONFIG_LINARO_DEBIAN_ENABLE$CONFIG_OFFICIAL_DEBIAN_ENABLE" != y ]; then
	echo "these items are wrong:"
	echo "    CONFIG_BUILDROOT_ENABLE"
	echo "    CONFIG_UBUNTU_ENABLE"
	echo "    CONFIG_LINARO_DEBIAN_ENABLE"
	echo "    CONFIG_OFFICIAL_DEBIAN_ENABLE"
	exit 2
fi

if [ "$CONFIG_OFFICIAL_DEBIAN_ENABLE" = y ] && [ -z "$CONFIG_OFFICIAL_DEBIAN_ALIAS" ]; then
	echo "error, CONFIG_OFFICIAL_DEBIAN_ALIAS can't be empty."
	exit 3
fi

if [ "$CONFIG_UBUNTU_ENABLE$CONFIG_OFFICIAL_DEBIAN_ENABLE" = y ] && [ -z "$CONFIG_ROOT_PASSWD" ]; then
	echo "error, CONFIG_ROOT_PASSWD can't be empty."
	exit 4
fi

echo "====================================================================================="
echo "preparing output file..."
if [ -n "$CONFIG_ROOTFS_BLKDEV" ]; then
	umout_all $CONFIG_ROOTFS_BLKDEV
	rm -rf $TMPMNT
	mkdir -p $TMPMNT
	mount $CONFIG_ROOTFS_BLKDEV $TMPMNT
fi

echo "====================================================================================="
echo "generating rootfs..."
if [ "$CONFIG_BUILDROOT_ENABLE" = y ]; then
	if [ -f $CONFIG_BUILDROOT_OUTPUT ]; then
		echo "extracting buildroot fs..."
		extract_rootfs $CONFIG_BUILDROOT_OUTPUT $TMPMNT
		echo "done"
		exit 0
	else
		echo "error, the file: $CONFIG_BUILDROOT_OUTPUT does not existence."
		exit 5
	fi

elif [ "$CONFIG_LINARO_DEBIAN_ENABLE" = y ]; then
	if [ -f $CONFIG_LINARO_DEBIAN_OUTPUT ]; then
		echo "extracting linaro-debian fs..."
		extract_rootfs $CONFIG_LINARO_DEBIAN_OUTPUT $TMPMNT
		echo "done"
		exit 0
	fi

	if [ ! -f $CONFIG_LINARO_DEBIAN_DL ]; then
		echo "retrieving linaro-debian fs..."
		wget -P dl $CONFIG_LINARO_DEBIAN_SRC
	fi
	rm -rf $CONFIG_LINARO_DEBIAN_FOLDER
	mkdir -p $CONFIG_LINARO_DEBIAN_FOLDER
	tar -xf $CONFIG_LINARO_DEBIAN_DL -C $CONFIG_LINARO_DEBIAN_FOLDER
	CONFIG_LINARO_DEBIAN_FOLDER=$CONFIG_LINARO_DEBIAN_FOLDER/binary

	debian_modify linaro $CONFIG_LINARO_DEBIAN_FOLDER

	echo "generating linaro debian image..."
	SRCPATH=$(find $CONFIG_LINARO_DEBIAN_FOLDER -type d -name proc | xargs dirname)
	cd $SRCPATH
	tar -cf $HOME/$CONFIG_LINARO_DEBIAN_OUTPUT *
	cd $HOME

elif [ "$CONFIG_OFFICIAL_DEBIAN_ENABLE" = y ]; then
	if [ -f $CONFIG_OFFICIAL_DEBIAN_OUTPUT ]; then
		echo "extracting official-debian fs..."
		extract_rootfs $CONFIG_OFFICIAL_DEBIAN_OUTPUT $TMPMNT
		echo "done"
		exit 0
	fi

	rm -rf $CONFIG_OFFICIAL_DEBIAN_FOLDER
	mkdir -p $CONFIG_OFFICIAL_DEBIAN_FOLDER
	debian_modify official $CONFIG_OFFICIAL_DEBIAN_FOLDER

	echo "generating official debian image..."
	SRCPATH=$(find $CONFIG_OFFICIAL_DEBIAN_FOLDER -type d -name proc | xargs dirname)
	cd $SRCPATH
	tar -cf $HOME/$CONFIG_OFFICIAL_DEBIAN_OUTPUT *
	cd $HOME

elif [ "$CONFIG_UBUNTU_ENABLE" = y ]; then
	if [ -f $CONFIG_UBUNTU_OUTPUT ]; then
		echo "extracting ubuntu fs..."
		extract_rootfs $CONFIG_UBUNTU_OUTPUT $TMPMNT
		echo "done"
		exit 0
	fi

	if [ ! -f $CONFIG_UBUNTU_DL ]; then
		echo "retrieving ubuntu fs..."
		wget -P dl $CONFIG_UBUNTU_SRC
	fi
	rm -rf $CONFIG_UBUNTU_FOLDER
	mkdir -p $CONFIG_UBUNTU_FOLDER
	tar -xf $CONFIG_UBUNTU_DL -C $CONFIG_UBUNTU_FOLDER

	echo "preparing the serial console..."
	cat > $CONFIG_UBUNTU_FOLDER/etc/init/ttyS0.conf <<- EOF
		start on stopped rc or RUNLEVEL=[12345]
		stop on RUNLEVEL [!12345]
		respawn
		exec /sbin/getty -L 115200 ttyS0 vt102
	EOF

	echo 'installing essential packages...'
	apt --yes install qemu-user-static
	cp /usr/bin/qemu-arm-static $CONFIG_UBUNTU_FOLDER/usr/bin

	echo "generating apt source.list in china..."
	mv $CONFIG_UBUNTU_FOLDER/etc/apt/sources.list $CONFIG_UBUNTU_FOLDER/etc/apt/sources.list.bak
	cat > $CONFIG_UBUNTU_FOLDER/etc/apt/sources.list <<- EOF
		deb $CONFIG_UBUNTU_APT_SOURCE $CONFIG_UBUNTU_ALIAS main multiverse restricted universe
		deb $CONFIG_UBUNTU_APT_SOURCE $CONFIG_UBUNTU_ALIAS-backports main multiverse restricted universe
		deb $CONFIG_UBUNTU_APT_SOURCE $CONFIG_UBUNTU_ALIAS-proposed main multiverse restricted universe
		deb $CONFIG_UBUNTU_APT_SOURCE $CONFIG_UBUNTU_ALIAS-security main multiverse restricted universe
		deb $CONFIG_UBUNTU_APT_SOURCE $CONFIG_UBUNTU_ALIAS-updates main multiverse restricted universe
		deb-src $CONFIG_UBUNTU_APT_SOURCE $CONFIG_UBUNTU_ALIAS main multiverse restricted universe
		deb-src $CONFIG_UBUNTU_APT_SOURCE $CONFIG_UBUNTU_ALIAS-backports main multiverse restricted universe
		deb-src $CONFIG_UBUNTU_APT_SOURCE $CONFIG_UBUNTU_ALIAS-proposed main multiverse restricted universe
		deb-src $CONFIG_UBUNTU_APT_SOURCE $CONFIG_UBUNTU_ALIAS-security main multiverse restricted universe
		deb-src $CONFIG_UBUNTU_APT_SOURCE $CONFIG_UBUNTU_ALIAS-updates main multiverse restricted universe
	EOF

	echo "chroot into ubuntu fs, this could take a big while..."
	cp /etc/resolv.conf $CONFIG_UBUNTU_FOLDER/etc/resolv.conf
	mnt2 $CONFIG_UBUNTU_FOLDER
	chroot $CONFIG_UBUNTU_FOLDER /bin/bash <<- EOT
		passwd root <<- EOF
			$CONFIG_ROOT_PASSWD
			$CONFIG_ROOT_PASSWD
		EOF
		apt update
		apt --yes install $CONFIG_UBUNTU_DEFAULT_SW
	EOT
	umnt2 $CONFIG_UBUNTU_FOLDER

	echo "setting logging permission of root in ssh..."
	sed -i 's/^PermitRootLogin prohibit-password/#PermitRootLogin prohibit-password/' $CONFIG_UBUNTU_FOLDER/etc/ssh/sshd_config
	echo "PermitRootLogin yes" >> $CONFIG_UBUNTU_FOLDER/etc/ssh/sshd_config
	echo "PermitEmptyPasswords yes" >> $CONFIG_UBUNTU_FOLDER/etc/ssh/sshd_config

	echo "setting others..."
	echo "ubuntu" > $CONFIG_UBUNTU_FOLDER/etc/hostname
	echo "127.0.0.1 localhost" >> $CONFIG_UBUNTU_FOLDER/etc/hosts
	echo "127.0.0.1 ubuntu" >> $CONFIG_UBUNTU_FOLDER/etc/hosts

	echo "generating ubuntu image..."
	rm -f $CONFIG_UBUNTU_FOLDER/etc/resolv.conf
	rm -f $CONFIG_UBUNTU_FOLDER/usr/bin/qemu-arm-static
	SRCPATH=$(find $CONFIG_UBUNTU_FOLDER -type d -name proc | xargs dirname)
	cd $SRCPATH
	tar -cf $HOME/$CONFIG_UBUNTU_OUTPUT *
	cd $HOME
fi

if [ -n "$CONFIG_ROOTFS_BLKDEV" ]; then
	umout_all $CONFIG_ROOTFS_BLKDEV
	rm -rf $TMPMNT/*
fi

echo "done"
