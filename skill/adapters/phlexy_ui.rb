#!/usr/bin/env ruby
# frozen_string_literal: true

# phlexed adapter: PhlexyUI
# Scans the PhlexyUI gem source to extract component metadata.
# Usage: ruby phlexy_ui.rb <gem_path> [output_path]
#   gem_path   — path to the phlexy_ui gem (from `bundle show phlexy_ui`)
#   output_path — where to write registry JSON (default: .phlexed/registry.json)

require "json"
require "pathname"

gem_path = ARGV[0]
output_path = ARGV[1] || ".phlexed/registry.json"

unless gem_path && Dir.exist?(gem_path)
  warn "Usage: ruby phlexy_ui.rb <gem_path> [output_path]"
  warn "  gem_path must be a valid directory (get it from: bundle show phlexy_ui)"
  exit 1
end

component_dir = File.join(gem_path, "lib", "phlexy_ui")
unless Dir.exist?(component_dir)
  warn "error: Cannot find lib/phlexy_ui/ in #{gem_path}"
  exit 1
end

# Read gem version. Two sources, in order:
#   1. A quoted literal in the gemspec (e.g. `s.version = "0.1.0"`)
#   2. A constant reference to lib/phlexy_ui/version.rb (e.g. `s.version = PhlexyUI::VERSION`,
#      where version.rb defines `VERSION = "0.3.1"`)
# Real PhlexyUI gemspecs use the constant form, so (2) is the common path.
version = "unknown"
gemspec = Dir.glob(File.join(gem_path, "*.gemspec")).first
if gemspec
  content = File.read(gemspec)
  if content =~ /\.version\s*=\s*["']([^"']+)["']/
    version = $1
  end
end

if version == "unknown"
  version_file = File.join(gem_path, "lib", "phlexy_ui", "version.rb")
  if File.exist?(version_file)
    vcontent = File.read(version_file)
    if vcontent =~ /VERSION\s*=\s*["']([^"']+)["']/
      version = $1
    end
  end
end

# Skip these files — they're not components
SKIP_FILES = %w[base.rb version.rb].freeze

# Semantic color variants. Preferred over utility modifiers when choosing an
# example variant, because e.g. Button's `variant: :primary` is more illustrative
# than Button's alphabetically-first `variant: :no_animation`.
SEMANTIC_VARIANTS = %w[primary secondary accent info success warning error neutral].freeze

# Parse a single component file
def parse_component(filepath)
  source = File.read(filepath)
  filename = File.basename(filepath, ".rb")

  # Extract class name
  class_match = source.match(/class\s+(\w+)\s*<\s*(?:Base|Phlex::HTML)/)
  return nil unless class_match

  class_name = class_match[1]
  full_class = "PhlexyUI::#{class_name}"

  # Extract modifiers from register_modifiers
  modifiers = []
  source.scan(/register_modifiers\(([^)]+)\)/m) do |match|
    block = match[0]
    # Each modifier is a key: "value" pair
    block.scan(/(\w+):\s*["']([^"']+)["']/) do |key, _css_class|
      modifiers << key.to_s
    end
  end

  # Extract initialize params (as: default, and any keyword args)
  props = []
  init_match = source.match(/def\s+initialize\(([^)]*)\)/m)
  if init_match
    params = init_match[1]
    # Extract keyword arguments (name: default)
    params.scan(/(\w+):\s*/) do |param|
      name = param[0]
      next if name == "base_modifiers" # internal
      props << name
    end
  end

  # Extract component HTML class (maps to DaisyUI class).
  # Real PhlexyUI source uses a symbol: `component_html_class: :btn`.
  # Older/docs examples may use a string: `component_html_class: "btn"`.
  # Match either form.
  html_class = nil
  html_class_match = source.match(/component_html_class:\s*(?:["']([^"']+)["']|:(\w+))/)
  html_class = (html_class_match[1] || html_class_match[2]) if html_class_match

  # Extract the element tag (as: :div default)
  default_tag = "div"
  as_match = source.match(/as:\s*:(\w+)/)
  default_tag = as_match[1] if as_match

  # Separate modifiers into variants and sizes
  variants = modifiers.select { |m| !m.match?(/xs|sm|md|lg|xl/) }
  sizes = modifiers.select { |m| m.match?(/xs|sm|md|lg|xl/) }

  # Build example usage. Prefer a semantic color variant (primary, secondary, accent,
  # info, success, warning, error, neutral) over utility modifiers (no_animation,
  # glass, wide, block, etc.) so the generated example is representative.
  # Falls back to the first variant if no semantic match exists.
  #
  # Order matters: `SEMANTIC_VARIANTS & variants` returns elements in SEMANTIC_VARIANTS
  # order (so :primary wins over :neutral when both are present). The reverse order
  # (`variants & SEMANTIC_VARIANTS`) would pick whichever semantic variant happened to
  # appear first in the component source, which for Button gives `:neutral` — correct
  # but not the canonical Rails UI example.
  example_variant = (SEMANTIC_VARIANTS & variants).first || variants.first
  example_props = []
  example_props << "variant: :#{example_variant}" if example_variant
  example = "render #{full_class}.new#{example_props.any? ? "(#{example_props.join(', ')})" : ''} { \"#{class_name}\" }"

  {
    name: class_name,
    class: full_class,
    file: filename,
    html_class: html_class,
    default_tag: default_tag,
    props: props.uniq,
    modifiers: modifiers,
    variants: variants,
    sizes: sizes,
    example: example
  }
end

# Categorize components into pattern groups
def categorize(components)
  categories = {
    layout: %w[Card Drawer Footer Hero Navbar Stack Artboard],
    forms: %w[Input Select Checkbox Radio Textarea Toggle Range FileInput],
    feedback: %w[Alert Toast Badge Tooltip Loading Progress],
    navigation: %w[Breadcrumb BottomNavigation Menu Tabs Link Steps Pagination],
    display: %w[Avatar Carousel Collapse Stat Table Timeline Countdown Diff],
    actions: %w[Button Dropdown Modal Swap],
    data_input: %w[Rating],
    mockup: %w[MockupBrowser MockupCode MockupPhone MockupWindow]
  }

  result = {}
  component_names = components.map { |c| c[:name] }

  categories.each do |category, expected_names|
    matched = expected_names & component_names
    result[category.to_s] = matched if matched.any?
  end

  # Catch any uncategorized
  all_categorized = categories.values.flatten
  uncategorized = component_names - all_categorized
  result["other"] = uncategorized if uncategorized.any?

  result
end

# Scan all component files
component_files = Dir.glob(File.join(component_dir, "*.rb"))
  .reject { |f| SKIP_FILES.include?(File.basename(f)) }
  .sort

components = component_files.filter_map { |f| parse_component(f) }

registry = {
  library: "phlexy_ui",
  version: version,
  generated_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
  component_count: components.size,
  components: components,
  patterns: categorize(components)
}

# Write output
output_dir = File.dirname(output_path)
Dir.mkdir(output_dir) unless Dir.exist?(output_dir)

File.write(output_path, JSON.pretty_generate(registry))
puts "Registry written to #{output_path} (#{components.size} components)"
