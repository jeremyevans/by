if ENV.delete('COVERAGE')
  require_relative 'simplecov_helper'
  BY_ENV = {
    'COVERAGE'=>'subprocess',
    'RUBYOPT'=>"#{ENV['RUBYOPT']} -r ./test/simplecov_helper",
    'BY_SERVER_NO_DAEMON_NO_CHDIR'=>'1',
  }.freeze
  BY_SERVER_ENV = BY_ENV.merge('BY_SERVER_NO_DAEMON'=>'1').freeze
  BY_ARGS = [].freeze
else
  BY_ENV = BY_SERVER_ENV = {}.freeze
  BY_ARGS = ['--disable-gems'].freeze
end

ENV['MT_NO_PLUGINS'] = '1' # Work around stupid autoloading of plugins
require 'minitest/global_expectations/autorun'
require 'open3'
require 'socket'
require 'rbconfig'

RUBY = RbConfig.ruby
BY_TEST_FILE = File.expand_path(File.join(__dir__, 'lib', 'lib.rb'))
BY_TEST_FILE2 = File.expand_path(File.join(__dir__, 'lib', 'lib2.rb'))
BY_TEST_ARGV_FILE = File.expand_path(File.join(__dir__, 'lib', 'argv_example.rb'))
BY = File.expand_path(File.join(__dir__, 'by_shim'))
BY_SERVER = File.expand_path(File.join(__dir__, 'by_server_shim'))
BY_SESSION = File.expand_path(File.join(__dir__, 'by_session_shim'))
BY_SOCKET = ENV['BY_SOCKET'] = File.expand_path(File.join(__dir__, 'by-test-socket'))

describe 'by/by_server' do
  def ensure_server_up
    i = 0
    until by('-e', 'print 1')[0] == '1'
      i += 1
      raise "by_server not running" if i > 10
      print '.'
      sleep(0.1)
    end
  end

  def by_server_capture(env, *args)
    Open3.capture3(env, RUBY, BY_SERVER, *args)
  end

  def by_server_env(env, *args)
    @by_server = Process.spawn(env, RUBY, BY_SERVER, *args)
    ensure_server_up
  end

  def by_server(*args)
    by_server_env({}, *args)
  end

  def by_server_stop(env={})
    system(env, RUBY, BY_SERVER, 'stop', exception: true)
  end

  def by_session_env(env, *args)
    Open3.capture3(env, RUBY, BY_SESSION, *args)
  end

  def by_env(env, *args)
    Open3.capture3(BY_ENV.merge(env), RUBY, *BY_ARGS, BY, *args)
  end

  def by(*args)
    by_env({}, *args)
  end

  after do
    if @by_server && File.socket?(BY_SOCKET)
      by_server_stop
      i = 0
      while File.socket?(BY_SOCKET)
        i += 1
        sleep(0.1)
        by_server_stop
        if i > 10
          $stderr.puts "leaked by-server"
          File.delete(BY_SOCKET)
          break
        end
      end
    elsif File.socket?(BY_SOCKET)
      File.delete(BY_SOCKET)
    end
  end

  it "should have server preload libraries when daemonizing" do
    by_server_env(BY_SERVER_ENV.merge('BY_SERVER_NO_DAEMON'=>'1'), BY_TEST_FILE)
    by('-e', 'print BY_TEST').must_equal ['1', '', 0]
    by(BY_TEST_FILE).must_equal ['', '', 0]
  end

  it "should have server preload libraries when not daemonizing" do
    env = BY_SERVER_ENV.merge(
      'BY_SERVER_NO_DAEMON_NO_CHDIR'=>'1',
      'BY_SERVER_DAEMON_NO_REDIR_STDIO'=>'1',
      'BY_SERVER_COVERAGE_TEST_NO_DAEMON'=>'1'
    )
    env.delete('BY_SERVER_NO_DAEMON')
    by_server_env(env, BY_TEST_FILE)
    by('-e', 'print BY_TEST').must_equal ['1', '', 0]
    by(BY_TEST_FILE).must_equal ['', '', 0]
  end

  it "should have by-server respect BY_SERVER_AUTO_REQUIRE environment variable" do
    by_server_env(BY_SERVER_ENV.merge('BY_SERVER_AUTO_REQUIRE'=>BY_TEST_FILE))
    by('-e', 'print BY_TEST').must_equal ['1', '', 0]
  end

  it "should print loaded libraries in worker if client has DEBUG=log environment variable set" do
    by_server_env(BY_SERVER_ENV)
    o, e, st = by_env({'DEBUG'=>'log'}, BY_TEST_FILE)
    o.must_include BY_TEST_FILE
    e.must_equal ''
    st.exitstatus.must_equal 0
  end

  it "should shutdown server and not remove socket file on server QUIT" do
    by_server_env(BY_SERVER_ENV.merge('BY_SERVER_NO_DAEMON'=>'1'), BY_TEST_FILE)
    File.socket?(BY_SOCKET).must_equal true
    Process.kill(:QUIT, @by_server)
    @by_server = nil
    sleep 0.1
    File.socket?(BY_SOCKET).must_equal true
  end

  it "should shutdown server and remove socket file on server TERM" do
    by_server_env(BY_SERVER_ENV.merge('BY_SERVER_NO_DAEMON'=>'1'), BY_TEST_FILE)
    File.socket?(BY_SOCKET).must_equal true
    Process.kill(:TERM, @by_server)
    @by_server = nil
    sleep 0.1
    File.socket?(BY_SOCKET).must_equal false
  end

  it "should not shutdown server on worker TERM" do
    by_server_env(BY_SERVER_ENV, BY_TEST_FILE)
    2.times do
      o, e, st = by('-e', 'print BY_TEST; Process.kill(:TERM, $$); print BY_TEST;')
      o.must_equal '1'
      e.must_equal ''
      st.exitstatus.must_equal 1
    end
  end

  it "should execute code from stdin if no arguments are given" do
    by_server_env(BY_SERVER_ENV, BY_TEST_FILE)
    o, e, st = by(:stdin_data=>'print BY_TEST').must_equal ['1', '', 0]

    o, e, st = by(:stdin_data=>'raise "foo"')
    ["#<RuntimeError: foo>\n", ''].must_include o
    e.must_include 'foo (RuntimeError)'
    st.exitstatus.must_equal 1
  end

  it "should return error code for -e with no second argument" do
    by_server_env(BY_SERVER_ENV, BY_TEST_FILE)
    o, e, st = by('-e')
    o.must_equal ''
    e.must_equal "no code specified for -e (RuntimeError)\n"
    st.exitstatus.must_equal 1
  end

  it "should handle ARGV correctly when using -e" do
    by_server_env(BY_SERVER_ENV, BY_TEST_FILE)
    o, e, st = by('-e', 'p ARGV', 'a', 'bc')
    o.must_equal "[\"a\", \"bc\"]\n"
    e.must_equal ""
    st.exitstatus.must_equal 0
  end

  it "should handle ARGV correctly when providing filename" do
    by_server_env(BY_SERVER_ENV, BY_TEST_FILE)
    o, e, st = by(BY_TEST_ARGV_FILE, 'a', 'bc')
    o.must_equal "[\"a\", \"bc\"]\n"
    e.must_equal ""
    st.exitstatus.must_equal 0
  end

  it "should have worker handle m first argument" do
    by_server_env(BY_SERVER_ENV.merge('BY_SERVER_COVERAGE_TEST_M_EXIT'=>'1'), 'minitest/global_expectations')
    o, e, st = by('m', 'test/lib/minitest_example.rb:6')
    o.must_include '1 runs, 1 assertions, 0 failures, 0 errors'
    e.must_equal ""
    st.exitstatus.must_equal 0

    o, e, st = by_env({'MINITEST_FAIL'=>'1'}, 'm', 'test/lib/minitest_example.rb:6')
    o.must_include '1 runs, 1 assertions, 1 failures, 0 errors'
    e.must_equal ""
    st.exitstatus.must_equal 1
  end

  it "should have worker handle file.rb:line first argument" do
    by_server_env(BY_SERVER_ENV.merge('BY_SERVER_COVERAGE_TEST_M_EXIT'=>'1'), 'minitest/global_expectations')
    o, e, st = by('test/lib/minitest_example.rb:6')
    o.must_include '1 runs, 1 assertions, 0 failures, 0 errors'
    e.must_equal ""
    st.exitstatus.must_equal 0

    o, e, st = by_env({'MINITEST_FAIL'=>'1'}, 'test/lib/minitest_example.rb:6')
    o.must_include '1 runs, 1 assertions, 1 failures, 0 errors'
    e.must_equal ""
    st.exitstatus.must_equal 1
  end

  it "should have worker handle irb first argument" do
    by_server_env(BY_SERVER_ENV, 'irb')
    o, e, st = by('irb', :stdin_data=>"p('a' + 'bc')")
    o.must_include "p('a' + 'bc')"
    o.must_include '"abc"'
    e.must_equal ""
    st.exitstatus.must_equal 0

    o, e, st = by('irb', 'test/lib/irb_example.rb')
    o.must_include '["a", "bc"]'
    e.must_equal ""
    st.exitstatus.must_equal 0
  end

  it "should have worker handle minitest with autorun with passing tests" do
    by_server_env(BY_SERVER_ENV, 'minitest/global_expectations')
    o, e, st = by('test/lib/minitest_example.rb')
    o.must_include '2 runs, 3 assertions, 0 failures, 0 errors'
    e.must_equal ""
    st.exitstatus.must_equal 0
  end

  it "should have worker handle minitest with autorun with failing tests" do
    by_server_env(BY_SERVER_ENV, 'minitest/global_expectations')
    o, e, st = by_env({'MINITEST_FAIL'=>'1'}, 'test/lib/minitest_example.rb')
    o.must_include '2 runs, 3 assertions, 1 failures, 0 errors'
    e.must_equal ""
    st.exitstatus.must_equal 1
  end

  it "should have worker handle minitest with autorun with extra arguments" do
    by_server_env(BY_SERVER_ENV, 'minitest/global_expectations')
    o, e, st = by('test/lib/minitest_example.rb', '-v')
    o.must_include '2 runs, 3 assertions, 0 failures, 0 errors'
    o.must_include '_should work = '
    o.must_include '_should always work = '
    e.must_equal ""
    st.exitstatus.must_equal 0
  end

  it "should have By::Server.with_argument_handling work" do
    server = File.expand_path(File.join(__dir__, 'by_server_subclass'))
    @by_server = Process.spawn(BY_SERVER_ENV, RUBY, server, BY_TEST_FILE)
    ensure_server_up
    by('-I', 'test/lib', '-e', 'print BY_TEST; Object.send(:remove_const, :BY_TEST); require "lib2"; print BY_TEST;').must_equal ['12', '', 0]
  end

  it "should have worker handle error when requiring file" do
    by_server_env(BY_SERVER_ENV)
    2.times do
      o, e, st = by('test/lib/error_example.rb')
      o.must_include ''
      e.must_include 'foo (RuntimeError)'
      st.exitstatus.must_equal 1
    end
  end

  it "should have server work without daemonizing and with logging turned on" do
    begin
      res = nil
      t = Thread.new do
        res = by_server_capture({'DEBUG'=>'log', 'BY_SERVER_NO_DAEMON'=>'1'}, BY_TEST_FILE)
      end
      ensure_server_up
      by('-e', 'print BY_TEST').must_equal ['1', '', 0]
    ensure
      by_server_stop(BY_SERVER_ENV)
      t.join
    end
    o, e, st = res
    o.must_include BY_TEST_FILE
    e.must_equal ''
    st.must_equal 0
  end

  it "should have server work without daemonizing and without logging turned on" do
    begin
      res = nil
      t = Thread.new do
        res = by_server_capture({'BY_SERVER_NO_DAEMON'=>'1'}, BY_TEST_FILE)
      end
      ensure_server_up
      by('-e', 'print BY_TEST').must_equal ['1', '', 0]
    ensure
      by_server_stop(BY_SERVER_ENV)
      t.join
    end
    o, e, st = res
    o.must_equal ''
    e.must_equal ''
    st.must_equal 0
  end

  it "should have server close existing server and then start with new arguments" do
    begin
      res = res2 = nil
      t = Thread.new do
        res = by_server_capture(BY_SERVER_ENV.merge('DEBUG'=>'log', 'BY_SERVER_NO_DAEMON'=>'1'), BY_TEST_FILE)
      end
      ensure_server_up
      by('-e', 'print BY_TEST').must_equal ['1', '', 0]
      t2 = Thread.new do
        res2 = by_server_capture(BY_SERVER_ENV.merge('DEBUG'=>'log', 'BY_SERVER_NO_DAEMON'=>'1'), BY_TEST_FILE2)
      end
      sleep 0.3
      ensure_server_up
      by('-e', 'print BY_TEST').must_equal ['2', '', 0]
    ensure
      by_server_stop(BY_SERVER_ENV)
      t.join
      t2.join
    end
    o, e, st = res
    o.wont_include "Shutting down existing by_server"
    o.must_include BY_TEST_FILE
    e.must_equal ''
    st.must_equal 0

    o, e, st = res2
    o.must_include "Shutting down existing by_server at #{BY_SOCKET}...Success!"
    o.must_include BY_TEST_FILE2
    e.must_equal ''
    st.must_equal 0
  end

  it "should have server close existing server if argument is stop" do
    begin
      res = res2 = nil
      t = Thread.new do
        res = by_server_capture(BY_SERVER_ENV.merge('DEBUG'=>'log', 'BY_SERVER_NO_DAEMON'=>'1'), BY_TEST_FILE)
      end
      ensure_server_up
      by('-e', 'print BY_TEST').must_equal ['1', '', 0]
      t2 = Thread.new do
        res2 = by_server_capture(BY_SERVER_ENV.merge('BY_SERVER_NO_DAEMON'=>'1'), 'stop')
      end
      sleep 0.3
    ensure
      if defined?(SimpleCov)
        system(RUBY, BY_SERVER, 'stop', err: File::NULL)
      else
        by_server_stop
      end
      t.join
      t2.join
    end
    o, e, st = res
    o.wont_include "Shutting down existing by_server"
    o.must_include BY_TEST_FILE
    e.must_equal ''
    st.must_equal 0

    o, e, st = res2
    o.must_equal ''
    e.must_equal ''
    st.must_equal 0
  end

  it "should print error message if by connecting to server that isn't by_server" do
    s = UNIXServer.new(BY_SOCKET)
    t = Thread.new do
      c = s.accept
      c.write('a')
      c.close
    end
    o, e, st = by('-e', '')
    o.must_equal ''
    e.must_equal "Invalid by_server worker pid\n"
    st.exitstatus.must_equal 1
  ensure
    if s
      s.close
      t.join
    end
  end

  it "should print error message if by_server connecting to server that isn't by_server" do
    s = UNIXServer.new(BY_SOCKET)
    t = Thread.new do
      c = s.accept
      c.write('a')
      c.close
    end
    o, e, st = by_server_capture(BY_SERVER_ENV.merge('DEBUG'=>'1'), 'stop')
    o.must_include 'Shutting down existing by_server'
    o.must_include 'FAILED!!!'
    e.must_equal "Error shutting down server on existing socket: RuntimeError: Invalid by_server worker pid\n"
    st.exitstatus.must_equal 1
  ensure
    if s
      s.close
      t.join
    end
  end

  it "should print error message if by_server connecting to server that isn't by_server if not in debug mode" do
    s = UNIXServer.new(BY_SOCKET)
    t = Thread.new do
      c = s.accept
      c.write('a')
      c.close
    end
    o, e, st = by_server_capture(BY_SERVER_ENV, 'stop')
    o.must_equal ''
    e.must_equal "Error shutting down server on existing socket: RuntimeError: Invalid by_server worker pid\n"
    st.exitstatus.must_equal 1
  ensure
    if s
      s.close
      t.join
    end
  end

  it "should print error message if by_server connecting to server that closes immediately" do
    s = UNIXServer.new(BY_SOCKET)
    t = Thread.new do
      s.accept.close
    end
    o, e, st = by_server_capture(BY_SERVER_ENV.merge('DEBUG'=>'1'), 'stop')
    o.must_include 'Shutting down existing by_server'
    o.must_include 'FAILED!!!'
    e.must_equal "Error shutting down server on existing socket: EOFError: end of file reached\n"
    st.exitstatus.must_equal 1
  ensure
    if s
      s.close
      t.join
    end
  end

  it "should have by-session open new shell" do
    o, e, st = by_session_env(BY_ENV, BY_TEST_FILE, :stdin_data=>"echo 1")
    o.must_equal "1\n"
    e.must_equal ''
    st.exitstatus.must_equal 0
  end

  it "should have by-session start server for shell session and close server afterward" do
    o, e, st = by_session_env(BY_ENV, BY_TEST_FILE, :stdin_data=>"#{'unset RUBYOPT; ' if defined?(SimpleCov)}#{RUBY} #{BY} -e 'print BY_TEST'")
    o.must_equal '1'
    e.must_equal ''
    st.exitstatus.must_equal 0
  end

  it "should have by-session respect BY_SERVER_AUTO_REQUIRE environment variable" do
    o, e, st = by_session_env(BY_ENV.merge('BY_SERVER_AUTO_REQUIRE'=>"#{BY_TEST_FILE} #{BY_TEST_ARGV_FILE}"), :stdin_data=>"#{'unset RUBYOPT; ' if defined?(SimpleCov)}#{RUBY} #{BY} -e 'print BY_TEST'")
    o.must_equal "[]\n1"
    e.must_equal ''
    st.exitstatus.must_equal 0
  end
end
