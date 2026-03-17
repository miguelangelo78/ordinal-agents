#!/bin/bash
# Fetch public IP address of the VPS
curl -s ifconfig.me || curl -s icanhazip.com || curl -s api.ipify.org
