#!/bin/bash
## Vars
PID=
HALF_HOUR=$( expr 60 \* 30 )  # in seconds
LOGFILE=1hourlog
LOGTOFILE=true # true
STATSFILE=stats
IFACE=lo
TSPID=
CAPTURED=0
hr="============================"  # horizontal rule

logg(){
    # log * with timestamps
    if [ -n "$1" ] && [ $LOGTOFILE ]
    then
        echo `date "+%F %T"` "$1" >> $LOGFILE
    fi
}

get_pid_byname(){
    # if a name is passed in $1
    # search for the pid and put it in a recognizable var
    if [ "$1" ]
    then
        logg "Looking for \`$1\`"
        PID=$(ps -ax | pcregrep -o1 "^(\d+).*[ ]$1")
        logg "Found pid:$PID"
    else
        echo "Missing arguments in function \"get_pid_byname\""
        exit 1
    fi
}

# log start time

capture_packets(){
    logg "Start the capture_packets function"
    # start capturing packets for half an hour
    logg "Starting tshark on interface $IFACE"
    tshark -i $IFACE -p -q -z io,stat,0,BYTES > $STATSFILE &
    # save the pid of tshark
    TSPID=$!
    logg "tshark pid is $TSPID"
    # start falkon as a sign
    logg "Starting falkon"
    falkon 2>/dev/null &
    # sleep for half an hour
    logg "Going to sleep for $(expr $HALF_HOUR / 60 )min"
    sleep $HALF_HOUR
    # kill tshark
    logg "I'm awake"
    kill_tshark
}

kill_tshark(){
    if [ "$TSPID" ] && [ "ps -$TSPID" ]
    then
        logg "Killing tshark"
        kill $TSPID
        wait $TSPID
        # gather the stats and log it properly
        CAPTURED=$(pcregrep -o1 '\|\W+(\d+)\W\|' $STATSFILE)
        CAPTURED=$(echo "scale=3; $CAPTURED  / 1024 " | bc )
        logg ---
        logg "---> $CAPTURED KB in this iteration"
        logg ---
    fi
}

start_sshuttle(){
    # Vars to keep things mantainable
    SSCMD=sshuttle
    SSCONFIG=/home/jtriff/.sshuttle/config
    SSSUBNET=0/0
    SSOPTS='--syslog'
    if [[ "$IFACE" = 'lo' ]]
    then
        SSOPTS="$SSOPTS --remote ''"
    fi
    SSHUTTLE_CMD="$SSCMD @$SSCONFIG $SSSUBNET $SSOPTS"
    logg "Starting shuttle with command: \`$SSHUTTLE_CMD\`"
    SSON=false # var to verify that it really started
    attempt=0

    # try this until it starts
    until [ "$SSON" = 'client: Connected' ]
    do
        let "attempt += 1"
        # start transparent proxy sshuttle
        logg ---
        logg "Attempt $attempt"
        SSHUTTLE_START_T=`date "+%F %T"`
        $SSHUTTLE_CMD &
        # save the pid of sshuttle
        SSHUTTLEPID=$!
        logg "sshuttle PID:$SSHUTTLEPID"
        # 15 secs
        sleep 10
        # looking for the 'client: Connected' pattern inside journalctl
        logg "Ckecking SSH connection"
        SSHON=$(journalctl --identifier=sshuttle --since="$SSHUTTLE_START_T" --no-pager | pcregrep -o 'pledge: network')
        if [ "$SSHON" != 'pledge: network' ]
        then
            logg "process hasn't started properly, killing it"
            # kill the process
            # supress logs
            LOGTOFILE=
            kill_sshuttle_clean
            # continue with logs
            LOGTOFILE=1
        else
            until [ "$SSON" = 'client: Connected' ]
            do
                logg "Checking sshuttle connection"
                SSON=$(journalctl --identifier=sshuttle --since="$SSHUTTLE_START_T" --no-pager | pcregrep -o 'client: Connected')
                sleep 1
            done
        fi

        # # if it didn't start
        # if [ "$SSON" != 'client: Connected' ]
        
    done

}

clean_after(){
    echo 'Killed by user'
    logg 'Killed by user'
    logg 'Cleaning up'
    kill_tshark
    kill_sshuttle_clean
}

kill_sshuttle_clean(){
    # if there is a shhuttle pid
    if [ "$SSHUTTLEPID" ] && [ "ps --pid $SSHUTTLEPID" ]
    then
        logg 'Getting the tty of sshuttle'
        TTY=$( ps -A -F | pcregrep -o1 "$USER\W+$SSHUTTLEPID.* \d\d:\d\d ([a-zA-Z0-9/]+) " )
        logg "TTY of sshuttle is $TTY"
        logg 'killing it'
        kill $SSHUTTLEPID
        wait $SSHUTTLEPID
        logg 'looking for remaning processes on the same TTY'
        PIDs=$( ps -A -F | pcregrep -o1  "$USER\W+(\d+).* \d\d:\d\d $TTY .*[s]sh.*" )
        REMAININGCMD=$( ps -A -F | pcregrep -o2  "$USER\W+(\d+).* \d\d:\d\d $TTY .*\d\d:\d\d:\d\d (.*[s]sh.*)" )
        logg 'found this: --->'
        logg "$REMAININGCMD"
        logg '---'
        logg 'killing them'
        kill $PIDs
        wait $PIDs
        # for pid in $PIDs
        # do
        #     kill $pid
        #     wait $pid
        # done
    fi
}


trap clean_after TERM INT

# chk if an interface was passed
if [[ "$1" ]]
then    
    if [[ $(ifconfig | grep -w "$1") ]]
    then
        IFACE=$1
    else
        echo "The interface name that you passed is not a valid network interface"
        echo "Usage: $0 [network-interface]"
        exit
    fi
fi


logg $hr

totalTime=$(expr $HALF_HOUR \* 2 / 60 )
logg "Starting $totalTime mins of capture"

logg "===> Starting with proxy"
start_sshuttle
capture_packets
logg "Killing proxy"
kill_sshuttle_clean

logg "===> Starting DIRECT"
capture_packets

logg "Killing falkon to finnish"
get_pid_byname falkon
kill $PID


exit
