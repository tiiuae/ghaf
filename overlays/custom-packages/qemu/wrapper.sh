#!/bin/bash -e
argv0="$0"
declare -a list=()
while [ -n "$1" ]; do
    case "$1" in
         vfio-pci,host=*)
            read -r unquoted < <(eval echo "$1")
            list+=("$unquoted")
         ;;
         *)
            list+=("$1")
         ;;
    esac     
    shift
done

exec -a "${argv0}" @UNWRAPPED@ "${list[@]}"
