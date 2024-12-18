require "rake/clean"

CLEAN.include ["by-*.gem", "rdoc", "coverage"]

desc "Build by gem"
task :package=>[:clean] do |p|
  sh %{#{FileUtils::RUBY} -S gem build by.gemspec}
end

### Specs

desc "Run tests"
task :test do
  sh "#{FileUtils::RUBY} #{"-w" if RUBY_VERSION >= '3'} #{'-W:strict_unused_block' if RUBY_VERSION >= '3.4'} test/by_test.rb"
end

task :default => :test

desc "Run tests with coverage"
task :test_cov do
  FileUtils::rm_r('coverage') if File.directory?('coverage')
  ENV['COVERAGE'] = '1'
  sh "#{FileUtils::RUBY} test/by_test.rb"
end

### RDoc

require "rdoc/task"

RDoc::Task.new do |rdoc|
  rdoc.rdoc_dir = "rdoc"
  rdoc.options += ["--quiet", "--line-numbers", "--inline-source", '--title', 'by: Ruby library preloader', '--main', 'README.rdoc']

  begin
    gem 'hanna'
    rdoc.options += ['-f', 'hanna']
  rescue Gem::LoadError
  end

  rdoc.rdoc_files.add %w"README.rdoc CHANGELOG MIT-LICENSE lib/**/*.rb"
end
