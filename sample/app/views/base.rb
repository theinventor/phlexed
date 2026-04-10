module Views
  # Base class for all Phlex views in this project.
  # Wraps Phlex::HTML and exposes Rails helpers.
  class Base < Phlex::HTML
    include Phlex::Rails::Helpers::Routes
    include Phlex::Rails::Helpers::CSRFMetaTags
    include Phlex::Rails::Helpers::CSPMetaTag
    include Phlex::Rails::Helpers::StylesheetLinkTag
    include Phlex::Rails::Helpers::LinkTo
    include Phlex::Rails::Helpers::ImageTag
    include Phlex::Rails::Helpers::FormWith
  end
end
