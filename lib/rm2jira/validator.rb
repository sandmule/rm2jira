module RM2Jira
  class Validator
    include Logging

    USER = 'redmine-xfer@livelinktechnology.net'.freeze
    PASS = ENV['PASS']
    @auth64 = Base64.strict_encode64("#{USER}:#{PASS}")

    def self.search_jira_for_rm_id(redmine_id)
      search_body = {
          jql: "project = #{$jira_project} AND 'Redmine ID' = #{redmine_id}",
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

      begin
        res = https.request(req)
        response_body = JSON.parse(res.body)
      rescue
        logger.info "failed to search for ticket:#{redmine_id}, retrying"
        sleep 1
        retry
      end
      if response_body['total'] >= 1
        ticket = Redmine.download_ticket(redmine_id)
        validate_data(ticket, response_body['issues'][0]['id'])
        logger.info "ticket:#{redmine_id} already exists and validated in jira - skipping"
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
      begin
        @jira_ticket = JSON.parse(http.request(req).body)['fields']
      rescue JSON::ParserError
        logger.info "Validation failed for #{@rm_ticket['id']}, retrying"
        sleep 1
        retry
      end
      case @jira_ticket['issuetype']['id']
      when '10001'
        unless story_validate(@jira_ticket)[:result]
          logger.error story_validate(@jira_ticket)[:error]
          logger.error "Jira:#{jira_id}, Redmine:#{@rm_ticket['id']} Ticket was unable to be validated - aborting"
          delete_issue(jira_id)
          abort
        end
      when '10004'
        unless bug_validate(@jira_ticket)[:result]
          logger.error bug_validate(@jira_ticket)[:error]
          logger.error "Jira:#{jira_id}, Redmine:#{@rm_ticket['id']} Ticket was unable to be validated - aborting"
          delete_issue(jira_id)
          abort
        end
      else
        logger.fatal "Unknown ticket type for ticket: #{@rm_ticket['id']}"
        return false
      end
      true
    end

    def self.story_validate(data) #this has to be the most hacky thing I've ever done. Surely I'm missing something simple here!
      return { result: false, error: "#{data['summary']} didn't match #{@rm_ticket['subject']}"} unless data['summary'] == @rm_ticket['subject']
      return { result: false, error: "#{data['customfield_10060']} didn't match see Redmine Description"} unless data['customfield_10060'] == 'see Redmine Description'
      return { result: false, error: "#{data['customfield_10058']} didn't match see Redmine Description"} unless data['customfield_10058'] == 'see Redmine Description'
      return { result: false, error: "#{data['customfield_10055']} didn't match #{@rm_ticket['id']}"} unless data['customfield_10055'] == @rm_ticket['id']
      return { result: false, error: "#{data['customfield_10056']} didn't match #{@rm_ticket['project']['name']}"} unless data['customfield_10056'] == @rm_ticket['project']['name']
      return { result: false, error: "#{data['priority']['name']} didn't match #{get_priority[@rm_ticket['priority']['name']]}"} unless data['priority']['name'] == get_priority[@rm_ticket['priority']['name']]
      return { result: false, error: "#{data['components'][0]['name']} didn't match #{get_component[@rm_ticket['project']['name']]}"} unless data['components'][0]['name'] == get_component[@rm_ticket['project']['name']]
      return { result: false, error: "#{data['customfield_10102']} didn't match #{get_description}"} unless data['customfield_10102'] == get_description
      return { result: false, error: "#{data['reporter']['name']} didn't match #{get_name} or redmine-xfer"} unless data['reporter']['name'] == get_name || data['reporter']['name'] == 'redmine-xfer'
      return { result: false, error: "comments didn't match" } unless validate_comments(@jira_ticket)
      return { result: false, error: "attachments didn't match" } unless validate_attachments(@jira_ticket)
      { result: true }
    end

    def self.bug_validate(data)
      return { result: false, error: "#{data['summary']} didn't match #{@rm_ticket['subject']}"} unless data['summary'] == @rm_ticket['subject']
      return { result: false, error: "#{data['customfield_10055']} didn't match #{@rm_ticket['id']}"} unless data['customfield_10055'] == @rm_ticket['id']
      return { result: false, error: "#{data['customfield_10056']} didn't match #{@rm_ticket['project']['name']}"} unless data['customfield_10056'] == @rm_ticket['project']['name']
      return { result: false, error: "#{data['priority']['name']} didn't match #{get_priority[@rm_ticket['priority']['name']]}"} unless data['priority']['name'] == get_priority[@rm_ticket['priority']['name']]
      return { result: false, error: "#{data['components'][0]['name']} didn't match #{get_component[@rm_ticket['project']['name']]}"} unless data['components'][0]['name'] == get_component[@rm_ticket['project']['name']]
      return { result: false, error: "#{data['description']} didn't match #{get_description}"} unless data['description'] == get_description
      return { result: false, error: "#{data['reporter']['name']} didn't match #{get_name} or redmine-xfer"} unless data['reporter']['name'] == get_name || data['reporter']['name'] == 'redmine-xfer'
      return { result: false, error: "comments didn't match" } unless validate_comments(@jira_ticket)
      return { result: false, error: "attachments didn't match" } unless validate_attachments(@jira_ticket)
      { result: true }
    end

    def self.validate_comments(data)
      return true if @rm_ticket['journals'].empty?
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
      return true if @rm_ticket['attachments'].empty?
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
        'Content Release'  => 'Content Release',
        'Site Changes'     => 'Site Changes',
        'Item Setup'       => 'Item Setup',
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
      relations = ''

      unless @rm_ticket['children'].nil?
        @rm_ticket['children'].each do |sub_task|
          sub_tasks << "plan.io ##{sub_task['id']} : #{sub_task['subject']}\n"
        end
      end

      unless @rm_ticket['relations'].nil?
        @rm_ticket['relations'].each do |relation|
          relations << "#{relations_hash(relation)[relation['id']]}\n"
        end
      end

      ticket_name = @rm_ticket['assigned_to'].nil? ? 'Unassigned' : @rm_ticket['assigned_to']['name']
      sub_tasks_string = "Redmine Subtasks:\n#{sub_tasks}"
      parent_string = @rm_ticket['parent'].nil? ? nil : "Redmine Parent ID: plan.io ##{@rm_ticket['parent']['id']}"
      relations_string = "Redmine Relations:\n#{relations}"

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
      "#{parent_string}\n"\
      "#{sub_tasks_string unless sub_tasks.empty?}"\
      "#{relations_string unless relations.empty?}"
    end

    def self.get_name
      return 'redmine-xfer' if @rm_ticket['author']['name'].split.count == 1
      return @rm_ticket['author']['name'] if @rm_ticket['author']['name'] == 'redmine-xfer' # api name
      name = @rm_ticket['author']['name'].downcase.split
      first_initial = name[0][0]
      surname = name[1]
      first_initial + '.' + surname
    end

    def self.relations_hash(relation)
      {
        1466 => "Related to plan.io ##{relation['issue_to_id']}",
        1467 => "Duplicates plan.io ##{relation['issue_to_id']}",
        1468 => "Duplicated by plan.io ##{relation['issue_id']}",
        1470 => "Blocks plan.io ##{relation['issue_to_id']}",
        1471 => "Blocked by plan.io ##{relation['issue_id']}",
        1472 => "Precedes plan.io ##{relation['issue_to_id']}",
        1473 => "Follows plan.io ##{relation['issue_id']}",
        1474 => "Copied from plan.io ##{relation['issue_id']}",
        1475 => "Copied to plan.io ##{relation['issue_to_id']}",
      }
    end

    def self.delete_issue(issue_id)
      uri = URI.parse("https://livelinktech.atlassian.net/rest/api/2/issue/#{issue_id}")
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true
      req = Net::HTTP::Delete.new(uri.path, 'Content-Type' => 'application/json')
      req['Authorization'] = "Basic #{@auth64}"
      res = https.request(req)
      if res.code == '204'
        logger.info "Ticket:#{issue_id} deleted successfully"
      else
        logger.fatal "unable to delete unvalidated ticket:#{issue_id}"
        abort
      end
      true
    end
  end
end
