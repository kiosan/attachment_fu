require 'RMagick'
module Technoweenie # :nodoc:
  module AttachmentFu # :nodoc:
    module Processors
      module RmagickProcessor
        def self.included(base)
          base.send :extend, ClassMethods
          base.alias_method_chain :process_attachment, :processing
        end

        module ClassMethods
          # Yields a block containing an RMagick Image for the given binary data.
          def with_image(file, &block)
            begin
              binary_data = file.is_a?(Magick::Image) ? file : Magick::Image.read(file).first unless !Object.const_defined?(:Magick)
            rescue
              # Log the failure to load the image.  This should match ::Magick::ImageMagickError
              # but that would cause acts_as_attachment to require rmagick.
              logger.debug("Exception working with image: #{$!}")
              binary_data = nil
            end
            block.call binary_data if block && binary_data
          ensure
            !binary_data.nil?
          end
        end

      protected
        def process_attachment_with_processing
          return unless process_attachment_without_processing
          with_image do |img|
            resize_image_or_thumbnail! img
            self.width  = img.columns if respond_to?(:width)
            self.height = img.rows    if respond_to?(:height)
            callback_with_args :after_resize, img
          end if image?
        end

        # Performs the actual resizing operation for a thumbnail
        def resize_image(img, size)
          size = size.first if size.is_a?(Array) && size.length == 1 && !size.first.is_a?(Fixnum)
          if size.is_a?(Fixnum) || (size.is_a?(Array) && size.first.is_a?(Fixnum))
            size = [size, size] if size.is_a?(Fixnum)
            img.thumbnail!(*size)
          elsif size.is_a?(String) && size =~ /^c.*$/ # Image cropping - example geometry string: c75x75
            dimensions = size[1..size.size].split("x")
            img.crop_resized!(dimensions[0].to_i, dimensions[1].to_i)

          elsif size.is_a?(String) && size =~ /^f.*$/ # Image resize with proportional scaling - example geometry string: f75x75
            dimensions = size[1..size.size].split("x")
            thumb = scale(img, dimensions[0].to_i, dimensions[1].to_i)
            img = Magick::Image.new(dimensions[0].to_i, dimensions[1].to_i) {
              self.format = 'JPEG'
              self.background_color = "#FFFFFF"
            }
            img.composite!(thumb, Magick::CenterGravity, Magick::OverCompositeOp)
          else
            img.change_geometry(size.to_s) { |cols, rows, image| image.resize!(cols<1 ? 1 : cols, rows<1 ? 1 : rows) }
          end
          img.strip! unless attachment_options[:keep_profile]
          temp_paths.unshift write_to_temp_file(img.to_blob)
        end
        
        # Proportional scaling.
        # Recieves Magick::Image instance and maxSize.
        # maxSize check is applied to the axis with the biggest value.
        def scale(img, max_size, max_top_size)
          height, width = img.rows, img.columns
          max_size = max_top_size if height > width
          if (height < max_size and width < max_size)
            return img
          end
          if height > width
            new_height = max_size
            new_width = (width * max_size).to_f / height
          else
            new_width = max_size
            new_height = (height * max_size).to_f / width
          end
          img.scale(new_width, new_height)
        end
      end
    end
  end
end
