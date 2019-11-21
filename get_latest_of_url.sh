#!/bin/bash
#pkgs_prefix='qemu-common-2.11'                                                                                                                                          
cd getPackage                                                                                                                                                            
for pkg in `echo $pkgs_prefix`; do                                                                                                                                       
  latest_pkg=`curl -s http://server/auto-build/oraclecloud/ol7/x86_64/ | sed -n "s/.*\($pkg.*\.rpm\).*/\1/p" | sort | tail -1`                       
  if [ "X$latest_pkg"  != "X" ];then                                                                                                                                     
    if ! ls $latest_pkg 2>/dev/null; then # If not found in local, download it                                                                                           
      echo "Downloading $latest_pkg ..."                                                                                                                                 
      wget  http://server/auto-build/oraclecloud/ol7/x86_64/$latest_pkg                                                                              
    fi                                                                                                                                                                   
  fi                                                                                                                                                                     
done
