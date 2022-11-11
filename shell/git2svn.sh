#/bin/bash

###脚本大体分为两步：1.从git仓库中”git show" 每次commit的历史文件 我们称为（生成补丁）
###                  2.将每次commit的历史文件同步到svn仓库        我们成为（打入补丁）
### 大致原理如下：
### 1. 本脚本主要通过 git diff $REV1..$REV2 --raw 来从git仓库中获得每次commit的修改并保存在all_raw.diff中
### 2. 然后通过解析all_raw.diff文件,使用git show $commit_id  file 的方式将每次commit_id的修改的文件全部show 出来
###      同时每个commit都会生成一个名为svn_repo_sync_command.sh的脚本用于将"git show"出来的文件同步到svn仓库中
### 3.同时会有一个patch_all.sh的脚本来统一管理好这些"svn_repo_sync_command.sh"脚本（每次成功执行一次
###      svn_repo_sync_command.sh后patch_all.sh脚本会自动只掉要调用该svn_repo_sync_command.sh的代码行）

### 该脚本需要如下前提条件
### 已经配置好需要同步的git仓库和svn仓库(git仓库和svn仓库下均能正常执行git 或 svn相关命令 而不需要每次输入密码)
### 如下实例：
### 确保配置好需要同步的git svn仓库：如下所述
### 1.工作目录下有两个文件夹(git_repo svn_repo)和一个文件(git2svn.sh)
###      git_repo svn_repo git2svn.sh
###   git_repo 表示git仓库 这个仓库能够正常执行git status 、git log 、 git pull 等操作(不需要输入用户名密码)
###   svn_repo 表示svn仓库 这个仓库能够正常执行svn st 、svn log 、 git up 等操作(不需要输入用户名密码)
### 2.执行./git2svn.sh -b main -g git_repo -s svn_repo
###     其中 -b 表示 同步 git 仓库的 main分支
###     其中 -g 表示 同步 git 仓库的 所在目录
###     其中 -s 表示 同步 svn 仓库的 所在目录
### 3.初次执行./git2svn.sh -b main -g git_repo -s svn_repo会如下出错信息：(因为脚本还不知道需要从git 的那次提交开始同步)
###      ./git2svn.sh -b main -g wifi/ -s svn_wifi/
###       Please fill in a long commit id (wifi repository ) or |"null" into
###      /home/work/workspace/git/test/wifi/.sync_git_to_svn/main_latest_commit_id
###    需要在git仓库wifi的.sync_git_to_svn/main_latest_commit_id中填写最后一次成功同步的commit id
###    也可以输入在该文件第一行中填入 null 表示从git 仓库第一次commit 开始同步
### 4.git2svn.sh脚本完成的第一步（生成补丁）后 会在 git_repo svn_repo git2svn.sh同级目录下生成 patchs_git_to_svn
###     文件夹，该文件夹下会根据 仓库名_分支/日期_序号/ 的方式生成二级文件夹 该文件夹下包含前文提到的 patch_all.sh 脚本
###     和所有的（生成补丁）步骤中的历史文件
###   正常情况下 git2svn.sh 脚本会自动调用 patch_all.sh 脚本来实现git 到 svn 的同步
###   如果出现错误可以根据错误提示确认错误发生的原因，出来好后再次手动调用patch_all.sh脚本可以完成后续未完成的事情
### 5.成功执行同步后git2svn.sh脚本会主动删除 patchs_git_to_svn/仓库名_分支/日期_序号/ 文件夹
###   否则生成的 patchs_git_to_svn/仓库名_分支/日期_序号/ 文件夹不会被删除



RED="\033[31m"
BLUE="\033[34m"
PLAIN='\033[0m'

PWD=`pwd`
g_index=0
NOT_PULL=0

SVN_CMD_FILE=svn_repo_sync_command.sh
SVN_COMM_FILE=svn_commit_file
GIT_SYNC_LOG_FOLDER=.sync_git_to_svn

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
##$2 表示追加的文件
git_repo_get_commitid_msg()
{
	curr_pwd=`pwd`
	cd $GIT_REPO_DIR
	echo -en "\t" >> $2
	git log --pretty=format:"%s" -1 $1 >> $2
	echo -en "\t" >> $2
	git log --pretty=format:"%b" -1 $1  >> $2
	echo -en "\tgit_commit_id:$1" >> $2
	cd $curr_pwd
}


###生成shell函数 check_git_cmid_patch_to_svn 
gen_check_git_cmd()
{
	echo "check_git_cmid_patch_to_svn()" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "{" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "	commit_id=$REV2" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "	curr_pwd=\`pwd\`" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "	cd \$SVN_REPO_DIR" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "	svn_find=\`svn log  | grep  -P \"git_commit_id:[0-9a-fA-F]{40}\" | grep \$commit_id | wc -l\`" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "	if [ \$svn_find -ne 0 ]; then" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "		echo \"$REV2 patched to svn repository and skip\"" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "		echo \"$REV2\" > \$GIT2SVN_TOP/../$GIT_NAME/$GIT_SYNC_LOG_FOLDER/${BR_NAME}_latest_commit_id" >> $PATCH_DIR/$SVN_CMD_FILE
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
	sed_pre=`expr $3 \* 8 + 22`
	sed_next=`expr $sed_pre + 6`
	echo "if [ \$? -ne 0 ]; then" >> $2
	echo "	echo $1 " >> $2
	echo "	exit -1" >> $2
	echo "else" >> $2
	echo "	sed -i '$sed_pre,$sed_next s/^/#/' \$GIT2SVN_TOP/\$BR_DIR/patch_all.sh" >> $2
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
	bank_i=`expr $g_index / 1000`
	REV2_NAME=$bank_i/${num_index}_$REV2
	mkdir -p ${PATCH_DIR_DATE}/$REV2_NAME/modified
	PATCH_DIR_MODIFIED=${PATCH_DIR_DATE}/$REV2_NAME/modified
}

###生成 find_top函数
### $1 生成在哪个shell脚本中
gen_find_top()
{
	echo "find_topdir()" >> $1
	echo "{" >> $1
	echo "	if [ \"\${0:0:1}\" == \"/\" ]; then" >> $1
	echo "		dir=\"\$0\"" >> $1
	echo "	else" >> $1
	echo "		dir=\"\`pwd\`/\$0\"" >> $1
	echo "	fi" >> $1
	echo "	cd \`dirname \$dir\`" >> $1
	echo "	if [ \"X\$GIT2SVN_TOP\" == \"X\" ]; then " >> $1
	echo "		echo \`while true; do if [ -f GIT2SVN_PATCH_TOP.flag ]; then pwd;exit; else cd ..;if [ \"\\\`pwd\\\`\" == \"/\" ]; then echo \"\"; exit; fi;fi;done;\` " >> $1
	echo "	else " >> $1
	echo "		echo \$GIT2SVN_TOP" >> $1
	echo "	fi" >> $1
	echo "}" >> $1
	echo "GIT2SVN_TOP=\`find_topdir\`" >> $1
	echo "if [ \"#\$GIT2SVN_TOP\" == \"#\" ]; then" >> $1
	echo "	echo \"cannot find top!!!!!\"" >> $1
	echo "	exit -1" >> $1
	echo "fi" >> $1
	echo "BR_DIR=${GIT_NAME}_$BR_NAME/$BASE_PATCH_DIRNAME" >> $1
}


###检测命令是否存在 $1 需要检测的命令
check_cmd()
{
	for cmd_i in $*
	do
		res=`which $cmd_i 2>/dev/null`
		if [[ "$?" != "0" ]]; then
			echo -e " ${RED} $cmd_i not exist please install $cmd_i ${PLAIN}";
			exit 1
		fi
	done
	
}

# $1 is revision, $2 源文件, $3 新文件, $4 修改的文件权限
# $5 文件的属性（增加：A  删除：D  修改：M  重命名：R  类型变更 T）
# $6 是否有空格文件名
cp_file_rev()
{
	cd $GIT_REPO_DIR
	temp_file=$(mktemp)
	r_file=$2
	if [ $6 -eq 0 ]; then
		r_dirname_org=`dirname $2`
		r_dirname_new=`dirname $3`
	else
		r_dirname_org=`echo $2 | sed -e 's/ /\\ /g' -e 's/(/\\(/g' -e 's/)/\\)/g' -e 's/&/\\&/g' | sed 's#[^/]*$##g'`
		r_dirname_new=`echo $3 | sed -e 's/ /\\ /g' -e 's/(/\\(/g' -e 's/)/\\)/g' -e 's/&/\\&/g' | sed 's#[^/]*$##g'`
	fi
	svn_a_cmd=""
	svn_d_cmd=""

	####重命名的情况
	if [ "#$5" == "#R" ]; then
		r_file=$3
		###删除源文件（写入$SVN_CMD_FILE 脚本）
		echo "rm \$SVN_REPO_DIR/$2 -rf " >> $PATCH_DIR/$SVN_CMD_FILE
		svn_d_cmd="$2"
		svn_a_cmd="$r_file"

		####重命名的文件夹加入待处理pending_folder
		echo "$r_dirname_org" >> $PATCH_DIR/pending_folder

		echo "mkdir -p \$SVN_REPO_DIR/$r_dirname_new 2>/dev/null" >> $PATCH_DIR/$SVN_CMD_FILE
		echo "cp \$PATCH_DIR_MODIFIED/$r_file \$SVN_REPO_DIR/$r_dirname_new -rf" >> $PATCH_DIR/$SVN_CMD_FILE
		gen_pre_cmd_check "\"exec cp \$PATCH_DIR_MODIFIED/$r_file \$SVN_REPO_DIR/$r_dirname_new -rf fail\"" $PATCH_DIR/$SVN_CMD_FILE
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
		echo "rm \$SVN_REPO_DIR/$r_file -rf" >> $PATCH_DIR/$SVN_CMD_FILE
		svn_d_cmd="$r_file"
		echo "cd \$SVN_REPO_DIR" >> $PATCH_DIR/$SVN_CMD_FILE
		if [ "$svn_d_cmd" != "" ]; then
			echo "svn delete $svn_d_cmd" >> $PATCH_DIR/$SVN_CMD_FILE
			gen_pre_cmd_check "exec svn delete $svn_d_cmd fail" $PATCH_DIR/$SVN_CMD_FILE
		fi

		####删除的文件的dirname 加入待处理pending_folder中
		echo "$r_dirname_new" >> $PATCH_DIR/pending_folder

	else
		if [ $6 -eq 0 ]; then
			git show $1:$r_file > $temp_file 2>/dev/null ;
			git_show_rst=$?
		else ##空格等文件名特殊处理
			echo "git show $1:$r_file > $temp_file 2>/dev/null" > /tmp/tmp_git2svn.sh
			echo "exit \$?" >> /tmp/tmp_git2svn.sh
			bash /tmp/tmp_git2svn.sh
			git_show_rst=$?
			if [ $git_show_rst -ne 0 ]; then
				rm /tmp/tmp_git2svn.sh
			fi
		fi

		if [ $git_show_rst -eq 0 ] ; then
			###在补丁文件夹中生成文件
			if [ $6 -eq 0 ]; then
				mkdir -p `dirname $PATCH_DIR_MODIFIED/$r_file`
				mv -f $temp_file $PATCH_DIR_MODIFIED/$r_file
			else ##空格文件名特殊处理
				r_file_full=`echo $PATCH_DIR_MODIFIED/$r_file | sed -e 's/ /\\ /g' -e 's/(/\\(/g' -e 's/)/\\)/g' -e 's/&/\\&/g' | sed 's#[^/]*$##g'`
				echo "mkdir -p $r_file_full " > /tmp/tmp_git2svn.sh
				echo "exit \$?" >> /tmp/tmp_git2svn.sh
				bash /tmp/tmp_git2svn.sh
				if [ $? -ne 0 ]; then
					echo -e "$RED mkdir -p \`dirname $PATCH_DIR_MODIFIED/$r_file fail"
					rm /tmp/tmp_git2svn.sh
					exit -1
				fi
				echo "mv -f $temp_file $PATCH_DIR_MODIFIED/$r_file" > /tmp/tmp_git2svn.sh
				echo "exit \$?" >> /tmp/tmp_git2svn.sh
				bash /tmp/tmp_git2svn.sh
				if [ $? -ne 0 ];then
					echo -e "$RED mv -f $temp_file $PATCH_DIR_MODIFIED/$r_file fail"
					rm /tmp/tmp_git2svn.sh
					exit -1
				fi
				rm /tmp/tmp_git2svn.sh
			fi
			###生成svn补丁脚本
			echo "mkdir -p \$SVN_REPO_DIR/$r_dirname_new 2>/dev/null" >> $PATCH_DIR/$SVN_CMD_FILE
			echo "cp \$PATCH_DIR_MODIFIED/$r_file \$SVN_REPO_DIR/$r_dirname_new -rf" >> $PATCH_DIR/$SVN_CMD_FILE
			gen_pre_cmd_check "\"exec cp \$PATCH_DIR_MODIFIED/$r_file \$SVN_REPO_DIR/$r_dirname_new -rf fail\"" $PATCH_DIR/$SVN_CMD_FILE
			if [ "#$5" == "#A" ]; then
				# array_add[${#array_add[*]}]=$r_file
				svn_a_cmd="$r_file"
			elif [ "#$5" == "#M" -o "#$5" == "#T" ]; then
				###nothing to do
				echo -n ""
			elif [ "#$5" == "#R" ]; then
				echo "at $1 $2 rename to $3"
			else
				echo -en "$RED $1:$r_file change_type unknow (A M D R T) change_type=$5 $PLAIN"
				exit -1
			fi
			###文件权限管理
			echo "chmod $4 \$SVN_REPO_DIR/$r_file" >> $PATCH_DIR/$SVN_CMD_FILE
			echo "cd \$SVN_REPO_DIR" >> $PATCH_DIR/$SVN_CMD_FILE

			if [ "$svn_d_cmd" != "" ]; then
				echo "svn delete $svn_d_cmd" >> $PATCH_DIR/$SVN_CMD_FILE
				gen_pre_cmd_check "exec svn delete $svn_d_cmd fail" $PATCH_DIR/$SVN_CMD_FILE
			fi
			if [ "$svn_a_cmd" != "" ]; then
				echo "svn add --parents $svn_a_cmd" >> $PATCH_DIR/$SVN_CMD_FILE
				gen_pre_cmd_check "exec svn add --parents $svn_a_cmd fail" $PATCH_DIR/$SVN_CMD_FILE
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

	echo "Processing $REV2"

	TMP_FILE=$(mktemp)
	####renameLimit设置为1048576
	git config diff.renameLimit 1048576
	####设置中文路径乱码的问题
	git config core.quotepath false
	###$REV1和$REV2相等时只需要git diff $REV1 --raw 既可
	if [ "#$REV1" == "#$REV2" ]; then
		git show --raw $REV1 > $TMP_FILE
		### 使用git show --raw $REV1 > $TMP_FILE 后 $TMP_FILE 等信息与 git diff $REV1..$REV2 --raw > $TMP_FILE
		### 不一样所以这里通过sed删除前面几行git commit message信息 这里第一次提交必定时添加文件 所以 grep -nE
		### 的时候匹配了 A 这新增的动作
		show_raw_n=`grep -nE "^:[0-9]{6} [0-9]{6} [0-9a-f]+ [0-9a-f]+ A" $TMP_FILE | sed -n '1p' | awk -F ":" '{print $1}'`
		if [ "#$show_raw_n" != "#" ];then
			show_raw_n=`expr $show_raw_n - 1`
			sed -i "1,${show_raw_n}d" $TMP_FILE
		fi
	else
		git diff $REV1..$REV2 --raw > $TMP_FILE
	fi
	if [ $? -ne 0  ]; then
		echo "Error: git diff failed."
		rm -f $TMP_FILE
		exit -1;
	fi

	create_patch_dir
	PATCH_DIR=${PATCH_DIR_DATE}/$REV2_NAME
	cd $PATCH_DIR

	touch $PATCH_DIR/pending_folder

	###生成svn补丁脚本（初始化svn补丁脚本）
	echo "#!/bin/bash" > $PATCH_DIR/$SVN_CMD_FILE
	gen_find_top $PATCH_DIR/$SVN_CMD_FILE
	echo "SVN_REPO_DIR=\$GIT2SVN_TOP/../$SVN_NAME" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "PATCH_DIR_MODIFIED=\$GIT2SVN_TOP/\$BR_DIR/$REV2_NAME/modified" >> $PATCH_DIR/$SVN_CMD_FILE
	gen_check_git_cmd
	#echo "cd $SVN_REPO_DIR" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "cd \$SVN_REPO_DIR" >> $PATCH_DIR/$SVN_CMD_FILE
	gen_svn_st_check $PATCH_DIR/$SVN_CMD_FILE
	###清空svn空间 后 svn up 一下
	echo "svn up " >> $PATCH_DIR/$SVN_CMD_FILE
	
	###svn补丁脚本加入总的执行脚本中
	echo "\$GIT2SVN_TOP/\$BR_DIR/$REV2_NAME/$SVN_CMD_FILE" >> ${PATCH_DIR_DATE}/patch_all.sh
	gen_pre_if_else "\"exec  \$GIT2SVN_TOP/\$BR_DIR/$REV2_NAME/$SVN_CMD_FILE  fail\"" ${PATCH_DIR_DATE}/patch_all.sh $3

	chmod +x ${PATCH_DIR_DATE}/patch_all.sh
	chmod +x $PATCH_DIR/$SVN_CMD_FILE

	mv -f $TMP_FILE all_raw.diff


	####特殊字符检测
	#special_char=`awk '{{if(NF>4){print 1} else {print 0}}}' all_raw.diff`
	special_char=`awk -F "\t" '{{if(NF>=3){print $2"___"$3} else {print $2}}}' all_raw.diff | grep " " | wc -l`
	if [ $special_char -eq 0 ]; then
		special_char=`grep "[()&]" all_raw.diff | wc -l`
	fi

	if [ $special_char -eq 0 ]; then
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
				cp_file_rev $REV2 ${file_olds[i]} ${file_news[i]} $file_mode $file_action $special_char
			done
		done
	else
		echo -e "$BLUE special file name was detected at $REV2 $PLAIN"
		all_size=`cat all_raw.diff | wc -l`
		for((a_size_i=1;a_size_i<=$all_size;a_size_i++))
		do
			if [ `expr $a_size_i % 100` -eq 0 ]; then
				echo -n "."
			fi
			file_old=`awk  -F "\t" 'NR=="'$a_size_i'" {if(NF>=2){print  $2} }' $PATCH_DIR/all_raw.diff | sed -e 's/ /\\\\ /g' -e 's/(/\\\\(/g' -e 's/)/\\\\)/g' -e 's/&/\\\\&/g'`
			file_new=`awk  -F "\t" 'NR=="'$a_size_i'" {if(NF==3){print  $3} else {print $2}}' $PATCH_DIR/all_raw.diff | sed -e 's/ /\\\\ /g' -e 's/(/\\\\(/g' -e 's/)/\\\\)/g' -e 's/&/\\\\&/g'`
			file_mode=`awk 'NR=="'$a_size_i'" {print $2}' $PATCH_DIR/all_raw.diff`
			file_action=`awk 'NR=="'$a_size_i'" {print $5}' $PATCH_DIR/all_raw.diff`
			file_mode=${file_mode:1}
			file_action=${file_action:0:1}
			cp_file_rev $REV2 "$file_old" "$file_new" $file_mode $file_action $special_char
		done
	fi
	rm $PATCH_DIR/all_raw_* -rf

	###生成svn补丁脚本(提交信息 提交命令等)
	echo "[`git_repo_get_commitid_author $REV2`] [`git_repo_get_commitid_date $REV2`]" > $PATCH_DIR/$SVN_COMM_FILE
	git_repo_get_commitid_msg $REV2 $PATCH_DIR/$SVN_COMM_FILE
	dos2unix $PATCH_DIR/$SVN_COMM_FILE &> /dev/null

	sort -u -r $PATCH_DIR/pending_folder > $PATCH_DIR/temp_folder
	mv $PATCH_DIR/temp_folder $PATCH_DIR/pending_folder

	###特殊字符检测
	special_char=`grep "[ ()&]" $PATCH_DIR/pending_folder | wc -l`
	space_folder_line=(`cat $PATCH_DIR/pending_folder | wc -l`)
	###处理可能需要删除的文件夹
	if [ $special_char -eq 0 ]; then
		page_sfl_size=5000
		if [ $space_folder_line -ne 0 ]; then
			sfl_page_len=`expr $space_folder_line / $page_sfl_size`
			if [ `expr $space_folder_line % $page_sfl_size` -ne 0 ]; then
				sfl_page_len=`expr $sfl_page_len + 1`
			fi
			echo "cd \$SVN_REPO_DIR" >> $PATCH_DIR/$SVN_CMD_FILE
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
					echo "		svn delete \$tmp_ar" >> $PATCH_DIR/$SVN_CMD_FILE
					echo "		tmp_ar=\`echo \$tmp_ar | sed -e 's# #\\\\ #g' -e 's#(#\\\\(#g' -e 's#)#\\\\)#g' -e 's#&#\\\\&#g' | sed  -e 's#/+\$##g' -e 's#/*[^/]*\$##g'\`" >> $PATCH_DIR/$SVN_CMD_FILE
					echo "	done" >> $PATCH_DIR/$SVN_CMD_FILE
					echo "fi" >> $PATCH_DIR/$SVN_CMD_FILE
				done
			done
		fi
	else ###文件名中有特殊字符的处理
		for((sp_ap_i=1;sp_ap_i<=$space_folder_line;sp_ap_i++))
		do
			ap=`sed -n "${sp_ap_i}p" $PATCH_DIR/pending_folder`
			echo "tmp_ar=$ap" >> $PATCH_DIR/$SVN_CMD_FILE
			echo "if [ ! -d \$tmp_ar ]; then" >> $PATCH_DIR/$SVN_CMD_FILE
			echo "	svn delete \$tmp_ar" >> $PATCH_DIR/$SVN_CMD_FILE
			echo "else" >> $PATCH_DIR/$SVN_CMD_FILE
			echo "	while [ \"#\`ls -A \$tmp_ar\`\" == \"#\" ]" >> $PATCH_DIR/$SVN_CMD_FILE
			echo "	do" >> $PATCH_DIR/$SVN_CMD_FILE
			echo "		svn delete \$tmp_ar" >> $PATCH_DIR/$SVN_CMD_FILE
			echo "		tmp_ar=\`echo \$tmp_ar | sed -e 's# #\\\\ #g' -e 's#(#\\\\(#g' -e 's#)#\\\\)#g' -e 's#&#\\\\&#g' | sed  -e 's#/+\$##g' -e 's#/*[^/]*\$##g'\`" >> $PATCH_DIR/$SVN_CMD_FILE
			echo "	done" >> $PATCH_DIR/$SVN_CMD_FILE
			echo "fi" >> $PATCH_DIR/$SVN_CMD_FILE
		done
	fi

	####svn commit 提交
	echo "cd \$SVN_REPO_DIR" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "svn commit -F \$PATCH_DIR_MODIFIED/../$SVN_COMM_FILE " >> $PATCH_DIR/$SVN_CMD_FILE
	###生成判断函数 上条命令是否执行成功
	gen_pre_cmd_check "\"svn commit -F \$PATCH_DIR_MODIFIED/../$SVN_COMM_FILE fail\"" $PATCH_DIR/$SVN_CMD_FILE
	echo "echo \"$REV2\" > \$GIT2SVN_TOP/../$GIT_NAME/$GIT_SYNC_LOG_FOLDER/${BR_NAME}_latest_commit_id" >> $PATCH_DIR/$SVN_CMD_FILE
	echo "$REV2 success git show to $PATCH_DIR"
}


main()
{
	cd $GIT_REPO_DIR
	if [ "#$1" == "#null" ]; then
		lastest_n=`git log --format=%H | wc -l`
	else
		lastest_n=`git log --format=%H | grep -n $1 | awk -F ":" '{print $1}'`
	fi
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
		gen_find_top ${PATCH_DIR_DATE}/patch_all.sh

		n_hast=(`git log --format=%H -$lastest_n`)
		gen_patch_index=0
		if [ "#$1" == "#null"  ]; then
			gen_patch ${n_hast[lastest_n-1]} ${n_hast[lastest_n-1]} $gen_patch_index
			gen_patch_index=`expr $gen_patch_index + 1`
		fi
		for((j=${#n_hast[@]}; j>=2; j--))
		do
			gen_patch ${n_hast[j-1]} ${n_hast[j-2]} $gen_patch_index
			gen_patch_index=`expr $gen_patch_index + 1`
		done
	else
		echo -e "$RED latest success commit id ($1) not find \n please check $LATEST_COMMIT_ID $PLAIN"
		exit -1
	fi
}


####检测svn仓库和git仓库文件夹是否存在
check_svn_git_name()
{
	if [ ! -d $SVN_NAME ];then
		echo "arg -s $SVN_NAME not exist"
		exit -1
	fi

	if [ ! -d $GIT_NAME ];then
		echo "arg -g $GIT_NAME not exist"
		exit -1
	fi
}


init()
{
	###删除最后一个斜杠 /
	GIT_NAME=${GIT_NAME%/}
	SVN_NAME=${SVN_NAME%/}

	SVN_REPO_DIR=$PWD/$SVN_NAME
	GIT_REPO_DIR=$PWD/$GIT_NAME
	GIT_BRANCH_NAME=$BR_NAME
	LATEST_COMMIT_ID=$GIT_REPO_DIR/$GIT_SYNC_LOG_FOLDER/${BR_NAME}_latest_commit_id

	if [ ! -d $GIT_REPO_DIR/$GIT_SYNC_LOG_FOLDER ]; then
		mkdir $GIT_REPO_DIR/$GIT_SYNC_LOG_FOLDER
	fi

	if [ ! -e $LATEST_COMMIT_ID ]; then
		echo -e "$RED Please fill in a long commit id ($GIT_NAME repository ) or |\"null\" into"
		echo -e "$LATEST_COMMIT_ID $PLAIN"
		exit -1
	fi

	###生成补丁路径
	TOP_PATCH_DIR=patchs_git_to_svn/${GIT_NAME}_$BR_NAME
	if [ ! -d $PWD/patchs_git_to_svn ]; then
		mkdir -p $PWD/patchs_git_to_svn
	fi
	if [ ! -e  $PWD/patchs_git_to_svn/GIT2SVN_PATCH_TOP.flag ]; then
		touch $PWD/patchs_git_to_svn/GIT2SVN_PATCH_TOP.flag
	fi
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

	#检测$GIT_REPO_DIR/$GIT_SYNC_LOG_FOLDER 是否正确
	if [ "#`sed -n '1p' $LATEST_COMMIT_ID`" == "#null" ];then
		COMMIT_HASH="null"
	else
		COMMIT_HASH=`sed -n '1p' $LATEST_COMMIT_ID | grep -o -P "^[0-9a-fA-F]{40}"`
		if [ "#$COMMIT_HASH" == "#" ]; then
			echo -e "$RED $LATEST_COMMIT_ID format error"
			echo -e "\t1.commit_id must be a long commit_id(40 characters hash) "
			echo -e "\t2.commit_id must be on one line and no other characters $PLAIN"
			exit -1
		fi
	fi

}



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

update_svn_git()
{
	###git svn 仓库都更新到最新
	if [ $NOT_PULL -eq 0 ]; then
		git_pull_git_repo
		svn_update_repo
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


check_cmd dos2unix sed git

#####
check_svn_git_name
init
update_svn_git
git_check_br

##主函数
main $COMMIT_HASH


###打入补丁
if [ -e ${PATCH_DIR_DATE}/patch_all.sh ]; then
	${PATCH_DIR_DATE}/patch_all.sh
fi

if [ $? -ne 0 ]; then
	echo "An error occurred while executing the ${PATCH_DIR_DATE}/patch_all.sh "
	exit -1
else
	rm  ${PATCH_DIR_DATE}/ -rf
	echo "git to svn success!!!"
fi
