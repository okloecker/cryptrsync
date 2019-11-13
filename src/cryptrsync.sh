#!/usr/bin/env bash
set -o nounset
set -o errexit

# script to watch a directory and if any changes occur, sync this with a remote,
# either using rclone or rsync
# There is a distinction between dir to watch and local dir to allow use of gocrypt:
# inotifywait can't watch the encrypted view, only the original dir

# call with parameters:
# ./cryptrsync.sh
# [--id=<uniqueID>]
# [--dry-run]
# --method=<rsync|rclone>
# --plaindir=<unencrypted dir> --syncdir=<encrypted dir> --url=<rsync or rclone url>
# --log=<logfile>

readonly ignore="\.~lock\..*#|\.sw?|~$|4913"
# readonly rclone=/opt/rcb/usr/bin/rclone #`which rclone`
readonly rclone=`which rclone`
rcloneopts="--progress --stats=2s"
rsyncopts="--archive --stats --delete --progress --human-readable --compress --update"
readonly delay="5"
readonly delayAfterFail="30"
readonly popupduration=5000
readonly configdir=$HOME/.config/cryptrsync
readonly DATE='date +%Y-%m-%d_%H:%M:%S'
LOG=${configdir}/log_cryptrsync
id="cryptrsync"
method=${1}
plaindir=${2}
syncdir=${3}
url=${4}
dryrun=0

# whether to use rclone (or rsync) (1=rclone, 0=rsync)
use_rclone=0

function echo_log {
  echo -e `$DATE`" [${id}] $1" |tee -a ${LOG}
}

function visualsleep {
  echo "Waiting $1 secs"
  for i in `seq $1` ; do
    echo -n . ; sleep 1
  done
}

alert(){
   notify-send -t $popupduration " 🔒  ${@}   `$DATE`  cryptrsync "
}
alert_fail(){
   notify-send -t $popupduration " 🔒  ${@}   `$DATE`  cryptrsync " --icon=${icon}
}

parseoptions() {
  for arg in $*; do
     # Split arg on "=". It is OK to have an "=" in the value, but not
     # the key.
     key=$(   echo ${arg} | cut --delimiter== --fields=1  )
     value=$( echo ${arg} | cut --delimiter== --fields=2- )

     case ${key} in
         "--id")
           id="${value}"
           ;;
         "--method")
           if [ "${value}" = "rclone" ] ; then
            use_rclone=1
          fi
          ;;
         "--dry-run")
           rcloneopts="${rcloneopts} --dry-run"
           rsyncopts="${rsyncopts} --dry-run"
           dryrun=1;;
         "--plaindir")
           plaindir=${value};;
         "--syncdir")
           syncdir=${value}
           ;;
         "--url")
           url=${value}
          ;;
         "--log")
           LOG="${value}"
           ;;
         *)
          echo_log "Unrecognised option ${key}"
              exit 1
     esac
  done
}

mountgocrypt() {
  # mount syncdir if necessary
  if [ ! -e "${syncdir}/gocryptfs.diriv" ] ; then
    echo_log "============ Reverse mounting crypted dir ${syncdir}"
    echo_log "Enter gocrypt password for ${plaindir} - ${syncdir}:"
    if which secret-tool
      then
        extpass="secret-tool lookup gocryptfs password"
        if [ -z `${extpass}` ] ; then  echo_log "\e[31m ===== COULD NOT FIND GNOME-KEYRING PASSWORD ===========\e[0m" ; fi
        gocryptfs -extpass "${extpass}" -reverse -q "${plaindir}" "${syncdir}"
      else
        gocryptfs -reverse -q "${plaindir}" "${syncdir}"
    fi
  else
    echo_log "============ Crypted dir already mounted: ${syncdir}"
  fi
}

function finish {
    if [ -n ${waitpid:-''} ] ; then
    echo_log "--- Cleaning up, killing $waitpid and removing $waitpidfile and ${changedfile}"
    echo
    rm -rf "${changedfile}" $waitpidfile
    kill $waitpid
  else
    echo_log "============ Exiting"
  fi
}
trap finish EXIT #SIGINT SIGTERM

lock() {
  local prefix=$1
  local fd=${2:-$LOCK_FD}
  local lock_file=$LOCKFILE_DIR/$prefix.lock

  # create lock file
  eval "exec $fd>$lock_file"

  # acquier the lock
  flock $fd \
    && return 0 \
    || return 1
}

unlock() {
  local fd=${1:-$LOCK_FD}
  flock -u $fd && return 0 || return 1
}

readchanges () {
  f="$1"
  lock changesfile || echo_log "Can\'t lock in readchanges()"
  echo_log "============ NOTIFIED CHANGE FOR $f"
  echo $f >> ${changedfile}
  unlock || echo_log "--- Couldn\'t remove lock"
}

startinotifyw() {
  ( inotifywait -m "${plaindir}" -r -e close_write,create,delete --format %w%f & echo $! >&3 ) 3>$waitpidfile | egrep --line-buffered -v ${ignore} |
    while read f ; do readchanges "$f" ; done &
  waitpid=$(<$waitpidfile)
  echo_log "PID of inotifywait ${waitpid}"
  echo_log "CHANGEDFILE ${changedfile}"
  echo_log "PIDFILE ${waitpidfile}"
}

sync () {
  local force=${1:-0}

  lock changesfile || echo_log "Can\'t lock in while"
  if [ $force = 1 ] || [ -s ${changedfile} ] ; then
    # sleep a little more between noticing changes and syncing to give processes
    # a chance to finish writing
    if [ $force = 0 ] ; then visualsleep $delay ; fi

    sort ${changedfile} | uniq | while read f ; do
      echo_log "============ SYNCING $f"
    done

    echo_log "......................................................."
    [ $dryrun -eq 1 ] && echo_log "\e[1m ===== DRY RUN ===========\e[0m"
    if [ $use_rclone = 1 ] ; then
      echo_log "\e[1m ============ CALLING rclone\e[0m"
      if which secret-tool ; then
        # rclone will read RCLONE_CONFIG_PASS environment variable and use it
        # for password if possible:
        export RCLONE_CONFIG_PASS=`secret-tool lookup rclone config`
        if [ -z "${RCLONE_CONFIG_PASS}" ] ; then  echo_log "\e[31m ===== COULD NOT FIND GNOME-KEYRING PASSWORD ===========\e[0m" ; fi
      fi
      cmd="${rclone} sync ${rcloneopts} ${syncdir} ${url}"
    else
      echo_log "\e[1m============ CALLING rsync at with options ${rsyncopts}\e[0m"
      cmd="rsync ${rsyncopts} ${syncdir}/ ${url}"
    fi

    echo "cmd=${cmd}"

    set +o errexit
    ${cmd} 2>&1 ; rv=$?
    set -o errexit
    if test ${rv} -eq 0 ; then alert "OK ${id}" ; fi
    echo_log "\e[1m ============ FINISHED ============ \e[0m"
    while test ${rv} -ne 0 ; do
      alert_fail "ERR ${id}" | tee -a "${LOG}"
      echo_log "\e[1mrsync failed\e[0m"
      visualsleep $delayAfterFail
      set +o errexit
      ${cmd} 2>&1 ; rv=$?
      set -o errexit
    done

    rm -f ${changedfile}
  fi
  unlock || echo_log "--- Couldn\'t remove lock"
}

main() {
  parseoptions $@

  readonly icon=/usr/share/icons/Adwaita/256x256/status/dialog-error.png
  readonly changedfile=`mktemp --suffix=_${id}_sync`
  readonly waitpidfile=`mktemp --suffix=_${id}_sync`

  readonly LOCKFILE_DIR=/tmp
  readonly LOCK_FD=9
  readonly LOCKWAIT=120

  mountgocrypt

  startinotifyw

  sync 1

  while true ; do
    sync

    sleep ${delay}s
  done
}

main $@
