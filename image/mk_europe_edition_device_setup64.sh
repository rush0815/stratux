#!/bin/bash

# DO NOT CALL ME DIRECTLY!
# This script is called by mk_europe_edition.sh via qemu

mv /etc/ld.so.preload /etc/ld.so.preload.bak
cd /root/stratux

# Make sure that the upgrade doesn't restart services in the chroot..
mkdir /root/fake
ln -s /bin/true /root/fake/initctl
ln -s /bin/true /root/fake/invoke-rc.d
ln -s /bin/true /root/fake/restart
ln -s /bin/true /root/fake/start
ln -s /bin/true /root/fake/stop
ln -s /bin/true /root/fake/start-stop-daemon
ln -s /bin/true /root/fake/service
ln -s /bin/true /root/fake/deb-systemd-helper

# Fake a proc FS for raspberrypi-sys-mods_20170519_armhf... Extend me as needed
mkdir -p /proc/sys/vm/

apt update
#PATH=/root/fake:$PATH apt dist-upgrade --yes
apt clean

PATH=/root/fake:$PATH apt install --yes libjpeg62-turbo-dev libconfig9 rpi-update hostapd isc-dhcp-server tcpdump git cmake \
    libusb-1.0-0-dev build-essential build-essential autoconf libtool i2c-tools screen libfftw3-dev libncurses-dev
apt clean
#echo y | rpi-update

# TODO: for some reason, gcc crashes a lot when compiling with qemu-user 64 bit.. therefore we will have to use clang for now
# Note that we also had to increase image size to 3gb for this.. hope we can reduce it again in the future
apt --yes install clang
export CC=clang


systemctl enable isc-dhcp-server
systemctl enable ssh
systemctl disable ntp
systemctl disable dhcpcd
systemctl disable hciuart
systemctl disable hostapd

echo INTERFACESv4=\"wlan0\" >> /etc/default/isc-dhcp-server

rm -r /proc/*
rm -r /root/fake


# For some reason in buster, the 8192cu module seems to crash the kernel when a client connects to hostapd.
# Use rtl8192cu module instead, even though raspbian doesn't seem to recommend it.
rm /etc/modprobe.d/blacklist-rtl8192cu.conf
echo "blacklist 8192cu" >> /etc/modprobe.d/blacklist-8192cu.conf

# Install golang
cd /root
wget https://golang.org/dl/go1.16.1.linux-arm64.tar.gz
tar xzf go1.16.1.linux-arm64.tar.gz
rm go1.16.1.linux-arm64.tar.gz


# Prepare wiringpi for fancontrol and some more tools. Need latest version for pi4 support
cd /root && git clone https://github.com/WiringPi/WiringPi.git && cd WiringPi/wiringPi && make && make install
cd /root && rm -r WiringPi
#wget https://project-downloads.drogon.net/wiringpi-latest.deb
#dpkg -i wiringpi-latest.deb
#rm wiringpi-latest.deb


cd /root/stratux
cp image/bashrc.txt /root/.bashrc
source /root/.bashrc

# Prepare librtlsdr. The one shipping with buster uses usb_zerocopy, which is extremely slow on newer kernels, so
# we manually compile the osmocom version that disables zerocopy by default..
cd /root/
rm -rf rtl-sdr
git clone https://github.com/osmocom/rtl-sdr.git
cd rtl-sdr
git checkout 0847e93e0869feab50fd27c7afeb85d78ca04631 # Nov. 20, 2020
mkdir build && cd build
cmake .. -DENABLE_ZEROCOPY=0
make -j8
make install
cd /root/
rm -r rtl-sdr

ldconfig

# Debian seems to ship with an invalid pkgconfig for librtlsdr.. fix it:
#sed -i -e 's/prefix=/prefix=\/usr/g' /usr/lib/arm-linux-gnueabihf/pkgconfig/librtlsdr.pc
#sed -i -e 's/libdir=/libdir=${prefix}\/lib\/arm-linux-gnueabihf/g' /usr/lib/arm-linux-gnueabihf/pkgconfig/librtlsdr.pc


# Compile stratux
cd /root/stratux

make clean
# Sometimes go build segfaults in qemu for some reason.. we will just try three times and hope for the best
make
make install


##### Some device setup - copy files from image directory ####
cd /root/stratux/image
#motd
cp -f motd /etc/motd

#dhcpd config
cp -f dhcpd.conf /etc/dhcp/dhcpd.conf
cp -f dhcpd.conf.template /etc/dhcp/dhcpd.conf.template

#hostapd config
cp -f hostapd.conf /etc/hostapd/hostapd.conf
cp -f hostapd.conf.template /etc/hostapd/hostapd.conf.template

#WPA supplicant config for wifi direct
cp -f wpa_supplicant.conf.template /etc/wpa_supplicant/wpa_supplicant.conf.template

#hostapd manager script
cp -f hostapd_manager.sh /usr/sbin/hostapd_manager.sh
chmod 755 /usr/sbin/hostapd_manager.sh

#remove hostapd startup scripts
rm -f /etc/rc*.d/*hostapd /etc/network/if-pre-up.d/hostapd /etc/network/if-post-down.d/hostapd /etc/init.d/hostapd /etc/default/hostapd
#interface config
cp -f interfaces /etc/network/interfaces
cp -f interfaces.template /etc/network/interfaces.template

#custom hostapd start script
cp stratux-wifi.sh /usr/sbin/
chmod 755 /usr/sbin/stratux-wifi.sh

#SDR Serial Script
cp -f sdr-tool.sh /usr/sbin/sdr-tool.sh
chmod 755 /usr/sbin/sdr-tool.sh

#ping udev
cp -f 99-uavionix.rules /etc/udev/rules.d

#logrotate conf
cp -f logrotate.conf /etc/logrotate.conf

#fan/temp control script
#remove old script
rm -rf /usr/bin/fancontrol.py /usr/bin/fancontrol
#install new program
cp ../fancontrol /usr/bin
chmod 755 /usr/bin/fancontrol
/usr/bin/fancontrol remove
/usr/bin/fancontrol install

#isc-dhcp-server config
cp -f isc-dhcp-server /etc/default/isc-dhcp-server

#sshd config
# Do not copy for now. It contains many deprecated options and isn't needed.
cp -f sshd_config /etc/ssh/sshd_config

#udev config
cp -f 10-stratux.rules /etc/udev/rules.d

#stratux files
cp -f ../libdump978.so /usr/lib/libdump978.so

#debug aliases
cp -f stxAliases.txt /root/.stxAliases

#rtl-sdr setup
cp -f rtl-sdr-blacklist.conf /etc/modprobe.d/

#system tweaks
cp -f modules.txt /etc/modules

#boot settings
cp -f config.txt /boot/
echo -e "\narm_64bit=1" >> /boot/config.txt

#cp /root/stratux/test/screen/screen.py /usr/bin/stratux-screen.py
#mkdir -p /etc/stratux-screen/
#cp -f /root/stratux/test/screen/stratux-logo-64x64.bmp /etc/stratux-screen/stratux-logo-64x64.bmp
#cp -f /root/stratux/test/screen/CnC_Red_Alert.ttf /etc/stratux-screen/CnC_Red_Alert.ttf

#startup scripts
cp -f ../__lib__systemd__system__stratux.service /lib/systemd/system/stratux.service
cp -f ../__root__stratux-pre-start.sh /root/stratux-pre-start.sh
cp -f rc.local /etc/rc.local

#kalibrate-rtl
cd /root
rm -rf kalibrate-rtl
git clone https://github.com/steve-m/kalibrate-rtl
cd kalibrate-rtl
./bootstrap
./configure
make -j8
make install
cd /root && rm -rf kalibrate-rtl


# TODO: not working right now - the pip one seems to at least make stratux-screen runnable (untested)
#cd /root
#git clone https://github.com/rm-hull/ssd1306
#cd ssd1306
# Force an older version of ssd1306, since recent changes have caused a lot of compatibility issues.
#git reset --hard 232fc801b0b8bd551290e26a13122c42d628fd39
#echo Y | python setup.py install
#pip install luma.core
#pip install luma.oled


#disable serial console
sed -i /boot/cmdline.txt -e "s/console=serial0,[0-9]\+ //"

#Set the keyboard layout to US.
sed -i /etc/default/keyboard -e "/^XKBLAYOUT/s/\".*\"/\"us\"/"


# TODO: done -- uninstall clang again
apt remove --yes clang
apt autoremove --yes


# Now also prepare the update file..
cd /root/stratux/selfupdate
./makeupdate.sh


mv /etc/ld.so.preload.bak /etc/ld.so.preload