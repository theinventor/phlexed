#!/usr/bin/env ruby
# frozen_string_literal: true

# phlexed adapter: shadcn_phlexcomponents
# Scans the shadcn_phlexcomponents gem source to extract component metadata.
# Usage: ruby shadcn_phlexcomponents.rb <gem_path> [output_path]

require "json"
require "pathname"

gem_path = ARGV[0]
output_path = ARGV[1] || ".phlexed/registry.json"

unless gem_path && Dir.exist?(gem_path)
  warn "Usage: ruby shadcn_phlexcomponents.rb <gem_path> [output_path]"
  exit 1
end

# Components can be in lib/shadcn_phlexcomponents/components/ or app/components/
component_dir = File.join(gem_path, "lib", "shadcn_phlexcomponents", "components")
unless Dir.exist?(component_dir)
  # Try alternate location
  component_dir = File.join(gem_path, "app", "components")
  unless Dir.exist?(component_dir)
    warn "error: Cannot find component directory in #{gem_path}"
    exit 1
  end
end

# Read gem version
version = "unknown"
version_file = File.join(gem_path, "lib", "shadcn_phlexcomponents", "version.rb")
if File.exist?(version_file)
  content = File.read(version_file)
  if content =~ /VERSION\s*=\s*["']([^"']+)["']/
    version = $1
  end
end

SKIP_FILES = %w[base.rb version.rb configuration.rb engine.rb alias.rb].freeze

# Preferred example variants for shadcn_phlexcomponents. shadcn uses `default` as
# the canonical base variant (unlike DaisyUI/PhlexyUI which use `primary`). Fallback
# order matches shadcn's typical Button/Alert/Badge variant vocabulary.
SHADCN_SEMANTIC_VARIANTS = %w[default destructive secondary outline ghost link].freeze

# Method names that look like subcomponent factories but are actually internal
# helpers or overrides. class_variants is overridden as a private method in
# alert_dialog.rb, command.rb, date_picker.rb, dropdown_menu.rb so it must be
# excluded from the def name(**) subcomponent scan.
SUBCOMPONENT_BLACKLIST = %w[
  initialize view_template default_attributes class_variants
  merge_default_attributes before_template
].freeze

def parse_component(filepath)
  source = File.read(filepath)
  filename = File.basename(filepath, ".rb")

  # Extract class name — may be namespaced within ShadcnPhlexcomponents
  class_match = source.match(/class\s+(\w+)\s*<\s*(?:(?:ShadcnPhlexcomponents::)?Base|Phlex::HTML)/)
  return nil unless class_match

  class_name = class_match[1]
  full_class = "ShadcnPhlexcomponents::#{class_name}"

  # Extract initialize keyword arguments (props)
  props = []
  init_match = source.match(/def\s+initialize\(([^)]*)\)/m)
  if init_match
    params = init_match[1]
    params.scan(/(\w+):/) do |param|
      name = param[0]
      next if name == "attributes" # internal
      props << name
    end
  end

  # Extract class_variants for variant/size information.
  #
  # Real shadcn_phlexcomponents source (v1.0+) uses a NESTED structure:
  #
  #   class_variants(
  #     **(
  #       ShadcnPhlexcomponents.configuration.button ||
  #       {
  #         base: <<~HEREDOC, ... HEREDOC,
  #         variants: {
  #           variant: { default: "...", destructive: "...", ... },
  #           size: { default: "...", sm: "...", lg: "...", icon: "..." },
  #         },
  #         defaults: { ... },
  #       }
  #     ),
  #   )
  #
  # The variant/size keys live under `variants: { variant: {...}, size: {...} }`,
  # not directly under `class_variants(...)`. Older/alternate formats pass the keys
  # directly as class_variants(variant: {...}, size: {...}) — we support both.
  #
  # Brace-balanced walker because the nested structure has multiple levels, HEREDOCs
  # with braces, and regex `[^}]` would stop at the first close brace.
  variants = []
  sizes = []

  # Walker: from `opener_regex` match, find the opening `{` and return the content
  # between it and the balanced closing `}`. Returns nil if no balanced match.
  extract_balanced = lambda do |src, start_idx|
    i = src.index("{", start_idx)
    return nil unless i
    depth = 0
    j = i
    while j < src.length
      c = src[j]
      if c == "{"
        depth += 1
      elsif c == "}"
        depth -= 1
        return src[(i + 1)...j] if depth.zero?
      end
      j += 1
    end
    nil
  end

  # Extract keys from a hash-body string. Only capture top-level keys by tracking
  # nesting depth — so `variant: { default: "bg-primary" }` yields ["default"], not
  # ["default", "primary"] (from "bg-primary"). Also handle commas/newlines.
  extract_top_level_keys = lambda do |body|
    keys = []
    depth = 0
    i = 0
    # Prepend a newline so the first key at column 0 is treated as line-start.
    b = "\n" + body
    while i < b.length
      c = b[i]
      if c == "{"
        depth += 1
      elsif c == "}"
        depth -= 1
      elsif depth.zero? && (c == "\n" || c == ",")
        # Skip whitespace to find a potential key
        j = i + 1
        j += 1 while j < b.length && b[j] =~ /\s/
        # Match `word:` followed by a value opener (quote, brace, or bareword start)
        m = b[j..].match(/\A(\w+):\s*["'{:a-zA-Z]/)
        keys << m[1] if m
      end
      i += 1
    end
    keys
  end

  # Nested path: `variants: { variant: {...}, size: {...} }`
  if (variants_idx = source.index(/variants:\s*\{/))
    variants_body = extract_balanced.call(source, variants_idx)
    if variants_body
      # Inside variants_body, find each top-level sub-key's block
      scanner_pos = 0
      while (sub_match = variants_body[scanner_pos..].match(/(\w+):\s*\{/))
        sub_name = sub_match[1]
        abs_idx = scanner_pos + sub_match.begin(0)
        sub_body = extract_balanced.call(variants_body, abs_idx + sub_match[0].length - 1)
        break unless sub_body
        keys = extract_top_level_keys.call(sub_body)
        if sub_name == "size"
          sizes.concat(keys)
        elsif sub_name == "variant"
          variants.concat(keys)
        end
        # Advance past this block
        close_idx = variants_body.index("}", abs_idx + sub_match[0].length - 1 + sub_body.length)
        scanner_pos = close_idx ? close_idx + 1 : variants_body.length
      end
    end
  end

  # Flat path: `class_variants(variant: {...}, size: {...})` — older format.
  # Only scan if we didn't find the nested form, to avoid duplicate captures.
  if variants.empty? && sizes.empty?
    if (cv_idx = source.index("class_variants("))
      cv_body = extract_balanced.call(source, cv_idx)
      if cv_body
        scanner_pos = 0
        while (sub_match = cv_body[scanner_pos..].match(/(\w+):\s*\{/))
          sub_name = sub_match[1]
          abs_idx = scanner_pos + sub_match.begin(0)
          sub_body = extract_balanced.call(cv_body, abs_idx + sub_match[0].length - 1)
          break unless sub_body
          keys = extract_top_level_keys.call(sub_body)
          if sub_name == "size"
            sizes.concat(keys)
          elsif sub_name == "variant"
            variants.concat(keys)
          end
          close_idx = cv_body.index("}", abs_idx + sub_match[0].length - 1 + sub_body.length)
          scanner_pos = close_idx ? close_idx + 1 : cv_body.length
        end
      end
    end
  end

  variants.uniq!
  sizes.uniq!

  # Extract subcomponent factory methods (trigger, content, item, etc.).
  # Blacklist internal methods including `class_variants` which some components
  # override as a private helper — those are not user-callable subcomponents.
  subcomponents = []
  source.scan(/def\s+(\w+)\(\*\*/) do |method_name|
    name = method_name[0]
    next if SUBCOMPONENT_BLACKLIST.include?(name)
    subcomponents << name
  end

  # Also scan for renders_one / renders_many (Phlex slots)
  slots = []
  source.scan(/renders_one\s+:(\w+)/) { |s| slots << s[0] }
  source.scan(/renders_many\s+:(\w+)/) { |s| slots << s[0] }

  # Build example. Prefer `:default` (shadcn's canonical base variant) over any other
  # variant, then destructive/secondary/outline/ghost/link in that order. Falls back
  # to the first source-order variant when no semantic match exists. The left-operand
  # ordering of SHADCN_SEMANTIC_VARIANTS & variants means the list order wins, so
  # :default beats :destructive even if destructive appears first in source.
  example_variant = (SHADCN_SEMANTIC_VARIANTS & variants).first || variants.first
  example_parts = []
  example_parts << "variant: :#{example_variant}" if example_variant
  example = "render #{full_class}.new#{example_parts.any? ? "(#{example_parts.join(', ')})" : ''} { \"#{class_name}\" }"

  {
    name: class_name,
    class: full_class,
    file: filename,
    props: props.uniq,
    variants: variants,
    sizes: sizes,
    subcomponents: subcomponents,
    slots: slots,
    example: example
  }
end

def categorize(components)
  categories = {
    layout: %w[Card CardHeader CardTitle CardContent CardFooter Separator AspectRatio],
    forms: %w[Input Select Checkbox Radio Textarea Toggle Switch Label FormField],
    feedback: %w[Alert AlertDialog Badge Toast Tooltip Popover],
    navigation: %w[Breadcrumb NavigationMenu Tabs TabsList TabsTrigger TabsContent Pagination],
    display: %w[Avatar Table Carousel Collapsible Accordion HoverCard],
    actions: %w[Button Dialog DropdownMenu ContextMenu Command],
    overlay: %w[Sheet Drawer Modal Sidebar]
  }

  result = {}
  component_names = components.map { |c| c[:name] }

  categories.each do |category, expected_names|
    matched = expected_names & component_names
    result[category.to_s] = matched if matched.any?
  end

  all_categorized = categories.values.flatten
  uncategorized = component_names - all_categorized
  result["other"] = uncategorized if uncategorized.any?

  result
end

# Scan all component files
component_files = Dir.glob(File.join(component_dir, "**", "*.rb"))
  .reject { |f| SKIP_FILES.include?(File.basename(f)) }
  .sort

components = component_files.filter_map { |f| parse_component(f) }

registry = {
  library: "shadcn_phlexcomponents",
  version: version,
  generated_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
  component_count: components.size,
  components: components,
  patterns: categorize(components)
}

output_dir = File.dirname(output_path)
Dir.mkdir(output_dir) unless Dir.exist?(output_dir)

File.write(output_path, JSON.pretty_generate(registry))
puts "Registry written to #{output_path} (#{components.size} components)"
