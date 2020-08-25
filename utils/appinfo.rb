#! /usr/bin/env ruby
# -*- coding: utf-8 -*-
#
#= アプリケーション情報の取得プログラム
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
#== Usage:
#
#=== デフォルト（./apps にあるjsonのアプリケーション情報を取得する）
# # ./appinfo.rb
#=== アプリケーションファイルの指定
# # ./appinfo.rb -t ./apps/hoge.json
#=== アプリケーションファイルの入力先ディレクトリの指定
# # ./appinfo.rb -d ./apps
#

require "rubygems"
require "json"                  # JSON
require "optparse"              # コマンドライン引数

require "include/task"

# アプリケーションのデフォルトディレクトリ名
$apps_dir = './apps/'

# コマンドライン引数の処理

opt = OptionParser.new

# アプリケーションファイルの指定
opt.on('-t VAL') {|v| 
    $file = v.to_s
}

# アプリケーションファイルのディレクトリの指定
opt.on('-d VAL') {|v| 
    $apps_dir = v.to_s
}

opt.parse!(ARGV)

class ANALYZER
    def initialize
        @app_table = []
        @u = 0
        @n = 0
    end

    # ファイル名の取得
    def get_application_file
        Dir.glob($apps_dir + "\*.json").each {|file|
            read_application(file)
        }
    end

    # アプリケーションの読み込み
    def read_application(file)
        u = 0               # アプリケーションのCPU利用率
        n = 0               # タスク数
        json = ""
        application_file = File.expand_path(file)
        File.open(File.expand_path(application_file), "r") do |file|
            while line = file.gets
                json += line
            end
        end
        res = (JSON.parser.new(json)).parse()
        res["cpu"].each do |cpu|
            cpu["core"].each do |core|
                core["application"].each do |app|
                    app["task"].each do |tsk|
                        u += tsk["wcet"].quo(tsk["period"])
                        n += 1
                    end
                    @app_table << [n,u]
                end
            end
        end
    end

    # 
    def output_appinfo
        @app_table.each do |app|
            @n += app[0]
            @u += app[1]
        end
        @n = @n.quo(@app_table.size)
        @u = @u.quo(@app_table.size)
        printf("----------\n")
        printf("# of apps: %d\n", @app_table.size)
        printf("av. of # of tasks: %f\n", @n)
        printf("av. of CPU utilization: %f\n", @u)
        printf("----------\n")
    end

    # 
    #  メインルーチン
    #
    def start
        if $file == nil
            get_application_file
        else
            read_application($file)
        end
        output_appinfo
    end
end

ana = ANALYZER.new
ana.start()
