#! /usr/bin/env ruby
# -*- coding: utf-8 -*-
#
#= バージョン番号を更新するスクリプト
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

require "tempfile"
require "optparse"              # コマンドライン引数

$start_year = 2011              # 開発を始めた年

#
#  コマンドライン引数の処理
#
opt = OptionParser.new

# 対象のバージョン番号
opt.on('-v VAL') {|v|
    $target_version = v.to_s
    unless $target_version =~ /\d+\.\d+\.(\d|[a-e])+$/
        print "error : " + $target_version + " is invalid version number.\n"
        exit(1)
    end
}

# 対象ファイル
opt.on('-f VAL') {|v|
    $target_file = v.to_s
    if !File.file?($target_file)
        print "error : " + $target_file + " is not found.\n"
        exit(1)
    end
}

opt.parse!(ARGV)

printf("Version number of " + $target_file + " is updated to " + $target_version + "\n")

# ファイル開く

# 一行ずつ読み込んでバージョン番号を置換
tmp = Tempfile::new("tmp", "./")
open($target_file) { |f|
    f.each { |line|
        if /Version/ =~ line || /Release/ =~ line
            # 1.2.3aや3.4.5eなどのalpha版にも対応
            line.sub!(/\d+\.\d+\.(\d|[a-e])+$/, $target_version)
        elsif /Copyright/ =~ line
            # YYYY - XXXX のXXXXを現在年に置き換える
            line.sub!(/\d+\s-\s\d+/, $start_year.to_s + " - " + Time.now.year.to_s)
        end
        tmp.puts(line)
    }
}
tmp.close

# 元のファイルに書込み
tmp.open
open($target_file, "w") { |f| 
    tmp.each { |line| 
        f.puts(line)
    }
}
tmp.close    

