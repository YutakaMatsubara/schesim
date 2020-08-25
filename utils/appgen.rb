#! /usr/bin/env ruby
# -*- coding: utf-8 -*-
#
#= アプリケーション・ジェネレータ
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
#=== デフォルト（アプリケーションファイルの出力先/apps, 生成アプリケーション数は1000）
# # ./utils/appgen.rb
#
#=== アプリケーションファイルの出力先ディレクトリの指定
# # ./utils/appgen.rb -d ./apps
#=== 生成するアプリケーション数の指定
# # ./utils/appgen.rb -t 1000
#=== レートモノトニック用の優先度割当て
# # ./utils/appgen.rb -p rm
#=== アプリケーションの生成条件（Lipariの予測）の適用
# # ./utils/appgen.rb -C
#=== 1プロセッサ内のコア数の指定
# # ./utils/appgen.rb -c 2
#=== 1コア内のアプリケーション数の指定
# # ./utils/appgen.rb -a 2
#=== タスクのスケジューリング属性（cyclic/sporadic）
# # ./utils/appgen.rb -n sporadic
#=== グローバルスケジューリングアルゴリズム（fp, edf, bss, tpa）
# # ./utils/appgen.rb -g fp
#=== ローカルスケジューリングアルゴリズム（fp, edf）
# # ./utils/appgen.rb -l fp
#

require "rubygems"
require "json"                  # JSON
require "optparse"              # コマンドライン引数

# グローバル変数の定義
$tnum_generate_apps = 1000      # 生成するアプリケーションの数
$tnum_cpu = 1                   # システムのCPU数
$tnum_core = 1                  # 1プロセッサ内のコア数
$tnum_app = 2                   # 1コア内のアプリ数

$cond = false           # アプリケーションの生成条件の適用
$agn_pri = "rand"       # 優先度割当てモード（デフォルト：ランダム）
$output_dir = "./apps/" # アプリケーションファイルを出力するディレクトリ
$act_attr = "cyclic"    # タスクの起動属性（デフォルト：周期起動）
$global_scheduling = "tpa"    # グローバルスケジューリングアルゴリズム
$local_scheduling = "fp"      # ローカルスケジューリングアルゴリズム

$seed = nil                     # 乱数生成に使用するシード

# コマンドライン引数の処理
opt = OptionParser.new

# アプリケーションファイルの出力先ディレクトリの指定
opt.on('-d VAL') {|v| 
    $output_dir = v.to_s
}

# アプリケーションの生成数の指定
opt.on('-t VAL') {|v| 
    $tnum_generate_apps = v.to_i
}

# コア数の指定
opt.on('-c VAL') {|v| 
    $tnum_core = v.to_i
}

# アプリケーション数の指定（邪魔アプリケーションを含む）
opt.on('-a VAL') {|v| 
    $tnum_app = v.to_i
}

# 優先度割当てポリシの指定
opt.on('-p VAL') {|v| 
    $agn_pri = v.to_s
}

# 乱数生成時に使用するシードの指定
opt.on('-s VAL') {|v| 
    $seed = v.to_i
}

# アプリケーション生成条件の適用
opt.on('-C') {
    $cond = true
}

# タスクのスケジュール属性の指定
opt.on('-n VAL') { |v| 
    $act_attr = v.to_s
}

# グローバルスケジューリングアルゴリズム
opt.on('-g VAL') { |v| 
    $global_scheduling = v.to_s
}

# ローカルスケジューリングアルゴリズム
opt.on('-l VAL') { |v| 
    $local_scheduling = v.to_s
}

opt.parse!(ARGV)

class GENERATOR
    def initialize(seed)
        # 固定値
        @MAX_TASK = 20        # １つのアプリケーション内の最大タスク数
        @MAX_PRIORITY = 15    # 最大優先度（最低優先度）
        @MAX_WCET = 10        # 統合前の最大最悪実行時間
        @MAX_PERIOD = 50      # 起動のベース周期

        @obstable_task_wcet = 100000 # 邪魔アプリのタスクの最悪実行時間

        # 変動値
        @tnum_generated_apps = 1 # 生成したアプリケーションファイル数
        @tsk_table = []          # 生成したタスクを一時的に格納する
        @res_info_json = []      # リソース情報（json）

        # オブジェクトのID（全体で一意に割り当てられる）
        @cpu_id = 1
        @core_id = 1
        @app_id = 1
        @tsk_id = 1

        @seed = seed

        if @seed == nil
            generate_seed
        end
        p @seed if $DEBUG
        srand(@seed)
    end

    def reinitialze
        # 変動値
        @tsk_table = []          # 生成したタスクを一時的に格納する
        @res_info_json = []      # リソース情報（json）

        # オブジェクトのID（全体で一意に割り当てられる）
        @cpu_id = 1
        @core_id = 1
        @app_id = 1
        @tsk_id = 1
    end

    # 
    #  メインルーチン
    #
    def start
        while @tnum_generated_apps <= $tnum_generate_apps
            reinitialze
            generate_res_info
            print_res_info if $DEBUG
            output_app_json_file
            output_app_desc_file
            @tnum_generated_apps += 1
        end
    end

    #
    #  乱数生成のための種を生成
    #
    def generate_seed
        t = Time.now
        @seed = t.sec ^ t.usec ^ Process.pid 
    end

    #
    #  リソース情報の生成
    #
    def generate_res_info
        @res_info_json = {
            "cpu" => []
        }
        $tnum_cpu.times {
            @res_info_json["cpu"] << generate_cpu_info()
            @cpu_id += 1
        }
    end

    #
    #  CPU情報の生成
    #
    def generate_cpu_info
        cpu_info = {
            "id" => @cpu_id,
            "core" => []
        }
        $tnum_core.times {
            cpu_info["core"] << generate_core_info()
            @core_id += 1
        }
        return cpu_info
    end

    #
    #  コア情報の生成
    #
    def generate_core_info
        core_info = {
            "id" => @core_id,
            "application" => [],
            "scheduling" => $global_scheduling,
        }
        obstacle_flag = false
        $tnum_app.times {
            core_info["application"] << generate_app_info(obstacle_flag)
            obstacle_flag = true
            @app_id += 1
        }
        return core_info
    end

    #
    #  アプリケーション情報の生成
    #
    #  引数のフラグがfalseの場合は，評価用アプリケーションを生成し，
    #  trueの場合は，邪魔アプリケーションを生成する．邪魔アプリケーショ
    #  ンは，デッドラインを持たず，終了しない（無限ループ処理）タスク１
    #  つで構成される．
    #
    def generate_app_info(obstacle_flag)
        app_info = {
            "id" => @app_id,
            "share" => 1.0 / $tnum_app,
            "scheduling" => $local_scheduling,
            "pri" => @app_id,
            "period" => 10,
            "task" => [],
        }

        if obstacle_flag
            tsk = {
                "id" => @tsk_id,
                "priority"=> 1,
                "period" => @obstable_task_wcet,
                "wcet" => @obstable_task_wcet,
                "attr" => "cyclic",
                "offset" => 0
            }
            @tsk_id += 1
            app_info["task"] << tsk
        else
            begin
                generate_application
                assign_priority
            end while $cond && !(check_app_condition)
            @tsk_table.each do |tsk|
                tsk["id"] = @tsk_id
                @tsk_id += 1
                app_info["task"] << tsk
            end
        end
        return app_info
    end

    #
    #  アプリケーションの生成
    #
    #  アプリケーションを生成する．起動周期（最小到着間隔）は，[1,周期
    #  の最大値]間でランダムに生成する．最悪実行時間も，[1,最大最悪実行
    #  時間]間でランダムに生成する．相対デッドラインは，起動周期に一致
    #  するものとする．タスクの優先度はassign_priority関数で割り当てる
    #  ので，ここでは何も設定しない．生成するアプリケーションの条件とし
    #  て，タスクのプロセッサ利用率（最悪実行時間／起動周期）の合計が
    #  100%以下であるものとする．
    #
    def generate_application
        @tsk_table = []
        sum_u = 0.0             # 合計プロセッサ利用率
        i = 0                   # 生成したタスク数
        @MAX_TASK.times {
            c = 1 + rand(@MAX_WCET)
            p = c + 1 + rand(@MAX_PERIOD)
            d = p
            u = c.quo(p)
            if sum_u + u <= 1
                sum_u += u 
                @tsk_table << {
                    "period" => p,
                    "wcet" => c,
                    "offset" => 0,
                    "deadline" => d,
                    "attr" => $act_attr,
                }
            end
        }
    end
    
    #
    #  タスクへの優先度割当て
    #
    #  タスクテーブル（@tsk_table）に格納されたタスクに対して，指定され
    #  た優先度割当てポリシに基づいて優先度を割当てる．優先度割当てポリ
    #  シは，RM，DM，ランダムのいずれかである．同一アプリケーション内に，
    #  同一の優先度をもつタスクが複数存在しないように優先度を割当てる．
    #
    def assign_priority
        case $agn_pri
        when "rm"
            # 周期が短い順に優先度を割当てる
            @tsk_table.sort!{|a,b| a["period"] <=> b["period"]}
        when "dm"
            # 相対デッドラインが短い順に優先度を割当てる
            @tsk_table.sort!{|a,b| a["deadline"] <=> b["deadline"]}
        when "rand"
            # 何もせず生成された順序で優先度を割当てる
        else
            # エラー処理
            STDERR.printf("Priority assignment policy '%s' is not supported.\n")
            exit(1)
        end

        # 優先度の割当
        i = 1
        @tsk_table.each do |tsk|
            tsk["priority"] = i
            i += 1
        end
        @tsk_table.sort!{|a,b| a["priority"] <=> b["priority"]}
    end

    #
    #  生成したタスクセットをチェックする
    #  
    #  生成するタスクセットが条件を満たしているかをチェックする．現在の
    #  条件は，次の通りである．(1)の条件はタスク生成時
    #  （generate_application関数の実行時）にチェックするので，ここでは
    #  (2) の条件のみをチェックする．
    # 
    #  (1) タスクセットのCPU利用率は1以下とする
    #  (2) Lipariの推測を満たす
    #
    #  この関数では，(2)の推測を満たす場合にtrueを返す．
    def check_app_condition
        (@tsk_table.size).times { |i|
            task_i = @tsk_table[i]
            ti = task_i["period"]
            s = 0
            (i+1).times { |j|
                task_j = @tsk_table[j]
                tj = task_j["period"]
                cj = task_j["wcet"]
                s += (ti.quo(tj)).ceil * cj
            }
            if s > ti
                return false
            end
        }
        return true
    end

    #
    #  リソース情報の表示
    #
    def print_res_info()
        print JSON.pretty_generate(@res_info_json)
    end

    #
    #  リソース情報をJSON形式でファイルに出力
    #
    def output_app_json_file
        $file_name = format("%06d",@tnum_generated_apps) + ".json"

        File.open(File.expand_path($output_dir + $file_name),'w') { |f|
            f.write JSON.pretty_generate(@res_info_json)
        }
    end

    #
    #  タスク処理記述ファイルの出力
    #
    def output_app_desc_file
        $file_name = format("%06d",@tnum_generated_apps) + ".rb"

        File.open(File.expand_path($output_dir + $file_name),'w') { |f|
            f.print "class TASK\n"
            @res_info_json["cpu"].each do |cpu|
                cpu["core"].each do |core|
                    core["application"].each do |app|
                        f.print "\t @@share" + app["id"].to_s + " = " + app["share"].to_s + "\n"
                        app["task"].each do |tsk|
                            f.print "\t def task" + tsk["id"].to_s + "\n"
                            if tsk["wcet"] == @obstable_task_wcet
                                f.print "\t\t while(1)\n"
                                f.print "\t\t\t exc(" + @obstable_task_wcet.to_s + ")\n"
                                f.print "\t\t end\n"
                            else
                                f.print "\t\t exc(" + tsk["wcet"].to_s + " * @@share" + app["id"].to_s + ")\n"
                            end
                            f.print "\t end\n"
                        end
                    end
                end
            end
            f.print "end\n"
        }
    end
end


# 
#  アプリケーション生成処理
#
gen = GENERATOR.new($seed)
gen.start
