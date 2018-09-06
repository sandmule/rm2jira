require 'yaml'

module RM2Jira
  class Configuration
    include Logging
    attr_reader :config

    def initialize
      @config = YAML.load_file('config/config.yml')

      if @config['projects'].nil?
        @config['projects'] = RM2Jira::Redmine.new.projects
        File.write('config/config.yml', YAML.dump(@config))
      end

      logger.level = log_level_hash[@config['debug_level']]
    end

    def log_level_hash
      {
        'debug'   => Logger::DEBUG,
        'error'   => Logger::ERROR,
        'fatal'   => Logger::FATAL,
        'info'    => Logger::INFO,
        'unknown' => Logger::UNKNOWN,
        'warn'    => Logger::WARN
      }
    end
  end
end
