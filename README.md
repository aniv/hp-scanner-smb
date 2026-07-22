# HP Scanner SMB server on Proxmox

This project creates an SMB2/SMB3 share named `scans` for an HP scanner. Run it in a small Ubuntu Server VM on Proxmox. Scanned files persist on the VM at `/srv/hp-scans`.

## Recommended topology

- Proxmox host: runs the VM.
- Ubuntu Server 24.04 VM: receives its own LAN IP, preferably a DHCP reservation.
- Docker container: publishes TCP port 445 on the VM.
- HP scanner: saves to `\\VM-IP\scans` as user `scanner`.

Running Docker in a VM is recommended here. Docker inside an LXC requires nesting and creates additional filesystem and security complications with little benefit for this small service.

## 1. Create the Ubuntu VM in Proxmox

1. Upload the Ubuntu Server 24.04 LTS ISO to Proxmox under **local > ISO Images**.
2. Select **Create VM** and use these practical minimums:
   - 1 CPU core
   - 1 GB RAM
   - 8–16 GB disk
   - VirtIO network adapter attached to `vmbr0`
3. Install Ubuntu Server. Select **OpenSSH server** during installation.
4. Give the VM a stable address. A DHCP reservation on your router is generally easier than configuring a static address in Ubuntu.
5. In Proxmox, enable **Start at boot** for the VM.

The VM must be bridged onto the same trusted LAN as the scanner. Do not expose TCP 445 through your router to the internet.

## 2. Install Docker in the VM

SSH into the new VM and install Ubuntu's Docker packages:

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
```

If `docker-compose-v2` is not available in your selected Ubuntu repository, install Docker Engine and the Compose plugin using Docker's official Ubuntu instructions.

## 3. Copy and configure the project

Copy this directory to the VM, then run:

```bash
cd hp-scanner-smb
cp .env.example .env
nano .env
sudo install -d -m 0770 -o 2000 -g 2000 /srv/hp-scans
sudo docker compose up -d --build
```

Replace the example password in `.env`. Use only ordinary printable characters if the HP control panel has trouble entering symbols. Protect the file:

```bash
chmod 600 .env
```

Check startup and validate the share locally:

```bash
sudo docker compose ps
sudo docker compose logs --tail=100 samba
sudo docker compose exec samba smbclient //localhost/scans -U scanner -c 'ls'
```

The last command prompts for the password from `.env`.

## 4. Configure the HP scanner

In the printer's Embedded Web Server, usually reached by opening `http://PRINTER-IP/` in a browser, find **Scan to Network Folder** and create a profile with:

| Field | Value |
| --- | --- |
| Network path | `\\VM-IP\scans` |
| Username | `scanner` |
| Password | Value of `SMB_PASSWORD` |
| Domain | Leave blank; if required, use `WORKGROUP` |
| Port | 445, if requested |

Use the VM's numeric IP first. This avoids DNS or NetBIOS name-resolution problems. Run the printer's connection test, then perform a one-page scan.

## 5. Access scans from a Mac or another computer

On macOS, in Finder choose **Go > Connect to Server** and enter:

```text
smb://VM-IP/scans
```

Sign in as `scanner`. On Linux, use `smb://VM-IP/scans` in the file manager or mount the share with CIFS.

## Firewall notes

If Ubuntu's firewall is enabled, permit SMB only from your LAN. For a typical `192.168.4.0/24` network:

```bash
sudo ufw allow from 192.168.4.0/24 to any port 445 proto tcp
```

Adjust the subnet to match your network. If the Proxmox firewall is enabled for the VM, add the equivalent inbound TCP 445 rule there as well.

## Operations and troubleshooting

```bash
# Follow logs
sudo docker compose logs -f samba

# Rebuild after changing configuration
sudo docker compose up -d --build

# Stop the service without deleting scans
sudo docker compose down

# List received files on the VM
ls -la /srv/hp-scans
```

Common failure points:

- **Connection refused:** container is stopped, port 445 is blocked, or another Samba service already uses port 445 on the VM.
- **Authentication failed:** re-enter the username as `scanner`; leave domain blank or use `WORKGROUP`; verify the password.
- **Folder test works but scans fail:** confirm `/srv/hp-scans` ownership and free disk space, then inspect container logs.
- **Scanner requires SMB1:** update the printer firmware first. Do not enable SMB1 unless there is no alternative; it is obsolete and materially weaker than SMB2/SMB3.
- **Scanner cannot find the hostname:** use the VM's numeric IP and `\\VM-IP\scans`.

## Backup

Back up `/srv/hp-scans`, or include the VM disk in a Proxmox backup job. Scans are bind-mounted outside the container, so rebuilding the image does not remove them.
