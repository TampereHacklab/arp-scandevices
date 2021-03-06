#!/bin/bash
# Tutkailee lähiverkosta laitteiden saapumisia ja lähtemisiä. Väsäsi poro trehacklabin käyttöön 12/2020
# sudo apt-get install arp-scan

iface="eth1"					# network interface for scanning the devices
gonesec=90					# mark device away if hasn't seen for x seconds
iprange="192.168.10.10-192.168.10.200"		# hacklab dhcp range

#####

ip link set $iface promisc on			# reduce "device x entered promiscuous mode" whine in dmesg..

declare -A devices				# all devices, mac address as a key, timestamp as a value
declare -A ipslist				# we need IP addresses too
declare -A status				# current status of the device: "here" or "" if gone/undefined

if [ ! -f macblacklist ]
then
	touch macblacklist
fi

while [ 0 ]; do
	# ARP-scan devices between $iprange and parse its results:
	nearcount=0
	while read i; do
		ip=$(echo $i|awk '{print $1}')
		mac=$(echo $i|awk '{print $2}')

		if ! grep -qi "^$mac" macblacklist; then
			((nearcount=nearcount+1))
			devices[$mac]=$(date +%s)		# update device's last seen
			ipslist[$mac]=$ip
		else
			if [ -n "${devices[$mac]}" ]; then
				unset devices[$mac]
				unset ipslist[$mac]
			fi
		fi
	done < <(arp-scan --timeout=1500 --retry=2 --ignoredups --numeric --plain --quiet --interface=$iface $iprange)

	# Track status changes:
	for i in ${!devices[*]}; do
		lastseen=$(expr $(date +%s) - ${devices[$i]})	# how long since last seen?

		echo -n "$i  |  IP:${ipslist[$i]}  |  Lastseen:${lastseen}s  |  Status:${status[$i]} "

		if [ "${status[$i]}" == "" ]; then		# device responded to arp scan, change status from "away" to "near"
			if (( $lastseen <= 2 )); then
				echo -n "Arrived!"
				status[$i]="Near"
				#curl https://127.0.0.1/here/$i
			fi
		else
			if (( $lastseen >= $gonesec )); then	# lately "near" device hasn't responded to arp-scans for over $gonesec, make it go "away"
				if ping -q -n -W3 -c2 ${ipslist[$i]} >/dev/null 2>&1; then
					echo -n "Ping says still here!?"
				else
					echo -n "Has left the building!"
					status[$i]=""
					#curl https://127.0.0.1/away/$i
				fi
			fi
		fi
		echo ""
	done

	echo "$(date) Devices replied to arp-scan: $nearcount. Devices total: ${#devices[@]}"
	echo "----------------------------------------------------------------------"

	sleep 15	# re-scan interval
done
