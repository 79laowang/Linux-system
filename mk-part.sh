#!/usr/bin/env bash
# -*- coding:utf-8 -*-
#-------------------------------------------------------------------------------
# File Name:   mk-part.sh
# Purpose:     Create a disk with specified parameter
#
# Author:      Ke Wang
#
# Created:     2019-11-21
# Copyright:   (c) Ke Wang 2019
# Licence:     <your licence>
#-------------------------------------------------------------------------------

mk_part() {
  local disk="$1" part_start="$2" part_end="$3"
  part_type=$(get_part_type "$disk")
  if [ "$part_type" == "MBR" ];then
    if parted "$disk" p | grep 'extended' ; then
      # Max logical partitions is 12 totally
      parted -s "$disk" mkpart logic "$part_start $part_end"
    else
      pri_part_num=$(parted "$disk" p | grep 'primary' | wc -l)
      if [ $pri_part_num -le 3 ];then
        if [ "$part_end" == "100%" ];then
          parted -s "$disk" mkpart primary "$part_start $part_end"
        else
          if [ $pri_part_num -eq 3 ];then # create extend part
            parted -s "$disk" mkpart extended "$part_start 100%"
            parted -s "$disk" mkpart logic "$part_start $part_end"
          else
            parted -s "$disk" mkpart primary "$part_start $part_end"
          fi
        fi
      fi
    fi
  else # GTP partition table
    parted -s "$disk" mkpart primary "$part_start $part_end"
  fi
}

get_rootdisk(){
  # Traditional root disk partition
  if echo "$rootdev" | grep "/dev/[hvs]d[a-z]" 2>&1 >/dev/null ; then
    rootdisk=`echo "$rootdev" | sed 's/[0-9]*//g'`
  elif echo "$rootdev" | grep "/dev/nvme" 2>&1 >/dev/null ; then
    rootdisk=`echo "$rootdev" | sed 's/p[0-9]//g'`
  else # LVM root volume
    rootdisk=`lvdisplay -am "$rootdev" | grep 'Physical volume' | awk '{print $3}' | sed 's/[0-9]*//g'`
  fi
  echo "$rootdisk"
}

get_part_type(){
  local disk="$1" part_type="MBR"
  part_table=`parted "$disk" p | grep 'Partition Table:' | awk '{print $3}'`
  if [ "X$part_table"  == "Xmsdos" ];then
    part_type="MBR"
  elif [ "X$part_table"  == "Xgpt" ];then
    part_type="GPT"
  else
    # Unknown partition, force to make gpt label
    parted "$disk" mklabel gpt
    part_type="GPT"
  fi
  echo "$part_type"
}

#
# Get the difference of the two arrays
# Usage: diff_array=($(diff_array arr_pre_parts[@] arr_post_parts[@]))
# echo "diff_array:${new_part[@]}"
#
diff_array(){
  awk 'BEGIN{RS=ORS=" "}
       {NR==FNR?a[$0]++:a[$0]--}
       END{for(k in a)if(a[k])print k}' <(echo -n "${!1}") <(echo -n "${!2}")
}

remove_part(){
 for lv in `lvdisplay | grep 'LV Path' | awk '{print $3}' | tr '\n' " "`; do lvremove $lv ;done
 for vg in `vgdisplay | grep 'VG Name' | awk '{print $3}' | tr '\n' " "`; do vgremove $vg ;done
 for pv in `pvdisplay | grep 'PV Name' | awk '{print $3}' | tr '\n' " "`; do pvremove $pv ;done
 for pt in `parted /dev/sda p | grep logical$ | awk '{print $1}' | tr '\n' " " | rev` ; do parted /dev/sda rm $pt;done
 for pt in `parted /dev/sda p | grep extended | awk '{print $1}'`; do parted /dev/sda rm $pt;done
}

get_free_space(){
  local disk="$1" unit="$2"
  [ "X$unit" == "X" ] && unit="GB"
  parted "$disk" unit "$unit" p free | grep 'Free Space' | tail -n 1
}

get_parts(){
  disk_name=`echo $disk | sed 's/\/dev\///g'`
  disks=`cat /proc/partitions |  grep "$disk_name" | awk '{print "/dev/"$4}'`
  echo "$disks"
}

get_new_part(){
  if [ "$part_type" == "MBR" ];then
    post_parts=$(get_parts)
    arr_post_parts=($post_parts)
    if [ ${#arr_pre_parts[@]} -ge 1 ];then # Not new disk
      new_part=($(diff_array arr_pre_parts[@] arr_post_parts[@]))
      parted "$disk" p | grep extended
      # First create extend partition
      if [ $? -eq 0 -a ${#new_part[@]} -gt 1 ] ; then
        ext_partid=`parted "$disk" p | grep extended | awk '{print $1}'`
        ext_part=`echo ${disk}${ext_partid}`
        # Only keep the logic part for new parts, not including extend part
	        if echo ${new_part[@]} | grep "$ext_part" ;then
	          new_part=`echo ${new_part[@]} | cut -d" " -f2`
	        fi
	      fi
	    else
	      new_part=($post_parts)
	    fi
	  else
	    post_parts=$(get_parts)
	    if [ ${#arr_pre_parts[@]} -ge 1 ];then  #Not new disk
	      arr_post_parts=($post_parts)
	      new_part=($(diff_array arr_pre_parts[@] arr_post_parts[@]))
	    else
	      new_part=($post_parts)
	    fi
	  fi
	}

	mount_part(){
	  case $part_fs_type in
	      ext4|ext3|ext2)
	        force_opt="-F"
	      ;;
	      xfs|btrfs)
	        force_opt="-f"
	      ;;
	      vfat|fat|msdos)
	        force_opt="-I"
	      ;;
	      *)
	        force_opt=""
	      ;;
	  esac

	  if [ $USE_LVM -eq 1 ];then
	    pvcreate -f $new_part
	    if [ $? -ne 0 ]; then
	      echo "Failed to create PV $new_part !"
	      exit 1
	    fi
	    vgcreate "vg_$part_name" $new_part
	    if [ $? -ne 0 ]; then
	      echo "Failed to create VG vg_$part_name !"
	      exit 1
	    fi
	    lvcreate -l +100%FREE "vg_$part_name" -n "lv_$part_name"
	    if lvscan | grep "lv_$part_name" ; then
	      part_dev="/dev/mapper/vg_$part_name-lv_$part_name"
	    else
	      echo "Failed to create logic volume lv_$part_name"
	      exit 1
	    fi
	  else # traditional disk
	    part_dev="$new_part"
	  fi
	  # If file system remained new partition
	  if blkid | grep "$part_dev"  | grep 'TYPE' ;then
	    mkfs.${part_fs_type} $force_opt $part_dev
	  else
	    mkfs.${part_fs_type} $part_dev
	  fi
	  part_dev_UUID=`blkid | grep "$part_dev" | awk '{print $2}'`
	  echo "$part_dev_UUID  $part_path        $part_fs_type         defaults        0 0" >> /etc/fstab
	  mount $part_dev  "$part_path"
	}

	mk_traditional_part(){
	  if [ "$part_size" == "100%" ];then
	    part_start=$(get_free_space "$disk" | awk '{print $1}')
	    mk_part "$disk" "$part_start" "$part_size"
	  else
	    input_unit=$(echo "$part_size" |  grep -Eo '[K|M|G|T]')
	    part_size_num=$(echo "$part_size" |  grep -Eo '^[0-9]+')
	    case $input_unit in
	               K)
	                 part_unit="MB"
	                 part_size_num=$[part_size_num/1000]
	               ;;
	               M)
	                 part_unit="MB"
	               ;;
	               G)
	                 part_unit="GB"
	               ;;
	               T)
	                 part_unit="TB"
	               ;;
	               *)
	                 echo "Invalid partition size unit $part_unit !"
	                 exit 1
	               ;;
	    esac

	    part_start=$(get_free_space "$disk" "$part_unit"| awk '{print $1}')
	    part_start_num=$(echo "$part_start" | sed "s/$part_unit//g")
	    part_end=$(get_free_space "$disk" "$part_unit" | awk '{print $2}')
	    part_end_num=$(echo "$part_end" | sed "s/$part_unit//g")
	    part_end_new=`echo "$part_start_num + $part_size_num" | bc`
	    if [ $(echo "$part_end_new < $part_end_num" | bc) -ne 0 ];then
	      mk_part "$disk" "$part_start" "${part_end_new}$part_unit"
	    else
	      echo "Not enough disk space, Remained disk space:$free_space !"
	      exit 1
	    fi
	  fi
	}

	usage(){
	  echo "Usage: $0 [-d disk name] [-p part name] [-s <part size>] [-t <part fs type>]] [-u Not mount part] [-v Using traditional disk]"
	  echo  'Default- part name:systest, part size: part size with unit(G,M,K), part fs type:xfs'
	  echo  "$0 -d /dev/sda -p systest -s 100G -t xfs -u -v"
	  printf "\n"
	  exit 1
	}

	# ---- Main -----
	DEF_PART_NAME="systest"
	DEF_PART_SIZE="100%"
	DEF_PART_FS_TYPE="xfs"
	IS_MOUNT=1
	USE_LVM=1
	PART_DATA=".partinfo"

	while (($# != 0)) ; do
	  case $1 in
	          -d)
	            shift
	            [ $# = 0 ] && usage
	            disk="$1"
	          ;;
	          -p)
	            shift
	            [ $# = 0 ] && usage
	            part_name=${1:-$DEF_PART_NAME}
	          ;;
	          -s)
	            shift
	            [ $# = 0 ] && usage
	            part_size=${1:-$DEF_PART_SIZE}
	          ;;
	          -t)
	            shift
	            [ $# = 0 ] && usage
	            part_fs_type=${1:-$DEF_PART_FS_TYPE}
	          ;;
	          -c)
	            remove_part
	          ;;
	          -u)
	            IS_MOUNT=0
	          ;;
	          -v)
	            USE_LVM=0
	          ;;
	          *|-h|-help|--help)
	            usage
	          ;;
	  esac
	  shift
	done
	part_name=${part_name:-$DEF_PART_NAME}
	part_size=${part_size:-$DEF_PART_SIZE}
	part_size_num=`echo $part_size | sed 's/[Gg]\|[GB|gb]//g'`
	part_fs_type=${part_fs_type:-$DEF_PART_FS_TYPE}

	if [ $IS_MOUNT -eq 1 ]; then
	  if mount |grep -w "$part_name" ; then
	    echo "The new created partition $part_name already existed!"
	    exit 1
	  fi
	fi

	if [ "X$disk" == "X" ];then
	  rootdev=`df -hT | grep /$ | awk '{print $1}'`
	  disk=$(get_rootdisk)
	fi
	part_type=$(get_part_type "$disk")
	if [ "$part_type" == "unknown" ];then
	  echo "Unknown disk label, please specify one!"
	  exit 1
	fi

	free_space=$(get_free_space "$disk" | awk '{print $3}')
	free_space_size=`echo $free_space | sed 's/[Gg]\|[GB|gb]//g'`
	if [ "$free_space_size" == "0.00" ];then
	  echo "$free_space_size space is available!"
	  exit 1
	fi

	# Only the free space is greater than 10Gb, create new
	if [ `echo "$free_space_size <= 10.00" | bc` -eq 1 ];then
	  echo "Less remained free space $free_space for use!"
	  exit 1
	fi

	if [ `echo "$part_size_num >= $free_space_size" | bc` -eq 1 ];then
	  part_size='100%'
	  echo "Warning: No enough space, using less remained free space $free_space for new partition!"
	fi

	pre_parts=$(get_parts)
	arr_pre_parts=($pre_parts)
	mk_traditional_part
	get_new_part
	echo "New partition:${new_part}"
	if [ "X${new_part}" != "X" ];then
	  if [ $IS_MOUNT -eq 1 ];then
	    part_path="/${part_name}"
	    [ -d "$part_path" ] || mkdir "$part_path"
	    mount_part
	  fi
	fi
