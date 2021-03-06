# ## Boxes
#
# The [HexaPDF::Layout::Box] class is used as the basis for all document layout
# features.
#
# This example shows the basic properties that are available for all boxes, like
# paddings, borders and and background color. It is also possible to use the
# underlay and overlay callbacks with boxes.
#
# Usage:
# : `ruby boxes.rb`
#

require 'hexapdf'

doc = HexaPDF::Document.new

annotate_box = lambda do |canvas, box|
  text = ""
  canvas.font("Times", size: 6)

  if (data = box.style.padding)
    text << "Padding (TRBL): #{data.top}, #{data.right}, #{data.bottom}, #{data.left}\n"
  end
  unless box.style.border.none?
    data = box.style.border.width
    text << "Border Width (TRBL): #{data.top}, #{data.right}, #{data.bottom}, #{data.left}\n"
    data = box.style.border.color
    text << "Border Color (TRBL):\n* #{data.top}\n* #{data.right}\n* #{data.bottom}\n* #{data.left}\n"
    data = box.style.border.style
    text << "Border Style (TRBL):\n* #{data.top}\n* #{data.right}\n* #{data.bottom}\n* #{data.left}\n"
  end

  canvas.line_width(0.1).rectangle(0, 0, box.content_width, box.content_height).stroke
  canvas.text(text, at: [0, box.content_height - 10])
end

canvas = doc.pages.add.canvas

[[1, 200], [5, 220], [15, 240]].each_with_index do |(width, red), row|
  [[:solid, 180], [:dashed, 200], [:dashed_round, 220],
   [:dotted, 240]].each_with_index do |(style, green), column|
    box = HexaPDF::Layout::Box.new(content_width: 100, content_height: 100, &annotate_box)
    box.style.border(width: width, style: style)
    box.style.background_color([red, green, 0])
    box.draw(canvas, 20 + 140 * column, 700 - 150 * row)
  end
end

# The whole kitchen sink
box = HexaPDF::Layout::Box.new(content_width: 470, content_height: 200, &annotate_box)
box.style.background_color([255, 255, 180])
box.style.padding([20, 5, 10, 15])
box.style.border(width: [20, 40, 30, 15],
                 color: [[46, 185, 206], [206, 199, 46], [188, 46, 206], [59, 206, 46]],
                 style: [:solid, :dashed, :dashed_round, :dotted])
box.style.underlay_callback do |canv, _|
  canv.stroke_color([255, 0, 0]).line_width(10).line_cap_style(:butt).
    line(0, 0, box.width, box.height).line(0, box.height, box.width, 0).
    stroke
end
box.style.overlay_callback do |canv, _|
  canv.stroke_color([0, 0, 255]).line_width(5).
    rectangle(10, 10, box.width - 20, box.height - 20).stroke
end
box.draw(canvas, 20, 100)

doc.write("boxes.pdf", optimize: true)
