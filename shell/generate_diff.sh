#!/bin/bash

TOP_PATCH_DIR=git_changes/changes

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
    git_changes/changes/
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
# $9 是否有特殊文件名
# $10 是否为链接文件
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
	if [ "#$6" != "#A" -a "#$6" != "#M" -a "#$6" != "#R" -a "#$6" != "#T" ]; then
		echo -en "$RED $1:$r_file change_type unknow (A M D R T) change_type=$6 $PLAIN"
		exit -1
	fi
	###如果本次提交是删除文件 或者 对于上次提交来说是增加文件则不需要 git show 出来
	if [ "#$8" == "#modified" -a "#$6" == "#D" -o "#$8" == "#original" -a "#$6" == "#A" ]; then
		rm -f $temp_file
	else
		if [ $9 -eq 0 ]; then
			git show $1:$r_file > $temp_file 2>/dev/null ;
			git_show_rst=$?
		else ##空格等文件名特殊处理
			echo "git show $1:$r_file > $temp_file 2>/dev/null" > /tmp/tmp_gen_diff.sh
			echo "exit \$?" >> /tmp/tmp_gen_diff.sh
			bash /tmp/tmp_gen_diff.sh
			git_show_rst=$?
			if [ $git_show_rst -ne 0 ]; then
				rm /tmp/tmp_gen_diff.sh
			fi
		fi

		if [ $git_show_rst -eq 0 ] ; then
			if [ $9 -eq 0 ]; then
				mkdir -p `dirname $7`
				mv -f $temp_file $7
				chmod $f_mode $7
				###链接文件处理
				if [ ${10} -eq 1 ]; then
					cd `dirname $7`
					ln -sf `cat $7` `basename $7`
					cd -
				fi
			else
				r_file_dirname=`echo $7 | sed -e 's/ /\\ /g' -e 's/(/\\(/g' -e 's/)/\\)/g' -e 's/&/\\&/g' -e 's/=/\\=/g' -e 's/;/\\;/g' | sed 's#[^/]*$##g'`
				r_file_basename=`echo $7 | sed -e 's/ /\\ /g' -e 's/(/\\(/g' -e 's/)/\\)/g' -e 's/&/\\&/g' -e 's/=/\\=/g' -e 's/;/\\;/g' | sed 's#[^/]*/##g'`
				r_file_name=`echo $7 | sed -e 's/ /\\ /g' -e 's/(/\\(/g' -e 's/)/\\)/g' -e 's/&/\\&/g' -e 's/=/\\=/g' -e 's/;/\\;/g'`
				echo "mkdir -p $r_file_dirname " > /tmp/tmp_gen_diff.sh
				echo "exit \$?" >> /tmp/tmp_gen_diff.sh
				bash /tmp/tmp_gen_diff.sh
				if [ $? -ne 0 ]; then
					echo -e "$RED mkdir -p $r_file_dirname fail"
					rm /tmp/tmp_gen_diff.sh
					exit -1
				fi
				echo "mv -f $temp_file $r_file_name" > /tmp/tmp_gen_diff.sh
				echo "if [ ${10} -eq 1 ]; then" >> /tmp/tmp_gen_diff.sh
				echo "	cd $r_file_dirname" >> /tmp/tmp_gen_diff.sh
				echo "	ln -sf \`cat $r_file_name\` $r_file_basename" >> /tmp/tmp_gen_diff.sh
				echo "fi" >> /tmp/tmp_gen_diff.sh
				echo "exit \$?" >> /tmp/tmp_gen_diff.sh
				bash /tmp/tmp_gen_diff.sh
				if [ $? -ne 0 ];then
					echo -e "$RED mv -f $7 fail"
					rm /tmp/tmp_gen_diff.sh
					exit -1
				fi
				rm /tmp/tmp_gen_diff.sh
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
	TMP_FILE1=$(mktemp)
	git diff $REV1..$REV2 --raw > $TMP_FILE
	if [ $? -ne 0  ]; then
		echo "Error: git diff failed."
		rm -f $TMP_FILE
		exit -1;
	fi

	git log --raw $REV2 -1 > $TMP_FILE1

	create_dir
	cd $PATCH_DIR
	mv -f $TMP_FILE all_raw.diff
	mv -f $TMP_FILE1 commit_info

	####特殊字符检测
	special_char=`awk -F "\t" '{{if(NF>=3){print $2"___"$3} else {print $2}}}' all_raw.diff | grep "[ ()&;=]" | wc -l`
	if [ $special_char -ne 0 ]; then
		cp all_raw.diff all_raw.diff.bak
		awk -F "\t" '{{if(NF>=3){print $2"___"$3} else {print $2}}}' all_raw.diff | grep -n "[ ()&;=]" | awk -F ":" '{print $1}' > $PATCH_DIR/all_raw_space_lines
		special_lines=`cat $PATCH_DIR/all_raw_space_lines`
		### 存在特殊字符的行全部转移到 $PATCH_DIR/all_raw_special_char.diff 中
		touch $PATCH_DIR/all_raw_special_char.diff
		for s_line in  ${special_lines[@]}
		do
			awk 'NR=="'$s_line'" {print $0}' $PATCH_DIR/all_raw.diff >> $PATCH_DIR/all_raw_special_char.diff
		done
		### 这里使用 sort -n -r 倒序排列 存在特殊字符的行号
		### 然后使用sed -i 删除存在特殊字符的行
		sort -n -r $PATCH_DIR/all_raw_space_lines > $PATCH_DIR/all_raw_space_lines.r
		special_lines=`cat $PATCH_DIR/all_raw_space_lines.r`
		for s_line in  ${special_lines[@]}
		do
			sed -i "${s_line}d"  $PATCH_DIR/all_raw.diff
		done
		rm -f $PATCH_DIR/all_raw_space_lines
		rm -f $PATCH_DIR/all_raw_space_lines.r
	fi

	LOG "Generating diff, please wait..."
	##这里将all_raw.diff按照个文件10000行的方式分割
	##一个很大的提交差异全部保存在shell数组中会出现溢出的情况
	page_ard_size=10000
	ard_len=`cat all_raw.diff | wc -l`
	page_ard_len=`expr $ard_len / $page_ard_size`
	if [ `expr $ard_len % $page_ard_size` -ne 0 ]; then
		page_ard_len=`expr $page_ard_len + 1`
	fi
	if [ $page_ard_len -eq 1 ]; then
		cp all_raw.diff all_raw_0
	fi
	for((ardp_i=0;ardp_i<$page_ard_len;ardp_i++))
	do
		start_line=`expr $ardp_i \* $page_ard_size + 1`
		end_line=`expr $ardp_i \* $page_ard_size + $page_ard_size`
		sed -n "$start_line , $end_line p" $PATCH_DIR/all_raw.diff > $PATCH_DIR/all_raw_$ardp_i
	done
	for((ardp_i=0;ardp_i<$page_ard_len;ardp_i++))
	do
		file_actions=(`awk '{print $5}' $PATCH_DIR/all_raw_$ardp_i`)
		file_olds=(`awk '{print $6}' $PATCH_DIR/all_raw_$ardp_i`)
		file_news=(`awk '{if(NF==7){print $7} else {print $6}}' $PATCH_DIR/all_raw_$ardp_i`)
		file_modes_news=(`awk '{print $2}' $PATCH_DIR/all_raw_$ardp_i`)
		file_modes_old=(`awk '{print $1}' $PATCH_DIR/all_raw_$ardp_i`)
		for((i=0;i<${#file_olds[@]};i++ ))
		do
			if [ `expr $i % 100` -eq 0 ]; then
				echo -n "."
			fi
			file_action=${file_actions[i]}
			file_action=${file_action:0:1}
			file_mode_new=${file_modes_news[i]}
			file_mode_old=${file_modes_old[i]}
			is_link_file=0
			if [ $file_mode_new -eq 120000 ]; then
				is_link_file=1
			fi

			### 160000是git的子模块 这里直接退出
			if [ $file_mode_new -eq 160000 ]; then
				echo -e "$RED error  at $REV2 ${file_olds[i]} ${file_news[i]} is git submodule  $PLAIN"
				exit -1
			fi

			file_mode_new=${file_mode_new:1}
			file_mode_old=${file_mode_old:1}
			cp_file_rev $REV1 ${file_olds[i]} ${file_news[i]} $file_mode_new $file_mode_old $file_action original/${file_olds[i]} original $special_char $is_link_file
			cp_file_rev $REV2 ${file_olds[i]} ${file_news[i]} $file_mode_new $file_mode_old $file_action modified/${file_news[i]} modified $special_char $is_link_file
		done
	done

	#### 特殊字符文件名 在这里处理
	if [ $special_char -ne 0 ]; then
		echo -e "\n special file name was detected at $REV2 or $REV1"
		all_size=`cat $PATCH_DIR/all_raw_special_char.diff | wc -l`
		for((a_size_i=1;a_size_i<=$all_size;a_size_i++))
		do
			if [ `expr $a_size_i % 100` -eq 0 ]; then
				echo -n "."
			fi
			file_old=`awk -F "\t" 'NR=="'$a_size_i'" {if(NF>=2){print  $2} }' $PATCH_DIR/all_raw_special_char.diff | sed -e 's/ /\\\\ /g' -e 's/(/\\\\(/g' -e 's/)/\\\\)/g' -e 's/&/\\\\&/g' -e 's/=/\\\\=/g' -e 's/;/\\\\;/g'`
			file_new=`awk -F "\t" 'NR=="'$a_size_i'" {if(NF==3){print  $3} else {print $2}}' $PATCH_DIR/all_raw_special_char.diff | sed -e 's/ /\\\\ /g' -e 's/(/\\\\(/g' -e 's/)/\\\\)/g' -e 's/&/\\\\&/g' -e 's/=/\\\\=/g' -e 's/;/\\\\;/g'`
			file_mode_new=`awk 'NR=="'$a_size_i'" {print $2}' $PATCH_DIR/all_raw_special_char.diff`
			file_mode_old=`awk 'NR=="'$a_size_i'" {print $1}' $PATCH_DIR/all_raw_special_char.diff`
			file_action=`awk 'NR=="'$a_size_i'" {print $5}' $PATCH_DIR/all_raw_special_char.diff`
			is_link_file=0
			if [ $file_mode_new -eq 120000 ]; then
				is_link_file=1
			fi
			if [ $file_mode_new -eq 160000 ]; then
				echo -e "$RED error  at $REV2 \"$file_old\" \"$file_new\"  is git submodule $PLAIN"
				exit -1
			fi

			file_mode_new=${file_mode_new:1}
			file_mode_old=${file_mode_old:1}
			file_action=${file_action:0:1}
			cp_file_rev $REV1 "$file_old" "$file_new" $file_mode_new $file_mode_old $file_action "original/$file_old" original $special_char $is_link_file
			cp_file_rev $REV2 "$file_old" "$file_new" $file_mode_new $file_mode_old $file_action "modified/$file_new" modified $special_char $is_link_file
		done
	fi
	rm $PATCH_DIR/all_raw* -rf

	echo -en "\n"
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
