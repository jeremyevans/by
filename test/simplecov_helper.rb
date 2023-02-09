require 'simplecov'
require 'coverage'

SimpleCov.instance_exec do
  enable_coverage :branch
  add_filter "/test/"
  add_group('Missing'){|src| src.covered_percent < 100}
  add_group('Covered'){|src| src.covered_percent == 100}
  enable_for_subprocesses true

  at_fork do |pid|
    command_name "#{SimpleCov.command_name}:#{pid}"
    self.print_error_status = false
    formatter SimpleCov::Formatter::SimpleFormatter
    minimum_coverage 0
    self.pid = $$
  end

  if ENV['COVERAGE'] == 'subprocess'
    ENV.delete('COVERAGE')
    command_name "spawn"
    at_fork.call(Process.pid)

    if ENV['BY_SERVER_COVERAGE_TEST_NO_DAEMON']
      def Process.daemon(*a) end
    end
    if ENV['BY_SERVER_COVERAGE_TEST_NO_KILL']
      Process.singleton_class.prepend(Module.new do
        def kill(sig, *)
          super unless sig == :KILL
        end
      end)
    end
    if ENV['BY_SERVER_COVERAGE_TEST_M_EXIT']
      require 'm'
      M.singleton_class.include(Module.new do
        def exit!(*a)
          SimpleCov.process_result(SimpleCov.result)
          super
        end
      end)
    end
  else
    command_name 'test'
  end

  start
end
