require 'yaml'

module RM2Jira
  class Configuration
    API_KEY = ENV['API_KEY']
    BASE_URL = ENV['BASE_URL']
    include Logging
    attr_reader :config

    def initialize
      @config = YAML.load_file('config/config.yml')

      if @config['projects'].nil?
        @config['projects'] = get_projects
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

    def get_projects
      uri = URI("#{BASE_URL}/projects.json")
      req = Net::HTTP::Get.new(uri)

      req["Content-Type"] = "application/json"
      req['X-Redmine-API-Key'] = API_KEY

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      response_json = JSON.parse(http.request(req).body)

      projects = {}
      response_json['projects'].each do |project|
        projects.merge!(project['name'] => project['id'])
      end

      projects
    end
  end
end
