#!/bin/bash

## Variables
IFACE=enp0s20f0u1
STATSFILE=stats
DOWNLOADSRV='https://raw.githubusercontent.com/jjtriff/files/master/'
DOWNLOADFLS='100k 200k'
TSPID=0
CAPTURED=0

# do a serie of tests while monitoring traffic with tshark
# start tshark in bg, its PID will be stored in $!
tshark -i $IFACE -p -q -z io,stat,0,BYTES > $STATSFILE &
TSPID=$!
# do the curl tests or whatever other dowload process you may like
for f in $DOWNLOADFLS 
do
    curl -o /dev/null -4 $DOWNLOADSRV$f
done
# stop tshark
kill $TSPID
wait $TSPID  # give it a chance to end
# extract the amount of bytes captured
CAPTURED=$(pcregrep -o1 '\|\W+(\d+)\W\|' $STATSFILE)
echo "$CAPTURED bytes were exchanged"

exit
