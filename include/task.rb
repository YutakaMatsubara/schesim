# -*- coding: utf-8 -*-
#
#= タスククラスの定義
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

require "./include/common_module"
require "./include/task_api"

class TASK
    include FATAL_ERROR
    # クラス変数（固定値）
    Max_priority = 1        # 最高優先度の値（最も小さな値）
    DELTA_PRD = 0.00000001        # 優先順位の刻み幅

    def initialize(id, pri, p, d, core, app, act_attr, 
                   schedule, offset, max_actcnt, max_wupcnt)

        # インスタンス変数（固定値）
        @id = id                # タスクID
        @pri = pri              # 現在優先度
        @inipri = pri           # 起動時の初期優先度
        @p = p                  # 起動周期
        @d = d                  # 相対デッドライン
        @inicore = core         # 初期割付けコアのインスタンス
        @core = core            # 所属するコアのインスタンス
        @iniapp = app           # 初期割付けアプリケーションのインスタンス
        @app = app              # 所属するアプリケーションのインスタンス
        @act_attr = act_attr    # タスクの起動属性
        @schedule = schedule    # スケジュール属性
        @offset = offset        # 起動オフセット
        @max_actcnt = max_actcnt # 起動要求キューイング数の最大値
        @max_wupcnt = max_wupcnt # 起床要求キューイング数の最大値

        # インスタンス変数（変動値）
        @ts = "DORMANT"         # タスク状態
        @rt = 0.0               # 次のイベントまでの残り時間（起動時は
                                # pretaskhookを実行するために，0を設定
                                # する．
        @prev_rt = nil          # タスク切り替え前の次イベント時刻までの残り時間

        @release_time = []      # 起動時刻（キューイングされる場合を考
                                # 慮して配列で定義）
        @D = []                 # 絶対デッドライン（キューイングされる
                                # 場合を考慮して配列で定義）
        @u = 0                  # CPU利用率
        @actque = 0             # 起動要求キューイング
        @wupque = 0             # 起床要求キューイング

        @pretaskhook_thread = nil  # PreTaskHookスレッド生成
        @posttaskhook_thread = nil # PostTaskHookスレッド生成
        @task_thread = nil         # タスクスレッド生成
        @thread_type = "Task"      # 実行中のスレッド種別

        @lastres = nil          # 最後に獲得したリソース

        @next_state = nil       # タスクの次の状態

        generate_seed
    end

    #
    #  乱数シードの生成
    #
    private
    def generate_seed
        t = Time.now
        @seed = t.sec ^ t.usec ^ Process.pid 
        srand(@seed)
    end

    #
    #  休止状態への遷移
    #
    #  指定されたタスクを休止状態に遷移する．まず，指定されたタスクを実
    #  行できない状態に遷移させ，タスクのパラメータを初期化する．起動要
    #  求がキューイングされている場合には，実行可能状態に遷移し，ログを
    #  出力する．
    #
    public
    def make_dormant
        @ts = "DORMANT"
        print_log_stat

        # タスクのパラメータを初期化する．（タスクの起動要求がキューイ
        # ングされている可能性があるので，actqueは初期化してはいけない）
        @core = @inicore

        @app = @iniapp
        @pri = @inipri
        @wupque = 0
        @rt = 0
        @prev_rt = nil

        if @actque > 0 
            @actque -= 1
            init_task_thread
            print_log_dispatch_from
            make_runnable
            print_log_dispatch_to
        end
    end
    
    #
    #  待ち状態への遷移
    #
    public
    def make_waiting
        @ts = @next_state
        @next_state = nil
        print_log_stat

        if @wupque > 0
            @wupque -= 1
            print_log_dispatch_from
            make_runnable
            print_log_dispatch_to
        end
    end

    #
    #  実行可能状態への遷移
    #
    #  指定されたタスクを実行可能状態に遷移する．タスクのデッドラインを
    #  設定し，レディーキューとデッドラインキューに挿入する．
    #
    public
    def make_runnable
        @ts = "RUNNABLE"
        print_log_stat
        if @d != nil
            new_D = @release_time[@release_time.size - 1] + @d
            @D.push(new_D)
            @D.sort!{|a,b| a <=> b}
            @app.deadline_queue.push(self)
            @app.deadline_queue.sort!{|a,b| a.D[0] <=> b.D[0]}
            set_event(new_D)
        end
        @app.ready_queue.push(self)
        set_priorder    # 優先順位を考慮した優先度の値を設定
        @app.schedule_task
    end

    # 
    #  タスクを実行できない状態に遷移した後の処理
    #
    #  この関数は，すでにタスクが実行できない状態（待ち状態もしくは休止
    #  状態）になった後に呼び出される．タスクが実行できない状態に遷移し
    #  た後は，対象タスクをレディーキューから外し，絶対デッドラインが設
    #  定されている場合（対象タスクがデッドラインをミスしている場合には，
    #  この時点ですでにデッドラインキューから外されている）には，デッド
    #  ラインキューからも外す．
    #
    public
    def make_non_runnable
        if @release_time.size == @D.size
            # デッドラインミスをしていない場合
            $event.delete(@D[0])
            @D.shift
        end
        @release_time.shift
        @app.ready_queue.delete_at(@app.ready_queue.index(self))
        if @app.deadline_queue.index(self) != nil
            @app.deadline_queue.delete_at(@app.deadline_queue.index(self))
        end
    end

    #
    #  Taskのスレッドを初期化する
    #
    private
    def init_task_thread
        @task_thread = task_thread_new
        @task_thread.resume  # スレッドの初期化完了を待つ
    end
    
    #
    #  PreTaskHookのスレッドを初期化する
    #
    public
    def init_pretaskhook_thread
        @pretaskhook_thread = pretaskhook_thread_new
        @pretaskhook_thread.resume  # スレッドの初期化完了を待つ
    end

    #
    #  PostTaskHookのスレッドを初期化する
    #
    public
    def init_posttaskhook_thread
        @posttaskhook_thread = posttaskhook_thread_new
        @posttaskhook_thread.resume  # スレッドの初期化完了を待つ
    end

    #
    #  タスクの起動
    #  
    #  タスクを起動する．休止状態のタスクを起動する場合は，残り実行時間，
    #  絶対デッドライン，次の起動時刻を設定し，実行可能状態に遷移する．
    #  対象タスクが，すでに実行可能状態もしくは待ち状態になっている場合
    #  には，起動要求をキューイングする．
    #
    public
    def make_active
        if @ts == "DORMANT"
            set_release_event
            init_task_thread
            make_runnable
        elsif @ts == "RUNNABLE" || @ts == "WAITING"
            if @max_actcnt == nil || @actque < @max_actcnt
                @actque += 1
                print_log_actque
            else
                print_log_ovractcnt
            end
            set_release_event
        end
    end

    #
    #  タスクの次の起動時刻を決定する
    #
    #  周期（cyclic）タスクの場合は，現在時刻に周期を加算した時刻を次の
    #  起動時刻とする．離散（sporadic）タスクの場合は，現在時刻に乱数に
    #  より生成した周期（最小到着間隔に，指数分布に従う乱数をジッタとし
    #  て加算した値）を加算した時刻を次回の起動時刻とする．周期的に起動
    #  しないタスク（normal）の場合は，次の起動時刻を設定しない．
    #  
    private
    def set_release_event
        case @act_attr
        when "cyclic"
            @app.add_event($system_time + @p, "act_tsk", self)
        when "sporadic"
            j = ((- Math::log(1-rand()))/0.4).truncate # ジッタの計算
            @app.add_event($system_time + @p + j, "act_tsk", self)
        when "normal"
            # 次の起動時刻は設定しない
        else
            raise_fatal_exception(sprintf("configuration file read error: attribute '%s' is not supported.\n", @act_attr))
        end
    end

    #
    #  次のイベント時刻までの残り時間を保存する
    #
    public
    def store_remaining_time
        @prev_rt = @rt
        printf("[%d]:[%d]: task %d store rt %s.\n", ($system_time * 10 ** $log_conf["system_time"]).round, @core.id, @id, @rt) if $DEBUG
    end

    #
    #  次のイベント時刻までの残り時間を復帰する
    #
    public
    def restore_remaining_time
        if @prev_rt != nil
            @rt = @prev_rt
            @prev_rt = nil
            printf("[%d]:[%d]: task %d restore rt %s.\n", ($system_time * 10 ** $log_conf["system_time"]).round, @core.id, @id, @rt) if $DEBUG
        else
            $event << $system_time
        end
    end

    #
    #  PreTaskHookの実行を開始するときの処理
    #
    public
    def start_pretaskhook
        $event << $system_time
        init_pretaskhook_thread
        print "Move to PreTaskHook\n"  if $DEBUG
        $next_flag = true
    end

    #
    #  PostTaskHookの実行を開始するときの処理
    #
    public
    def start_posttaskhook
        $event << $system_time
        init_posttaskhook_thread
        print "Move to PostTaskHook\n"  if $DEBUG
        $next_flag = true
    end

    #
    #  デッドラインミスのチェック
    #
    #  対象タスクがデッドラインをミスしているかどうかをチェックする．対
    #  象タスクがデッドラインをミスしていたら，そのデッドラインに対する
    #  監視を止めるため，対象タスクの最も早いデッドラインを削除する．ロ
    #  グを出力してtrueを返す．デッドラインミスをしていなければ，false
    #  を返す．
    #
    public
    def check_deadline_miss
        if @D != [] && @D[0] <= $system_time
            print_log_deadline_miss
            $event.delete(@D[0])
            @D.shift
            return true
        end
        return false
    end

    #
    #  タスクのイベント時刻を設定
    #
    private
    def set_event(evt)
        $event << evt.round_to($log_conf["system_time"])
    end

    #
    #  タスクのリソース情報を出力
    #
    public
    def print_resource_file_task
        $res_info["Resources"]["TASK"+@id.to_s] = {
            "Type" => "Task",
            "Attributes" => {
                "prcId" => @core.id,
                "appId" => @app.id,
                "id" => @id,
                "pri" => @pri
            }
        }
    end

    #
    #  タスクのスレッド管理
    #

    #
    #  PreTaskHookスレッドの生成
    #
    private
    def pretaskhook_thread_new
        thread = Fiber.new do
            Fiber.yield
            if @app.call_preapphook
                @app.preapplication_hook
                @app.call_preapphook = false
            end
            pretask_hook            
        end
        return thread
    end

    #
    #  PostTaskHookスレッドの生成
    #
    private
    def posttaskhook_thread_new
        thread = Fiber.new do
            exc(0)              # タスク終了とPostTaskHookの間でタスク
                                # が切り替わらないようにイベントをセッ
                                # トする．
            posttask_hook
            if @app.call_postapphook
                @app.postapplication_hook
                @app.call_postapphook = false
            end
        end
        return thread
    end

    #
    #  タスクスレッドの生成
    #
    private
    def task_thread_new
        thread = Fiber.new do
            Fiber.yield
            start_task
            __send__("task" + @id.to_s)
        end
        return thread
    end

    #
    #  タスクの実行開始時の処理
    # 
    private
    def start_task
        if @schedule == "non"
            set_priorder(Max_priority)
        end
    end

    #
    #  優先順位の設定
    #
    #  指定した優先度をもつタスクで，かつ，すでに優先順位が付加されてい
    #  るタスクの中で，もっとも低い優先順位を決定して割り当てる．具体的
    #  には，指定した優先度をもつタスクで，かつ，すでに優先順位が付加さ
    #  れているタスク（休止状態ではないタスク）の数に対して，微小な優先
    #  度を加算して値を増加する（実行する優先度としては低い）．
    #
    public
    def set_priorder(pri = nil)
        if pri == nil
            pri = @pri.truncate
        end
        @pri = pri + (DELTA_PRD * @app.count_ready_pri_task(pri))
    end

    #
    #  タスクの実行
    #
    #  アプリケーションに属するタスクを指定した時間（$exc_time）だけ実
    #  行する．タスクが属するアプリケーションの残りバジェットを実行した
    #  時間だけ減らす．実行できる時間が，次のイベントまでの時間であれば
    #  タスクのスレッドを実行する．実行できる時間が，次のイベント時刻よ
    #  り前にある場合には，実行できる時間分だけ，次のイベントまでの時間
    #  を減らす．excが完了する時刻は，必ず次のイベントになるはずである．
    #
    public
    def execute_task
        if $exc_time != 0
            @app.reduce_budget($exc_time) 
        end

        # 実行中タスクの次のイベント時刻までの時間を計算
        @rt = [(@rt - $exc_time).round_to($log_conf["system_time"]), 0].max

        if @rt == 0
            case @thread_type
            when "Task"
                @task_thread.resume
            when "PostTaskHook"
                @posttaskhook_thread.resume
            when "PreTaskHook"
                @pretaskhook_thread.resume
            end
        elsif @rt > 0
            # 何もしない
        else
            raise_fatal_exception(sprintf("Fatal runtime error: rt = %f, exc_time = %f, system_time = %f\n", @rt, $exc_time, $system_time))
            exit(1)
        end

        #
        #  実行中タスクのスレッド実行後の状態遷移
        #
        #  タスクが待ち状態に遷移するか，タスクスレッドの実行が完了した
        #  （タスク関数の処理が完了した）場合には，PostTaskHookの実行を
        #  開始する．
        #
        #  タスクがPostTaskHookの実行を終了した結果，タスクが待ち状態の
        #  場合には実行できない状態へ遷移する．スレッドの実行が完了した
        #  場合には，さらに休止状態へ遷移する．
        #
        if @thread_type == "Task" && check_non_runnable
            # このタスクが実行可能ではない状態に遷移すると，アプリケー
            # ションが休止状態に遷移する場合には，PostAppHookを呼び出す
            # フラグを立てる．
            if @app.ready_queue.size == 1
                @app.call_postapphook = true
            end
            start_posttaskhook
            @thread_type = "PostTaskHook"
            @app.tsk_dis_dsp = true
        elsif @thread_type == "PostTaskHook" && !(@posttaskhook_thread.alive?) 
            if check_non_runnable
                make_non_runnable
                if !(@task_thread.alive?)
                    make_dormant
                else
                    make_waiting
                end
            else
                # PostTaskHook実行中に実行可能状態に遷移した場合                
            end
        end
    end

    #
    #  タスクが実行可能ではない状態であることをチェック
    #
    private
    def check_non_runnable
        return (@next_state != nil || !(@task_thread.alive?))
    end

    #
    #  ログ出力機能
    #
    public
    def print_pram
        printf("id = %s, pri= %s, period = %s, deadline = %s, offset = %s, utilization = %f \n", @id, @pri, @p, @d, @offset, @u) if $DEBUG               
    end

    public
    def print_log_stat
        if check_print("task", __method__)
            printf("[%d]:[%d]: task %s becomes %s.\n", 
                   ($system_time * 10 ** $log_conf["system_time"]).round, 
                   @core.id, @id, @ts)
        end
    end

    public
    def print_log_dispatch_from
        if check_print("task", __method__)
            printf("[%d]:[%d]: dispatch from task %s.\n", 
                   ($system_time * 10 ** $log_conf["system_time"]).round, 
                   @core.id, @id)
        end
    end

    public
    def print_log_dispatch_to
        if check_print("task", __method__)
            printf("[%d]:[%d]: dispatch to task %s.\n", 
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id) 
        end
    end

    public
    def print_log_deadline_miss
        if check_print("task", __method__)
            printf("[%d]:[%d]: task %s misses deadline.\n", 
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id)
        end
    end

    public
    def print_log_actque
        if check_print("task", __method__)
            printf("[%d]:[%d]: number of activation requests of task %s is %d.\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, @actque)
        end
    end

    public
    def print_log_wupque
        if check_print("task", __method__)
            printf("[%d]:[%d]: number of wakeup requests of task %s is %d.\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, @wupque)
        end
    end

    public
    def print_log_ovractcnt
        if check_print("task", __method__)
            printf("[%d]:[%d]: number of activation requests of task %s over max_actcnt.\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id)
        end
    end

    public
    def print_log_ovrwupcnt
        if check_print("task", __method__)
            printf("[%d]:[%d]: number of wakeup requests of task %s over max_wupcnt.\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id)
        end
    end

    public
    attr_accessor :pri, :p, :d, :ts, :rt, :D, :u, :release_time, :id, :posttaskhook_thread, :pretaskhook_thread, :offset, :core, :app, :max_wupcnt, :wupque, :thread_type
end
