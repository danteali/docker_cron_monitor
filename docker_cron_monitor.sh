#!/bin/bash
    red=`tput setaf 1`
    green=`tput setaf 2`
    yellow=`tput setaf 3`
    blue=`tput setaf 4`
    magenta=`tput setaf 5`
    cyan=`tput setaf 6`
    under=`tput sgr 0 1`
    reset=`tput sgr0`

# Check running as root - attempt to restart with sudo if not already running with root
    if [ $(id -u) -ne 0 ]; then tput setaf 1; echo "Not running as root, attempting to automatically restart script with root access..."; tput sgr0; echo; sudo $0 $*; exit 1; fi


# Script watches set of container names to alert if any are not running.
# If container is not running it will initially be logged in the FIRST_WARN_FILE
# to give a grace period in case a container is updating or restarting.
# If it is still not running in the next check then an alert will be sent.
# Only one alert will be sent to avoid bombarding with alerts.
# Notification will also be sent of container resumes.

# Save script in location of your choice and make these empty files in the same location:
# crontab_monitor.alerts - current set of alerts i.e. these containers have gone down and 
#                          notifications have been sent.
# crontab_monitor.warn - current set of 'warnings' i.e. container has been down for one
#                        instance of monitoring script but not yet two. If container still
#                        down next time script runs an alert will be sent.
# crontab_monitor.history - will log a history or container status changes

# Add script to crontab to run as frequently as you want to monitor your containers.
# I run it every 10 mins:
# 0,10,20,30,40,50 * * * * /path/to/script/docker_cron_monitor.sh


# And make 'crontab_monitor.watchlist' containing list of containernames
# to monitor. One container nane per line.

# Utilises slack script from https://github.com/danteali/Slackomatic
# for sending alerts.
# And pushbullet script from https://gist.github.com/danteali/6cf4d91e29d5774a96720a35aff8b00e

# Make sure you already have properly configured your email utilities.
# This script uses 'mutt' to send email but you came substitute in
# 'sendmail' or other email tool as needed.

# Variables
    WHEREAMI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
    WHOAMI=$(basename $0)
    DATETIME=$(date +%Y%m%d-%H%M%S)
    MAIL_BIN="/usr/bin/mutt"
    EMAIL_ADDRESS="<your email here>"
    # Files
    LOG_EXISTING_ALERTS="$WHEREAMI/crontab_monitor.alerts"
    LOG_FIRST_WARN="$WHEREAMI/crontab_monitor.warn"
    LOG_ALERT_HISTORY="$WHEREAMI/crontab_monitor.history"
    WATCHLIST_FILE="$WHEREAMI/crontab_monitor.watchlist"
    # Script variables
    WATCHLIST=()
    #
    EXISTING_ALERT_FILE_ARRAY=()
    EXISTING_ALERT_FILE_LIST=""
    #
    FIRST_WARN_FILE_ARRAY=()
    FIRST_WARN_FILE_LIST=""
    #
    CONTAINER_STATUS_ARRAY=()
    CONTAINER_EXISTING_ALERT_FILE_ARRAY=()
    CONTAINER_PREV_WARN_ARRAY=()
    CONTAINER_NOT_RUNNING_ARRAY=()
    #
    NEW_ALERTS_ARRAY=()
    NEW_ALERTS_STRING=""
    NEW_ALERTS=0
    NEW_WARNINGS_ARRAY=()
    NEW_WARNINGS_STRING=""
    NEW_WARNINGS=0
    CLEARED_WARNINGS_ARRAY=()
    CLEARED_WARNINGS_STRING=""
    CLEARED_WARNINGS=0
    CLEARED_ALERTS_ARRAY=()
    CLEARED_ALERTS_STRING=""
    CLEARED_ALERTS=0
    CONTINUING_ALERTS_ARRAY=()
    CONTINUING_ALERTS_STRING=""
    CONTINUING_ALERTS=0
    # Notification Switches - Slack / Email / Pushbullet
    # If you want to send anotification for each container that is down set NOTIFY_EVERY_INSTANCE=1 
    # Set NOTIFY_SUMMARY=1 to send one notification consolidating all new alerts for downed containers
    SCREEN=1
    NOTIFY_PB=1
    NOTIFY_SLACK=1
    NOTIFY_EMAIL=1
    NOTIFY_EVERY_INSTANCE=1
    NOTIFY_SUMMARY=0
    # Print debug messages?
    DEBUG=0



# ======================================================================================================================================
# READ LIST OF CONTAINERS TO MONITOR
# ======================================================================================================================================

# Read in watchlist
  # Option 1:
    #IFS=$'\n' read -d '' -r -a WATCHLIST < $WATCHLIST_FILE
  # Option 2:
    #IFS=$'\r\n' GLOBIGNORE='*' command eval  'WATCHLIST=($(cat $WATCHLIST_FILE))'
  # Option 3:
    readarray -t WATCHLIST < $WATCHLIST_FILE
                                                                                                          if [[ $DEBUG == 1 ]]; then
                                                                                                              echo "Debugging ++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "WATCHLIST array length = "${#WATCHLIST[@]}
                                                                                                              echo "WATCHLIST array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${WATCHLIST[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${WATCHLIST[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo
                                                                                                          fi



# ======================================================================================================================================
# EXISTING ALERTS
# ======================================================================================================================================

# Read list of containers with existing alerts so that we don't repeatedly warn
# cat alerts file | grep: remove header line | awk: get column with container names
EXISTING_ALERT_FILE_LIST=$( \
    cat "${LOG_EXISTING_ALERTS}" \
    | grep -v "Date" \
    | grep -v "\-\-\-\-\-" \
    | awk '{ print $2 }' \
     )
# Create existing alert array
read -r -a EXISTING_ALERT_FILE_ARRAY <<< $EXISTING_ALERT_FILE_LIST

                                                                                                          if [[ $DEBUG == 1 ]]; then
                                                                                                              echo "Debugging ++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "Existing alertlist: "$EXISTING_ALERT_FILE_LIST
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++";
                                                                                                              echo "EXISTING_ALERT_FILE_ARRAY array length = "${#EXISTING_ALERT_FILE_ARRAY[@]}
                                                                                                              echo "EXISTING_ALERT_FILE_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${EXISTING_ALERT_FILE_ARRAY[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${EXISTING_ALERT_FILE_ARRAY[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo
                                                                                                          fi

# Get existing alert start date/time so that we can reporton duration of resolved alert later
# cat alerts file | grep: remove header line | awk: get column with container names
EXISTING_ALERT_START_LIST=$( \
    cat "${LOG_EXISTING_ALERTS}" \
    | grep -v "Date" \
    | grep -v "\-\-\-\-\-" \
    | awk '{ print $1 }' \
     )
# Create existing alert array
read -r -a EXISTING_ALERT_START_ARRAY <<< $EXISTING_ALERT_START_LIST

                                                                                                          if [[ $DEBUG == 1 ]]; then
                                                                                                              echo "Debugging ++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "Existing alertlist: "$EXISTING_ALERT_START_ARRAY
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++";
                                                                                                              echo "EXISTING_ALERT_START_ARRAY array length = "${#EXISTING_ALERT_START_ARRAY[@]}
                                                                                                              echo "EXISTING_ALERT_START_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${EXISTING_ALERT_START_LIST[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${EXISTING_ALERT_START_ARRAY[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo
                                                                                                          fi
# Convert dates into epoch seconds
#date --date="$(echo "20190419-203002" | sed 's/^\(.\{13\}\)/\1:/' | sed 's/^\(.\{11\}\)/\1:/' | sed 's/-/ /')" +%s
for i in "${!EXISTING_ALERT_START_ARRAY[@]}"; do
    ALERT_SECS=$(date --date="$(echo "${EXISTING_ALERT_START_ARRAY[i]}" | sed 's/^\(.\{13\}\)/\1:/' | sed 's/^\(.\{11\}\)/\1:/' | sed 's/-/ /')" +%s)
    EXISTING_ALERT_START_SECS_ARRAY+=("$ALERT_SECS")
done
                                                                                                          if [[ $DEBUG == 1 ]]; then
                                                                                                              echo "Debugging ++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "Existing alertlist: "$EXISTING_ALERT_START_SECS_ARRAY
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++";
                                                                                                              echo "EXISTING_ALERT_START_SECS_ARRAY array length = "${#EXISTING_ALERT_START_SECS_ARRAY[@]}
                                                                                                              echo "EXISTING_ALERT_START_SECS_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${EXISTING_ALERT_START_LIST[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${EXISTING_ALERT_START_SECS_ARRAY[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo
                                                                                                          fi


# ======================================================================================================================================
# PREVIOUS FIRST WARNINGS
# ======================================================================================================================================

# Read list of containers with existing alerts so that we don't repeatedly warn
# cat alerts file | grep: remove header line | awk: get column with container names
FIRST_WARN_FILE_LIST=$( \
    cat "${LOG_FIRST_WARN}" \
    | grep -v "Date" \
    | grep -v "\-\-\-\-\-" \
    | awk '{ print $2 }' \
     )
# Create existing alert array
read -r -a FIRST_WARN_FILE_ARRAY <<< $FIRST_WARN_FILE_LIST

                                                                                                          if [[ $DEBUG == 1 ]]; then
                                                                                                              echo "Debugging ++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "FIRST_WARN_FILE_LIST list: "$FIRST_WARN_FILE_LIST
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++";
                                                                                                              echo "FIRST_WARN_FILE_ARRAY array length = "${#FIRST_WARN_FILE_ARRAY[@]}
                                                                                                              echo "FIRST_WARN_FILE_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${FIRST_WARN_FILE_ARRAY[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${FIRST_WARN_FILE_ARRAY[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo
                                                                                                          fi




# ======================================================================================================================================
# QUERY DOCKER
# ======================================================================================================================================

# Loop through docker watchlist and check status, also check if alert already exists
for i in "${!WATCHLIST[@]}"; do
    CONTAINER_STATUS=""

    # If container not running we get an error with inspect command so can't just set CONTAINER_STATUS to command result since error isn't counted as valid result
    # So need to check if ocmmand runs successfully first, then set variable.
    if (docker inspect --format='{{ .State.Status }}' "${WATCHLIST[i]}" > /dev/null 2>&1 ); then
        CONTAINER_STATUS=$(docker inspect --format='{{ .State.Status }}' "${WATCHLIST[i]}" )
    else
        CONTAINER_STATUS="NOT RUNNING"
    fi

    # Add CONTAINER_STATUS to array
    CONTAINER_STATUS_ARRAY+=("$CONTAINER_STATUS")

    # Check if new alert or if already in existing alert list
    CONTAINER_EXISTING_ALERT="no"
    if [[ $EXISTING_ALERT_FILE_LIST == *"${WATCHLIST[i]}"* ]]; then
        CONTAINER_EXISTING_ALERT="YES"
    fi
    # Add existing alert info to array
    CONTAINER_EXISTING_ALERT_FILE_ARRAY+=($CONTAINER_EXISTING_ALERT)

    # Check if alert in previously first warned list
    CONTAINER_PREV_WARN="no"
    if [[ $FIRST_WARN_FILE_LIST == *"${WATCHLIST[i]}"* ]]; then
        CONTAINER_PREV_WARN="YES"
    fi
    # Add existing alert info to array
    CONTAINER_PREV_WARN_ARRAY+=($CONTAINER_PREV_WARN)

    # Increment counts
    CONTAINERS_CHECKED=$(($CONTAINERS_CHECKED + 1))
    if [[ $CONTAINER_STATUS == "running" ]]; then
        # Increment count
        CONTAINERS_RUNNING=$(($CONTAINERS_RUNNING + 1))
    else
        # Increment count
        CONTAINERS_NOT_RUNNING=$(($CONTAINERS_NOT_RUNNING + 1))
        # Add non-running containers to array for checking later
        CONTAINER_NOT_RUNNING_ARRAY+=("${WATCHLIST[i]}")
    fi

done
                                                                                                          if [[ $DEBUG == 1 ]]; then
                                                                                                              echo "Debugging ++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "Debugging: CONTAINER_STATUS_ARRAY length = "${#CONTAINER_STATUS_ARRAY[@]}
                                                                                                              echo "CONTAINER_STATUS_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${CONTAINER_STATUS_ARRAY[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${CONTAINER_STATUS_ARRAY[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "Debugging: CONTAINER_EXISTING_ALERT_FILE_ARRAY length = "${#CONTAINER_EXISTING_ALERT_FILE_ARRAY[@]}
                                                                                                              echo "CONTAINER_EXISTING_ALERT_FILE_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${CONTAINER_EXISTING_ALERT_FILE_ARRAY[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${CONTAINER_EXISTING_ALERT_FILE_ARRAY[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "Debugging: CONTAINER_PREV_WARN_ARRAY length = "${#CONTAINER_PREV_WARN_ARRAY[@]}
                                                                                                              echo "CONTAINER_PREV_WARN_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${CONTAINER_PREV_WARN_ARRAY[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${CONTAINER_PREV_WARN_ARRAY[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "Debugging: CONTAINER_NOT_RUNNING_ARRAY length = "${#CONTAINER_NOT_RUNNING_ARRAY[@]}
                                                                                                              echo "CONTAINER_NOT_RUNNING_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${CONTAINER_NOT_RUNNING_ARRAY[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${CONTAINER_NOT_RUNNING_ARRAY[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                          fi



# ======================================================================================================================================
# ANALYSIS
# ======================================================================================================================================

# Compare CONTAINER_NOT_RUNNING_ARRAY to FIRST_WARN_FILE_ARRAY to find any NEW_ALERTS and NEW_WARNINGS
# Loop through containers not running
for i in "${!CONTAINER_NOT_RUNNING_ARRAY[@]}"; do
    # Check to see if CONTAINERS_NOT_RUNNING element is in FIRST_WARN_FILE_ARRAY = new alert to be sent
    if [[ ${FIRST_WARN_FILE_ARRAY[@]} == *"${CONTAINER_NOT_RUNNING_ARRAY[i]}"* ]]; then
        # Increment new alert count
        NEW_ALERTS=$(($NEW_ALERTS + 1))
        # Add new alerts to array
        NEW_ALERTS_ARRAY+=("${CONTAINER_NOT_RUNNING_ARRAY[i]}")
        # Add new alerts to string
        if [[ $NEW_ALERTS == 1 ]]; then
            NEW_ALERTS_STRING=$(echo "${CONTAINER_NOT_RUNNING_ARRAY[i]}")
        else
            NEW_ALERTS_STRING=$(echo "$NEW_ALERTS_STRING, ${CONTAINER_NOT_RUNNING_ARRAY[i]}")
        fi
    # If CONTAINERS_NOT_RUNNING element is NOT in FIRST_WARN_FILE_ARRAY
    # Then check to see if it's NOT in EXISTING_ALERT_FILE_ARRAY = NEW_WARNINGS to be added to .warn file
    else
        if [[ ! ${EXISTING_ALERT_FILE_ARRAY[@]} == *"${CONTAINER_NOT_RUNNING_ARRAY[i]}"* ]]; then
            # Increment count
            NEW_WARNINGS=$(($NEW_WARNINGS + 1))
            # Add new alerts to array
            NEW_WARNINGS_ARRAY+=("${CONTAINER_NOT_RUNNING_ARRAY[i]}")
            # Add new alerts to string
            if [[ $NEW_WARNINGS == 1 ]]; then
                NEW_WARNINGS_STRING=$(echo "${CONTAINER_NOT_RUNNING_ARRAY[i]}")
            else
                NEW_WARNINGS_STRING=$(echo "$NEW_WARNINGS_STRING, ${CONTAINER_NOT_RUNNING_ARRAY[i]}")
            fi
        fi

    fi
done

                                                                                                          if [[ $DEBUG == 1 ]]; then
                                                                                                              echo "Debugging ++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "Debugging: NEW_ALERTS_STRING = "$NEW_ALERTS_STRING
                                                                                                              echo "Debugging: NEW_ALERTS_ARRAY length = "${#NEW_ALERTS_ARRAY[@]}
                                                                                                              echo "NEW_ALERTS_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${NEW_ALERTS_ARRAY[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${NEW_ALERTS_ARRAY[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "Debugging: NEW_WARNINGS_STRING = "$NEW_WARNINGS_STRING
                                                                                                              echo "Debugging: NEW_WARNINGS_ARRAY length = "${#NEW_WARNINGS_ARRAY[@]}
                                                                                                              echo "NEW_WARNINGS_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${NEW_WARNINGS_ARRAY[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${NEW_WARNINGS_ARRAY[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                          fi

# Compare FIRST_WARN_FILE_ARRAY to CONTAINER_NOT_RUNNING_ARRAY to find any CLEARED_WARNINGS
# Loop through first warnings
for i in "${!FIRST_WARN_FILE_ARRAY[@]}"; do
    # Check to see if prev warning is NOT in CONTAINERS_NOT_RUNNING list = CLEARED_WARNINGS
    if [[ ! ${CONTAINER_NOT_RUNNING_ARRAY[@]} == *"${FIRST_WARN_FILE_ARRAY[i]}"* ]]; then
        # Increment new alert count
        CLEARED_WARNINGS=$(($CLEARED_WARNINGS + 1))
        # Add new alerts to array
        CLEARED_WARNINGS_ARRAY+=("${FIRST_WARN_FILE_ARRAY[i]}")
        # Add new alerts to string
        if [[ $CLEARED_WARNINGS == 1 ]]; then
            CLEARED_WARNINGS_STRING=$(echo "${FIRST_WARN_FILE_ARRAY[i]}")
        else
            CLEARED_WARNINGS_STRING=$(echo "$CLEARED_WARNINGS_STRING, ${FIRST_WARN_FILE_ARRAY[i]}")
        fi
    fi
done

                                                                                                          if [[ $DEBUG == 1 ]]; then
                                                                                                              echo "Debugging ++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "Debugging: CLEARED_WARNINGS_STRING = "$CLEARED_WARNINGS_STRING
                                                                                                              echo "Debugging: CLEARED_WARNINGS_ARRAY length = "${#CLEARED_WARNINGS_ARRAY[@]}
                                                                                                              echo "CLEARED_WARNINGS_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${CLEARED_WARNINGS_ARRAY[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${CLEARED_WARNINGS_ARRAY[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo
                                                                                                          fi

# Compare EXISTING_ALERT_FILE_ARRAY to CONTAINER_NOT_RUNNING_ARRAY to CLEARED_ALERTS and CONTINUING_ALERTS
# Loop through existing alerts
for i in "${!EXISTING_ALERT_FILE_ARRAY[@]}"; do
    # Check to see if existing alert element is NOT in CONTAINERS_NOT_RUNNING list = CLEARED_ALERTS
    if [[ ! ${CONTAINER_NOT_RUNNING_ARRAY[@]} == *"${EXISTING_ALERT_FILE_ARRAY[i]}"* ]]; then
        CLEARED_ALERTS=$(($CLEARED_ALERTS + 1))
        CLEARED_ALERTS_ARRAY+=("${EXISTING_ALERT_FILE_ARRAY[i]}")
        # Add cleared alerts to string
        if [[ $CLEARED_ALERTS == 1 ]]; then
            CLEARED_ALERTS_STRING=$(echo "${EXISTING_ALERT_FILE_ARRAY[i]}")
        else
            CLEARED_ALERTS_STRING=$(echo "$CLEARED_ALERTS_STRING, ${EXISTING_ALERT_FILE_ARRAY[i]}")
        fi
        # Calc time since alert raised
        NOW_SECS=$(date +%s)
        ELAPSED=$(($NOW_SECS - ${EXISTING_ALERT_START_SECS_ARRAY[i]}))
        CLEARED_ALERTS_DURATION_SECS_ARRAY+=($ELAPSED)
        ELAPSED_PRETTY="$(($ELAPSED / 86400))days $(($ELAPSED / 3600))hrs $((($ELAPSED / 60) % 60))min $(($ELAPSED % 60))sec"
        CLEARED_ALERTS_DURATION_SECS_PRETTY_ARRAY+=("$ELAPSED_PRETTY")
    # Check to see if existing alert element is in CONTAINERS_NOT_RUNNING list = CONTINUING_ALERTS
    else
        CONTINUING_ALERTS=$(($CONTINUING_ALERTS + 1))
        CONTINUING_ALERTS_ARRAY+=("${EXISTING_ALERT_FILE_ARRAY[i]}")
        # Add cleared alerts to string
        if [[ $CONTINUING_ALERTS == 1 ]]; then
            CONTINUING_ALERTS_STRING=$(echo "${EXISTING_ALERT_FILE_ARRAY[i]}")
        else
            CONTINUING_ALERTS_STRING=$(echo "$CONTINUING_ALERTS_STRING, ${EXISTING_ALERT_FILE_ARRAY[i]}")
        fi
        # Record CONTINUING_ALERTS start datetime from alert file
        CONTINUING_ALERTS_START_ARRAY+=("${EXISTING_ALERT_START_ARRAY[i]}")
        # Calc time since alert raised
        NOW_SECS=$(date +%s)
        ELAPSED=$(($NOW_SECS - ${EXISTING_ALERT_START_SECS_ARRAY[i]}))
        CONTINUING_ALERTS_DURATION_SECS_ARRAY+=($ELAPSED)
        ELAPSED_PRETTY="$(($ELAPSED / 86400))days $(($ELAPSED / 3600))hrs $((($ELAPSED / 60) % 60))min $(($ELAPSED % 60))sec"
        CONTINUING_ALERTS_DURATION_SECS_PRETTY_ARRAY+=("$ELAPSED_PRETTY")
    fi
done

                                                                                                          if [[ $DEBUG == 1 ]]; then
                                                                                                              echo "Debugging ++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "Debugging: CLEARED_ALERTS_STRING = "$CLEARED_ALERTS_STRING
                                                                                                              echo "Debugging: CLEARED_ALERTS_ARRAY length = "${#CLEARED_ALERTS_ARRAY[@]}
                                                                                                              echo "CLEARED_ALERTS_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${CLEARED_ALERTS_ARRAY[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${CLEARED_ALERTS_ARRAY[@]}"
                                                                                                              echo "Debugging ++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "Debugging: CLEARED_ALERTS_DURATION_SECS_ARRAY length = "${#CLEARED_ALERTS_DURATION_SECS_ARRAY[@]}
                                                                                                              echo "CLEARED_ALERTS_DURATION_SECS_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${CLEARED_ALERTS_ARRAY[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${CLEARED_ALERTS_DURATION_SECS_ARRAY[@]}"
                                                                                                              echo "Debugging ++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "Debugging: CLEARED_ALERTS_DURATION_SECS_PRETTY_ARRAY length = "${#CLEARED_ALERTS_DURATION_SECS_PRETTY_ARRAY[@]}
                                                                                                              echo "CLEARED_ALERTS_DURATION_SECS_PRETTY_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${CLEARED_ALERTS_ARRAY[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${CLEARED_ALERTS_DURATION_SECS_PRETTY_ARRAY[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"; 
                                                                                                              echo "Debugging: CONTINUING_ALERTS_STRING = "$CONTINUING_ALERTS_STRING
                                                                                                              echo "Debugging: CONTINUING_ALERTS_ARRAY length = "${#CONTINUING_ALERTS_ARRAY[@]}
                                                                                                              echo "CONTINUING_ALERTS_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${CONTINUING_ALERTS_ARRAY[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${CONTINUING_ALERTS_ARRAY[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "Debugging: CONTINUING_ALERTS_START_ARRAY length = "${#CONTINUING_ALERTS_START_ARRAY[@]}
                                                                                                              echo "CONTINUING_ALERTS_START_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${CONTINUING_ALERTS_ARRAY[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${CONTINUING_ALERTS_START_ARRAY[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "Debugging: CONTINUING_ALERTS_DURATION_SECS_ARRAY length = "${#CONTINUING_ALERTS_DURATION_SECS_ARRAY[@]}
                                                                                                              echo "CONTINUING_ALERTS_DURATION_SECS_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${CONTINUING_ALERTS_ARRAY[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${CONTINUING_ALERTS_DURATION_SECS_ARRAY[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo "Debugging: CONTINUING_ALERTS_DURATION_SECS_PRETTY_ARRAY length = "${#CONTINUING_ALERTS_DURATION_SECS_PRETTY_ARRAY[@]}
                                                                                                              echo "CONTINUING_ALERTS_DURATION_SECS_PRETTY_ARRAY array elements..."
                                                                                                              #All elements on single line
                                                                                                              #echo ${CONTINUING_ALERTS_ARRAY[@]}
                                                                                                              #All elements on new lines:
                                                                                                              printf "%s\n" "${CONTINUING_ALERTS_DURATION_SECS_PRETTY_ARRAY[@]}"
                                                                                                              echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
                                                                                                              echo
                                                                                                          fi


# ======================================================================================================================================
# OUTPUT
# ======================================================================================================================================

# Output results to screen (if flag set)
if [[ $SCREEN == 1 ]]; then
    printf "${cyan}%30s %16s %16s %16s${reset}\n" "Container" "Status" "Already Alerted?" "Prev Warn?"
    printf "${cyan}%30s %16s %16s %16s${reset}\n" "==============================" "================" "================" "================"
    for i in "${!WATCHLIST[@]}"; do
        # if not running and no prev warning or alert = new warning = yellow
        # if not running and prev warning but not yet alerted = new alert = red
        # if not running and already alerted = existing alert = magenta
        if [[ ! "${CONTAINER_STATUS_ARRAY[i]}" == "running" ]] && [[ ! "${CONTAINER_EXISTING_ALERT_FILE_ARRAY[i]}" == "YES" ]] && [[ ! "${CONTAINER_PREV_WARN_ARRAY[i]}" == "YES" ]]; then
            printf "${yellow}%30s %16s %16s %16s${reset}\n" "${WATCHLIST[i]}" "${CONTAINER_STATUS_ARRAY[i]}" "${CONTAINER_EXISTING_ALERT_FILE_ARRAY[i]}" "${CONTAINER_PREV_WARN_ARRAY[i]}"
        elif [[ ! "${CONTAINER_STATUS_ARRAY[i]}" == "running" ]] && [[ ! "${CONTAINER_EXISTING_ALERT_FILE_ARRAY[i]}" == "YES" ]] && [[ "${CONTAINER_PREV_WARN_ARRAY[i]}" == "YES" ]]; then
            printf "${red}%30s %16s %16s %16s${reset}\n" "${WATCHLIST[i]}" "${CONTAINER_STATUS_ARRAY[i]}" "${CONTAINER_EXISTING_ALERT_FILE_ARRAY[i]}" "${CONTAINER_PREV_WARN_ARRAY[i]}"
        elif [[ ! "${CONTAINER_STATUS_ARRAY[i]}" == "running" ]] && [[ "${CONTAINER_EXISTING_ALERT_FILE_ARRAY[i]}" == "YES" ]]; then
            printf "${magenta}%30s %16s %16s %16s${reset}\n" "${WATCHLIST[i]}" "${CONTAINER_STATUS_ARRAY[i]}" "${CONTAINER_EXISTING_ALERT_FILE_ARRAY[i]}" "${CONTAINER_PREV_WARN_ARRAY[i]}"
        else
            printf "${green}%30s %16s %16s %16s${reset}\n" "${WATCHLIST[i]}" "${CONTAINER_STATUS_ARRAY[i]}" "${CONTAINER_EXISTING_ALERT_FILE_ARRAY[i]}" "${CONTAINER_PREV_WARN_ARRAY[i]}"
        fi
    done
    printf "${cyan}%30s %16s %16s %16s${reset}\n" "==============================" "================" "================" "================"

    # Print prev warnings list
    echo; echo "PREVIOUS WARNINGS - CONTAINER STILL DOWN -> NEW ALERTS - NOTIFICATION SENT..."
    for i in "${!NEW_ALERTS_ARRAY[@]}"; do
        echo "${NEW_ALERTS_ARRAY[i]}"
    done
    echo
    # Print previous warnings now cleared
    echo "PREVIOUS WARNINGS - CONTAINER NOW RUNNING -> WARNING CLEARED..."
    for i in "${!CLEARED_WARNINGS_ARRAY[@]}"; do
        echo "${CLEARED_WARNINGS_ARRAY[i]}"
    done
    echo
    # Print new warnings
    echo "CONTAINERS NOT RUNNING -> NEW WARNING LOGGED..."
    for i in "${!NEW_WARNINGS_ARRAY[@]}"; do
        echo "${NEW_WARNINGS_ARRAY[i]}"
    done
    echo
    # Print previous alerts now cleared
    echo "PREVIOUSLY ALERTED - CONTAINER NOW RUNNING -> ALERT CLEARED - NOTIFICATION SENT..."
    for i in "${!CLEARED_ALERTS_ARRAY[@]}"; do
        echo "${CLEARED_ALERTS_ARRAY[i]} (Downtime: ${CLEARED_ALERTS_DURATION_SECS_PRETTY_ARRAY[i]})"
    done
    echo
    # Print previous alerts
    echo "PREVIOUSLY ALERTED - CONTAINER STILL NOT RUNNING..."
    for i in "${!CONTINUING_ALERTS_ARRAY[@]}"; do
        echo "${CONTINUING_ALERTS_ARRAY[i]} (Downtime: ${CONTINUING_ALERTS_DURATION_SECS_PRETTY_ARRAY[i]})"
    done
    echo

    echo "=================================="
    printf "%-29s ${blue}%3s${reset}\n" "No. containers checked:" "$CONTAINERS_CHECKED"
    printf "%-29s ${blue}%3s${reset}\n" "No. containers running:" "$CONTAINERS_RUNNING"
    printf "%-29s ${blue}%3s${reset}\n" "No. containers NOT running:" "$CONTAINERS_NOT_RUNNING"
    echo "----------------------------------"
    printf "%-29s ${yellow}%3s${reset}\n" "No. existing warnings:" "${#FIRST_WARN_FILE_ARRAY[@]}"
    printf "%-29s ${yellow}%3s${reset}\n" "No. new warnings:" "${#NEW_WARNINGS_ARRAY[@]}"
    printf "%-29s ${yellow}%3s${reset}\n" "No. prev warnings cleared:" "${#CLEARED_WARNINGS_ARRAY[@]}"
    echo "----------------------------------"
    printf "%-29s ${magenta}%3s${reset}\n" "No. existing alerts:" "${#EXISTING_ALERT_FILE_ARRAY[@]}"
    printf "%-29s ${magenta}%3s${reset}\n" "No. new alerts:" "${#NEW_ALERTS_ARRAY[@]}"
    printf "%-29s ${magenta}%3s${reset}\n" "No. prev alerts cleared:" "${#CLEARED_ALERTS_ARRAY[@]}"
    printf "%-29s ${magenta}%3s${reset}\n" "No. continuing alerts:" "${#CONTINUING_ALERTS_ARRAY[@]}"
    echo "=================================="
    echo

fi



# ======================================================================================================================================
# NEW ALERT NOTIFICATIONS
# ======================================================================================================================================

# Send individual error notifications (if flag set)
if [[ ! $NEW_ALERTS_STRING == "" ]] &&[[ $NOTIFY_EVERY_INSTANCE == 1 ]]; then
    # loop through errors
    echo "-----------------------------------------------------"
    for i in "${!NEW_ALERTS_ARRAY[@]}"; do
        if [[ $NOTIFY_EMAIL == 1 ]]; then
            echo "CONTAINER DOWN - Sending email notification for "${NEW_ALERTS_ARRAY[i]}...
            echo "${NEW_ALERTS_ARRAY[i]} down at `date`" | $MAIL_BIN -s "${NEW_ALERTS_ARRAY[i]} CONTAINER DOWN!!!" "$EMAIL_ADDRESS"
        fi
        if [[ $NOTIFY_PB == 1 ]]; then
            echo "CONTAINER DOWN - Sending Pushbullet notification for "${NEW_ALERTS_ARRAY[i]}
            PB_SUBJECT="${NEW_ALERTS_ARRAY[i]} CONTAINER DOWN!!!"
            PB_MSG="${NEW_ALERTS_ARRAY[i]} down @ `date`"
            pushbullet "$PB_SUBJECT" "$PB_MSG"
        fi
        if [[ $NOTIFY_SLACK == 1 ]]; then
            echo "CONTAINER DOWN - Sending Slack notification for "${NEW_ALERTS_ARRAY[i]}
            SLACK_SUBJECT="${NEW_ALERTS_ARRAY[i]} CONTAINER DOWN!!!"
            SLACK_TEXT="${NEW_ALERTS_ARRAY[i]} down @ `date`"
            slack -u "docker-crontab-monitor" -c "#alert" -T "$SLACK_SUBJECT" -t "$SLACK_TEXT" -e ":whale:" -C red
        fi
    done
    echo "-----------------------------------------------------"; echo
fi

# Send summary error notifications if NEW_ALERTS_STRING string not empty (if flag set)
if [[ ! $NEW_ALERTS_STRING == "" ]] && [[ $NOTIFY_SUMMARY == 1 ]]; then
    echo "-----------------------------------------------------"
    if [[ $NOTIFY_EMAIL == 1 ]]; then
        echo "CONTAINERS DOWN - Sending summary email notification - these containers stopped: $NEW_ALERTS_STRING"
        echo "$NEW_ALERTS_STRING DOWN at `date`" | $MAIL_BIN -s "CONTAINERS DOWN!!!" "$EMAIL_ADDRESS"
    fi
    if [[ $NOTIFY_PB == 1 ]]; then
        echo "CONTAINERS DOWN - Sending summary Pushbullet notification - these containers stopped: $NEW_ALERTS_STRING"
        PB_SUBJECT="CONTAINERS DOWN!!!"
        PB_MSG="$NEW_ALERTS_STRING down @ `date`"
        pushbullet "$PB_SUBJECT" "$PB_MSG"
    fi
    if [[ $NOTIFY_SLACK == 1 ]]; then
        echo "CONTAINERS DOWN - Sending summary Slack notification for - these containers stopped: $NEW_ALERTS_STRING"
        SLACK_SUBJECT="CONTAINERS DOWN!!!"
        SLACK_TEXT="$NEW_ALERTS_STRING down @ `date`"
        slack -u "docker-crontab-monitor" -c "#alert" -T "$SLACK_SUBJECT" -t "$SLACK_TEXT" -e ":whale:" -C red
    fi
    echo "-----------------------------------------------------"; echo
fi



# ======================================================================================================================================
# CLEARED ALERT NOTIFICATIONS
# ======================================================================================================================================

# Send individual cleared notifications (if flag set)
if [[ ! $CLEARED_ALERTS_STRING == "" ]] && [[ $NOTIFY_EVERY_INSTANCE == 1 ]]; then
    # loop through errors
    echo "-----------------------------------------------------"
    for i in "${!CLEARED_ALERTS_ARRAY[@]}"; do
        if [[ $NOTIFY_EMAIL == 1 ]]; then
            echo "CONTAINER UP - Sending email notification for "${CLEARED_ALERTS_ARRAY[i]}...
            echo "${CLEARED_ALERTS_ARRAY[i]} up at `date`. Container downtime: ${CLEARED_ALERTS_DURATION_SECS_PRETTY_ARRAY[i]}" | $MAIL_BIN -s "${CLEARED_ALERTS_ARRAY[i]} CONTAINER UP!!!" "$EMAIL_ADDRESS"
        fi
        if [[ $NOTIFY_PB == 1 ]]; then
            echo "CONTAINER UP - Sending Pushbullet notification for "${CLEARED_ALERTS_ARRAY[i]}
            PB_SUBJECT="${CLEARED_ALERTS_ARRAY[i]} CONTAINER UP!!!"
            PB_MSG="${CLEARED_ALERTS_ARRAY[i]} up @ `date`. Container downtime: ${CLEARED_ALERTS_DURATION_SECS_PRETTY_ARRAY[i]}"
            pushbullet "$PB_SUBJECT" "$PB_MSG"
        fi
        if [[ $NOTIFY_SLACK == 1 ]]; then
            echo "CONTAINER UP - Sending Slack notification for "${CLEARED_ALERTS_ARRAY[i]}
            SLACK_SUBJECT="${CLEARED_ALERTS_ARRAY[i]} CONTAINER UP!!!"
            SLACK_TEXT="${CLEARED_ALERTS_ARRAY[i]} up @ `date`. Container downtime: ${CLEARED_ALERTS_DURATION_SECS_PRETTY_ARRAY[i]}"
            slack -u "docker-crontab-monitor" -c "#alert" -T "$SLACK_SUBJECT" -t "$SLACK_TEXT" -e ":whale:" -C green
        fi
    done
    echo "-----------------------------------------------------"; echo
fi

# Send summary cleared notifications if CLEARED_ALERTS_STRING string not empty (if flag set)
if [[ ! $CLEARED_ALERTS_STRING == "" ]] && [[ $NOTIFY_SUMMARY == 1 ]]; then
    echo "-----------------------------------------------------"
    if [[ $NOTIFY_EMAIL == 1 ]]; then
        echo "CONTAINERS UP - Sending summary email notification - these containers back up: $CLEARED_ALERTS_STRING"
        echo "$CLEARED_ALERTS_STRING UP at `date`" | $MAIL_BIN -s "CONTAINERS UP!!!" "$EMAIL_ADDRESS"
    fi
    if [[ $NOTIFY_PB == 1 ]]; then
        echo "CONTAINERS UP - Sending summary Pushbullet notification - these containers back up: $CLEARED_ALERTS_STRING"
        PB_SUBJECT="CONTAINERS UP!!!"
        PB_MSG="$CLEARED_ALERTS_STRING up @ `date`"
        pushbullet "$PB_SUBJECT" "$PB_MSG"
    fi
    if [[ $NOTIFY_SLACK == 1 ]]; then
        echo "CONTAINERS UP - Sending summary Slack notification for - these containers back up: $CLEARED_ALERTS_STRING"
        SLACK_SUBJECT="CONTAINERS UP!!!"
        SLACK_TEXT="$CLEARED_ALERTS_STRING up @ `date`"
        slack -u "docker-crontab-monitor" -c "#alert" -T "$SLACK_SUBJECT" -t "$SLACK_TEXT" -e ":whale:" -C green
    fi
    echo "-----------------------------------------------------"; echo
fi


# ======================================================================================================================================
# UPDATE LOGS
# ======================================================================================================================================

# Update current alert list
printf "%-17s %-50s %-21s\n" "DateTime" "Container" "Downtime" > $LOG_EXISTING_ALERTS
printf "%-17s %-50s %-21s\n" "---------------" "--------------------------------------------------" "---------------------" >> $LOG_EXISTING_ALERTS
for i in "${!CONTINUING_ALERTS_ARRAY[@]}"; do
    printf "%-17s %-50s %-21s\n" "${CONTINUING_ALERTS_START_ARRAY[i]}" "${CONTINUING_ALERTS_ARRAY[i]}" "${CONTINUING_ALERTS_DURATION_SECS_PRETTY_ARRAY[i]}" >> $LOG_EXISTING_ALERTS
done
for i in "${!NEW_ALERTS_ARRAY[@]}"; do
    printf "%-17s %-50s %-21s\n" "$(date +%Y%m%d-%H%M%S)" "${NEW_ALERTS_ARRAY[i]}" >> $LOG_EXISTING_ALERTS
done

# Update warnings list
printf "%-17s %-50s\n" "DateTime" "Container" > $LOG_FIRST_WARN
printf "%-17s %-50s\n" "---------------" "----------------------" >> $LOG_FIRST_WARN
for i in "${!NEW_WARNINGS_ARRAY[@]}"; do
    printf "%-17s %-50s\n" "$(date +%Y%m%d-%H%M%S)" "${NEW_WARNINGS_ARRAY[i]}" >> $LOG_FIRST_WARN
done

# LOG_ALERT_HISTORY header - only uncomment if starting log from scratch
#printf "%-17s %-40s %-35s %-21\n" "DATE-TIME" "CONTAINER NAME" "STATUS" "DOWNTIME" > $LOG_ALERT_HISTORY
#printf "%-17s %-40s %-35s %-21\n" "-----------------" "----------------------------------------" "----------------" "---------------------" >> $LOG_ALERT_HISTORY
# Add entry to alerts log for new and cleared alerts
# Loop through new alerts
for i in "${!NEW_ALERTS_ARRAY[@]}"; do
    printf "%-17s %-40s %-35s %-21s\n" "$(date +%Y%m%d-%H%M%S)" "${NEW_ALERTS_ARRAY[i]}" "Container Down - Alert Sent" "" >> $LOG_ALERT_HISTORY
done
# loop through cleared alerts
for i in "${!CLEARED_ALERTS_ARRAY[@]}"; do
    printf "%-17s %-40s %-35s %-21s\n" "$(date +%Y%m%d-%H%M%S)" "${CLEARED_ALERTS_ARRAY[i]}" "Container Back Up" "${CLEARED_ALERTS_DURATION_SECS_PRETTY_ARRAY[i]}" >> $LOG_ALERT_HISTORY
done
# Loop through continuing alerts (could cause LARGE log file if not commented out)
#for i in "${!CONTINUING_ALERTS_ARRAY[@]}"; do
#    printf "%-17s %-40s %-35s %-21s\n" "$(date +%Y%m%d-%H%M%S)" "${CONTINUING_ALERTS_ARRAY[i]}" "Container Still Down" "${CONTINUING_ALERTS_DURATION_SECS_PRETTY_ARRAY[i]}" >> $LOG_ALERT_HISTORY
#done
# Loop through new warnings
for i in "${!NEW_WARNINGS_ARRAY[@]}"; do
    printf "%-17s %-40s %-35s %-21s\n" "$(date +%Y%m%d-%H%M%S)" "${NEW_WARNINGS_ARRAY[i]}" "Warning - Container Down - No Alert" "" >> $LOG_ALERT_HISTORY
done
# Loop through cleared warnings
for i in "${!CLEARED_WARNINGS_ARRAY[@]}"; do
    printf "%-17s %-40s %-35s %-21s\n" "$(date +%Y%m%d-%H%M%S)" "${CLEARED_WARNINGS_ARRAY[i]}" "Warning Cleared - Container Back Up" "" >> $LOG_ALERT_HISTORY
done

cat $LOG_ALERT_HISTORY


echo; echo

