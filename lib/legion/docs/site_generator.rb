# frozen_string_literal: true

require 'fileutils'

begin
  require 'kramdown'
rescue LoadError
  # kramdown optional — plain-text fallback used when absent
end

begin
  require 'rouge'
rescue LoadError
  # rouge optional — syntax highlighting skipped when absent
end

module Legion
  module Docs
    class SiteGenerator
      GUIDE_SOURCES = [
        { source: 'docs/getting-started.md', title: 'Getting Started', section: 'guides' },
        { source: 'docs/overview.md', title: 'Architecture', section: 'guides' },
        { source: 'docs/extension-development.md', title: 'Extension Development', section: 'guides' },
        { source: 'docs/best-practices.md', title: 'Best Practices', section: 'guides' },
        { source: 'docs/protocol/LEGION_WIRE_PROTOCOL.md', title: 'Wire Protocol', section: 'protocol' }
      ].freeze

      # Legacy constant — preserved so existing code that references SECTIONS still works.
      SECTIONS = GUIDE_SOURCES.freeze

      def initialize(output_dir: 'docs/site')
        @output_dir = output_dir
        @pages = []
      end

      # Generate the full static site.
      #
      # Returns a hash with :output, :sections, :pages, and :files keys.
      def generate
        FileUtils.mkdir_p(@output_dir)
        generate_guides
        generate_cli_reference
        generate_extension_reference
        generate_index
        {
          output:   @output_dir,
          sections: GUIDE_SOURCES.size,
          pages:    @pages.size,
          files:    @pages.map { |p| p[:file] }
        }
      end

      private

      # ---------------------------------------------------------------------------
      # Markdown rendering
      # ---------------------------------------------------------------------------

      def render_markdown(content)
        if defined?(Kramdown::Document)
          highlighter = defined?(Rouge) ? :rouge : nil
          opts = { auto_ids: true }
          opts[:syntax_highlighter] = highlighter if highlighter
          Kramdown::Document.new(content, **opts).to_html
        else
          # Plain-text fallback: wrap in <pre> so it is at least readable.
          "<pre>#{escape_html(content)}</pre>"
        end
      end

      def escape_html(text)
        text.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
      end

      # ---------------------------------------------------------------------------
      # HTML template
      # ---------------------------------------------------------------------------

      def html_template(title:, body:, nav:)
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>#{escape_html(title)} — LegionIO Docs</title>
            <style>
              body { font-family: sans-serif; margin: 0; display: flex; }
              nav  { width: 220px; min-height: 100vh; background: #1a1a2e; padding: 1rem; box-sizing: border-box; }
              nav a { display: block; color: #a78bfa; text-decoration: none; margin: 0.3rem 0; font-size: 0.9rem; }
              nav a:hover { color: #fff; }
              nav .section-heading { color: #6d6d8a; font-size: 0.75rem; text-transform: uppercase;
                                     letter-spacing: 0.08em; margin-top: 1rem; }
              main { flex: 1; padding: 2rem; max-width: 900px; }
              h1, h2, h3 { color: #1a1a2e; }
              pre  { background: #f4f4f8; padding: 1rem; overflow-x: auto; border-radius: 4px; }
              code { background: #f4f4f8; padding: 0.1em 0.3em; border-radius: 3px; }
              .highlight pre { background: #f4f4f8; }
            </style>
          </head>
          <body>
            <nav>
              <div style="color:#a78bfa;font-weight:bold;margin-bottom:1rem;">LegionIO</div>
              #{nav}
            </nav>
            <main>
              <h1>#{escape_html(title)}</h1>
              #{body}
            </main>
          </body>
          </html>
        HTML
      end

      # ---------------------------------------------------------------------------
      # Navigation sidebar
      # ---------------------------------------------------------------------------

      def build_navigation
        sections = @pages.group_by { |p| p[:section] }
        html = +''
        sections.each do |section, pages|
          html << "<div class=\"section-heading\">#{escape_html(section.to_s.capitalize)}</div>\n"
          pages.each do |page|
            html << "  <a href=\"#{page[:slug]}.html\">#{escape_html(page[:title])}</a>\n"
          end
        end
        html
      end

      # ---------------------------------------------------------------------------
      # Index page
      # ---------------------------------------------------------------------------

      def generate_index
        nav  = build_navigation
        body = +"<p>Welcome to the LegionIO documentation.</p>\n"

        sections = @pages.group_by { |p| p[:section] }
        sections.each do |section, pages|
          body << "<h2>#{escape_html(section.to_s.capitalize)}</h2>\n<ul>\n"
          pages.each do |page|
            body << "  <li><a href=\"#{page[:slug]}.html\">#{escape_html(page[:title])}</a></li>\n"
          end
          body << "</ul>\n"
        end

        html = html_template(title: 'LegionIO Documentation', body: body, nav: nav)
        write_page('index', html)
      end

      # ---------------------------------------------------------------------------
      # Guide pages (Markdown sources)
      # ---------------------------------------------------------------------------

      def generate_guides
        GUIDE_SOURCES.each do |entry|
          slug    = File.basename(entry[:source], '.md').downcase.tr('_', '-')
          title   = entry[:title]
          section = entry[:section]

          markdown = if File.exist?(entry[:source])
                       File.read(entry[:source])
                     else
                       "# #{title}\n\n_Documentation coming soon._\n"
                     end

          register_page(slug: slug, title: title, section: section)
          body = render_markdown(markdown)
          nav  = build_navigation
          html = html_template(title: title, body: body, nav: nav)
          write_page(slug, html)
        end
      end

      # ---------------------------------------------------------------------------
      # CLI reference (introspects Thor commands when available)
      # ---------------------------------------------------------------------------

      def generate_cli_reference
        register_page(slug: 'cli-reference', title: 'CLI Reference', section: 'reference')
        body = build_cli_body
        nav  = build_navigation
        html = html_template(title: 'CLI Reference', body: body, nav: nav)
        write_page('cli-reference', html)
      end

      def build_cli_body
        body = +"<p>Available <code>legion</code> commands:</p>\n"

        commands = introspect_thor_commands
        if commands.empty?
          body << "<p><em>CLI introspection unavailable — require LegionIO to see commands.</em></p>\n"
          return body
        end

        body << "<table>\n<thead><tr><th>Command</th><th>Description</th></tr></thead>\n<tbody>\n"
        commands.each do |cmd|
          body << "  <tr><td><code>#{escape_html(cmd[:name])}</code></td>" \
                  "<td>#{escape_html(cmd[:description])}</td></tr>\n"
        end
        body << "</tbody>\n</table>\n"
        body
      end

      def introspect_thor_commands
        return [] unless defined?(Legion::CLI::Main)

        cmds = Legion::CLI::Main.all_commands.filter_map do |name, cmd|
          next if name.start_with?('_') || name == 'help'

          { name: "legion #{name}", description: cmd.description.to_s.split("\n").first.to_s }
        end
        cmds.sort_by { |c| c[:name] }
      rescue StandardError
        []
      end

      # ---------------------------------------------------------------------------
      # Extension reference (discovered LEX gems)
      # ---------------------------------------------------------------------------

      def generate_extension_reference
        register_page(slug: 'extensions', title: 'Extensions', section: 'reference')
        body = build_extensions_body
        nav  = build_navigation
        html = html_template(title: 'Extensions', body: body, nav: nav)
        write_page('extensions', html)
      end

      def build_extensions_body
        body = +"<p>Discovered LEX extensions:</p>\n"

        extensions = discover_extensions
        if extensions.empty?
          body << "<p><em>No extensions discovered. Ensure LEX gems are installed.</em></p>\n"
          return body
        end

        body << "<table>\n<thead><tr><th>Gem</th><th>Version</th></tr></thead>\n<tbody>\n"
        extensions.each do |ext|
          body << "  <tr><td><code>#{escape_html(ext[:name])}</code></td>" \
                  "<td>#{escape_html(ext[:version])}</td></tr>\n"
        end
        body << "</tbody>\n</table>\n"
        body
      end

      def discover_extensions
        specs = if defined?(Bundler)
                  Bundler.load.specs.select { |s| s.name.start_with?('lex-') }
                else
                  Gem::Specification.select { |s| s.name.start_with?('lex-') }
                end
        specs.map { |s| { name: s.name, version: s.version.to_s } }
             .sort_by { |e| e[:name] }
      rescue StandardError, LoadError
        []
      end

      # ---------------------------------------------------------------------------
      # Helpers
      # ---------------------------------------------------------------------------

      def register_page(slug:, title:, section:)
        path = File.join(@output_dir, "#{slug}.html")
        @pages << { slug: slug, title: title, section: section, file: path }
      end

      def write_page(slug, html)
        path = File.join(@output_dir, "#{slug}.html")
        File.write(path, html)
        path
      end
    end
  end
end
