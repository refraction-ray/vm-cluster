VM-CLUSTER
=========


## Quick Start

```bash
$ git clone https://github.com/refraction-ray/vm-cluster.git
$ cd vm-cluster
# after editing vars_default.sh
$ sudo ./vm-cluster cluster-up # build up a VM cluster
# now you can ssh into VMs, and play around
$ sudo ./vm-cluster nodes-add 3 4 # add the third and fourth VM as compute nodes to the cluster
$ sudo ./vm-cluster cluster-down # tear down the whole VM cluster
```

## Prerequisite

You should have a host Linux machine with KVM module enabled. You should also have some packages installed.  For Ubuntu, you can `apt install qemu-kvm libvirt-bin virtinst ansible`.

## How does it work

The bash script makes use of virsh interface to provision KVM based VMs and utilizes ansible playbooks to further configure the cluster. 

In the first provision phase, we use the official Ubuntu cloud image and also make .iso file to provide data for cloud init within VM.

In the second configuration phase, we apply several ansible-playbooks on VM, and build a full featured HPC cluster with well configured slurm work load manager.

## How to customize

The first place you have to go is `vars_default.sh`. Here you can edit the variables, specifically, you must specify a pair of ssh keys, public key string as variable `sshkey`, absolute path of secret key file as variable `keyfile`. You can only ssh into VMs, after you properly configured ssh key pairs at the beginning. The default ip for the master VM node is `192.168.100.100`, which can be tuned by `ip24` for a different ip prefix.

Furthermore, if you want to have finer control on the configuration of VM, you can customize ansible roles by hand and even change the template files in `bootstrap`. You may particularly be interested in `slurm.conf` in `bootstrap/roles/slurm/template/`.


## How universal is the script

Only tested on the combination of KVM based VM, Ubuntu OS and bash for host. And ansible playbooks are specially designed for Ubuntu18.04 on VM side.
I have no intention to make the script more robust or platform agnostic.  But PRs on this are welcome.
