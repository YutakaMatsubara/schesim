# -*- coding: utf-8 -*-
#
#= アプリケｰションクラスの定義
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
require "./include/budget"
require "./include/common_module"

class APPLICATION
    include FATAL_ERROR
    INFINITY = 1000000000

    def initialize(app_id,core,share,scheduling,pri)
        # 定数値
        @id = app_id            # アプリケーションID
        @core = core            # 所属するコアのインスタンス
        @share = share          # シェア（百分率）
        @scheduling = scheduling # タスクスケジューリングアルゴリズム
        @pri = pri              # 優先度
        @d = INFINITY           # 相対デッドライン
        @D = @d                 # アプリケーションの絶対デッドライン

        # 変数値
        @as = "DORMANT"         # アプリケーションの状態
        @budget = 0             # アプリケーションのバジェット
        @release_time = $start_time  # アプリケーションの次の起動時刻（周期起動のみ）
        
        # スケジューリングに関連する情報
        @runtsk = nil           # 実行中のタスク
        @schedtsk = nil         # 最高優先順位タスク
        @tsk_table = []         # タスクのテーブル
        @u = 0                  # タスクセットのプロセッサ利用率
        @lcm = 1                # タスクセット周期のLCM
        @tsk_dsp_flg = false    # タスク切り替えが発生したことを示すフ
                                # ラグ
        @tsk_dis_dsp = false    # タスク切替え禁止状態（フック実行中）
                                # であることを示すフラグ
        @prev_runtsk = nil      # 前に実行していたタスク

        # フック関数に関する情報
        @call_preapphook = false # PreAppHookを呼び出すことを示すフラグ
        @call_postapphook = false # PostAppHookを呼び出すことを示すフラグ

        # スケジューリング用キュー
        @tsk_event_queue = EVENT_LIST.new() # タスクのイベント管理キュー（絶対時刻）
        @ready_queue = []       # タスクレディーキュー
        @deadline_queue = []    # タスクデッドラインキュー
    end

    #
    #  アプリケーションの初期化
    #
    def initialize_application
        read_application
        calc_lcm

        #
        #  タスクの初期起動のセット
        # 
        #  タスクの初期起動イベントをセットする．イベントの発生時刻はア
        #  プリケーション情報ファイルのオフセット（offset）で指定された
        #  値である．オフセットが指定されていない場合には，初期起動をし
        #  ない．オフセットに負の値が指定された場合には，エラーとする．
        #
        @tsk_table.each do |tsk|            
            if tsk.offset == nil
            elsif tsk.offset >= 0
                add_event($system_time + tsk.offset,"act_tsk",tsk)
            else
                raise_fatal_exception(sprintf("input error: invalid offset of task %d.\n",tsk.id))
            end
        end
    end

    #
    #  タスクセットの読み込み
    #
    def read_application
        $tsk_info[@id].each do |tsk|
            id = tsk["id"]
            pri = tsk["priority"]
            check_positive_number("priority", pri, id)
            p = tsk["period"]
            check_positive_number("period", p, id)
            c = tsk["wcet"]
            check_positive_number("wcet", c, id)
            d = tsk["deadline"]
            if d != nil
                check_positive_number("deadline", d, id)
            end
            attr = tsk["attr"]
            schedule = tsk["schedule"]
            if schedule != "full" && schedule != "non"
                if schedule == nil
                    schedule = "full"
                else
                    raise_fatal_exception(sprintf("Configuration error: schedule attribution '%s' of task %d is invalid.\n", schedule, id))
                end
            end
            offset = tsk["offset"]
            if offset != nil
                check_nonnegative_number("offset", offset, id)
            end
            max_actcnt = tsk["max_actcnt"]
            if max_actcnt != nil
                check_nonnegative_number("max_actcnt", max_actcnt, id)
            end
            max_wupcnt = tsk["max_wupcnt"]
            if max_wupcnt != nil
                check_nonnegative_number("max_wupcnt", max_wupcnt, id)
            end

            case @core.scheduling
            when "bss"
                tsk = BSS_TASK.new(id, pri, p, d, @core, self, attr, schedule, offset, max_actcnt, max_wupcnt)
            when "tpa"
                tsk = TPA_TASK.new(id, pri, p, d, @core, self, attr, schedule, offset, max_actcnt, max_wupcnt)
            else
                tsk = TASK.new(id, pri, p, d, @core, self, attr, schedule, offset, max_actcnt, max_wupcnt)
            end
#            tsk = TASK_LOAD_BALANCE.new(id, pri, p, d, @core, self, attr, schedule, offset, max_actcnt, max_wupcnt)

            # タスク関数が定義されているかチェック
            if !TASK.method_defined?("task"+id.to_s)
                raise_fatal_exception(sprintf("Configuration error: undefined main function of task %d.\n",id))
            end
            @tsk_table << tsk
            if p != nil && c != nil
                tsk.u = c.quo(p)
                @u += tsk.u
            end
            tsk.print_pram
        end
        output_resource_file
    end

    #
    #  パラメータが正の整数であることをチェック
    #
    def check_positive_number(param_name, val, id)
        if val != nil and val < 0
            raise_fatal_exception(sprintf("Configuration error: '%s' of task %d is nil or lower than 0.\n", param_name, id))
        end
    end

    #
    #  パラメータが0以上の整数であることをチェック
    #
    def check_nonnegative_number(param_name, val, id)
        if val == nil or (val.nonzero? && val < 0)
            raise_fatal_exception(sprintf("Configuration error: '%s' of task %d is nil or negative value.\n", param_name, id))
        end
    end

    #
    #  LCMの計算
    #
    #  タスクの起動周期のLCMを計算する．タスクの起動正気が浮動小数点表
    #  現の数値で与えられた場合には，一度整数値になるよう桁上げして，
    #  LCMを計算する．
    #
    private
    def calc_lcm
        keta = 0
        # 整数値になる桁数を取得する
        @tsk_table.each do |tsk|
            if tsk.p != nil && tsk.p != 0
                keta = [APPLICATION::get_digit(tsk.p),keta].max
            end
        end
        # 桁上げした起動周期を用いてLCMを計算する
        @tsk_table.each do |tsk|
            if tsk.p != nil && tsk.p != 0
                val = (tsk.p * (10 ** keta)).to_i
                @lcm = @lcm.lcm(val)
            end
        end
        # もとの桁に戻す
        @lcm /= 10.0 ** keta
    end

    #
    #  浮動小数点表現の数値の小数点以下の桁数を取得する
    #
    #  他のクラスのメソッドでも使用するので，クラスメソッドとする．
    #
    def self.get_digit(f_val)
        count = 0
        f_str = f_val.to_s.split(/\./)[1]
        if f_str != nil
            f_str.each_byte {|c| count += 1}
        end
        return count
    end

    #
    #  タスクのリソースファイルの出力
    #
    def output_resource_file
        @tsk_table.each do |tsk|
            tsk.print_resource_file_task
        end
    end

    #
    #  アプリケーションのバジェットを減らす
    #
    public
    def reduce_budget(b)
        @budget = (@budget - b).round_to($log_conf["system_time"])
        print_log_budget
    end

    #
    #  イベントを処理する
    #
    public
    def process_task_event
        event = @tsk_event_queue.check_event
        event.each do |evt|
            send(evt.inst,*evt.args)
        end
    end

    #
    #  イベントキューへのイベント追加
    #
    public
    def add_event(time,inst,args)
        @tsk_event_queue.add_event(time.round_to($log_conf["system_time"]),inst,args)
    end

    #
    #  タスクの起動
    #
    public
    def act_tsk(tsk)
        tsk.act_tsk(tsk.id)
    end

    #
    #  アプリケーション内タスクのスケジューリング
    #
    public
    def schedule_task
        case @scheduling
        when "fp"
            sched_tsk_fp
        when "edf"
            sched_tsk_edf
        else 
            raise_fatal_exception(sprintf("Local scheduling algorithm '%s' is not supported.\n", @scheduling))
        end
        @schedtsk = @ready_queue[0]
    end

    #
    #  タスクのスケジューリング（固定優先度スケジューリング）
    #
    private
    def sched_tsk_fp
        @ready_queue.sort!{|a,b| a.pri <=> b.pri}
    end

    #
    #  タスクのスケジューリング（EDF）
    #
    private
    def sched_tsk_edf
        @ready_queue.sort!{|a,b| a.D[0] <=> b.D[0]}
    end

    #
    #  タスクの切り替え
    #
    public
    def dispatch_task
        if @runtsk != nil && @runtsk.thread_type == "PreTaskHook"
            if @runtsk.pretaskhook_thread.alive?
                # PreTaskHookの実行が完了するまで実行する
                # この間はタスク切替えは発生しない
                return
            else
                # PreTaskHookの完了後に，タスクの本体の処理を開始する準
                # 備をする
                @runtsk.restore_remaining_time
                @runtsk.thread_type = "Task"
                print "Move to Task\n" if $DEBUG
                @tsk_dis_dsp = false
                $next_flag = true
            end
        end
        if @runtsk == nil || @runtsk.thread_type == "Task"
            if @runtsk != @schedtsk
                # 実行するタスクを切り替える準備をする
                if @runtsk != nil
                    # 実行中タスクから別のタスクに実行を切り替える準備をする．
                    @runtsk.store_remaining_time
                    @runtsk.start_posttaskhook
                    @runtsk.thread_type = "PostTaskHook"
                    @tsk_dis_dsp = true
                else
                    # アイドル状態からタスクの実行を開始する
                    @prev_runtsk = nil
                    @tsk_dsp_flg = true
                end
            end
        end
        if @runtsk != nil && @runtsk.thread_type == "PostTaskHook"
            if @runtsk.posttaskhook_thread.alive?
                # PostTaskHookの実行が完了するまで実行するこの間はタス
                # ク切替えは発生しない
                return
            else
                @prev_runtsk = @runtsk
                @tsk_dsp_flg = true
                @tsk_dis_dsp = false
                @runtsk.thread_type = "Task"
                print "Move to Task\n"  if $DEBUG
                $next_flag = true
            end
        end

        # タスク切替え処理
        if @tsk_dsp_flg && !@tsk_dis_dsp
            @runtsk = @schedtsk
            if @runtsk != nil
                # 実行中タスクから別タスクの実行を開始する
                @runtsk.start_pretaskhook
                @runtsk.thread_type = "PreTaskHook"
                @tsk_dis_dsp = true
            else
                # 実行中タスクのPostTaskHookを完了してアイドル状態
                # （runtsk == nil && schedtsk == nil）になる．
            end
        end
    end

    # 
    #  タスクのデッドラインミスのチェック
    #
    #  アプリケーションに属するタスクがデッドラインをミスしていたら
    #  trueを返す．デッドラインをミスしているタスクがなければ，falseを
    #  返す．対象タスクに監視するデッドラインがない場合には，デッドライ
    #  ンキューから削除する．
    #
    public
    def check_deadline_miss
        miss_flag = false
        tmp_deadline_queue = @deadline_queue
        @deadline_queue = []
        tmp_deadline_queue.each do |tsk|
            if tsk.check_deadline_miss
                miss_flag = true
            end
            if tsk.D != []
                @deadline_queue.push(tsk)
            end
        end
        @deadline_queue.sort!{|a,b| a.D[0] <=> b.D[0]}
        return miss_flag
    end

    #
    #  アプリケーションの次のイベントまでの相対時刻を取得
    #
    #  シナリオファイルで登録されたタスク起動イベントの中で最も早いイベ
    #  ントまでの時刻を返す．
    #
    public
    def get_next_event_time
        return @tsk_event_queue.get_next_event_time
    end

    #
    #  タスクIDからタスクのインスタンスを取得
    #
    public
    def get_tsk(tskid)
        @tsk_table.each do |tsk|
            if tskid == tsk.id
                return tsk
            end
        end
        return nil
    end

    #
    #  指定した優先度のレディーキューの回転
    #
    public
    def rotate_ready_queue(pri)
        # priと同じ優先度を持つタスクを一時配列に移動
        tmp_array = @ready_queue.select{|x| x.pri.truncate == pri}
        @ready_queue.reject!{|x| x.pri.truncate == pri}

        # priと同じ優先度を持つタスクが存在しない場合はリターン
        if tmp_array == []
            return
        end

        # 先頭のタスクを末尾へ移動
        tmp_array.push(tmp_array.shift)

        # 優先順位の再割当て
        tmp_array.each do |x| 
            @ready_queue.push(x)
            x.set_priorder
        end

        # 再スケジューリング
        schedule_task
    end

    #
    #  アプリケーションのイベント情報の表示（デバッグ用）
    #
    public
    def print_event
        printf("APP %d: \n", @id)
        printf("[%f]budget = %s, event = %s, exc_time = %s, absolute deadline = %s.\n", $system_time, @budget, $event[0], $exc_time, @D)
        printf("event_queue\n")
        print_event_queue
        printf("-----------------\n")
        printf("deadline_queue\n")
        @deadline_queue.each do |tsk|
            print tsk.id, ":", tsk.D[0], "\n"
        end
        printf("-----------------\n")
    end

    #
    #  アプリケーションの状態遷移に関連する関数
    #

    #
    #  アプリケーションを実行可能状態に遷移
    #
    #  アプリケーションが満了状態の場合は，実行可能状態に遷移してtrueを
    #  返す．実行可能状態もしくは休止状態の場合は，なにもしない．アプリ
    #  ケーションが休止状態から実行可能状態に遷移する際には，休止状態か
    #  ら直接，実行可能状態に遷移することはなく，休止状態からは一度満了
    #  状態に遷移した後に実行可能状態になるので，ここでは何もする必要は
    #  ない．
    #
    public
    def make_application_runnable
        case @as
        when "EXPIRED"
            @as = "RUNNABLE"
            print_log_stat
            return true
        when "RUNNABLE"
            # すでに実行可能状態の場合はなにもしない
        when "DORMANT"
            # 休止状態の場合はなにもしない
        end
        return false
    end    

    #
    #  アプリケーションを実行できない状態に遷移
    #
    #  対象アプリケーションの実行中タスクの次イベントまでの残り時間を保
    #  存し，PostTaskHookを実行する．
    #
    public
    def make_application_non_runnable       
        @runtsk.store_remaining_time
        @runtsk.start_posttaskhook
        @runtsk.thread_type = "PostTaskHook"
        @call_postapphook = true
        @tsk_dis_dsp = true
    end

    #
    #  アプリケーションを満了状態に遷移
    #
    public
    def make_application_expired        
        @as = "EXPIRED"
        print_log_stat
    end

    #
    #  アプリケーションを休止状態に遷移
    #
    public
    def make_application_dormant
        @as = "DORMANT"
        print_log_stat
    end

    # 
    #  指定する優先度をもつ実行可能なタスク数を計算
    #
    public
    def count_ready_pri_task(pri)
        num = 0
        @ready_queue.each do |tsk|
            if pri == tsk.pri.truncate
                num += 1
            end
        end
        return num
    end

    #
    #  アプリケーションの起動
    #
    #  アプリケーションを起動する．アプリケーションが実行可能状態に遷移
    #  した場合には，レディーキューに挿入する．
    #
    public
    def act_app
        if make_application_active
            @core.ready_queue.push(self)
        end
    end

    # 
    #  アプリケーションの起動
    # 
    #  アプリケーションにバジェットを補充する．アプリケーションが実行可
    #  能状態になり，アプリケーションレディーキューに挿入する必要がある
    #  場合には，trueを返す．そうでない場合には，falseを返す．
    #
    public
    def make_application_active
        update_deadline
        replenish_budget        # バジェットの補充
        return make_application_runnable
    end

    #
    #  アプリケーションの絶対デッドラインの更新
    #
    #  アプリケーションの絶対デッドラインは，現在のシステム時刻と相対デッ
    #  ドラインを加算して求める．アプリケーションの絶対デッドラインは，
    #  EDFでスケジュールするために必要となる．
    #
    public
    def update_deadline
        @D = $system_time + @d
    end

    #
    #  バジェットの補充
    #
    public
    def replenish_budget
        @budget = @d * @share
        print_log_budget
    end

    #
    #  ログ出力機能
    #
    private
    def print_acb
        printf("id = %s, d = %s, share = %f.\n", @id, @d, @share)
    end

    private
    def print_log_stat
        if check_print("application", __method__)
            printf("[%d]:[%d]: application %s becomes %s.\n", 
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, @as)
        end
    end

    public
    def print_log_dispatch_from
        if check_print("application", __method__)
            printf("[%d]:[%d]: dispatch from application %s.\n", 
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id)
        end
    end

    public
    def print_log_dispatch_to
        if check_print("application", __method__)
            printf("[%d]:[%d]: dispatch to application %s.\n", 
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id)
        end
    end

    public
    def print_log_deadline_miss
        if check_print("application", __method__)
            printf("[%d]:[%d]: application %s misses deadline.\n", 
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id)
        end
    end

    public
    def print_log_budget
        if check_print("application", __method__)
            # TLVでの表示を見やすくするため，残りバジェットの値を10倍している．
            printf("[%d]:[%d]: budget of application %s is %s.\n", 
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, (@budget * 10).ceil)
        end
    end

    public
    def print_prev_runtsk_dispatch_from
        if @prev_runtsk != nil
            @prev_runtsk.print_log_dispatch_from
        end
    end

    public
    def print_runtsk_dispatch_from
        if @runtsk != nil
            @runtsk.print_log_dispatch_from
        end
    end

    public
    def print_runtsk_dispatch_to
        if @runtsk != nil
            @runtsk.print_log_dispatch_to
        end
    end

    private
    def check_print(obj, method_name)
        method_name.to_s =~ /print_log_/
        return $log_conf[obj][$']
    end

    private
    def print_event_queue
        @tsk_event_queue.print_event_list
    end

    private
    def print_log_preapplicationhook_start
        if check_print("application", __method__)
            printf("[%d]:[%d]: PreAppHook of application %s starts.\n", 
                   ($system_time * 10 ** $log_conf["system_time"]).round, @core.id, @id)
        end
    end

    private
    def print_log_preapplicationhook_finished
        if check_print("application", __method__)
            printf("[%d]:[%d]: PreAppHook of application %s finished.\n", ($system_time * 10 ** $log_conf["system_time"]).round, @core.id, @id)
        end
    end

    private
    def print_log_postapplicationhook_start
        if check_print("application", __method__)
            printf("[%d]:[%d]: PostAppHook of application %s starts.\n", ($system_time * 10 ** $log_conf["system_time"]).round, @core.id, @id)
        end
    end

    private
    def print_log_postapplicationhook_finished
        if check_print("application", __method__)
            printf("[%d]:[%d]: PostAppHook of application %s finished.\n", ($system_time * 10 ** $log_conf["system_time"]).round, @core.id, @id)
        end
    end

    public
    attr_accessor :id, :p, :d, :D, :as, :budget, :share, :runtsk, :schedtsk, :ready_queue, :u, :lcm, :release_time, :pri, :tsk_dsp_flg, :tsk_dis_dsp, :prev_runtsk, :core, :deadline_queue, :call_preapphook, :call_postapphook
end

# 
#  アプリケーションの定義（周期実行アルゴリズム）
#
class CYCLIC_APPLICATION < APPLICATION
    include FATAL_ERROR
    def initialize(app_id, core, share, scheduling, pri, period)
        super(app_id,core,share,scheduling,pri)
        @p = period
        @d = @p
    end

    #
    #  アプリケーションの周期起動
    #
    #  アプリケーションを起動する．アプリケーションが実行可能状態に遷移
    #  した場合には，レディーキューに挿入して，次の起動時刻をイベントと
    #  してセットする．
    #
    public
    def act_app
        super
        @core.add_event($system_time + @p,"act_app",self)
    end

    #
    #  ログ出力機能
    #
    private
    def print_acb
        printf("id = %s, p = %s, d = %s, share = %f.\n", @id, @p, @d, @share)
    end
end

# 
#  アプリケーションの定義（ランダム周期実行アルゴリズム）
#
class RANDOM_APPLICATION < CYCLIC_APPLICATION
    def initialize(app_id,core,share,scheduling,pri,period)
        super(app_id,core,share,scheduling,pri,period)
        @MAX_PERIOD = period
        generate_seed
    end

    #
    #  乱数のシードを生成
    #
    private
    def generate_seed
        t = Time.now
        @seed = t.sec ^ t.usec ^ Process.pid 
        srand(@seed)
    end


    #
    #  アプリケーションの周期起動
    #
    public
    def act_app
        update_deadline
        super
    end

    #
    #  アプリケーションの絶対デッドラインの更新
    #
    public
    def update_deadline
        @d = rand(@MAX_PERIOD)
        @p = @d
        super
    end
end
