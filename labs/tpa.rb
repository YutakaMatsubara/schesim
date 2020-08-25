# -*- coding: utf-8 -*-
#
#= アプリケーションの定義（時間保護アルゴリズム）
#
#Authors:: Yutaka MATSUBARA (ERTL, Nagoya Univ.)
#Version:: 0.8.0
#License:: Apache License, Version 2.0
#
#== License:
#
#  Copyright 2011 Yutaka MATSUBARA
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

require "./labs/bss"

class TPA_TASK < BSS_TASK
    # 
    #  タスクを実行可能状態にした後の処理
    #
    #  指定されたタスクをデッドラインキューに挿入する．この関数は，タス
    #  クの状態が実行可能状態になった後に呼び出されることを前提としてい
    #  る．タスクをレディーキューに入れるか，起動を遅延するかは，この後
    #  の処理で判断するため，ここでレディーキューに入れてはいけない．
    #
    public
    def make_runnable
        @ts = "RUNNABLE"
        print_log_stat
        if @d != nil
            new_D = @release_time[0] + @d
            @D << new_D
            @D.sort!{|a,b| a <=> b}
            @app.deadline_queue << self
            @app.deadline_queue.sort!{|a,b| a.D[0] <=> b.D[0]}
            set_event(new_D)
        end

        # 遅延条件を満たすかチェック
        if check_activation_delay
            @app.act_waiting_tsk_queue.push(self)
        else
            # 起動を遅延しない場合にはレディーキューに入れてスケジューリング
            @app.ready_queue.push(self)
            set_priorder    # 優先順位を考慮した優先度の値を設定
            @app.schedule_task
        end

        @app.update_deadline
        @app.replenish_budget
        @budget_list.print_budgetlist if $DEBUG
    end

    # 
    #  起動するタスクの起動遅延をチェック
    #
    #  実行するタスクが以下の遅延条件を満たすかどうかをチェックし，遅延
    #  させる場合はtrueを返す．
    #
    #  ※τ：レディーキューのタスク
    #  (1) τより優先度が高い
    #  (2) τより絶対デッドラインが遅い
    #
    private
    def check_activation_delay
        if !@app.ready_queue.empty?
            @app.ready_queue.each do |task_tau|
                if @pri.truncate < task_tau.pri.truncate && @D[0] > task_tau.D[0]
                    return true
                end
            end
        end
        return false
    end

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
                exc_thread(@task_thread)
            when "PostTaskHook"
                exc_thread(@posttaskhook_thread)
            when "PreTaskHook"
                exc_thread(@pretaskhook_thread)
            end
        elsif @rt > 0
            # 何もしない
        else
            raise_fatal_exception(sprintf("Fatal runtime error: rt = %f, exc_time = %f, system_time = %f\n", @runtsk.rt, $exc_time, $system_time))
            exit(1)
        end

        #
        #  実行中タスクのスレッド実行後の状態遷移
        #
        #  実行中タスクのスレッドを実行した結果，タスクが待ち状態に遷移
        #  した場合，またはスレッドの実行が完了した場合には，
        #  PostTaskHookの実行を開始する．
        #
        #  タスクがPostTaskHookの実行を終了した結果，タスクが待ち状態の
        #  場合には待ち状態へ遷移する．スレッドの実行が完了した場合には，
        #  休止状態へ遷移する．
        #
        if @thread_type == "Task"
            if @ts == "WAITING" || @ts == "WAIT_SLP" || !(@task_thread.status)
                start_posttaskhook
                @thread_type = "PostTaskHook"
                @app.tsk_dis_dsp = true
            end
        elsif @thread_type == "PostTaskHook" && !(@runtsk.posttaskhook_thread.status)
            if @runtsk.ts == "WAITING" || @runtsk.ts == "WAIT_SLP"
                make_non_runnable(@runtsk)
            elsif !(@runtsk.task_thread.status)
                make_dormant(@runtsk)

                #
                #  タスク起動遅延の解除チェック
                #
                #  実行を完了したタスクが，起動を遅延しているタスクの起
                #  動遅延条件の対象になっている場合に，そのタスクの起動
                #  遅延を解除するかどうかをチェックする．起動遅延を解除
                #  する場合には，起動遅延キューから一つずつタスクを解除
                #  して，すぐにレディーキューに接続する．
                #
                release_tsk = []
                @app.act_waiting_tsk_queue.each do |tsk|                    
                    if !tsk.check_activation_delay
                        release_tsk.push(tsk)
                        # 起動待ちを解除したタスクを，次のタスクの遅延
                        # 条件の対象に加えるために，すぐにレディーキュー
                        # に追加する．
                        @app.ready_queue.push(tsk)
                        tsk.set_priorder    # 優先順位を考慮した優先度の値を設定
                    end
                end
                #  起動遅延を解除するタスクを起動待ちキューから削除する
                release_tsk.each do |tsk|
                    @app.act_waiting_tsk_queue.delete_at(@app.act_waiting_tsk_queue.index(tsk))
                end
            end
        end
    end
end

class TPA_APPLICATION < BSS_APPLICATION
    def initialize(app_id,core,share,scheduling,pri)
        super(app_id,core,share,scheduling,pri)
        # スケジューリング用キュー
        @act_waiting_tsk_queue = [] # 起動待ちタスクキュー
    end
end
