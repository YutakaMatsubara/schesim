# -*- coding: utf-8 -*-
#
#= 共通モジュール・クラス
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

module FATAL_ERROR
    #
    #  致命的なエラーが発生したときの処理
    #
    def raise_fatal_exception(msg)
        STDERR.printf(msg)
        exit(1)
    end
end

#
#  順序付きハッシュ（簡易版）
#
class OrderedHash < Hash
    def initialize
        @keys = []
        super
    end
 
    def []=(key, value) 
        @keys << key unless member?(key)
        super
    end
 
    def each
        @keys.each {|key| yield key, self[key]}
    end
 
    def delete(key)
        @keys.delete key
        super
    end
end

#
#  浮動小数点値を指定した桁数で丸める
#
class Numeric
    def round_to(digit)
        num = self * (10 ** digit)
        num.round * (10 ** -digit)
    end
end
