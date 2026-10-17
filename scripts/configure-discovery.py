#!/usr/bin/env python3
"""Generate an installation-specific Info.plist with a token-free tailnet seed."""
import argparse
import ipaddress
import json
import pathlib
import plistlib
import re
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--port", type=int, default=3333)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("port must be between 1 and 65535")
    binary = shutil.which("tailscale") or "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    status = json.loads(subprocess.check_output([binary, "status", "--json"], timeout=8))
    if status.get("BackendState") != "Running":
        parser.error("connect Tailscale on this Mac before preparing the installation")
    addresses = status.get("Self", {}).get("TailscaleIPs", [])
    network = ipaddress.ip_network("100.64.0.0/10")
    seeds = [f"http://{ip}:{args.port}" for ip in addresses if ipaddress.ip_address(ip).version == 4 and ipaddress.ip_address(ip) in network]
    if not seeds:
        parser.error("this Mac has no Tailscale IPv4 address")
    source = pathlib.Path(__file__).resolve().parents[1] / "Petroglyphs" / "Info.plist"
    info = plistlib.loads(source.read_bytes())
    info["PetroglyphsDiscoveryOrigins"] = seeds
    exceptions = info["NSAppTransportSecurity"]["NSExceptionDomains"]
    dns_name = status.get("Self", {}).get("DNSName", "").lower().rstrip(".")
    if len(dns_name) <= 253 and re.fullmatch(r"(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.){2,}ts\.net", dns_name):
        suffix = dns_name.split(".", 1)[1]
        exceptions[suffix] = {"NSExceptionAllowsInsecureHTTPLoads": True, "NSIncludesSubdomains": True}
        seeds.insert(0, f"http://{dns_name}:{args.port}")
        info["PetroglyphsDiscoveryOrigins"] = seeds
    # Keep exact known node exceptions as well as the tailnet CIDR exception.
    # Some device/SDK combinations reject an IP load with only the range entry.
    macs = [status.get("Self", {})] + [peer for peer in status.get("Peer", {}).values() if peer.get("OS") in ("macOS", "darwin")]
    for mac in macs:
        for raw in mac.get("TailscaleIPs", []):
            ip = ipaddress.ip_address(raw)
            if ip.version == 4 and ip in network:
                exceptions[str(ip)] = {"NSExceptionAllowsInsecureHTTPLoads": True}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(plistlib.dumps(info))
    print(f"Generated {args.output} with {len(seeds)} token-free discovery entry")


if __name__ == "__main__":
    main()
