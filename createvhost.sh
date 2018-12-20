#!/bin/bash

VERSION=0.1

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -u|--username)
    USERNAME="$2"
    shift # past argument
    shift # past value
    ;;

    -d|--domain)
    DOMAIN="$2"
    shift # past argument
    shift # past value
    ;;

    -p|--phpversion)
    PHPVERSION="$2"
    shift # past argument
    shift # past value
    ;;

	-h|--help)
	help
	shift
	;;
#    --default)
#    DEFAULT=YES
#    shift # past argument
#    ;;

    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters



help () {
	echo "createvhost.sh version $VERSION.
Usage:
	-u | --username USERNAME 		Name of the user for: vhost, php-fpm pool, mariadb, owner of the document root.
	-d | --domain DOMAIN 			Name of the domain you would like to create: foobar.example.com.
	-p | --phpversion PHPVERSION	Version of php-fpm to use: 7.0, 7.1, 7.2.
	-h | --help 					Prints this help."
}


if [ -z $USERNAME ]
then
	echo "you need to set a username -u "
	help
	exit 2
fi
if [ -z $DOMAIN ]
then
	echo "you need to set a domain -d"
	help
	exit 2
fi
if [ -z $PHPVERSION ]
then
	echo "you need to set a php version -p"
	help
	exit 2
else
	if [[ "$PHPVERSION" != "7.2" && "$PHPVERSION" != "7.1" && "$PHPVERSION" != "7.0" ]]
	then
		echo "valid values for phpversion -p are 7.2, 7.1, 7.0, you have entered: $PHPVERSION"
		help
		exit 2
	fi
fi


VHOST=$DOMAIN
VHOSTDIR=/var/www/$DOMAIN

echo "creating directories..."
mkdir $VHOSTDIR
mkdir $VHOSTDIR/html
mkdir $VHOSTDIR/cgi-bin
mkdir $VHOSTDIR/logs
mkdir $VHOSTDIR/sockets
mkdir $VHOSTDIR/tmp

echo "creating user..."
useradd -d $VHOSTDIR -s /bin/bash $USERNAME
usermod -a -G $USERNAME www-data

echo "setting directory permissions..."
chown $USERNAME:$USERNAME -R $VHOSTDIR


echo "creating php pool..."
sed s/t_username/$USERNAME/g /root/scripts/template/php$PHPVERSION.conf > /tmp/conf
sed s/t_vhost/$VHOST/g /tmp/conf > /etc/php/$PHPVERSION/fpm/pool.d/$USERNAME.conf
rm /tmp/conf
service php7.2-fpm restart

echo "creating apache vhost..."
sed s/t_vhost/$VHOST/g /root/scripts/template/apachevhost.conf > /etc/apache2/sites-available/$VHOST.conf
a2ensite $VHOST.conf
service apache2 restart

echo "creating ssl certificate..."
certbot --authenticator webroot --installer apache --webroot-path /var/www/$VHOST/html/ -d $VHOST -d www.$VHOST certonly

echo "creating apache ssl vhost..."
sed s/t_vhost/$VHOST/g /root/scripts/template/ssl_apachevhost.conf >> /etc/apache2/sites-available/$VHOST.conf
service apache2 restart

echo "creating logrotate config..."
sed s/t_vhost/$VHOST/g /root/scripts/template/logrotate.conf > /tmp/log.conf
sed -i s/t_username/$USERNAME/g /tmp/log.conf
sed s/t_phpversion/$PHPVERSION/g /tmp/log.conf > /etc/logrotate.d/$VHOST.conf


echo "creating mysql database..."
PASSWORD=$(pwgen -n 16 1 )
mysql -e "create user '$USERNAME'@'localhost' IDENTIFIED BY '$PASSWORD'"
mysql -e "create database $USERNAME"
mysql -e "grant all privileges on $USERNAME.* TO '$USERNAME'@'localhost'"

echo "all done"
echo "MariaDB Username: $USERNAME"
echo "MariaDB Password: $PASSWORD"
echo "MariaDB Database: $USERNAME"

echo "[client]
user = $USERNAME
password = $PASSWORD
" >> /var/www/$VHOST/.my.cnf
