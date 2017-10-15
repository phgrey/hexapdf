$LOAD_PATH.unshift(File.expand_path('../../lib', __FILE__))

require 'hexapdf'


class FormProcessor < HexaPDF::Content::Processor
  def process(operator, operands = [])
    # p "NO_OPERATOR FOR #{ operator } : " unless @operators.key?(operator)
    msg = OPERATOR_MESSAGE_NAME_MAP[operator]
    # p "NO_MESSAGE FOR #{ operator }(#{ msg })" unless msg && respond_to?(msg, true)
    super
  end

  def show_text(str)
    p decode_text str
    # p str
  end

  alias :show_text_with_positioning :show_text

end



def here(fname = '')
  File.expand_path "../#{fname}", __FILE__
end
manual = HexaPDF::Document.open here 'form_manual.pdf'
manual2 = HexaPDF::Document.open here 'form_manual2.pdf'
manual3 = HexaPDF::Document.open here 'form_manual3.pdf'
empty  =  HexaPDF::Document.open here 'form_empty.pdf'

# manual3.each do |obj|
#   p obj.inspect
# end

val = manual2.object 75
p val
# return
frm2 = manual2.object 38
frm1 = manual.object 38

frm2.process_contents FormProcessor.new

frm1.process_contents FormProcessor.new


=begin




manual:
  +38:1,
  +75:0
  +133:0
  -38:0
  -75:0
manual2:
  +38:2
  -38:1
  +114:0
  +-75:0 ()



=end
