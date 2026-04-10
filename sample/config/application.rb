require_relative "boot"

require "rails/all"

# Eager-load all gems listed in the Gemfile.
Bundler.require(*Rails.groups)

module PhlexedSample
  class Application < Rails::Application
    config.load_defaults 8.0

    config.autoload_paths << Rails.root.join("app/components")
    config.autoload_paths << Rails.root.join("app/views")

    # Phlex conventions — view classes live under app/views/
    config.generators do |g|
      g.template_engine :phlex
      g.test_framework :rspec
    end
  end
end
