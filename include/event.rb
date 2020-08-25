# -*- coding: utf-8 -*-
#
#= イベントリストクラスの定義
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

class EVENT_LIST
    def initialize()
        @event_queue = []
    end

    def add_event(time,inst,args)
        @event_queue.push(EVENT.new(time,inst,args))
        @event_queue.sort!{|a,b| a.time <=> b.time}
    end

    def check_event
        event = []
        tmp_queue = @event_queue
        @event_queue = []
        tmp_queue.each do |evt|
            if evt.check_time
                event << evt
            else
                @event_queue << evt
            end
        end
        return event
    end

    def get_next_event_time
        if @event_queue.empty?
            next_event = 1.0/0.0 # 無限大
        else
            next_event = @event_queue[0].time
        end
        return next_event
    end

    def print_event_list
        @event_queue.each do |evt|
            evt.print_event
        end
    end

    attr_accessor :event_queue
end

#
#  イベントクラスの定義
#
class EVENT
    def initialize(time, inst, args)
        @time = time            # イベントが発生する絶対時刻
        @inst = inst            # 命令
        @args = args            # 命令に渡す引数
    end

    def check_time
        if @time <= $system_time
            return true
        else
            return false
        end
    end

    def print_event
        printf("time = %f, inst = %s, args = %s\n", @time, @inst, @args.id)
    end
    attr_accessor :time,:inst,:args
end
