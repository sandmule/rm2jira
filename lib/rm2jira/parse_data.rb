module RM2Jira
  class ParseData
    def initialize(ticket)
      @ticket = ticket
      @attachment = @ticket['attachments'].empty?
    end

    def get_body(changed_name = nil)
      @changed_name = changed_name
      case @ticket['tracker']['name']
      when 'Defect'
        get_bug_body
      when 'Task'
        get_story_body
      when 'Enhancement'
        get_story_body
      else
        puts 'error in parse data finding issue type'
      end
    end

    def get_story_body
      body = {
        fields: {
          project:
          {
             id: "10016"
          },
          summary: @ticket['subject'],
          assignee: {
            name: get_assignee_name
          },
          reporter: {
            name: get_name
          },
          priority: {
            name: get_priority[@ticket['priority']['name']]
          },
          customfield_10060: 'see Redmine Description',
          customfield_10058: 'see Redmine Description',
          customfield_10055: @ticket['id'],
          customfield_10056: @ticket['project']['name'],
          customfield_10102: get_description,
          customfield_10103: @ticket.fetch('fixed_version', {})['name'],
          components: [{
            name: get_component[@ticket['project']['name']]
          }],
          issuetype: {
            id: issue_types(@ticket['tracker']['name'])
          }
        }
     }

     body[:transition]= {id: get_status[@ticket['status']['name']]} unless get_status[@ticket['status']['name']] == '0'
     body.to_json
    end

    def get_bug_body
      body = {
       fields: {
         project:
         {
            id: "10016"
         },
         summary: @ticket['subject'],
         description: get_description,
         assignee: {
           name: get_assignee_name
         },
         reporter: {
           name: get_name
         },
         priority: {
           name: get_priority[@ticket['priority']['name']]
         },
         customfield_10055: @ticket['id'],
         customfield_10056: @ticket['project']['name'],
         components: [{
           name: get_component[@ticket['project']['name']]
         }],
         issuetype: {
           id: issue_types(@ticket['tracker']['name'])
         }
       }
     }

     body[:transition]= {id: get_status[@ticket['status']['name']]} unless get_status[@ticket['status']['name']] == '0'
     body.to_json
    end

    def get_name
      return 's.salter' if @ticket['author']['name'].split.count == 1
      return @ticket['author']['name'] if @ticket['author']['name'] == 's.salter' # api name
      name = @ticket['author']['name'].downcase.split
      first_initial = name[0][0]
      surname = name[1]
      first_initial + '.' + surname
    end

    def get_assignee_name
      return '' if @ticket['assigned_to'].nil?
      return 's.salter' if @ticket['assigned_to']['name'].split.count == 1
      return @ticket['assigned_to']['name'] if @ticket['assigned_to']['name'] == 's.salter' # api name
      name = @ticket['assigned_to']['name'].downcase.split
      first_initial = name[0][0]
      surname = name[1]
      first_initial + '.' + surname
    end

    def get_description
      sub_tasks = ''
      unless @ticket['children'].nil?
        @ticket['children'].each do |sub_task|
          sub_tasks << "plan.io ##{sub_task['id']}:#{sub_task['subject']}\n"
        end
      end

      ticket_name = @ticket['assigned_to'].nil? ? 'Unassigned' : @ticket['assigned_to']['name']
      sub_tasks_string = "Redmine Subtasks:\n#{sub_tasks}"

      unless @changed_name
        author_string = "Redmine Author: #{@ticket['author']['name']}"
        assignee_string = "Redmine Assigned: #{ticket_name}"
      else
        author_string = "Redmine Author: #{@changed_name[:author].nil? ? @ticket['author']['name'] : @changed_name[:author]}"
        assignee_string = "Redmine Assigned: #{@changed_name[:assignee].nil? ? ticket_name : @changed_name[:assignee]}"
      end

      "#{@ticket['description']}\n\n"\
      "Migration metadata\n\n"\
      "#{author_string} \n"\
      "#{assignee_string} \n"\
      "Redmine Created at: #{Time.parse(@ticket['created_on']).strftime("%y-%m-%-e %H:%M")}\n"\
      "Redmine Updated at: #{Time.parse(@ticket['updated_on']).strftime("%y-%m-%-e %H:%M")}\n"\
      "#{sub_tasks_string unless sub_tasks.empty?}"
    end

    def get_comment_name(comment_name)
      return comment_name if comment_name == 's.salter' # api name
      name = comment_name.downcase.split
      first_initial = name[0][0]
      surname = name[1]
      first_initial + '.' + surname
    end

    def get_priority
      {
        'Low'       => 'Low',
        'Normal'    => 'Medium',
        'High'      => 'High',
        'Urgent'    => 'High',
        'Immediate' => 'Highest'
      }
    end

    def issue_types(ticket_type)
      redmine_issues = { 'Task'        => :Story,
                         'Enhancement' => :Story,
                         'Defect'      => :Bug
                       }
      jira_issues = { Story:    '10001',
                      Support:  '10010',
                      Bug:      '10004',
                      Subtask:  '10003',
                      Epic:     '10000',
                      StoryBug: '10011'
                    }
      jira_issues[redmine_issues[ticket_type]]
    end

    def get_comments(comment)
      message = "#{comment['user']['name']} at: #{Time.parse(comment['created_on']).strftime("%y-%m-%-e %H:%M")} commented: #{comment['notes']}"
      { body: message }.to_json
    end

    def get_component
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

    def get_status
      {
        'Open'            => '0', # needs nothing
        'Pending'         => '0',
        'For Discussion'  => '0',
        'Blocked'         => '51',
        'in Progress'     => '41',
        'Feedback'        => '61',
        'Code Review'     => '61',
        'Awaiting Review' => '61',
        'Internal QA'     => '171',
        'QA'              => '171',
        'Documentation'   => '101',
        'Closed'          => '101',
        'Merged'          => '181',
        'Reopened'        => '0',
        'Rejected'        => '201'
      }
    end
  end
end
