#!/bin/bash

# ANSI escape codes for colored output
YELLOW=$(tput setaf 3)
GREEN=$(tput setaf 2)
NC=$(tput sgr0) # No Color

echo -e "${YELLOW}Enter the desired hostname:${NC}"
read new_hostname

echo -e "${GREEN}Setting hostname to '$new_hostname'...${NC}"
sudo hostnamectl set-hostname $new_hostname

echo -e "${GREEN}Array to store IP addresses and hostnames${NC}"
declare -A hosts_array

read -p "Enter the number of hosts to add: " num_hosts

if ! [[ $num_hosts =~ ^[0-9]+$ ]]; then
    echo -e "${YELLOW}Invalid input. Please enter a valid number.${NC}"
    exit 1  # Exit the script with an error code
fi

for ((i=1; i<=num_hosts; i++))
do
    read -p "Enter the IP address for host $i: " ip_address
    read -p "Enter the hostname for host $i (master/worker): " hostname

    if [[ $hostname == *master* || $hostname == *worker* ]]; then
        hosts_array[$ip_address]=$hostname
    else
        echo -e "${YELLOW}Hostname must include 'master' or 'worker'. Skipping this input.${NC}"
        exit 1  # Exit the script with an error code
    fi

    if [[ $hostname == *master1* ]]; then
        master1_ip=$ip_address
    fi
done

echo -e "${GREEN}Adding hosts to /etc/hosts...${NC}"
for ip in "${!hosts_array[@]}"; do
    echo "$ip ${hosts_array[$ip]}" >> /etc/hosts
done

echo -e "${GREEN}Automatically assigning the value of master1_ip${NC}"
echo "${GREEN}master1 IP: $master1_ip${NC}"

echo -e "${GREEN}Common setup steps for both master and worker nodes${NC}"

echo -e "${YELLOW}Installing necessary packages and tools...${NC}"
yum install -y yum-utils device-mapper-persistent-data lvm2

echo -e "${GREEN}Adding Docker repository...${NC}"
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

echo -e "${GREEN}Installing Docker...${NC}"
yum install -y docker-ce

echo -e "${GREEN}Enabling and starting Docker service...${NC}"
systemctl enable docker && systemctl start docker

echo -e "${GREEN}Temporarily disabling SELinux...${NC}"
setenforce 0

echo -e "${GREEN}Updating SELinux permanently...${NC}"
sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config

echo -e "${GREEN}Updating network settings...${NC}"
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

echo -e "${GREEN}Disabling and stopping firewalld service...${NC}"
systemctl mask --now firewalld

echo -e "${GREEN}Disabling swap...${NC}"
swapoff -a
echo 0 > /proc/sys/vm/swappiness

echo -e "${GREEN}Commenting out the swap line in /etc/fstab...${NC}"
sed -e '/swap/ s/^#*/#/' -i /etc/fstab

echo "${GREEN}Configuring Kubernetes repository...${NC}"
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF

echo "${GREEN}Installing Kubernetes packages...${NC}"
yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

echo "${GREEN}Enabling and starting Kubelet service...${NC}"
systemctl enable kubelet && systemctl start kubelet

echo "${GREEN}Checking containerd service status and deleting configuration file...${NC}"
systemctl status containerd
rm -f /etc/containerd/config.toml

echo "${GREEN}Restarting containerd service...${NC}"
systemctl restart containerd

echo -e "${YELLOW}Is this a master or worker node? (master/worker)${NC}"
read node_type

if [[ $node_type == "master" ]]; then
    echo -e "${YELLOW}Installing HAProxy? (yes/no)${NC}"
    read install_haproxy_choice

    if [ "$install_haproxy_choice" = "yes" ]; then
        echo -e "${GREEN}Installing HAProxy${NC}"
        yum -y install haproxy

        echo -e "${GREEN}Adding configuration to haproxy.cfg${NC}"
        cat <<EOF >> /etc/haproxy/haproxy.cfg
frontend kubernetes-master-lb
bind 0.0.0.0:26443
option tcplog
mode tcp
default_backend kubernetes-master-nodes

backend kubernetes-master-nodes
mode tcp
balance roundrobin
option tcp-check
option tcplog
EOF

        for ip in "${!hosts_array[@]}"; do
            if [[ ${hosts_array[$ip]} == *master* ]]; then
                echo "server ${hosts_array[$ip]} $ip:6443 check" >> /etc/haproxy/haproxy.cfg
            fi
        done

        echo -e "${GREEN}Restart and enable HAProxy${NC}"
        systemctl restart haproxy && systemctl enable haproxy

        echo -e "${GREEN}Check HAProxy status${NC}"
        systemctl status haproxy

        echo -e "${GREEN}Check port 26443${NC}"
        netstat -nltp | grep 26443
    else
        echo -e "${YELLOW}Skipping HAProxy installation.${NC}"
    fi

if [[ $node_type == "master" ]]; then
    echo -e "${YELLOW}Enter the IP address for master1:${NC}"
    read master1_ip

    kubeadm init --control-plane-endpoint "$master1_ip:26443" \
      --upload-certs \
      --pod-network-cidr "10.244.0.0/16"

    echo "${GREEN}Copying admin.conf to user's .kube directory...${NC}"
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config

elif [[ $node_type == "worker" ]]; then
    # Worker node setup steps

    echo "${YELLOW}Enter the kubeadm join command for this worker node:${NC}"
    read kubeadm_join_command

    # Execute the kubeadm join command
    $kubeadm_join_command

    echo -e "${GREEN}Worker node setup completed.${NC}"
else
    echo -e "${YELLOW}Invalid node type. Please select 'master' or 'worker'.${NC}"
    exit 1
fi

 echo "${GREEN}Deploying and enabling Flannel network plugin...${NC}"
 kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

elif [[ $node_type == "worker" ]]; then
    # Worker node setup steps

    echo -e "${GREEN}Worker node setup completed.${NC}"
else
    echo -e "${YELLOW}Invalid node type. Please select 'master' or 'worker'.${NC}"
    exit 1
fi

echo -e "${YELLOW}Do you want to reboot the system? (yes/no)${NC}"
read reboot_choice

if [ "$reboot_choice" = "yes" ]; then
    echo -e "${YELLOW}Rebooting the system...${NC}"
    reboot
else
    echo -e "${GREEN}Script execution completed.${NC}"
fi