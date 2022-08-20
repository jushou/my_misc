#/bin/bash

RED="\033[31m"
PLAIN='\033[0m'

PWD=`pwd`
g_index=0
NOT_PULL=0

SVN_CMD_FILE=svn_repo_sync_command.sh
SVN_COMM_FILE=svn_commit_file


##获取commit作者 $1 表示commit_id
git_repo_get_commitid_author()
{
	curr_pwd=`pwd`
	cd $GIT_REPO_DIR
	sub_author=`git log --pretty=format:"%an" -1 $1`
	cd $curr_pwd
	echo $sub_author
}

##获取commit日期  $1 表示commit_id
git_repo_get_commitid_date()
{
	curr_pwd=`pwd`
	cd $GIT_REPO_DIR
	sub_date=`git log --pretty=format:"%ad" --date=iso -1 $1`
	cd $curr_pwd
	echo $sub_date
}

##获取commit 提交的信息  $1 表示commit_id
git_repo_get_commitid_msg()
{
	curr_pwd=`pwd`
	cd $GIT_REPO_DIR
	sub_msg_s=`git log --pretty=format:"%s" -1 $1`
	sub_msg_b=`git log --pretty=format:"%b" -1 $1`
	cd $curr_pwd
	echo -en "\t$sub_msg_s\n\n\t$sub_msg_b\n\tgit_commit_id:$1"
}

##获取最新的commit_id
get_git_head_commit_id()
{
	curr_pwd=`pwd`
	cd $GIT_REPO_DIR
	head_commit=`git log -1 HEAD --pretty=format:"%H"`
	cd $curr_pwd
	echo $head_commit
}

###生成shell函数 check_git_cmid_patch_to_svn 
gen_check_git_cmd()
{
	echo "check_git_cmid_patch_to_svn()" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "{" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "	commit_id=$REV2" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "	curr_pwd=\`pwd\`" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "	cd $SVN_REPO_DIR" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "	svn_find=\`svn log  | grep  -P \"git_commit_id:[0-9a-fA-F]{40}\" | grep \$commit_id | wc -l\`" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "	if [ \$svn_find -ne 0 ]; then" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "		echo \"$REV2 patched to svn repository and skip\"" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "		exit 0" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "	fi" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "	cd \$curr_pwd" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "}" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "check_git_cmid_patch_to_svn" >> $PATCH_DIR/$SVN_CMD_FILE
	echo -ne "\n"  >> $PATCH_DIR/$SVN_CMD_FILE
}

####生成shell 判断语句 判断前一条命令是否执行成功
### $1 提示语（注意 提示语中有空格则需要用双引号包裹）  
### $2 生成在哪个shell脚本中
gen_pre_cmd_check()
{
	echo "if [ \$? -ne 0 ]; then" >> $2
	echo "	echo $1 " >> $2
	echo "	exit -1" >> $2
	echo "fi" >> $2
	echo -ne "\n"  >> $2
}

##执行成功就注释掉if else 语句
### $1 提示语（注意 提示语中有空格则需要用双引号包裹）  
### $2 生成在哪个shell脚本中
### $3 第几if else 语句
gen_pre_if_else()
{
	sed_pre=`expr $3 \* 8 + 2`
	sed_next=`expr $sed_pre + 6`
	echo "if [ \$? -ne 0 ]; then" >> $2
	echo "	echo $1 " >> $2
	echo "	exit -1" >> $2
	echo "else" >> $2
	echo "	sed -i '$sed_pre,$sed_next s/^/#/' $2" >> $2
	echo "fi" >> $2
	echo -ne "\n"  >> $2
}


###生成svn st检查脚本 在执行同步到svn之前 检查svn仓库是否是干净的
###不干净则会使用svn revert 是的仓库是干净的
### $1 生成在哪个shell脚本中
gen_svn_st_check()
{
	echo "svn_st=\`svn st ./ | wc -l\`" >> $1
	echo "if [ \$svn_st -ne 0 ]; then " >> $1
	echo "	echo \" sync $REV2 to svn The svn repository is not clean \"" >> $1
	echo "	echo \" now try to clean the svn repository \"" >> $1
	echo "	svn st ./ --no-ignore | awk '{print \$2}' | xargs rm -rf;svn revert ./ --depth infinity" >> $1
	echo "fi" >> $1
	echo -ne "\n"  >> $1
}


####补丁文件夹
create_patch_dir()
{
	g_index=`expr $g_index + 1`
	num_index=`printf "%05d" $g_index`
	REV2_NAME=${num_index}_$REV2
	mkdir -p ${PATCH_DIR_DATE}/$REV2_NAME/modified
	PATCH_DIR_MODIFIED=${PATCH_DIR_DATE}/$REV2_NAME/modified
}



# $1 is revision, $2 源文件, $3 新文件, $4 修改的文件权限
# $5 文件的属性（增加：A  删除：D  修改：M  重命名：R  类型变更 T）
cp_file_rev()
{
	cd $GIT_REPO_DIR
	temp_file=$(mktemp)
	r_file=$2
	r_dirname_org=`dirname $2`
	r_dirname_new=`dirname $3`
	svn_a_cmd=""
	svn_d_cmd=""

	####重命名的情况
	if [ "#$5" == "#R" ]; then
		r_file=$3
		###删除源文件（写入$SVN_CMD_FILE 脚本）
		echo "rm $SVN_REPO_DIR/$2 -rf " >> $PATCH_DIR/$SVN_CMD_FILE
		svn_d_cmd="$2"
		svn_a_cmd="$r_file"

		####重命名的文件夹加入待处理pending_folder
		echo "$r_dirname_org" >> $PATCH_DIR/pending_folder

		echo "mkdir -p $SVN_REPO_DIR/$r_dirname_new 2>/dev/null" >> $PATCH_DIR/$SVN_CMD_FILE
		echo "cp $PATCH_DIR_MODIFIED/$r_file $SVN_REPO_DIR/$r_dirname_new -rf" >> $PATCH_DIR/$SVN_CMD_FILE
		gen_pre_cmd_check "\"exec cp $PATCH_DIR_MODIFIED/$r_file $SVN_REPO_DIR/$r_dirname_new -rf fail\"" $PATCH_DIR/$SVN_CMD_FILE
	fi
	
	####其它用户有可执行权限才向svn中增加可执行权限
	exec_on=`expr $4 % 10`
	exec_on_cmd=""

	if [ $((exec_on & 1)) -eq 1 ]; then
		exec_on_cmd="svn propset svn:executable on $r_file"
	else
		exec_on_cmd="svn propdel svn:executable $r_file"
	fi

	#### 针对文件的修改（A D M R）操作
	if [ "#$5" == "#D" ]; then
		rm -f $temp_file 
		echo "rm $SVN_REPO_DIR/$r_file -rf" >> $PATCH_DIR/$SVN_CMD_FILE
		svn_d_cmd="$r_file"
		echo "cd $SVN_REPO_DIR" >> $PATCH_DIR/$SVN_CMD_FILE
		if [ "$svn_d_cmd" != "" ]; then
			echo "svn delete \"$svn_d_cmd\"" >> $PATCH_DIR/$SVN_CMD_FILE
			gen_pre_cmd_check "exec svn delete \"$svn_d_cmd\" fail" $PATCH_DIR/$SVN_CMD_FILE
		fi

		####删除的文件的dirname 加入待处理pending_folder中
		echo "$r_dirname_new" >> $PATCH_DIR/pending_folder

	else
		if git show $1:$r_file > $temp_file 2>/dev/null; then
			###在补丁文件夹中生成文件
			mkdir -p `dirname $PATCH_DIR_MODIFIED/$r_file`
			mv -f $temp_file $PATCH_DIR_MODIFIED/$r_file
			
			###生成svn补丁脚本
			echo "mkdir -p $SVN_REPO_DIR/$r_dirname_new 2>/dev/null" >> $PATCH_DIR/$SVN_CMD_FILE
			echo "cp $PATCH_DIR_MODIFIED/$r_file $SVN_REPO_DIR/$r_dirname_new -rf" >> $PATCH_DIR/$SVN_CMD_FILE
			gen_pre_cmd_check "\"exec cp $PATCH_DIR_MODIFIED/$r_file $SVN_REPO_DIR/$r_dirname_new -rf fail\"" $PATCH_DIR/$SVN_CMD_FILE
			if [ "#$5" == "#A" ]; then
				# array_add[${#array_add[*]}]=$r_file
				svn_a_cmd="$r_file"
			elif [ "#$5" == "#M" -o "#$5" == "#T"]; then
				###nothing to do
				echo -n ""
			elif [ "#$5" == "#R" ]; then
				echo "at $1 $2 rename to $3"
			else
				echo -en "$RED $1:$r_file change_type unknow (A M D R T) change_type=$5 $PLAIN"
				exit -1
			fi
			###文件权限管理
			echo "chmod $4 $SVN_REPO_DIR/$r_file" >> $PATCH_DIR/$SVN_CMD_FILE
			echo "cd $SVN_REPO_DIR" >> $PATCH_DIR/$SVN_CMD_FILE

			if [ "$svn_d_cmd" != "" ]; then
				echo "svn delete \"$svn_d_cmd\"" >> $PATCH_DIR/$SVN_CMD_FILE
				gen_pre_cmd_check "exec svn delete \"$svn_d_cmd\" fail" $PATCH_DIR/$SVN_CMD_FILE
			fi
			if [ "$svn_a_cmd" != "" ]; then
				echo "svn add --parents \"$svn_a_cmd\"" >> $PATCH_DIR/$SVN_CMD_FILE
				gen_pre_cmd_check "exec svn add --parents \"$svn_a_cmd\" fail" $PATCH_DIR/$SVN_CMD_FILE
			fi
			echo "$exec_on_cmd" >> $PATCH_DIR/$SVN_CMD_FILE
			gen_pre_cmd_check "\" exec $exec_on_cmd fail\"" $PATCH_DIR/$SVN_CMD_FILE
		else
			echo -e "$RED at $1 (git show $1:$r_file) fail change_type=$5"
			echo -e "patch at ${PATCH_DIR_DATE}/$REV2_NAME"
			echo -e "you can  cat ${PATCH_DIR_DATE}/$REV2_NAME/all_raw.diff  check all changes $PLAIN"
			exit -1
		fi
	fi
}


####生成补丁文件，并生成svn的同步脚本
gen_patch()
{
	cd $GIT_REPO_DIR
	REV1=$1
	REV2=$2

	TMP_FILE=$(mktemp)
	####renameLimit设置为1048576
	git config diff.renameLimit 1048576
	####设置中文路径乱码的问题
	git config core.quotepath false
	git diff $REV1..$REV2 --raw > $TMP_FILE 
	if [ $? -ne 0  ]; then
		echo "Error: git diff failed."
		rm -f $TMP_FILE
		exit -1;
	fi

	create_patch_dir
	PATCH_DIR=${PATCH_DIR_DATE}/$REV2_NAME
	cd $PATCH_DIR
	
	touch $PATCH_DIR/pending_folder

	###生成svn补丁脚本（初始话svn补丁脚本）
	echo "#!/bin/bash" > $PATCH_DIR/$SVN_CMD_FILE
	gen_check_git_cmd
	echo "cd $SVN_REPO_DIR" >> $PATCH_DIR/$SVN_CMD_FILE
	gen_svn_st_check $PATCH_DIR/$SVN_CMD_FILE
	###清空svn空间 后 svn up 一下
	echo "svn up " >> $PATCH_DIR/$SVN_CMD_FILE
	
	###svn补丁脚本加入总的执行脚本中
	echo $PATCH_DIR/$SVN_CMD_FILE >> ${PATCH_DIR_DATE}/patch_all.sh
	gen_pre_if_else "\"exec  $PATCH_DIR/$SVN_CMD_FILE   fail\"" ${PATCH_DIR_DATE}/patch_all.sh $3

	chmod +x ${PATCH_DIR_DATE}/patch_all.sh
	chmod +x $PATCH_DIR/$SVN_CMD_FILE

	mv -f $TMP_FILE all_raw.diff


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
		file_modes=(`awk '{print $2}' $PATCH_DIR/all_raw_$ardp_i`)
		file_actions=(`awk '{print $5}' $PATCH_DIR/all_raw_$ardp_i`)
		file_olds=(`awk '{print $6}' $PATCH_DIR/all_raw_$ardp_i`)
		file_news=(`awk '{if(NF==7){print $7} else {print $6}}' $PATCH_DIR/all_raw_$ardp_i`)
		for((i=0;i<${#file_olds[@]};i++ ))
		do
			if [ `expr $i % 100` -eq 0 ]; then
				echo -n "."
			fi
			file_action=${file_actions[i]}
			file_action=${file_action:0:1}
			file_mode=${file_modes[i]}
			file_mode=${file_mode:1}
			cp_file_rev $REV2 ${file_olds[i]} ${file_news[i]} $file_mode $file_action
		done
	done
	rm $PATCH_DIR/all_raw_* -rf

	###生成svn补丁脚本(提交信息 提交命令等)
	echo "[`git_repo_get_commitid_author $REV2`] [`git_repo_get_commitid_date $REV2`]" > $PATCH_DIR/$SVN_COMM_FILE
	git_repo_get_commitid_msg $REV2 >> $PATCH_DIR/$SVN_COMM_FILE

	sort -u -r $PATCH_DIR/pending_folder > $PATCH_DIR/temp_folder
	mv $PATCH_DIR/temp_folder $PATCH_DIR/pending_folder

	###处理可能需要删除的文件夹
	page_sfl_size=5000
	space_folder_line=(`cat $PATCH_DIR/pending_folder | wc -l`)
	if [ $space_folder_line -ne 0 ]; then
		sfl_page_len=`expr $space_folder_line / $page_sfl_size`
		if [ `expr $space_folder_line % $page_sfl_size` -ne 0 ]; then
			sfl_page_len=`expr $sfl_page_len + 1`
		fi
		echo "cd $SVN_REPO_DIR" >> $PATCH_DIR/$SVN_CMD_FILE
		for((sflp_i=0;sflp_i<$sfl_page_len;sflp_i++))
		do
			start_line=`expr $sflp_i \* $page_sfl_size + 1`
			end_line=`expr $sflp_i \* $page_sfl_size + $page_sfl_size`
			array_peding=(`sed -n "$start_line , $end_line p" $PATCH_DIR/pending_folder`)
			for ap in ${array_peding[@]}
			do
				echo "tmp_ar=$ap" >> $PATCH_DIR/$SVN_CMD_FILE
				echo "if [ ! -d \$tmp_ar ]; then" >> $PATCH_DIR/$SVN_CMD_FILE
				echo "	svn delete \$tmp_ar" >> $PATCH_DIR/$SVN_CMD_FILE
				echo "else" >> $PATCH_DIR/$SVN_CMD_FILE
				echo "	while [ \"#\`ls -A \$tmp_ar\`\" == \"#\" ]" >> $PATCH_DIR/$SVN_CMD_FILE
				echo "	do" >> $PATCH_DIR/$SVN_CMD_FILE
				echo "		svn delete \"\$tmp_ar\"" >> $PATCH_DIR/$SVN_CMD_FILE
				echo "		tmp_ar=\`dirname \$tmp_ar\`" >> $PATCH_DIR/$SVN_CMD_FILE
				echo "	done" >> $PATCH_DIR/$SVN_CMD_FILE
				echo "fi" >> $PATCH_DIR/$SVN_CMD_FILE
			done
		done
	fi
	####svn commit 提交
	echo "cd $SVN_REPO_DIR" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "svn commit -F $PATCH_DIR/$SVN_COMM_FILE " >> $PATCH_DIR/$SVN_CMD_FILE
	###生成判断函数 上条命令是否执行成功
	gen_pre_cmd_check "\"svn commit -F $PATCH_DIR/$SVN_COMM_FILE fail\"" $PATCH_DIR/$SVN_CMD_FILE
	echo "echo \"$REV2\" > $LATEST_COMMIT_ID" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "$REV2 success git show to $PATCH_DIR"
}


main()
{
	cd $GIT_REPO_DIR
	lastest_n=`git log --format=%H | grep -n $1 | awk -F ":" '{print $1}'`
	if [ "#$lastest_n" != "#" ]; then
		if [ $lastest_n -eq 1 ]; then
			echo "No commits to sync from git to svn"
			exit 0
		else
			echo "$lastest_n git commit finded"
			echo "Generating patch files, please wait"
		fi

		mkdir -p ${PATCH_DIR_DATE}
		echo "#!/bin/bash" > ${PATCH_DIR_DATE}/patch_all.sh

		n_hast=(`git log --format=%H -$lastest_n`)
		gen_patch_index=0
		for((j=${#n_hast[@]}; j>=2; j--))
		do
			gen_patch ${n_hast[j-1]} ${n_hast[j-2]} $gen_patch_index
			gen_patch_index=`expr $gen_patch_index + 1`
		done
	fi
}

usage()
{
	echo -e "\tgit_repo svn_repo and $0 must be in the same level directory "
	echo -e "\t$0 -b -g -s "
	echo -e "\t-g git_repo_path_name \n\t-b git_branch_name \n\t-s svn_repo_path_name "
	echo -e "\t-n not pull git and svn repo"
	echo -e "\tfor example: "
	echo -e "\t\t$0 -b main -g git_repo -s svn_repo"
	exit -1
}

if [ $# -eq 0 ]; then
	usage
fi

###参数检查
while getopts "g:s:b:n" OPT
do
	case $OPT in
		b)
		BR_NAME=$OPTARG ;;
		s)
		SVN_NAME=$OPTARG ;;
		g)
		GIT_NAME=$OPTARG ;;
		n)
		NOT_PULL=1 ;;
		?)
		usage;;
	esac
done


if [ ! -d $SVN_NAME ];then
	echo "arg -s $SVN_NAME not exist"
	exit -1
fi

if [ ! -d $GIT_NAME ];then
	echo "arg -g $GIT_NAME not exist"
	exit -1
fi


###删除最后一个斜杠 /
GIT_NAME=${GIT_NAME%/}
SVN_NAME=${SVN_NAME%/}

SVN_REPO_DIR=$PWD/$SVN_NAME
GIT_REPO_DIR=$PWD/$GIT_NAME
GIT_BRANCH_NAME=$BR_NAME
LATEST_COMMIT_ID=$GIT_REPO_DIR/.sync_git_to_svn/latest_commit_id

if [ ! -d $GIT_REPO_DIR/.sync_git_to_svn ]; then
	mkdir $GIT_REPO_DIR/.sync_git_to_svn
fi

if [ ! -e $LATEST_COMMIT_ID ]; then
	echo -e "$RED Please fill in a long commit id (GIT_NAME repository ) into"
	echo -e "$LATEST_COMMIT_ID $PLAIN"
	exit -1
fi


TOP_PATCH_DIR=patchs_git_to_svn/${GIT_NAME}_$BR_NAME
DATE=$(date +%Y-%m-%d)
date_index=1
while true
do
date_num=`printf "%04d" $date_index`
if [ ! -d $PWD/$TOP_PATCH_DIR/${DATE}_$date_num ]; then
	BASE_PATCH_DIRNAME=${DATE}_$date_num
	break
else
	date_index=`expr $date_index + 1`
fi
done
PATCH_DIR_DATE=$PWD/$TOP_PATCH_DIR/$BASE_PATCH_DIRNAME

####检查分支是否存在
git_check_br()
{
	curr_pwd=`pwd`
	cd $GIT_REPO_DIR
	curr_br=`git branch | grep -P "^\*" | awk '{print $2}'`
	local_br=`git branch --all | grep "$BR_NAME\$" | wc -l`
	if [ $local_br -eq 0 ]; then
		echo -e "$RED\n branch ($BR_NAME) not exist in ${GIT_NAME} \n$PLAIN"
		exit -1
	fi
	if [ "$curr_br" != "$BR_NAME" ];then
		git checkout $BR_NAME
		if [ $? -ne 0 ]; then
			echo -e "$RED\n git checkout $BR_NAME error \n$PLAIN"
			exit -1
		fi
	fi
	cd $curr_pwd
}

####git pull 到最新
git_pull_git_repo()
{
	curr_pwd=`pwd`
	cd $GIT_REPO_DIR
	git pull
	if [ $? -ne 0 ]; then
		echo -e "$RED\n git pull error \n$PLAIN"
		exit -1
	fi
	cd $curr_pwd
}

####svn仓库更新的最新
svn_update_repo()
{
	curr_pwd=`pwd`
	cd $SVN_REPO_DIR
	svn update ./
	if [ $? -ne 0 ]; then
		echo -e "$RED\n svn update ./ error \n$PLAIN"
		exit -1
	fi
	cd $curr_pwd
}

COMMIT_HASH=`sed -n '1p' $LATEST_COMMIT_ID | grep -o -P "^[0-9a-fA-F]{40}"`
if [ "#$COMMIT_HASH" == "#" ]; then
	echo -e "$RED $LATEST_COMMIT_ID format error"
	echo -e "\t1.commit_id must be a long commit_id(40 characters hash) "
	echo -e "\t2.commit_id must be on one line and no other characters $PLAIN"
	exit -1
fi

###git svn 仓库都更新到最新
if [ $NOT_PULL -eq 0 ]; then
	git_pull_git_repo
	svn_update_repo
fi

git_check_br

##主函数
main $COMMIT_HASH


###打入补丁
#${PATCH_DIR_DATE}/patch_all.sh
