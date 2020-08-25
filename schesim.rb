#! /usr/bin/env ruby
# -*- coding: utf-8 -*-
#
#= スケジューリング・シミュレータの本体
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
#=== デフォルト（階層型スケジューリングTPAモード）
# # ./schesim.rb
#
#=== 入力・出力ファイル名の指定
#
#==== 入力するアプリケーションのファイル名の指定
# # ./schesim.rb -t ./tlv/sampleFiles/asp-tp/sample.json
#==== 入力するシナリオのファイル名の指定
# # ./schesim.rb -c ./tlv/sampleFiles/asp-tp/sample.scn
#==== 入力するタスク処理記述のファイル名の指定
# # ./schesim.rb -d ./tlv/sampleFiles/asp-tp/sample.rb
#==== 出力するリソースファイル名の指定
# # ./schesim.rb -r ./tlv/sampleFiles/asp-tp/sample.res
#
#=== その他の指定
#
#==== シミュレーション時間の指定
# # ./schesim.rb -e 200000
#

# 標準ライブラリ
require "rational"              # lcm
require "rubygems"
require "json"                  # JSON
require "fiber"
require "optparse"              # コマンドライン引数

# 独自ライブラリ
require "./include/core"
require "./include/application"
require "./include/task"
require "./include/hook"
require "./include/event"
require "./include/common_module"

# 階層型スケジューリングライブラリ（研究用）
require "./labs/bss"
require "./labs/tpa"

include FATAL_ERROR

# グローバル変数の定義
$start_time = 1.0               # システムの開始時刻
$system_time = $start_time      # システム時刻

# 入力ファイルの情報
$app_info = {}                  # アプリケーションの情報
$tsk_info = {}                  # タスクの情報
$log_conf = []                  # ログ情報の出力設定

# 出力ファイルの情報

$res_info = []                  # アプリケーションセットのリソース情報

# シミュレーションのためのグローバル変数

$event = []
$event << $system_time          # イベントが発生する時刻を管理する配列
$exc_time = 0.0                 # 実行時間

# コンフィギュレーション情報のファイル名
$configuration_file = "./schesim.conf"

# アプリケーション情報のファイル名
$application_file = ""

# ログファイルのデフォルトファイル名
$log_file = File.expand_path('./tlv/sampleFiles/asp-tp/sample.log') 

# リソースファイルのデフォルトファイル名
$resource_file = File.expand_path('./tlv/sampleFiles/asp-tp/sample.res')

# シナリオファイルのデフォルトファイル名
$scenario_file = ""

#
#  ローカル変数
#
sim_time = 0                    # シミュレーション時間（デフォルト）

#
#  コマンドライン引数の処理
#
opt = OptionParser.new

# 入力するアプリケーションのファイル名の指定
opt.on('-t VAL') {|v|
    $application_file = v.to_s
}

# 入力するシナリオのファイル名の指定
opt.on('-c VAL') {|v|
    $scenario_file = v.to_s
}

# 入力するタスク処理記述のファイル名の指定
opt.on('-d VAL') {|v|
    begin
        open v
        require v
    rescue
        raise_fatal_exception("task description file read error: " + $!.message + "\n")
    end
}

# 出力するリソースファイル名の指定
opt.on('-r VAL') {|v|
    $resource_file = v.to_s
}

# シミュレーション時間の指定
opt.on('-e VAL') {|v|
    sim_time = v.to_f
}

opt.parse!(ARGV)

$next_flag = false

#
#  シミュレータクラスの定義
#
class SIMULATOR
    include FATAL_ERROR
    def initialize(sim_time)
        @sim_time = sim_time    # シミュレーション時間（デフォルト）

        # 入力ファイル情報
        @cpuid_info = [] # プロセッサIDのテーブル（マルチプロセッサ対応）
        @core_info = []  # コアの情報
        @stop_conf_info = []    # シミュレーション停止条件の設定情報
        @scenario = []          # シナリオファイルの情報
        @core_table = []        # コアクラスの管理テーブル

        #
        # ファイル入出力処理
        #
        read_configuration_file
        read_application_file
        if $scenario_file != ""
            read_scenario_file
        end
        print_resource_file
    end

    # 
    #  コンフィギュレーションファイルの読み込み
    #
    private
    def read_configuration_file
        file_type = File::extname($configuration_file)
        case file_type
        when ".conf"
            read_configuration_json_file
        else
            raise_fatal_exception(sprintf("configuration file read error: file type '%s' is not supported.\n", file_type))
        end
    end

    # 
    #  アプリケーションファイルの読み込み
    #
    private
    def read_application_file
        file_type = File::extname($application_file)
        case file_type
        when ".json"
            read_application_json_file
        else
            raise_fatal_exception(sprintf("application file read error: file type '%s' is not supported.\n", file_type))
        end
    end

    # 
    #  シナリオファイルの読み込み
    #
    private
    def read_scenario_file
        file_type = File::extname($scenario_file)
        case file_type
        when ".scn"
            File.open(File.expand_path($scenario_file), "r") do |file|
                while line = file.gets
                    unless line =~ /^\#/ # 「#」で始まる行はコメントと判断する
                        @scenario << line.split(/\s*:\s*/)
                    end
                end
            end            
        else
            raise_fatal_exception(sprintf("scenario file read error: file type '%s' is not supported.\n", file_type))
        end
    end

    #
    #  シナリオに書かれたイベントの登録
    #
    private
    def regist_scenario
        print @scenario.join(',') if $DEBUG
        @scenario.each do |scn|
            event_time = scn[0].to_f
            coreid = scn[1].to_i
            inst = scn[2]
            ccb = nil
            @core_table.each do |core|
                if coreid == core.id
                    ccb = core
                    break
                end
            end
            if ccb == nil
                raise_fatal_exception(sprintf("scenario file read error: core with id %d is not defined.\n", coreid))
            end
            case inst
            when "act_tsk"
                tskid = scn[3].to_i
                tsk = nil
                tmp_app = nil
                ccb.app_table.each do |app|
                    tsk = app.get_tsk(tskid)
                    if tsk != nil
                        tmp_app = app
                        break
                    end
                end
                if tsk == nil
                    printf("error task id %d",tskid)
                    exit
                end
                tmp_app.add_event(event_time,inst,tsk)
            when "chg_mod"
                mode = scn[3]
                val = scn[4].to_i
                ccb.add_event(event_time,inst,[mode,val])
            else
                raise_fatal_exception(sprintf("scenario file read error: %s is undefined.\n", inst))
            end
        end
    end

    #
    #  リソース情報ファイルの生成
    #
    private
    def print_resource_file
        print_resource_common
        @core_info[1].each do |core|
            @core_table << CORE.new(core["id"],core["scheduling"])
#            @core_table << CORE_LOAD_BALANCE.new(core["id"],core["scheduling"])
        end
        $res_info["VisualizeRules"] << "fmp_core"+ (@core_table.size).to_s
        
        @core_info[1].each do |core|
            $res_info["Resources"]["CurrentContext_PRC"+(core["id"]).to_s] = {
                "Type" => "Context",
                "Attributes" => {
                    "name" => "None"
                }
            }
        end
        sort_resource_file
        output_resource_file
    end

    #
    #  リソース情報の共通部の出力
    #
    private
    def print_resource_common
        $res_info = {
            "TimeScale" => "us",
            "TimeRadix" => 10,
            "ConvertRules" => ["fmp-tp"],
            "VisualizeRules" => ["fmp","toppers","asp-tp"],
            "ResourceHeaders" => ["asp-tp"],
            "Resources" => {}
        }
    end

    #
    #  JSON形式のコンフィギュレーションファイルの読込み
    #
    private
    def read_configuration_json_file
        json = ""
        File.open(File.expand_path($configuration_file), "r") do |file|
            while line = file.gets
                json += line
            end
        end
        @stop_conf_info = ((JSON.parser.new(json)).parse())["stop_condition"]
        $log_conf = ((JSON.parser.new(json)).parse())["log"]
    end

    #
    #  JSON形式のアプリケーションファイルの読込み
    #
    private
    def read_application_json_file
        json = ""
        begin
            File.open(File.expand_path($application_file), "r") do |file|
                while line = file.gets
                    json += line
                end
            end
        rescue
            raise_fatal_exception(sprintf("application file read error: %s is not exist.\n",$application_file))
        end

        res = (JSON.parser.new(json)).parse()
        res["cpu"].each do |cpu|
            @cpuid_info << cpu["id"]
            @core_info[cpu["id"]] = []
            cpu["core"].each do |core|
                @core_info[cpu["id"]] << core
                $app_info[core["id"]] = []
                core["application"].each do |app|
                    $tsk_info[app["id"]] = []
                    app["task"].each do |tsk|
                        $tsk_info[app["id"]] << tsk
                    end
                    $app_info[core["id"]] << app
                end
            end
        end
    end

    #
    #  リソース情報のソート
    #
    #  リソース情報（タスク，アプリケーション，実行コンテキスト）をTLV
    #  で可視化したときに，見やすいようソートする．
    #
    private
    def sort_resource_file
        temp_task = {}
        temp_application = {}
        temp_context = {}
        temp_task_sorted = []
        temp_application_sorted = []
        temp_context_sorted = []
        sorted_res_info = OrderedHash.new()

        # リソース情報中の情報をタスク，アプリケーション，コンテキストごとに分けて取り出す
        $res_info["Resources"].each do |i|
            if i[1]["Type"] == "Task"
                temp_task[i[0]] = i[1]
            elsif i[1]["Type"] == "Application"
                temp_application[i[0]] = i[1]
            else
                temp_context[i[0]] = i[1]                
            end
        end

        # コンテキストを名称で昇順にソートする
        temp_context_sorted = temp_context.sort { |a,b|
            a[0] <=> b[0]
        }

        # アプリケーションをプロセッサ番号，IDの順で昇順にソートする
        temp_application_sorted = temp_application.sort { |a,b|
            (a[1]["Attributes"]["prcId"] <=> b[1]["Attributes"]["prcId"]).nonzero? or 
            (a[1]["Attributes"]["id"] <=> b[1]["Attributes"]["id"])
        }
        
        # タスクをプロセッサ番号，アプリケーションID，優先度，IDの順で昇順にソートする
        temp_task_sorted = temp_task.sort { |a,b|
            (a[1]["Attributes"]["prcId"] <=> b[1]["Attributes"]["prcId"]).nonzero? or 
            (a[1]["Attributes"]["appId"] <=> b[1]["Attributes"]["appId"]).nonzero? or 
            (a[1]["Attributes"]["pri"] <=> b[1]["Attributes"]["pri"]).nonzero? or 
            (a[1]["Attributes"]["id"] <=> b[1]["Attributes"]["id"])
        }

        # ソートした情報をリソース情報$res_infoに戻す
        temp_context_sorted.each do |i|
            sorted_res_info[i[0]] = i[1]
        end
        temp_application_sorted.each do |i|
            sorted_res_info[i[0]] = i[1]
        end
        temp_task_sorted.each do |i|
            i[1]["Attributes"].delete("appId") # ソートのために追加したアプリケーションID番号を削除
            sorted_res_info[i[0]] = i[1]
        end
        $res_info["Resources"] = sorted_res_info
    end

    #
    #  リソース情報のファイルへの書き出し
    #
    private
    def output_resource_file
        begin
            File.open($resource_file,'w') { |f|
                f.write JSON.pretty_generate($res_info)
            }
        rescue
            raise_fatal_exception(sprintf("resource file output error: %s could not be created.\n",$resource_file))
        end
    end

    #
    #  シミュレーション本体
    #
    public
    def start
        # シミュレーション時間の設定
        if @sim_time == 0
            @sim_time = 1
            calc_lcm
        end

        @sim_time += $start_time
        regist_scenario
        deadline_miss = 0       # デッドラインミス回数

        printf("simulation time = %f\n", @sim_time) if $DEBUG
        print_log_simulation_start

        #
        #  シミュレーションのメインループ
        #
        while $system_time <= @sim_time
            #
            #  前のイベント時刻から現在のイベント時刻まで，コアごとの最
            #  高優先順位アプリケーションの最高優先順位タスクを実行する．
            #
            printf("============================================\n") if $DEBUG
            begin
                @core_table.each do |core|        
                    $next_flag = false
                    core.signal_time
                    if $next_flag == false
                        core.process_application_event
                    end
                    core.global_scheduling
                    core.print_dispatch_log
                    $event << core.get_next_event_time # 次のイベント時刻を追加
                end

                #
                #  不要なイベント時刻（システム時刻より古いイベント時刻，
                #  重複している時刻）を削除
                #
                $event.delete_if {|x| x < $system_time} 
                $event.sort!{|a,b| a <=> b}
                $event.uniq!

                # 実行時間（システム全体で最も早い次のイベント時刻までの時間）を更新
                next_event = $event.shift
                $exc_time = next_event - $system_time
                printf("--------------------------------------------\n") if $DEBUG
            end while $exc_time == 0
            
            @core_table.each do |core|
                # デッドラインミスの発生チェック
                if core.check_deadline_miss
                    deadline_miss += 1
                    if deadline_miss == @stop_conf_info["deadline_miss"]
                        raise_fatal_exception(sprintf("# of deadline misses reaches %s.\n", deadline_miss))                        
                    end
                end
                # イベント列出力（デバッグ用）
                if core.runapp != nil
                    core.runapp.print_event if $DEBUG
                end
            end

            # 次のイベント時刻までシステム時刻を進める
            $system_time = next_event.round_to($log_conf["system_time"])
        end

        print_log_simulation_finish
    end

    #
    #  LCMの計算
    #
    private
    def calc_lcm
        keta = 0
        # 整数値になる桁数を取得する
        @core_table.each do |core|
            if core.lcm != nil
                keta = [APPLICATION::get_digit(core.lcm),keta].max
            end
        end
        # 桁上げした起動周期を用いてLCMを計算する
        @core_table.each do |core|
            if core.lcm != nil
                val = (core.lcm * (10 ** keta)).to_i
                @sim_time = @sim_time.lcm(val)
            end
        end
        # もとの桁に戻す
        @sim_time /= 10.0 ** keta
    end

    #
    #  タスクのインスタンスの取得
    #
    #  指定するID番号をもつタスクのインスタンスを返す．
    #
    public
    def get_tsk(tskid)
        @core_table.each do |ccb|
            ccb.app_table.each do |app|
                tsk = app.get_tsk(tskid)
                if tsk != nil
                    return tsk
                end
            end
        end
        return nil
    end


    #
    #  アプリケーションのインスタンスの取得
    #
    #  指定するID番号をもつアプリケーションのインスタンスを返す．
    #
    public
    def get_app(appid)
        @core_table.each do |ccb|
            ccb.app_table.each do |tmp_app|
                if appid == tmp_app.id
                    return tmp_app
                end
            end
        end
        return nil
    end

    #
    #  ログ出力機能
    #
    private
    def print_log_simulation_start
        if check_print("simulation", __method__)
            printf("[%d]:[%d]: simulation starts.\n", 
                   ($system_time * 10 ** $log_conf["system_time"]).round, 0)
                   
        end
    end

    public
    def print_log_simulation_finish
        if check_print("simulation", __method__)
            printf("[%d]:[%d]: simulation finished.\n", 
                   ( @sim_time * 10 ** $log_conf["system_time"]).round, 0)
        end
    end

    private
    def check_print(obj, method_name)
        method_name.to_s =~ /print_log_/
        return $log_conf[obj][$']
    end
end

#
#  シミュレーション本体
#
SIM = SIMULATOR.new(sim_time);
SIM.start
