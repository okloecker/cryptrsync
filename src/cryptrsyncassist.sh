#!/usr/bin/env bash
set -o nounset
set -o errexit

# Assistant for cryptrsync.sh that reads the command line parameters from a
# configuration file ($HOME/.config/cryptrsync/autostarts
# Config file must have 5 elements (N.B. no whitespace before or after semicolon!):
# <id>;<method>;<plaindir>;<cryptdir>;<url>
#
# Example config entries:
#Private;rsync;/home/user/Private;/home/user/Private_gocrypt;user@example.com:/home/user/Private_gocrypt
#Media;rclone;/home/user/Bigfiles;/home/user/Bigfiles_gocrypt;gmailuser:gocrypt/Bigfiles_gocrypt
#
# Call with the ID defined in the configuration file.
# ./cryptrsyncassist.sh 
# --sync=<id>
# [--dry-run] 
# --log=<logfile>
#
# List IDs: --showconfig

cd `dirname $0`
readonly cryptrsyncprog=./cryptrsync.sh
readonly configdir=$HOME/.config/cryptrsync
readonly autostartsfile=${configdir}/autostarts
declare -A ids
declare -A methods
declare -A plaindirs
declare -A syncdirs
declare -A urls

dryrun=""
idtosync=""
showconfig=0

readonly DATE='date +%Y-%m-%d_%H:%M:%S'
# log file
LOG=${configdir}/log
logdir=`dirname "${LOG}"`
function echo_log {
  local f=${LOG}_${1}
  echo -e `$DATE`" $2" |tee -a ${f}
}

loadConfig() {
  if [ -e "${autostartsfile}" ] ; then
    echo_log ""  "============ Reading config from ${autostartsfile}"
    local lineNo=1
    while read line || [[ -n "$line" ]]; do
      IFS=\; read id method ldir sdir rurl <<< "${line}"

      # ignore lines starting with "#"
      [ "${id#"#"}" != "${id}" ] && continue

      if [ -z "${id}" ] || [ -z "${method}" ] || [ -z "${ldir}" ] || [ -z "${sdir}" ] || [ -z "${rurl}" ] ; then
        echo_log ""  "============ incorrect config file in line ${lineNo}"
        exit 1
      fi

      ids[${id}]="${id}"
      methods[${id}]="${method}"
      eval plaindirs[${id}]="${ldir}"
      eval syncdirs[${id}]="${sdir}"
      urls[${id}]="${rurl}"

      ((lineNo++))
    done < "${autostartsfile}"

  else 
    echo `date +"%Y-%m-%d %H:%M:%S"` "============ No config file ${autostartsfile}"
    exit 2
  fi
}

mountgocrypt() {
  local id=${1:-""} 
  # mount syncdir if necessary
  if [ -n "${id}" ] ; then
    local syncdir=${syncdirs[${id}]}
    local plaindir=${plaindirs[${id}]}
    if [ ! -e "${syncdir}/gocryptfs.diriv" ] ; then
      echo_log "${id}"  "============ Reverse mounting crypted dir ${syncdir}"
      echo_log "${id}"  "Enter gocrypt password for ${plaindir} - ${syncdir}:"
      gocryptfs -reverse -q "${plaindir}" "${syncdir}" 
    else
      echo_log "${id}"  "============ Crypted dir already mounted: ${syncdir}"
    fi
  fi
}

function finish {
  echo_log ""  "============ Exiting"
}
trap finish EXIT

parseoptions() {
  for arg in $*; do
     # Split arg on "=". It is OK to have an "=" in the value, but not
     # the key.
     key=$(   echo ${arg} | cut --delimiter== --fields=1  )
     value=$( echo ${arg} | cut --delimiter== --fields=2- )

     case ${key} in
         "-h")
         ;&
         "--help")
          echo "Options: --dry-run"
          echo "         --sync=<ID>"
          echo "         --showconfig"
          echo "         --log=<logfile>"
          echo " any other option is interpreted as ID" 
          echo " default logfile: ${LOG}"
          exit 0
         ;;

         "--dry-run")
           dryrun="--dry-run"
           ;;
         "--sync")
           idtosync="${value}"
           ;;
         "--showconfig")
           showconfig=1
           ;;
         "--log")
           LOG="${value}"
           logdir=`dirname "${LOG}"`
           ;;
         *)
          idtosync="${arg}"
          ;;
     esac
  done
}

main() {
  parseoptions $@

  [ -d "${logdir}" ] || mkdir "${logdir}"
  if [ -z "${idtosync}" ] ; then
    echo_log "" "\e[1m============ No ID supplied\e[0m"
    exit 1
  fi

  loadConfig 
  echo_log "" "Log file: ${LOG}"

  if [ ${showconfig} = 1 ] ; then
    echo_log "" "============ Config:"
    for id in "${!ids[@]}"; do
      echo "[${id}]"
      echo "          Plain dir ${plaindirs[${id}]}"
      echo "          Synced dir ${syncdirs[${id}]}"
      echo "          Remote Url ${urls[${id}]}"
      echo "          Method ${methods[${id}]}"
    done
    exit
  fi

  if [ -z "${ids[${idtosync}]:-""}" ] ; then
    echo_log "" "\e[1m============ No config for [$idtosync] found\e[0m"
  fi

  for id in "${!ids[@]}"; do
    local id=${ids[${id}]}
    local method=${methods[${id}]}
    local syncdir=${syncdirs[${id}]}
    local plaindir=${plaindirs[${id}]}
    local url=${urls[${id}]}
    if [ "${id}" = "${idtosync}" ] ; then
      #mountgocrypt ${id}
      echo_log ""  "\e[1m===== Calling syncdir.sh for [$id]\e[0m"
      ${cryptrsyncprog} ${dryrun} --id="${id}" --method="${method}" --plaindir="${plaindir}" --syncdir="${syncdir}" --url="${url}" --log=${LOG}_${id}
    fi

  done

#  echo "Assist: I AM $$"
}

main $@
