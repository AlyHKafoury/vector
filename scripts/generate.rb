#!/usr/bin/env ruby

# generate.rb
#
# SUMMARY
#
#   A simple script that generates files across the Vector repo. This is used
#   for documentation, config examples, etc. The source templates are located
#   in /scripts/generate/templates/* and the results are placed in their
#   respective root directories.
#
#   See the README.md in the generate folder for more details.

Dir.chdir "scripts/generate"

#
# Require
#

require "erb"
require "ostruct"
require "rubygems"
require "bundler"
Bundler.require(:default)

require_relative "generate/context"
require_relative "generate/core_ext/hash"
require_relative "generate/core_ext/object"
require_relative "generate/core_ext/string"
require_relative "generate/post_processors/component_presence_checker"
require_relative "generate/post_processors/link_checker"
require_relative "generate/post_processors/option_referencer"
require_relative "generate/post_processors/section_sorter"
require_relative "generate/post_processors/toml_syntax_switcher"

#
# Functions
#

def post_process(content, doc, links)
  content = PostProcessors::TOMLSyntaxSwitcher.switch!(content)
  content = PostProcessors::SectionSorter.sort!(content)
  content = PostProcessors::OptionReferencer.reference!(content)
  content = PostProcessors::LinkChecker.check!(content, doc, links)
  content
end

def render(template, context)
  content = File.read(template)
  renderer = ERB.new(content, nil, '-')
  content = renderer.result(context.get_binding).lstrip.strip

  if template.end_with?(".md.erb")
    notice =
      <<~EOF

      <!--
           THIS FILE IS AUTOGENERATED!

           To make changes please edit the template located at:

           scripts/generate/#{template}
      -->
      EOF

    content.sub!(/\n# /, "#{notice}\n# ")
  end

  content
end

def say(words, color: nil, title: false)
  if color
    words = Paint[words, color]
  end

  indented_words = words.gsub("\n", "\n     ")

  if title
    puts "#### #{indented_words}"
  else
    puts "---> #{indented_words}"
  end
end

#
# Constants
#

VECTOR_ROOT = File.join(Dir.pwd.split(File::SEPARATOR)[0..-3])

CHECK_URLS = ARGV.any? { |arg| arg == "--check-urls=true" }
DOCS_ROOT = File.join(VECTOR_ROOT, "docs")
META_ROOT = File.join(VECTOR_ROOT, ".meta")
VECTOR_DOCS_HOST = "https://docs.vector.dev"

#
# Render templates
#

puts ""
say("Generating files...", title: true)
puts ""

if CHECK_URLS
  message =
    <<~EOF
    NOTE
    URL checking is enabled, this process may take a few minutes.
    You can disable URL checking via the check-urls argument:
    
      make check_urls=false generate
    EOF

  say(message, color: :blue)
else
  say("URL checking is disabled.", color: :yellow)
end

metadata = Metadata.load(META_ROOT)
context = Context.new(metadata)
templates = Dir.glob("templates/**/*.erb", File::FNM_DOTMATCH).to_a
templates.each do |template|
  basename = File.basename(template)

  # Skip partials
  if !basename.start_with?("_")
    content = render(template, context)
    target = template.gsub(/^templates\//, "#{VECTOR_ROOT}/").gsub(/\.erb$/, "")
    content = post_process(content, target, metadata.links)

    # Create the file if it does not exist
    if !File.exists?(target)
      File.open(target, "w") {}
    end

    current_content = File.read(target)

    if current_content != content
      action = false ? "Will be changed" : "Changed"
      say("#{action} - #{target.gsub("../../", "")}", color: :green)
      File.write(target, content)
    else
      action = false ? "Will not be changed" : "Not changed"
      say("#{action} - #{target.gsub("../../", "")}", color: :blue)
    end
  end
end

#
# Check component presence
#

docs = Dir.glob("#{DOCS_ROOT}/usage/configuration/sources/*.md").to_a
PostProcessors::ComponentPresenceChecker.check!("sources", docs, metadata.sources)

docs = Dir.glob("#{DOCS_ROOT}/usage/configuration/transforms/*.md").to_a
PostProcessors::ComponentPresenceChecker.check!("transforms", docs, metadata.transforms)

docs = Dir.glob("#{DOCS_ROOT}/usage/configuration/sinks/*.md").to_a
PostProcessors::ComponentPresenceChecker.check!("sinks", docs, metadata.sinks)

#
# Post process individual docs
#

puts ""
say("Post processing files...", title: true)
puts ""

docs = Dir.glob("#{DOCS_ROOT}/**/*.md").to_a
docs = docs + ["#{VECTOR_ROOT}/README.md"]
docs = docs - ["#{DOCS_ROOT}/SUMMARY.md"]
docs.each do |doc|
  content = File.read(doc)
  if content.include?("THIS FILE IS AUTOGENERATED")
    say("Skipped - #{doc}", color: :blue)
  else
    content = post_process(content, doc, metadata.links)
    File.write(doc, content)
    say("Processed - #{doc}", color: :green)
  end
end
