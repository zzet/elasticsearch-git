class Repository
  include Elasticsearch::Git::Repository

  index_name 'elasticsearch-git-test'

  def repository_id
    1
  end
end
