#! /usr/bin/env ruby
# -*- coding: utf-8 -*-
#
#= ログファイルから統計情報（xls）を出力するツール
#
#Authors:: Yasumasa SANO (ERTL, Nagoya Univ.)
#Version:: 0.8.0
#License:: Apache License, Version 2.0
#
#== License:
#
#  Copyright 2011 - 2013 Yasumasa SANO
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
#== Usage:
#
#=== デフォルト
#
#==== 入力するログファイル名の指定
# # ./stats.rb -i sample.log
#==== 出力するxlsファイル名の指定
# # ./stats.rb -o sample.xls
#==== 待ち状態、待ち解除状態を繰り返すタスクの応答時間も計測する(初回起動も計測)
# # ./stats.rb -F
#==== 待ち状態、待ち解除状態を繰り返すタスクの応答時間も計測する(初回起動は除外)
# # ./stats.rb -S
#==== 機能応答時間も計測する
# # ./stats.rb -R
#==== csv出力
# # ./stats.rb -c
#

require "rubygems"
require "spreadsheet"
require "optparse"              # コマンドライン引数

$F_flag = 0
$S_flag = 0
$R_flag = 0
$c_flag = 0
$input_file
$output_dir = './'
$output_file
$log_file
$start_time = Array.new
$exc_time = Array.new
$all_exc_time = Array.new
$dispatch_time = Array.new            # コアの数だけ変数を用意
$response_time = Array.new
$event_time = Hash.new
$act_count = Array.new                # キューイング数の確認
$running_task = Array.new
$request_flag = Array.new             # 実行回数を正確に計測するために使用
$run_count = Array.new
$func_start_time = Array.new          # 機能応答時間用
$func_response_time = Array.new       # 機能応答時間用
$func_event_time = Hash.new           # 機能応答時間用
$app_disp_count = 0                   # アプリケーションの切り替え回数
$measure_flag = Array.new             # begin_measure, end_measure関数用
$measure_start_time = Array.new       # begin_measure, end_measure関数用
$measure_exc_time = Array.new         # begin_measure, end_measure関数用
$measure_all_exc_time = Array.new     # begin_measure, end_measure関数用
$measure_dispatch_time = Array.new    # begin_measure, end_measure関数用
$measure_response_time = Array.new    # begin_measure, end_measure関数用
$system_start_time
$system_last_time
$system_total_exc = 0

# コマンドライン引数の処理

opt = OptionParser.new

# 入力するログファイル名
opt.on('-i VAL') {|v| 
    $input_file = v.to_s
}

# 出力するxlsのファイル名
opt.on('-o VAL') {|v| 
    $output_file = v.to_s
}

# 待ち、待ち解除を繰り返すタスクを考慮する場合のオプション指定(初回起動も計上)
opt.on('-F') {|v| 
    $F_flag = 1
}

# 待ち、待ち解除を繰り返すタスクを考慮する場合のオプション指定(初回起動は無視)
opt.on('-S') {|v| 
    $S_flag = 1
}

# 機能応答時間も計測する場合のオプション指定
opt.on('-R') {|v| 
    $R_flag = 1
}

# csv出力
opt.on('-c') {|v| 
    $c_flag = 1
}

opt.parse!(ARGV)

#
#  オプションに関するエラー処理
#
if $F_flag == 1 && $S_flag == 1
    abort("option error.\n")
end
if $output_file == nil
    abort("output file is undecleared.\n")
end

# 
#  ログファイルの読み込み
#
def read_file
    if $input_file == ""
        abort("input file is undeclared.\n")
    else
        $log_file = open($input_file)
    end
end

# 
#  統計情報処理
#
def statistics_calculate
    $log_file.each do |line|

        if line =~ /\[(\d+)\]\:\[(\d+)\]\:\stask\s(\d+)\sbecomes\s(\w+)\./
            time = $1.to_i
            core_id = $2.to_i
            task_num = $3.to_i
            event = $4

            # 2次元配列を用意
            if $all_exc_time[task_num] == nil
                $all_exc_time[task_num] = Array.new
            end
            if $response_time[task_num] == nil
                $response_time[task_num] = Array.new
            end
            if $func_response_time[task_num] == nil
                $func_response_time[task_num] = Array.new
            end

            if event == "DORMANT"
                
                # 実行時間の計算
                if $running_task[core_id] == task_num
                    if $exc_time[task_num] == nil
                        $exc_time[task_num] = time - $dispatch_time[core_id]
                    elsif
                        $exc_time[task_num] += time - $dispatch_time[core_id]
                    end
                end

                $all_exc_time[task_num] << $exc_time[task_num]
                $exc_time[task_num] = 0

                $act_count[task_num] -= 1

                # 実行状態のタスクがなくなる
                $running_task[core_id] = -1

                # 応答時間の計算
                $response_time[task_num] << time - $start_time[task_num].shift

                # 機能応答時間の計算
                $func_response_time[task_num] << time - $func_start_time[task_num].shift

            elsif event == "RUNNABLE"

                # 通常起動(キューイングされていない)
                if $act_count[task_num] == nil || $act_count[task_num] == 0
                    if $start_time[task_num] == nil
                        $start_time[task_num] = Array.new
                    end
                    $start_time[task_num] << time

                    if $act_count[task_num] == nil
                        $act_count[task_num] = 1
                    else
                        $act_count[task_num] += 1
                    end
                end

                # 実行可能状態
                $request_flag[task_num] = 1

            end

        elsif line =~ /\[(\d+)\]\:\[(\d+)\]\:\snumber\sof\sactivation\srequests\sof\stask\s(\d+)\sis\s(\d+)/

            # キューイングされたとき
            time = $1.to_i
            core_id = $2.to_i
            task_num = $3.to_i

            $start_time[task_num] << time
            $act_count[task_num] += 1

        elsif line =~ /\[(\d+)\]\:\[(\d+)\]\:\sapplog\sstrtask.+TASK\s(\d+)\s\:\s(\w+)\((.*)\)/
            time = $1.to_i
            core_id = $2.to_i
            task_num = $3.to_i
            event = $4.to_s
            arg_num = $5.to_i

            # 2次元配列を用意
            if $measure_start_time[arg_num] == nil
                $measure_start_time[arg_num] = Array.new
            end
            if $measure_all_exc_time[arg_num] == nil
                $measure_all_exc_time[arg_num] = Array.new
            end
            if $measure_response_time[arg_num] == nil
                $measure_response_time[arg_num] = Array.new
            end
            if $func_start_time[task_num] == nil
                $func_start_time[task_num] = Array.new
            end
            if $func_start_time[arg_num] == nil
                $func_start_time[arg_num] = Array.new
            end

            if event == "act_tsk"
                if task_num == arg_num
                    # 最上位タスクの場合
                    $func_start_time[task_num] << time
                else
                    # 他タスクから起動される場合
                    $func_start_time[arg_num] << $func_start_time[task_num][0]
                end
            elsif event == "begin_measure"
                $measure_start_time[arg_num] << time
                if $measure_start_time[arg_num].length >= 2
                    abort("Error:begin_measure was called two times or more before end_measure was called.\n")
                end
                $measure_dispatch_time[arg_num] = time
                # どのタスクがbegin_measureを呼んでいるのかを記録
                $measure_flag[arg_num] = task_num
            elsif event == "end_measure"
                if $measure_flag[arg_num] != task_num
                    abort("Error:begin_measure and end_measure were not called by same task")
                end
                $measure_response_time[arg_num] << time - $measure_start_time[arg_num].shift
                # 実行時間の計算
                if $measure_exc_time[arg_num] == nil
                    $measure_exc_time[arg_num] = time - $measure_dispatch_time[arg_num]
                elsif
                    $measure_exc_time[arg_num] += time - $measure_dispatch_time[arg_num]
                end
                $measure_all_exc_time[arg_num] << $measure_exc_time[arg_num]
                $measure_exc_time[arg_num] = 0
                $measure_flag[arg_num] = -1
            end

            if $F_flag == 1 || $S_flag == 1
                if event == "SetEvent"
                    # 対象のハッシュに時間を格納
                    $event_time[arg_num] = time
                    $func_event_time[arg_num] = $func_start_time[task_num][0]

                elsif event == "WaitEvent"

                    # 実行時間の計算
                    if $exc_time[task_num] == nil && $S_flag == 1
                        $run_count[task_num] -= 1
                    else
                        if $exc_time[task_num] == nil
                            $exc_time[task_num] = time - $dispatch_time[core_id]
                        elsif
                            $exc_time[task_num] += time - $dispatch_time[core_id]
                        end

                        $all_exc_time[task_num] << $exc_time[task_num]
                    end
                    $exc_time[task_num] = 0

                    # 実行状態のタスクがなくなる
                    $running_task[core_id] = -1

                    # 応答時間の計算
                    if $F_flag == 1 && $start_time[task_num] != []
                        # RUNNABLEになってからWaitEventまで
                        $response_time[task_num] << time - $start_time[task_num].shift
                    elsif $event_time[arg_num] != nil
                        # ClearEventからWaitEventまで
                        $response_time[task_num] << time - $event_time[arg_num]
                    end

                    # 機能応答時間の計算
                    if $S_flag == 1 && $func_event_time[arg_num] != nil
                        $func_response_time[task_num] << time - $func_event_time[arg_num]
                    elsif $F_flag == 1
                        $func_response_time[task_num] << time - $func_start_time[task_num]
                    end
                end
            end

        elsif line =~ /\[(\d+)\]\:\[(\d+)\]\:\sdispatch\sto\stask\s(\d+)\./
            time = $1.to_i
            core_id = $2.to_i
            task_num = $3.to_i

            # becomes RUNNABLEのログの後のdispatch toで実行回数をインクリメント
            if $request_flag[task_num] == 1
                if $run_count[task_num] == nil
                    $run_count[task_num] = 1
                else
                    $run_count[task_num] += 1
                end
                $request_flag[task_num] = 0
            end

            # dispatch from task で時間を計測するためにdispatch to task の時間を格納
            $dispatch_time[core_id] = time

            # 次に実行状態になるタスクのIDを格納
            $running_task[core_id] = task_num

            # $measure_flagにtask_numの値が入っている要素を更新
            arg_num = 0
            $measure_flag.each do |flag|
                if flag != nil && flag == task_num
                    $measure_dispatch_time[arg_num] = time
                end
                arg_num += 1
            end

        elsif line =~ /\[(\d+)\]\:\[(\d+)\]\:\sdispatch\sfrom\stask\s(\d+)\./
            time = $1.to_i
            core_id = $2.to_i
            task_num = $3.to_i

            # 実行状態のタスクがある場合，現在までの実行時間をexc_timeに計上する
            if $running_task[core_id] != -1 && $running_task[core_id] != nil
                if $exc_time[$running_task[core_id]] == nil
                    $exc_time[$running_task[core_id]] = time - $dispatch_time[core_id]
                elsif
                    $exc_time[$running_task[core_id]] += time - $dispatch_time[core_id]
                end
            end

            # 実行状態のタスクがなくなる
            $running_task[core_id] = -1

            # $measure_flagにtask_numの値が入っている場合，一旦実行時間を計算する
            arg_num = 0
            $measure_flag.each do |flag|
                if flag != nil && flag == task_num
                    if $measure_exc_time[arg_num] == nil
                        $measure_exc_time[arg_num] = time - $measure_dispatch_time[arg_num]
                    elsif
                        $measure_exc_time[arg_num] += time - $measure_dispatch_time[arg_num]
                    end
                end
                arg_num += 1
            end

        elsif line =~ /\[(\d+)\]\:\[(\d+)\]\:\sdispatch\sto\sapplication\s(\d+)\./
            # アプリケーションの切り替え回数+1
            $app_disp_count += 1
        elsif line =~ /\[(\d+)\]\:\[(\d+)\]\:\ssimulation\sstarts\./
            # シミュレーションの開始時刻
            $system_start_time = $1.to_i
        elsif line =~ /\[(\d+)\]\:\[(\d+)\]\:\ssimulation\sfinished\./
            # シミュレーションの終了時刻
            $system_last_time = $1.to_i
        end
    end



end

#
#  ファイルへの書き出し
#
def write_file
    book = Spreadsheet::Workbook.new
    task_sheet = book.create_worksheet
    task_sheet.name = "タスク情報"
    system_sheet = book.create_worksheet
    system_sheet.name = "システム情報"
    measure_sheet = book.create_worksheet
    measure_sheet.name = "measure情報"
    format = Spreadsheet::Format.new(:name => "ＭＳ Ｐゴシック", :size => 11)

    # タスクシートの見出しの印字
    task_sheet[0, 0] = "タスクID"
    task_sheet[0, 1] = "起動回数"
    task_sheet[0, 2] = "平均応答時間"
    task_sheet[0, 3] = "最大応答時間"
    task_sheet[0, 4] = "最小応答時間"
    task_sheet[0, 5] = "総実行時間"
    task_sheet[0, 6] = "平均実行時間"
    task_sheet[0, 7] = "最大実行時間"
    task_sheet[0, 8] = "最小実行時間"
    task_sheet[0, 9] = "CPU利用率"
    task_sheet.column(0).width = 9
    task_sheet.column(1).width = 9
    task_sheet.column(2).width = 13
    task_sheet.column(3).width = 13
    task_sheet.column(4).width = 13
    task_sheet.column(5).width = 11
    task_sheet.column(6).width = 13
    task_sheet.column(7).width = 13
    task_sheet.column(8).width = 13
    task_sheet.column(9).width = 11

    if $R_flag == 1
        task_sheet[0, 10] = "平均機能応答時間"
        task_sheet[0, 11] = "最大機能応答時間"
        task_sheet[0, 12] = "最小機能応答時間"
        task_sheet.column(10).width = 17
        task_sheet.column(11).width = 17
        task_sheet.column(12).width = 17
    end

    task_num = 0
    row = 1
    system_time = $system_last_time - $system_start_time

    $response_time.each do |time|
        if time != nil && time != []
            # タスクの情報の出力
            total_exc = $all_exc_time[task_num].inject(0){|result, item| result + item}
            task_sheet[row, 0] = task_num
            task_sheet[row, 1] = $run_count[task_num]
            task_sheet[row, 2] = $response_time[task_num].inject(0){|result, item| result + item} / $response_time[task_num].length
            task_sheet[row, 3] = $response_time[task_num].max
            task_sheet[row, 4] = $response_time[task_num].min
            task_sheet[row, 5] = total_exc
            task_sheet[row, 6] = (total_exc / $run_count[task_num]).round
            task_sheet[row, 7] = $all_exc_time[task_num].max
            task_sheet[row, 8] = $all_exc_time[task_num].min
            task_sheet[row, 9] = total_exc * 100 / system_time.to_f
            $system_total_exc += total_exc

            if $R_flag == 1
                task_sheet[row, 10] = $func_response_time[task_num].inject(0){|result, item| result + item} / $func_response_time[task_num].length
                task_sheet[row, 11] = $func_response_time[task_num].max
                task_sheet[row, 12] = $func_response_time[task_num].min
            end

            row += 1
        end
        task_sheet.row(task_num).height = 17
        for i in 0..9
            # フォントの変更
            task_sheet.row(task_num).set_format(i,format)
        end

        if $R_flag == 1
            for i in 10..12
                # フォントの変更
                task_sheet.row(task_num).set_format(i,format)
            end
        end

        task_num += 1        
    end

    # システムシートの見出しの印字
    system_sheet.row(0).height = 17
    system_sheet.row(1).height = 17
    #system_sheet[0, 0] = "コア数"
    #system_sheet[0, 1] = "アプリケーション数"
    system_sheet[0, 2] = "タスク数"
    system_sheet[0, 3] = "CPU利用率"
    system_sheet[0, 4] = "アプリケーション切り替え回数"
    #system_sheet.column(0).width = 7
    #system_sheet.column(1).width = 17
    system_sheet.column(2).width = 11
    system_sheet.column(3).width = 11
    system_sheet.column(4).width = 25

    # フォントの変更
    for col_num in 0..4
        system_sheet.row(0).set_format(col_num,format)
        system_sheet.row(1).set_format(col_num,format)
    end

    # システムの情報の出力
    system_sheet[1, 2] = row-1
    system_sheet[1, 3] = (($system_total_exc / system_time.to_f * 10000).round)/100.0
    system_sheet[1, 4] = $app_disp_count

    # measure情報の見出しの印字
    measure_sheet[0, 0] = "ID"
    measure_sheet[0, 1] = "計測回数"
    measure_sheet[0, 2] = "平均応答時間"
    measure_sheet[0, 3] = "最大応答時間"
    measure_sheet[0, 4] = "最小応答時間"
    measure_sheet[0, 5] = "平均実行時間"
    measure_sheet[0, 6] = "最大実行時間"
    measure_sheet[0, 7] = "最小実行時間"

    measure_sheet.column(0).width = 5
    measure_sheet.column(1).width = 9
    measure_sheet.column(2).width = 13
    measure_sheet.column(3).width = 13
    measure_sheet.column(4).width = 13
    measure_sheet.column(5).width = 13
    measure_sheet.column(6).width = 13
    measure_sheet.column(7).width = 13

    measure_num = 0
    row = 1
    $measure_response_time.each do |time|
        if time != nil && time != []
            # measureの情報の出力
            measure_sheet[row, 0] = measure_num
            measure_sheet[row, 1] = $measure_response_time[measure_num].length
            measure_sheet[row, 2] = $measure_response_time[measure_num].inject(0){|result, item| result + item} / $measure_response_time[measure_num].length
            measure_sheet[row, 3] = $measure_response_time[measure_num].max
            measure_sheet[row, 4] = $measure_response_time[measure_num].min
            measure_sheet[row, 5] = $measure_all_exc_time[measure_num].inject(0){|result, item| result + item} / $measure_response_time[measure_num].length
            measure_sheet[row, 6] = $measure_all_exc_time[measure_num].max
            measure_sheet[row, 7] = $measure_all_exc_time[measure_num].min
            row += 1
        end
        measure_sheet.row(measure_num).height = 17
        for i in 0..7
            # フォントの変更
            measure_sheet.row(measure_num).set_format(i,format)
        end
        measure_num += 1        
    end
    book.write($output_file)

end

#
#  CSV出力
#
def csv_mode
    task_num = 0
    print "タスクID,実行回数,平均応答時間,最大応答時間,最小応答時間,総実行時間,平均実行時間,最大実行時間,最小実行時間\n"
    $response_time.each do |time|
        if time != nil && time != []
            total_exc = $all_exc_time[task_num].inject(0){|result, item| result + item}
            print task_num, ","
            print $run_count[task_num], ","
            print $response_time[task_num].inject(0){|result, item| result + item} / $response_time[task_num].length, ","
            print $response_time[task_num].max, ","
            print $response_time[task_num].min, ","
            print total_exc, ","
            print (total_exc / $run_count[task_num]).round, ","
            print $all_exc_time[task_num].max, ","
            print $all_exc_time[task_num].min

            if $R_flag != 1
                print "\n"
            elsif $R_flag == 1
                print ","
                print $func_response_time[task_num].inject(0){|result, item| result + item} / $func_response_time[task_num].length, ","
                print $func_response_time[task_num].max, ","
                print $func_response_time[task_num].min, "\n"
            end

        end
        task_num += 1        
    end
end

read_file
statistics_calculate
if $c_flag != 1
    write_file
else
    csv_mode
end
