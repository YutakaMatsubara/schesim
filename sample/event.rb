# -*- coding: utf-8 -*-
#
#= リソースとイベント機能のサンプルプログラム
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
    @@res1 = RESOURCE.new(1)  
    @@evt1 = EVENT_FLAG.new()
    @@mode2 = 2
    # タスクIDが1のタスク処理記述
    def task1
        GetResource(@@res1)
        exc(1)
        ReleaseResource(@@res1)
        exc(1)
    end
    # タスクIDが2のタスク処理記述
    def task2
        exc(1)
        GetResource(@@res1)
        exc(2)
        ReleaseResource(@@res1)
        exc(1)
    end
    # タスクIDが3のタスク処理記述
    def task3
        exc(1)
    end
    # タスクIDが4のタスク処理記述
    def task4
        while (1) 
            WaitEvent(@@evt1)
            ClearEvent(@@evt1)
            exc(2)
        end
    end
    # タスクIDが5のタスク処理記述
    def task5
        case @@mode2
        when 1
            exc(1)
        when 2
            SetEvent(@@evt1)
            exc(1)
        end
    end     
    # タスクIDが6のタスク処理記述
    def task6
        exc(1)
    end
end
