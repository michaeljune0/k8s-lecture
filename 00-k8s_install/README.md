# Kubernetes Cluster Setup Script

## Overview

This script automates the setup of a Kubernetes cluster on CentOS-based systems. It guides you through the process of configuring hostnames, IP addresses, installing necessary packages, setting up Docker, Kubernetes, and more.

## Usage

1. **Run the Script:**

    Open a terminal and navigate to the directory where the script is located. Run the following command to start the script:

    ```bash
    bash k8s_master_worker_install_v0.3_host_choice.sh
    ```

2. **Hostname Configuration:**

    Enter the desired hostname for the current node. The script will set the hostname using the `hostnamectl` command.

3. **IP and Hostname Configuration for Nodes:**

    - Enter the number of hosts you want to add to the cluster. This includes both master and worker nodes.

    - For each host, provide the following information:
        - IP address: The IP address of the host.
        - Hostname: Specify whether the host is a "master" or "worker". The hostname must include either "master" or "worker".

    The script will use this information to update the `/etc/hosts` file, ensuring proper name resolution within the cluster.

4. **Common Setup Steps for Both Master and Worker Nodes:**

    The script will perform the following common setup steps for both master and worker nodes:

    - Install necessary packages and tools.
    - Add the Docker repository and install Docker.
    - Enable and start the Docker service.
    - Temporarily disable SELinux and update SELinux settings permanently.
    - Update network settings to enable bridge networking.
    - Disable and stop the `firewalld` service.
    - Disable swap and update the `/etc/fstab` file to comment out the swap entry.

5. **Master or Worker Node Configuration:**

    - Specify whether the current node is a master or worker by typing "master" or "worker" when prompted.

    If the node is a master:

    - Optionally, install HAProxy for load balancing by typing "yes" or "no" when prompted.

    - If you choose to install HAProxy, the script will:
        - Install HAProxy using `yum`.
        - Configure HAProxy's `haproxy.cfg` file to set up load balancing for the Kubernetes API servers.
        - Restart and enable the HAProxy service.
        - Check the HAProxy status and port 26443 status using `systemctl` and `netstat`.

    - Enter the IP address for the first master node (master1) to initialize the Kubernetes control plane using `kubeadm`.
    - The script will upload the certificates and configure the pod network CIDR.
    - Copy `admin.conf` to the user's `.kube` directory for `kubectl` access.

    If the node is a worker:

    - Enter the `kubeadm join` command for this worker node. This command was generated during the master node setup. The command should look like:

    ```bash
    kubeadm join --token <token> <master-ip>:<master-port>
    ```

    The script will execute the `kubeadm join` command to add the worker node to the cluster.

6. **Deploying and Enabling Flannel Network Plugin:**

    The script will deploy the Flannel network plugin using the `kubectl apply` command.

7. **Reboot Option:**

    After the setup is completed, the script will ask if you want to reboot the system. Choose "yes" or "no" based on your preference.

8. **Completion:**

    Once all steps are completed, the script execution will finish, and you'll see a message indicating the completion of the setup process.
