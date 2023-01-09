# frozen_string_literal: true

module PageObjects
  module Pages
    class User < PageObjects::Pages::Base
      def visit(user)
        page.visit("/u/#{user.username}")
        self
      end

      def find(selector)
        page.find(".user-content-wrapper #{selector}")
      end

      def active_user_primary_navigation
        find(".user-primary-navigation li a.active")
      end

      def active_user_secondary_navigation
        find(".user-secondary-navigation li a.active")
      end

      def has_warning_messages_path?(user)
        page.has_current_path?("/u/#{user.username}/messages/warnings")
      end

      def click_staff_info_warnings_link(warnings_count: 0)
        staff_counters = page.find(".staff-counters")
        staff_counters.click_link(
          "#{warnings_count} #{I18n.t("js.user.staff_counters.warnings_received")}",
        )
        self
      end
    end
  end
end
