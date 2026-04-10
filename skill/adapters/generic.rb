#!/usr/bin/env ruby
# frozen_string_literal: true

# phlexed adapter: generic
# Fallback adapter that scans app/views/components/ and app/components/
# for any class inheriting from Phlex::HTML.
#
# Usage:
#   ruby generic.rb <project_root> [output_path]
#       Full-scan mode. Walks SCAN_DIRS, parses every Phlex class, writes
#       a complete registry to output_path.
#
#   ruby generic.rb <project_root> [output_path] --append <file.rb>
#       Incremental append mode (v0.2). Parses one Ruby file and merges its
#       component into an existing registry.json at output_path without
#       re-scanning the rest of the project. Intended to be called by
#       /phlexed-component after creating a new Phlex class — avoids the
#       cost of a full rebuild for projects with many components. Handles:
#         - dedup by file path (re-appending the same file updates in place)
#         - conflict detection against existing library components
#         - local_components metadata update in merged registries

require "json"
require "pathname"

# --- ARGV parsing: extract --append flag and remaining positional args ---
args = ARGV.dup
append_file = nil
if (append_idx = args.index("--append"))
  append_file = args[append_idx + 1]
  args.delete_at(append_idx + 1) if args[append_idx + 1]
  args.delete_at(append_idx)
end

project_root = args[0] || "."
output_path_arg = args[1] || ".phlexed/registry.json"

unless Dir.exist?(project_root)
  warn "error: project root does not exist: #{project_root}"
  warn "Usage: ruby generic.rb <project_root> [output_path] [--append <file.rb>]"
  exit 1
end

# Resolve output_path against project_root when it's a relative path. This
# matches user expectations: `generic.rb /path/to/app` should write to
# /path/to/app/.phlexed/registry.json, not $PWD/.phlexed/registry.json.
# Absolute output paths (passed explicitly) pass through unchanged so tests
# and custom invocations can target arbitrary locations.
output_path =
  if Pathname.new(output_path_arg).absolute?
    output_path_arg
  else
    File.join(project_root, output_path_arg)
  end

if append_file && !File.exist?(append_file)
  warn "error: --append file does not exist: #{append_file}"
  exit 1
end

# Directories to scan for Phlex components. Ordered most-specific-first so
# dedicated component dirs take precedence, with app/views as a catch-all for
# projects that put Phlex views inline (a common pattern during ERB→Phlex
# migration, and the convention the sample/ fixture uses).
SCAN_DIRS = %w[
  app/views/components
  app/components
  app/views/layouts
  app/views
].freeze

def parse_phlex_file(filepath, project_root)
  source = File.read(filepath)

  # Must inherit from Phlex::HTML directly, or from a project-level base class that
  # itself inherits from Phlex::HTML. Covers the common conventions:
  #
  #   class MyView < Phlex::HTML          # direct
  #   class MyView < Views::Base          # project base (sample/ uses this)
  #   class MyView < ApplicationView      # Rails-convention base
  #   class MyView < ApplicationComponent # ViewComponent-style base
  #
  # The generic adapter can't trace inheritance transitively without loading the
  # code, so the acceptance check is name-based. Good enough for the fallback case
  # — a real project's own base class is typically one of these four.
  return nil unless source.match?(/class\s+[\w:]+.*<\s*(?:Phlex::HTML|Views::Base|ApplicationView|ApplicationComponent)/) ||
                    source.match?(/include\s+Phlex/)

  # Extract class name with full module nesting
  modules = []
  source.scan(/module\s+([\w:]+)/) { |m| modules << m[0] }
  class_match = source.match(/class\s+([\w:]+)\s*</)
  return nil unless class_match

  class_name = class_match[1]
  short_name = class_name.split("::").last
  full_class = modules.any? ? "#{modules.join('::')}::#{class_name}" : class_name

  # Extract initialize keyword args
  props = []
  init_match = source.match(/def\s+initialize\(([^)]*)\)/m)
  if init_match
    params = init_match[1]
    params.scan(/(\w+):/) do |param|
      props << param[0]
    end
  end

  # Extract slots
  slots = []
  source.scan(/renders_one\s+:(\w+)/) { |s| slots << s[0] }
  source.scan(/renders_many\s+:(\w+)/) { |s| slots << s[0] }

  relative_path = Pathname.new(filepath).relative_path_from(Pathname.new(project_root)).to_s

  example = "render #{full_class}.new#{props.any? ? "(#{props.first}: ...)" : ''}"

  {
    name: short_name,
    class: full_class,
    file: relative_path,
    props: props,
    slots: slots,
    example: example
  }
end

# --- Append mode (v0.2): merge one component into an existing registry ---
# Short-circuits the full scan. Used by /phlexed-component after creating a new
# Phlex class, so we avoid re-parsing every file in app/components.
if append_file
  unless File.exist?(output_path)
    warn "error: registry not found at #{output_path}"
    warn "       Run a full scan first (or /phlexed-setup) before using --append."
    exit 1
  end

  new_component = parse_phlex_file(append_file, project_root)
  unless new_component
    warn "error: #{append_file} does not look like a Phlex component"
    warn "       (must inherit from Phlex::HTML, Views::Base, ApplicationView, or ApplicationComponent)"
    exit 1
  end

  # Normalize to string keys to match the serialized registry format, and tag
  # as local since append mode is only meaningful for project-local components
  # (library gems get re-scanned via phlexed-registry on version bumps).
  new_component = new_component.transform_keys(&:to_s)
  new_component["source"] = "local"

  # Load existing registry
  registry = JSON.parse(File.read(output_path))
  components = registry["components"] || []

  # Dedup by file path: if the same file was appended before, replace the entry
  # rather than creating a duplicate. This makes repeated calls idempotent —
  # /phlexed-component can re-emit without worrying about leaking stale entries.
  components.reject! { |c| c["file"] == new_component["file"] }

  # Conflict detection against existing library components. If a library
  # component shares the same short name, flag this local one with
  # conflict: true so downstream consumers (phlexed-render-cursorrules,
  # /phlexed-build) can surface a rename warning.
  library_names = components.select { |c| c["source"] == "library" }.map { |c| c["name"] }
  if library_names.include?(new_component["name"])
    new_component["conflict"] = true
  end

  components << new_component
  registry["components"] = components
  registry["component_count"] = components.size

  # Update local_components metadata if this is a merged v0.2 registry. Flat
  # v0.1 registries don't have this block, so we leave it alone in that case.
  if registry.key?("local_components") || registry.key?("has_local_components")
    local_comps = components.select { |c| c["source"] == "local" }
    registry["local_components"] = {
      "count" => local_comps.size,
      "conflicts" => local_comps.count { |c| c["conflict"] }
    }
    registry["has_local_components"] = !local_comps.empty?
  end

  File.write(output_path, JSON.pretty_generate(registry))
  conflict_note = new_component["conflict"] ? " (⚠ name conflicts with library component)" : ""
  puts "Appended #{new_component["name"]} to #{output_path} — #{components.size} components total#{conflict_note}"
  exit 0
end

# Scan all directories. The entries in SCAN_DIRS overlap (e.g. app/views/layouts is
# under app/views), so track seen filepaths to avoid parsing and emitting the same
# file twice.
all_components = []
seen_paths = {}

SCAN_DIRS.each do |dir|
  full_dir = File.join(project_root, dir)
  next unless Dir.exist?(full_dir)

  Dir.glob(File.join(full_dir, "**", "*.rb")).sort.each do |filepath|
    next if seen_paths[filepath]
    seen_paths[filepath] = true

    component = parse_phlex_file(filepath, project_root)
    all_components << component if component
  end
end

registry = {
  library: "custom",
  version: "0.0.0",
  generated_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
  component_count: all_components.size,
  components: all_components,
  patterns: {}
}

output_dir = File.dirname(output_path)
Dir.mkdir(output_dir) unless Dir.exist?(output_dir)

File.write(output_path, JSON.pretty_generate(registry))
puts "Registry written to #{output_path} (#{all_components.size} components)"
