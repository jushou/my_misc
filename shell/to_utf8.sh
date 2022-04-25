#!/bin/bash


####脚本依赖enca工具 自动转换可能会出现问题需要手动比较
####在git仓库下可以用git diff 比较（也可以安装tig比较）

RED="\033[31m"
PLAIN='\033[0m'



is_exist_cmd()
{
    res=`which $1 2>/dev/null`
    if [[ "$?" != "0" ]]; then
        echo -e "\n\n$RED $1 not exist please install $1\n\n $PLAIN"
        exit -1
    fi
}


do_check()
{
    file_list=(`find -type f`)
    for fl in ${file_list[@]}
    do
        ####文件类型是text才做utf8检查
        file_type=`file --mime-type $fl | awk -F ":" '{print $2}' | grep "text/"`
        if [ "#$file_type" != "#" ]; then
            file_encode=`enca -L none -m $fl`
            if [ "#$file_encode" != "#UTF-8" ]; then
                enca -L zh_CN -x UTF-8 $fl
                if [ $? -ne 0 ]; then
                    echo -e "\n\n$RED enca -L zh_CN -x UTF-8 $fl error$PLAIN\n\n"
                fi
            fi
        fi
    done
}


is_exist_cmd enca
do_check


