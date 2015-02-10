#!/bin/bash
#enable debugging
set -x
CURRENT_DIR=`pwd`
TOOLS_DIR=$(dirname $0)
PRG=$(basename $0)

##################################################################
# function help message
function Usage ()
{
   echo "Usage:"
   echo "    $PRG [options] <sourceRfsDir> <destDirForVmdkFile>"
   echo "Available options:"
   echo "    -h|--help     This help message"
   echo "    -s            Size of disk in MiB"
   echo "    -n            Name of the zipped file w/o file extension"
}

##################################################################
# function to read the command line
function GetOptions ()
{
   declare -i optIndex=0
   while test $# -gt 0 ; do
     case $1 in
     # Normal options 
       -h | --help) Usage; exit 0;;
       -s)  # size of vmdk
            if [[ $# -gt 1 && "$2" != "" ]]; then
               LSIM_IMAGE_SIZE="$2"
               shift
            fi
         ;;
       -n)  # name of vmdk
            if [[ $# -gt 1 && "$2" != "" ]]; then
               LSIM_FILE_NAME="$2"
               shift
            fi
         ;;
     # Special cases
       *) break ;;   # Done with options
     esac
     # next option 
     ((optIndex++))
     shift
   done
   if test $# -eq 2 ; then
      LSIM_MOUNT_POINT=${1} # the place of the currently created root file system
      LSIM_OUTPUT_DIR=${2}  # the place where the vmdk file shall be created
   fi
}

##################################################################
# function to react on creating vmdk image errors
# If $1 is "" this function cleans up the mounts and loop devices
function ErrorCreatingVMDKImage()
{
  set +u
  VMDK_ERROR="${1}"
  THIS_USER=`stat --format="%U" ${LSIM_MOUNT_POINT}`
  if [[ -z ${LOOP_DEVICE} ]]; then
    set -u
    for LINE in `mount | grep "${THIS_USER}" | grep "${LSIM_FILE_NAME}"`; do
      MOUNT_POINT_LINE=`echo ${LINE} | awk '{print $3}'`
      sudo umount ${MOUNT_POINT_LINE} 2>/dev/null
    done
    for LINE in `sudo losetup --all | grep "${LSIM_FILE_NAME}" | grep "${THIS_USER}"`; do
      LOOP_DEVICE=`echo ${LINE} | sed 's|.*loop\([0-9]\).*|/dev/loop\1|'`
      sleep 1
      sudo kpartx -d ${LOOP_DEVICE} 2>/dev/null
      sleep 1
      sudo losetup -d ${LOOP_DEVICE} 2>/dev/null
    done
  else
    set -u
    sleep 1
    sudo kpartx -d ${LOOP_DEVICE} 2>/dev/null
    sleep 1
    sudo losetup -d ${LOOP_DEVICE} 2>/dev/null
  fi
  
  sudo umount ${LSIM_TEMP_MOUNT} 2>/dev/null
  if [ "${VMDK_ERROR}" != "" ]; then
    echo -en '\n\E[37;41m'"\033[1m ERROR. Creating VMDK image '${VMDK_ERROR}'. \033[0m\n\n"
    echo -en "Error in '${0}'\n\n" >&2
    exit 1
  else
    echo -en "     Deleted loop devices\n"
  fi
}

##################################################################
# start the script
set +u
LSIM_IMAGE_SIZE="8096"
LSIM_FILE_NAME="gen3lsim"
LSIM_MOUNT_POINT= ${1} # the place of the currently created root file system
#LSIM_OUTPUT_DIR="/home/dus5cob/samba/views/dus5cob_AI_PRJ_CF3_BASE_SW_14.0F48.vws_GEN/ai_projects/generated/prj_download/lsim/gen3lsim.tar.bz2"  # the place where the vmdk file shall be created
LSIM_OUTPUT_DIR= ${2}   # the place where the vmdk file shall be created
LSIM_OUTPUT_DIR="${_SWBUILDROOT}/generated/prj_download/lsim/"  # the place where the vmdk file shall be created
set -u # break if a variable is empty when using

GetOptions $@

if [[ -z $LSIM_MOUNT_POINT || -z $LSIM_OUTPUT_DIR ]]; then
   echo "ERROR: Parameters required"
   Usage
   exit 1
fi

LSIM_ROOTFS_TARBALL="${1}/rfs.tar.bz2"
LSIM_TEMP_MOUNT=`mktemp -d --suffix=_${LSIM_FILE_NAME}`

LSIM_VMDK_TARBALL="${LSIM_OUTPUT_DIR}/${LSIM_FILE_NAME}.tar.bz2"
LSIM_VMDK_TARBALL_FILE="${LSIM_VMDK_TARBALL##*/}"
LSIM_VMDK_TARBALL_PATH="${LSIM_VMDK_TARBALL%/*}"
LSIM_HARDDISK_VMDK="${LSIM_VMDK_TARBALL_PATH}/${LSIM_VMDK_TARBALL_FILE%%.*}.vmdk"
LSIM_HARDDISK_IMAGE="${LSIM_VMDK_TARBALL_PATH}/${LSIM_VMDK_TARBALL_FILE%%.*}.img"

echo -en '\n\E[47;35m'"\033[1m Building VMDK image for GEN3 \033[0m\n\n"
echo "***********************************************************"
echo "   LSIM_IMAGE_SIZE        ${LSIM_IMAGE_SIZE}"
echo "   LSIM_TEMP_MOUNT         ${LSIM_TEMP_MOUNT}"
echo "   LSIM_MOUNT_POINT       ${LSIM_MOUNT_POINT}"
echo "   LSIM_HARDDISK_VMDK     ${LSIM_HARDDISK_VMDK}"
echo "   LSIM_VMDK_TARBALL      ${LSIM_VMDK_TARBALL}"
echo "   LSIM_HARDDISK_IMAGE    ${LSIM_HARDDISK_IMAGE}"
echo "   LSIM_FILE_NAME         ${LSIM_FILE_NAME}"
echo "***********************************************************"

#exit 0 # DEBUG
##################################################################
# check if the required data is available
# if [ -z ${LSIM_ROOTFS_TARBALL} ] && [ ! -e ${LSIM_ROOTFS_TARBALL}]; then
  # ErrorCreatingVMDKImage " Error: LSIM_ROOTFS_TARBALL '${LSIM_ROOTFS_TARBALL}' is wrong."
# fi

if [ -z ${LSIM_HARDDISK_VMDK} ]; then
  ErrorCreatingVMDKImage " Error: LSIM_HARDDISK_VMDK '${LSIM_HARDDISK_VMDK}' is wrong."
fi

##################################################################
# check if the required tools are avaialble (kpartx, grub, qemu-img)

if [ ! -e /sbin/kpartx ]; then
  ErrorCreatingVMDKImage "please install Kpartx: sudo apt-get install kpartx"
fi

if [ ! -e /sbin/parted ]; then
  ErrorCreatingVMDKImage "please install GNU Parted: sudo apt-get install parted"
fi

GRUB_VERSION=0
if [ ! -e /usr/sbin/grub ]; then
  GRUB_VERSION=1
fi

if [[ "*version 2*" = `dpkg -l | grep grub2-common` ]]; then
  GRUB_VERSION=2
fi

if [[ -z GRUB_VERSION ]]; then
	ErrorCreatingVMDKImage "please install Grub2: sudo apt-get install grub-pc"
fi

if [ ! -e /usr/bin/qemu-img ]; then
  ErrorCreatingVMDKImage "please install Qemu-utils: sudo apt-get install qemu-utils"
fi

# # Check if required files for building lsim harddisk are avaialabe
# if [ ! -f ${LSIM_ROOTFS_TARBALL} ]; then
  # ErrorCreatingVMDKImage "Please provide lsim tarball '${LSIM_ROOTFS_TARBALL}'"
# fi
##################################################################
# create all needed stuff and delete last try

if [ ! -d ${LSIM_MOUNT_POINT} ]; then
    ErrorCreatingVMDKImage "LSIM rootfs not available: Did you run prepare_lsim.pl ?"
    exit 1
fi

if [ ! -d ${LSIM_TEMP_MOUNT} ]; then
    mkdir -p ${LSIM_TEMP_MOUNT}
fi

echo -en '\n\E[44;33m'"\033[1m   Cleanup old files...\033[0m\n"
## this call unmounts the loop device(s)
ErrorCreatingVMDKImage ""

#exit 0

## Cleanup building for some reason failed before 
if [ -e ${LSIM_VMDK_TARBALL} ]; then
   rm -f ${LSIM_VMDK_TARBALL} 2>/dev/null
fi

if [ -e ${LSIM_HARDDISK_VMDK} ]; then
   rm -f ${LSIM_HARDDISK_VMDK} 2>/dev/null
fi

if [ -e ${LSIM_HARDDISK_IMAGE} ]; then
   rm -f ${LSIM_HARDDISK_IMAGE} 2>/dev/null
fi
##################################################################
# create raw disk image for lsim

echo -en '\n\E[44;33m'"\033[1m   Create Raw harddisk Image (This might take a while...)\033[0m\n"
if [[ ! -d ${LSIM_VMDK_TARBALL_PATH} ]]; then
  mkdir -p ${LSIM_VMDK_TARBALL_PATH}
fi

dd if=/dev/zero of=${LSIM_HARDDISK_IMAGE} bs=1M count=${LSIM_IMAGE_SIZE} 2>&1
#qemu-img create -f raw ${LSIM_HARDDISK_IMAGE} 8G
echo -en "     Set image as loopback device.\n"
LOOP_DEVICE=`sudo losetup --show -f ${LSIM_HARDDISK_IMAGE}`
if [[ $? -ne 0 ]]; then
  ErrorCreatingVMDKImage "no free loop device found!"
fi
LOOP_MAPPER_DEVICE=`echo ${LOOP_DEVICE} | sed 's|.*loop\([0-9]\).*|/dev/mapper/loop\1p1|'`

sleep 1

#read -s -n 1 -p "Press any key to continue..." KEY # DEBUG

if [ "$?" != 0 ]; then
  ErrorCreatingVMDKImage "Could not attach to ${LOOP_DEVICE}"
fi

##################################################################
# create partition in image

echo -en '\n\E[44;33m'"\033[1m   Partitioning harddisk Image \033[0m\n"

sudo fdisk ${LOOP_DEVICE} 2>&1 <<EOF
n
p
1


a
1
w
EOF

sleep 1
echo -en "     Attaching the partions to loopback device \n"
sudo kpartx -av ${LOOP_DEVICE}
sleep 1
#echo -en "     Listing partition table\n"
#sudo kpartx -lv ${LOOP_DEVICE}
#sleep 1
#echo -en "     Check partition with fdisk.\n"
#sudo fdisk -lu ${LOOP_DEVICE}
sleep 1

if [ "$?" != 0 ]; then
  ErrorCreatingVMDKImage "Partitioning failed"
fi

##################################################################
# format root partition

echo -en '\n\E[44;33m'"\033[1m   Formatting the root partition \033[0m\n"

sudo mkfs.ext4 ${LOOP_MAPPER_DEVICE}  2>&1
sleep 1

if [ "$?" != 0 ]; then
  ErrorCreatingVMDKImage "Formating failed"
fi

##################################################################
# mount root partition

echo -en '\n\E[44;33m'"\033[1m   Mount filesystem to '${LSIM_MOUNT_POINT}' \033[0m\n"

# Some magic to get the Beginning of the image in order to install grub2
IMG_OFFSET=`parted ${LSIM_HARDDISK_IMAGE} unit B print | tail -n2 | head -n1 | awk '{print $2}' | sed 's/.$//' `

sudo mount -o loop,rw,offset=${IMG_OFFSET} -t ext4 ${LSIM_HARDDISK_IMAGE} ${LSIM_TEMP_MOUNT}
#sudo mount -t ext4 ${LOOP_MAPPER_DEVICE} ${LSIM_TEMP_MOUNT}
# ##################################################################
# # copy files to lsim

echo -en '\n\E[44;33m'"\033[1m   Copying the lsim rootfs files (This might take a while...)\033[0m\n"

#sudo cp -aR ${LSIM_MOUNT_POINT}/* ${LSIM_TEMP_MOUNT}
tar xf ${LSIM_ROOTFS_TARBALL} -C ${LSIM_TEMP_MOUNT}
sleep 1

#read -s -n 1 -p "Press any key to continue..." KEY #DEBUG
#mount temprary rootfs
sudo umount ${LSIM_TEMP_MOUNT}

#Delete partition mappings
sudo kpartx -d ${LOOP_DEVICE}

#detach the file or device associated with the specified loop device
sudo losetup -d ${LOOP_DEVICE}

#set a disk image as a loopback device
sudo losetup ${LOOP_DEVICE} ${LSIM_HARDDISK_IMAGE}

#add partition mapping
sudo kpartx -a ${LOOP_DEVICE}

#Mount the tamp filesystem via loopback
#include<stdio.h>sudo mount ${LOOP_MAPPER_DEVICE} ${LSIM_TEMP_MOUNT}

#sudo cp /usr/lib/grub/i386-pc/stage1 /usr/lib/grub/i386-pc/stage2 ${LSIM_TEMP_MOUNT}/boot/grub/

#unmount temp rootfs
#sudo umount ${LSIM_TEMP_MOUNT}

#Delete partition mappings
#sudo kpartx -d ${LOOP_DEVICE}

#detach the file or device associated with the specified loop device
#sudo losetup -d ${LOOP_DEVICE}

if [ "$?" != 0 ]; then
  ErrorCreatingVMDKImage "Could not mount the partition"
fi

#sudo chown -v -R dus5cob:smbuser ${LSIM_TEMP_MOUNT}
##################################################################
# install grub to lsim

echo -en '\n\E[44;33m'"\033[1m   Installing grub \033[0m\n"

echo $GRUB_VERSION
if [[ $GRUB_VERSION == 0 ]]; then
  grub --batch --no-floppy --device-map=/dev/null <<EOF
device (hd0) ${LSIM_HARDDISK_IMAGE}
root (hd0,0)
setup (hd0)
quit
EOF

#Create a device map for grub
#echo '(hd0)      ${LOOP_DEVICE}' > ${LSIM_TEMP_MOUNT}/boot/grub/device.map

#Use grub2-install to actually install Grub. The options are:
#No floppy polling.
#Use the device map we generated in the previous step.
#Include the basic set of modules we need in the Grub image.
#Install grub into the filesystem at our loopback mountpoint.
#Install the MBR to the loopback device itself.

else # GRUB_VERSION == 2
  echo "GRUB_VERSION 2"
  sudo mount -o loop,rw,offset=${IMG_OFFSET} -t ext4 ${LSIM_HARDDISK_IMAGE} ${LSIM_TEMP_MOUNT}
  mkdir -p ${LSIM_TEMP_MOUNT}/boot/grub
  echo '(hd0)      ${LOOP_DEVICE}' > ${LSIM_TEMP_MOUNT}/boot/grub/device.map
  if [[ -e ${LSIM_TEMP_MOUNT}/boot/grub/menu.lst ]]; then
    sudo grub-menulst2cfg  ${LSIM_TEMP_MOUNT}/boot/grub/menu.lst ${LSIM_TEMP_MOUNT}/boot/grub/grub.cfg
  fi

  sudo grub-install --no-floppy --grub-mkdevicemap=${LSIM_TEMP_MOUNT}/boot/grub/device.map --boot-directory=${LSIM_TEMP_MOUNT}/boot --modules="ext2 part_msdos iso9660 search_fs_uuid normal multiboot loopback" ${LOOP_DEVICE}
fi

if [ "$?" -ne 0 ]; then
  ErrorCreatingVMDKImage "Failed to install grub"
fi

##################################################################
# stop loop devices and lsim filesystem mount

sleep 1
echo -en '\n\E[44;33m'"\033[1m   Unmount '${LSIM_TEMP_MOUNT}' \033[0m\n"
#sleep 30
ls ${LSIM_TEMP_MOUNT}/boot/grub/
sudo umount ${LSIM_TEMP_MOUNT}
sleep 1
mount

if [ -e "${LSIM_TEMP_MOUNT}/etc/issue" ]; then
  echo -en '\n\E[44;33m'"\033[1m   Please close all windows with '${LSIM_TEMP_MOUNT}' \033[0m\n"
  echo -en '\n\E[44;33m'"\033[1m     Press a key when you are ready. \033[0m\n"
  read -sn1
  sudo umount -f ${LSIM_TEMP_MOUNT}
fi

echo -en '\n\E[44;33m'"\033[1m Resizing of the device. \033[0m\n"
#sudo fsck.ext4 -f -y ${LOOP_MAPPER_DEVICE} 2>&1
#sudo resize2fs ${LOOP_MAPPER_DEVICE} 2>&1

# create vmdk image

echo -en '\n\E[44;33m'"\033[1m   Creating vmdk image '${LSIM_HARDDISK_VMDK}' (This might take a while...)\033[0m\n"

qemu-img convert -o compat6 -f raw ${LSIM_HARDDISK_IMAGE} -O vmdk ${LSIM_HARDDISK_VMDK}

if [ "$?" != 0 ]; then
  ErrorCreatingVMDKImage "Converting raw to vmdk image failed"
fi

echo -en '\n\E[44;33m'"\033[1m   Compressing vmdk image '${LSIM_HARDDISK_VMDK}' to tarball '${LSIM_VMDK_TARBALL}' \033[0m\n"
cd ${LSIM_VMDK_TARBALL_PATH} > /dev/null 2>&1
tar cjf ${LSIM_VMDK_TARBALL} ${LSIM_HARDDISK_VMDK##*/}
if [ "$?" != 0 ]; then
  ErrorCreatingVMDKImage "Compressing vmdk image failed"
else
  echo "enter the window full path where you want to copy the created vmdk image : "
  read VMDKFULLPATH
  echo $VMDKFULLPATH
  cp ${LSIM_VMDK_TARBALL} $VMDKFULLPATH
fi
# Cleanup

sudo chown -R --reference=${LSIM_MOUNT_POINT} $(dirname $LSIM_VMDK_TARBALL_PATH)
sudo chmod -R ugo+rw $(dirname $LSIM_VMDK_TARBALL_PATH)

# remove prj and lsim 
ErrorCreatingVMDKImage ""
rm -rf ${LSIM_HARDDISK_VMDK} 2>/dev/null
rm -rf ${LSIM_HARDDISK_IMAGE} 2>/dev/null
rm -rf ${LSIM_TEMP_MOUNT} 2>/dev/null


##################################################################
# build vmdk image done

cd ${CURRENT_DIR}
echo -en '\n\E[47;35m'"\033[1m DONE. Building VMDK image in '${LSIM_VMDK_TARBALL}' \033[0m\n\n"
exit 0
