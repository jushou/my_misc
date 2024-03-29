#!/bin/bash

function __do_space_deal()
{
	file_type=`file -bi $1 | grep "charset=binary"`
	if [ "#$file_type" == "#" ]; then
		sed -i  's/[ \t]\+$//' $1
	fi
}

function CRLF_2_LF()
{
	file_type=`file -bi $1 | grep "charset=binary"`
	if [ "#$file_type" == "#" ]; then
		crlf_file=$1
		echo -en "\ncflf_flag" >> $crlf_file
		sed -i ':a ; N;s/\r\n/\n/ ; t a ; ' $crlf_file
		sed -i '$d' $crlf_file
	fi
}

function tail_space_deal()
{
	if [ -f $1 ]; then
		__do_space_deal $1
		CRLF_2_LF $1
	elif [ -d $1 ];then
		dirs=(`ls $1`)
		for el in  ${dirs[@]}
		do
			if [ -f $1/$el ]; then
				__do_space_deal $1/$el
				CRLF_2_LF $1/$el
			elif [ -d $1/$el ]; then
				tail_space_deal $1/$el
			fi
		done
	fi
}

for flist in $@
do
	tail_space_deal $flist
done
