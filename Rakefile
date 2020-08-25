# -*- coding: utf-8 -*-
#
#= スケジューリングシミュレータのRakefile
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
#=== シミュレータのソースコードからrdocドキュメントを生成する
# # ./rake rdoc
#

require 'rake/clean'
require 'rake/rdoctask'

TEXT_SRCS = FileList["./README"] # テキストファイルの場所
SIM_SRCS = FileList["./*.rb","include/*.rb","labs/bss.rb","labs/tpa.rb"] # シミュレータのソースコード
UTIL_SRCS = FileList["utils/*.rb","utils/*.sh"] # ユーティリティ用ソースコード
TEST_SRCS = FileList["test/*.rb"] # テスト用ソースコード
SAMPLE_SRCS = FileList["sample/*.rb"] # サンプルソースコード

RAKE_SRCS = FileList["./Rakefile"] # Rakefileの場所

ALL_SRCS = TEXT_SRCS + SIM_SRCS + UTIL_SRCS + TEST_SRCS + SAMPLE_SRCS + RAKE_SRCS

OLD_LOG = FileList["test/*.log"]   # テストで出力したログファイル
OLD_DIFF = FileList["test/*.diff"] # テストで出力したdiffファイル
OLD_XLS = FileList["test/*.xls"] # テストで出力したxlsファイル
OLD_CSV = FileList["test/*.csv"] # テストで出力したcsvファイル
OLD_RES = FileList["test/*.res"] # テストで出力したresファイル
OLD_COV = FileList["coverage/*"] # rcov取得で出力したカバレッジ情報ファイル

HOME_DIR = File::expand_path('.')
SAMPLE_DIR = HOME_DIR + "/sample/"
TEST_DIR = HOME_DIR + "/test/"
EXC = TEST_DIR + "exc.rb"
COMPARE = TEST_DIR + "compare.rb"

SVNCO = "svn co https://www.nces.is.nagoya-u.ac.jp/svn/schesim/tags/"
SVNCP = "svn copy https://www.nces.is.nagoya-u.ac.jp/svn/schesim/trunk/ https://www.nces.is.nagoya-u.ac.jp/svn/schesim/tags/"

#
#  ドキュメント（rdoc）の生成
#
Rake::RDocTask.new do |rdoc|
    rdoc.rdoc_dir = "doc/rdoc"
    rdoc.title = "An Open-source Flexible Real-time Scheduling Simulator <schesim>"
    rdoc.rdoc_files = SIM_SRCS
    rdoc.options << '-c utf8' << '-d' << '--fileboxes' << '--line-numbers' << '--inline-source' << '-All'
end

#
#  テストの実行
#
desc "Start schesim test"
task:test, "version", "exc_time", "reuse"

task:test do |x, args|
    version = args.version
    exc_time = args.exc_time
    reuse = args.reuse

    if version == nil
        print "test error : Specify target version like \'rake test[ version, exec_time, on/off ]\'\n"
        exit(1)
    end

    # 指定したバージョンのソースがなければダウンロードする．
    target = "schesim-" + version
    if !File.directory?(target) 
        sh "#{SVNCO}" + version + " " + target
    end

    if !File.directory?(target) 
        print "test error : " + target + " is not found.\n"
        exit(1)
    end

    #
    # シミュレーションを実行する．
    #

    # 比較対象
    cd target do
        if reuse != "on"
            sh "#{EXC}" + " -v " + version + " -s " + "#{SAMPLE_DIR}" + " -d " + "#{TEST_DIR}" + " -e " + exc_time
        end
    end

    # 最新バージョン
    sh "#{EXC}" + " -v current" + " -s " + "#{SAMPLE_DIR}" + " -d " + "#{TEST_DIR}" + " -e " + exc_time

    #
    # ログと統計情報を比較する．	 
    #
    sh "#{COMPARE}" + " -i " + version + " -t current" + " -s " + "#{SAMPLE_DIR}"+ " -d " + "#{TEST_DIR}"
end

#
#  リリース（バージョン番号更新）
#
desc "Start release schesim"
task:release,"version"

task:release do |x, args|
    version = args.version

    if version == nil
        print "error : Specify version number e.g. \'rake release[\"0.7.2\"]\'\n"
        exit(1)
    end

    #
    #  すべてのソースコード中のバージョン表示を更新
    #
    ALL_SRCS.each { |src|
        print src, "\n"
        sh "utils/version.rb" + " -v " + version + " -f " + src
    }
end

#
#  C0カバレッジの取得（バージョン0.8.0以降では使用できない）
#
desc "Generating coverage information of schesim"
task:cov, "exc_time"
task:cov do |x, args|
    exc_time = args.exc_time

    if exc_time == nil
        print "error : Specify execution time e.g. \'rake cov[1000]\'\n"
        exit(1)
    end

    #
    # カバレッジ取得を有効にしてシミュレーションを実行する．
    #
    sh "#{EXC}" + " -c " + " -v current" + " -s " + "#{SAMPLE_DIR}" + " -d " + "#{TEST_DIR}" + " -e " + exc_time

    #
    # すべてのカバレッジ情報をまとめる
    #
    sh "rcov --aggregate ./coverage/schesim.info --sort coverage"
end

# テストで出力したファイルを削除する
CLEAN.include(OLD_LOG)
CLEAN.include(OLD_CSV)
CLEAN.include(OLD_DIFF)
CLEAN.include(OLD_XLS)
CLEAN.include(OLD_RES)
CLEAN.include(OLD_COV)
