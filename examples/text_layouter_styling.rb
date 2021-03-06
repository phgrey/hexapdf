# ## Text Layouter - Styling
#
# The text used as part of a [HexaPDF::Layout::TextLayouter] class can be styled
# using [HexaPDF::Layout::Style]. To do this [HexaPDF::Layout::TextFragment]
# objects have to be created with the needed styling and then added to a text
# layout object. In addition the style objects can be used for customizing the
# text layouts themselves.
#
# This example shows how to do this and shows off the various styling option,
# including using callbacks to further customize the appearance.
#
# Usage:
# : `ruby text_layouter_styling.rb`
#

require 'hexapdf'

include HexaPDF::Layout

# Wraps the text in a TextFragment using the given style.
def fragment(text, style)
  TextFragment.new(items: style.font.decode_utf8(text),
                                    style: style)
end

# Draws the text at the given [x, y] position onto the canvas.
def draw_text(layouter, canvas, x, y)
  rest, height = layouter.fit
  raise "Error" unless rest.empty?
  layouter.draw(canvas, x, y)
  y - height
end

sample_text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit,
sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut
enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut
aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit
in voluptate velit esse cillum dolore eu fugiat nulla pariatur.
Excepteur sint occaecat cupidatat non proident, sunt in culpa qui
officia deserunt mollit anim id est laborum.\u{2029}".tr("\n", ' ') * 3

doc = HexaPDF::Document.new

heading = Style.new(font: doc.fonts.load("Helvetica", variant: :bold),
                    font_size: 32, align: :center,
                    fill_color: [200], text_rendering_mode: :fill_stroke,
                    stroke_color: [255, 0, 0], stroke_alpha: 0.7,
                    stroke_width: 1, stroke_dash_pattern: [0.5, 1, 1.5],
                    stroke_cap_style: :round, stroke_join_style: :round)
body = Style.new(font: doc.fonts.load("Times"),
                 font_size: 10, align: :justify,
                 text_indent: 20)
body.line_spacing(:fixed, 16)
highlight1 = Style.new(font: doc.fonts.load("Times", variant: :bold_italic),
                       text_rendering_mode: :stroke,
                       stroke_color: [255, 0, 0], stroke_width: 0.2,
                       stroke_join_style: :round)
highlight2 = Style.new(font: doc.fonts.load("Times", variant: :italic))
highlight2.underlay_callback do |canv, box|
  canv.fill_color(240, 240, 0).opacity(fill_alpha: 0.5).
    rectangle(0, 0, box.width, box.height).fill
end
highlight2.overlay_callback do |canv, box|
  canv.line_width(1).stroke_color([0, 255, 0]).
    line(0, 0, box.width, box.height).stroke
end
highlight3 = Style.new(font: doc.fonts.load("Times"), superscript: true)
intro = Style.new(font: doc.fonts.load("Times", variant: :bold),
                  fill_color: [0, 0, 160], font_size: 14)

canvas = doc.pages.add.canvas
y_base = 800
left = 50
width = 500

layouter = TextLayouter.new(items: [fragment("This is a header", heading)],
                            width: width, style: heading)
y_base = draw_text(layouter, canvas, left, y_base)

layouter = TextLayouter.new(items: [fragment(sample_text, body)],
                            width: width, style: body)
y_base = draw_text(layouter, canvas, left, y_base - 20)

highlights = [highlight1, highlight2, highlight3]
highlight = nil
items = sample_text.split(/(Lorem ipsum dolor sit|\b\w{2,4}\b)/).map do |str|
  if str.length >= 2 && str.length <= 4
    fragment(str, highlight)
  elsif str =~ /Lorem/
    highlight = highlights.shift
    fragment(str, intro)
  else
    fragment(str, body)
  end
end

layouter = TextLayouter.new(items: items, width: width, style: body)
draw_text(layouter, canvas, left, y_base - 20)
doc.write("text_layouter_styling.pdf", optimize: true)
