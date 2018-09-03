module RM2Jira
  class Validator
    USER = 's.salter@livelinktechnology.net'.freeze
    PASS = ENV['PASS']
    @auth64 = Base64.strict_encode64("#{USER}:#{PASS}")

    def self.search_jira_for_rm_id(redmine_id)
      search_body = {
          jql: "project = ZREDIMP AND 'Redmine ID' = #{redmine_id}",
          startAt: 0,
          maxResults: 15,
          fields: [
              'id',
              'summary',
              'status',
              'assignee'
           ]
      }.to_json

      uri = URI.parse("https://livelinktech.atlassian.net/rest/api/2/search")
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true
      req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
      req['Authorization'] = "Basic #{@auth64}"
      req.body = search_body
      res = https.request(req)
      response_body = JSON.parse(res.body)
      if response_body['total'] >= 1
        puts "ticket:#{redmine_id} already exists in jira - skipping"
        true
      else
        false
      end
    end

    def self.validate_data(rm_ticket, jira_id, changed_name = nil)
      @changed_name = changed_name
      @rm_ticket = rm_ticket
      uri = URI("https://livelinktech.atlassian.net/rest/api/2/issue/#{jira_id}")
      req = Net::HTTP::Get.new(uri)

      req["Content-Type"] = "application/json"
      req['Authorization'] = "Basic #{@auth64}"

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      @jira_ticket = JSON.parse(http.request(req).body)['fields']

      case @jira_ticket['issuetype']['id']
      when '10001'
        unless story_validate(@jira_ticket)
          puts "Jira:#{jira_id}, Redmine:#{@rm_ticket['id']} Ticket was unable to be validated - aborting"
          result = delete_issue(jira_id)
          abort
        end
      when '10004'
        unless bug_validate(@jira_ticket)
          puts "Jira:#{jira_id}, Redmine:#{@rm_ticket['id']} Ticket was unable to be validated - aborting"
          result = delete_issue(jira_id)
          abort
        end
      else
        puts "Unknown ticket type for ticket: #{@rm_ticket['id']}"
        return false
      end

      puts "Ticket:#{jira_id} validated successfully" if result.nil?
      true
    end

    def self.story_validate(data) #this has to be the most hacky thing I've ever done. Surely I'm missing something sinmple here!
      return false unless data['summary'] == @rm_ticket['subject']
      return false unless data['customfield_10060'] == 'see Redmine Description'
      return false unless data['customfield_10058'] == 'see Redmine Description'
      return false unless data['customfield_10055'] == @rm_ticket['id']
      return false unless data['customfield_10056'] == @rm_ticket['project']['name']
      return false unless data['priority']['name'] == get_priority[@rm_ticket['priority']['name']]
      return false unless data['components'][0]['name'] == get_component[@rm_ticket['project']['name']]
      return false unless data['customfield_10102'] == get_description
      return false unless data['reporter']['name'] == get_name
      return false unless validate_comments(@jira_ticket) unless @rm_ticket['journals'].empty?
      return false unless validate_attachments(@jira_ticket) unless @rm_ticket['attachments'].empty?
      true
    end

    def self.bug_validate(data)
      return false unless data['summary'] == @rm_ticket['subject']
      return false unless data['customfield_10055'] == @rm_ticket['id']
      return false unless data['customfield_10056'] == @rm_ticket['project']['name']
      return false unless data['priority']['name'] == get_priority[@rm_ticket['priority']['name']]
      return false unless data['components'][0]['name'] == get_component[@rm_ticket['project']['name']]
      return false unless data['description'] == get_description
      return false unless data['reporter']['name'] == get_name
      return false unless validate_comments(@jira_ticket) unless @rm_ticket['journals'].empty?
      return false unless validate_attachments(@jira_ticket) unless @rm_ticket['attachments'].empty?
      true
    end

    def self.validate_comments(data)
      results = []
      data['comment']['comments'].each do |j_comment|
        @rm_ticket['journals'].each do |rm_comment|
          next if rm_comment['notes'].nil? || rm_comment['notes'].empty?
          next unless j_comment['body'] == get_comments(rm_comment)
          results << (j_comment['body'] == get_comments(rm_comment))
        end
      end
      results.include?(false) ? false : true
    end

    def self.validate_attachments(data)
      array = []
      data['attachment'].each { |x| array << x['filename'] }
      return true unless array.uniq.length == array.length
      return false unless @rm_ticket['attachments'].count == data['attachment'].count
      data['attachment'].each do |j_attachment|
        @rm_ticket['attachments'].each do |rm_attachment|
          next unless j_attachment['filename'] == rm_attachment['filename']
          return false unless j_attachment['size'] == rm_attachment['filesize']
        end
      end
      true
    end

    def self.get_priority
      {
        'Low'       => 'Low',
        'Normal'    => 'Medium',
        'High'      => 'High',
        'Urgent'    => 'High',
        'Immediate' => 'Highest'
      }
    end

    def self.get_component
      {
        'Physical Kiosk'   => 'Physical Kiosk',
        'Kiosk Apps'       => 'Physical Kiosk',
        'Kiosk Dashboard'  => 'Kiosk Dashboard',
        'Instore Team'     => 'Physical Kiosk',
        'Web Prism'        => 'Web Prism',
        'Web Development'  => 'Web Kiosk',
        'Web Kiosk'        => 'Web Kiosk',
        'QATS'             => 'QATS'
      }
    end

    def self.get_comments(comment)
      "#{comment['user']['name']} at: #{Time.parse(comment['created_on'])} commented: #{comment['notes']}"
    end

    def self.get_description
      sub_tasks = ''
      unless @rm_ticket['children'].nil?
        @rm_ticket['children'].each do |sub_task|
          sub_tasks << "plan.io ##{sub_task['id']}:#{sub_task['subject']}\n"
        end
      end

      ticket_name = @rm_ticket['assigned_to'].nil? ? 'Unassigned' : @rm_ticket['assigned_to']['name']
      sub_tasks_string = "Redmine Subtasks:\n#{sub_tasks}"

      unless @changed_name
        author_string = "Redmine Author: #{@rm_ticket['author']['name']}"
        assignee_string = "Redmine Assigned: #{ticket_name}"
      else
        author_string = "Redmine Author: #{@changed_name[:author].nil? ? @rm_ticket['author']['name'] : @changed_name[:author]}"
        assignee_string = "Redmine Assigned: #{@changed_name[:assignee].nil? ? ticket_name : @changed_name[:assignee]}"
      end

      "#{@rm_ticket['description']}\n\n"\
      "Migration metadata\n\n"\
      "#{author_string} \n"\
      "#{assignee_string} \n"\
      "Redmine Created at: #{Time.parse(@rm_ticket['created_on']).strftime("%y-%m-%-e %H:%M")}\n"\
      "Redmine Updated at: #{Time.parse(@rm_ticket['updated_on']).strftime("%y-%m-%-e %H:%M")}\n"\
      "#{sub_tasks_string unless sub_tasks.empty?}"
    end

    def self.get_name
      return 's.salter' if @rm_ticket['author']['name'].split.count == 1
      return @rm_ticket['author']['name'] if @rm_ticket['author']['name'] == 's.salter' # api name
      name = @rm_ticket['author']['name'].downcase.split
      first_initial = name[0][0]
      surname = name[1]
      first_initial + '.' + surname
    end

    def self.delete_issue(issue_id)
      uri = URI.parse("https://livelinktech.atlassian.net/rest/api/2/issue/#{issue_id}")
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true
      req = Net::HTTP::Delete.new(uri.path, 'Content-Type' => 'application/json')
      req['Authorization'] = "Basic #{@auth64}"
      res = https.request(req)
      if res.code == '204'
        puts "Ticket:#{issue_id} deleted successfully"
      else
        puts "unable to delete unvalidated ticket:#{issue_id}"
        abort
      end
      return true
    end
  end
end