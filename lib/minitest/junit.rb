require 'minitest/junit/version'
require 'minitest'
require 'ox'
require 'socket'
require 'time'

# :nodoc:
module Minitest
  module Junit
    # :nodoc:
    class Reporter
      def initialize(io, options)
        @io = io
        @results = []
        @options = options
        @options[:timestamp] = options.fetch(:timestamp, Time.now.iso8601)
        @options[:hostname] = options.fetch(:hostname, Socket.gethostname)
      end

      def passed?
        true
      end

      def start; end

      def record(result)
        @results << result
      end

      def report
        doc = Ox::Document.new(version: '1.0', encoding: 'UTF-8')
        instruct = Ox::Instruct.new(:xml)
        instruct[:version] = '1.0'
        instruct[:encoding] = 'UTF-8'
        doc << instruct

        testsuite = Ox::Element.new('testsuite')
        testsuite['name'] = @options[:name] || 'minitest'
        testsuite['timestamp'] = @options[:timestamp]
        testsuite['hostname'] = @options[:hostname]
        testsuite['tests'] = @results.size
        testsuite['skipped'] = @results.count(&:skipped?)
        testsuite['failures'] = @results.count { |result| !result.error? && result.failure }
        testsuite['errors'] = @results.count(&:error?)
        testsuite['time'] = format_time(@results.map(&:time).inject(0, :+))
        @results.each do |result|
          testsuite << format(result)
        end

        testsuites = Ox::Element.new('testsuites')
        testsuites << testsuite

        doc << testsuites
        @io << Ox.dump(doc)
      end

      def format(result, parent = nil)
        testcase = Ox::Element.new('testcase')
        testcase['classname'] = format_class(result)
        testcase['name']      = format_name(result)
        testcase['time']      = format_time(result.respond_to?(:time) ? result.time : 0)
      
        if result.respond_to?(:source_location) && result.source_location
          file, line = result.source_location
          testcase['file'] = relative_to_cwd(file)
          testcase['line'] = line
        else
          testcase['file'] = ''
          testcase['line'] = ''
        end
      
        testcase['assertions'] = result.respond_to?(:assertions) ? result.assertions : 0
      
        if result.skipped?
          skipped = Ox::Element.new('skipped')
          skipped['message'] = result.respond_to?(:message) ? result.message : result.to_s
          testcase << skipped
        else
          Array(result.failures).each do |failure|
            tag = Ox::Element.new(classify(failure))
            tag['message'] = failure.respond_to?(:message) ? failure.message.to_s : failure.to_s
            tag << format_backtrace(failure)
            testcase << tag
          end
        end
      
        # Rails 7.1+ screenshot attachment (GitLab JUnit consumption)
        if result.respond_to?(:metadata)
          metadata = begin
            result.metadata
          rescue StandardError
            nil
          end
      
          if metadata.is_a?(Hash) && (path = metadata[:failure_screenshot_path])
            screenshot = Ox::Element.new('system-out')
            screenshot << "[[ATTACHMENT|#{path}]]"
            testcase << screenshot
          end
        end
      
        testcase
      end

      private

      def classify(failure)
        if failure.instance_of? UnexpectedError
          'error'
        else
          'failure'
        end
      end

      def working_directory
        @working_directory ||= Dir.getwd
      end

      def relative_to_cwd(path)
        path.sub(working_directory, '.')
      end

      def format_backtrace(failure)
        Minitest.filter_backtrace(failure.backtrace).map do |line|
          relative_to_cwd(line)
        end.join("\n")
      end

      def format_class(result)
        if @options[:junit_jenkins]
          result.klass.to_s.gsub(/(.*)::(.*)/, '\1.\2')
        else
          result.klass
        end
      end

      def format_name(result)
        result.name
      end

      def format_time(time)
        Kernel::format('%.6f', time)
      end
    end
  end
end
