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

You can find documentation and how to use it in the script itself.

Enjoy :)
