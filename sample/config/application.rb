require_relative "boot"

require "rails/all"

# Eager-load all gems listed in the Gemfile.
Bundler.require(*Rails.groups)

module PhlexedSample
  class Application < Rails::Application
    config.load_defaults 8.0
    config.eager_load = false

    # The fixture does not ship a full asset pipeline, but tailwindcss-rails
    # expects these config hooks during Rails initialization.
    config.assets = ActiveSupport::OrderedOptions.new
    config.assets.precompile = []

    config.autoload_paths << Rails.root.join("app/components")
    config.autoload_paths << Rails.root.join("app/views")

    initializer "phlexed_sample.views_base", before: :set_autoload_paths do |app|
      app.autoloaders.main.ignore(app.root.join("app/views/base.rb"))
      require app.root.join("app/views/base").to_s
    end

    # Phlex conventions — view classes live under app/views/
    config.generators do |g|
      g.template_engine :phlex
      g.test_framework :rspec
    end
  end
end
