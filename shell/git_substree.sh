#!/bin/bash


###要拆分的仓库名称
repo_name_list=(repo1, repo2, repo3, repo4)
###要拆分的仓库在主仓库的相对路径
repo_path_list=(module1/func1/repo1 module1/func1/repo2 module1/func1/repo3 module1/func1/repo4)

###主仓库名称
main_repo_name=repo_main

get_br_list()
{
	curr_pwd=`pwd`
	$curr_pwd/$main_repo_name
	echo `git branch -r | grep -v '\->' | awk -F "/" '{print $2}'`
	cd $curr_pwd
}


####列举所有主仓库分支
br_list=(`get_br_list`)

####分割所有仓库分支
subtree_split_all_br()
{
	curr_pwd=`pwd`
	for bl in ${br_list[@]}
	do
		cd $curr_pwd/$main_repo_name
		git checkout $bl
		for((i=0;i<${#repo_name_list[@]};i++ ))
		do
			if [ -d ${repo_path_list[i]} ]; then
				bran=`git branch -a | grep "br_${bl}_sp_${repo_name_list[i]}"`
				if [ "#$bran" == "#" ]; then
					echo "subtree split -P ${repo_path_list[i]} -b br_${bl}_sp_${repo_name_list[i]}"
					git subtree split -P ${repo_path_list[i]} -b br_${bl}_sp_${repo_name_list[i]}
				else
					echo "br_${bl}_sp_${repo_name_list[i]} exist"
				fi
			fi
		done
		cd $curr_pwd
	done
}

###检测git中是否存在特定的分支
git_exist_br()
{
	curr_pwd=`pwd`
	cd $1
	rst=`git branch -a | grep -w "$2"`
	cd $curr_pwd
	if [ "#$rst" == "#" ]; then
		echo 0
	else
		echo 1
	fi
}

####从主仓库中同步
get_main_all_br_name()
{
	curr_pwd=`pwd`
	cd $curr_pwd/$main_repo_name
	br_all=`git branch -a | grep "br_" | grep "_sp_"`
	cd $curr_pwd
	for ba in ${br_all[@]}
	do
		cd $curr_pwd
		br_name=`echo $ba | awk -F "br_" '{print $2}' | awk -F "_sp_" '{print $1}'`
		br_repo=`echo $ba | awk -F "br_" '{print $2}' | awk -F "_sp_" '{print $2}'`
		###同级目录下存在对应的仓库才执行接下来的操作
		if [ -d $br_repo ]; then
			if [ `git_exist_br $curr_pwd/$br_repo $br_name` -eq 1 ]; then
				cd $br_repo
				git checkout $br_name
				echo "git pull ../$main_repo_name $ba"
				git pull ../$main_repo_name $ba
			fi
		fi
	done
	cd $curr_pwd
}


####删除主仓库的所有为了拆分而建立的临时分支
delete_main_all_split_br()
{
	curr_pwd=`pwd`
	cd $curr_pwd/$main_repo_name
	br_all=`git branch -a | grep "br_" | grep "_sp_"`
	cd $curr_pwd
	for ba in ${br_all[@]}
	do
		git branch -D $ba
	done
	cd $curr_pwd
}

###主函数
main()
{
	subtree_split_all_br
	get_main_all_br_name
	cd $curr_pwd/$main_repo_name

	#清空主仓库的
	delete_main_all_split_br
	git filter-branch --force --index-filter 'git rm --cached --ignore-unmatch -r ${repo_path_list[@]}' --prune-empty --tag-name-filter cat -- --all
	###清理本地缓存
	rm -rf .git/refs/original/
	git reflog expire --expire=now --all
	git gc --prune=now
	git gc --aggressive --prune=now
}

main
