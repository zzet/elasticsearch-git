require 'test_helper'

class CommitTest < TestCase
  def setup
    @commit = Elasticsearch::Git::CommitRepository.new(
      url: 'http://localhost:9200', log: true,
      repo: TEST_REPO_PATH, id: 1
    )
    @commit.create_index! force: true
  end

  def test_commit_index
    commit_count = @commit.index_range
    assert { commit_count == RepoInfo::COMMIT_COUNT }
    @commit.refresh_index!
    res = @commit.search('Initial')
    assert { res.count == 1 }
  end
end
