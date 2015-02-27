# zfs-replicator
Incremental ZFS replicator for FreeBSD and ZFS-on-Linux

This script was created because i needed something that worked on both FreeBSD and Linux (ZFS-on-Linux), and all
the other scripts i tried, failed or didn't work, or were too complicated for me to make work.

This script has been worked on over time, and was started to just take snapshots one at a time and send them to a slave.
I started out with a script i found here: http://www.aisecure.net/2012/01/11/automated-zfs-incremental-backups-over-ssh/
and worked on that. Over time alot of stuff was added here and there, then was rewritten, moved around, more
functionality added, more moving arround, rewritten, and so on and so on. Therefore some logic might seem weird in some
places, but somewhere along the line it made sence and it seems to work fine :)

Yes there are too many ssh calls, and there are alot of stuff that could be done better, but you are welcome to run
with this, and do whatever you want with it.

The following info describes the script and usage, and can also be found in the script.

Enjoy :)

ZFS replicator - By Kenneth Lutzke - kml@bundgas.dk
----------------------------------------------------------------------------
"THE BEER-WARE LICENSE" (Revision 42):
<kml@bundgas.dk> wrote this file. As long as you retain this notice you
can do whatever you want with this stuff. If we meet some day, and you think
this stuff is worth it, you can buy me a beer in return. -Kenneth Lutzke
----------------------------------------------------------------------------
DISCLAIMER: YOU RUN THIS AT YOUR OWN RISK!!! If you don't agree, don't run this script.
----------------------------------------------------------------------------
USAGE (should be used with crontab): zfs-replicator.sh <generation-name> <number of snapshots to keep>
This script recursively snapshots a given pool, and replicates it to another host (slave). It supports grandfathering schemes (generations)
on both master and slave (mirrored), all controlled from the master with this script and crontab.
Only the first snapshot will be sent in 100% size, all following snapshots will be sent incrementally.

If the slave is down, or the script is already running, a snapshot will still be taken, and it will be synced with other missed snapshots
when the slave is up again. While the slave is down, no cleaning will be done on the master or the slave, so snapshots will build up on the
master until the slave is synced again. As soon as the master and slave are in sync again, cleaning will kick in and obey the keep rule(s).
If you are running multible generations, cleaning of the individual generation will not interfer with other generations.

BE VERY CAREFUL WITH "zfs destroy -r":
If you destroy a filesystem on the master, it will destroy the filesystem on the slave too, including all the snapshots (across all generations)
for that filesystem, with a single run of the script. This is as intended, as it is the way recursive zfs send and receive work, and as it comes
in handy when you really want the data deleted forever. So if you need the snapshots kept, don't destroy the filesystem, delete the data inside
the filesystem instead, and destroy it when it has "trickeled through" your generations.

For this script to work, ssh keys with no passphrase must first be set up so that a user (ex. root) can ssh from the master to the slave without
being prompted for login.

Example of use with crontab (*1min schedule should only be used for testing, or on pools with few filesystems and low io).

1-4/1,6-9/1,11-14/1,16-19/1,21-24/1,26-29/1,31-34/1,36-39/1,41-44/1,46-49/1,51-54/1,56-59/1 * * * *  root    /root/zfs-replicator.sh 1min 5
5,10,20,25,35,40,50,55 * * * *           root   /root/zfs-replicator.sh 5min 3
15,30,45 * * * *                         root   /root/zfs-replicator.sh 15min 4
0 1-5,7-11,13-17,19-23 * * *             root   /root/zfs-replicator.sh 1hour 6
0 0,6,12,18 * * *                        root   /root/zfs-replicator.sh 6hour 9

The example is set on FreeBSD. On linux you might need to remove "root" before the command entry.
This would give you 1 snapshot every minute for 5 minutes, 1 snapshot every 5 minutes for 15 minutes, 1 snapshot every 15 minutes for 1 hour,
1 snapshot every hour for 6 hours, and 1 snapshot every 6 hours for 2 days* (* 2 day = 8 snapshots. The 9 in the example is because you need
one extra snapshot in the end to be able to go 2 whole days back, or that snapshot will just have have been destroyed, and you could now only
go 1 day and 18 hours back. This is not a problem for 1min, 5min, 15min or 1hour schedules in the above example, as they all overlap 1 snapshot
with the next generation.

* 1min schedule will most likely only work smoothly with very few filesystems with nearly no writing IO, as it can take some time to sync each 
filesystem. This would give you a lot of overlapping script-executions, and you will end up with a snapshot backlog, which would probably
result in even more overlapping script-executions, and so on. Adjust your lowest snapshot increment so that there on average is enough time to
transfer everything incrementally to the slave. Because the script picks up snapshots missed for transfer on the next round, it is ok if it
doesn't make it on time every time, but if your increments are set too often, you are probably in for a bumpy ride.

If you want to be extra sure that you get monitor-output if the script fails, run it in crontab like this:
15,30,45 * * * *  root   /root/zfs-replicator.sh 15min 4 || echo "SCRIPT-FAILED: Sync script failed - Check manually!!!" >> /path/to/monitor-file.txt
----------------------------------------------------------------------------
