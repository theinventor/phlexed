# frozen_string_literal: true

# The sample keeps phlexy_ui in Gemfile.lock so phlexed can exercise real
# library detection and registry building. PhlexyUI 0.1.5+ uses anonymous block
# forwarding syntax that Ruby 3.3 cannot parse when component files autoload, so
# rendering this fixture uses a tiny local compatibility layer instead.
require "phlex"

module PhlexyUIRuntimeFixture
  module_function

  def install!
    raise "phlexy_ui must be loaded before installing the runtime fixture" unless defined?(PhlexyUI)

    replace(:Card, card_class)
    replace(:CardTitle, card_title_class)
    replace(:CardBody, card_body_class)
    replace(:CardActions, card_actions_class)
    replace(:Button, button_class)
  end

  def replace(name, component_class)
    PhlexyUI.send(:remove_const, name) if PhlexyUI.const_defined?(name, false)
    PhlexyUI.const_set(name, component_class)
  end

  def base_class
    @base_class ||= Class.new(Phlex::HTML) do
      private

      def class_names(*values)
        values.flatten.compact.flat_map { |value| value.to_s.split }.reject(&:empty?).uniq.join(" ")
      end

      def attrs_with_classes(attributes, *classes)
        attributes.merge(class: class_names(classes, attributes[:class]))
      end
    end
  end

  def card_class
    Class.new(base_class) do
      def initialize(bordered: false, compact: false, variant: nil, **attributes)
        @attributes = attrs_with_classes(
          attributes,
          "card",
          "bg-base-100",
          ("card-bordered" if bordered),
          ("card-compact" if compact),
          ("card-#{variant}" if variant)
        )
      end

      def view_template(&content)
        div(**@attributes) { content.call if content }
      end
    end
  end

  def card_title_class
    Class.new(base_class) do
      def initialize(**attributes)
        @attributes = attrs_with_classes(attributes, "card-title")
      end

      def view_template(&content)
        h2(**@attributes) { content.call if content }
      end
    end
  end

  def card_body_class
    Class.new(base_class) do
      def initialize(**attributes)
        @attributes = attrs_with_classes(attributes, "card-body")
      end

      def view_template(&content)
        div(**@attributes) { content.call if content }
      end
    end
  end

  def card_actions_class
    Class.new(base_class) do
      def initialize(justify: nil, **attributes)
        @attributes = attrs_with_classes(attributes, "card-actions", justify_class(justify))
      end

      def view_template(&content)
        div(**@attributes) { content.call if content }
      end

      private

      def justify_class(value)
        return unless value

        "justify-#{value.to_s.tr("_", "-")}"
      end
    end
  end

  def button_class
    Class.new(base_class) do
      def initialize(as: :button, variant: nil, size: nil, href: nil, type: nil, **attributes)
        @tag_name = as.to_sym
        @tag_name = :button if @tag_name == :submit

        attributes[:href] = href if href
        attributes[:type] = type || "submit" if as.to_sym == :submit
        attributes[:type] ||= "button" if @tag_name == :button

        @attributes = attrs_with_classes(
          attributes,
          "btn",
          ("btn-#{variant}" if variant),
          ("btn-#{size}" if size)
        )
      end

      def view_template(&content)
        public_send(@tag_name, **@attributes) { content.call if content }
      end
    end
  end
end

PhlexyUIRuntimeFixture.install!
