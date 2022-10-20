#!/bin/bash

RED="\033[31m"
PLAIN='\033[0m'

check_CR_LF()
{
    crcl_n=`cat -A $1 | grep -n "\\^M\\\\$" | wc -l`
    if [ $crcl_n -ne 0 ]; then
        echo -e "\n\n$RED $1 exist $crcl_n CR LF $PLAIN\n\n"
        error=1
    fi
}

do_check()
{
    ##临时文件夹保存git diff --raw的内容
    TMP_FILE=$(mktemp)
    ####只需要检出最新一次的修改就可以了
    change_list=(`git log $1 -2 --format=%H`)
    if [ $? -ne 0 ];then
        echo "git log $1 -2 --format=%H error"
        exit -1
    fi
    ####设置中文路径乱码的问题
    git config core.quotepath false
    git diff ${change_list[1]}..${change_list[0]} --raw > $TMP_FILE
    ###文件的修改（增、删、改、重命名 A、D、M、R）
    file_actions=(`awk '{print $5}' $TMP_FILE`)
    file_news=(`awk '{if(NF==7){print $7} else {print $6}}' $TMP_FILE`)
    echo "all change"
    cat $TMP_FILE
    rm $TMP_FILE
    error=0
    for((i=0;i<${#file_news[@]};i++))
    do
        ###不是文件删除才会检测
        if [ "#${file_actions[i]}" != "#D" ]; then
            if [ -e ${file_news[i]} ] ; then
                ####文件类型是text才做utf8检查
                file_type=`file -bi ${file_news[i]} | grep "charset=binary"`
                if [ "#$file_type" == "#" ]; then
                    ###通过file匹配文件encoding 为us-ascii或者utf-8 才认为是utf8（不是很精确）
                    file_encode=`file --mime-encoding ${file_news[i]} | awk '{print $2}'`
                    if [ "#$file_encode" != "#utf-8" -a "#$file_encode" != "#us-ascii" ]; then
                        echo -e "\n\n$RED ${file_news[i]} not a utf8 encoding file $PLAIN\n\n"
                        error=1
                    fi
                fi
            else
                echo -e "\n\n$RED \"${file_news[i]}\" not exist (There may be spaces in the filename) $PLAIN\n\n"
                error=1
            fi
        fi
    done

    if [ $error -ne 0 ];then
        exit -1
    else
        echo "utf-8 checkout success"
    fi
}

####检测是否为git仓库

is_git=`git rev-parse --is-inside-work-tree`
if [ "#$is_git" != "#true" ];then
    echo -e "\n\n$RED \" `pwd` \" not a git repository \n\n $PLAIN"
    exit -1;
fi

usage()
{
    echo -e "\tusage:"
    echo -e "\t$0 commit_id(40 characters hash)\n"
    exit -1
}

if [ $# -eq 0 ]; then
    usage
fi


COMMIT_HASH=`echo $1 | grep -o -P "^[0-9a-fA-F]{40}"`
if [ "#$COMMIT_HASH" == "#" ]; then
    echo -e "\t $1 must be a long commit_id(40 characters hash)\n"
    exit -1
fi


do_check $1
