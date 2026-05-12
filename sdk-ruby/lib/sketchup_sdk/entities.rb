module Sketchup
  # Mirrors Sketchup::Entities from the official Ruby API.
  # Retrieved via model.entities — do not instantiate directly.
  class Entities
    def initialize(native_ptr)
      @native_ptr = native_ptr
    end

    # Creates a face from an array of points and adds it to the model.
    #
    # Accepts the same argument styles as the official SketchUp Ruby API:
    #   entities.add_face([x,y,z], [x,y,z], ...)
    #   entities.add_face([[x,y,z], [x,y,z], ...])
    #   entities.add_face(Geom::Point3d, ...)
    #
    # Returns a Sketchup::Face, or nil on failure.
    def add_face(*args)
      pts = args.flatten(1)

      # Detect flat numeric list: add_face(x,y,z, x,y,z, ...) — convert to triples.
      if pts.first.is_a?(Numeric)
        raise ArgumentError, "Point count must be divisible by 3" unless (pts.size % 3).zero?
        pts = pts.each_slice(3).to_a
      end

      n = pts.size
      raise ArgumentError, "Need at least 3 points, got #{n}" if n < 3

      buf = FFI::MemoryPointer.new(:double, n * 3)
      pts.each_with_index do |pt, i|
        coords = extract_coords(pt)
        buf.put_double((i * 3 + 0) * 8, coords[0])
        buf.put_double((i * 3 + 1) * 8, coords[1])
        buf.put_double((i * 3 + 2) * 8, coords[2])
      end

      ptr = SketchUpBridge.entities_add_face(@native_ptr, buf, n)
      return nil if ptr.nil? || ptr.null?

      Face.new(ptr)
    end

    private

    def extract_coords(pt)
      if pt.respond_to?(:x) && pt.respond_to?(:y) && pt.respond_to?(:z)
        [pt.x.to_f, pt.y.to_f, pt.z.to_f]
      elsif pt.respond_to?(:to_a)
        a = pt.to_a.map(&:to_f)
        a.size == 3 ? a : raise(ArgumentError, "Expected 3 coords, got #{a}")
      else
        raise ArgumentError, "Cannot convert #{pt.inspect} to a 3-D point"
      end
    end
  end
end
