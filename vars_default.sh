#!/bin/bash

ip24="192.168.100"
#imageurl="https://cloud-images.ubuntu.com/releases/18.04/release-20190722.1/ubuntu-18.04-server-cloudimg-amd64.img"
imageurl="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cloud-images/bionic/20190731/bionic-server-cloudimg-amd64.img"
#this is designed for users in China which has terrible network speed to ubuntu.com, use the official link above if you have no network issues
download=1 #otherwise you need prepare your own cloud image in the working folder with name os.img
nocn=1 #number of compute nodes instance
muser=ubuntu #main sudo user of the cluster: id1000
br="mybr1" # bridge interface name in host
mkbr=1 #otherwise you need to setup the bridge on host with ip ip24.1 by your self
vmprefix="cn" #the VM name in the cluster will be cn0, cn1...
ansibleplaybook="/usr/bin/ansible-playbook"
macprefix="52:54:00:aa:aa"
macwan="52:54:00:aa:bb:cc"
keyfile= #secret key file path
sshkey= #pub key string 

if [ -f ${dir}/vars.sh ]; then
    source ${dir}/vars.sh
fi
