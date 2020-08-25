# -*- coding: utf-8 -*-
#
#= イベントフラグクラスの定義
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

require "./include/task.rb"

class EVENT_FLAG
    def initialize()
        @flag = false           # イベントフラグ
        @queue = []             # 待ちキュー
    end
    
    def get_flag
        return @flag
    end
        
    #
    #  イベントのセット
    #
    def set_event
        @flag = true
        task_list = @queue;
        @queue = [];
        return task_list;
    end

    #
    #  イベントのクリア
    #
    def clear_event
        @flag = false
    end

    def push_queue(tsk)
        @queue.push(tsk)
    end
end
