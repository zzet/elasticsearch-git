require "rubygems"
require 'bundler/setup'
require 'pry'
require 'elasticsearch/git'

SUPPORT_PATH = File.join(File.expand_path(File.dirname(__FILE__)), '../support')
TEST_REPO_PATH = File.join(SUPPORT_PATH, 'testme.git')

require_relative 'support/repo_info'

Bundler.require

require 'wrong/adapters/minitest'

PROJECT_ROOT = File.join(Dir.pwd)

Wrong.config.color

Minitest.autorun

class TestCase < Minitest::Test
  include Wrong

  def fixtures_path
    @path ||= File.expand_path(File.join(__FILE__, "../fixtures"))
  end
end
