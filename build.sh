#!/bin/bash root

cleanHome(){
    cd ~
    sudo mv $HOME/livecdtmp/ubuntu-20.04-desktop-amd64.iso ~

    sudo umount $HOME/livecdtmp/mnt
    sudo umount $HOME/livecdtmp/edit/run

    sudo rm -r livecdtmp
}

cleanChroot(){
    sudo chroot edit apt clean
    sudo chroot edit rm -rf /tmp/* ~/.bash_history
    sudo chroot edit rm /etc/resolv.conf
    sudo chroot edit rm /sbin/initctl
    sudo chroot edit dpkg-divert --rename --remove /sbin/initctl
}

mountChroot(){
    sudo mount --bind /dev/ edit/dev
    sudo chroot edit mount -t proc none /proc
    sudo chroot edit mount -t sysfs none /sys
    sudo chroot edit mount -t devpts none /dev/pts
}

umountChroot(){
    sudo chroot edit umount /proc || umount -lf /proc
    sudo chroot edit umount /sys
    sudo chroot edit umount /dev/pts
    sudo chroot edit umount /dev
}

# Install pre-requisities
sudo apt install squashfs-tools genisoimage hashalot jq

#Obtain the base system
# 1 Download Ubuntu 20.04 desktop image in config to validate it
wget --no-parent --user-agent "user" -P $HOME/os-builder/ http://paraguayeduca.org/descarga/ubuntu-20.04-desktop-amd64.iso

#Verify that the image has been downloaded correctly
sudo sh $HOME/os-builder/helpers/validateIso.sh

#Capture return code from validateIso.sh
if [ $? -eq 0 ]; then
    echo "OK"
else
    exit 1
fi

#Move the downloaded image to the home
sudo mv $HOME/os-builder/ubuntu-20.04-desktop-amd64.iso ~

# 2 Move or copy it into an empty directory
cd ~
mkdir ~/livecdtmp
mv ubuntu-20.04-desktop-amd64.iso ~/livecdtmp

mkdir $HOME/os-builder/config/Activities
sudo cp $HOME/os-builder/config/repository.json $HOME/os-builder/config/Activities
cd $HOME/os-builder/config/Activities
bash $HOME/os-builder/helpers/activitiesGit.sh
sudo cp -r $HOME/os-builder/config ~/livecdtmp
sudo rm -r $HOME/os-builder/config/Activities/
cd ~

#Extract the CD .iso contents
#Mount the Desktop .iso
cd livecdtmp
mkdir mnt
sudo mount -o loop ubuntu-20.04-desktop-amd64.iso mnt

#Extract .iso contents into dir 'extract-cd'
mkdir extract-cd
sudo rsync --exclude=/casper/filesystem.squashfs -a mnt/ extract-cd

#Extract the Desktop system
sudo unsquashfs mnt/casper/filesystem.squashfs
sudo mv squashfs-root edit

#Prepare and chroot
#If you need network connectivity within chroot
sudo cp $HOME/os-builder/config/resolv.conf ~/livecdtmp/edit/etc/
sudo cp $HOME/os-builder/config/sources.list ~/livecdtmp/edit/etc/apt/

#Pull your host's resolvconf info into the chroot
cd ~/livecdtmp
sudo mount -o bind /run/ edit/run

#Copy the hosts file
sudo cp $HOME/os-builder/config/hosts ~/livecdtmp/edit/etc/

#Mount important directories of your host system to the edit directory
cd ~/livecdtmp
mountChroot

#Before installing or upgrading packages you need to run
sudo chroot edit dpkg-divert --local --rename --add /sbin/initctl
sudo chroot edit ln -s /bin/true /sbin/initctl

#Install software
sudo cp config/install.sh config/flatpak.json config/login config/login.png ~/livecdtmp/edit/
sudo chroot edit sudo bash install.sh
sudo chroot edit chmod +x login
sudo chroot edit ./login login.png
sudo cp -r ~/livecdtmp/config/Activities/* ~/livecdtmp/edit/usr/share/sugar/activities/

#Be sure to remove any temporary files which are no longer needed
cleanChroot

#Now unmount all special filesystems and exit the chroot
umountChroot

#Producing the CD image
#Assembling the file system
#Regenerate manifest
sudo chmod +w extract-cd/casper/filesystem.manifest
sudo cp extract-cd/casper/filesystem.manifest extract-cd/casper/filesystem.manifest-desktop
sudo sed -i '/ubiquity/d' extract-cd/casper/filesystem.manifest-desktop
sudo sed -i '/casper/d' extract-cd/casper/filesystem.manifest-desktop

#Compress filesystem
#To get the most compression possible at the cost of compression time, you can use the xz method and it is best to exclude the edit / boot directory entirely:

sudo mksquashfs edit extract-cd/casper/filesystem.squashfs -comp xz -e edit/boot

#Update the filesystem.size file, which is needed by the installer:
sudo printf $(du -sx --block-size=1 edit | cut -f1) >extract-cd/casper/filesystem.size

#Remove old md5sum.txt and calculate new md5 sums
cd extract-cd/
sudo rm md5sum.txt
find -type f -print0 | sudo xargs -0 md5sum | grep -v isolinux/boot.cat | sudo tee md5sum.txt

#Create the ISO image
sudo mkisofs -D -r -V "$IMAGE_NAME" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $HOME/ubuntu-20.04-sugar.iso .

#Clean home directory after created the iso
cleanHome