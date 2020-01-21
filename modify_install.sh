#! /bin/bash

install_dir="$HOME"
hostname="jorges_ctf"

if [ $currentuser != "root" ]; then
    echo " you need sudo privileges to run this script, or run it as root"
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

cd $tmp
if [[ ! -f $tmp/$download_file ]]; then
    echo -n " downloading $download_file: "
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

if grep -qs $tmp/iso_org /proc/mounts ; then
    echo " image is already mounted, continue"
else
    (mount -o loop $tmp/$download_file $tmp/iso_org > /dev/null 2>&1)
fi
(cp -rT $tmp/iso_org $tmp/iso_new > /dev/null 2>&1)
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

#The above comes mostly from https://github.com/netson/ubuntu-unattended/

#After the initial configuration of hostnames and such, we then move onto the installation of dependencies

#for now we'll use a local script to install the dependencies
#First we'll start up a simple server and background it
python3 -m http.server 8090 --bind localhost
chroot $tmp/iso_new 




#Full Cleanup in CHROOT
#apt-get autoremove && apt-get autoclean
#rm -rf /tmp/* ~/.bash_history
#rm /var/lib/dbus/machine-id
#rm /sbin/initctl
#dpkg-divert --rename --remove /sbin/initctl