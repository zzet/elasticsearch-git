class Repository
  include Elasticsearch::Git::Repository

  def repository_id
    1
  end
end
