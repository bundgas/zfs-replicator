#!/bin/sh
# ZFS replicator v. 0.9.1 - By Kenneth Lutzke - kml@bundgas.dk
# ----------------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 42):
# <kml@bundgas.dk> wrote this file. As long as you retain this notice you
# can do whatever you want with this stuff. If we meet some day, and you think
# this stuff is worth it, you can buy me a beer in return. -Kenneth Lutzke
# ----------------------------------------------------------------------------
# DISCLAIMER: YOU RUN THIS AT YOUR OWN RISK!!! If you don't agree, don't run this script.
# ----------------------------------------------------------------------------
# USAGE (should be used with crontab): zfs-replicator.sh <generation-name> <number of snapshots to keep>
#
# This script recursively snapshots a given pool, and replicates it to another host (slave). It supports grandfathering schemes (generations)
# on both master and slave (mirrored), all controlled from the master with this script and crontab.
# Only the first snapshot will be sent in 100% size, all following snapshots will be sent incrementally.
#
# If the slave is down, or the script is already running (ex. in case of a big initial sync that takes time), a snapshot will still be taken,
# and it will be synced with other missed snapshots when the slave is up and the script is not already running. While the slave is down or the
# script is already running, no cleaning will be done on the master or the slave, so snapshots will build up on the master until the slave is
# synced again. As soon as the master and slave are in sync again, cleaning will kick in and obey the keep rule(s).
#
# BE VERY CAREFUL WITH "zfs destroy -r":
# If you destroy a filesystem on the master, it will destroy the filesystem on the slave too, including all the snapshots (across all generations)
# for that filesystem, with a single run of the script. This is as intended, as it is the way recursive zfs send and receive work, and as it comes
# in handy when you really want the data deleted forever. So if you need the snapshots kept, don't destroy the filesystem, delete the data inside
# the filesystem instead, and destroy it when it has "trickeled through" your generations.
#
# You can create manual snapshots on the master, as long as you don't name your snapshot with the same prefix as in this script. If you create a
# snapshots on the slave, it will be destroyed as soon as this script is run again. This is how ZFS recursive send/receive works...
#
# For this script to work, you need to do the following things:
# - ssh keys with no passphrase must first be set up so that a user (ex. root) can ssh from the master to the slave without being prompted for login.
# - create a pool with the same name as the master-pool, that you want replicated, on the slave.
#
# Example of use with crontab (*1min schedule should only be used for testing, or on pools with few filesystems and low io).
#
# 1-4/1,6-9/1,11-14/1,16-19/1,21-24/1,26-29/1,31-34/1,36-39/1,41-44/1,46-49/1,51-54/1,56-59/1 * * * *  root    /root/zfs-replicator.sh 1min 5
# 5,10,20,25,35,40,50,55 * * * *           root   /root/zfs-replicator.sh 5min 3
# 15,30,45 * * * *                         root   /root/zfs-replicator.sh 15min 4
# 0 1-5,7-11,13-17,19-23 * * *             root   /root/zfs-replicator.sh 1hour 6
# 0 0,6,12,18 * * *                        root   /root/zfs-replicator.sh 6hour 9
#
# The example is set on FreeBSD. On Linux you might need to remove "root" in front of the command entry.
# This would give you 1 snapshot every minute for 5 minutes, 1 snapshot every 5 minutes for 15 minutes, 1 snapshot every 15 minutes for 1 hour,
# 1 snapshot every hour for 6 hours, and 1 snapshot every 6 hours for 2 days* (* 2 day = 8 snapshots. The 9 in the example is because you need
# one extra snapshot in the end to be able to go 2 whole days back, or that snapshot will just have have been destroyed, and you could now only
# go 1 day and 18 hours back. This is not a problem for 1min, 5min, 15min or 1hour schedules in the above example, as they all overlap 1 snapshot
# with the next generation. Because of the way cleaning doesn't interfere with other generations, there will sometimes be leftover snapshots,
# where the generations overlap, but they will be automatically cleaned up on the next run of the script with that generation.
#
# * 1min schedule will most likely only work smoothly with very few filesystems with nearly no writing IO, as it can take some time to sync each 
# filesystem. This would give you a lot of overlapping script-executions, and you will end up with a snapshot backlog, which would probably
# result in even more overlapping script-executions, and so on. Adjust your lowest snapshot increment so that there on average is enough time to
# transfer everything incrementally to the slave. Because the script picks up snapshots missed for transfer on the next round, it is ok if it
# doesn't make it on time every time, but if your increments are set too often, you are probably in for a bumpy ride.
#
# The script outputs a log and monitor output. The monitor output can be used for monitoring software such as Nagios.
# It uses arcfour128 as ssh cipher. 
#
# If you want to be extra sure that you get monitor-output if the script fails, run it in crontab like this:
# 15,30,45 * * * *  root   /root/zfs-replicator.sh 15min 4 || echo "CRITICAL - Sync script failed - Check manually!!!" >> /path/to/monitor-file
# ----------------------------------------------------------------------------

sleep 1
PATH=/usr/bin:/sbin:/bin

##### CONFIG #####

pool="tank"   # Pool to replicate
host="172.16.0.42"   # Slave address.
user="root"   # User to ssh to slave.
prefix="autosnap"   # Prefix for main snapshot name (will be the same for all generations).
logfile="/var/log/zfs-replicator.log"   # Main logfile. Put this somewhere with log rotation.
lastsucclog="/root/tmp/zfs-replicator-last-successful.log"   # For script to know last successful transfer. Put this somewhere that is persistant over reboots.
lockfile="/tmp/zfs-replicator.lock"   # Script lock file. Put this in /tmp/
monitor_output="/root/tmp/zfs-replicator-monitor.txt"   # Output file for monitoring software (Nagios or other).
monitor_warn_prefix="WARNING -" # Prefix for monitor software (ex. Nagios). Just leave as is if you don't know what to put here.
monitor_critical_prefix="CRITICAL -" # Prefix for monitor software (ex. Nagios). Just leave as is if you don't know what to put here.

##### /CONFIG #####

# check logfiles
if [ ! -f $logfile ]; then
 echo "Logfile: $logfile doesn't exist - Trying to touch"
 if ! touch $logfile; then
  echo "Cannot create $logfile - Please create the directory-structure manually"
  exit 1
 fi
fi

if [ ! -f $lastsucclog ]; then
 echo "Logfile: $lastsucclog doesn't exist - Trying to touch"
 echo "Logfile: $lastsucclog doesn't exist - Trying to touch" >> $logfile
 if ! touch $lastsucclog; then
  echo "Cannot create $lastsucclog - Please create the directory-structure manually"
  echo "Cannot create $lastsucclog - Please create the directory-structure manually" >> $logfile
  echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting with exit code 1" >> $logfile
  exit 1
 fi
fi

if [ ! -f $monitor_output ]; then
 echo "Logfile: $monitor_output doesn't exist - Trying to touch"
 echo "Logfile: $monitor_output doesn't exist - Trying to touch" >> $logfile
 if ! touch $monitor_output; then
  echo "Cannot create $monitor_output - Please create the directory-structure manually"
  echo "Cannot create $monitor_output - Please create the directory-structure manually" >> $logfile
  exit 1
 fi
fi

# check inputs
if [ -z "$1" ]; then
 echo "`date +"%Y-%m-%d %H:%M:%S"` - no generation defined. Execute this script with name of the generation. Ex: './zfs-replicator.sh hourly 12' would name this generation 'hourly'"
 echo "`date +"%Y-%m-%d %H:%M:%S"` - no generation defined. Execute this script with name of the generation. Ex: './zfs-replicator.sh hourly 12' would name this generation 'hourly'" >> $logfile
 echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting with exit code 1" >> $logfile
 exit 1
fi

if [ -z "$2" ]; then
 echo "`date +"%Y-%m-%d %H:%M:%S"` - no keep rule defined. Execute this script with the number of this generation to keep. Ex: './zfs-replicator.sh hourly 12' would keep 12 snapshots of the generation 'hourly'"
 echo "`date +"%Y-%m-%d %H:%M:%S"` - no keep rule defined. Execute this script with the number of this generation to keep. Ex: './zfs-replicator.sh hourly 12' would keep 12 snapshots of the generation 'hourly'" >> $logfile
 echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting with exit code 1" >> $logfile
 exit 1
fi

snapname="$1"
keep="$2"

echo "`date +"%Y-%m-%d %H:%M:%S"` - Script started - Checks are OK" >> $logfile

# Check if snapshot already exists on master
now=`date +"%Y-%m-%d_%H.%M"`
snapshot_now="$pool@$prefix-$snapname-$now"

if zfs list -H -o name -t snapshot | sort | grep -e "$snapshot_now$" > /dev/null; then
 echo "`date +"%Y-%m-%d %H:%M:%S"` - $snapshot_now, already exists on master" >> $logfile
 echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting" >> $logfile
 echo "$monitor_critical_prefix $snapshot_now, already exists on master. Something is wrong." > $monitor_output
 exit 0
fi

# take a snapshot
if zfs snapshot -r $snapshot_now >> $logfile; then
 echo "`date +"%Y-%m-%d %H:%M:%S"` - Snapshot $snapshot_now taken" >> $logfile
else
 echo "`date +"%Y-%m-%d %H:%M:%S"` - Couldn't take snapshot. Check your pool" >> $logfile
 echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting" >> $logfile
 echo "$monitor_critical_prefix Couldn't take snapshot. Check your pool." > $monitor_output
 exit 0
fi

# Check if slave is online
if ssh $user@$host hostname > /dev/null; then
 echo "`date +"%Y-%m-%d %H:%M:%S"` - $host (slave) is up" >> $logfile
 slavestatus="up"
else
 echo "`date +"%Y-%m-%d %H:%M:%S"` - $host is down - doing only local snapshot - snapshot $snapshot_now will be synced when slave is up again - no cleaning will be performed" >> $logfile
 slavestatus="down"
 echo "$monitor_critical_prefix Slave ($host) seems to be down - Unable to sync to slave." > $monitor_output
 echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting" >> $logfile
 exit 0
fi

# Check if snapshot exists on slave (it really shouldn't but just to be sure)
if [ $slavestatus = "up" ]; then
 if ssh $user@$host zfs list -H -o name -t snapshot | sort | grep "$snapshot_now$" > /dev/null; then
  echo "`date +"%Y-%m-%d %H:%M:%S"` - $snapshot_now already exists on slave" >> $logfile
  echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting" >> $logfile
  echo "$monitor_critical_prefix $snapshot_now already exists on slave. Something is wrong." > $monitor_output
  exit 0
 fi
fi

# Check if script is already running
if [ -f $lockfile ]; then
 echo "`date +"%Y-%m-%d %H:%M:%S"` - script started, but already seems to be running. A snapshot was taken. No sync or cleaning will be performed on this round. Maybe adjust your snapshot increments if this appers often." >> $logfile
 if [ ! -z "$monitor_output" ]; then
  echo "$monitor_warn_prefix Snapshot $snapshot_now was taken, but didn't sync to $host - Script already seems to be running. Check manually if this persists, or appers often." > $monitor_output
 fi
 echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting" >> $logfile
 exit 0
fi

touch $lockfile

# Include last successful sync snapshot variable
. $lastsucclog

# Transfer snapshot(s) to slave
if [ -z "$lastsucc" ]; then
 echo "`date +"%Y-%m-%d %H:%M:%S"` - No last successful snapshot - syncing initial snapshot $snapshot_now" >> $logfile
 if zfs send -R $snapshot_now | ssh -c arcfour128 $user@$host zfs receive -Fduv $pool >> $logfile; then
  echo "lastsucc=$snapshot_now" > $lastsucclog
  echo "`date +"%Y-%m-%d %H:%M:%S"` - Initial snapshot $snapshot_now was successfully send to $host . No cleanup on this round." >> $logfile
  echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting" >> $logfile
  rm $lockfile
  exit 0
 else
  echo "`date +"%Y-%m-%d %H:%M:%S"` - Initial snapshot $snapshot_now failed to sync to $host ." >> $logfile
  echo "$monitor_critical_prefix Initial snapshot $snapshot_now failed to sync to $host ." > $monitor_output
  echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting" >> $logfile
  rm $lockfile
  exit 0
 fi
else
 if zfs list -H -o name -t snapshot | grep "$lastsucc$" > /dev/null; then
  echo "`date +"%Y-%m-%d %H:%M:%S"` - last successful snapshot $lastsucc exists on master" >> $logfile
  if [ $slavestatus = "up" ] ; then
   if ssh $user@$host zfs list -H -o name -t snapshot | grep "$lastsucc$" > /dev/null; then
    echo "`date +"%Y-%m-%d %H:%M:%S"` - last successful snapshot $lastsucc exists on slave - starting incremental sync" >> $logfile
    if [ `zfs list -H -o name -t snapshot | grep -e "^$pool@$prefix-" | grep -A 2 -e "^$lastsucc$" | wc -l` -gt "2" ]; then
     echo "`date +"%Y-%m-%d %H:%M:%S"` - snapshots have been taken by this script after $lastsucc that were not synced. Syncing those first" >> $logfile
     while [ `zfs list -H -o name -t snapshot | grep -e "^$pool@$prefix-" | grep -A 2 -e "^$lastsucc$" | wc -l` -gt "2" ]; do
      missedsnap=`zfs list -H -o name -t snapshot | grep -e "^$pool@$prefix-" | grep -A 1 -e "^$lastsucc$"  | tail -n 1`
      if zfs send -R -i $lastsucc $missedsnap | ssh -c arcfour128 $user@$host zfs receive -Fduv $pool >> $logfile; then 
       echo "`date +"%Y-%m-%d %H:%M:%S"` - Missed snapshot $missedsnap successfully synced to $host ." >> $logfile
       echo "lastsucc=$missedsnap" > $lastsucclog
       lastsucc=$missedsnap
      else
       echo "`date +"%Y-%m-%d %H:%M:%S"` - incremental zfs send $missedsnap to $host failed." >> $logfile
       echo "$monitor_critical_prefix incremental zfs send $missedsnap to $host failed - sync failed - check manually and clear alert" > $monitor_output
       rm $lockfile
       echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting" >> $logfile
       exit 0
      fi
     done
    fi
    if [ $lastsucc != $snapshot_now ] ; then
     if zfs send -R -i $lastsucc $snapshot_now | ssh -c arcfour128 $user@$host zfs receive -Fduv $pool >> $logfile; then
      echo "`date +"%Y-%m-%d %H:%M:%S"` - $snapshot_now successfully synced to $host ." >> $logfile
      echo "lastsucc=$snapshot_now" > $lastsucclog
     else
      echo "`date +"%Y-%m-%d %H:%M:%S"` - incremental zfs send $snapshot_now to $host failed." >> $logfile
      echo "$monitor_critical_prefix incremental zfs send $snapshot_now to $host failed - sync failed - check manually and clear alert" > $monitor_output
      rm $lockfile
      echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting" >> $logfile
      exit 0
     fi
    fi
   else
    echo "`date +"%Y-%m-%d %H:%M:%S"` - Snapshot $lastsucc doesn't exist on slave, but stated in $lastsucclog - exiting." >> $logfile
    echo "$monitor_critical_prefix incremental zfs send $snapshot_now to $host failed - sync failed - check manually and clear alert" > $monitor_output
    rm $lockfile
    echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting" >> $logfile
    exit 0
   fi
  fi
 else
  echo "`date +"%Y-%m-%d %H:%M:%S"` - Snapshot $lastsucc doesn't exist on master, but stated in $lastsucclog - exiting." >> $logfile
  echo "$monitor_critical_prefix incremental zfs send $snapshot_now to $host failed - sync failed - check manually and clear alert" > $monitor_output
  rm $lockfile
  echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting" >> $logfile
  exit 0
 fi
fi

lastsucc=$snapshot_now

# snapshot cleaning
# master
if [ `zfs list -H -o name -t snapshot | grep -e "^$pool@$prefix-$snapname-" | wc -l` -gt "$keep" ]; then
 while [ `zfs list -H -o name -t snapshot | grep -e "^$pool@$prefix-$snapname-" | wc -l` -gt "$(( $keep ))" ]; do
  if [ $lastsucc != `zfs list -H -o name -t snapshot | sort | grep -e "^$pool@$prefix-$snapname-" | head -n 1` ] ; then 
   echo "`date +"%Y-%m-%d %H:%M:%S"` - destroying snapshot `zfs list -H -o name -t snapshot | sort | grep -e "^$pool@$prefix-$snapname-" | head -n 1` from master in cleaning process - nom nom nom..." >> $logfile
   zfs destroy -r `zfs list -H -o name -t snapshot | sort | grep -e "^$pool@$prefix-$snapname-" | head -n 1` >> $logfile
  else
   echo "`date +"%Y-%m-%d %H:%M:%S"` - Last successful snapshot $lastsucc ended up in cleanup process on the master somehow, but will not be destroyed. Stopping cleanup. Check manually if this persists, or appers often." >> $logfile
   echo "$monitor_warn_prefix Last successful snapshot $lastsucc ended up in cleanup process on the master somehow. Stopping cleanup. Check manually if this persists, or appers often." > $monitor_output
   rm $lockfile
   echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting" >> $logfile
   exit 0
  fi
 done
fi

# slave
if [ `ssh $user@$host zfs list -H -o name -t snapshot | grep -e "^$pool@$prefix-$snapname-" | wc -l` -gt "$keep" ]; then
 while [ `ssh $user@$host zfs list -H -o name -t snapshot | grep -e "^$pool@$prefix-$snapname-" | wc -l` -gt "$(( $keep ))" ]; do
  if [ $lastsucc != `ssh $user@$host zfs list -H -o name -t snapshot | sort | grep -e "^$pool@$prefix-$snapname-" | head -n 1` ] ; then
   echo "`date +"%Y-%m-%d %H:%M:%S"` - destroying snapshot `ssh $user@$host zfs list -H -o name -t snapshot | sort | grep -e "^$pool@$prefix-$snapname-" | head -n 1` from slave in cleaning process - nom nom nom..." >> $logfile
   ssh $user@$host zfs destroy -r `ssh $user@$host zfs list -H -o name -t snapshot | sort | grep -e "^$pool@$prefix-$snapname-" | head -n 1` >> $logfile
  else
   echo "`date +"%Y-%m-%d %H:%M:%S"` - Last successful snapshot $lastsucc ended up in cleanup process on the slave somehow, but will not be destroyed. Stopping cleanup. Check manually if this persists, or appers often." >> $logfile
   echo "$monitor_warn_prefix Last successful snapshot $lastsucc ended up in cleanup process on the slave somehow. Stopping cleanup. Check manually if this persists, or appers often." > $monitor_output
   rm $lockfile
   echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting" >> $logfile
   exit 0
  fi
 done
fi

# end
echo -n "" > $monitor_output
rm $lockfile
echo "`date +"%Y-%m-%d %H:%M:%S"` - exiting" >> $logfile
