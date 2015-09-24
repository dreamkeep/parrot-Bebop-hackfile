#! /bin/sh

name="$(basename $0)"

source /bin/ardrone3_shell.sh

WIFI_DHCP_CONF="/etc/udhcpd.conf.eth0"
WIFI_DHCP_CMD="udhcpd $WIFI_DHCP_CONF"
IFACE_NAME="eth0"
IFACE_IP_AP="192.168.42.1"

CURRENT_TTY=$(tty)
if [ $? -ne 0 -o "${CURRENT_TTY}" = "" ]; then
    CURRENT_TTY=/dev/console
fi

exec 2>${CURRENT_TTY}

# ######################################
# #######  FUNCTIONS  ##################
# ######################################
print_info ()
{
    logger -s -t ${name} -p user.info "$@"
}

print_error ()
{
    logger -s -t ${name} -p user.err "ERROR: $@"
}

dir=$(dirname ${NET_STATE_WIFI_BCM})
[ ! -d ${dir} ] && mkdir -p ${dir}

wifi_state_change ()
{
    print_info "WIFI BCM NEW STATE : $@"
    echo "$@" > ${NET_STATE_WIFI_BCM}
}

tmpmac_file="/tmp/mac_address.txt"

generate_mac_address()
{
  #
  # Generate MAC address from
  #  address stored in factory
  #  serial number
  #  random number

  if [ -f ${FACTORY_SERIAL_FILE} ]; then
      SERIAL_NUMBER=$(cat ${FACTORY_SERIAL_FILE})
  fi

  if [ ! -z ${SERIAL_NUMBER} ]
  then
    SN=$(( 1$(echo -n ${SERIAL_NUMBER} | tail -c 6)-1000000 ))
  else
    SN=$(( 0x$(cat /dev/urandom |hexdump -d | sed s/\ //g |dd bs=5 count=1 skip=2 2>/dev/null) ))
  fi

  HB="[0-9a-fA-F]{2}"
  FACTORYMAC=$(cat ${FACTORY_MAC_ADDR_FILE} 2>/dev/null | egrep -o "${HB}:${HB}:${HB}:${HB}:${HB}:${HB}")
  if [ ! -z ${FACTORYMAC} ]; then
    HWADDR=${FACTORYMAC}
  else
    HWADDR=$(printf "A0:14:3D:%02X:%02X:%02X" $(( (SN >> 16) & 0x00FF )) $(( (SN >> 8) & 0x00FF )) $(( SN & 0x00FF )) )
  fi

  echo -n ${HWADDR} >${tmpmac_file}
}

# BCM kernel modules
mod_bcm_dbus="/lib/modules/extra/bcm_aard/bcm_dbus.ko"
mod_wl="/lib/modules/extra/bcm_aard/wl.ko"

load_module ()
{
if [ ! -f ${mod_bcm_dbus} -o ! -f ${mod_wl} ]
    then
      print_error "BCM modules are not available. Wifi unavailable."
      return 1
    fi

    generate_mac_address

    # Load module and bring the interface up.
    insmod ${mod_bcm_dbus}
    RES0=$?
    insmod ${mod_wl}
    RES1=$?

    if [ $RES0 -ne 0 -o $RES1 -ne 0 ]; then
        RES=1
    else
        RES=0
    fi

    return $RES
}

go_to_band_in_US_mode()
{
    wanted_band=$1
    wanted_country=$2
    print_info "go_to_band_in_US_mode : wanted_band: $wanted_band ; wanted_country: $wanted_country"

    bcmwl down
    bcmwl country US
    bcmwl band $wanted_band
    apply_country_with_revision $NEW_COUNTRY
    bcmwl up
}

manage_country_allowed_channels ()
{
    if [ $# -eq 0 ]; then
        _COUNTRY=`bcmwl country | cut -d ' ' -f 1`
    else
        _COUNTRY=$1
    fi

    current_band=`bcwml band`
    bcmwl band auto
    CHANNELS_2_4GHZ=`bcmwl chan_info | grep -i "B Band"`
    CHANNELS_5GHZ=`bcmwl chan_info | grep -i "A Band"`
    bcmwl band $current_band

    FORCE_SETTINGS=0
    band_in_settings=`grep wifi_band ${DRAGON_CONF} | awk -F ':' '{print $2+0}'`
    if [ $band_in_settings -eq 0 ]; then
        if [ "$CHANNELS_2_4GHZ" = "" ]; then
            print_info " No channels for 2.4GHz for this country ($_COUNTRY)"
            FORCE_SETTINGS=1
            FORCE_BAND=1
            FORCE_CHAN=36

            # No channels in 2.4GHz, force band 5GHz
            go_to_band_in_US_mode a $_COUNTRY
        fi
    else
        if [ "$CHANNELS_5GHZ" = "" ]; then
            print_info " No channels for 5GHz for this country ($_COUNTRY)"
            FORCE_SETTINGS=1
            FORCE_BAND=0
            FORCE_CHAN=6

            # No channels in 5GHz, force band 2.4GHz
            go_to_band_in_US_mode b $_COUNTRY
        fi
    fi

}

apply_country_with_revision ()
{
    country_to_apply=$1
    /usr/bin/dragon-prog --bcm_country_rev $country_to_apply >/dev/null 2>&1
    revision=$?
    if [ $revision -eq 255 ]; then
        echo "####################################"
        echo "### Wifi ERROR : Unknown country"
        echo "### \"$country_to_apply\""
        echo "####################################"
    else
        bcmwl country "$country_to_apply/$revision"
    fi
}

channels_list_on_2_4GHz="1 2 3 4 5 6 7 8 9 10 11 12 13 14"
channels_list_on_5GHz="36 40 44 48 52 56 60 64 100 104 108 112 116 132 136 140 144 149 153 157 161 165"

is_a_valid_channel()
{
    for i in $2
    do
        if [ $i = $1 ]
        then
            echo "true"
            return 0
        fi
    done

    echo "false"
    return 1
}

wifi_config_driver()
{
  print_info "Disable Roaming"
  bcmwl roam_off 1

  print_info "Set STBC mode"
  bcmwl stbc_rx 1
  bcmwl stbc_tx -1

  print_info "Set Core Chains"
  bcmwl rxchain 3
  bcmwl txchain 3
  #bcmwl txcore -s 3 -c 0x7

  print_info "Set Retries"
  bcmwl lrl 6
  bcmwl srl 7

  print_info "Set Bandwidth"
  bcmwl mimo_bw_cap 0
  bcmwl bw_cap 2g 0x1
  bcmwl bw_cap 5g 0x1

  print_info "Disable Aggregation"
  #bcmwl wme 0
  #bcmwl ampdu 2
  #bcmwl ampdu_tx 2
  #bcmwl ampdu_rx 2

  print_info "Set Fragmentation"
  #bcmwl fragthresh 300

  print_info "Set DTIM period"
  bcmwl dtim 1
}

wifi_config_parsing()
{
  autoselect_mode=`grep wifi_autoselect_mode ${DRAGON_CONF} | cut -d ':' -f 2 | cut -d '"' -f 2`
  band=`grep wifi_band ${DRAGON_CONF} | awk -F ':' '{print $2+0}'`
  chan=`grep wifi_channel ${DRAGON_CONF} | awk -F ':' '{print $2+0}'`

  if [ $autoselect_mode = "2.4GHz" ]
  then
      (
      echo "Mode 2.4 GHz"
      bcmwl band b
      bcmwl chanspec 6/20
      if [ $(is_a_valid_channel $chan "$channels_list_on_2_4GHz") = "true" ]
      then
          bcmwl chanspec $chan/20
      fi
      ) | logger -s -t ${name} -p user.info
  elif [ $autoselect_mode = "5GHz" ]
  then
      (
      echo "Mode 5 GHz"
      bcmwl band a
      bcmwl chanspec 40/20
      bcmwl dfs_channel_forced 40
      if [ $(is_a_valid_channel $chan "$channels_list_on_5GHz") = "true" ]
      then
          bcmwl chanspec $chan/20
          bcmwl dfs_channel_forced $chan
      fi
      ) | logger -s -t ${name} -p user.info
  else
      if [ $band -eq 0 ]
      then
          (
          echo "Band 2.4 GHz"
          bcmwl band b
          bcmwl chanspec 6/20
          if [ $(is_a_valid_channel $chan "$channels_list_on_2_4GHz") = "true" ]
          then
              bcmwl chanspec $chan/20
          fi
          ) | logger -s -t ${name} -p user.info
      elif [ $band -eq 1 ]
      then
          (
          echo "Band 5 GHz"
          bcmwl band a
          bcmwl chanspec 40/20
          bcmwl dfs_channel_forced 40
          if [ $(is_a_valid_channel $chan "$channels_list_on_5GHz") = "true" ]
          then
              bcmwl chanspec $chan/20
              bcmwl dfs_channel_forced $chan
          fi
          ) | logger -s -t ${name} -p user.info
      fi
  fi
}

wifi_wait_for_scan_ending()
{
  scan_duration_limit_s=5
  sleep_duration_ms=100000

  max_sleep_nb=$((scan_duration_limit_s*1000000/sleep_duration_ms))

  print_info "Scanning..."

  cpt=0
  bcmwl scanresults > /dev/null 2> /dev/null

  while ( [ $? -ne 0 ] && [ $cpt -lt $max_sleep_nb ] )
  do
      cpt=$((cpt+1))
      usleep $sleep_duration_ms
      bcmwl scanresults > /dev/null 2> /dev/null
  done
}

create_access_point_for_country ()
{
    country=$1

    wifi_config_driver

    if [ ! -f ${tmpmac_file} ]
    then
        generate_mac_address
    fi

    HWADDR=$(cat ${tmpmac_file})

    print_info "Set MAC address ${HWADDR}"
    ifconfig ${IFACE_NAME} hw ether ${HWADDR}

    sed -i "s/\"auto_country\" : 0,/\"auto_country\" : 1,/" ${DRAGON_CONF}
    sed -i "s/\"country_code\" : \".*\",/\"country_code\" : \"$country\",/" ${DRAGON_CONF}

    bcmwl autocountry 0
    bcmwl autocountry_default $country
    apply_country_with_revision $country | logger -s -t ${name} -p user.info

    ACTUAL_COUNTRY=`bcmwl country | cut -d '(' -f 2 | cut -d ')' -f 1`
    print_info "The actual country is $ACTUAL_COUNTRY"

    (
        echo -n "The actual power is:"
        bcmwl txpwr1
    ) | logger -s -t ${name} -p user.info

    print_info "Start AP..."
    bcmwl ap 1

    wifi_config_parsing

    ENABLE_SET_DATARATES=1
    if [ $ENABLE_SET_DATARATES -eq 1 ]; then
    (
        echo -n "Set Datarates"
        band=`grep wifi_band ${DRAGON_CONF} | awk -F ':' '{print $2+0}'`
        bcmwl down
        if [ $band -eq 0 ]
        then
            echo "     MCS[0-7] + 6 legacy"
            bcmwl down ; bcmwl band a ; bcmwl rateset 6b -m 0xFF ; bcmwl up ; bcmwl down ; bcmwl band b ; bcmwl rateset 6b -m 0xFF ; bcmwl up

        elif [ $band -eq 1 ]
        then
            echo "     MCS[0-7] + 6 legacy"
            bcmwl down ; bcmwl band b ; bcmwl rateset 6b -m 0xFF ; bcmwl up ; bcmwl down ; bcmwl band a ; bcmwl rateset 6b -m 0xFF ; bcmwl up
        fi
        bcmwl up
    ) | logger -s -t ${name} -p user.info
    fi

    ssid=$(grep product_name ${DRAGON_CONF} | cut -d ':' -f 2- | cut -d '"' -f 2)

    (
        echo "Setting SSID to ${ssid}"
        bcmwl ssid ${ssid}
    ) | logger -s -t ${name} -p user.info

    print_info "Disable RTS/CTS"
    bcmwl rtsthresh 2347
    bcmwl ampdu_rts 0
    (
        bcmwl gmode_protection 0
        bcmwl gmode_protection_control 0
        bcmwl gmode_protection_override 0
    ) 2>&1 | logger -s -t ${name} -p user.info

    print_info "Set Long Guard Interval"
    bcmwl sgi_rx 0
    bcmwl sgi_tx 0

    # Start Wifi
    print_info "Up BCM interface..."
    ifconfig ${IFACE_NAME} ${IFACE_IP_AP} up
    if ! [ $? -eq 0 ]; then
        print_error "Interface ${IFACE_NAME} could not be brought up. Bail out."
        rmmod wl
        rmmod bcm_dbus
        print_info "WIFI BCM FAILED"
        exit 3
    fi

    print_info "Starting server..."
    $WIFI_DHCP_CMD

    print_info "WIFI BCM OK"
}

create_access_point ()
{
    wifi_config_driver

    if [ ! -f ${tmpmac_file} ]
    then
      generate_mac_address
    fi

    HWADDR=$(cat ${tmpmac_file})

    print_info "Set MAC address ${HWADDR}"
    ifconfig ${IFACE_NAME} hw ether ${HWADDR}

    # Auto country management:
    bcmwl down
    autoselect_mode=`grep wifi_autoselect_mode ${DRAGON_CONF} | cut -d ':' -f 2 | cut -d '"' -f 2`
    country_in_settings=`grep country_code ${DRAGON_CONF} | cut -d ':' -f 2 | cut -d '"' -f 2`

    # Put band auto so that scan will scan on all bands.
    bcmwl band auto
    # Put country US to do scan... Because some countries have issues for scanning...
    bcmwl country US
    # If autocountry does not find anything: use "country_in_settings"
    bcmwl autocountry_default $country_in_settings

    autocountry_mode=`grep auto_country ${DRAGON_CONF} | awk -F ':' '{print $2+0}'`
    if [ "$autocountry_mode" = "" ]; then
        autoselect_mode=`grep wifi_autoselect_mode ${DRAGON_CONF} | cut -d ':' -f 2 | cut -d '"' -f 2`
        if [ $autoselect_mode != "none" ]; then
            autocountry_mode=1
        else
            autocountry_mode=0
        fi
    fi

    if [ "$autocountry_mode" = "1" ]; then
        print_info "Use BCM autocountry"
        bcmwl autocountry 1
        bcmwl up
        bcmwl scan
        wifi_wait_for_scan_ending # At most 5 seconds...
        NEW_COUNTRY=`bcmwl country | cut -d ' ' -f 1`
        echo "=> NEW_COUNTRY : $NEW_COUNTRY" | logger -s -t ${name} -p user.info
        apply_country_with_revision $NEW_COUNTRY | logger -s -t ${name} -p user.info
        sed -i "s/\"country_code\" : \".*\",/\"country_code\" : \"$NEW_COUNTRY\",/" ${DRAGON_CONF}
    else
        print_info "Do NOT use BCM autocountry"
        bcmwl autocountry 0
        apply_country_with_revision $country_in_settings | logger -s -t ${name} -p user.info
        bcmwl up
    fi

    ACTUAL_COUNTRY=`bcmwl country | cut -d '(' -f 2 | cut -d ')' -f 1`
    print_info "The actual country is $ACTUAL_COUNTRY"

    (
      echo -n "The actual power is:"
      bcmwl txpwr1
    ) | logger -s -t ${name} -p user.info

    print_info "Start AP..."
    bcmwl ap 1

    wifi_config_parsing

    ENABLE_SET_DATARATES=1
    if [ $ENABLE_SET_DATARATES -eq 1 ]; then
        (
        echo -n "Set Datarates"
        band=`grep wifi_band ${DRAGON_CONF} | awk -F ':' '{print $2+0}'`
        bcmwl down
        if [ $band -eq 0 ]
        then
            echo "     MCS[0-7] + 6 legacy"
            bcmwl down ; bcmwl band a ; bcmwl rateset 6b -m 0xFF ; bcmwl up ; bcmwl down ; bcmwl band b ; bcmwl rateset 6b -m 0xFF ; bcmwl up

        elif [ $band -eq 1 ]
        then
            echo "     MCS[0-7] + 6 legacy"
            bcmwl down ; bcmwl band b ; bcmwl rateset 6b -m 0xFF ; bcmwl up ; bcmwl down ; bcmwl band a ; bcmwl rateset 6b -m 0xFF ; bcmwl up
        fi
        bcmwl up
        ) | logger -s -t ${name} -p user.info
    fi

    ssid=$(grep product_name ${DRAGON_CONF} | cut -d ':' -f 2- | cut -d '"' -f 2)

    (
      echo "Setting SSID to ${ssid}"
      bcmwl ssid ${ssid}
    ) | logger -s -t ${name} -p user.info

    print_info "Disable RTS/CTS"
    bcmwl rtsthresh 2347
    bcmwl ampdu_rts 0
    (
      bcmwl gmode_protection 0
      bcmwl gmode_protection_control 0
      bcmwl gmode_protection_override 0
    ) 2>&1 | logger -s -t ${name} -p user.info

    print_info "Set Long Guard Interval"
    bcmwl sgi_rx 0
    bcmwl sgi_tx 0

    # Start Wifi
    print_info "Up BCM interface..."
    ifconfig ${IFACE_NAME} ${IFACE_IP_AP} up
    if ! [ $? -eq 0 ]; then
        print_error "Interface ${IFACE_NAME} could not be brought up. Bail out."
        rmmod wl
        rmmod bcm_dbus
        print_info "WIFI BCM FAILED"
        exit 3
    fi

    print_info "Starting server..."
    $WIFI_DHCP_CMD

    print_info "WIFI BCM OK"
}

generate_wifi_exception ()
{
    subject="$1"
    echo "${subject}" > /tmp/generic_subject.txt
    sha1=`sha1sum /tmp/generic_subject.txt | awk '{split($0,a," "); print a[1]}'`
    desc="$2"

    echo -e "${sha1}\n${subject}\n${desc}\n" > /data/exceptions/generic_wifi_crash
}
# ######################################
# #######  SCRIPT  #####################
# ######################################

if [ $# -eq 0 ]; then
    print_info " No command... => stops (Possible command are: insmod , rmmod , create_net_interface , remove_net_interface, status )"
    exit 1
else
    BCM_SCRIPT_CMD=$1
fi

print_info "($@) : CURRENT_TTY = ${CURRENT_TTY}"

case $BCM_SCRIPT_CMD in
    insmod)
        print_info "Load Modules :"
        load_module
        if [ $? -eq 0 ]; then
            wifi_state_change "WIFI_BCM_DRIVER_LOADED"
        else
            wifi_state_change "WIFI_BCM_DRIVER_LOADING_FAILED"
        fi
        exit 0
        ;;
    rmmod)
        print_error ""
        print_error " ############################################ "
        print_error " ######       CAUTION : ERROR          ###### "
        print_error " ###### BROADCOM DISAPEARED ON USB !!! ###### "
        print_error " ############################################ "
        print_error ""
        print_info "Unload Modules :"
        # XXX What do we do?
        rmmod wl
        rmmod bcm_dbus
        print_info ""
        wifi_state_change "WIFI_BCM_UNPLUGGED"
        generate_wifi_exception "BROADCOM Wifi chipset disapeared on USB !!!" "wifi chipset is dead and must be reseted"
        exit 0
        ;;
    create_net_interface)
        print_info "Create Access Point :"
        if [ -e $FACTORY_COUNTRY_SETTING_FILE ]
        then
            country=$(cat $FACTORY_COUNTRY_SETTING_FILE)
            bcmwl country $country
            error=$(echo $?)
            if [ $error -ne 0 ]
            then
                create_access_point
            else
                create_access_point_for_country $country
            fi
        else
            create_access_point
        fi
        mkdir -p $(dirname ${NET_WIFI_BCM_STARTED})
        touch ${NET_WIFI_BCM_STARTED}
        wifi_state_change "WIFI_BCM_ACCESS_POINT_OK"
        exit 0
        ;;
    remove_net_interface)
        # XXX What do we do?

        # Stop dhcp :
        UDHCP_PID=`ps | grep "$WIFI_DHCP_CMD" | grep -v grep | awk -F " " '{print $1}'`
        if [ -z $UDHCP_PID ]; then
            print_info "No UDHCP_PID found for wifi..."
        else
            print_info "Kill dhcp for wifi... (PID = $UDHCP_PID)"
            kill -9 $UDHCP_PID
        fi

        # Reset Broadcom Wifi chipset :
        broadcom_setup.sh reboot
        rm -f ${NET_WIFI_BCM_STARTED}
        wifi_state_change "WIFI_BCM_OFF"
        exit 0
        ;;
    reboot)
        print_info ""
        print_info " ## Reboot broadcom module ## "
        print_info ""
        bcmwl reboot
        (echo 1 > /sys/class/gpio/gpio9/value) > /dev/null 2>&1
        (echo 0 > /sys/class/gpio/gpio9/value) > /dev/null 2>&1
        ;;
    status)
        print_info "Status: ${NET_STATE_WIFI_BCM} $(cat ${NET_STATE_WIFI_BCM})"
        iwconfig ${IFACE_NAME}
        bcmwl status
        echo "Country: $(bcmwl country)"
        echo "Auto Country: $(bcmwl autocountry)"
        ;;
    *)
        print_info "Unknown Command..."
        exit 1
        ;;
esac
