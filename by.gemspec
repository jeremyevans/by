spec = Gem::Specification.new do |s|
  s.name = 'by'
  s.version = '1.0.1'
  s.platform = Gem::Platform::RUBY
  s.extra_rdoc_files = ["README.rdoc", "CHANGELOG", "MIT-LICENSE"]
  s.rdoc_options += ["--quiet", "--line-numbers", "--inline-source", '--title', 'by: Ruby library preloader', '--main', 'README.rdoc']
  s.license = "MIT"
  s.summary = "Ruby library preloader"
  s.author = "Jeremy Evans"
  s.email = "code@jeremyevans.net"
  s.homepage = "http://github.com/jeremyevans/by"
  s.require_path = "lib"
  s.bindir = 'bin'
  s.executables << 'by' << 'by-server' << 'by-session'
  s.files = %w(MIT-LICENSE CHANGELOG README.rdoc) + Dir["lib/**/*.rb"]
  s.description = <<END
by is a library preloader for ruby designed to speed up process startup.
It uses a client/server approach, where the server loads the libraries and
listens on a UNIX socket, and the client connects to that socket to run
processes.  For each client connection, the server forks a worker process,
which uses the current directory, stdin, stdout, stderr, and environment
of the client process.  The worker process then processes the arguments
provided by the client. The client process waits until the worker process
closes the socket, which the worker process attempts to do right before
it exits.
END

  s.metadata          = { 
    'bug_tracker_uri'   => 'https://github.com/jeremyevans/by/issues',
    'changelog_uri'     => 'https://github.com/jeremyevans/by/blob/master/CHANGELOG',
    'mailing_list_uri'  => 'https://github.com/jeremyevans/by/discussions',
    "source_code_uri"   => 'https://github.com/jeremyevans/by'
  }

  s.required_ruby_version = ">= 2.6"
  s.add_development_dependency "minitest-global_expectations"
  s.add_development_dependency 'm'
end
