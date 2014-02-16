# Elasticsearch::Git

Attention: Pre-pre-pre beta code. Not production.

[Elasticsearch](https://github.com/elasticsearch/elasticsearch-rails/tree/master/elasticsearch-model) integrations for git repositories

## Installation

Add this line to your application's Gemfile:

``` ruby
gem 'elasticsearch-git'
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

  set_repository_id       project.id
  repository_for_indexing '/path/to/your/repo'

end

Repository.__elasticsearch__.create_index! force: true

repo = Repository.new
repo.index_commits
repo.index_blobs

Repository.search("query", type: 'blob')
Repository.search("query", type: 'commit')

# Search in all types
Repository.search("query")
```

## Contributing

1. Fork it ( http://github.com/[my-github-username]/elasticsearch-git/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
