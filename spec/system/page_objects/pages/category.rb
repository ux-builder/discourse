# frozen_string_literal: true

module PageObjects
  module Pages
    class Category < PageObjects::Pages::Base
      # keeping the various category related features combined for now

      def visit(category)
        page.visit("/c/#{category.id}")
        self
      end

      def visit_settings(category)
        page.visit("/c/#{category.slug}/edit/settings")
        self
      end

      def back_to_category
        find(".edit-category-title-bar span", text: "Back to category").click
        self
      end

      def save_settings
        find("#save-category").click
        self
      end

      def toggle_setting(setting, text = "")
        find(".edit-category-tab .#{setting} label.checkbox-label", text: text).click
        self
      end
    end
  end
end
