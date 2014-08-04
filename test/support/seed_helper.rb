unless File.exists?(TEST_REPO_PATH)
  puts 'Prepare seeds'
  FileUtils.mkdir_p(SUPPORT_PATH)
  system(*%W(git clone --bare https://github.com/gitlabhq/testme.git), chdir: SUPPORT_PATH)
  system(*%W(git checkout 5937ac0a7beb003549fc5fd26fc247adbce4a52e), chdir: SUPPORT_PATH)
end
