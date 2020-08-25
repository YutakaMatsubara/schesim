# -*- coding: utf-8 -*-
#
#= リソースクラスの定義
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

class RESOURCE
    def initialize(ceilpri)
        @ceilpri = ceilpri      # リソースを獲得するタスクの最高優先度
        @prepri = nil           # リソース獲得前の優先度
        @prevres = nil          # リソース獲得前に獲得しているリソース
    end

    #
    #  リソースの獲得
    #
    #  このリソースを獲得する前の優先度と最後に獲得したリソースを保存し
    #  て，新しいタスクの優先度を返す．
    #
    def get_resource(prepri, lastres)
        @prepri = prepri
        @prevres = lastres
        return @ceilpri
    end

    #
    #  リソースの解放
    #
    def release_resource
        prepri = @prepri
        prevres = @prevres
        @prepri = nil
        @prevres = nil
        return [prepri, prevres]
    end
end
