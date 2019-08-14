#!/bin/bash

if [ ! -z ${VM_CLUSTER_DEBUG} ];then
    debuglevel=1
fi
if [ -z ${VM_CLUSTER_CONF} ]; then
    dir=$(pwd)
else
    dir=${VM_CLUSTER_CONF}
fi

source $dir/vars_default.sh

debug(){
if [ ${debuglevel} == 1 ]; then
    echo "debug info: ${1}"
fi
}

prepare_bridge(){
ip link add name $1 type bridge
ip link set $1 up
ip addr add ${ip24}.1/24 dev $1
debug "finish setting up bridge ${1} on host"
}

download_image(){
curl -o ${dir}/os.img $imageurl
}

prepare_dir(){
mkdir -p ${dir}/${1}

cat << END > ${dir}/${1}/meta-data
instance-id: $1
local-hostname: $1
END

cat << END > ${dir}/${1}/user-data
#cloud-config
users:
- name: ${muser}
  groups: sudo
  shell: /bin/bash
  ssh_authorized_keys:
  - ${sshkey}
  sudo:  ALL=(ALL) NOPASSWD:ALL
END

cp ${dir}/os.img ${dir}/${1}/os.qcow2

genisoimage -o ${dir}/${1}/config.iso -V cidata -r -J ${dir}/${1}/meta-data ${dir}/${1}/user-data
}

install_vm(){
if [ $1 == 0 ]; then
    networkopt="--network network=default,mac=${macwan}" 
    #master should has nat connection to the internet
    specopt="-r 512" 
    #I have no attention to generalize the hardware spec settings, but you could hack there
    resizeopt="+6G"
else
    networkopt=""
    specopt="-r 512"
    resizeopt="+2G"
fi

qemu-img resize ${dir}/${vmprefix}${1}/os.qcow2 $resizeopt

virt-install -n ${vmprefix}$1 $specopt --disk ${dir}/${vmprefix}${1}/os.qcow2 --import --disk path=${dir}/${vmprefix}${1}/config.iso,device=cdrom $networkopt  --network bridge=$br,mac=${macprefix}:$(printf "%02x" $1) --noautoconsole
}

ansible_init(){
slurmdbpass="bigbrowatchu"
userpass="123456"

cat << END > ${dir}/bootstrap/roles/slurm/defaults/main.yml
---
# defaults file for slurm
db_user: slurm
slurm_user: ${muser}
db_pass: ${slurmdbpass}
END

cat << END > ${dir}/bootstrap/roles/user/defaults/main.yml
---
# defaults file for user
users:
  - name: "${muser}"
    uid: 1000
    password: "${userpass}"
END

cat << END > ${dir}/bootstrap/group_vars/all.yml
ansible_python_interpreter: "/usr/bin/python3"
timezone: "Asia/Shanghai"
admin: ${muser}
netmask: 255.255.255.0
mask: 24
ip_range: ${ip24}.0
ntp_server: ntp.tuna.tsinghua.edu.cn
wan_mask: 24
master_ip: ${ip24}.100
master_name: ${vmprefix}0
dhcp_start_ip: ${ip24}.20
dhcp_end_ip: ${ip24}.90
dns_server:
  - 166.111.8.28
cluster_domain: hpc.cluster
cluster_name: hpc
#wan_ip
#wan_gateway
END

for i in $(seq 1 ${nocn})
do
cat << END > ${dir}/bootstrap/host_vars/${vmprefix}${i}.yml
ip: ${ip24}.1$(printf "%02d" ${i})
mac: ${macprefix}:$(printf "%02x" ${i})
END
done
}

add_cns(){
for i in $@
do
    exist=$(virsh list --all|grep ${vmprefix}${i}|wc -l)
    if [ $exist -gt 0 ]; then
        echo "compute node instance ${vmprefix}${i} already exists, exiting"
        exit 1
    fi
done

ansible_bootstrap_pre $@
for i in $@
do
    prepare_dir ${vmprefix}${i}
    install_vm ${i}
done

ansible_bootstrap_post $@
}

ansible_bootstrap_head(){
wanip=
while [ -z "$wanip" ]; do
    sleep 10
    wanip=$(virsh net-dhcp-leases default|grep "${macwan}"|tail -n1|awk '{print $5}'|awk -F/ '{print $1}')
done

cat << END > ${dir}/bootstrap/hosts
[ln]
${vmprefix}0 ansible_ssh_host=${wanip} ansible_ssh_user=${muser} ansible_sudo_pass=
[cn]
END
for i in $(seq 1 ${nocn})
do
    echo "${vmprefix}${i} ansible_ssh_host=${ip24}.1$(printf "%02d" ${i}) ansible_ssh_user=${muser} ansible_sudo_pass=" >> ${dir}/bootstrap/hosts
done

echo "wan_ip: ${wanip}" >> ${dir}/bootstrap/group_vars/all.yml
echo "wan_gateway: $(echo $wanip|awk -F "." '{print $1"."$2"."$3"."1}')" >> ${dir}/bootstrap/group_vars/all.yml

while [  $(nc -zv $wanip 22 2>&1|grep succeeded|wc -l) == 0 ]; do
    sleep 10
done
sleep 20

cd ${dir}/bootstrap && $ansibleplaybook -i ${dir}/bootstrap/hosts ${dir}/bootstrap/site.yml --key-file "${keyfile}"
}

ansible_bootstrap_pre(){
beyond=0
for i in $@
do
    if [ $i -gt ${nocn} ]; then
        echo "${vmprefix}${i} ansible_ssh_host=${ip24}.1$(printf "%02d" ${i}) ansible_ssh_user=${muser} ansible_sudo_pass=" >>${dir}/bootstrap/hosts
    cat << END > ${dir}/bootstrap/host_vars/${vmprefix}${i}.yml
ip: ${ip24}.1$(printf "%02d" ${i})
mac: ${macprefix}:$(printf "%02x" ${i}) 
END
    beyond=1
    fi
done
if [ ${beyond} == 1 ]; then
    cd ${dir}/bootstrap && $ansibleplaybook -i ${dir}/bootstrap/hosts -l ln ${dir}/bootstrap/site.yml --key-file "${keyfile}"
fi
}

ansible_bootstrap_post(){
for i in $@; do
    while [ $(nc -zv ${ip24}.1$(printf "%02d" $i ) 22 2>&1|grep succeeded|wc -l) == 0  ];do
        sleep 5
    done
done

sleep 15

cd ${dir}/bootstrap && $ansibleplaybook -i ${dir}/bootstrap/hosts ${dir}/bootstrap/site.yml --key-file "${keyfile}"
}

check_command(){
if [ $(which ${1}|wc -l) == 0 ]; then
    echo "${1} is not installed in the host system, exiting..."
    exit 2
fi
}

check(){
check_command $ansibleplaybook
check_command curl
check_command virsh
check_command virt-install
check_command qemu-img
check_command ip
check_command genisoimage

exist_br=$(ip link show|grep ${br}|wc -l)
if [ $mkbr == 1 ] && [ ${exist_br} -gt 0 ]; then
    echo "the bridge $br already exists and you insist on creating it, exiting..."
    exit 1 
fi
exist_ln=$(virsh list --all|grep ln0|wc -l)
if [ ${exist_ln} -gt 0 ]; then
    echo "head node ln0 already exists, exiting..."
    exit 1
fi
exist_img=$(ls ${dir}|grep os.img|wc -l)
if [ ${download} == 0 ] && [ ${exist_img} == 0 ]; then
    echo "You turned off download image, but we cannot find os.img in ${dir}, exiting..."
    exit 1
fi
if [ ! -d "${dir}/bootstrap" ]; then
    echo "Bootstrap folder hosting ansible playbooks not exsist in ${dir}, exiting..."
    exit 1
fi
}

cluster_spin_up(){
check

if [ $download == 1 ];then
    download_image
fi
prepare_dir ${vmprefix}0
if [ $mkbr == 1 ];then
    prepare_bridge $br
fi
install_vm 0
ansible_init
ansible_bootstrap_head
add_cns $(seq 1 $nocn)
}

cluster_tear_down(){
vmlist=($(virsh list --all|grep "${vmprefix}"|awk '{print $2}'))

for i in ${vmlist[@]}
do
    virsh destroy $i
    virsh undefine $i
    rm -r ${dir}/$i
done

ip link del $br
debug "finish cluster ${vmprefix} teardown"
}


if [ "$1" == "cluster-up" ]; then
    cluster_spin_up
elif [ "$1" == "cluster-down" ]; then
    cluster_tear_down
elif [ "$1" == "nodes-add" ]; then
    add_cns ${@:2}
else
    echo "unrecognized action, exiting..."
    exit 4
fi
