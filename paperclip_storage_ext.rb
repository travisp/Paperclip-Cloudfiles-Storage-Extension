require 'paperclip'
module Paperclip
  module Storage
    module Cloud_files
      def self.extended base
        begin
          require 'cloudfiles'
        rescue LoadError => e
          e.message << " (You may need to install the cloudfiles gem)"
          raise e
        end unless defined?(CloudFiles)
        @@container ||= {}
        base.instance_eval do
          @cloudfiles_credentials = parse_credentials(@options[:cloudfiles_credentials])
          @container_name         = @options[:container] || options[:container_name] || @cloudfiles_credentials[:container] || @cloudfiles_credentials[:container_name]
          @container_name         = @container_name.call(self) if @container_name.is_a?(Proc)
          @alt_container_name     = @options[:alt_container] || options[:alt_container_name] || @cloudfiles_credentials[:alt_container] || @cloudfiles_credentials[:alt_container_name]
          @alt_container_name     = @alt_container_name.call(self) if @alt_container_name.is_a?(Proc)
          @testing                = @options[:testing]        || @cloudfiles_credentials[:testing]
          @cloudfiles_options     = @options[:cloudfiles_options]     || {}
          @@cdn_url               = @cloudfiles_credentials[:cname] || cloudfiles_container.cdn_url
          @@ssl_url               = @cloudfiles_credentials[:cname] || cloudfiles_container.cdn_ssl_url
          @@alt_url               = alt_cloudfiles_container.cdn_url if @alt_container_name
          @@alt_ssl_url           = alt_cloudfiles_container.cdn_ssl_url if @alt_container_name
          @use_ssl                = @options[:ssl] || false
          @path_filename          = ":cf_path_filename" unless @url.to_s.match(/^:cf.*filename$/)
          @url                    = ":cf_url" + "/#{URI.encode(@path_filename).gsub(/&/,'%26')}"
          @path = (Paperclip::Attachment.default_options[:path] == @options[:path]) ? ":attachment/:id/:style/:basename.:extension" : @options[:path]
        end

        Paperclip.interpolates(:cf_path_filename) do |attachment, style|
          URI.encode(attachment.path(style))
        end

        Paperclip.interpolates(:cf_url) do |attachment, style|
          if attachment.testing && !attachment.exists?(style)
            (@use_ssl == true ? @@alt_ssl_url : @@alt_url)
          else
            (@use_ssl == true ? @@ssl_url : @@cdn_url)
          end
        end
      end

      def create_alt_container
        container = cloudfiles.create_container(@alt_container_name)
        container.make_public
        container
      end

      def alt_container_name
        @alt_container_name
      end

      def alt_cloudfiles_container
        @@container[@alt_container_name] ||= create_alt_container
      end

      def testing
        @testing
      end

      def alt_exists?(style = default_style)
        alt_cloudfiles_container.object_exists?(path(style))
      end

      # Returns representation of the data of the file assigned to the given
      # style, in the format most representative of the current storage.
      def to_file style = default_style
        return @queued_for_write[style] if @queued_for_write[style]
        filename = path(style)
        extname = File.extname(filename)
        basename = File.basename([basename, extname])
        file = Tempfile.new([basename, extname])
        file.binmode
        file = Tempfile.new(path(style))
        container = (testing && !exists?(style)) ? alt_cloudfiles_container : cloudfiles_container
        file.write(container.object(path(style)).data)
        file.rewind
        return file
      end

    end
  end
end
