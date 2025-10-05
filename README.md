# Build-OpenWRT-ZTE-MF286D
Customized OpenWrt image builder with essential 4G modem support

This script automates the process of building a customized OpenWrt firmware image, specifically for the zte_mf286d profile with version 24.10.3 on the ipq40xx/generic platform.

# Main steps of the script:

Initial setup:
Sets variables such as OpenWrt version, hardware target, device profile, and the list of packages to include in the image.

# Check required tools:
Verifies that essential commands (wget, tar, make, unzstd, sha256sum) are installed, otherwise it throws an error and suggests how to install them.

Download ImageBuilder:
Downloads the OpenWrt ImageBuilder, which is a tool used to create custom firmware images, if it’s not already present.

Extraction:
Extracts the downloaded archive.

Detect extracted folder:
Automatically finds the folder where the ImageBuilder files were extracted for further processing.

# Automatic kernel modules hash retrieval:
Fetches the webpage containing kernel modules and extracts the correct hash for the current version to ensure up-to-date kernel modules are used.

Write repositories.conf:
Sets up the repositories for the ImageBuilder to pull packages and kernel modules from, limiting them to essential sources.

Custom network configuration:
Creates a network config file with basic settings for loopback, LAN (bridge with specific ports), WAN over 4G modem using QMI protocol, and IPv6.

Firewall configuration:
Sets basic firewall rules allowing LAN traffic and NAT (masquerading) for WAN.

Wi-Fi disabled configuration:
Creates a wireless config with Wi-Fi disabled (useful for devices with built-in Wi-Fi not in use).

# Build the image:
Changes directory to the ImageBuilder folder and runs make image with the profile, packages, and custom configuration.

# Image output:
Finds the generated sysupgrade image file, verifies it exists, and copies it to the user’s Desktop with a timestamped filename.
