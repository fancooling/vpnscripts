# vpnscripts

This guide uses the popular [Nyr/openvpn-install](https://github.com/Nyr/openvpn-install) script for a quick and secure OpenVPN server setup on Ubuntu.

## OpenVPN Server Setup

This method automates the entire installation and configuration process.

### 1. Download the Installation Script

Log in to your server and download the script.

```bash
curl -O https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh
```

### 2. Make the Script Executable

Give the script execute permissions.

```bash
chmod +x openvpn-install.sh
```

### 3. Run the Script

Run the script with `sudo`. The first time you run it, it will guide you through the server setup process.

```bash
sudo ./openvpn-install.sh
```

The script will ask a series of questions to configure your VPN. In most cases, you can accept the default options. It will also prompt you to create your first client.

Once finished, your OpenVPN server will be running, and the first client configuration file (e.g., `client-name.ovpn`) will be placed in the home directory of the user who ran the script (e.g., `/root/client-name.ovpn`).

### 4. Managing VPN Clients (Add/Revoke)

To add or remove clients, simply run the script again from your server.

```bash
sudo ./openvpn-install.sh
```

Since OpenVPN is already installed, the script will present you with a menu to add a new user, revoke an existing user, or remove OpenVPN entirely. New client `.ovpn` files are created in the home directory of the user executing the script.

A more convenient appraoch to add new client is to use the `new_vpn_client.sh` script in this repository.

## Advanced VPN configuration

### Change VPN subnet

If you need to change the VPN subnet after installation (e.g., from the default `10.8.0.0/24` to `10.9.0.0/24`), you need to manually edit a few configuration files.

**Important:** This process does not require you to regenerate existing client profiles. They will automatically connect and receive an IP from the new subnet.

1.  **Stop the OpenVPN Service and Distable iptables introduced by VPN**

    ```bash
    sudo systemctl stop openvpn-server@server
    sudo systemctl stop openvpn-iptables.service
    ```

2.  **Edit the Server Configuration**

    Open the server configuration file.

    ```bash
    sudo nano /etc/openvpn/server/server.conf
    ```

    Find the `server` line and change the IP address to your new subnet.

    ```diff
    - server 10.8.0.0 255.255.255.0
    + server 10.9.0.0 255.255.255.0
    ```

3.  **Update Iptables Rules**
    Open OpenVPN iptables.
    ```bash
    sudo nano /etc/systemd/system/openvpn-iptables.service
    ```
    Look for lines like:
    ```
    ExecStart=/usr/sbin/iptables -w 5 -t nat -A POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to 192.168.1.1
    ExecStart=/usr/sbin/iptables -w 5 -I FORWARD -s 10.8.0.0/24 -j ACCEPT
    ExecStop=/usr/sbin/iptables -w 5 -t nat -D POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to 192.168.1.1
    ExecStop=/usr/sbin/iptables -w 5 -D FORWARD -s 10.8.0.0/24 -j ACCEPT
    ```
    Change all occurrences of 10.8.0.0/24 to 10.9.0.0/24.
4.  **(Recommended) Clear Client IP Persistence**

    To ensure clients get fresh IPs from the new subnet, remove the old IP persistence file.

    ```bash
    sudo rm /etc/openvpn/ipp.txt
    ```

5.  **Restart Services**

    Restart your firewall to apply the new rules, then start the OpenVPN server.

    ```bash
    sudo systemctl daemon-reload
    # Start OpenVPN
    sudo systemctl start openvpn-server@server
    # Update iptables
    sudo systemctl start openvpn-iptables.service
    ```

    Your server is now operating on the new `10.9.0.0/24` subnet.

### Connect to Home Network from VPN (Site-to-Site)

Assume you configure the OpenVPN server in a public Cloud. The following setup allows you to
connect to your cloud VPN server from any device (e.g., your laptop on public Wi-Fi) and
securely access devices on your home network (like a NAS or Raspberry Pi).

This guide assumes your home network uses a subnet like `192.168.1.0/24` and your VPN subnet is the default `10.8.0.0/24`.

Follow instruction above on how to change VPN subnet.

#### Step 1: Configure the Cloud VPN Server

First, we'll tell the server to allow clients to communicate with each other and how to reach your home network.

1.  **Edit the server configuration:**

    ```bash
    sudo nano /etc/openvpn/server/server.conf
    ```

2.  **Add the following lines** to the file. This enables client-to-client communication, tells the server where to find client-specific rules, and tells all connecting clients how to reach your home network.

    ```ini
    client-to-client
    client-config-dir ccd
    push "route 192.168.1.0 255.255.255.0"
    route 192.168.1.0 255.255.255.0
    ```

3.  **Create the client configuration directory:**

    ```bash
    sudo mkdir /etc/openvpn/server/ccd
    ```

4.  **Restart the OpenVPN server** to apply the changes:
    ```bash
    sudo systemctl restart openvpn-server@server
    ```

#### Step 2: Create and Configure a Dedicated Home Gateway Client

This client will live inside your home network and act as the gateway.

1.  **On the cloud server**, create a new VPN client profile. Let's name it `home-gateway`.

    ```bash
    sudo ./openvpn-install.sh
    ```

    Follow the prompts to add a new user named `home-gateway`.

2.  **Create a specific rule for this client** on the cloud server. This tells OpenVPN that the `home-gateway` client is the entry point for your entire home subnet.
    ```bash
    # Replace 192.168.1.0 255.255.255.0 with your actual home network subnet and mask
    echo 'iroute 192.168.1.0 255.255.255.0' | sudo tee /etc/openvpn/server/ccd/home-gateway
    ```
    If you have a different client name, make sure to update the file name to match client name.

#### Step 3: Set Up the Gateway Client on an Ubuntu Host at Home

On a dedicated Ubuntu machine inside your home network:

1.  **Install the OpenVPN client:**

    ```bash
    sudo apt update
    sudo apt install openvpn
    ```

2.  **Securely transfer the `home-gateway.ovpn` file** from your cloud server to this home Ubuntu machine. Place it at `/etc/openvpn/client/home-gateway.conf`.

3.  **Enable IP forwarding** to allow the machine to route traffic:

    ```bash
    echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-openvpn-forward.conf
    sudo sysctl -p
    ```

4.  **Set up firewall rules for routing (NAT).** This allows devices on your home network to reply to requests from your VPN clients.

    - First, find your home network's interface name (e.g., `eth0`, `enp3s0`): `ip a`
    - Then, add the firewall rules. Replace `eth0` with your actual interface name and `10.8.0.0/24` if you use a different VPN subnet.

    ```bash
    sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
    sudo iptables -A FORWARD -i eth0 -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A FORWARD -i tun0 -o eth0 -j ACCEPT
    ```

5.  **Make the iptables rules persistent** across reboots:

    ```bash
    sudo apt install iptables-persistent
    sudo iptables-save

    ```

6.  **Enable and start the OpenVPN client service.** This will automatically connect to your cloud server on boot.
    ```bash
    sudo systemctl enable --now openvpn-client@home-gateway
    ```

#### Step 4: Connect and Access Your Home Network

You're all set! Now, when you connect to your cloud VPN server from any other client (your laptop, your phone), you can directly access devices on your home network by their local IP address.

For example, from your laptop connected to the VPN, you can now run:

```bash
# Ping a device on your home network
ping 192.168.1.50

# SSH into a server at home
ssh user@192.168.1.100
```

### The OpenVPN Management Interface

The following explains how to enable OpenVPN management interface.

1.  **Configure OpenVPN server**

    ```bash
    sudo vim /etc/openvpn/server/server.conf
    ```

    Add the following line.

    ```
    management 127.0.0.1 5555
    ```

2.  **Restart the OpenVPN server:**

    ```bash
    sudo systemctl restart openvpn-server@server
    ```

3.  **Connect to management interface**
    ```bash
    telnet localhost 5555
    ```

After that, run commands, e.g.,:

- help
- list
- status
- kill <client_name>

### Other Useful Ubuntu Commands

```bash
sudo iptables -t nat -L -v -n -line-num
sudo iptables  -L -v -n --line-num
sudo netfilter-persistent save
```
