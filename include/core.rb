# -*- coding: utf-8 -*-
#
#= コアクラスの定義
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

require "./include/event"
require "./include/common_module"

class CORE
    include FATAL_ERROR

    def initialize(core_id, scheduling)
        # 定数値
        @id = core_id               # コアのID番号
        @scheduling = scheduling    # アプリケーションのスケジューリング

        # 属するアプリケーションの情報
        @runapp = nil                    # 実行中のアプリケーション
        @schedapp = nil                  # 最高優先順位のアプリケーション
        @app_table = []                  # アプリケーションのテーブル
        @lcm = 1                         # アプリケーションの周期のLCM
        @u = 0                           # アプリケーションセットのプロセッサ利用率

        @app_dsp_flg = false  # アプリケーション切り替えが発生したこと
                              # を示すフラグ
        @app_dis_dsp = false
        @prev_runapp = nil      # 前に実行していたアプリケーション

        # スケジューリング用キュー
        @ready_queue = []                   # アプリケーションのレディーキュー
        @app_event_queue = EVENT_LIST.new() # アプリケーションのイベント管理キュー（絶対時刻）

        initialize_core
    end

    public
    attr_accessor :id, :app_table, :runapp, :lcm, :ready_queue, :scheduling

    #
    #  コアの初期化
    #
    private
    def initialize_core
        u = 0
        $app_info[@id].each do |app|
            app_id = app["id"]
            share = app["share"]
            check_positive_number("share", share, app_id)
            local_scheduling = app["scheduling"]
            pri = app["pri"]
            check_positive_number("priority", pri, app_id)
            period = app["period"]
            check_positive_number("period", period, app_id)

            # シェアの合計が1を越えた場合にはエラー
            u += share
            if 1 < u 
                raise_fatal_exception(sprintf("configuration file read error: sum of share of application %d is greater than 1.\n", id))
            end

            case @scheduling
            when "fp", "edf"
                if app_id == 1
                    cyc_app = CYCLIC_APPLICATION.new(app_id, self, share, local_scheduling, pri, period)
                    @app_table << cyc_app
                    add_event(1,"act_app",cyc_app)
                else
                    rand_app = CYCLIC_APPLICATION.new(app_id, self, share, local_scheduling, pri, period)
                    @app_table << rand_app
                    add_event(1,"act_app",rand_app)
                end
            when "bss"
                # 階層型スケジューリングBSSモード
                @app_table << BSS_APPLICATION.new(app_id, self, share, local_scheduling, pri)
            when "tpa"
                # 階層型スケジューリングTPAモード
                if app_id == 1
                    @app_table << TPA_APPLICATION.new(app_id, self, share, local_scheduling, pri)
                else
#                    rand_app = RANDOM_APPLICATION.new(app_id, self, share, local_scheduling, pri, period)
                    rand_app = CYCLIC_APPLICATION.new(app_id, self, share, local_scheduling, pri, period)
                    @app_table << rand_app
                    add_event(1,"act_app",rand_app)
                end
            else
                raise_fatal_exception(sprintf("Global scheduling algorithm '%s' is not supported.\n", scheduling))
            end
        end
        
        # アプリケーションの初期化
        @app_table.each do |app|
            app.initialize_application
        end 

        calc_lcm
        print_resource_file_app
    end

    #
    #  パラメータが正の整数であることをチェック
    #
    private
    def check_positive_number(param_name, val, id)
        if val <= 0
            raise_fatal_exception(sprintf("Configuration error: %s of application %d is equal to or lower than 0.\n", param_name, id))
        end
    end

    #
    #  LCMの計算
    #
    private
    def calc_lcm
        keta = 0
        # 整数値になる桁数を取得する
        @app_table.each do |app|
            if app.lcm != nil
                keta = [APPLICATION::get_digit(app.lcm),keta].max
            end
            @u = @u + app.u
        end
        # 桁上げした起動周期を用いてLCMを計算する
        @app_table.each do |app|
            if app.lcm != nil
                val = (app.lcm * (10 ** keta)).to_i
                @lcm = @lcm.lcm(val)
            end
        end
        # もとの桁に戻す
        @lcm /= 10.0 ** keta
    end
    
    #
    #  アプリケーションに関するリソースファイルの出力
    #
    private
    def print_resource_file_app
        @app_table.each do |app|
            $res_info["Resources"]["APPLICATION"+app.id.to_s] = {
                "Type" => "Application",
                "Attributes" => {
                    "prcId" => @id,
                    "id" => app.id,
                    "share" => app.share
                }
            }
        end
    end

    #
    #  コアにティックを供給する
    #
    #  実行可能なアプリケーションがあれば，そのアプリケーションの最高優
    #  先度タスクを実行する．実行可能なアプリケーションがなければ，アイ
    #  ドル時の処理をする．
    #
    public
    def signal_time
        if @runapp != nil
            execute_application
        else
            idle
        end
    end

    #
    #  アプリケーション内の実行状態タスクの実行
    #
    #  実行状態アプリケーションの実行状態タスクを実行する．タスクを実行
    #  した結果，タスクが切り替えが発生し，かつアプリケーションが実行可
    #  能状態である場合は，アプリケーションを再スケジューリングする．こ
    #  の再スケジューリングは，本来は不要であるが，絶対デッドラインが同
    #  じアプリケーションはどちらを先に実行しても構わないことを確認する
    #  ために実行している．この後に，アプリケーションの状態を遷移する．
    #
    private 
    def execute_application
        if @runapp.runtsk == nil
            raise "assert"
            exit(1)
        end
        @runapp.runtsk.execute_task
        #
        #  実行中アプリケーションのタスクを実行した結果，実行中アプリケー
        #  ションを，実行可能状態からその他の状態へ遷移するための処理
        #
        if @runapp.ready_queue.empty?
            #
            #  実行中のアプリケーションに，実行できるタスクが存在せず
            #  （PostTaskHookの実行も完了している），レディーキューが空
            #  になっている場合には，実行可能状態から休止状態に遷移する．
            #
            @runapp.make_application_dormant
            @ready_queue.delete_at(@ready_queue.index(@runapp))
            @prev_runapp = @runapp
            @runapp = nil
        elsif @runapp.budget <= 0
            #
            #  実行中アプリケーションの実行を継続するためのバジェットが
            #  なくなった場合には，実行可能状態から満了状態に遷移する．
            #  この状態遷移は，次の２段階で実行する．
            #
            #  (1) 実行中アプリケーションの実行中タスクのPostTaskHookを
            #      実行する．PostTaskHookが完了するまで実行中アプリケー
            #      ションの状態は実行可能状態とする．
            #
            #  (2) 実行中アプリケーションを満了状態に遷移する．
            #
            if @runapp.runtsk.thread_type == "Task"
                # 実行中アプリケーションを満了状態に遷移する準備をする．
                @runapp.make_application_non_runnable
            elsif @runapp.runtsk.thread_type == "PostTaskHook" && !@runapp.runtsk.posttaskhook_thread.alive?
                # 実行可能状態から満了状態に遷移する．
                @runapp.make_application_expired
                @ready_queue.delete_at(@ready_queue.index(@runapp))
                @prev_runapp = @runapp
                @app_dsp_flg = true
                @runapp = nil
            end
        end
    end
    
    #
    #  プロセッサアイドル時の処理
    #
    #  プロセッサがアイドル状態のときは，満了状態のアプリケーションを除
    #  くアプリケーションについて，アイドル時間だけ実行されたときと同じ
    #  処理をする．すなわち，バジェットの残っているアプリケーションのバ
    #  ジェットから，アイドル時間分のバジェットを減らす．この処理の対象
    #  から満了状態のアプリケーションを除く理由は，すでに得られたシェア
    #  分のバジェットを消費しているためである．
    #
    private
    def idle
        printf("[%d]:[%d]: core %d is idle.\n", 
               ($system_time * 10 ** $log_conf["system_time"]).round,
               @id, @id) if $DEBUG

        @app_table.each do |app|
            if app.as != "EXPIRED" && app.budget > 0
                app.reduce_budget($exc_time)
            end
        end
    end

    #
    #  イベント処理
    #
    #  コアに属するアプリケーションのタスクイベントを処理し，アプリケー
    #  ションの状態を遷移する．次に，アプリケーションイベントを処理する．
    #
    public
    def process_application_event
        @app_table.each do |app|
            app.process_task_event
            # 休止状態または満了状態からの状態遷移
            if !(app.ready_queue.empty?)
                if app.as == "DORMANT"
                    app.make_application_expired
                end
                if app.as == "EXPIRED" && app.budget > 0
                    app.make_application_runnable
                    @ready_queue.push(app)
                end
            end
        end
        event = @app_event_queue.check_event
        event.each do |evt|
            send(evt.inst,*evt.args)
        end
    end

    # コア内でアプリケーションをスケジューリングする
    public
    def global_scheduling
        local_scheduling
        schedule_application
        dispatch_application
    end

    # 
    #  アプリケーション内のスケジューリング
    #
    #  アプリケーション内のタスクスケジューリングとタスク切換えをする．
    #
    private
    def local_scheduling
        @app_table.each do |app|
            app.schedule_task
            app.dispatch_task
        end
    end

    # コア内のアプリケーションのスケジューリング
    private
    def schedule_application
        case @scheduling
        when "fp"
            sched_app_fp
        when "edf", "bss", "tpa"
            sched_app_edf
        else 
            # エラー処理
            raise_fatal_exception(sprintf("Global scheduling algorithm '%s' is not supported.\n", @scheduling))
        end
    end

    # アプリケーションのスケジューリング（固定優先度スケジューリング）
    private
    def sched_app_fp
        @ready_queue.sort!{|a,b| a.pri <=> b.pri}
    end

    # アプリケーションのスケジューリング（レートモノトニッックスケジューリング）
    private
    def sched_app_rm
        @ready_queue.sort!{|a,b| a.p <=> b.p}
    end

    # アプリケーションのスケジューリング（EDF）
    private
    def sched_app_edf
        @ready_queue.sort!{|a,b| a.D <=> b.D}
    end

    #
    # アプリケーションの切り替え
    #
    private
    def dispatch_application
        if @runapp != nil
            if @app_dis_dsp && @runapp.tsk_dsp_flg
                # アプリケーションスケジューリングによるアプリケーショ
                # ン切り替えが保留された状態で，PostTaskHookの実行が完
                # 了したときにここにくる．このあとに，アプリケーション
                # を切り替える．
                @app_dis_dsp = false
                @app_dsp_flg = true
            elsif @runapp.tsk_dis_dsp
                # 実行中アプリケーションが，タスク切り替え禁止状態のと
                # きは，アプリケーションの切り替えをせずにリターンする．
                return
            end
        end

        # アプリケーション切り替え処理
        @schedapp = @ready_queue[0]        
        if @schedapp != @runapp
            if @runapp != nil
                if !@app_dsp_flg && !@runapp.tsk_dis_dsp && @runapp.runtsk != nil && @runapp.runtsk.thread_type == "Task"
                    # 実行中アプリケーションのタスク切替え要求が発生し
                    # ていない状況で，アプリケーションをスケジューリン
                    # グした結果，実行中アプリケーションから別のアプリ
                    # ケーションに実行を切り替える必要がある場合には，
                    # 実行中のアプリケーションを実行できない状態に遷移
                    # する．
                    @runapp.make_application_non_runnable
                    @app_dis_dsp = true
                    return
                end
                @prev_runapp = @runapp
            end
            @runapp = @schedapp
            #　実行状態のアプリが切り替わるので，PreAppHookを呼び出すた
            #  めのフラグを立てる．
            @runapp.call_preapphook = true

            if !@app_dsp_flg
                @app_dsp_flg = true
            end
        end
    end

    # デッドラインミスのチェック
    public
    def check_deadline_miss
        @app_table.each do |app|
            if app.check_deadline_miss
                return true
            end
        end
        return false
    end

    #
    #  イベントキューへのイベント追加
    #
    public
    def add_event(time,inst,args)
        @app_event_queue.add_event(time.round_to($log_conf["system_time"]),inst,args)
    end

    #
    #  タスクの起動
    #
    public
    def act_app(app)
        app.act_app
    end
        
    #
    #  タスク切替えログの表示
    # 
    public
    def print_dispatch_log
        if @app_dsp_flg && !@app_dis_dsp
            # アプリ切替えが発生した場合
            if @prev_runapp != nil
                # ディスパッチされたアプリケーションのログ（dispatch
                # from）を出力する
                @prev_runapp.print_log_dispatch_from
                @prev_runapp.print_prev_runtsk_dispatch_from 
                @prev_runapp = nil 
            end
            if @runapp != nil
                # ディスパッチしたアプリケーションのログ（dispatch to）
                # を出力する
                @runapp.print_log_dispatch_to
                @runapp.print_runtsk_dispatch_to
                if @runapp.tsk_dsp_flg
                    @runapp.tsk_dsp_flg = false
                end
            end
            @app_dsp_flg = false
        elsif @runapp != nil && @runapp.tsk_dsp_flg
            # 実行中アプリケーション内でタスク切替えが発生した場合
            @runapp.print_prev_runtsk_dispatch_from
            @runapp.print_runtsk_dispatch_to
            @runapp.tsk_dsp_flg = false
        end
    end

    #
    #  コアイベント時刻の取得
    #
    #  アプリケーションの起動イベントと実行中アプリケーションの実行中タ
    #  スクの終了時刻の中で最も早いイベントの時刻をコアのイベントとする．
    #
    public
    def get_next_event_time
        # アプリケーションの起動時刻で最も早い時刻
        event = @app_event_queue.get_next_event_time

        # シナリオファイルや実行中に登録された，タスクに関するイベントで最も早い時刻
        @app_table.each do |app|
            event = [event, app.get_next_event_time].min
        end

        # 実行中アプリケーションに関するイベントの登録
        if @runapp != nil
            # アプリケーションのバジェットが0になる可能性のある時刻を登
            # 録する．この時点でバジェットが0になっている場合には，ルー
            # プしてしまうため，登録する必要はない．
            if @runapp.budget > 0
                event = [event, $system_time + @runapp.budget].min
            end
            # 実行中タスクの次イベント（実行終了もしくはAPI呼び出し）が
            # 発生する可能性のある時刻を登録する．
            if @runapp.runtsk != nil
                event = [event, $system_time + @runapp.runtsk.rt].min
            end
        end
        return event.round_to($log_conf["system_time"])
    end

    #
    #  シナリオライブラリ
    #
    #  シナリオファイルで利用できる関数群を定義する．
    #

    # 
    #  モードの変更
    #
    def chg_mod(mode, val)
        if TASK.class_variable_defined?(mode)
            TASK.class_eval {
                class_variable_set(mode, val)
            }
        else
            raise_fatal_exception(sprintf("scenario file error: mode '%s' is undefined.\n", mode))
        end
    end
end
