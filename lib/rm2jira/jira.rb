require 'rest-client'

module RM2Jira
  class Jira
    USER = 's.salter@livelinktechnology.net'.freeze
    PASS = ENV['PASS']

    def self.upload_ticket_to_jira(ticket)
      @ticket = ticket
      @auth64 = Base64.strict_encode64("#{USER}:#{PASS}")
      res = upload_ticket
      changed_name = {}

      while res[:code] == '400'
        if res[:response]['errors'].key?('reporter')
          puts "Author doesn't exist in Jira, defaulting to bot account"
          changed_name[:author] = @ticket['author']['name']
          @ticket['author']['name'] = 's.salter' # api bot name here
        elsif res[:response]['errors'].key?('assignee')
          puts "Assignee doesn't exist in Jira, defaulting to bot account"
          changed_name[:assignee] = @ticket.fetch('assigned_to', {})['name']
          @ticket.fetch('assigned_to', {})['name'] = 's.salter'
        else
          puts "UNCAUGHT ERROR:#{res[:code]}, #{res[:response]['errors']}, Redmine ID:#{@ticket['id']}"
          abort
        end

        res = upload_ticket(changed_name)
      end
    end

  def gets_issue_meta #ignore - this is only for dev work
    uri = URI("https://livelinktech.atlassian.net/rest/api/2/issue/ZREDIMP-25/transitions?expand=transitions.fields")
    uri = URI("https://livelinktech.atlassian.net/rest/api/2/issue/createmeta?expand=projects.issuetypes.fields&projectIds=10016&issuetypeIds=10004")
    # uri = URI("https://livelinktech.atlassian.net/rest/api/2/issue/11764")
    req = Net::HTTP::Get.new(uri)

    req["Content-Type"] = "application/json"
    req['Authorization'] = "Basic #{@auth64}"

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    response_json = JSON.parse(http.request(req).body)

    response_json['projects'][0]['issuetypes'][0]
  end

    def self.upload_ticket(changed_name = nil)
      uri = URI.parse("https://livelinktech.atlassian.net/rest/api/2/issue/")
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true
      req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
      req['Authorization'] = "Basic #{@auth64}"
      @parse_data = ParseData.new(@ticket)
      req.body = @parse_data.get_body(changed_name)
      res = https.request(req)
      response_body = JSON.parse(res.body)
      if res.code == '201'
        puts "Ticket created - Jira ID:#{response_body['id']} Redmine ID:#{@ticket['id']}"
        upload_attachments(response_body['id']) unless @ticket['attachments'].empty?
        add_comment(response_body['id']) unless @ticket['journals'].empty?
        abort unless Validator.validate_data(@ticket, response_body['id'], changed_name)
        puts "Ticket:#{response_body['id']} validated successfully"
      end
      { code: res.code, response: response_body }
    end

    def self.upload_attachments(ticket_id)
      @ticket['attachments'].each.with_index do |attachment, index|
        url = "https://livelinktech.atlassian.net/rest/api/2/issue/#{ticket_id}/attachments"
        resource = RestClient::Resource.new(url, USER, PASS)
        response = resource.post({ file: File.new("tmp/#{@ticket['id']}/#{attachment['filename']}")}, 'X-Atlassian-Token' => 'nocheck' )
        response.code.eql?(200)
        puts "Attachment #{index + 1} of #{@ticket['attachments'].count} added to ticket:#{ticket_id}"
      end
      FileUtils.rm_rf("tmp/#{@ticket['id']}") if File.directory? "tmp/#{@ticket['id']}"
    end

    def self.add_comment(ticket_id)
      total_count = 0
      count = 0
      @ticket['journals'].each { |x| total_count += 1 unless x.fetch('notes', {}).empty? }
      @ticket['journals'].each.with_index do |comment, index|
        next if comment['notes'].nil? || comment['notes'].empty?
        count += 1
        uri = URI.parse("https://livelinktech.atlassian.net/rest/api/2/issue/#{ticket_id}/comment")
        https = Net::HTTP.new(uri.host, uri.port)
        https.use_ssl = true
        req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
        req['Authorization'] = "Basic #{@auth64}"
        req.body = @parse_data.get_comments(comment)
        res = https.request(req)
        puts "Comment #{count} of #{total_count} added to Jira ticket:#{ticket_id}"
      end
    end
  end
end
