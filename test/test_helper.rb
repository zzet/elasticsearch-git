require "rubygems"
require 'bundler/setup'
require 'pry'

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
