# frozen_string_literal: true
    
module By
  class Worker
    # Whether the worker process should signal a normal exit to the client.
    # The default is nil, which signals a normal exit when the worker
    # process exits normally.  This can be set to false to signal an
    # abnormal exit, such as to indicate test failures.
    attr_writer :normal_exit 

    # Create the worker.  Arguments
    # socket :: The Unix socket to use to communicate with the client.
    # sigterm_handler
    def initialize(socket)
      @socket = socket
      @normal_exit = nil
    end

    # Run the worker process.
    def run
      write_pid
      reopen_stdio
      chdir_or_stop
      replace_env
      handle_args(get_args)
    end

    # Write the current process pid to the client, to signal that
    # the worker process is ready.
    def write_pid
      @socket.write($$.to_s)
      @socket.write("\0")
    end

    # Replace stdin, stdout, stderr with the IO values provided by the client.
    def reopen_stdio
      $stdin.reopen(@socket.recv_io(IO))
      $stdout.reopen(@socket.recv_io(IO))
      $stderr.reopen(@socket.recv_io(IO))
    end 

    # Change to the given directory, unless the client is telling the
    # worker to stop the server.
    def chdir_or_stop
      arg = @socket.readline("\0", chomp: true)
      arg == 'stop' ? stop_server : chdir(arg)
    end

    # Stop the server process by sending it the SIGQUIT signal, then exit.
    def stop_server
      Process.kill(:QUIT, Process.ppid)
      cleanup_proc.call
      exit
    end

    # Change to the given directory.
    def chdir(dir)
      Dir.chdir(dir)
    end

    # Print <tt>$LOADED_FEATURES</tt> to stdout.
    def print_loaded_features
      puts $LOADED_FEATURES
    end

    # A proc for communicating exit status to the client, and
    # printing the loaded features if configured.  Used during
    # process shutdown.
    def cleanup_proc
      proc do
        if @normal_exit.nil?
          @normal_exit = $!.nil? || ($!.is_a?(SystemExit) && $!.success?)
        end
        @socket.write(@normal_exit ? '0' : '1')
        @socket.shutdown(Socket::SHUT_WR)
        @socket.close
        print_loaded_features if ENV['DEBUG'] == 'log'
      end
    end

    # Replace ENV with the environment provided by the client.
    def replace_env
      env = {}
      while line = @socket.readline("\0", chomp: true)
        break if line.empty?
        k, v = line.split("=")
        env[k] = v
      end
      ENV.replace(env)
    end

    # An array of arguments provided by the client.
    def get_args
      args = []
      while !@socket.eof?
        args << @socket.readline("\0", chomp: true)
      end
      args
    end

    # Handle arguments provided by the client.  Ensure correct
    # client after handling the arguments.
    def handle_args(args)
      worker = self
      cleanup = cleanup_proc

      case arg = args.first
      when 'm', /\.rb:\d+\z/
        args.shift if arg == 'm'
        ARGV.replace(args)
        require 'm'
        M.define_singleton_method(:exit!) do |exit_code|
          worker.normal_exit = exit_code == true
          cleanup.call
          super(exit_code)
        end
        M.run(args)
      when 'irb'
        at_exit(&cleanup)
        args.shift
        ARGV.replace(args)
        require 'irb'
        IRB.start(__FILE__)
      when '-e'
        at_exit(&cleanup)
        unless args.length >= 2
          $stderr.puts 'no code specified for -e (RuntimeError)'
          exit(1)
        end
        args.shift
        code = args.shift
        ARGV.replace(args)
        ::TOPLEVEL_BINDING.eval(code)
      when String
        args.shift
        ARGV.replace(args)

        begin
          require File.expand_path(arg)
        rescue
          @normal_exit = false
          at_exit(&cleanup)
          raise
        end

        if defined?(Minitest) && Minitest.class_variable_get(:@@installed_at_exit)
          Minitest.singleton_class.prepend(Module.new do
            define_method(:run) do |argv|
              super(argv).tap{|exit_code| p worker.normal_exit = exit_code == true}
            end
          end)
          Minitest.after_run(&cleanup)
        else
          at_exit(&cleanup)
        end
      else
        # no arguments
        at_exit(&cleanup)
        ::TOPLEVEL_BINDING.eval($stdin.read)
      end
    end
  end
end

