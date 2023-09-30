#!/bin/sh
set -e
set -x

# Set default values for CUPSADMIN and CUPSPASSWORD
: "${CUPSADMIN:=cupsadmin}"
: "${CUPSPASSWORD:=$CUPSADMIN}"

# Create user if not exists
if [ "$(grep -ci "$CUPSADMIN" /etc/shadow)" -eq 0 ]; then
	adduser -S -G lpadmin --no-create-home "$CUPSADMIN"
fi
echo "$CUPSADMIN":"$CUPSPASSWORD" | chpasswd

# Create directories and perform cleanup
mkdir -p /config/ppd
mkdir -p /services
rm -rf /etc/avahi/services/*
rm -rf /etc/cups/ppd
ln -s /config/ppd /etc/cups

# Copy service files if they exist
if [ "$(ls -l /services/*.service 2>/dev/null | wc -l)" -gt 0 ]; then
	cp -f /services/*.service /etc/avahi/services/
fi

# Copy or create printers.conf
if [ "$(ls -l /config/printers.conf 2>/dev/null | wc -l)" -eq 0 ]; then
	touch /config/printers.conf
fi
cp /config/printers.conf /etc/cups/printers.conf

# Copy cupsd.conf if it exists and is non-empty
if [ "$(ls -l /config/cupsd.conf 2>/dev/null | wc -l)" -ne 0 ]; then
	cp /config/cupsd.conf /etc/cups/cupsd.conf
fi

# Function for handling file updates
printerUpdate() {
	/usr/bin/inotifywait -m -e close_write,moved_to,create /etc/cups |
		while read -r directory events filename; do
			case "$filename" in
			"printers.conf")
				rm -rf /services/AirPrint-*.service
				/root/airprint-generate.py -d /services
				cp /etc/cups/printers.conf /config/printers.conf
				rsync -avh /services/ /etc/avahi/services/
				;;
			"cupsd.conf")
				cp /etc/cups/cupsd.conf /config/cupsd.conf
				;;
			esac
		done
}

# Start avahi daemon and printerUpdate function
/usr/sbin/avahi-daemon --daemonize --no-drop-root
printerUpdate &
exec /usr/sbin/cupsd -f
