#!/bin/bash


git_check_br()
{
	curr_pwd=`pwd`
	cd $GIT_NAME
	curr_br=`git branch | grep -P "^\*" | awk '{print $2}'`
	local_br=`git branch --all | grep "$BR_NAME\$" | wc -l`
	if [ $local_br -eq 0 ]; then
		echo -e "$RED\n branch ($BR_NAME) not exist in ${GIT_NAME} \n$PLAIN"
		exit -1
	fi
	if [ "$curr_br" != "$BR_NAME" ];then
		echo " git switch to $BR_NAME ing ... please wait"
		git checkout $BR_NAME
		if [ $? -ne 0 ]; then
			echo -e "$RED\n git checkout $BR_NAME error \n$PLAIN"
			exit -1
		fi
	fi
	cd $curr_pwd
}

usage()
{
	echo -e "\tshow git log "
	echo -e "\t$0 -b -g -n "
	echo -e "\t-g git_repo_path_name \n\t-b git_branch_name \n\t-n git log count"
	echo -e "\tfor example: "
	echo -e "\t\t$0 -b dev_ugw6.0_main -g UGW_main -n 5"
	exit -1
}

while getopts "b:g:n:" OPT
do
	case $OPT in
		b)
		BR_NAME=$OPTARG ;;
		g)
		GIT_NAME=$OPTARG ;;
		n)
		N_COUNT=$OPTARG ;;
		?)
		usage;;
	esac
done

if [ "#$BR_NAME" == "#" ]; then
	usage
fi

if [ ! -d $GIT_NAME  ]; then
	usage
fi


git_check_br
cd $GIT_NAME && git log -$N_COUNT