#!/bin/bash

if [ ! -d `pwd`/back_shell ]; then
	mkdir `pwd`/back_shell
fi

back_sh_raw=`pwd`/back_shell/back_git2svn_shell.sh
back_sh=${back_sh_raw}.bak

echo back shell to $back_sh

get_git_repo_sync()
{
		CURR_DIR=`pwd`
		git_repo_list=(`find git_*  -maxdepth 0 -type d | sort`)
		for item in ${git_repo_list[@]}
		do
				cd $item
				git config remote.origin.url > /dev/null 2>&1
				if [ $? -ne 0 ]; then
					echo "git config remote.origin.url"
					rm $back_sh
					exit -1
				fi
				echo "if [ ! -d $item ]; then" >> $back_sh
				echo "	git clone `git config remote.origin.url` $item" >> $back_sh
				echo "	if [ \$? -ne 0 ]; then" >> $back_sh
				echo "		echo \"git clone `git config remote.origin.url` $item error\"" >> $back_sh
				echo "		exit -1" >> $back_sh
				echo "	fi" >> $back_sh
				echo "fi" >> $back_sh
				echo "if [ ! -d $item/.sync_git_to_svn ]; then" >> $back_sh
				echo "	mkdir -p $item/.sync_git_to_svn" >> $back_sh
				echo "fi" >> $back_sh
				last_cmid=(`find .sync_git_to_svn -maxdepth 1 -type f | sort`)
				for cmid in ${last_cmid[@]}
				do
						echo "echo `cat $cmid` > $item/$cmid" >> $back_sh
				done
				echo -en "\n" >> $back_sh
				cd ..
		done
		cd $CURR_DIR
}


get_svn_repo_url()
{
		CURR_DIR=`pwd`
		svn_repo_list=(`find svn_*  -maxdepth 0 -type d | sort`)
		for item in ${svn_repo_list[@]}
		do
				cd $item
				svn info > /dev/null 2>&1
				if [ $? -ne 0 ]; then
					echo "svn info $item error"
					rm $back_sh
					exit -1
				fi
				url=`svn info | grep -E "^URL:" | awk '{print $2}'`
				echo "svn co $url $item" >> $back_sh
				echo "if [ \$? -ne 0 ]; then" >> $back_sh
				echo "	echo \"svn co $url $item error \"" >> $back_sh
				echo "	exit -1" >> $back_sh
				echo "fi" >> $back_sh
				echo -en "\n" >> $back_sh
				cd ..
		done
		cd $CURR_DIR
}


echo "#!/bin/bash" > $back_sh
echo -en "\n" >> $back_sh
get_git_repo_sync
get_svn_repo_url
chmod +x $back_sh
echo "move $back_sh to $back_sh_raw"
mv $back_sh $back_sh_raw