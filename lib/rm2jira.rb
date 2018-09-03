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

    desc "migrate_tickets [project_name]", "migrates tickets from redmine to jira"
    def migrate_tickets(project_name)
      ticket_ids = RM2Jira::Redmine.get_issue_ids(RM2Jira::Redmine.new.projects[project_name])
      RM2Jira::Redmine.get_issues(ticket_ids)
    end
  end
end
