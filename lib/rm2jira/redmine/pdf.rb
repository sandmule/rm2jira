require 'fileutils'

module RM2Jira
  class Redmine
    class PDF
      include Logging
      API_KEY = ENV['API_KEY']

      def self.download_pdfs(issue_ids, start_at = 0)
        start_at = start_at.to_i
        id_hash = {}
        issue_ids.each.with_index do |value, index|
          id_hash.merge!(value => index)
        end

        @total_count = issue_ids.count - (start_at = start_at.zero? ? 0 : id_hash[start_at])
        bar = ProgressBar.new(@total_count)
        logger.info "#{@total_count} tickets to migrate"
        issue_ids.drop(id_hash[start_at.to_i] || 0).each do |issue_id|
          # next if Validator.search_jira_for_rm_id(issue_id)
          ticket = Redmine.download_ticket(issue_id)
          download_pdf_from_ticket(ticket)
          bar.increment!
        end
      end

      def self.download_pdf_from_ticket(ticket)
        FileUtils.mkdir_p("ticket_pdfs/#{@project_name}/#{ticket['id']}") unless File.exist?("ticket_pdfs/#{@project_name}/#{ticket['id']}")
        uri = URI("https://redmine.livelink.io/issues/#{ticket['id']}.pdf")
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', verify_mode: OpenSSL::SSL::VERIFY_NONE ) do |http|
          request = Net::HTTP::Get.new(uri.request_uri)
          request['X-Redmine-API-Key'] = API_KEY
          http.request(request) do |response|
            open("ticket_pdfs/#{@project_name}/#{ticket['id']}/#{ticket['id']}.pdf", 'wb') do |file|
              file.write(response.body)
            end
          end
        end
      end
    end
  end
end
