require 'open-uri'
require 'progress_bar'
require 'rm2jira/redmine/pdf'

module RM2Jira
  class Redmine
    API_KEY = ENV['API_KEY']
    BASE_URL = ENV['BASE_URL']
    JIRA_API = ENV['JIRA_API']
    attr_reader :projects

    def initialize
      @projects = get_projects
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

    def self.get_issue_ids(project_id)
      id_array = []
      offset = 0
      while @total_count != id_array.uniq.count
        uri = URI("#{BASE_URL}/issues.json?project_id=#{project_id}&sort=id&status_id=*&limit=100&offset=#{offset}")
        req = Net::HTTP::Get.new(uri)

        req["Content-Type"] = "application/json"
        req['X-Redmine-API-Key'] = API_KEY

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        response_json = JSON.parse(http.request(req).body)
        @total_count = response_json['total_count']
        offset += 100
        response_json['issues'].each do |x|
          next if id_array.include? x['id']
          id_array << x['id']
        end
      end

      id_array
    end

    def self.get_issues(issue_ids, start_at = 0)
      id_hash = {}
      issue_ids.each.with_index do |x, index|
        id_hash.merge!(x => index)
      end

      bar = ProgressBar.new(@total_count - (start_at.to_i.zero? ? 0 : id_hash[start_at.to_i]))
      puts "#{@total_count - (start_at.to_i.zero? ? 0 : id_hash[start_at.to_i])} tickets to migrate"
      issue_ids.drop(id_hash[start_at.to_i] || 0).each do |issue_id|
        bar.increment!
        next if Validator.search_jira_for_rm_id(issue_id)
        ticket = Redmine.download_ticket(issue_id)
        Redmine.download_attachments(ticket) unless ticket['attachments'].empty?
        RM2Jira::Jira.upload_ticket_to_jira(ticket)
      end
    end

    def self.upload_single_ticket(ticket_id)
      return if Validator.search_jira_for_rm_id(ticket_id)
      ticket = Redmine.download_ticket(ticket_id)
      Redmine.download_attachments(ticket) unless ticket['attachments'].empty?
      RM2Jira::Jira.upload_ticket_to_jira(ticket)
    end

    def self.download_ticket(ticket_id)
      uri = URI("#{BASE_URL}/issues/#{ticket_id}.json?include=attachments,relations,children,changesets,journals") #fix fix fix
      req = Net::HTTP::Get.new(uri)

      req["Content-Type"] = "application/json"
      req['X-Redmine-API-Key'] = API_KEY

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      response = http.request(req)

      JSON.parse(response.body)['issue']
    end

    def self.download_attachments(ticket)
      Dir.mkdir("tmp/#{ticket['id']}") unless File.exist?("tmp/#{ticket['id']}")
      ticket['attachments'].each do |attachment|
        uri = URI(attachment['content_url'])
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', verify_mode: OpenSSL::SSL::VERIFY_NONE ) do |http|
          request = Net::HTTP::Get.new(uri.request_uri)
          request['X-Redmine-API-Key'] = API_KEY
          http.request(request) do |response|
            open("tmp/#{ticket['id']}/#{attachment['filename']}", 'wb') do |file|
              file.write(response.body)
            end
          end
        end
      end
    end
  end
end
