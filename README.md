# docker_cron_monitor.sh
Script to monitor and alert on docker container failures

Script watches set of container names to alert if any are not running.

Add script to crontab to run as frequently as you want to monitor your containers. I run it every 10 mins (resulting in a notification 
if a container is down for 20 min):

`0,10,20,30,40,50 * * * * /path/to/script/crontab_monitor.sh`

If container is not running it will initially be logged in `crontab_monitor.warn` to give a grace period in case a container is 
updating or restarting. If it is still not running in the next check then an alert will be sent. Only one alert will be sent to 
avoid bombarding with repeated alerts. Another notification will be sent when the container is brought back up, this notification 
will detail the length of time the container was down.

Save script in location of your choice and make 'crontab_monitor.watchlist' containing list of container names to monitor. One 
container nane per line.

And make these empty files in the same location:
* `crontab_monitor.warn` - current set of 'warnings' i.e. container has been down for one instance of monitoring script but not yet two. 
If the container is still down next time script runs an alert will be sent.
* `crontab_monitor.alerts` - current set of alerts i.e. these containers have gone down and notifications have been sent.
* `crontab_monitor.history` - will log a history or container status changes.

The script send notoifications to Slack, email, and Pushbullet. It utilises [this Slack command line script](https://github.com/danteali/Slackomatic)
, and [this Pushbullet script](https://gist.github.com/danteali/6cf4d91e29d5774a96720a35aff8b00e). If you want to send emails make 
sure you already have your email ultility configured, the script uses `mutt` to send emails but you can easily swap it for `sendmail` etc.
