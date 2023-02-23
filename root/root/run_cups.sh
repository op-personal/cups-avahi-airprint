#!/bin/sh
set -e
set -x

# Is CUPSADMIN set? If not, set to default
if [ -z "$CUPSADMIN" ]; then
    CUPSADMIN="cupsadmin"
fi

# Is CUPSPASSWORD set? If not, set to $CUPSADMIN
if [ -z "$CUPSPASSWORD" ]; then
    CUPSPASSWORD=$CUPSADMIN
fi

if [ "$(grep -ci "$CUPSADMIN" /etc/shadow)" -eq 0 ]; then
    adduser -S -G lpadmin --no-create-home "$CUPSADMIN" 
fi
echo "$CUPSADMIN":"$CUPSPASSWORD" | chpasswd

mkdir -p /config/ppd
mkdir -p /services
rm -rf /etc/avahi/services/*
rm -rf /etc/cups/ppd
ln -s /config/ppd /etc/cups
if [ "$(ls -l /services/*.service 2>/dev/null | wc -l)" -gt 0 ]; then
	cp -f /services/*.service /etc/avahi/services/
fi
if [ "$(ls -l /config/printers.conf 2>/dev/null | wc -l)" -eq 0 ]; then
    touch /config/printers.conf
fi
cp /config/printers.conf /etc/cups/printers.conf

if [ "$(ls -l /config/cupsd.conf 2>/dev/null | wc -l)" -ne 0 ]; then
    cp /config/cupsd.conf /etc/cups/cupsd.conf
fi

printer-update () {
/usr/bin/inotifywait -m -e close_write,moved_to,create /etc/cups | 
while read -r directory events filename; do
	if [ "$filename" = "printers.conf" ]; then
		rm -rf /services/AirPrint-*.service
		/root/airprint-generate.py -d /services
		cp /etc/cups/printers.conf /config/printers.conf
		rsync -avh /services/ /etc/avahi/services/
	fi
	if [ "$filename" = "cupsd.conf" ]; then
		cp /etc/cups/cupsd.conf /config/cupsd.conf
	fi
done
}

/usr/sbin/avahi-daemon --daemonize --no-drop-root
printer-update & exec /usr/sbin/cupsd -f
