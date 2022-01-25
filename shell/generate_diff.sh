#!/bin/bash

TOP_PATCH_DIR=git_changes/change

RED="\033[31m"
PLAIN='\033[0m'

QUIET=0
#-----------------------------------------------------------------------------------------
usage() {
  cat << END
usage: `basename $0` [options] <commit_id>
    Generate changes of commit_id
options:
    -q:           quiet mode
output structure:
    git_changes/change/
            |--commit_id
            |   |--all.diff
            |   |--original
            |   |   |-- xxxxx
            |   |--modified
            |       |-- yyyyy
examples:
    $0 88d7d2fae78d7e57aad87e0b46239ce29ae80df4
END
}

LOG()
{
  if [ ${QUIET} -eq 0 ]; then
      echo "[$PROG_NAME] $*"
  fi
}


get_rev()
{
	change_list=(`git log $1 -2 --format=%H`)
	if [ $? -ne 0 ]; then
		echo -e "$RED $1 not exist $PLAIN"
		exit -1
	fi
	REV1=${change_list[1]}
	REV2=${change_list[0]}
}

create_dir()
{
	if [ -d $PATCH_DIR/original ]; then
		rm $PATCH_DIR/original -rf
	fi
	if [ -d $PATCH_DIR/modified ]; then
		rm $PATCH_DIR/modified -rf
	fi
	mkdir -p $PATCH_DIR/original
	mkdir -p $PATCH_DIR/modified
}

# $1 is revision, $2 源文件, $3 新文件, $4 新的修改的文件权限 $5 老的修改的文件权限
# $6 文件的属性（增加：A  删除：D  修改：M  重命名：R）
# $7 文件保存的位置  $8（original/modified）
cp_file_rev()
{
	temp_file=$(mktemp)
	r_file=$2
	f_mode=$4

	####重命名的情况
	if [ "#$6" == "#R" ]; then
		r_file=$3
	fi
	####删除操作需要记录老的文件权限
	if [ "#$6" == "#D" ]; then
		f_mode=$5
	fi

	#### 针对文件的修改（A D M R）操作
	if [ "#$6" == "#D" -o "#$6" == "#A" ]; then
		if [ "#$6" == "#D" -a "#$8" == "#original" -o "#$8" == "#modified" -a "#$6" == "#A" ]; then
			if git show $1:$r_file > $temp_file 2>/dev/null; then
				mkdir -p `dirname $7`
				mv -f $temp_file $7
				chmod $f_mode $7
			else
				echo -e "$RED at $1 (git show $1:$r_file) fail change_type=$6"
				echo -e "patch at $7"
				echo -e "you can  cat $PATCH_DIR/all_raw.diff  check all changes $PLAIN"
				exit -1
			fi
		else
			rm -f $temp_file
		fi
	else
		if git show $1:$r_file > $temp_file 2>/dev/null; then
			mkdir -p `dirname $7`
			mv -f $temp_file $7
			chmod $f_mode $7

			if [ "#$6" != "#A" -a "#$6" != "#M" -a "#$6" != "#R" ]; then
				echo -en "$RED $1:$r_file change_type unknow (A M D R) change_type=$6 $PLAIN"
				exit -1
			fi
		else
			echo -e "$RED at $1 (git show $1:$r_file) fail change_type=$6"
			echo -e "patch at $7"
			echo -e "you can  cat $PATCH_DIR/all_raw.diff  check all changes $PLAIN"
			exit -1
		fi
	fi
}


main()
{
	cd $PROJ_TOP

	TMP_FILE=$(mktemp)
	git diff $REV1..$REV2 --raw > $TMP_FILE 
	if [ $? -ne 0  ]; then
		echo "Error: git diff failed."
		rm -f $TMP_FILE
		exit -1;
	fi

	create_dir
	cd $PATCH_DIR
	mv -f $TMP_FILE all_raw.diff

	LOG "Generating diff, please wait..."
	modified_files=`sed -n '/diff --git/p' all_raw.diff | awk '{print $3}'`
	file_news=(`awk '{if(NF==7){print $7} else {print $6}}' all_raw.diff`)
	file_mode_news=(`awk '{print $2}' all_raw.diff`)
	file_mode_olds=(`awk '{print $1}' all_raw.diff`)
	file_actions=(`awk '{print $5}' all_raw.diff`)
	file_olds=(`awk '{print $6}' all_raw.diff`)
	for((i=0;i<${#file_news[@]};i++ ))
		do
			file_action=${file_actions[i]}
			file_action=${file_action:0:1}
			file_mode_new=${file_mode_news[i]}
			file_mode_new=${file_mode_new:1}
			file_mode_old=${file_mode_olds[i]}
			file_mode_old=${file_mode_old:2}
			cp_file_rev $REV1 ${file_olds[i]} ${file_news[i]} $file_mode_new $file_mode_old $file_action original/${file_olds[i]} original
			cp_file_rev $REV2 ${file_olds[i]} ${file_news[i]} $file_mode_new $file_mode_old $file_action modified/${file_news[i]} modified
		done
	LOG "Two diffs were successfully generated to $PATCH_DIR"

}

#----------------------------------------------------------------------
PROG_NAME=`basename $0`
while getopts "q:" options; do
	case "$options" in
		q) QUIET=1 ;;
		\?) usage; exit -1;;
	esac
done

shift $((OPTIND - 1))

if [ $# -lt 1 ]; then
	usage
	exit 0
fi

get_rev $1

PROJ_TOP=`git rev-parse --show-toplevel`
if [ $? -ne 0 ];then
	exit -1
fi

if [ "#$PROJ_TOP" == "#" ]; then
	echo "$RED not a git repository (or any of the parent directories) $PLAIN"
	exit -1
fi

PATCH_DIR=$PROJ_TOP/$TOP_PATCH_DIR/$1

main
