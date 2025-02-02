require "pathname"
require_relative "github_fetcher"
require_relative "message"

class MessageBuilder
  TEMPLATE_DIR = Pathname.new(File.join(File.dirname(__FILE__), *%w[.. templates]))

  attr_accessor :pull_requests, :report, :mood, :poster_mood

  def initialize(team)
    @team = team
  end

  def build
    if old_pull_requests.any?
      Message.new(bark_about_old_pull_requests, mood: "angry")
    elsif unapproved_pull_requests.any?
      Message.new(list_pull_requests, mood: "informative")
    else
      Message.new(no_pull_requests, mood: "approval")
    end
  end

  def rotten?(pull_request)
    today = Date.today
    actual_age = (today - pull_request[:updated]).to_i
    weekdays_age = if today.monday?
                     actual_age - 2
                   elsif today.tuesday?
                     actual_age - 1
                   else
                     actual_age
                   end
    weekdays_age > 2
  end

private

  attr_reader :team

  def pull_requests
    @pull_requests ||= GithubFetcher.new(team).list_pull_requests
  end

  def old_pull_requests
    @old_pull_requests ||= pull_requests.select { |pr| rotten?(pr) }
  end

  def unapproved_pull_requests
    @unapproved_pull_requests ||= pull_requests.reject { |pr| pr[:approved] }
  end

  def recent_pull_requests
    @recent_pull_requests ||= unapproved_pull_requests - old_pull_requests
  end

  def bark_about_old_pull_requests
    @angry_bark = present_multiple(old_pull_requests)
    @list_recent_pull_requests = present_multiple(recent_pull_requests)

    render "old_pull_requests"
  end

  def list_pull_requests
    @message = present_multiple(unapproved_pull_requests)

    render "list_pull_requests"
  end

  def no_pull_requests
    render "no_pull_requests"
  end

  def comments(pull_request)
    return " comment" if pull_request[:comments_count] == 1

    " comments"
  end

  def these(item_count)
    if item_count == 1
      "This"
    else
      "These"
    end
  end

  def pr_plural(pr_count)
    if pr_count == 1
      "pull request has"
    else
      "pull requests have"
    end
  end

  def present(pr, index)
    @index = index
    @pr = pr
    @title = pr[:title]
    @days = age_in_days(@pr)

    @thumbs_up = if (@pr[:thumbs_up]).positive?
                   " | #{@pr[:thumbs_up]} :+1:"
                 else
                   ""
                 end

    @approved = @pr[:approved] ? " | :white_check_mark: " : ""

    render "_pull_request"
  end

  def present_multiple(prs)
    prs.map.with_index(1) { |pr, n| present(pr, n) }.join("\n")
  end

  def age_in_days(pull_request)
    (Date.today - pull_request[:updated]).to_i
  end

  def days_plural(days)
    case days
    when 0
      "today"
    when 1
      "yesterday"
    else
      "#{days} days ago"
    end
  end

  def labels(pull_request)
    pull_request[:labels]
      .map { |label| "[#{label['name']}]" }
      .join(" ")
  end

  def html_encode(string)
    string.tr("&", "&amp;").tr("<", "&lt;").tr(">", "&gt;")
  end

  def apply_style(template_name)
    if team.compact
      "#{template_name}.compact"
    else
      template_name
    end
  end

  def render(template_name)
    template_file = TEMPLATE_DIR + "#{apply_style(template_name)}.text.erb"
    ERB.new(template_file.read).result(binding).strip
  end
end
