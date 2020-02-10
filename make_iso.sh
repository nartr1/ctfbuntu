#! /bin/bash

#This is where most of the work will be done, will contain the final .iso
mkdir final

#These just make it easier to keep track of where the hell this script is running from
working_dir="$(pwd)"
tmp="$(pwd)/final"

#Nothing special about this seed, pretty much a copy of the netson.seed for the script this one is based on
seed_file="jorge.seed"
IMAGE_NAME="jorgebuntu1"
#Honestly, this can be whatever you want it to be
hostname="jorges_ctf"

#For later use
cp $seed_file final

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

#Didn't feel like working with sed, this made for a nice workaround
function replace_string {
PYTHON_FILE_REPLACE="$1"
PYTHON_SEARCH_REPLACE="$2"
PYTHON_STRING_REPLACE="$3"
python3 - <<END
with open('$PYTHON_FILE_REPLACE') as f:
  newText=f.read().replace('$PYTHON_SEARCH_REPLACE', '$PYTHON_STRING_REPLACE')
  with open('$PYTHON_FILE_REPLACE', "w") as f:
    f.write(newText)
END
}

#An adapted bash/python3 integrated funtion adapted from here: https://serverfault.com/questions/330069/how-to-create-an-sha-512-hashed-password-for-shadow
function make_password {
PYTHON_PASSWORD="$1"
python3 - <<END
import crypt
print(crypt.crypt('$PYTHON_PASSWORD', crypt.mksalt(crypt.METHOD_SHA512)))
END
}

#Normal check, we need root to access mounting commands, as well as chroot further into the install
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

#Temporary storage of the ubuntu release page, most likely overkill for this. Originally used for a multiple choice unattended install script
tmphtml=$tmp/tmphtml
rm $tmphtml >/dev/null 2>&1

#Must be Ubuntu 18.04.3 as the server version is missing the casper directory which contains the filesystem to be modified
wget -O $tmphtml 'http://releases.ubuntu.com/' >/dev/null 2>&1
bion=$(fgrep Bionic $tmphtml | head -1 | awk '{print $3}' | sed 's/href=\"//; s/\/\"//')
bion_vers=$(fgrep Bionic $tmphtml | head -1 | awk '{print $6}')

download_file="ubuntu-$bion_vers-desktop-amd64.iso"
download_location="http://releases.ubuntu.com/18.04.3/"

#Might be changing this to something cooler, and not exactly the same as the fucking input file
new_iso_name="ctf-ubuntu-$bion_vers-amd64-unattended.iso"

#Keep this link around in case you need to hard code it in
#http://releases.ubuntu.com/18.04.3/ubuntu-18.04.3-desktop-amd64.iso

#Automatically pull the timezone from the local machine the script is being run on
if [ -f /etc/timezone ]; then
  timezone=`cat /etc/timezone`
elif [ -h /etc/localtime ]; then
  timezone=`readlink /etc/localtime | sed "s/\/usr\/share\/zoneinfo\///"`
else
  checksum=`md5sum /etc/localtime | cut -d' ' -f1`
  timezone=`find /usr/share/zoneinfo/ -type f -exec md5sum {} \; | grep "^$checksum" | sed "s/.*\/usr\/share\/zoneinfo\///" | head -n 1`
fi

#Let the user feel somewhat part of the process
read -ep " please enter your preferred timezone: " -i "${timezone}" timezone
read -ep " please enter your preferred username: " -i "jorge" username
read -sp " please enter your preferred password: " password
printf "\n"
read -sp " confirm your preferred password: " password2

#Pretty standard check, make sure the password confirmation matches
if [[ "$password" != "$password2" ]]; then
    echo " your passwords do not match; please restart the script and try again"
    echo ""
    exit
fi
echo ""

#Now begins the actual work with the iso
cd $tmp

#Check if the iso has already been download, HOWEVER this does not check the integrity of the ubuntu 18.04 iso.
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
echo " remastering your iso file"
mkdir $tmp/iso_org #iso_org is the mount point for the downloaded iso, we cannot work with it until it is copied into a new directory, hence the iso_new dir.
mkdir $tmp/iso_new

#Mount and copy the contents of the iso so we can modify it
echo "Mounting the downloaded iso and copying the relavent files"
mount -o loop $tmp/$download_file $tmp/iso_org > /dev/null 2>&1
(cp -rT $tmp/iso_org $tmp/iso_new > /dev/null 2>&1)

#Decompress the filesystem to allow for modification
echo "Decompressing the filesystem"
sudo rsync --exclude=/casper/filesystem.squashfs -a $tmp/iso_org $tmp/iso_new
unsquashfs $tmp/iso_new/casper/filesystem.squashfs #fix this
mv squashfs-root $tmp/iso_new

#Mounting of the psuedo directories to have full internet access because we will be working with the apt repo's, updating and installing dependencies
echo "Mounting the pseudo directories to allow for a more full out chroot for installs"
cp /etc/resolv.conf $tmp/iso_new/squashfs-root/etc
mount --bind /dev/ $tmp/iso_new/squashfs-root/dev
mount -t proc none $tmp/iso_new/squashfs-root/proc
mount -t sysfs none $tmp/iso_new/squashfs-root/sys
mount -t devpts none $tmp/iso_new/squashfs-root/dev/pts

#Currently Missing Dependencies:
#Logging system? (This will come later)
#Qemu+Virtualbox for the automatic instancing of prebuilt virtual machines (Also coming later)

echo "Building the dependency installer"
cat <<EOT > $tmp/iso_new/squashfs-root/etc/apt/sources.list
deb http://archive.ubuntu.com/ubuntu/ bionic main universe
deb http://security.ubuntu.com/ubuntu/ bionic-security main universe
deb http://archive.ubuntu.com/ubuntu/ bionic-updates main universe
EOT

cat <<EOT >> $tmp/iso_new/squashfs-root/after_chroot_todo.sh
export HOME=/root
export LC_ALL=C
dbus-uuidgen > /var/lib/dbus/machine-id
dpkg-divert --local --rename --add /sbin/initctl
ln -s /bin/true /sbin/initctl
export PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin
apt update -y && apt upgrade -y && apt dist-upgrade -y
apt remove -y thunderbird libreoffice
apt install software-properties-common build-essential git -y
apt update -y
apt install python-pip  python3-dev python3-mysqldb python3-mysqldb-dbg python3-pycurl zlib1g-dev memcached libmemcached-dev -y
echo "ctf" | apt install mysql-server libmysqlclient-dev -y
sudo service mysql enable
sudo service mysql start
sudo mysql -u root -p=rtb -e "create user 'rtb'@'localhost' identified by 'rtb'; create database rootthebox character set utf8mb4; grant all on rootthebox.* to 'rtb'@'localhost';"
echo "" > ~/.mysql_history
cd /root
git clone https://github.com/moloch--/RootTheBox.git /root/RootTheBox
pip3 install nose py-postgresql tornado==5.* pbkdf2 PyMySQL python-memcached python-dateutil defusedxml netaddr nose future python-resize-image sqlalchemy alembic enum34 mysqlclient rocketchat_API --upgrade
#check this
/root/RootTheBox/rootthebox.py --setup=prod

#Full Cleanup in CHROOT
apt-get autoremove -y && apt-get autoclean -y
rm -rf /tmp/* ~/.bash_history
rm /var/lib/dbus/machine-id
rm /sbin/initctl
dpkg-divert --rename --remove /sbin/initctl
umount /proc || umount -lf /proc
umount /sys || umount -lf /sys
umount /dev/pts || umount -lf /dev/pts
umount /dev || umount -lf /dev
exit
EOT

#Allow for execution of the chroot dependency script
chmod +x $tmp/iso_new/squashfs-root/after_chroot_todo.sh

#Enter the newly decompressed file system
cd $tmp/iso_new/squashfs-root

#Set up language to be English/US
echo "Setting up your language settings"
echo en > $tmp/iso_new/isolinux/lang

#Set up the pasword hash for /etc/shadow by using the preseed file's option for a password hash
echo "Making you a shiny new password hash"
pwhash=$(make_password $password)

#Copy our base seed file into where the other seed files reside
#OLD cp $tmp/$seed_file $tmp/iso_new/preseed/
cat << EOT >> $tmp/iso_new/preseed/$seed_file
# regional setting
d-i debian-installer/language                               string      en_US:en
d-i debian-installer/country                                string      US
d-i debian-installer/locale                                 string      en_US
d-i debian-installer/splash                                 boolean     false
d-i localechooser/supported-locales                         multiselect en_US.UTF-8
d-i pkgsel/install-language-support                         boolean     true

# keyboard selection
d-i console-setup/ask_detect                                boolean     false
d-i keyboard-configuration/modelcode                        string      pc105
d-i keyboard-configuration/layoutcode                       string      us
d-i keyboard-configuration/variantcode                      string      intl
d-i keyboard-configuration/xkb-keymap                       select      us(intl)
d-i debconf/language                                        string      en_US:en

# network settings
d-i netcfg/choose_interface                                 select      auto
d-i netcfg/dhcp_timeout                                     string      5
d-i netcfg/get_hostname                                     string      {{hostname}}
d-i netcfg/get_domain                                       string      {{hostname}}

# mirror settings
d-i mirror/country                                          string      manual
d-i mirror/http/hostname                                    string      archive.ubuntu.com
d-i mirror/http/directory                                   string      /ubuntu
d-i mirror/http/proxy                                       string

# clock and timezone settings
d-i time/zone                                               string      {{timezone}}
d-i clock-setup/utc                                         boolean     false
d-i clock-setup/ntp                                         boolean     true

# user account setup
d-i passwd/root-login                                       boolean     false
d-i passwd/make-user                                        boolean     true
d-i passwd/user-fullname                                    string      {{username}}
d-i passwd/username                                         string      {{username}}
d-i passwd/user-password-crypted                            password    {{pwhash}}
d-i passwd/user-uid                                         string
d-i user-setup/allow-password-weak                          boolean     false
d-i passwd/user-default-groups                              string      adm cdrom dialout lpadmin plugdev sambashare
d-i user-setup/encrypt-home                                 boolean     false

# configure apt
d-i apt-setup/restricted                                    boolean     true
d-i apt-setup/universe                                      boolean     true
d-i apt-setup/backports                                     boolean     true
d-i apt-setup/services-select                               multiselect security
d-i apt-setup/security_host                                 string      security.ubuntu.com
d-i apt-setup/security_path                                 string      /ubuntu
tasksel tasksel/first                                       multiselect Basic Ubuntu server
d-i pkgsel/upgrade                                          select      safe-upgrade
d-i pkgsel/update-policy                                    select      none
d-i pkgsel/updatedb                                         boolean     true

# disk partitioning
d-i partman/confirm_write_new_label                         boolean     true
d-i partman/choose_partition                                select      finish
d-i partman/confirm_nooverwrite                             boolean     true
d-i partman/confirm                                         boolean     true
d-i partman-auto/purge_lvm_from_device                      boolean     true
d-i partman-lvm/device_remove_lvm                           boolean     true
d-i partman-lvm/confirm                                     boolean     true
d-i partman-lvm/confirm_nooverwrite                         boolean     true
d-i partman-auto-lvm/no_boot                                boolean     true
d-i partman-md/device_remove_md                             boolean     true
d-i partman-md/confirm                                      boolean     true
d-i partman-md/confirm_nooverwrite                          boolean     true
d-i partman-auto/method                                     string      lvm
d-i partman-auto-lvm/guided_size                            string      max
d-i partman-partitioning/confirm_write_new_label            boolean     true

# grub boot loader
d-i grub-installer/only_debian                              boolean     true
d-i grub-installer/with_other_os                            boolean     true

# finish installation
d-i finish-install/reboot_in_progress                       note
d-i finish-install/keep-consoles                            boolean     false
d-i cdrom-detect/eject                                      boolean     true
d-i debian-installer/exit/halt                              boolean     false
d-i debian-installer/exit/poweroff                          boolean     false
EOT


echo "Replacing terms in the seed file"
replace_string $tmp/iso_new/preseed/$seed_file {{username}} $username
replace_string $tmp/iso_new/preseed/$seed_file {{pwhash}} $pwhash
replace_string $tmp/iso_new/preseed/$seed_file {{hostname}} $hostname
replace_string $tmp/iso_new/preseed/$seed_file {{timezone}} $timezone

echo "Remastering the checksums of files"
seed_checksum=$(md5sum $tmp/iso_new/preseed/$seed_file)

#Add autoinstall option to menu
#Fix this
echo "Adding autoinstall option to installation menu"
sed -i "/label install/ilabel autoinstall\n\
  menu label ^Autoinstall Jorge's CTF Ubuntu Server\n\
  kernel /install/vmlinuz\n\
  append file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/netson.seed preseed/file/checksum=$seed_checksum --" $tmp/iso_new/isolinux/txt.cfg

#This fucked me for a while. DONT OVERWRITE YOUR WORK
#After the initial configuration of hostnames and such, we then move onto the installation of dependencies

#for now we'll use a local script to install the dependencies
#First we'll start up a simple server and background it
echo "Installing dependencies"
chroot . "./after_chroot_todo.sh"

# cleanup
echo "Cleaning up"
umount $tmp/iso_org
rm -rf $tmp/iso_new/casper/filesystem.squashfs
#umount -lf $tmp/iso_new/squashfs-root/dev
#umount -lf $tmp/iso_new/squashfs-root/proc
#umount -lf $tmp/iso_new/squashfs-root/sys
#umount $tmp/ubuntu-18.04.3-desktop-amd64.iso


#Fix the dpkg-query and tee issues
chmod +w $tmp/iso_new/casper/filesystem.manifest
chroot $tmp/iso_new/squashfs-root dpkg-query -W --showformat='${Package} ${Version}\n' | sudo tee $tmp/iso_new/casper/filesystem.manifest
cp $tmp/iso_new/casper/filesystem.manifest $tmp/iso_new/casper/filesystem.manifest-desktop
sed -i '/ubiquity/d' $tmp/iso_new/casper/filesystem.manifest-desktop
sed -i '/casper/d' $tmp/iso_new/casper/filesystem.manifest-desktop

mksquashfs $tmp/iso_new/squashfs-root $tmp/iso_new/casper/filesystem.squashfs -b 1048576

#Fix this too
printf $(sudo du -sx --block-size=1 $tmp/iso_new | cut -f1) > $tmp/iso_new/casper/filesystem.size
rm -rf $tmp/iso_new/md5sum.txt
cd $tmp/iso_new
find -type f -print0 | sudo xargs -0 md5sum | grep -v $tmp/iso_new/isolinux/boot.cat > $tmp/iso_new/md5sum.txt

#Helper from forum
#mkisofs -r -V "Fedora Live" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o Fedora-Live-14.iso mycd/
#OLD #cd $tmp/iso_new && sudo genisoimage -loliet-long -D -r -V "$IMAGE_NAME" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o ../jorgebuntu.iso .
cd $tmp/iso_new && sudo genisoimage -joliet-long -D -r -V "Jorgebuntu" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o ../jorgebuntu.iso .

#rm -rf $tmp/iso_new
rm -rf $tmp/iso_org
rm -rf $tmphtml

# print info to user
echo " -----"
echo " finished remastering your ubuntu iso file"
echo " the new file is located at: $tmp/$new_iso_name"
echo " your username is: $username"
echo " your password is: $password"
echo " your hostname is: $hostname"
echo " your timezone is: $timezone"
echo ""

# unset vars
unset username
unset password
unset hostname
unset timezone
unset pwhash
unset download_file
unset download_location
unset new_iso_name
unset tmp
unset seed_file