# -*- coding: utf-8 -*-
#
#= タスク処理記述内のフック関数の定義
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
require "./include/semaphore"
require "./include/resource"
require "./include/event_flag"

class TASK
    #
    #  PreTaskHookの定義
    #
    private
    def pretask_hook
        print_log_pretaskhook_start
#        exc(1)
        print_log_pretaskhook_finished
    end

    #
    #  PostTaskHookの定義
    #
    private
    def posttask_hook
        print_log_posttaskhook_start
#        exc(1)
        print_log_posttaskhook_finished
    end
end

class APPLICATION
    #
    #  PreAppHookの定義
    #
    public
    def preapplication_hook
        print_log_preapplicationhook_start
#        @runtsk.exc(1)
        print_log_preapplicationhook_finished
    end

    #
    #  PostAppHookの定義
    #
    public
    def postapplication_hook
        print_log_postapplicationhook_start
#        @runtsk.exc(1)
        print_log_postapplicationhook_finished
    end
end
