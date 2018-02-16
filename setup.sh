#!/bin/bash

#Auto fix organizr to subdomain
#figure out order of ssl certs LE and ORG
#host on github and include pulls for other resources

#Run as sudo
#This supports debian or ubuntu based systems

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

#Remove default "pi" user
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
	#escape the path in the variable then replace
	#esc_chain=$(printf '%s\n' "${cert_location[0]}" | sed 's:[\/&]:\\&:g;$!s/$/\\/')
	#esc_key=$(printf '%s\n' "${cert_location[1]}" | sed 's:[\/&]:\\&:g;$!s/$/\\/')
	#sed -i 's/\/etc.*pem;/'$esc_chain'/' $varinput.conf
	#sed -i 's/\/etc.*key;/'$esc_key'/' $varinput.conf

	dpkg -s certbot > /dev/null
	if [ $? -eq 0 ]; then
		cert_location=($(awk '/live/' certbot.out | awk -F': ' '{ print $2 }'))
	else
		while true
		do
			read -p 'Where is your certificate key? ' cert_location[1]
			[ -f ${cert_location[1]} ] && break
			echo "Could not find ${cert_location[1]}, try again..."
		done

		while true
		do
			read -p 'Where is your certificate? ' cert_location[0]
			[ -f ${cert_location[0]} ] && break
			echo "Could not find ${cert_location[0]}, try again..."
		done
	fi

	sed -i 's:/etc.*pem;:'${cert_location[0]}':' $vardomain.conf
	sed -i 's:/etc.*key;:'${cert_location[1]}':' $vardomain.conf
	sed -i 's/#ssl_cert/ssl_cert/g' $vardomain.conf

	echo '>>>Server SSL updated'
	sleep 1
	echo
}

#Set up organizr subdomain
org_subdomain(){
	#set up the subdomain
        while true
        do
                read -p 'Enter your domain/organizr install folder (domain.local)' vardomain
                [ -f /etc/nginx/site-enabled/$vardomain.conf ] && break
                echo "Could not find $vardomain nginx configuration file, try again..."
        done

        read -p 'What would you like the organizr domain to be (sub.example.com)? ' varsubdom
        replace_domain="server_name $varsubdom localhost;"
        sed -i 's/server_name.*host;/'$replace_domain'/' $vardomain.conf
}

#Install Organizer/Nginx/PHP
organizer_install(){
	echo ">>>Installing Organizr, Nginx, and/or PHP. See https://organizr.us/ for installation guide"
	sleep 5
	apt-get install git
	git clone https://github.com/elmerfdz/OrganizrInstaller /opt/OrganizrInstaller
	cd /opt/OrganizrInstaller/ubuntu/oui
	bash ou_installer.sh

	read -p 'Would you like to set up Organizr on a subdomain [nginx only] (y/n)? ' varinput
	if [[ $varinput =~ ^[Yy]$ ]]; then
		org_subdomain
	fi

	echo '---Organizr---' >> results.txt
	echo 'Install directory: /var/www/domain.local' >> results.txt
	echo 'Organizr files stored: /var/www/domain.local/html' >> results.txt
	echo 'Organizr db directory: /var/www/domain.local/db' >> results.txt
	echo 'Use the above db path when setting up admin user' >> results.txt
	echo 'Visit localhost/ to finish setup' >> results.txt
	echo 'You will still need to edit /etc/nginx/site-enabled/domain.local.conf to add services'
	echo '-This is also where you will tell nginx where your SSL certs are located'
	echo >> results.txt

	echo '>>>Done installing Organizr'
	echo
	sleep 2
}

#Install Guac
guac_install(){
	echo '>>>Installing guacamole'
	sleep 5
	wget https://raw.githubusercontent.com/MysticRyuujin/guac-install/master/guac-install.sh
	chmod +x guac-install.sh
	#Expand to include raspbian
	sed -i 's/\[\[ "\${NAME}" == \*"Debian"\* \]\]/[[ "${NAME}" == *"Debian"* ]] || [[ "${NAME}" == *"Raspbian"* ]]/' guac-install.sh

	#Select guac functionality
	options=("RDP" "SSH" "Telnet" "VNC" "VNC Audio" "Recordings" "SSL/TLS" "Audio Compression" "WebP")
	to_install="apt -y install build-essential libcairo2-dev ${JPEGTURBO} ${LIBPNG} libossp-uuid-dev mysql-server \
		mysql-client mysql-common mysql-utilities libmysql-java ${TOMCAT} freerdp-x11 ghostscript wget dpkg-dev "

	#function to print the menu
	menu() {
		echo "Avaliable guacamole options:"
		for i in ${!options[@]}; do
			printf "%3d%s) %s\n" $((i+1)) "${choices[i]:- }" "${options[i]}"
		done
		[[ "$msg" ]] && echo "$msg"; :
	}

	#start with a clean prompt
	clear
	prompt="Check an option (again to uncheck, ENTER when done): "

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
					to_install="$to_install libfreerdp-dev "
					;;
				1)
					to_install="$to_install libpango1.0-dev libssh2-1-dev libssl-dev "
					;;
				2)
					to_install="$to_install libpango1.0-dev libtelnet-dev "
					;;
				3)
					to_install="$to_install libvncserver-dev "
					;;
				4)
					to_install="$to_install libpulse-dev "
					;;
				5)
					to_install="$to_install libavcodec-dev libavutil-dev libswscale-dev "
					;;
				6)
					to_install="$to_install libssl-dev "
					;;
				7)
					to_install="$to_install libvorbis-dev "
					;;
				8)
					to_install="$to_install libwebp-dev "
					;;
			esac
		}
	done

	#Change dependencies
	echo '>>>Replacing dependencies'
	perl -i -pe 'BEGIN{undef $/;} s/apt -y install build-essential.*dpkg-dev/'"${to_install}"'/smg' guac-install.sh

	./guac-install.sh
	echo '---Guacamole---' >> results.txt
	echo 'See server config information here: http://guacamole.apache.org/doc/gug/proxying-guacamole.html' >> results.txt
	echo >> results.txt

	echo '>>>Done installing Guacamole'
	echo
	sleep 2
}

#Install wake on lan server
wol_setup1(){
	chmod u+s `which ping`
	git clone https://github.com/sciguy14/Remote-Wake-Sleep-On-LAN-Server.git
	mkdir /var/www/wol
}
wol_setup2(){
	mv Remote-Wake-Sleep-On-LAN-Server/* /var/www/wol
	rm -rf Remote-Wake-Sleep-On-LAN-Server/
	mv /var/www/wol/config_sample.php /var/www/wol/config.php
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
	wolhash="$(echo -n "$wolPass" | sha256sum | awk '{print $1}')"
	sed -i 's/YOUR.*HERE/'$wolhash'/' /var/www/wol/config.php

	echo 'For the computer you would like to wake up:'
	read -p 'Please enter the computer name: ' compName
	echo
	sed -i 's/computer1.*ter2/'$compName'/' /var/www/wol/config.php

	read -p 'Please enter the MAC address(XX:XX): ' compMAC
	echo
	sed -i 's/00:00:00:00:00:00.*00:00:00:00:00:00/'$compMAC'/' /var/www/wol/config.php

	read -p 'Please enter the IP address: ' compIP
	echo
	sed -i 's/190.*0.2/'$compIP'/' /var/www/wol/config.php
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
	mv Remote-Wake-Sleep-On-LAN-Server/.htaccess /var/www/wol

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
	apt-get install wakeonlan
	wol_setup1
	wol_setup2

	echo '---WoL Server---' >> results.txt
	echo 'WoL Nginx location block example saved to WoL_nginx_example' >> results.txt
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
		chmod a+x certbot-auto
		mv certbot-auto /opt/certbot-auto
		/opt/certbot-auto certonly

		echo '---Certbot---' >> results.txt
		echo 'Your SSL certs are located at:' >> results.txt
		/opt/certbot-auto certificates >> results.txt
		echo >> results.txt
		echo '/opt/certbot-auto renew' >> /etc/cron.daily/autoupdt
	}
	finish(){
		certbot certonly
		echo '---Certbot---' >> results.txt
		echo 'Your SSL certs are located at:' >> results.txt
		certbot certificates >> results.txt
		echo 'certbot renew' >> /etc/cron.daily/autoupdt
	}

	#Get nix flavor and version
	source /etc/os-release
	if [[ "${NAME}" == *"Debian"* ]] || [[ "${NAME}" == *"Raspbian"* ]]; then
		if [[ $PRETTY_NAME = *"jessie"* ]] || [[ $PRETTY_NAME = *"stretch"* ]]; then
			sudo apt-get -y install python-certbot
			finish
		else
			misc
		fi
	elif [[ "${NAME}" == "Ubuntu" ]]; then
		case $VERSION_ID in
			*"17.04"* | *"16.10"* | *"16.04"* | *"14.04"*)
				apt-get install software-properties-common;
				add-apt-repository ppa:certbot/certbot;
				apt-get update;
				apt-get install certbot;
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

#Install nginx
nginx_install(){
	echo '>>>Installing nginx'

	#Get nix flavor and version
	source /etc/os-release
	if [[ "${NAME}" == *"Debian"* ]]; then
		if [[ $PRETTY_NAME = *"squeeze"* ]]; then
			echo 'deb http://nginx.org/packages/debian/ squeeze nginx' >> /etc/apt/sources.list.d/nginx.list
			echo 'deb-src http://nginx.org/packages/debian/ squeeze nginx' >> /etc/apt/sources.list.d/nginx.list
		fi
	elif [[ "${NAME}" == "Ubuntu" ]]; then
		read -p 'What release are you using (e.g. xenial)? ' varinput
		echo "deb http://nginx.org/packages/ubuntu/ $varinput nginx" >> /etc/apt/sources.list.d/nginx.list
		echo "deb-src http://nginx.org/packages/ubuntu/ $varinput nginx" >> /etc/apt/sources.list.d/nginx.list
	fi

	sudo apt-get update
	sudo apt-get install nginx

	echo '>>>Done with nginx'
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
	options=("Create new sudo user" "Enable SSH" "Update system")
	#function to print the menu
	menu() {
		echo "What would you like to do?"
		for i in ${!options[@]}; do
			printf "%3d%s) %s\n" $((i+1)) "${choices[i]:- }" "${options[i]}"
		done
		[[ "$msg" ]] && echo "$msg"; :
	}

	clear
	prompt="Check an option (again to uncheck, ENTER when done): "

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
		echo 'Restarting, please re-run as sudo after logging in.'
		echo 'Press Ctrl+C to cancel and re-login manually'
		sleep 10
	else
		echo 'Please re-run the script (as sudo) for part 2'
	fi

}

after_reboot(){
	options=("Delete default user" "Install Organizr" "Install Guacamole" "Install Wake-On-LAN Server" "Install Certbot (Let's Encrypt)" "Nginx (included with organizr)")
	#function to print the menu
	menu() {
		echo "What would you like to do?"
		for i in ${!options[@]}; do
			printf "%3d%s) %s\n" $((i+1)) "${choices[i]:- }" "${options[i]}"
		done
		[[ "$msg" ]] && echo "$msg"; :
	}

	clear
	prompt="Check an option (again to uncheck, ENTER when done): "

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
					INSTALL_ORGANIZR=true
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
					INSTALL_NGINX=true
					;;
			esac
		}
	done

	if [[ $DELETE_USER = true ]]; then
		del_default_user
	fi

	if [[ $INSTALL_ORGANIZR = true ]]; then
		organizer_install
	fi

	if [[ $INSTALL_NGINX = true ]]; then
		nginx_install
	fi

	if [[ $INSTALL_GUACAMOLE = true ]]; then
		guac_install
	fi

	if [[ $INSTALL_WOL_SERVER = true ]]; then
		echo 'Setting up the WoL server...'
		echo 'I support nginx or apache. Organizr comes configured for nginx'
		read -p 'Which are you using (a or n)?' varserver
		if [[ $varserver =~ ^[Aa]$ ]]; then
			wol_apache
		else
			wol_nginx
		fi
	fi

	if [[ $INSTALL_LETSENCRYPT = true ]]; then
		letsencrypt
	fi

	read -p 'Would you like to set up organizr (recommended)(y/n)? ' varinput
	if [[ $varinput =~ ^[Yy]$ ]]; then
		org_setup
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
