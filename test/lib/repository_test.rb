require 'test_helper'


class RepositoryTest < TestCase
  def setup
    @repository = Repository.new
    @repository.repository_for_indexing(TEST_REPO_PATH)
  end

  def test_index_commits
    commit_count = @repository.index_commits
    assert { commit_count == RepoInfo::COMMIT_COUNT }
  end

  def test_index_all_blobs_from_head
    blob_count = @repository.index_blobs
    result = @repository.search('def project_name_regex')
    assert { result[:blobs][:total_count]  == 1 }
  end
end
