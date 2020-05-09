#!/bin/bash
apt update
apt -y upgrade
apt -y dist-upgrade
apt clean
apt -y autoremove
