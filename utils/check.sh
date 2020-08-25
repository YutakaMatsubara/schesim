#!/bin/sh
#
#= スケジュール可能ではないアプリケーションの検出
#
#Authors:: Yutaka MATSUBARA (ERTL, Nagoya Univ.)
#Version:: 0.8.0
#License:: Apache License, Version 2.0
#
#== License:
#
#  Copyright 2011 - 2013 Yutaka MATSUBARA
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
# 
#== 概要:
#
#  指定したディレクトリにあるアプリケーションファイル（jsonファイル）に
#  対応するlogファイルが存在する場合，そのアプリケーションはスケジュー
#  ル可能ではなかったと判断し，ファイル名を出力する．この判定方法は，ス
#  ケジュール可能だったときに，test.shでlogファイルを削除する仕様に依存
#  している．
#
#== Usage: 
# 
#=== デフォルト
# # ./check.sh ./fp_ok ./bss_ok ./tpa_ok
#
#=== チェック対象としないアルゴリズムはoffとする
# # ./check.sh ./fp_dir off ./tpa_dir
#

# コマンド引数処理

#
#  FPのチェック
#
fp_dir=$1
if [ $1 -a $1 != "off" ]
then
	fp_dir=`echo $1`

# 最後の"/"が無ければ補完
	length=${#fp_dir}
	chk=`echo $fp_dir | cut -c $length`

	if [ $chk != "/" ]
	then
		fp_dir=`echo $fp_dir"/"`
	else
		fp_dir=`echo $fp_dir`
	fi

# FPのチェック
	files=$fp_dir"/*.json"
	declare -i fp_i
	declare -i fp_j
	declare -i fp_k
	fp_i=0
	fp_j=0
	fp_k=0

	echo "---------------------------------------------------"
	echo "Following tasksets are unschedulable in ${fp_dir}."

	for filepath in ${files}
	do
		basename=${filepath##*/}
		log_file=$fp_dir${basename%.*}.log

		if [ -f $log_file ]
		then
			echo "${filepath}"
			fp_i=${fp_i}+1
		else
			fp_j=${fp_j}+1
		fi
	done
fi

#
#  BSSのチェック
#
bss_dir=$2
if [ $2 -a $2 != "off" ]
then
	bss_dir=`echo $2`

# 最後の"/"が無ければ補完
	length=${#bss_dir}
	chk=`echo $bss_dir | cut -c $length`

	if [ $chk != "/" ]
	then
		bss_dir=`echo $bss_dir"/"`
	else
		bss_dir=`echo $bss_dir`
	fi

	files=$bss_dir"/*.json"
	declare -i bss_i
	declare -i bss_j
	declare -i bss_k
	bss_i=0
	bss_j=0
	bss_k=0

	echo "---------------------------------------------------"
	echo "Following tasksets are unschedulable in ${bss_dir}."

	for filepath in ${files}
	do
		basename=${filepath##*/}
		log_file=$bss_dir${basename%.*}.log

		if [ -f $log_file ]
		then
			echo "${filepath}"
			bss_i=${bss_i}+1
		else
			bss_j=${bss_j}+1
		fi
	done
fi

#
#  TPAのチェック
#
tpa_dir=$3
if [ $3 -a $3 != "off" ]
then
	tpa_dir=`echo $3`

# 最後の"/"が無ければ補完
	length=${#tpa_dir}
	chk=`echo $tpa_dir | cut -c $length`

	if [ $chk != "/" ]
	then
		tpa_dir=`echo $tpa_dir"/"`
	else
		tpa_dir=`echo $tpa_dir`
	fi

	files=$tpa_dir"/*.json"
	declare -i tpa_i
	declare -i tpa_j
	declare -i tpa_k
	tpa_i=0
	tpa_j=0
	tpa_k=0

	echo "---------------------------------------------------"
	echo "Following tasksets are unschedulable in ${tpa_dir}."
	
	for filepath in ${files}
	do
		basename=${filepath##*/}
		log_file=$tpa_dir${basename%.*}.log
		
		if [ -f $log_file ]
		then
			echo "${filepath}"
			tpa_i=${tpa_i}+1
		else
			tpa_j=${tpa_j}+1
		fi
	done
fi

# 集計結果

echo "---------------------------------------------------"

# FPの結果
if [ $1 -a $1 != "off" ]
then
	fp_k=${fp_i}+${fp_j}
	echo "${fp_j} / ${fp_k} files are schedulable in ${fp_dir}."
else
	echo "Check for FP is OFF."
fi	

# BSSの結果
if [ $2 -a $2 != "off" ]
then
	bss_k=${bss_i}+${bss_j}
	echo "${bss_j} / ${bss_k} files are schedulable in ${bss_dir}."
else
	echo "Check for BSS is OFF."
fi

# TPAの結果
if [ $3 -a $3 != "off" ]
then
	tpa_k=${tpa_i}+${tpa_j}
	echo "${tpa_j} / ${tpa_k} files are schedulable in ${tpa_dir}."
else
	echo "Check for TPA is OFF."
fi

echo "---------------------------------------------------"

exit
