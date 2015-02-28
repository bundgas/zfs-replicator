# zfs-replicator
Incremental ZFS replicator with grandfathering scheme support for FreeBSD and ZFS-on-Linux

USAGE (should be used with crontab): zfs-replicator.sh (generation-name) (number of snapshots to keep)

This shell script recursively snapshots a given pool, and replicates it to another host (slave). It supports grandfathering schemes (generations) on both master and slave (mirrored), all controlled from the master with this script and crontab.
Only the first snapshot will be sent in 100% size, all following snapshots will be sent incrementally.
The script outputs log and monitor output. The monitor output can be used for monitoring software such as Nagios.

If the slave is down, or the script is already running, a snapshot will still be taken, and it will be synced with other missed snapshots when the slave is up again. While the slave is down, no cleaning will be done on the master or the slave, so snapshots will build up on the master until the slave is synced again. As soon as the master and slave are in sync again, cleaning will kick in and obey the keep rule(s).
If you are running multible generations, cleaning of the individual generation will not interfer with other generations.

This script was created because i needed something that worked on both FreeBSD and Linux (ZFS-on-Linux), and all the other scripts i tried failed or didn't work, or were too complicated for me to make work.

This script has been worked on over time, and was started to just take snapshots one at a time and send them to a slave.
I started out with a script i found here: http://www.aisecure.net/2012/01/11/automated-zfs-incremental-backups-over-ssh/ and worked on that. Over time a lot of stuff was added here and there, then was rewritten, moved around, more functionality added, more moving arround, rewritten, and so on and so on. Therefore some logic might seem weird in some places, but a lot of it will take care of unexpected situations i ended up in, and now this has been running in production on some of my systems, both Linux (Ubuntu 12.04 and 14.04) and FreeBSD (10.0 and 10.1), and seem to be running error free. This script does not work on Solaris, and i haven't tested it on Illumos.

I'm a sysadmin, not a coder, so there will be some "sledgehammer" approches in the script, but it works. Please feel free to do with this what you want, and i hope this will make your life easier.

You can find documentation and how to use it in the script itself. Read the documentation, and fill out the config-area of the script, and you should be ready to go.

Enjoy :)

Kenneth Lutzke - kml@bundgas.dk
