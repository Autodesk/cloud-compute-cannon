# https://github.com/docker/docker/issues/17830
require 'json'

module Fluent
  class TextParser
    class JsonInStringParser < Parser
      Plugin.register_parser("json_in_string", self)

      config_param :time_format, :string, :default => nil # time_format is configurable

      def configure(conf)
        super
        @time_parser = TimeParser.new(@time_format)
      end

      # This is the main method. The input "text" is the unit of data to be parsed.
      # If this is the in_tail plugin, it would be a line. If this is for in_syslog,
      # it is a single syslog message.
      def parse(text)
        begin
          text.gsub! '\"', '"'
          hash = nil
          time = nil
          if text.start_with?('{') then
            begin
              hash = JSON.parse(text)
              time = @time_parser.parse(hash['time'])
            rescue => e
              puts "parse failed #{e.message}"
              hash = text
            end
          else
              hash = text
          end
          yield time, hash
        rescue => e
          puts "parse failed #{e.message}"
          yield text
        end
      end
    end
  end
end