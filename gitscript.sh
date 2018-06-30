#!/bin/bash
###########################################
#To automate the git push
###########################################
getParamsFromCli()
{
    USAGE="usage: ${0##*/} -m <Commit message>"
    if [ $# -eq 0 ] ; then
    echo -e "\\033[33;31m No arguments supplied - ${USAGE} \\033[0m" >&2
    exit 1
    fi

    while getopts ":m:" opt "$@"; do
        case $opt in
        m)
            MESSAGE=\'$OPTARG\'
            functionCall
        ;;
        *)
            echo -e "\\033[33;31m Unimplemented option: -$OPTARG - $USAGE \\033[0m" >&2
        ;;  
        esac
    done
}
functionCall()
{
    echo $MESSAGE
    git add --all
    git commit -m '$MESSAGE'
    git push -u origin master
}

getParamsFromCli "$@"
