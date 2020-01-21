#! /bin/bash

mkdir final
tmp="$(pwd)/final"
install_dir="$HOME"
hostname="jorges_ctf"
# define download function
# courtesy of http://fitnr.com/showing-file-download-progress-using-wget.html
download()
{
    local url=$1
    echo -n "    "
    wget --progress=dot $url 2>&1 | grep --line-buffered "%" | \
        sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
    echo -ne "\b\b\b\b"
    echo " DONE"
}

# define function to check if program is installed
# courtesy of https://gist.github.com/JamieMason/4761049
function program_is_installed {
    # set to 1 initially
    local return_=1
    # set to 0 if not found
    type $1 >/dev/null 2>&1 || { local return_=0; }
    # return value
    echo $return_
}

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

tmphtml=$tmp/tmphtml
rm $tmphtml >/dev/null 2>&1
wget -O $tmphtml 'http://releases.ubuntu.com/' >/dev/null 2>&1
bion=$(fgrep Bionic $tmphtml | head -1 | awk '{print $3}' | sed 's/href=\"//; s/\/\"//')
bion_vers=$(fgrep Bionic $tmphtml | head -1 | awk '{print $6}')

download_file="ubuntu-$bion_vers-server-amd64.iso"
download_location="http://cdimage.ubuntu.com/releases/$bion/release/"
new_iso_name="ubuntu-$bion_vers-server-amd64-unattended.iso"

if [ -f /etc/timezone ]; then
  timezone=`cat /etc/timezone`
elif [ -h /etc/localtime ]; then
  timezone=`readlink /etc/localtime | sed "s/\/usr\/share\/zoneinfo\///"`
else
  checksum=`md5sum /etc/localtime | cut -d' ' -f1`
  timezone=`find /usr/share/zoneinfo/ -type f -exec md5sum {} \; | grep "^$checksum" | sed "s/.*\/usr\/share\/zoneinfo\///" | head -n 1`
fi

read -ep " please enter your preferred timezone: " -i "${timezone}" timezone
read -ep " please enter your preferred username: " -i "jorge" username
read -sp " please enter your preferred password: " password
printf "\n"
read -sp " confirm your preferred password: " password2

if [[ "$password" != "$password2" ]]; then
    echo " your passwords do not match; please restart the script and try again"
    echo
    exit
fi
echo ""
cd $tmp
if [[ ! -f $tmp/$download_file ]]; then
    echo -n "downloading $download_file: "
    download "$download_location$download_file"
fi
if [[ ! -f $tmp/$download_file ]]; then
  echo "Error: Failed to download ISO: $download_location$download_file"
  echo "This file may have moved or may no longer exist."
  echo
  echo "You can download it manually and move it to $tmp/$download_file"
  echo "Then run this script again."
  exit 1
fi
seed_file="jorge.seed"

echo " remastering your iso file"
mkdir -p $tmp
mkdir -p $tmp/iso_org
mkdir -p $tmp/iso_new

#Check for mounting errors
if grep -qs $tmp/iso_org /proc/mounts ; then
    echo " image is already mounted, continue"
else
    (mount -o loop $tmp/$download_file $tmp/iso_org > /dev/null 2>&1)
fi
(cp -rT $tmp/iso_org $tmp/iso_new > /dev/null 2>&1)

#Decompress the filesystem to allow for modification
sudo rsync --exclude=/casper/filesystem.squashfs -a $tmp/iso_org $tmp/iso_new
unsquashfs mnt/casper/filesystem.squashfs
mv squashfs-root $tmp/iso_new

#Mounting of the psuedo directories to have full internet access
cp /etc/resolv.conf $tmp/iso_new/etc
mount --bind /dev/ $tmp/iso_new/dev
mount -t proc none $tmp/iso_new/proc
mount -t sysfs none $tmp/iso_new/sys
mount -t devpts none $tmp/iso_new/dev/pts

#Create a script to be run within the chroot to properly install dependencies
cat <<EOT >> $tmp/iso_new/after_chroot_todo.sh
export HOME=/root
export LC_ALL=C
dbus-uuidgen > /var/lib/dbus/machine-id
dpkg-divert --local --rename --add /sbin/initctl
ln -s /bin/true /sbin/initctl
export PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin
apt update -y && apt upgrade -y && apt dist-upgrade -y
apt install software-properties-common build-essential git
apt update
apt install python3-pip python3-dev python3-mysqldb python3-mysqldb-dbg python3-pycurl zlib1g-dev memcached libmemcached-dev

#Full Cleanup in CHROOT
apt-get autoremove && apt-get autoclean
rm -rf /tmp/* ~/.bash_history
rm /var/lib/dbus/machine-id
rm /sbin/initctl
dpkg-divert --rename --remove /sbin/initctl
EOT

cd $tmp/iso_new
echo en > $tmp/iso_new/isolinux/lang
pwhash=$(echo $password | mkpasswd -s -m sha-512)

sed -i "s@{{username}}@$username@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{pwhash}}@$pwhash@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{hostname}}@$hostname@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{timezone}}@$timezone@g" $tmp/iso_new/preseed/$seed_file

seed_checksum=$(md5sum $tmp/iso_new/preseed/$seed_file)

#Add autoinstall option to menu
sed -i "/label install/ilabel autoinstall\n\
  menu label ^Autoinstall Jorge's CTF Ubuntu Server\n\
  kernel /install/vmlinuz\n\
  append file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/netson.seed preseed/file/checksum=$seed_checksum --" $tmp/iso_new/isolinux/txt.cfg

cp -rT $tmp/$seed_file $tmp/iso_new/preseed/$seed_file

#After the initial configuration of hostnames and such, we then move onto the installation of dependencies

#for now we'll use a local script to install the dependencies
#First we'll start up a simple server and background it
chroot $tmp/iso_new ./after_chroot_todo.sh