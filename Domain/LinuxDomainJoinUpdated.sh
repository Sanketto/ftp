#!/bin/bash

red_on=$(tput setaf 1)$(tput smso)  
red_off=$(tput sgr0)
green_on=$(tput setaf 118)$(tput smso)  
green_off=$(tput sgr0)

echo "---------------------------------------------------------------"
#Save stdout to $LOGFILE
LOGFILE="/var/log/adjoin.log"
exec > >(tee -a "${LOGFILE}") 2>&1
#Setting hostname
HOSTNAME=$(hostname)
last_char=$(tail -c 2 /etc/hostname)
if [[ "$last_char" == "L" ]]; then
    echo "$green_on Hostname already set as required with the last character as 'L'. $green_off"
    echo "Exiting ..."
    sleep 3
    exit 0
fi

echo "# SETTING THE HOSTS FILE #"
hostnamectl set-hostname "$HOSTNAME""L"

groupadd StdAdmin
hostnamectl


echo "---------------------------------------------------------------"
#Setting Domainname
DOMAINNAME=kpit.com

echo "---------------------------------------------------------------"
echo "# INSTALLING PREREQUISITES FOR DOMAIN JOIN #"
#apt update

echo "---------------------------------------------------------------"
echo "# DISCOVERING THE DOMAIN AND EDITING THE HOSTS FILE #"
realm discover $DOMAINNAME


echo "---------------------------------------------------------------"
echo "Enter domain admin username: "
read USERNAME

echo "---------------------------------------------------------------"
echo "# JOIN THE SYSTEM TO DOMAIN #"
# Enter domain server as per requirement
source /etc/lsb-release
realm join -v kpit.com -U "$USERNAME" --computer-name "$HOSTNAME""L.kpit.com" --os-name="$DISTRIB_ID" --os-version="$DISTRIB_RELEASE" --computer-ou='OU=Assets,DC=kpit,DC=com'

sssdConfFile=/etc/sssd/sssd.conf
JOIN_DOMAIN=$(grep "ad_domain = kpit.com" $sssdConfFile)
HOSTSFILE=/etc/hosts
if ( echo $JOIN_DOMAIN | grep -q "ad_domain = kpit.com" ); then
    JOIN_DOMAIN=true
    echo "# SETTING THE HOSTS FILE #"
    hostnamectl set-hostname "$HOSTNAME""L"
if ! grep -q '.kpit.com' $HOSTSFILE; then
   cp -r /etc/hosts /etc/hosts.bak
fi
if grep -q $HOSTNAME $HOSTSFILE; then
# HOSTS_COMMENT="#127.0.1.1"
# HOSTS_ENTRY="127.0.1.1 $HOSTNAME"
sed -i "s/$HOSTNAME/$(hostname).kpit.com $(hostname)/g" $HOSTSFILE
fi

echo "$green_on Domain has been join successfully $green_off"

else
    JOIN_DOMAIN=false
    hostnamectl set-hostname "$HOSTNAME"
    echo "$red_on Failed to join Domain!!!  Exiting.... $red_off"
    sleep 3
    exit 0

fi

echo "---------------------------------------------------------------"
echo "# SETTING THE REQUIRED PARAMETERS FOR LOGIN #"
NSSWITCHFILE=/etc/nsswitch.conf
if ! grep -q 'hosts:          files dns' $NSSWITCHFILE; then
   cp -r $NSSWITCHFILE /etc/nsswitch.conf.bak
fi
MKHOME=/usr/share/pam-configs/mkhomedir
cp -r $MKHOME /usr/share/pam-configs/mkhomedir.bak
sed -i 's/Default: no/Default: yes/' $MKHOME
sed -i 's/Priority: 0/Priority: 900/' $MKHOME


echo "---------------------------------------------------------------"
#echo "# RESTARTING THE SSSD SERVICE #"
# systemctl restart sssd
# systemctl status sssd >> sssd
realm permit --all
#New Updates
sed -i -e 's/use_fully_qualified_names = True/#use_fully_qualified_names = True/g' /etc/sssd/sssd.conf
sed -i 's/@%d//g' /etc/sssd/sssd.conf
cp $(pwd)/sssd.conf /etc/sssd/
if ! grep -q 'ad_hostname = $(hostname).kpit.com' $sssdConfFile; then
   sed -i "s/#ad_hostname = .kpit.com/ad_hostname = $(hostname).kpit.com/g" /etc/sssd/sssd.conf
fi
#ad_hostname = .kpit.com
chmod 600 /etc/sssd/sssd.conf
realm permit --groups domain\ users
systemctl restart sssd.service
pam-auth-update --enable mkhomedir
pam-auth-update --enable sss
sed -i 's/[[:blank:]]*dns//g' $NSSWITCHFILE
sed -i 's/hosts:          files/hosts:          files dns/g' $NSSWITCHFILE
echo "---------------------------------------------------------------"
echo "# RESTARTING THE SSSD SERVICE #"
systemctl restart sssd
systemctl status sssd >> sssd
head -5 sssd

echo "---------------------------------------------------------------"
echo "# RESTRICTING SPECIFIC COMMANDS TO SUDO USERS #"
#Sudo restrictions
FILE="/etc/sudoers"
WKSALIAS="User_Alias CSADMINGROUP = %WksAdmin"
STDALIAS="User_Alias SUDOGROUP = %StdAdmin"
SHELLSALIAS="Cmnd_Alias SHELLS = /usr/bin/dash, /usr/bin/csh, /usr/bin/ksh, /usr/bin/zsh, /usr/bin/fish, /usr/bin/tcsh"
SUALIAS="Cmnd_Alias SU = /usr/sbin/adduser, /usr/sbin/deluser, /bin/su, /usr/bin/passwd root, /usr/sbin/visudo, /usr/bin/add-apt-repository, /usr/bin/dpkg --purge --force-all mfecma, /usr/bin/dpkg --purge --force-all mfert, /opt/McAfee/ens/tp/init/mfetpd-control.sh stop, /opt/McAfee/ens/tp/init/mfetpd-control.sh uninstall, /opt/isec/ens/threatprevention/bin/isecav --setoasglobalconfig --oas off, /opt/traps/scripts/uninstall.sh,/opt/zscaler/UninstallApplication,/usr/bin/chattr -i /etc/modprobe.d/blacklist.conf, /usr/bin/chattr -i /etc/netplan/01-network-manager-all.yaml, /usr/bin/chattr -i /etc/sudoers, /usr/bin/chattr -i /etc/sudoers.d, /usr/bin/chattr -i /etc/group"
CSADMIN="CSADMINGROUP   ALL=(ALL:ALL) ALL"
SUDOGRP="SUDOGROUP   ALL=(ALL:ALL) ALL, !SU, !SHELLS"
if grep -q -x -F "$WKSALIAS" "$FILE"; then
    echo "Line '$WKSALIAS' already exists in $FILE. Skipping."
else
    # Append the line to the end of the file
    sed -i '16i\User_Alias CSADMINGROUP = %WksAdmin' /etc/sudoers
    echo "Appended line '$WKSALIAS' to $FILE."
fi
if grep -q -x -F "$STDALIAS" "$FILE"; then
    echo "Line '$STDALIAS' already exists in $FILE. Skipping."
else
    # Append the line to the end of the file
    sed -i '17i\User_Alias SUDOGROUP = %StdAdmin' /etc/sudoers
    echo "Appended line '$STDALIAS' to $FILE."
fi
if grep -q -x -F "$SHELLSALIAS" "$FILE"; then
    echo "Line '$SHELLSALIAS' already exists in $FILE. Skipping."
else
    # Append the line to the end of the file
    sed -i '20i\Cmnd_Alias SHELLS = /usr/bin/bash, /usr/bin/dash, /usr/bin/sh, /usr/bin/csh, /usr/bin/ksh, /usr/bin/zsh, /usr/bin/fish, /usr/bin/tcsh' /etc/sudoers
    echo "Appended line '$SHELLSALIAS' to $FILE."
fi
if grep -q -x -F "$SUALIAS" "$FILE"; then
    echo "Line '$SUALIAS' already exists in $FILE. Skipping."
else
    # Append the line to the end of the file
    sed -i '21i\Cmnd_Alias SU = /usr/sbin/adduser, /usr/sbin/deluser, /bin/su, /usr/bin/passwd root, /usr/sbin/visudo, /usr/bin/add-apt-repository, /usr/bin/dpkg --purge --force-all mfecma, /usr/bin/dpkg --purge --force-all mfert, /opt/McAfee/ens/tp/init/mfetpd-control.sh stop, /opt/McAfee/ens/tp/init/mfetpd-control.sh uninstall, /opt/isec/ens/threatprevention/bin/isecav --setoasglobalconfig --oas off, /opt/traps/scripts/uninstall.sh,/opt/zscaler/UninstallApplication,/usr/bin/chattr -i /etc/modprobe.d/blacklist.conf, /usr/bin/chattr -i /etc/netplan/01-network-manager-all.yaml, /usr/bin/chattr -i /etc/sudoers, /usr/bin/chattr -i /etc/sudoers.d, /usr/bin/chattr -i /etc/group' /etc/sudoers
    echo "Appended line '$SUALIAS' to $FILE."
fi
if grep -q -x -F "$CSADMIN" "$FILE"; then
    echo "Line '$CSADMIN' already exists in $FILE. Skipping."
else
    # Append the line to the end of the file
    sed -i '24i\CSADMINGROUP   ALL=(ALL:ALL) ALL' /etc/sudoers
    echo "Appended line '$CSADMIN' to $FILE."
fi
if grep -q -x -F "$SUDOGRP" "$FILE"; then
    echo "Line '$SUDOGRP' already exists in $FILE. Skipping."
else
    # Append the line to the end of the file
    sed -i '25i\SUDOGROUP   ALL=(ALL:ALL) ALL, !SU, !SHELLS' /etc/sudoers
    echo "Appended line '$SUDOGRP' to $FILE."
fi


echo "---------------------------------------------------------------"
echo "# UPDATING THE GROUP DATABASE TO ENABLE ADMIN ACCESS in GUI #"
GROUPSFILE=/etc/group
cp -r $GROUPSFILE /etc/group.bak
sed -i 's/sudo.*/&,WksAdmin/' $GROUPSFILE
cat $GROUPSFILE | grep -i sudo

# Block USB access
#echo blacklist usb_storage >> /etc/modprobe.d/blacklist.conf
#echo blacklist uas >> /etc/modprobe.d/blacklist.conf
#sed -i '26iGRUB_CMDLINE_LINUX_DEFAULT="quiet splash modprobe.blacklist=nouveau"' /etc/default/grub
#update-grub2
#update-initramfs -u

# Modifying Local KPIT account
#encrypted_kpitpw='$6$KPITLx$WSiYINYTISdxa9.H5vOy4OaIylWfDcpMUW8OAzurY7zaogTOaIfr/cfAY8l0UtOsjDdpUYUMMUMPd59tm.gIT1'
#echo "kpit:${encrypted_kpitpw}" | sudo chpasswd -e
#gpasswd -d kpit adm
#gpasswd -d kpit sudo
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
echo "Backing up keyrings"
mv ~/.local/share/keyrings/login.keyring ~/.local/share/keyrings/login.keyring.bak

echo "# ENABLE PASSWORD AUTHENTICATION IN SSH CONFIG #"
SSHCONFIG=/etc/ssh/sshd_config
cp -r $SSHCONFIG /etc/ssh/sshd_config.bak
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' $SSHCONFIG
cat $SSHCONFIG | grep -i PasswordAuthentication
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
