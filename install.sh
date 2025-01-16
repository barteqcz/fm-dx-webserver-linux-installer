#!/bin/bash

user=$(whoami)

clear
compatible_devices=$(ls /dev/serial/by-id | grep "FMDX.org")
compatible_device_count=$(echo "$compatible_devices" | wc -l)

if [[ -z "$compatible_devices" ]]; then
    read -rp "Please provide the used serial port path (or leave empty for the default: /dev/ttyUSB0): " xdrd_serial_port
else
    if [[ "$compatible_device_count" -eq 1 ]]; then
        device_id=$(echo "$compatible_devices")
        device_path="/dev/serial/by-id/$device_id"
        xdrd_serial_port=$(readlink -f "$device_path")
    else
        echo "Available devices (enter the corresponding number to pick one):"
        select device_id in $compatible_devices; do
            if [[ -n "$device_id" ]]; then
                device_path="/dev/serial/by-id/$device_id"
                xdrd_serial_port=$(readlink -f "$device_path")
                break
            else
                echo "Invalid selection. Please try again."
            fi
        done
    fi
fi

read -rp "Please provide password for xdrd (or leave empty for the default: password): " xdrd_password

if [[ $xdrd_serial_port == "" ]]; then
    xdrd_serial_port="/dev/ttyUSB0"
fi

if [[ $xdrd_password == "" ]]; then
    xdrd_password="password"
fi

mkdir build
cd build

build_dir=$(pwd)

PS3="Please select your distribution: " 
select option in "Arch Linux" "Debian/Ubuntu" "Fedora/Red Hat" "SUSE/OpenSUSE"
do
    case $option in
        "Arch Linux")
            distribution="arch"
            ;;
        "Debian/Ubuntu")
            distribution="debian/ubuntu"
            ;;
        "Fedora/Red Hat")
            distribution="fedora/redhat"
            ;;
        "SUSE/OpenSUSE")
            distribution="suse/opensuse"
            ;;
        *)
            echo "Invalid option, please try again."
            ;;
    esac
done

if [[ "$distribution" == "arch" ]]; then
    sudo pacman -Sy
    sudo pacman -S git make gcc openssl pkgconf alsa-utils --noconfirm
    sudo usermod -aG uucp $user
elif [[ "$distribution" == "debian/ubuntu" ]]; then
    sudo apt update
    sudo apt install git make gcc libssl-dev pkgconf alsa-utils -y
    sudo usermod -aG dialout $user
fi

git clone https://github.com/kkonradpl/xdrd.git
cd xdrd/
make
sudo make install

cat <<EOF | sudo tee /etc/systemd/system/xdrd.service
[Unit]
Description=xdrd
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/xdrd -s $xdrd_serial_port -p $xdrd_password
User=$user
Restart=always
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=xdrd

[Install]
WantedBy=multi-user.target
EOF

sudo chmod 644 /etc/systemd/system/xdrd.service
sudo systemctl daemon-reload
sudo systemctl enable --now xdrd

cd $build_dir
git clone https://github.com/NoobishSVK/fm-dx-webserver.git

if [[ "$distribution" == "arch"]]; then
    sudo pacman -S ffmpeg nodejs npm -y
elif [[ "$distribution" == "debian"]]; then
    sudo apt install ffmpeg nodejs npm -y
fi

cd fm-dx-webserver/
npm install

sudo usermod -aG audio $user

cat <<EOF | sudo tee /etc/systemd/system/fm-dx-webserver.service
[Unit]
Description=FM-DX Webserver
After=network-online.target xdrd.service
Requires=xdrd.service

[Service]
ExecStart=npm run webserver
WorkingDirectory=$build_dir/fm-dx-webserver
User=$user
Restart=always
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=fm-dx-webserver

[Install]
WantedBy=multi-user.target
EOF

sudo chmod 644 /etc/systemd/system/fm-dx-webserver.service
sudo systemctl daemon-reload
sudo systemctl enable --now fm-dx-webserver

clear
echo "Installation process finished. Check http://localhost:8080 in your browser."
