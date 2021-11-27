#!/bin/bash

for ((i=0;i<=15;i++)); do 
	echo -ne "Creating lv minio$i\n"
	lvcreate -L 1G -n minio$i ubuntu-vg
	mkfs.xfs /dev/ubuntu-vg/minio$i
	mkdir -p /data/minio$i
	echo "/dev/mapper/ubuntu--vg-minio$i /data/minio$i xfs defaults 0 1" >> /etc/fstab
done

mount -a