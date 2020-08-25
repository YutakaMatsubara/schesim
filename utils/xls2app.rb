#! /usr/bin/env ruby
# -*- coding: utf-8 -*-
#
#= xlsからアプリケーション情報ファイルを生成するツール
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
#== Usage:
#
#=== デフォルト
# # ./xls2app.rb
#
#=== 入力・出力ファイル名の指定
#
#==== 入力するxlsファイル名の指定
# # ./xls2app.rb -x sample.xls
#==== 出力するアプリケーション情報ファイル名の指定（指定しない場合は標準出力に出力）
# # ./xls2app.rb -t sample.json
#==== 出力するタスク処理記述のファイル名の指定
# # ./xls2app.rb -d sample.rb
#

require "rubygems"
require "spreadsheet"
require "json"
require "optparse"              # コマンドライン引数

$tnum_cpu = 1
$tnum_core = 1
$tnum_app = 1
$global_scheduling = "edf"
$local_scheduling = "fp"

$tsk_table = []
$res_info_json = []
$cpu_id = 1
$core_id = 1
$app_id = 1
$tsk_id = 1

$input_dir = './'
$input_file = ""
$output_dir = './'
$output_json_file = ""
$output_rb_file = ""

# コマンドライン引数の処理

opt = OptionParser.new

# 入力するxlsのファイル名
opt.on('-x VAL') {|v| 
    $input_file = v.to_s
}

# 出力するアプリケーション情報ファイルのファイル名
opt.on('-t VAL') {|v| 
    $output_json_file = v.to_s
}

# 出力するタスク処理記述のファイル名
opt.on('-d VAL') {|v| 
    $output_rb_file = v.to_s
}

opt.parse!(ARGV)

book = Spreadsheet.open(File.expand_path($input_dir + $input_file), 'rb') # read only
sheet = book.worksheet(0)                     # 一番目のシート

#
#  リソース情報の生成
#
def generate_res_info
    $res_info_json = {
        "cpu" => []
    }
    $tnum_cpu.times {
        $res_info_json["cpu"] << generate_cpu_info()
        $cpu_id += 1
    }
end

#
#  CPU情報の生成
#
def generate_cpu_info
    cpu_info = {
        "id" => $cpu_id,
        "core" => []
    }
    $tnum_core.times {
        cpu_info["core"] << generate_core_info()
        $core_id += 1
    }
    return cpu_info
end

#
#  コア情報の生成
#
def generate_core_info
    core_info = {
        "id" => $core_id,
        "application" => [],
        "scheduling" => $global_scheduling,
    }
    $tnum_app.times {
        core_info["application"] << generate_app_info()
        $app_id += 1
    }
    return core_info
end

#
#  アプリケーション情報の生成
#
def generate_app_info
    app_info = {
        "id" => $app_id,
        "share" => 1.0 / $tnum_app,
        "scheduling" => $local_scheduling,
        "pri" => $app_id,
        "period" => 10,
        "task" => [],
    }

    $tsk_table.each do |tsk|
        app_info["task"] << tsk
    end
    return app_info
end


#
#  タスク処理記述ファイルの出力
#
def output_app_desc_file
    File.open(File.expand_path($output_dir + $output_rb_file),'w') { |f|
        f.print "class TASK\n"
        $res_info_json["cpu"].each do |cpu|
            cpu["core"].each do |core|
                core["application"].each do |app|
                    app["task"].each do |tsk|
                        f.print "\t def task" + tsk["id"].to_s + "\n"
                        f.print "\t\t pretask_hook\n"
                        f.print "\t\t exc(" + tsk["wcet"].to_s + ")\n"
                        f.print "\t\t posttask_hook\n"
                        f.print "\t end\n"
                    end
                end
            end
        end
        f.print "end\n"
    }
end

# 
#  変換処理本体
#

row = 1
record = sheet.row(row)

while record != []
    col = 0
    tsk = {}
    sheet.row(0).each do |param|
        val = record[col]
        case param
        when "id", "priority"
            val = record[col].to_i
        when "attr"
            if val != "cyclic" && val != "sporadic" && val != "normal"
                STDERR.printf("error at line %d: attr %s is not defined.\n", 
                              row, val)
                exit(1)
            end
        when nil
            break
        end
        tsk[param] = val
        col += 1
    end
    $tsk_table << tsk
    row += 1
    record = sheet.row(row)
end 

generate_res_info()
if $output_rb_file != ""
    output_app_desc_file()
end
if $output_json_file != ""
    File.open(File.expand_path($output_dir + $output_json_file),'w') { |f|
        f.write JSON.pretty_generate($res_info_json)
    }
else
    print JSON.pretty_generate($res_info_json)
end
