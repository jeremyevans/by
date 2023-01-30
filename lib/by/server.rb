# frozen_string_literal: true

require 'socket'
require_relative 'worker'

module By
  class Server
    # Return a subclass that will use a Worker subclass with
    # a handle_args method defined by the given block. Allows
    # for easily customizing/overriding the default argument
    # handling.
    def self.with_argument_handler(&block)
      worker_subclass = Class.new(new.default_worker_class) do
        define_method(:handle_args, &block)
      end
      Class.new(self) do
        define_method(:default_worker_class){worker_subclass}
      end
    end

    # Creates a new server.  Arguments:
    # socket_path: The path to the UNIX socket to create and listen on.
    # argv: The arguments to the server, which are libraries to be required by default.
    # debug: If set, operations on an existing server socket will be logged.
    #        If the value is <tt>'log'</tt>, <tt>$LOADED_FEATURES</tt> will also be logged to the stdout
    #        after libraries have been required.
    # daemonize: Whether to daemonize, +true+ by default.
    # daemon_args: Arguments to use when daemonizing, <tt>[false, false]</tt> by default.
    # worker_class: The class to use for worker process handling, Worker by default.
    def initialize(socket_path: default_socket_path, argv: default_argv, debug: default_debug,
                   daemonize: default_daemonize, daemon_args: default_daemon_args,
                   worker_class: default_worker_class)
      @socket_path = socket_path
      @argv = argv
      @debug = debug
      if @daemonize = !!daemonize
        @daemon_args = Array(daemon_args)
      end
      @worker_class = worker_class
    end

    # The default socket path to use.  Use the +BY_SOCKET+ environment variable if set,
    # or <tt>~/.by_socket</tt> if not set.
    def default_socket_path
      ENV['BY_SOCKET'] || File.join(ENV["HOME"], '.by_socket')
    end

    # The default server arguments, uses +ARGV+ by default.
    def default_argv
      ARGV
    end

    # The default debug mode.  This uses and removes the +DEBUG+ environment variable.
    def default_debug
      ENV.delete('DEBUG')
    end

    # The default for whether to daemonize. It is true if the +BY_SERVER_NO_DAEMON+
    # environment variable is not set.
    def default_daemonize
      !ENV['BY_SERVER_NO_DAEMON']
    end

    # The default arguments when daemonizing.  By default, considers the 
    # +BY_SERVER_DAEMON_NO_CHDIR+ and +BY_SERVER_DAEMON_NO_REDIR_STDIO+ environment
    # variables.
    def default_daemon_args
      [!!ENV['BY_SERVER_DAEMON_NO_CHDIR'], !!ENV['BY_SERVER_DAEMON_NO_REDIR_STDIO']]
    end

    # The default worker class to use for worker processes, Worker by default.
    def default_worker_class
      Worker
    end

    # Runs the server.  This will not terminate until the server receives SIGTERM
    # or stop_accepting_clients! is called manually.
    #
    # If stop? is true, does not run a server, just handles an existing server.
    def run
      handle_existing_server
      return if stop?

      handle_argv
      setup_server
      daemonize if daemonize?
      setup_signals
      accept_clients
    end

    # Handle an existing server socket.  This attempts to connect to the socket and
    # then shutdown the server. If successful, it removes the socket.  If unnecessful,
    # it will print an error.
    def handle_existing_server
      if File.socket?(@socket_path)
        begin
          @socket = UNIXSocket.new(@socket_path)
          print "Shutting down existing by_server at #{@socket_path}..." if @debug
          raise "Invalid by_server worker pid" unless @socket.readline("\0", chomp: true).to_i > 1
          @socket.send_io($stdin)
          @socket.send_io($stdout)
          @socket.send_io($stderr)
          @socket.write("stop")
          @socket.shutdown(Socket::SHUT_WR)
          @socket.read
          @socket.close
        rescue => e
          puts "FAILED!!!" if @debug
          $stderr.puts "Error shutting down server on existing socket: #{e.class}: #{e.message}"
          exit(1)
        else
          puts "Success!" if @debug
        end
        @socket = nil
        File.delete(@socket_path)
      end
    end

    # Whether to only stop an existing server and not start a new server.
    def stop?
      @argv == ['stop']
    end

    # Handle arguments provided to the server.  Requires each argument by default.
    def handle_argv
      (auto_require_files + @argv).each{|f| require f}
      print_loaded_features if @debug == 'log'
    end

    # Files to automatically require, uses the +BY_SERVER_AUTO_REQUIRE+ environment
    # variable by default.
    def auto_require_files
      (ENV['BY_SERVER_AUTO_REQUIRE'] || '').split
    end

    # Creates and listens on the server socket.
    def setup_server
      # Prevent TOCTOU on server socket creation
      umask = File.umask(077)
      @socket = UNIXServer.new(@socket_path)
      File.umask(umask)
      system('chmod', '600', @socket_path)
    end

    # Daemonize with configured daemon args using Process.daemon.
    def daemonize
      Process.daemon(*@daemon_args)
    end

    # Whether to daemonize.
    def daemonize?
      !!@daemonize
    end

    # Trap SIGTERM and have it stop accepting clients.
    # Trap SIGTERM and have it remove the socket and stop accepting clients.
    def setup_signals
      @sigquit_default = Signal.trap(:QUIT) do
        stop_accepting_clients!
      end
      @sigterm_default = Signal.trap(:TERM) do
        begin
          File.delete(@socket_path)
        rescue Errno::ENOENT
          # server socket already deleted, ignore
        end
        stop_accepting_clients!
      end
    end

    # Accept each client connection and fork a worker socket for it.
    # Terminate loop when stop_accepting_clients! is called.
    def accept_clients
      while socket = accept_client
        fork_worker(socket)
      end
    end

    # Accept a new client connection, or return nil if
    # stop_accepting_clients! has been called.
    def accept_client
      @socket.accept
    rescue IOError, Errno::EBADF
      # likely closed stream, return nil to exit accept_clients loop
      nil
    end

    # Close the server socket.  This will trigger the accept_clients
    # loop to terminate.
    def stop_accepting_clients!
      @socket.close
    end

    # Fork a worker process to handle the client connection.  Close the
    # given socket after the fork, so the socket will open be open in
    # the worker process.
    def fork_worker(socket)
      Process.detach(Process.fork do
        Signal.trap(:QUIT, @sigquit_default)
        Signal.trap(:TERM, @sigterm_default)
        @worker_class.new(socket).run
      end)
      socket.close
    end

    # Print <tt>$LOADED_FEATURES</tt> to stdout.
    def print_loaded_features
      puts $LOADED_FEATURES
    end
  end
end
