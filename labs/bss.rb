# -*- coding: utf-8 -*-
#
#= アプリケーションの定義（BSSアルゴリズム）
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

require "./include/task.rb"
require "./include/application.rb"

class BSS_TASK < TASK
    public
    def make_runnable
        super
        @app.update_deadline
        @app.replenish_budget
        @app.budget_list.print_budgetlist if $DEBUG
    end
    
    public
    def make_non_runnable
        super
        @app.update_deadline
        @app.replenish_budget
        @app.budget_list.print_budgetlist if $DEBUG
    end
end

class BSS_APPLICATION < APPLICATION
    def initialize(app_id,core,share,scheduling,pri)
        super(app_id,core,share,scheduling,pri)
        @budget_list = BUDGET_LIST.new(@share)
        @D = nil
        @old_D = 0        # 更新前のアプリケーションの絶対デッドライン
    end

    #
    #  アプリケーションの絶対デッドラインの更新
    #  
    #  実行可能タスクの絶対デッドラインの中で最も早い絶対デッドラインを，
    #  アプリケーションの絶対デッドラインとする．実行可能タスクがなく，
    #  デッドラインキューが空の場合には，アプリケーションの絶対デッドラ
    #  インはnilとする．
    #
    public
    def update_deadline
        @old_D = @D
        if @deadline_queue.empty?
            @D = nil
        else
            # ソートされていない場合があるので，ここで早い順にソートする．
            @deadline_queue.sort!{|a,b| a.D[0] <=> b.D[0]}
            @D = @deadline_queue[0].D[0]
        end
    end

    #
    #  バジェットの消費
    # 
    #  タスクを実行後に，アプリケーションデッドラインが更新されている状
    #  態，もしくは実行可能なタスクがなくなった状態で呼び出される．
    #
    public
    def reduce_budget(b)
        super(b)
        if @D != nil
            @budget_list.update_budgetlist(@D,b)
        else
            raise "assert"
        end 
        @budget_list.maintenance_budgetlist(@share)
    end

    # バジェットの補充
    public
    def replenish_budget
        if @D == nil
            @budget = 0
        else
            @budget_list.maintenance_budgetlist(@share)
            b = @budget_list.search_budget(@D)
            if b != nil
                @budget = b
            else
                @budget = @budget_list.add_budget(@old_D,@D)
            end
        end
        print_log_budget
    end

    #
    #  アプリケーションを満了状態に遷移
    #
    #  デッドラインをミスすることが確定しているタスクのデッドラインを，
    #  タスクの相対デッドライン分だけ伸ばし，実行に必要なバジェットを補
    #  充できるようにする．デッドラインをミスするタスクとは，バジェット
    #  が0，かつ実行可能状態，かつ絶対デッドラインがアプリケーションの
    #  デッドラインと一致するタスクである．
    #
    public
    def make_application_expired       
        super
        #  バジェットの延長機構
=begin
        if @schedtsk != nil
            while @budget == 0
                @tsk_table.each do |tsk|
                    # 延長してもバジェットが無い場合，バジェットが0より
                    # 大きくなるまで繰り返す．
                    while tsk.D[0] == @D && tsk.ts == "RUNNABLE" && @budget_list.judge_budget_zero(tsk.D[0])
                        tsk.D[0] += tsk.d
                        update_deadline
                        replenish_budget
                        @budget_list.print_budgetlist if $DEBUG
                    end
                end
            end
        end
=end
    end
    attr_accessor :budget_list
end
