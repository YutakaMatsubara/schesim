# -*- coding: utf-8 -*-
#
#= セマフォクラスの定義
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

require "./include/task"

class SEMAPHORE
    def initialize(num)
        @max = num              # セマフォ最大資源数
        @num = num              # セマフォの数
        @queue = []             # 待ちキュー
    end

    #
    #  セマフォの資源の獲得
    #
    #  セマフォを獲得する．セマフォの残り数が１以上の場合は，セマフォの
    #  残り数を１減らしてtrueを返す．そうでなければ，falseを返す．
    #
    def get_sem
        if 1 <= @num
            @num -= 1
            return true
        else
            return false
        end
    end

    #
    #  セマフォの資源の返却
    #
    #  セマフォを解放する．セマフォ待ちキューが空の場合は，セマフォの残
    #  り数を１増やす．セマフォの返却を待っているタスクがあれば，セマフォ
    #  の残り数は変更せずに，そのタスクを返す．
    #
    def rel_sem
        tsk = nil
        if @queue == []
            if @max < (@num + 1)
                p "E_QOVR"
                exit(1);
            end
            @num += 1
        else
            tsk = @queue.shift
        end
        return tsk
    end

    def push_queue(tsk)
        @queue.push(tsk)
    end
end
