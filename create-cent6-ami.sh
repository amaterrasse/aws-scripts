#!/bin/sh

# Check EBS device file
#COUNT=`/bin/find /dev -name "xv*" -print | /usr/bin/wc -l`
COUNT=`/bin/ls -1t /dev/xv* | /usr/bin/wc -l`
if [ ${COUNT} -le 1 ]; then
  echo "Please Attach EBS VOLUME."
  exit 1
fi

EBS_DEV=`/bin/ls -1t /dev/xv* | /usr/bin/head -n 1`

# Check type of /dev/${EBS_DEV}
echo -n "Check ${EBS_DEV} ... "
if [ -b ${EBS_DEV} ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

# Create filesystem
echo "Begin create filesystem..."
/sbin/mkfs.ext4 ${EBS_DEV}
if [ $? -eq 0 ]; then
  echo "DONE: Create filesystem"
else
  echo "ERROR: Create filesystem"
  exit 1
fi

# Mount EBS Volume
echo -n "Mount EBS Volume... "
MOUNT_POINT=`/bin/mktemp -d -p /mnt`
/bin/mount -t ext4 ${EBS_DEV} ${MOUNT_POINT}
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

# Install MAKEDEV
echo -n "Install MAKEDEV..."
/usr/bin/yum -q -y install MAKEDEV
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

# Create device files
echo -n "Create device file: ${MOUNT_POINT}/dev/console ... "
/sbin/MAKEDEV -d ${MOUNT_POINT}/dev -x console
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Create device file: ${MOUNT_POINT}/dev/null ... "
/sbin/MAKEDEV -d ${MOUNT_POINT}/dev -x null
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Create device file: ${MOUNT_POINT}/dev/zero ... "
/sbin/MAKEDEV -d ${MOUNT_POINT}/dev -x zero
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Create etc directory: ${MOUNT_POINT}/etc ... "
/bin/mkdir ${MOUNT_POINT}/etc
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Create fstab: ${MOUNT_POINT}/etc/fstab ... "
/bin/cat >${MOUNT_POINT}/etc/fstab<<EOF
/dev/xvde1 / ext4 defaults 1 1
none /proc proc defaults 0 0
none /sys sysfs defaults 0 0
none /dev/pts devpts gid=5,mode=620 0 0
none /dev/shm tmpfs defaults 0 0
EOF
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Create proc filesystem: ${MOUNT_POINT}/proc ... "
/bin/mkdir ${MOUNT_POINT}/proc
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Mount proc filesystem: ${MOUNT_POINT}/proc ... "
/bin/mount -t proc none ${MOUNT_POINT}/proc
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Backup /etc/yum.repos.d to /etc/yum.repos.d.bak ... "
if [ -d /etc/yum.repos.d ]; then
  /bin/mv /etc/yum.repos.d /etc/yum.repos.d.bak
  if [ $? -ne 0 ]; then
    echo "ERROR"
    exit 1
  fi
else
  echo "ERROR"
  exit 1
fi
echo "OK"

echo -n "Cleanup yum repo ... "
/usr/bin/yum -q clean all
echo "OK"

echo -n "Create yum.conf: /mnt/yum.conf ... "
/bin/cat >/mnt/yum.conf<<EOF
[base]
name=CentOS-6 - Base
baseurl=http://mirror.centos.org/centos/6/os/x86_64/
[updates]
name=CentOS-6 - Updates
baseurl=http://mirror.centos.org/centos/6/updates/x86_64/
EOF
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Install Core package ... "
/usr/bin/yum -c /mnt/yum.conf --installroot=${MOUNT_POINT} -q -y groupinstall Core
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Install RPM-GPG-KEY-CentOS-6 ... "
/bin/cp -p ${MOUNT_POINT}/etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6 /etc/pki/rpm-gpg
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Install kernel ... "
/usr/bin/yum --installroot=${MOUNT_POINT} -q -y install kernel
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Recover /etc/yum.repos.d ... "
/bin/mv /etc/yum.repos.d.bak /etc/yum.repos.d
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Setting User Provided Kernel ... "
KERNEL_FULL_FILENAME=`/bin/ls -1 ${MOUNT_POINT}/boot/vmlinuz-*`
KERNEL_FILENAME=`/bin/basename ${KERNEL_FULL_FILENAME}`
INITRD_FULL_FILENAME=`/bin/ls -1 ${MOUNT_POINT}/boot/initramfs-*`
INITRD_FILENAME=`/bin/basename ${INITRD_FULL_FILENAME}`

/bin/cat > ${MOUNT_POINT}/boot/grub/menu.lst<<EOF
default=0
timeout=0
hiddenmenu
title CentOS 6
root (hd0)
kernel /boot/${KERNEL_FILENAME} ro root=/dev/xvde1
initrd /boot/${INITRD_FILENAME}
EOF
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Setting network file ... "
/bin/cat > ${MOUNT_POINT}/etc/sysconfig/network<<EOF
NETWORKING=yes
NETWORKING_IPV6=no
HOSTNAME=aws-cent6-template
EOF
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Setting ifcfg-eth0 file ... "
/bin/cat > ${MOUNT_POINT}/etc/sysconfig/network-scripts/ifcfg-eth0<<EOF
DEVICE=eth0
BOOTPROTO=dhcp
ONBOOT=on
EOF
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Setting hosts file ... "
/bin/cat > ${MOUNT_POINT}/etc/hosts<<EOF
127.0.0.1 aws-cent62-template localhost localhost.localdomain
EOF
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Disable SELINUX ... "
/bin/sed -i -e "s/SELINUX=enforcing/SELINUX=disabled/" ${MOUNT_POINT}/etc/selinux/config
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Setting SSH ... "
/bin/mkdir ${MOUNT_POINT}/root/.ssh
/bin/chmod 700 ${MOUNT_POINT}/root/.ssh
/bin/touch ${MOUNT_POINT}/root/.ssh/authorized_keys
/bin/chmod 600 ${MOUNT_POINT}/root/.ssh/authorized_keys
/bin/sed -i -e "s/#PermitRootLogin yes/PermitRootLogin without-password/" ${MOUNT_POINT}/etc/ssh/sshd_config
/bin/sed -i -e "s/#UseDNS yes/UseDNS no/" ${MOUNT_POINT}/etc/ssh/sshd_config
echo "OK"

echo -n "Setting rc.local ... "
/bin/cat >> ${MOUNT_POINT}/etc/rc.local<<EOF

# for AWS
PUB_KEY_URI=http://169.254.169.254/1.0/meta-data/public-keys/0/openssh-key
PUB_KEY_FROM_HTTP=/tmp/openssh_id.pub
ROOT_AUTHORIZED_KEYS=/root/.ssh/authorized_keys
/usr/bin/curl --retry 3 --retry-delay 0 --silent --fail -o \$PUB_KEY_FROM_HTTP \$PUB_KEY_URI
if [ \$? -eq 0 -a -e \$PUB_KEY_FROM_HTTP ] ; then
  if ! /bin/grep -q -f \$PUB_KEY_FROM_HTTP \$ROOT_AUTHORIZED_KEYS
  then
    /bin/cat \$PUB_KEY_FROM_HTTP >> \$ROOT_AUTHORIZED_KEYS
    echo "New key added to authrozied keys file from parameters" | /usr/bin/logger -t "aws"
    /bin/dd if=/dev/urandom count=50 | /usr/bin/md5sum | /usr/bin/passwd --stdin root
    echo "The root password randomized" | /usr/bin/logger -t "aws"
  fi
  /bin/chmod 600 \$ROOT_AUTHORIZED_KEYS
  /bin/rm -f \$PUB_KEY_FROM_HTTP
fi
EOF
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Unmount proc filesystem: ${MOUNT_POINT}/proc ..."
/bin/umount ${MOUNT_POINT}/proc
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi

echo -n "Unmount EBS Volume..."
/bin/umount ${MOUNT_POINT}
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "ERROR"
  exit 1
fi
