#!/bin/bash

# Color definitions
red_on=$(tput setaf 1)$(tput smso)
red_off=$(tput sgr0)
green_on=$(tput setaf 118)$(tput smso)
green_off=$(tput sgr0)

# Log file
LOGFILE="/var/log/adjoin.log"
exec > >(tee -a "${LOGFILE}") 2>&1

# Hostname
HOSTNAME=$(hostname)
last_char=$(tail -c 2 /etc/hostname)

# Check if hostname already has 'L' suffix
if [[ "$last_char" == "L" ]]; then
    echo "$green_on Hostname already set as required with the last character as 'L'. $green_off"
    echo "Exiting..."
    sleep 3
    exit 0
fi

echo "--------------------SETTING THE HOSTS/FQDN NAME--------------------"
hostnamectl set-hostname "$HOSTNAME""L"
FQDN="$HOSTNAME""L.kpit.com"
groupadd StdAdmin
hostnamectl

# Backuping the neccessary files
echo "-------------------Backuping the neccessary files-------------------------------"
HOSTSFILE=/etc/hosts
NSSWITCHFILE=/etc/nsswitch.conf
if ! ( grep -q "$FQDN" "$HOSTSFILE" )
then
   cp -r "$HOSTSFILE" /etc/hosts.bak
   sed -i "s/$HOSTNAME/$FQDN "$HOSTNAME""L"/g" "$HOSTSFILE"
fi
if ! ( grep -q "hosts:          files dns" "$NSSWITCHFILE" )
then
   cp -r "$NSSWITCHFILE" /etc/nsswitch.conf.bak
fi


echo "---------------------------------------------------------------"

# Domain name
DOMAINNAME=kpit.com

echo "---------------------------------------------------------------"
echo "# INSTALLING PREREQUISITES FOR DOMAIN JOIN #"
# apt update

echo "---------------------------------------------------------------"
echo "# DISCOVERING THE DOMAIN AND EDITING THE HOSTS FILE #"
realm discover $DOMAINNAME

echo "---------------------------------------------------------------"
read -p "Enter domain admin username: " USERNAME

echo "---------------------------------------------------------------"
echo "# JOIN THE SYSTEM TO DOMAIN #"
# Get distribution information
source /etc/lsb-release
realm join -v kpit.com -U "$USERNAME" --os-name="$DISTRIB_ID" --os-version="$DISTRIB_RELEASE" --computer-ou='OU=Assets,DC=kpit,DC=com'

# Check if domain join was successful
sssdConfFile=/etc/sssd/sssd.conf
if grep -q "ad_domain = kpit.com" "$sssdConfFile"; then
    echo "# SETTING THE HOSTS FILE #"
    hostnamectl set-hostname "$HOSTNAME""L"
    echo "$green_on Domain has been joined successfully $green_off"
else
    echo "$red_on Failed to join Domain!!!  Exiting.... $red_off"
    hostnamectl set-hostname "$HOSTNAME"
    sed -i "s/$FQDN "$HOSTNAME""L"/"$HOSTNAME"/g" "$HOSTSFILE"
    sleep 3
    exit 0
fi

echo "---------------------------------------------------------------"
echo "# SETTING THE REQUIRED PARAMETERS FOR LOGIN #"
MKHOME=/usr/share/pam-configs/mkhomedir

#Modify Mkhomedir Configuration
cp -r "$MKHOME" /usr/share/pam-configs/mkhomedir.bak
sed -i 's/Default: no/Default: yes/' "$MKHOME"
sed -i 's/Priority: 0/Priority: 900/' "$MKHOME"

echo "---------------------------------------------------------------"
realm permit --all

# New Updates
sed -i -e 's/use_fully_qualified_names = True/#use_fully_qualified_names = True/g' /etc/sssd/sssd.conf
sed -i 's/@%d//g' /etc/sssd/sssd.conf
cp $(pwd)/sssd.conf /etc/sssd/

if ! grep -q 'ad_hostname = $(hostname).kpit.com' "$sssdConfFile"; then
   sed -i "s/#ad_hostname = .kpit.com/ad_hostname = $(hostname).kpit.com/g" "$sssdConfFile"
fi

chmod 600 /etc/sssd/sssd.conf
realm permit --groups domain\ users

# Restart sssd and update pam
systemctl restart sssd.service
pam-auth-update --enable mkhomedir
pam-auth-update --enable sss
sed -i 's/[[:blank:]]*dns//g' "$NSSWITCHFILE"
sed -i 's/hosts:          files/hosts:          files dns/g' "$NSSWITCHFILE"

echo "---------------------------------------------------------------"
echo "# RESTARTING THE SSSD SERVICE #"
systemctl restart sssd
systemctl status sssd >> sssd
head -5 sssd

echo "---------------------------------------------------------------"
echo "# RESTRICTING SPECIFIC COMMANDS TO SUDO USERS #"

# Sudo restrictions (implemented with checks to avoid duplication)
FILE="/etc/sudoers"
WKSALIAS="User_Alias CSADMINGROUP = %WksAdmin"
STDALIAS="User_Alias SUDOGROUP = %StdAdmin"
SHELLSALIAS="Cmnd_Alias SHELLS = /usr/bin/dash, /usr/bin/csh, /usr/bin/ksh, /usr/bin/zsh, /usr/bin/fish, /usr/bin/tcsh"
SUALIAS="Cmnd_Alias SU = /usr/sbin/adduser, /usr/sbin/deluser, /bin/su, /usr/bin/passwd root, /usr/sbin/visudo, /usr/bin/add-apt-repository, /usr/bin/dpkg --purge --force-all mfecma, /usr/bin/dpkg --purge --force-all mfert, /opt/McAfee/ens/tp/init/mfetpd-control.sh stop, /opt/McAfee/ens/tp/init/mfetpd-control.sh uninstall, /opt/isec/ens/threatprevention/bin/isecav --setoasglobalconfig --oas off, /opt/traps/scripts/uninstall.sh,/opt/zscaler/UninstallApplication,/usr/bin/chattr -i /etc/modprobe.d/blacklist.conf, /usr/bin/chattr -i /etc/netplan/01-network-manager-all.yaml, /usr/bin/chattr -i /etc/sudoers, /usr/bin/chattr -i /etc/sudoers.d, /usr/bin/chattr -i /etc/group"
CSADMIN="CSADMINGROUP   ALL=(ALL:ALL) ALL"
SUDOGRP="SUDOGROUP   ALL=(ALL:ALL) ALL, !SU, !SHELLS"

# Function to append lines to /etc/sudoers if they don't already exist
append_to_sudoers() {
  line="$1"
  if ! grep -q -x -F "$line" "$FILE"; then
    sed -i "$1" /etc/sudoers #Adjust insertion point if needed
    echo "Appended line '$line' to $FILE."
  else
    echo "Line '$line' already exists in $FILE. Skipping."
  fi
}

append_to_sudoers "'16i'\'$WKSALIAS'"
append_to_sudoers "'17i'\'$STDALIAS'"
append_to_sudoers "'20i'\'$SHELLSALIAS'"
append_to_sudoers "'21i'\'$SUALIAS'"
append_to_sudoers "'24i'\'$CSADMIN'"
append_to_sudoers "'25i'\'$SUDOGRP'"

echo "---------------------------------------------------------------"
echo "# UPDATING THE GROUP DATABASE TO ENABLE ADMIN ACCESS in GUI #"
GROUPSFILE=/etc/group
cp -r "$GROUPSFILE" /etc/group.bak
sed -i 's/sudo.*/&,wksadmin/' "$GROUPSFILE"
cat "$GROUPSFILE" | grep -i sudo

# Block USB access (commented out)
#echo blacklist usb_storage >> /etc/modprobe.d/blacklist.conf
#echo blacklist uas >> /etc/modprobe.d/blacklist.conf
#sed -i '26iGRUB_CMDLINE_LINUX_DEFAULT="quiet splash modprobe.blacklist=nouveau"' /etc/default/grub
#update-grub2
#update-initramfs -u

# Modifying Local KPIT account
adduser kpit StdAdmin

# Revoking access to a sudoers, network config, group and blacklist files
chattr +i /etc/netplan/01-network-manager-all.yaml
chattr +i /etc/sudoers
chattr +i /etc/sudoers.d
chattr +i /etc/modprobe.d/blacklist.conf
chattr -i /etc/group
chattr +i /etc/hostname

# Setting root password
encrypted_pw='$6$LinSec$9ZGhCKxvumcqAUkQdSY.JM5iOcFgQShNYZMChw0BcKJny7Wj9NtlaTBgAAbM65Gfa5EMlmit2L7hOdovE3hDK0'
echo "root:${encrypted_pw}" | sudo chpasswd -e
sleep 3
echo "---------------------------------------------------------------"

echo "# ENABLE PASSWORD AUTHENTICATION IN SSH CONFIG #"
SSHCONFIG=/etc/ssh/sshd_config
cp -r "$SSHCONFIG" /etc/ssh/sshd_config.bak
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' "$SSHCONFIG"
cat "$SSHCONFIG" | grep -i PasswordAuthentication
realm list

echo "---------------------------------------------------------------"
echo "# VERIFY LOGIN VIA SSH #"
ssh $USERNAME@localhost

echo "---------------------------------------------------------------"
echo "---------------------------------------------------------------"
echo "If you were able to login successfully, then the system has been successfully joined to the KPIT domain"
echo "If not, please look for errors in /var/log/adjoin.log file"
echo "---------------------------------------------------------------"
echo "---------------------------------------------------------------"