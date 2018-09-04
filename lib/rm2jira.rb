require 'net/https'
require 'uri'
require 'json'
require 'rubygems'
require 'pp'
require 'thor'
require 'pry'
require 'Base64'
require 'rm2jira/jira'
require 'rm2jira/redmine'
require 'rm2jira/parse_data'
require 'rm2jira/validator'

module RM2Jira
  class CLI < Thor
    def initialize(*args)
      super
      @projects = RM2Jira::Redmine.new.projects
    end

    desc "list_projects", "lists available projects"
    def list_projects
      @projects.each_key { |x| puts x }
    end

    desc "migrate_tickets [project_name] (ticket_id)", "migrates tickets from redmine to jira. if restarting the application use last ticket id"
    def migrate_tickets(project_name, ticket_id = 0)
      ticket_ids = RM2Jira::Redmine.get_issue_ids(RM2Jira::Redmine.new.projects[project_name])
      RM2Jira::Redmine.get_issues(ticket_ids, ticket_id)
    end

    desc "upload_single_ticket [ticket_id]", "migrates a single tickets from redmine to jira(mainly used for test purposes)"
    def upload_single_ticket(ticket_id)
      RM2Jira::Redmine.upload_single_ticket(ticket_id)
    end

    desc "download_pdfs [project_name] (ticket_id)", 'downloads pdfs from redmine. if restarting the application use last ticket id'
    def download_pdfs(project_name, ticket_id = 0)
      RM2Jira::Redmine::PDF.download_pdfs(project_name, ticket_id = 0)
    end
  end
end
