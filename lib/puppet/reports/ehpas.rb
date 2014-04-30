require 'puppet'
require 'pp'

require 'net/smtp'
require 'time'

Puppet::Reports.register_report(:ehpas) do
  desc "Process reports in EHPAS format
    based on the prescense of 'ehpas' tag in the log messages.
    Hacking up the tagmail report processor to suit our purposes."

  emails = 'jeremy@puppetlabs.com'
  taglists = ['ehpas']

  # Find all matching messages.
  def match(taglists)
    matching_logs = []
    taglists.each do |emails, pos, neg|
      # First find all of the messages matched by our positive tags
      messages = nil
      if pos.include?("all")
        messages = self.logs
      else
        # Find all of the messages that are tagged with any of our
        # tags.
        messages = self.logs.find_all do |log|
          pos.detect { |tag| log.tagged?(tag) }
        end
      end

      # Now go through and remove any messages that match our negative tags
      messages = messages.reject do |log|
        true if neg.detect do |tag| log.tagged?(tag) end
      end

      if messages.empty?
        Puppet.info "No messages to report to #{emails.join(",")}"
        next
      else
        matching_logs << [emails, messages.collect { |m| m.to_report }.join("\n")]
      end
    end

    matching_logs
  end

  # Process the report.  This just calls the other associated messages.
  def process
    unless Puppet::FileSystem.exist?(Puppet[:tagmap])
      Puppet.notice "Cannot send tagmail report; no tagmap file #{Puppet[:tagmap]}"
      return
    end

    metrics = raw_summary['resources'] || {} rescue {}

    if metrics['out_of_sync'] == 0 && metrics['changed'] == 0
      Puppet.notice "Not sending tagmail report; no changes"
      return
    end

    taglists = parse(File.read(Puppet[:tagmap]))

    # Now find any appropriately tagged messages.
    reports = match(taglists)

    send(reports) unless reports.empty?
  end

  # Send the email reports.
  def send(reports)
    pid = Puppet::Util.safe_posix_fork do
      if Puppet[:smtpserver] != "none"
        begin
          Net::SMTP.start(Puppet[:smtpserver], Puppet[:smtpport], Puppet[:smtphelo]) do |smtp|
            reports.each do |emails, messages|
              smtp.open_message_stream(Puppet[:reportfrom], *emails) do |p|
                p.puts "From: #{Puppet[:reportfrom]}"
                p.puts "Subject: Puppet Report for #{self.host}"
                p.puts "To: " + emails.join(", ")
                p.puts "Date: #{Time.now.rfc2822}"
                p.puts
                p.puts messages
              end
            end
          end
        rescue => detail
          message = "Could not send report emails through smtp: #{detail}"
          Puppet.log_exception(detail, message)
          raise Puppet::Error, message, detail.backtrace
        end
      elsif Puppet[:sendmail] != ""
        begin
          reports.each do |emails, messages|
            # We need to open a separate process for every set of email addresses
            IO.popen(Puppet[:sendmail] + " " + emails.join(" "), "w") do |p|
              p.puts "From: #{Puppet[:reportfrom]}"
              p.puts "Subject: Puppet Report for #{self.host}"
              p.puts "To: " + emails.join(", ")
              p.puts
              p.puts messages
            end
          end
        rescue => detail
          message = "Could not send report emails via sendmail: #{detail}"
          Puppet.log_exception(detail, message)
          raise Puppet::Error, message, detail.backtrace
        end
      else
        raise Puppet::Error, "SMTP server is unset and could not find sendmail"
      end
    end

    # Don't bother waiting for the pid to return.
    Process.detach(pid)
  end
end
