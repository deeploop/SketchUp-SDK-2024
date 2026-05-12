module Sketchup
  # Mirrors Sketchup::Color from the official Ruby API.
  class Color
    attr_accessor :red, :green, :blue, :alpha

    def initialize(r = 0, g = 0, b = 0, a = 255)
      @red   = r.to_i.clamp(0, 255)
      @green = g.to_i.clamp(0, 255)
      @blue  = b.to_i.clamp(0, 255)
      @alpha = a.to_i.clamp(0, 255)
    end

    def to_a; [@red, @green, @blue, @alpha]; end
    def to_s; "Color(#{@red}, #{@green}, #{@blue}, #{@alpha})"; end

    # Allow construction from hex string "#RRGGBB"
    def self.from_hex(hex)
      hex = hex.delete('#')
      new(hex[0,2].to_i(16), hex[2,2].to_i(16), hex[4,2].to_i(16))
    end
  end
end
