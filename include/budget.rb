# -*- coding: utf-8 -*-
#
#= バジェットリストクラスの定義
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

class BUDGET_LIST
    def initialize(share)
        @budget_table = []
        @share = share
    end

    #
    #  バジェットの探索
    #
    #  指定されたバジェット有効時刻に一致するバジェット要素が，バジェッ
    #  トのリストに存在する場合には，そのバジェット要素の残りバジェット
    #  の値を返す．存在しない場合には，nilを返す．
    #
    def search_budget(d)
        if @budget_table.empty?
            return nil
        end
        @budget_table.each do |bgt|
            if d == bgt.d
                return bgt.b
            end
        end
        return nil
    end

    #
    #  バジェットの追加
    #
    #  指定されたバジェット有効時刻までに利用可能なバジェットを計算して，
    #  新しいバジェット要素をバジェットリストに追加し，バジェットの値を
    #  返す．なお，指定されたバジェット有効時刻に一致するバジェット要素
    #  は，バジェットリスト中に存在しない状況で呼び出されることを前提と
    #  する．
    #
    def add_budget(old_d,d)
        index = 0
        @budget_table.each do |bgt|
            if d > bgt.d
                index += 1
            elsif d == bgt.d
                raise "assert: found an duplicate element."
            else
                break
            end
        end

        # index の位置に挿入する
        prv = @budget_table[index-1] # 挿入位置の前の要素
        nxt = @budget_table[index]   # 挿入位置の後の要素
        
        if index == 0
            prv = nil
        end
        if index == @budget_table.size
            nxt = nil
        end

        # バジェットの計算
        if prv == nil && nxt == nil
            # 挿入位置の前後に要素がない場合
            b = (d - $system_time) * @share
        elsif prv != nil && nxt == nil
            #
            #  挿入位置の前にのみ要素が存在する場合
            if old_d != nil && old_d < d
                # 絶対デッドラインが延びた場合
                b = prv.b + (d - prv.d) * @share
            else # ここにくることはなさそう
                # 絶対デッドラインが早くなった場合
                b = [prv.b + (d - prv.d) * @share, (d - $system_time) * @share].min
            end
        elsif prv == nil && nxt != nil
            # 挿入位置の後ろにのみ要素が存在する場合
            b = [(d - $system_time) * @share, nxt.b].min
        else
            # 挿入位置の前後に要素が存在する場合
            if old_d != nil && old_d < d
                #  デッドラインが延長した場合
                b = [prv.b + (d - prv.d) * @share, nxt.b].min
            else
                #  デッドラインが早くなった場合
                b = [prv.b + (d - prv.d) * @share, (d - $system_time) * @share, nxt.b].min
            end
        end
        
        # バジェットリストの index の位置に，新しいバジェット要素を挿入する
        @budget_table[index,0] = BUDGET_ELEMENT.new(d,b)
        @budget_table.sort!{|a,c| a.d <=> c.d}
        
        return b
    end
    
    #
    #  バジェットリストの更新
    #
    #  デッドラインがd以降であるバジェット要素の残りバジェットをbだけ減
    #  らす．バジェットを減らした結果，負の値になる場合には，残りバジェッ
    #  トを0とする．
    #
    def update_budgetlist(d,b)
        if @budget_table.empty?
            raise "assert"
        end
        current_b = search_budget(d)
        tmp_budget_table = @budget_table
        @budget_table = []
        tmp_budget_table.each do |bgt|
            if bgt.d < d && bgt.b > current_b
                # バジェット要素の削除条件(3)を満たす場合
                # budget_tableに追加せず，削除する
            else
                if d <= bgt.d
                    bgt.b = [(bgt.b - b).round_to($log_conf["system_time"]), 0].max
                end
                @budget_table.push(bgt)
            end
        end
    end

    #
    #  バジェットリストの管理
    #
    #  バジェットリストから，以下の条件を満たすバジェット要素は，バジェッ
    #  ト計算で使用されないので，削除できる．効率的に不要なバジェットを
    #  削除するため，この関数では，(1)のみ対応し，(3)はバジェットリスト
    #  更新時に行う．(2)は，バジェットリストに対応するタスクを特定する
    #  必要があるため，現時点では未実装である．
    #
    #  (1) バジェットのデッドラインが，システム時刻より古い
    #  (2) 対象タスクの実行が終了しており，残りバジェットが，現在時刻か
    #      らのシェア分を越えている
    #  (3) デッドラインが現在のアプリケーションデッドラインより早く，そ
    #      の残りバジェットが現在のアプリケーションデッドラインに対応す
    #      るバジェット要素より多い
    #
    def maintenance_budgetlist(share)
        if !(@budget_table.empty?)
            tmp_budget_table = @budget_table
            @budget_table = []
            tmp_budget_table.each do |bgt|
                # 条件(1)に当てはまらない場合には残す
                if 0 <= bgt.d - $system_time
                    @budget_table.push(bgt)
                end
            end
        end
    end

    def print_budgetlist
        printf("-[%d]-\n", $system_time)
        @budget_table.each do |bgt|
            printf("(%f,%f)\n", bgt.d, bgt.b)
        end
        printf("-----\n")
    end

    #
    #  バジェットリストの探索
    #
    #  指定されたデッドラインの要素のバジェットが0の場合はtrue
    #  そうでない場合はfalseを返す
    #
    def judge_budget_zero(d)
        if @budget_table.empty?
            return false
        end
        @budget_table.each do |bgt|
            if bgt.d == d && bgt.b == 0
                return true
            end
        end
        return false
    end
end

#
#  バジェット要素のクラス
#
class BUDGET_ELEMENT
    def initialize(d,b)
        @d = d
        @b = b
    end
    attr_accessor :d, :b
end
