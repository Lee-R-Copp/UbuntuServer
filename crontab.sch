# Replace default cron schedule with this file
SHELL=/bin/sh
#
# m h dom mon dow user  command
0  *    * * *   root    cd / && run-parts --report /etc/cron.hourly
0  0    * * *   root    test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.daily )
0  0    * * 7   root    test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.weekly )
0  0    1 * *   root    test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.monthly )
