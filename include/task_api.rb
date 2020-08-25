# -*- coding: utf-8 -*-
#
#= タスク処理記述用APIライブラリの定義
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

class TASK
    #
    #  APIの定義
    #

    #
    #  プロセッサ時間の消費
    #
    public
    def exc(exc_time)
        @rt = exc_time
        Fiber.yield
        printf("Task %d is executed at %d.\n", @id, $system_time) if $DEBUG
    end

    # 
    #  タスクの起動
    #
    public
    def act_tsk(tskid, reltim = 0)
        tsk = SIM.get_tsk(tskid)
        if tsk == nil
            return "E_ID"
        end
        if reltim == 0
            print_log_act_tsk(tskid)
            tsk.release_time << $system_time
            tsk.make_active
        else
            tsk.app.add_event($system_time + reltim, "act_tsk", tsk)
        end
    end

    #
    #  セマフォの資源の獲得
    #
    #  セマフォを獲得できた場合には，スレッドの実行を継続する．セマフォ
    #  を獲得できなかった場合には，自タスクを待ち状態にして，セマフォ待
    #  ちキューに接続する．さらに，実行するタスクを切り替えるため，スレッ
    #  ドを停止する．
    #
    private
    def wai_sem(sem)
        print_log_wai_sem(get_instance_name(sem))
        if !sem.get_sem
            sem.push_queue(self)
            @next_state = "WAITING"
            Fiber.yield
        end
    end

    #
    #  セマフォの資源の返却
    #
    private
    def sig_sem(sem)
        print_log_sig_sem(get_instance_name(sem))
        tsk = sem.rel_sem
        if tsk != nil
            tsk.release_time << $system_time
            tsk.make_runnable
            Fiber.yield
        end
    end

    #
    #  タスクを起床待ちにする
    #
    private
    def slp_tsk
        print_log_slp_tsk
        if @wupque > 0
            @wupque -= 1
            ercd = "E_OK"
        else
            @next_state = "WAIT_SLP"
            print_log_stat
            Fiber.yield
            ercd = "E_OK"
        end
        return ercd
    end

    #
    #  タスクの起床
    #
    private
    def wup_tsk(tskid)
        print_log_wup_tsk(tskid)
        tsk = SIM.get_tsk(tskid)
        if tsk == nil
            return "E_ID"
        end
        if tsk.ts == "WAIT_SLP"
            tsk.release_time << $system_time
            tsk.make_runnable
            Fiber.yield
            ercd = "E_OK"
        elsif tsk.ts == "DORMANT"
            ercd = "E_OBJ"
        else
            if tsk.max_wupcnt == nil || tsk.wupque < tsk.max_wupcnt
                tsk.wupque += 1
                print_log_wupque
                ercd = "E_OK"
            else
                print_log_ovrwupcnt
                ercd = "E_QOVR"
            end
        end
        return ercd
    end

    #
    #  タスクの優先順位の回転
    #
    private
    def rot_rdq(pri)
        print_log_rot_rdq(pri)
        @app.rotate_ready_queue(pri) 
    end

    #
    #  タスクの割付けアプリケーションの変更
    #
    #  tskidで指定したタスクの割付けアプリケーションを，appidで指定した
    #  アプリケーションに変更する．対象タスクが，自タスクが割り付けられ
    #  たアプリケーションに割り付けられている場合には，対象タスクを
    #  appidで指定したアプリケーションに割り付ける．対象タスクが実行で
    #  きる状態の場合には，appidで指定したアプリケーションに割り付けら
    #  れた同じ優先度のタスクの中で，最も優先順位が低い状態となる．対象
    #  タスクが，自タスクが割付けられたアプリケーションと異なるアプリケー
    #  ションに割り付けられている場合には，E_OBJエラーとなる.
    #
    private
    def mig_tsk(tskid, appid)
        print_log_mig_tsk(tskid, appid)
        tsk = SIM.get_tsk(tskid)
        new_app = SIM.get_app(appid)

        if tsk == nil
            return "E_ID"
        end

        # 対象タスクが，自タスクが割りつけられたアプリケーションと異な
        # る場合には，E_OBJエラーを返す．
        if @app != tsk.app
            return "E_OBJ"
        end
        
        # 対象タスクが実行できる状態の場合には，現在の割付アプリケーショ
        # ンのレディキューから外す
        if tsk.ts == "RUNNABLE"
            tsk.make_non_runnable
        end

        # マイグレーション先のアプリケーションのレディキューに挿入
        tsk.core = new_app.core
        tsk.app = new_app
        if tsk.ts == "RUNNABLE"
            tsk.make_runnable
        end
        return "E_OK"
    end

    #
    #  リソースの獲得
    #
    #  獲得するリソースの管理ブロックに，リソース獲得前のタスク優先度と
    #  最後に確保したリソースを保存する．その後に，リソース獲得後のタス
    #  ク優先度（ceiling）を取得し，最後に確保したリソースを更新する．
    #  最後に，現在のタスク優先度をceilingまで上げる．
    #
    private
    def GetResource(res)
        print_log_GetResource(get_instance_name(res))
        ceilpri = res.get_resource(@pri, @lastres)
        @lastres = res
        if ceilpri < @pri
            @pri = ceilpri
        end
    end

    #
    #  リソースの解放
    #
    #  リソースを解放して，タスクの優先度をリソース獲得前に戻し，このリ
    #  ソースを確保する前に確保していたリソースをlastresに戻す．
    #
    private
    def ReleaseResource(res)
        print_log_ReleaseResource(get_instance_name(res))
        @pri, @lastres = res.release_resource
        Fiber.yield
    end

    #
    #  イベント待ち
    #
    #  引数で指定したイベントがセットされていなければ，タスクを待ち状態
    #  に遷移させて，イベント待ちキューに接続する．すでにイベントがセッ
    #  トされている場合には，そのまま実行を継続する．
    #
    private 
    def WaitEvent(evt) 
        print_log_WaitEvent(get_instance_name(evt)) 
        if !evt.get_flag
            @next_state = "WAITING"
            evt.push_queue(self) 
            Fiber.yield
        end 
    end

    #
    #  イベントのセット
    #
    private
    def SetEvent(evt)
        print_log_SetEvent(get_instance_name(evt))
        task_list = evt.set_event
        if task_list != []
            task_list.each do |tsk|
                tsk.release_time << $system_time
                tsk.make_runnable
            end
            Fiber.yield
        end
    end

    #
    #  イベントのクリア
    #
    private
    def ClearEvent(evt)
        print_log_ClearEvent(get_instance_name(evt))
        evt.clear_event
    end

    #
    #  計測区間の開始
    #
    private
    def begin_measure(id)
        print_log_begin_measure(id)
    end

    #
    #  計測区間の終了
    #
    private
    def end_measure(id)
        print_log_end_measure(id)
    end

    #
    #  タスク処理記述中の変数名の取得
    #
    private
    def get_instance_name(obj)
        var_list = TASK.class_variables
        var_list.each do |var|
            if obj == TASK.class_eval{ class_variable_get(var) }
                return var
            end
        end
        return nil
    end

    #
    #  ログ出力機能
    #
    private
    def print_log_act_tsk(id)
        if check_print("api", __method__)
            printf("[%d]:[%d]: applog strtask : TASK %s : act_tsk(%d).\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, id)
        end
    end

    private
    def print_log_wai_sem(name)
        if check_print("api", __method__)
            printf("[%d]:[%d]: applog strtask : TASK %s : wai_sem(%s).\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, name)
        end
    end

    private
    def print_log_sig_sem(name)
        if check_print("api", __method__)
            printf("[%d]:[%d]: applog strtask : TASK %s : sig_sem(%s).\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, name)
        end
    end


    private
    def print_log_slp_tsk
        if check_print("api", __method__)
            printf("[%d]:[%d]: applog strtask : TASK %s : slp_tsk.\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id)
        end
    end
    

    private
    def print_log_wup_tsk(id)
        if check_print("api", __method__)
            printf("[%d]:[%d]: applog strtask : TASK %s : wup_tsk(%d).\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, id)
        end
    end
    

    private
    def print_log_rot_rdq(pri)
        if check_print("api", __method__)
            printf("[%d]:[%d]: applog strtask : TASK %s : rot_rdq(%s).\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, pri)
        end
    end

    private
    def print_log_mig_tsk(tskid, prcid)
        if check_print("api", __method__)
            printf("[%d]:[%d]: applog strtask : TASK %s : mig_tsk(%s,%s).\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, tskid, prcid)
        end
    end

    private
    def print_log_GetResource(name)
        if check_print("api", __method__)
            printf("[%d]:[%d]: applog strtask : TASK %s : GetResource(%s).\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, name)
        end
    end

    private
    def print_log_ReleaseResource(name)
        if check_print("api", __method__)
            printf("[%d]:[%d]: applog strtask : TASK %s : ReleaseResource(%s).\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, name)
        end
    end

    private
    def print_log_SetEvent(name)
        if check_print("api", __method__)
            printf("[%d]:[%d]: applog strtask : TASK %s : SetEvent(%s).\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, name)
        end
    end

    private
    def print_log_WaitEvent(name)
        if check_print("api", __method__)
            printf("[%d]:[%d]: applog strtask : TASK %s : WaitEvent(%s).\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, name)
        end
    end

    private
    def print_log_ClearEvent(name)
        if check_print("api", __method__)
            printf("[%d]:[%d]: applog strtask : TASK %s : ClearEvent(%s).\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, name)
        end
    end

    private
    def print_log_pretaskhook_start
        if check_print("task", __method__)
            printf("[%d]:[%d]: PreTaskHook of task %s starts.\n", 
                   ($system_time * 10 ** $log_conf["system_time"]).round, @core.id, @id)
        end
    end

    private
    def print_log_pretaskhook_finished
        if check_print("task", __method__)
            printf("[%d]:[%d]: PreTaskHook of task %s finished.\n", ($system_time * 10 ** $log_conf["system_time"]).round, @core.id, @id)
        end
    end

    private
    def print_log_posttaskhook_start
        if check_print("task", __method__)
            printf("[%d]:[%d]: PostTaskHook of task %s starts.\n", ($system_time * 10 ** $log_conf["system_time"]).round, @core.id, @id)
        end
    end

    private
    def print_log_posttaskhook_finished
        if check_print("task", __method__)
            printf("[%d]:[%d]: PostTaskHook of task %s finished.\n", ($system_time * 10 ** $log_conf["system_time"]).round, @core.id, @id)
        end
    end

    private
    def print_log_begin_measure(id)
        if check_print("api", __method__)
            printf("[%d]:[%d]: applog strtask : TASK %s : begin_measure(%d).\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, id)
        end
    end

    private
    def print_log_end_measure(id)
        if check_print("api", __method__)
            printf("[%d]:[%d]: applog strtask : TASK %s : end_measure(%d).\n",
                   ($system_time * 10 ** $log_conf["system_time"]).round,
                   @core.id, @id, id)
        end
    end

    private
    def check_print(obj, method_name)
        method_name.to_s =~ /print_log_/
        return $log_conf[obj][$']
    end
end
