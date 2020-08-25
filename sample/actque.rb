# -*- coding: utf-8 -*-
#
#= 起動要求キューイングのサンプルプログラム
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
    @@mode = 1
    # タスクIDが1のタスク処理記述
    def task1
        exc(4)
    end
    # タスクIDが2のタスク処理記述
    def task2
        exc(4)
    end
    # タスクIDが3のタスク処理記述
    def task3
        case @@mode
        when 1
            exc(3)
            @@mode = 2
        when 2
            exc(1)
            @@mode = 1
        end
    end
end
