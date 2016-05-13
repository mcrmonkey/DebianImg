#!/bin/bash -ex

DEVICE=/dev/sdb
ROOTFS=/rootfs
DISTRO=jessie
BINDMNTS="dev sys"
SUPPMNTS="etc/hosts etc/resolv.conf"




## Clean up the target disk to prevent errors showing up in the partioning step, be quiet about it too.

dd if=/dev/zero of=${DEVICE} bs=1M count=5 2>&1 >/dev/null && partprobe 



## Partition the target - GPT

parted ${DEVICE} << EOFF
mktable gpt
mkpart primary ext2 1 2
set 1 bios_grub on
mkpart primary ext4 2 100%
quit
EOFF

## Then Format with ext4, and mount it where ROOTFS says

mkfs.ext4 -L root ${DEVICE}2

mkdir -p $ROOTFS

mount ${DEVICE}2 ${ROOTFS}


## Bootstrap the image install ... This may take a while. Go grab a coffee.

debootstrap --include=atop,htop,vim,grub2,sudo,openssh-server,less,locales-all,linux-image-686-pae,ca-certificates,curl,haveged,cloud-init --arch=i386 ${DISTRO} ${ROOTFS}

## Make sure this exists
touch ${ROOTFS}/etc/resolv.conf

## mount common things

for d in $BINDMNTS ; do
  mount --bind /${d} ${ROOTFS}/${d}
done
mount -t proc none ${ROOTFS}/proc


## detail what to mount systemD will handle the rest

cat > ${ROOTFS}/etc/fstab <<EOFF
LABEL=root	/         ext4    defaults,relatime,errors=remount-ro  0 1
EOFF



## Install grub so we can boot

chroot ${ROOTFS} grub-install /dev/sdb
chroot ${ROOTFS} update-grub


## Setup basic networking

cat << EOFF >> ${ROOTFS}/etc/network/interfaces


# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug eth0
iface eth0 inet dhcp

EOFF


## Setup some default apt repos, then update from them.

cat << EOFF > ${ROOTFS}/etc/apt/sources.list

deb http://ftp.uk.debian.org/debian/ jessie main
deb-src http://ftp.us.debian.org/debian ${DISTRO} main

deb http://security.debian.org/ ${DISTRO}/updates main
deb-src http://security.debian.org/ ${DISTRO}/updates main

EOFF

chroot ${ROOTFS} apt-get update



## Give a configuration for cloud-init so it can do stuff

cat > ${ROOTFS}/etc/cloud/cloud.cfg << EOFF
users:
 - default

disable_root: 1
ssh_pwauth:   0

mount_default_fields: [~, ~, 'auto', 'defaults,nofail', '0', '2']
resize_rootfs_tmp: /dev
ssh_deletekeys:   True
ssh_genkeytypes:  ['rsa', 'ed25519']
syslog_fix_perms: ~

cloud_init_modules:
 - migrator
 - bootcmd
 - write-files
 - growpart
 - resizefs
# - set_hostname
# - update_hostname
# - update_etc_hosts
 - rsyslog
 - users-groups
 - ssh

cloud_config_modules:
 - mounts
 - locale
 - set-passwords
# - yum-add-repo
 - package-update-upgrade-install
 - timezone
# - puppet
# - chef
# - salt-minion
# - mcollective
# - disable-ec2-metadata
 - runcmd

cloud_final_modules:
# - rightscale_userdata
 - scripts-per-once
 - scripts-per-boot
 - scripts-per-instance
 - scripts-user
 - ssh-authkey-fingerprints
 - keys-to-console
# - phone-home
 - final-message

system_info:
  default_user:
    name: debian
    lock_passwd: true
    gecos: Cloud User
    groups: [sudo, adm, systemd-journal]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash

  paths:
    cloud_dir: /var/lib/cloud
    templates_dir: /etc/cloud/templates
  ssh_svcname: sshd

mounts:
 - [ ephemeral0, /media/ephemeral0 ]
 - [ swap, none, swap, sw, "0", "0" ]

datasource_list: [ None ]

EOFF





