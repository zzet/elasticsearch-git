require 'test_helper'


class RepositoryTest < TestCase
  def setup
    @repository = Repository.new
    @repository.repository_for_indexing(TEST_REPO_PATH)
    Repository.__elasticsearch__.create_index! force: true
  end

  def test_index_commits
    commit_count = @repository.index_commits
    assert { commit_count == RepoInfo::COMMIT_COUNT }
  end

  def test_index_commits_after_first_push
    commit_count = @repository.index_commits(
        from_rev: "0000000000000000000000000000000000000000",
        to_rev: @repository.repository_for_indexing.head.target.oid)

    assert { commit_count == RepoInfo::COMMIT_COUNT }
  end

  #TODO write better assertions
  def test_index_all_blobs_from_head
    blob_count = @repository.index_blobs
    Repository.__elasticsearch__.refresh_index!

    result = @repository.search('def project_name_regex')
    assert { result[:blobs][:total_count]  == 1 }
  end

  #TODO write better assertions
  def test_index_blobs_after_first_push
    commit_count = @repository.index_blobs(
        from_rev: "0000000000000000000000000000000000000000",
        to_rev: @repository.repository_for_indexing.head.target.oid)
    Repository.__elasticsearch__.refresh_index!

    result = @repository.search('def project_name_regex')
    assert { result[:blobs][:total_count]  == 1 }
  end
end
