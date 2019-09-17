#!/bin/bash

#Run as sudo
if ! [ $(id -u) = 0 ]; then echo "Please run this script as sudo or root"; exit 1 ; fi

#This supports debian 9 based systems because they changed so much I don't have time to cover more
#You can help expand by submitting a pull request
source /etc/os-release
if ! [[ "${NAME}" == *"Debian"* ]] || [[ "${NAME}" == *"Raspbian"* ]]; then
	echo "Only Debian 9 is officially supported."; exit 1 ;
elif ! [[ $PRETTY_NAME = *"stretch"* ]]; then
	echo "Only Debian 9 is officially supported."; exit 1 ;
fi

#Track requested services
CREATE_USER=false
ENABLE_SSH=false
DELETE_USER=false
UPDATE_SYSTEM=false
INSTALL_ORGANIZR=false
INSTALL_GUACAMOLE=false
INSTALL_WOL_SERVER=false
INSTALL_LETSENCRYPT=false
INSTALL_NGINX=false
REBOOT_NEEDED=false
prompt="Press the number and enter to check an option (again to uncheck, ENTER when done): "
DOMAIN_NAME="domain.com"

#Create a new sudo user
create_user(){
	echo '>>>Creating new user'
	read -p 'Enter username: ' varname
	echo
	adduser $varname
	adduser $varname sudo
	adduser $varname adm
	REBOOT_NEEDED=true;

	echo '>>>Done creating user'
	echo
	sleep 2
}

#Make sure SSH is enabled
enable_ssh(){
	echo ">>>Enabling SSH..."
	systemctl enable ssh
	systemctl start ssh
	echo '>>>Done enabling SSH'
	echo
	sleep 2
}

#Remove default "pi" user if using raspbian
del_default_user(){
	echo '>>>Deleting default user'
	read -p 'What is the default user? ' varinput
	echo
	deluser $varinput
	echo '>>>Done deleting user'
	echo
	sleep 2
}

#Update your system
update_sys(){
	echo '>>>Updating the system'
	sleep 1
	chmod +x autoupdt.sh
	mv autoupdt.sh /etc/cron.weekly/autoupdt
	/etc/cron.weekly/autoupdt
	echo
	echo '>>>Done with update. System will update weekly. See /etc/cron.weekly/autoupdt'
	echo
	sleep 5
}

org_ssl(){
	dpkg -s certbot > /dev/null
	if [ $? -eq 0 ]; then
		while true
		do
			echo "In /etc/letsencrypt/live/ by default"
			echo "Give the full path"
			read -p 'Where is your certificate key (.key)? ' cert_location[1]
			[ -f ${cert_location[1]} ] && break
			echo "Could not find ${cert_location[1]}, try again..."
		done

		while true
		do
			read -p 'Where is your certificate (.pem)? ' cert_location[0]
			[ -f ${cert_location[0]} ] && break
			echo "Could not find ${cert_location[0]}, try again..."
		done
	fi

	sed -i 's:/etc.*pem:'${cert_location[0]}':' ${DOMAIN_NAME}.conf
	sed -i 's:/etc.*key:'${cert_location[1]}':' ${DOMAIN_NAME}.conf
	sed -i 's/#ssl_cert/ssl_cert/g' ${DOMAIN_NAME}.conf

	echo '>>>Server SSL updated'
	sleep 1
	echo
}

#Set up organizr subdomain
org_subdomain(){
	#set up the subdomain
        while true
        do
                if [[ $DOMAIN_NAME = "domain.com" ]]; then
			read -p 'Enter your domain (domain.local): ' DOMAIN_NAME
		fi
                [ -f ${DOMAIN_NAME}.conf ] && break
                echo 'Could not find '${DOMAIN_NAME}'.conf nginx conf file in this folder, try again...'
        done

        read -p 'What would you like the organizr domain to be (sub.domain.com)? ' varsubdom
        replace_domain="server_name $varsubdom localhost;"
        sed -i "s/server_name.*host;/${replace_domain}/g" "${DOMAIN_NAME}.conf"
}

#Install Organizer/Nginx/PHP
organizer_install(){
	echo ">>>Installing Organizr, Nginx, and/or PHP. See https://docs.organizr.app/books/installation for installation guide"
	sleep 5
	if [[ $DOMAIN_NAME = "domain.com" ]]; then
		read -p 'Enter your domain name (domain.local): ' DOMAIN_NAME
	fi
	apt-get install git

	#install dependencies
	apt install -y ca-certificates apt-transport-https
	wget -q https://packages.sury.org/php/apt.gpg -O- | apt-key add -
	echo "deb https://packages.sury.org/php/ stretch main" | sudo tee /etc/apt/sources.list.d/php.list

	apt-get update
	apt-get install -y php7.3-fpm php7.3-mysql php7.3-sqlite3 sqlite3 php7.3-xml php7.3-zip openssl php7.3-curl

	#PHP security upgrade
	sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g' /etc/php/7.3/fpm/php.ini
	systemctl restart php7.3-fpm

	git clone https://github.com/causefx/Organizr /var/www/websites/org.${DOMAIN_NAME}
	chown -R www-data:www-data /var/www/websites/org.${DOMAIN_NAME}/

	read -p 'Would you like to set up Organizr on a subdomain (y/n)? ' varinput
	if [[ $varinput =~ ^[Yy]$ ]]; then
		org_subdomain
	fi

	echo '---Organizr---' >> results.txt
	echo 'Install directory: /var/www/websites/org.'${DOMAIN_NAME} >> results.txt
	echo 'Update your nginx conf and visit http://localhost to finish setup' >> results.txt
	echo >> results.txt

	echo '>>>Done installing Organizr'
	echo
	sleep 2
}

#Install Guac
guac_install(){
	echo '>>>Installing guacamole'
	sleep 5
#	wget https://raw.githubusercontent.com/MysticRyuujin/guac-install/master/guac-install.sh

	chmod +x guac-install.sh
	./guac-install.sh

	echo '---Guacamole---' >> results.txt
	echo 'See server config information here: http://guacamole.apache.org/doc/gug/proxying-guacamole.html' >> results.txt
	echo >> results.txt

	echo '>>>Done installing Guacamole'
	echo
	sleep 2
}

#Install nginx
nginx_install(){
        echo '>>>Installing nginx'
	wget https://nginx.org/keys/nginx_signing.key
	apt-key add nginx_signing.key
        #Get nix flavor and version
        source /etc/os-release
        if [[ "${NAME}" == *"Debian"* ]]; then
                if [[ $PRETTY_NAME = *"stretch"* ]]; then
                        echo 'deb http://nginx.org/packages/debian/ stretch nginx' >> /etc/apt/sources.list
                        echo 'deb-src http://nginx.org/packages/debian/ stretch nginx' >> /etc/apt/sources.list
                fi

        elif [[ "${NAME}" == "Ubuntu" ]]; then
		echo "NGINX supports Ubuntu releases 16.04 (xenial), 18.04 (bionic), 18.10 (cosmic), and 19.04 (disco)"
                read -p 'What release are you using (e.g. disco)? ' varinput
                echo "deb http://nginx.org/packages/ubuntu/ $varinput nginx" >> /etc/apt/sources.list
                echo "deb-src http://nginx.org/packages/ubuntu/ $varinput nginx" >> /etc/apt/sources.list
                read -p 'What release are you using (e.g. xenial)? ' varinput
                echo "deb http://nginx.org/packages/ubuntu/ $varinput nginx" >> /etc/apt/sources.list.d/nginx.list
                echo "deb-src http://nginx.org/packages/ubuntu/ $varinput nginx" >> /etc/apt/sources.list.d/nginx.li$
        fi

	apt-get remove nginx-common
        apt-get update
        apt-get install -y nginx
	nginx
	if [[ $DOMAIN_NAME = "domain.com" ]]; then
                read -p 'Enter your domain name (domain.local): ' DOMAIN_NAME
        fi
	mv domain.com.conf ${DOMAIN_NAME}.conf
	sed -i 's/domain.com/'${DOMAIN_NAME}'/' ${DOMAIN_NAME}.conf
	rm -f nginx_signing.key

	#Change NGINX service user to www-data to maintain compatability with php
	sed -i 's/user  nginx/user  www-data/' /etc/nginx/nginx.conf

	echo 'Template nginx conf file saved with this script' >> results.txt
        echo '>>>Done with nginx'
        echo
        sleep 2
}

#Install wake on lan server
wol_setup1(){
	chmod u+s `which ping`
	git clone https://github.com/sciguy14/Remote-Wake-Sleep-On-LAN-Server.git
	mkdir -p /var/www/websites/wol
}
wol_setup2(){
	mv Remote-Wake-Sleep-On-LAN-Server/* /var/www/websites/wol
	rm -rf Remote-Wake-Sleep-On-LAN-Server/
	mv /var/www/websites/wol/config_sample.php /var/www/websites/wol/config.php
	while true
	do
		read -s -p 'Please enter a password for WoL: ' wolPass
		echo
		read -s -p 'Please confirm password: ' wolPass2
		echo
		[ "$wolPass" = "$wolPass2" ] && break
		echo "Passwords don't match. Please try again."
		echo
	done
	wolhash="$(echo -n "${wolPass}" | sha256sum | awk '{print $1}')"
	sed -i 's/YOUR.*HERE/'${wolhash}'/' /var/www/websites/wol/config.php

	echo 'For the computer you would like to wake up:'
	read -p 'Please enter the computer name: ' compName
	echo
	sed -i 's/computer1.*ter2/'${compName}'/' /var/www/websites/wol/config.php

	read -p 'Please enter the MAC address(XX:XX): ' compMAC
	echo
	sed -i 's/00:00:00:00:00:00.*00:00:00:00:00:00/'${compMAC}'/' /var/www/websites/wol/config.php

	read -p 'Please enter the IP address: ' compIP
	echo
	sed -i 's/"19.*0\.2"/"'$compIP'"/' /var/www/websites/wol/config.php
}
wol_apache(){
	echo '>>>Installing WoL server'
	apt-get -y install wakeonlan apache2 php5 git php5-curl libapache2-mod-php5

	wol_setup1
	a2enmod headers
	service apache2 restart
	echo 'Moving included apache conf file to /etc/apache2/sites-available/wol.conf'
	mv -f Remote-Wake-Sleep-On-LAN-Server/000-default.conf /etc/apache2/sites-available/wol.conf
	sed -i.bak "s/expose_php = On/expose_php = Off/g" /etc/php5/apache2/php.ini
	sed -i.bak "s/E_ALL & ~E_NOTICE & ~E_STRICT & ~E_DEPRECATED/error_reporting = E_ERROR/g" /etc/php5/apache2/php.ini
	sed -i.bak "s/ServerSignature On/ServerSignature Off/g" /etc/apache2/conf-available/security.conf
	sed -i.bak "s/ServerTokens OS/ServerTokens Prod/g" /etc/apache2/conf-available/security.conf
	service apache2 restart
	mv Remote-Wake-Sleep-On-LAN-Server/.htaccess /var/www/websites/wol

	wol_setup2

	echo '---WoL Server---' >> results.txt
	echo 'WoL config file example saved to /etc/apache2/sites-available/wol.conf' >> results.txt
	echo  >> results.txt

	echo '>>>Done with WoL server'
	echo
	sleep 2
}
wol_nginx(){
	echo '>>>Installing WoL server'
	dpkg -s nginx > /dev/null
        if [ $? -ne 0 ]; then
                nginx_install
        fi

	apt install -y ca-certificates apt-transport-https
	wget -q https://packages.sury.org/php/apt.gpg -O- | apt-key add -
	echo "deb https://packages.sury.org/php/ stretch main" | tee /etc/apt/sources.list.d/php.list
	apt-get update
	apt-get install -y wakeonlan php7.3-fpm
	wol_setup1
	wol_setup2

	echo '---WoL Server---' >> results.txt
	echo 'WoL Nginx location block example in domain.com.conf' >> results.txt
	echo 'Website file root is /var/www/websites/wol' >> results.txt
	echo  >> results.txt
	echo '>>>Done with WoL server'
	echo
	sleep 2
}

#Install Letsencrypt
letsencrypt(){
	echo '>>>Installing certbot for SSL'
	echo 'The webroot option is easiest'
	read -p 'Make sure your website is up and running before continuing. Enter anything to continue: ' varinput
	misc(){
		#non-packaged version
		wget https://dl.eff.org/certbot-auto
		mv certbot-auto /usr/local/bin/certbot-auto
		chown root /usr/local/bin/certbot-auto
		chmod 0755 /usr/local/bin/certbot-auto

		/usr/local/bin/certbot-auto certonly --nginx
		echo "0 0,12 * * * root python -c 'import random; import time; time.sleep(random.random() * 3600)' && /usr/local/bin/certbot-auto renew" | sudo tee -a /etc/crontab > /dev/null

		echo '---Certbot---' >> results.txt
		echo 'Your SSL certs are located at:' >> results.txt
		/opt/certbot-auto certificates >> results.txt
		echo >> results.txt
		echo '/opt/certbot-auto renew' >> /etc/cron.daily/autoupdt
	}
	finish(){
		certbot certonly --nginx
		echo '---Certbot---' >> results.txt
		echo 'Your SSL certs are located at:' >> results.txt
		certbot certificates >> results.txt
		echo 'certbot renew' >> /etc/cron.daily/autoupdt
	}

	#Get nix flavor and version
	source /etc/os-release
	if [[ "${NAME}" == *"Debian"* ]] || [[ "${NAME}" == *"Raspbian"* ]]; then
		if [[ $PRETTY_NAME = *"stretch"* ]]; then
			echo "deb http://deb.debian.org/debian stretch-backports main" >> /etc/apt/sources.list
			apt-get update
			apt-get -y install certbot python-certbot-nginx -t stretch-backports
			finish
		else
			misc
		fi
	elif [[ "${NAME}" == "Ubuntu" ]]; then
		case $VERSION_ID in
			*"18.04"* | *"16.04"*)
				apt-get -y install software-properties-common;
				add-apt-repository universe;
				add-apt-repository ppa:certbot/certbot;
				apt-get update;
				apt-get -y install certbot python-certbot-nginx;
				finish;;
			*)
				misc;;
		esac
	fi

	read -p 'Do you want to update organizr with the new certs(y/n)? ' varinput
	if [[ $varinput =~ ^[Yy]$ ]]; then
		org_ssl
	fi

	echo '>>>Done with Certbot (letsencrypt)'
	echo
	sleep 2
}

#Install resources
resources(){
	echo 'Resources for the following components:'
	echo 'WoL Server: https://github.com/sciguy14/Remote-Wake-Sleep-On-LAN-Server/wiki/Installation'
	echo 'Organizr: https://github.com/causefx/Organizr/wiki/Linux-Installation'
	echo 'Guacamole: http://guacamole.apache.org/doc/gug/'
	echo 'Certbot: https://certbot.eff.org/'
}

#Ending comments
wrap_up(){
	echo
	echo 'Done!'
	resources
	echo
	cat results.txt 2>/dev/null
}

before_reboot(){
	local options=("Create new sudo user" "Enable SSH" "Update system")
	#function to print the menu
	menu() {
		echo "What would you like to do?"
		for i in ${!options[@]}; do
			printf "%3d%s) %s\n" $((i+1)) "${choices[i]:- }" "${options[i]}"
		done
		[[ "$msg" ]] && echo "$msg"; :
	}

	clear

	while menu && read -rp "$prompt" num && [[ "$num" ]]; do
		clear
		[[ "$num" != *[![:digit:]]* ]] &&
		(( num > 0 && num <= ${#options[@]} )) ||
		{ msg="Invalid option: $num"; continue; }
		((num--)); msg="${options[num]} was ${choices[num]:+un}checked"
		[[ "${choices[num]}" ]] && choices[num]="" || choices[num]="+"
	done

	printf "Installation options selected\n";
	for i in ${!options[@]}; do
		[[ "${choices[i]}" ]] && {
			case $i in
				0)
					CREATE_USER=true
					;;
				1)
					ENABLE_SSH=true
					;;
				2)
					UPDATE_SYSTEM=true
					;;
			esac
		}
	done

	if [[ $CREATE_USER = true ]]; then
		create_user
	fi

	if [[ $ENABLE_SSH = true ]]; then
		enable_ssh
	fi

	if [[ $UPDATE_SYSTEM = true ]]; then
		update_sys
	fi

	if [[ $REBOOT_NEEDED = true ]]; then
		echo 'Restarting in 10 seconds, please re-run as sudo after logging in.'
		echo 'Press Ctrl+C to cancel and re-login manually'
		sleep 10
	else
		echo 'Please re-run the script (as sudo) for part 2'
	fi

}

after_reboot(){
	local options=("Delete default user" "Install Nginx" "Install Guacamole" "Install Wake-On-LAN Server" "Install Certbot (Let's Encrypt)" "Install Organizr")

	#Clear last menu variables
        unset num
        unset msg
        unset choices

	#function to print the menu
	menu() {
		echo "What would you like to do?"
		for i in ${!options[@]}; do
			printf "%3d%s) %s\n" $((i+1)) "${choices[i]:- }" "${options[i]}"
		done
		[[ "$msg" ]] && echo "$msg"; :
	}

	clear

	while menu && read -rp "$prompt" num && [[ "$num" ]]; do
		clear
		[[ "$num" != *[![:digit:]]* ]] &&
		(( num > 0 && num <= ${#options[@]} )) ||
		{ msg="Invalid option: $num"; continue; }
		((num--)); msg="${options[num]} was ${choices[num]:+un}checked"
		[[ "${choices[num]}" ]] && choices[num]="" || choices[num]="+"
	done

	printf "Installation options selected\n";
	for i in ${!options[@]}; do
		[[ "${choices[i]}" ]] && {
			case $i in
				0)
					DELETE_USER=true
					;;
				1)
					INSTALL_NGINX=true
					;;
				2)
					INSTALL_GUACAMOLE=true
					;;
				3)
					INSTALL_WOL_SERVER=true
					;;
				4)
					INSTALL_LETSENCRYPT=true
					;;
				5)
					INSTALL_ORGANIZR=true
					;;
			esac
		}
	done

	if [[ $DELETE_USER = true ]]; then
		del_default_user
	fi

	if [[ $INSTALL_NGINX = true ]]; then
                nginx_install
        fi

	if [[ $INSTALL_ORGANIZR = true ]]; then
		mkdir -p /var/www/websites
		organizer_install
	fi

	if [[ $INSTALL_GUACAMOLE = true ]]; then
		guac_install
	fi

	if [[ $INSTALL_WOL_SERVER = true ]]; then
		echo 'Setting up the WoL server...'
		mkdir -p /var/www/websites
		echo 'I support nginx or apache. Organizr comes configured for nginx'
		read -p 'Which are you using (a or n)? ' varserver
		if [[ $varserver =~ ^[Aa]$ ]]; then
			wol_apache
		else
			wol_nginx
		fi
	fi

	if [[ $INSTALL_LETSENCRYPT = true ]]; then
		letsencrypt
	fi

	wrap_up
	rm /var/run/rebooting-for-updates 2>/dev/null
}

echo 'NOTES:'
echo "-You shouldn't need to install any SSL options as long as you install certbot"
echo "-I recommend using nginx unless you aren't using Organizr"
echo "-Even then, I suggest using nginx..."
echo "-Please pull up the following resources before continuing:"
resources
echo
echo "-After installation, results.txt will save some important information"

if [ -f /var/run/rebooting-for-updates ]; then
    read -p 'Do you want to start from the beginning(y/n)? ' varinput
	if [[ $varinput =~ ^[Yy]$ ]]; then
		before_reboot
		touch /var/run/rebooting-for-updates
	fi
	after_reboot
	#update-rc.d myupdate remove
else
    read -p 'Do you want to start from the beginning(y/n)? ' varinput
	if [[ $varinput =~ ^[Yy]$ ]]; then
		before_reboot
		touch /var/run/rebooting-for-updates
		#update-rc.d myupdate defaults
	else
		after_reboot
	fi
fi
