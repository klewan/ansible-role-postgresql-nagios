#!/bin/sh
# File: check_postgres_backup_to_Networker.sh
#
# This is a Nagios plugin that queries Networker server to check PostgreSQL backups
#
# History:
#
# Date       Author       Comments
# ---------- ------------ ----------------------------------------------
# 06/11/2018 KLewandowski Created
# ----------------------------------------------------------------------
#

# Nagios return codes
#
RC_OK=0
RC_WARNING=1
RC_CRITICAL=2
RC_UNKNOWN=3

# Default return code
#
RC=$RC_OK

# variables
#
typeset -i ARCH_DAYS_WARN
typeset -i ARCH_DAYS_CRIT
typeset -i FULL_DAYS_WARN
typeset -i FULL_DAYS_CRIT
typeset -i ARCH_HOURS_WARN
typeset -i ARCH_HOURS_CRIT
typeset -i FULL_HOURS_WARN
typeset -i FULL_HOURS_CRIT
DEBUG=0
PGTAB=/etc/pgtab

NSR_SERVER=$(awk ' $1!~ /[#*]/ {print $1} ' /nsr/res/servers 2>/dev/null| head -1)
NSR_CLIENT="$(hostname -s)-nsr.$(echo $NSR_SERVER | awk -F. '{$1="";OFS="." ; print $0}' | sed 's/^.//')"

# Parse input parameters
#
if [ $# -ne 3 ]
then
  echo "SYNTAX : $0 CLUSTER_NAME arch_days_warn:arch_days_crit full_days_warn:full_days_crit"
  exit 1
fi

CLUSTER_NAME=$1
ARCH_DAYS_WARN=${2%%:*}
ARCH_DAYS_CRIT=${2##*:}
FULL_DAYS_WARN=${3%%:*}
FULL_DAYS_CRIT=${3##*:}

if [ ! $ARCH_DAYS_WARN -gt 0 ] || [ ! $ARCH_DAYS_CRIT -gt 0 ] || [ $ARCH_DAYS_WARN -ge $ARCH_DAYS_CRIT ] ||
   [ ! $FULL_DAYS_WARN -gt 0 ] || [ ! $FULL_DAYS_CRIT -gt 0 ] || [ $FULL_DAYS_WARN -ge $FULL_DAYS_CRIT ]
then
  echo "INFO: Something is wrong with input parameters. Exiting.."
  exit $RC_UNKNOWN
fi

ARCH_HOURS_WARN=$((24 * $ARCH_DAYS_WARN))
ARCH_HOURS_CRIT=$((24 * $ARCH_DAYS_CRIT))
FULL_HOURS_WARN=$((24 * $FULL_DAYS_WARN))
FULL_HOURS_CRIT=$((24 * $FULL_DAYS_CRIT))

if [ $DEBUG -eq 1 ]; then
  cat <<EOT
DEBUG> ARCH_DAYS_WARN: $ARCH_DAYS_WARN
DEBUG> ARCH_DAYS_CRIT: $ARCH_DAYS_CRIT
DEBUG> FULL_DAYS_WARN: $FULL_DAYS_WARN
DEBUG> FULL_DAYS_CRIT: $FULL_DAYS_CRIT
DEBUG> ARCH_HOURS_WARN: $ARCH_HOURS_WARN
DEBUG> ARCH_HOURS_CRIT: $ARCH_HOURS_CRIT
DEBUG> FULL_HOURS_WARN: $FULL_HOURS_WARN
DEBUG> FULL_HOURS_CRIT: $FULL_HOURS_CRIT
EOT
fi

#
# read pgtab file
#

PGTABENTRY=$(awk ' $1!~ /[#*]/ {print $1} ' $PGTAB | sed '/^$/d' | cut -d: -f1,2,3,4 | grep -v ':dummy' | grep -w $CLUSTER_NAME | tail -1)
if [ -n "$PGTABENTRY" ]; then
  export PGDATABASE=`echo $PGTABENTRY |cut -d: -f1`
  export PGHOME=`echo $PGTABENTRY |cut -d: -f2`
  export PGDATA=`echo $PGTABENTRY |cut -d: -f3`
  export PGPORT=`echo $PGTABENTRY |cut -d: -f4`
else
  echo "ERROR: Cannot find an entry for $CLUSTER_NAME instance in $PGTAB file"
  exit 1
fi

if [ "$(whoami)" == "root" ]; then
  SUDO=""
else
  SUDO="sudo -E "
fi

CLUSTER_STATE=$($SUDO $PGHOME/bin/pg_controldata | grep -i "Database cluster state" | cut -d: -f2 | sed 's/^ *//')

if [ ! "$CLUSTER_STATE" == "in production" ]; then
  echo "OK: This PostgreSQL cluster is not in production state. Skipping checks .."
  exit $RC_OK
fi

# Query Networker server
#

LAST_FULL_BACKUP_TIME=$(mminfo -s $NSR_SERVER -oRt -r 'name,savetime(22)' -q "client=${NSR_CLIENT}" 2>/dev/null | grep PG_FULL_DATA_${CLUSTER_NAME}_TAG | head -1 | sed 's/^[^ ]* //')
LAST_ARCH_BACKUP_TIME=$(mminfo -s $NSR_SERVER -oRt -r 'name,savetime(22)' -q "client=${NSR_CLIENT}" 2>/dev/null | egrep "(PG_FULL_ARCH_${CLUSTER_NAME}_TAG|PG_ARCH_${CLUSTER_NAME}_TAG)" | head -1 | sed 's/^[^ ]* //')

if [ "$LAST_FULL_BACKUP_TIME" == "" ]; then
  echo "ERROR: there are no Full backups for ${CLUSTER_NAME} instance."
  exit $RC_CRITICAL
fi

if [ "$LAST_ARCH_BACKUP_TIME" == "" ]; then
  echo "ERROR: there are no WAL file archives backups for ${CLUSTER_NAME} instance."
  exit $RC_CRITICAL
fi

if [ $DEBUG -eq 1 ]; then
  cat <<EOT

DEBUG> LAST_FULL_BACKUP_TIME: $LAST_FULL_BACKUP_TIME
DEBUG> LAST_ARCH_BACKUP_TIME: $LAST_ARCH_BACKUP_TIME
EOT
fi

LAST_ARCH_BACKUP_SECONDS=$(date -d "$LAST_ARCH_BACKUP_TIME" +%s)
LAST_FULL_BACKUP_SECONDS=$(date -d "$LAST_FULL_BACKUP_TIME" +%s)

if [ $DEBUG -eq 1 ]; then
  cat <<EOT

DEBUG> LAST_ARCH_BACKUP_SECONDS: $LAST_ARCH_BACKUP_SECONDS
DEBUG> LAST_FULL_BACKUP_SECONDS: $LAST_FULL_BACKUP_SECONDS
EOT
fi

# Print output
#
echo -n "Postgres backup: ${CLUSTER_NAME}: "

echo -n "last Arch backup: $LAST_ARCH_BACKUP_TIME ("
if [ $(date -d "now - $ARCH_DAYS_WARN days" +%s) -lt $LAST_ARCH_BACKUP_SECONDS ]; then
  echo -n "OK"
  A_RC=$RC_OK
elif [ $(date -d "now - $ARCH_DAYS_CRIT days" +%s) -lt $LAST_ARCH_BACKUP_SECONDS ]; then
  echo -n "WARNING"
  A_RC=$RC_WARNING
else
  echo -n "CRITICAL"
  A_RC=$RC_CRITICAL
fi

echo -n "): last Full backup: $LAST_FULL_BACKUP_TIME ("
if [ $(date -d "now - $FULL_DAYS_WARN days" +%s) -lt $LAST_FULL_BACKUP_SECONDS ]; then
  echo -n "OK"
  F_RC=$RC_OK
elif [ $(date -d "now - $FULL_DAYS_CRIT days" +%s) -lt $LAST_FULL_BACKUP_SECONDS ]; then
  echo -n "WARNING"
  F_RC=$RC_WARNING
else
  echo -n "CRITICAL"
  F_RC=$RC_CRITICAL
fi
echo ")"

RC=$A_RC
if [ $F_RC -gt $RC ]; then
  RC=$F_RC
fi

exit $RC

