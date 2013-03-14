This is a simple script to install FreeBSD on ZFS root for people that cannot
use GPT partitioning scheme or have to use MBR.

ZFS dataset paths are compatible with beadm.

The requirements 
----------------
for running the installer are:

* MBR scheme
* A free BSD slice
* a working internet connection
* FreeBSD (usb install image is fine)

Usage
-----
./installer.sh /dev/ada0s1

Customization
-------------
Read the code in the Settings fold for a list of supported enviroment
variables.

The structure and settings of ZFS datasets can not be changed easily, you will
need to edit the code. This part has been written to be as userfriendly as possible
:)
