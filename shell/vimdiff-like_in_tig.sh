#/bin/bash

RED="\033[31m"
PLAIN='\033[0m'


vim_diff_cfg="\"vim_diff_colors {{{
if &diff
    set t_Co=256
    hi DiffAdd    ctermfg=233 ctermbg=194 guifg=#003300 guibg=#DDFFDD gui=none cterm=none
    hi DiffChange ctermbg=0  guibg=#ececec gui=none   cterm=none
    hi DiffText   ctermfg=233  ctermbg=189  guifg=#000033 guibg=#DDDDFF gui=none cterm=none
    hi DiffDelete ctermfg=252 ctermbg=224   guifg=#DDCCCC guibg=#FFDDDD gui=none    cterm=none
endif
\"}}}
"

tig_set1="bind diff      <Enter>       !sh -c \"git difftool --tool=vimdiff  --no-prompt %(commit)^! -- %(file)\""
tig_set2="bind stage     <Enter>       !sh -c \"git difftool --tool=vimdiff  --no-prompt \`expr '%(status)' : 'Staged changes' > /dev/null && echo --cached\` -- '%(file)'\""

is_exist_cmd()
{
	res=`which $1 2>/dev/null`
	if [[ "$?" != "0" ]]; then
		echo -e "\n\n$RED $1 not exist please install $1\n\n $PLAIN"
		exit -1
	fi
}


git_diff_param_set()
{
	##设置diff.tool为vimdff
	diff_tmp=`git config --global diff.tool`
	if [ "#$diff_tmp" != "#vimdiff" ]; then
		git config --global diff.tool vimdiff
	fi

	##去掉提示
	diff_tmp=`git config --global difftool.prompt`
	if [ "#$diff_tmp" != "#false" ]; then
		git config --global difftool.prompt false
	fi

	##cq之后退出所有
	diff_tmp=`git config --global difftool.trustExitCode`
	if [ "#$diff_tmp" != "#true" ]; then
		git config --global difftool.trustExitCode true
	fi

}


sudo_exec_string()
{
	if [ "`whoami`" == "root" ]; then
		echo " "
	else
		echo "sudo "
	fi
}


vim_diff_set()
{
	if [ ! -d ~/.vim ]; then
		mkdir -p ~/.vim
	fi
	if [ ! -e ~/.vim/vimrc ]; then
		touch ~/.vim/vimrc
	fi
	find1=`cat ~/.vim/vimrc | grep "\"vim_diff_colors {{{"`
	if [ "#$find1" == "#" ]; then
		echo -e "$vim_diff_cfg" >> ~/.vim/vimrc
	fi
}


tigrc_set()
{
	if [ ! -e ~/.tigrc ]; then
		touch ~/.tigrc
	fi
	find1=`cat ~/.tigrc | grep "#my_tig_set"`
	if [ "#$find1" == "#" ]; then
		echo "#my_tig_set" >> ~/.tigrc
		echo "$tig_set1" >> ~/.tigrc
		echo "$tig_set2" >> ~/.tigrc
	fi
}


###检测是否存在tig 和 vim命令
is_exist_cmd tig
is_exist_cmd vim
is_exist_cmd git

###设置git diff 参数
git_diff_param_set

vim_diff_set

tigrc_set


