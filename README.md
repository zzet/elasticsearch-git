# Elasticsearch::Git

[Elasticsearch](https://github.com/elasticsearch/elasticsearch-rails/tree/master/elasticsearch-model) integrations for git repositories.

## NOTE

Now indexing text-like documents mo nore 1 mb size

## Installation

Add this line to your application's Gemfile:

``` ruby
gem 'elasticsearch-git', '~> 0.0.4'

# or

gem 'elasticsearch-git', github: 'zzet/elasticsearch-git', ref: 'last_ref'
```

And then execute:

``` bash
$ bundle
```

Or install it yourself as:

``` bash
$ gem install elasticsearch-git
```

## Usage

``` ruby
class Repository
  include Elasticsearch::Git::Repository

  def repository_id
    project.id
  end

  repository_for_indexing '/path/to/your/repo'
end

Repository.__elasticsearch__.create_index! force: true

repo = Repository.new
repo.index_commits
repo.index_blobs

repo.index_commits(from_rev: "1802bafa70d3b1678cfa46a482fd396dd8a4bd40", to_rev: "8d4175e9f4a36065b52fa752c1fd3594c82c0f28")
repo.index_blobs(from_rev: "1802bafa70d3b1678cfa46a482fd396dd8a4bd40", to_rev: "8d4175e9f4a36065b52fa752c1fd3594c82c0f28")

Repository.search("query", type: 'blob')
Repository.search("query", type: 'commit')

# Search in all types
Repository.search("query")
```

## Integration with Gitlab

[Sample](https://github.com/zzet/gitlabhq/tree/master/app/elastic)

``` ruby
# app/elastic/repositories_search.rb
module RepositoriesSearch
  extend ActiveSupport::Concern

  included do
    include Elasticsearch::Git::Repository

    def repository_id
      project.id
    end
  end

  module ClassMethods
    def import
      Repository.__elasticsearch__.create_index! force: true

      Project.find_each do |project|
        if project.repository.exists? && !project.repository.empty?
          project.repository.index_commits
          project.repository.index_blobs
        end
      end
    end
  end
end

# app/models/repository.rb
class Repository
  include RepositoriesSearch
  #...
  def project
    @project ||= Project.find_with_namespace(@path_with_namespace)
  end
  #...
end

Repository.import # for indexing all repositories

Repository.__elasticsearch__.create_index! force: true
Project.last.repository.index_commits
Project.last.repository.index_blobs

Repository.search("some_query")
# => {blobs: [{}, {}, {}], commits: [{}, {}, {}]}

Repository.search("some_query", type: :blob)
# => {blobs: [{}, {}, {}], commits: []}

Repository.search("some_query", type: :commit)
# => {blobs: [], commits: [{}, {}, {}]}

Repository.search("some_query", type: :commit, page: 2, per: 50)
# => ...

Repository.search("some_query", options: { repository_id: Project.last.id })
# => {blobs: [{}, {}, {}], commits: [{}, {}, {}]}

Repository.search("some_query", options: { repository_id: current_user.authorized_projects.ids })
# => {blobs: [{}, {}, {}], commits: [{}, {}, {}]}

Project.last.repository.search("Copyright")[:blobs].first
=> #<Elasticsearch::Model::Response::Result:0xbb84b3fc
 @result=
  {"_index"=>"repository-index-development",
   "_type"=>"repository",
   "_id"=>"4328_LICENSE.txt",
   "_score"=>0.034848917,
   "_source"=>
    {"blob"=>
      {"type"=>"blob",
       "oid"=>"f99909cd4ecb6f2ad08f8e55aac3a9fcd86a2bd2",
       "rid"=>4328,
       "content"=>
        "Copyright (c) 2014 Andrey Kumanyaev\n\nMIT
License\n\nPermission is hereby granted, free of charge, to any person
obtaining\na copy of this software and associated documentation files
(the\n\"Software\"), to deal in the Software without restriction,
including\nwithout limitation the rights to use, copy, modify, merge,
publish,\ndistribute, sublicense, and/or sell copies of the Software,
and to\npermit persons to whom the Software is furnished to do so,
subject to\nthe following conditions:\n\nThe above copyright notice and
this permission notice shall be\nincluded in all copies or substantial
portions of the Software.\n\nTHE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT
WARRANTY OF ANY KIND,\nEXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
THE WARRANTIES OF\nMERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE
AND\nNONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
BE\nLIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION\nOF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION\nWITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.\n",
       "commit_sha"=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28"}}}>
```

## Examples

After integration this gem into [Gitlab](https://github.com/gitlabhq/gitlabhq)

``` ruby
Repository.search("too")[:commits].first
=> #<Elasticsearch::Model::Response::Result:0xbb50dfdc
 @result=
  {"_index"=>"repository-index-development",
   "_type"=>"repository",
   "_id"=>"4328_1802bafa70d3b1678cfa46a482fd396dd8a4bd40",
   "_score"=>0.15873253,
   "_source"=>
    {"commit"=>
      {"type"=>"commit",
       "rid"=>4328,
       "sha"=>"1802bafa70d3b1678cfa46a482fd396dd8a4bd40",
       "author"=>
        {"name"=>"Andrey Kumanyaev",
         "email"=>"me@zzet.org",
         "time"=>"2014-02-16T02:24:23+04:00"},
       "committer"=>
        {"name"=>"Andrey Kumanyaev",
         "email"=>"me@zzet.org",
         "time"=>"2014-02-16T02:24:23+04:00"},
       "message"=>"Save 2. Indexing work. Search too\n"}}}>


Project.last.repository.as_indexed_json
  Project Load (1.7ms)  SELECT "projects".* FROM "projects" ORDER BY "projects"."id" DESC LIMIT 1
  Namespace Load (4.8ms)  SELECT "namespaces".* FROM "namespaces" WHERE "namespaces"."id" = $1 ORDER BY "namespaces"."id" ASC LIMIT 1  [["id", 3739]]
  Namespace Load (0.9ms)  SELECT "namespaces".* FROM "namespaces" WHERE "namespaces"."path" = 'zzet' LIMIT 1
  Project Load (0.7ms)  SELECT "projects".* FROM "projects" WHERE "projects"."namespace_id" = 3739 AND "projects"."path" = 'elasticsearch-git' LIMIT 1
# Long lines are stripped manually
=> {:blobs=>
  [[{:type=>"blob",
     :id=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28_.gitignore",
     :rid=>4328,
     :oid=>"d87d4be66f458acd52878902bbf1391732ad21e1",
     :content=>
      "*.gem\n*.rbc\n.bundle\n.config\n.yardoc\nGemfile.lock\nInstalledFiles\n_yardoc\ncoverage\ndoc/\nlib/bundler/man\npkg\nrdoc\nspec/reports\ntest/tmp\ntest/version_tmp\ntmp\n",
     :commit_sha=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28"},
    {:type=>"blob",
     :id=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28_Gemfile",
     :rid=>4328,
     :oid=>"7322405f8f3ee5de24f7a727940ac52543e8954c",
     :content=>
      "source 'https://rubygems.org'\n\n# Specify your gem's dependencies in elasticsearch-git.gemspec\ngemspec\n\ngem 'elasticsearch-model', github: 'elasticsearch/elasticsearch-rails'\ngem 'elasticsearc....."
     :commit_sha=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28"},
    {:type=>"blob",
     :id=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28_LICENSE.txt",
     :rid=>4328,
     :oid=>"f99909cd4ecb6f2ad08f8e55aac3a9fcd86a2bd2",
     :content=>
      "Copyright (c) 2014 Andrey Kumanyaev\n\nMIT License\n\nPermission is hereby granted, free of charge, to any person obtaining\na copy of this software and associated documentation files (the\n\"Softw...."
     :commit_sha=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28"},
    {:type=>"blob",
     :id=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28_README.md",
     :rid=>4328,
     :oid=>"8258d574dfc8040a5d003f06c6493e0033527f36",
     :content=>
      "# Elasticsearch::Git\n\nAttention: Pre-pre-pre beta code. Not production.\n\n[Elasticsearch](https://github.com/elasticsearch/elasticsearch-rails/tree/master/elasticsearch-model) integrations for g...."
     :commit_sha=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28"},
    {:type=>"blob",
     :id=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28_Rakefile",
     :rid=>4328,
     :oid=>"29955274e0d42e164337c411ad9144e8ffd7e46e",
     :content=>"require \"bundler/gem_tasks\"\n",
     :commit_sha=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28"},
    {:type=>"blob",
     :id=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28_elasticsearch-git.gemspec",
     :rid=>4328,
     :oid=>"67762437568dda1bb98ec5eca8be7e4a5c8115a9",
     :content=>
      "# coding: utf-8\nlib = File.expand_path('../lib', __FILE__)\n$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)\nrequire 'elasticsearch/git/version'\n\nGem::Specification.new do |spec|\n  spec..."
     :commit_sha=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28"},
    {:type=>"blob",
     :id=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28_elasticsearch/git.rb",
     :rid=>4328,
     :oid=>"d3817ec58af1f44dfd18856bf54ef2bf607901a8",
     :content=>
      "require \"elasticsearch/git/version\"\nrequire \"elasticsearch/git/model\"\nrequire \"elasticsearch/git/commit\"\n\nmodule Elasticsearch\n  module Git\n    class Test\n      include Elasticsearch::..."
     :commit_sha=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28"},
    {:type=>"blob",
     :id=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28_git/model.rb",
     :rid=>4328,
     :oid=>"3dfbae747f25391779fbe012fe8cc4f38cc4651c",
     :content=>
      "require 'active_support/concern'\nrequire 'active_model'\nrequire 'elasticsearch/model'\n\nmodule Elasticsearch\n  module Git\n    module Model\n      extend ActiveSupport::Concern\n\n      include..."
     :commit_sha=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28"},
    {:type=>"blob",
     :id=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28_git/repository.rb",
     :rid=>4328,
     :oid=>"70fe59c8391f6c27adb79c3e45824e6b4cf9566c",
     :content=>
      "require 'active_support/concern'\nrequire 'active_model'\nrequire 'elasticsearch'\nrequire 'elasticsearch/model'\nrequire 'rugged'\nrequire 'gitlab_git'\n\nmodule Elasticsearch\n  module Git\n    m..."
     :commit_sha=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28"},
    {:type=>"blob",
     :id=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28_git/version.rb",
     :rid=>4328,
     :oid=>"79e8082b122492464732f1fb43e9f2bdc96ea146",
     :content=>
      "module Elasticsearch\n  module Git\n    VERSION = \"0.0.1\"\n  end\nend\n",
     :commit_sha=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28"},
    {:type=>"blob",
     :id=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28_test/test_helper.rb",
     :rid=>4328,
     :oid=>"6acc0d2b7bf0f286557d3757c1140b41ab57e8f7",
     :content=>
      "require \"rubygems\"\nrequire 'bundler/setup'\nrequire 'pry'\n\nBundler.require\n\nrequire 'wrong/adapters/minitest'\n\nPROJECT_ROOT = File.join(Dir.pwd)\n\nWrong.config.color\n\nMinitest.autorun\n..."
     :commit_sha=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28"}]],
 :commits=>
  [{:type=>"commit",
    :sha=>"8d4175e9f4a36065b52fa752c1fd3594c82c0f28",
    :author=>
     {:name=>"Andrey Kumanyaev",
      :email=>"me@zzet.org",
      :time=>2014-02-16 13:50:32 +0400},
    :committer=>
     {:name=>"Andrey Kumanyaev",
      :email=>"me@zzet.org",
      :time=>2014-02-16 13:50:32 +0400},
    :message=>"Improve readme\n"},
   {:type=>"commit",
    :sha=>"37f1b0710eb7f41254ae0c33db09794a25bbb246",
    :author=>
     {:name=>"Andrey Kumanyaev",
      :email=>"me@zzet.org",
      :time=>2014-02-16 13:49:25 +0400},
    :committer=>
     {:name=>"Andrey Kumanyaev",
      :email=>"me@zzet.org",
      :time=>2014-02-16 13:49:25 +0400},
    :message=>"prepare first test release\n"},
   {:type=>"commit",
    :sha=>"1802bafa70d3b1678cfa46a482fd396dd8a4bd40",
    :author=>
     {:name=>"Andrey Kumanyaev",
      :email=>"me@zzet.org",
      :time=>2014-02-16 02:24:23 +0400},
    :committer=>
     {:name=>"Andrey Kumanyaev",
      :email=>"me@zzet.org",
      :time=>2014-02-16 02:24:23 +0400},
    :message=>"Save 2. Indexing work. Search too\n"},
   {:type=>"commit",
    :sha=>"3ed383bfbf6cba611d191dbc3590779c0444b7f0",
    :author=>
     {:name=>"Andrey Kumanyaev",
      :email=>"me@zzet.org",
      :time=>2014-02-16 00:23:10 +0400},
    :committer=>
     {:name=>"Andrey Kumanyaev",
      :email=>"me@zzet.org",
      :time=>2014-02-16 00:23:10 +0400},
    :message=>"Save commit\n"},
   {:type=>"commit",
    :sha=>"7021addf520a19bdeceef29947c8687965c132ff",
    :author=>
     {:name=>"Andrey Kumanyaev",
      :email=>"me@zzet.org",
      :time=>2014-02-15 14:28:43 +0400},
    :committer=>
     {:name=>"Andrey Kumanyaev",
      :email=>"me@zzet.org",
      :time=>2014-02-15 14:28:43 +0400},
    :message=>"first commit\n"}]}
```

## TODO

    * Add Exceptions handlers for indexing (Error connections and timeouts)

## Contributing

1. Fork it ( http://github.com/[my-github-username]/elasticsearch-git/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
