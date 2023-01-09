# frozen_string_literal: true
require "highline/import"

module SystemHelpers
  def pause_test
    result =
      ask(
        "\n\e[33mTest paused, press enter to resume, type `d` and press enter to start debugger.\e[0m",
      )
    binding.pry if result == "d" # rubocop:disable Lint/Debugger
    self
  end

  def sign_in(user)
    visit "/session/#{user.encoded_username}/become.json?redirect=false"
  end

  def sign_out
    delete "/session"
  end

  def setup_system_test
    SiteSetting.login_required = false
    SiteSetting.content_security_policy = false
    SiteSetting.force_hostname = Capybara.server_host
    SiteSetting.port = Capybara.server_port
    SiteSetting.external_system_avatars_enabled = false
    SiteSetting.disable_avatar_education_message = true
  end

  def try_until_success(timeout: 2, frequency: 0.01)
    start ||= Time.zone.now
    backoff ||= frequency
    yield
  rescue RSpec::Expectations::ExpectationNotMetError
    raise if Time.zone.now >= start + timeout.seconds
    sleep backoff
    backoff += frequency
    retry
  end

  def resize_window(width: nil, height: nil)
    original_size = page.driver.browser.manage.window.size
    page.driver.browser.manage.window.resize_to(
      width || original_size.width,
      height || original_size.height,
    )
    yield
  ensure
    page.driver.browser.manage.window.resize_to(original_size.width, original_size.height)
  end

  def using_browser_timezone(timezone, &example)
    previous_browser_timezone = ENV["TZ"]

    ENV["TZ"] = timezone

    Capybara.using_session(timezone) { freeze_time(&example) }

    ENV["TZ"] = previous_browser_timezone
  end
end
