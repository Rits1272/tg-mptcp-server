# tg-mptcp-server

Ansible-based deployment of an MPTCP proxy server that lets [TollGate](https://github.com/OpenTollGate) routers combine multiple internet connections for faster speeds.

## What This Does

TollGate routers use [Crows Nest](https://github.com/OpenTollGate) to scan for and connect to nearby WiFi gateways. Currently, a router can only use one gateway at a time. This project deploys a **server-side MPTCP aggregation endpoint** on a VPS that allows a router to bond multiple gateway connections together for increased bandwidth.

The VPS acts as a convergence point: the router sends traffic through multiple slow links using [Multipath TCP](https://www.multipath-tcp.org/), and the VPS reassembles them into a single fast connection before forwarding to the internet. The destination server never needs to know MPTCP is involved.

## Architecture

```
                        +----- Gateway A (cafe WiFi) ------+
                        |                                   |
Internet  <-->  VPS  <--+----- Gateway B (another TollGate) +--->  TollGate Router
   (MPTCP server)       |                                   |     (Crows Nest)
                        +----- Gateway C (mobile hotspot) --+
```

**Traffic flow:**
1. The TollGate router connects to multiple WiFi gateways via Crows Nest
2. The router runs a shadowsocks client that connects to the VPS over MPTCP
3. The kernel splits that MPTCP connection into **subflows** — one per gateway
4. The VPS kernel reassembles the subflows back into a single stream
5. Shadowsocks on the VPS forwards that traffic to the internet via standard TCP
6. Responses flow back the same path, split across the available links

**Why a VPS is needed:** Most internet servers don't support MPTCP. The router can't just enable MPTCP and talk to YouTube directly — YouTube would ignore it. The VPS sits in the middle: the router bonds its multiple slow links to the VPS using MPTCP, and the VPS makes normal TCP connections to destinations on behalf of the router.

## Prerequisites

### Local Machine (where you run Ansible)

- Python 3.8+
- Ansible 2.12+ (`pip install ansible`)
- `sshpass` (only if using SSH password auth)

```bash
# macOS
brew install ansible
brew install sshpass  # optional, for password auth

# Linux
pip install ansible
apt install sshpass   # optional
```

### Target VPS

- Ubuntu 22.04+ or Debian 12+
- Linux kernel 5.6+ (stock kernels on these distros qualify)
- Root SSH access (key-based recommended)
- Public IP address
- At least 512MB RAM

## Quick Start

### 1. Configure

Edit `group_vars/all.yml` and set your VPS IP and shadowsocks password:

```yaml
vps_ip: "<VPS IP>"
shadowsocks_password: "your-strong-password-here"
```

> **Note:** You do NOT need to configure a glorytun key. The playbook auto-generates one on the VPS during deployment using `glorytun keygen`. After deployment, all credentials (including the generated glorytun key) are saved to `/opt/tollgate/mptcp/server-config.txt` on the VPS.

### 2. Deploy

```bash
./scripts/setup-mptcp.sh <VPS IP>
```

With SSH password:

```bash
./scripts/setup-mptcp.sh -p your-ssh-password <VPS IP>
```

### 3. Verify

```bash
./scripts/verify-mptcp.sh <VPS IP>
```

This runs health checks confirming:
- MPTCP is enabled in the kernel
- Shadowsocks is running and listening
- Glorytun is running (if enabled)
- IP forwarding and NAT are configured

### 4. Retrieve Credentials

After deployment, SSH into the VPS and read the config:

```bash
ssh root@<VPS IP>
cat /opt/tollgate/mptcp/server-config.txt
```

This shows all the credentials your router needs to connect.

## Configuration Reference

All configurable variables are in `group_vars/all.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `vps_ip` | `YOUR_VPS_IP` | VPS public IP address |
| `mptcp_max_subflows` | `8` | Max MPTCP subflows (one per gateway) |
| `mptcp_max_add_addr_accepted` | `8` | Max additional addresses from clients |
| `shadowsocks_port` | `65101` | Shadowsocks listening port |
| `shadowsocks_method` | `chacha20-ietf-poly1305` | Encryption method |
| `shadowsocks_password` | (change this) | Shadowsocks authentication password |
| `shadowsocks_timeout` | `600` | Idle connection timeout (seconds) |
| `glorytun_enabled` | `true` | Enable Glorytun UDP tunnel |
| `glorytun_port` | `65001` | Glorytun listening port |
| `glorytun_server_ip` | `10.255.255.1` | Tunnel interface IP (server side) |
| `glorytun_client_ip` | `10.255.255.2` | Tunnel interface IP (client side) |
| `firewall_manage` | `false` | Set `true` to let the playbook manage UFW |
| `firewall_extra_ports` | `[]` | Extra ports to open (only if `firewall_manage=true`) |
| `ssh_hardening_enabled` | `false` | Set `true` to harden SSH (disables password auth) |
| `ssh_port` | `22` | SSH port |
| `nat_interface` | (auto-detected) | Outbound network interface |

> **Safety:** `firewall_manage` and `ssh_hardening_enabled` are **off by default** so the playbook won't disrupt other services on a shared VPS. Only enable them if you understand the implications (see comments in `group_vars/all.yml`).

## OpenMPTCProuter Compatibility

The defaults are chosen to be compatible with [OpenMPTCProuter](https://github.com/OMPRouter) router firmware out of the box:

| Setting | This Server | OpenMPTCProuter Default | Match? |
|---------|-------------|------------------------|--------|
| Shadowsocks port | 65101 | 65101 | Yes |
| Shadowsocks encryption | chacha20-ietf-poly1305 | chacha20-ietf-poly1305 | Yes |
| Glorytun port | 65001 | 65001 | Yes |
| Glorytun tunnel IPs | 10.255.255.1/2 | 10.255.255.1/2 | Yes |

The only things you need to manually enter on the OpenMPTCProuter router (in the LuCI web interface):
1. **VPS IP address**
2. **Shadowsocks password** (from `server-config.txt`)
3. **Glorytun key** (from `server-config.txt`)

All ports and tunnel IPs will match automatically.

## Scripts

| Script | Description |
|--------|-------------|
| `./scripts/setup-mptcp.sh <vps-ip>` | Deploy MPTCP server to VPS |
| `./scripts/verify-mptcp.sh <vps-ip>` | Run health checks |
| `./scripts/teardown.sh <vps-ip>` | Remove all MPTCP components from VPS |

All scripts accept `-p <password>` for SSH password auth or read `TG_SSH_PASS` env var.

## VPS File Layout

After deployment, the VPS will have:

```
/opt/tollgate/mptcp/
  server-config.txt          # All credentials + config summary (mode 0600)
  glorytun.key               # Glorytun secret key (auto-generated, mode 0600)

/etc/shadowsocks-libev/
  config.json                # Shadowsocks server config

/etc/sysctl.d/
  90-mptcp.conf              # MPTCP kernel parameters

/etc/systemd/system/
  mptcp-limits.service       # Persist MPTCP subflow limits on boot
  glorytun-server.service    # Glorytun tunnel service
  shadowsocks-libev-server@config.service.d/
    mptcp.conf               # Override to add --mptcp flag
```

## How the Router Side Connects

> **Note:** This section is a reference for the router client side.

If using **OpenMPTCProuter firmware** 
1. Flash OpenMPTCProuter onto your router
2. Open LuCI web interface
3. Enter VPS IP, shadowsocks password, and glorytun key from `server-config.txt`
4. OpenMPTCProuter handles all the MPTCP path management automatically

If using **custom OpenWrt** with manual MPTCP setup:

1. **Multiple WAN interfaces** — Connect to multiple gateways, each becoming a separate WAN interface (wwan0, wwan1, wwan2, etc.)

2. **MPTCP enabled in the kernel** — Build OpenWrt with `kmod-mptcp` or use OpenMPTCProuter's kernel

3. **Shadowsocks client** — Install `shadowsocks-libev` and configure:
   ```json
   {
       "server": "VPS_IP",
       "server_port": 65101,
       "local_address": "0.0.0.0",
       "local_port": 1080,
       "password": "same-password-as-server",
       "method": "chacha20-ietf-poly1305",
       "mptcp": true
   }
   ```

4. **MPTCP path manager** — Tell the kernel to create subflows over each WAN:
   ```bash
   ip mptcp endpoint add <wwan0_ip> dev wwan0 subflow
   ip mptcp endpoint add <wwan1_ip> dev wwan1 subflow
   ip mptcp endpoint add <wwan2_ip> dev wwan2 subflow
   ```

5. **Route traffic through the proxy** — Use `ss-redir` for transparent proxying or configure SOCKS5.

## Verifying Bandwidth Aggregation

Once both server and client are set up:

**On the VPS:**
```bash
# Watch MPTCP subflow events in real-time
ip mptcp monitor

# Show active MPTCP connections
ss -M
```

**On the router:**
```bash
# Speed test through the proxy — combined speed should exceed any single gateway
curl --socks5 127.0.0.1:1080 -o /dev/null http://speedtest.tele2.net/10MB.zip
```

## Troubleshooting

**Shadowsocks won't start:**
```bash
systemctl status shadowsocks-libev-server@config
journalctl -u shadowsocks-libev-server@config -n 50
```

**MPTCP not working (only single path used):**
```bash
sysctl net.mptcp.enabled          # Should be 1
ip mptcp limits show               # Should show subflows 8
ss -M                              # Show MPTCP connections
```

**Glorytun connection issues:**
```bash
systemctl status glorytun-server
journalctl -u glorytun-server -n 50
ip addr show tun-tollgate
```

**Firewall blocking connections:**
```bash
ufw status verbose
# Temporarily disable to test
ufw disable
```

**Retrieve all credentials:**
```bash
cat /opt/tollgate/mptcp/server-config.txt
```

## Links

- [TollGate Project](https://github.com/OpenTollGate)
- [Multipath TCP](https://www.multipath-tcp.org/)
- [Linux Kernel MPTCP](https://www.mptcp.dev/)
- [OpenMPTCProuter](https://github.com/OMPRouter)
- [shadowsocks-libev](https://github.com/shadowsocks/shadowsocks-libev)
- [Glorytun](https://github.com/angt/glorytun)
