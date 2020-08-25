# -*- coding: utf-8 -*-
#
#= 統計情報測定区間の指定機能のサンプルプログラム
#
#Authors:: Yasumasa Sano (ERTL, Nagoya Univ.)
#Version:: 0.8.0
#License:: Apache License, Version 2.0
#
#== License:
#
#  Copyright 2011 - 2013 Yasumasa Sano
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
    def task1
        begin_measure(1)
        exc(3)
        end_measure(1)
    end

    def task2
        begin_measure(3)
        exc(4)
        begin_measure(2)
        exc(3)
        end_measure(2)
        end_measure(3)
    end
end
