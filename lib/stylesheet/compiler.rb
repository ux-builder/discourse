# frozen_string_literal: true

require 'stylesheet/importer'

module Stylesheet

  class Compiler
    ASSET_ROOT = "#{Rails.root}/app/assets/stylesheets" unless defined? ASSET_ROOT

    def self.compile_asset(asset, options = {})
      importer = Importer.new(options)
      file = importer.prepended_scss

      if Importer::THEME_TARGETS.include?(asset.to_s)
        filename = "theme_#{options[:theme_id]}.scss"
        file += options[:theme_variables].to_s
        file += importer.theme_import(asset)
      elsif plugin_assets = Importer.plugin_assets[asset.to_s]
        filename = "#{asset.to_s}.scss"
        options[:load_paths] = [] if options[:load_paths].nil?
        plugin_assets.each do |src|
          file += File.read src
          options[:load_paths] << File.expand_path(File.dirname(src))
        end
      else
        filename = "#{asset}.scss"
        path = "#{ASSET_ROOT}/#{filename}"
        file += File.read path

        case asset.to_s
        when "embed", "publish"
          file += importer.font
        when "wizard"
          file += importer.wizard_fonts
        when Stylesheet::Manager::COLOR_SCHEME_STYLESHEET
          file += importer.import_color_definitions
          file += importer.import_wcag_overrides
          file += importer.category_backgrounds
          file += importer.font
        end
      end

      compile(file, filename, options)
    end

    def self.compile(stylesheet, filename, options = {})
      source_map_file = options[:source_map_file] || "#{filename.sub(".scss", "")}.css.map"

      load_paths = [ASSET_ROOT]
      load_paths += options[:load_paths] if options[:load_paths]

      engine = SassC::Engine.new(stylesheet,
                                 filename: filename,
                                 style: :compressed,
                                 source_map_file: source_map_file,
                                 source_map_contents: true,
                                 theme_id: options[:theme_id],
                                 theme: options[:theme],
                                 theme_field: options[:theme_field],
                                 color_scheme_id: options[:color_scheme_id],
                                 load_paths: load_paths)

      result = engine.render

      if options[:rtl]
        [rtlify_css(result) || result, nil]
      else
        source_map = engine.source_map
        source_map.force_encoding("UTF-8")

        [result, source_map]
      end
    end

    def self.rtlify_css(src_css)
      @context ||= begin
        context = MiniRacer::Context.new
        context.eval(File.read("#{Rails.root}/app/assets/javascripts/rtlcss-miniracer/dist/main.js"))
        context
      end
      @context.eval("rtlcss.default.process(#{src_css.inspect})")
    rescue MiniRacer::RuntimeError
      nil
    end
  end
end
