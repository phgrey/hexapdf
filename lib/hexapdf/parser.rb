# -*- encoding: utf-8 -*-
#
#--
# This file is part of HexaPDF.
#
# HexaPDF - A Versatile PDF Creation and Manipulation Library For Ruby
# Copyright (C) 2014-2017 Thomas Leitner
#
# HexaPDF is free software: you can redistribute it and/or modify it
# under the terms of the GNU Affero General Public License version 3 as
# published by the Free Software Foundation with the addition of the
# following permission added to Section 15 as permitted in Section 7(a):
# FOR ANY PART OF THE COVERED WORK IN WHICH THE COPYRIGHT IS OWNED BY
# THOMAS LEITNER, THOMAS LEITNER DISCLAIMS THE WARRANTY OF NON
# INFRINGEMENT OF THIRD PARTY RIGHTS.
#
# HexaPDF is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public
# License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with HexaPDF. If not, see <http://www.gnu.org/licenses/>.
#
# The interactive user interfaces in modified source and object code
# versions of HexaPDF must display Appropriate Legal Notices, as required
# under Section 5 of the GNU Affero General Public License version 3.
#
# In accordance with Section 7(b) of the GNU Affero General Public
# License, a covered work must retain the producer line in every PDF that
# is created or manipulated using HexaPDF.
#++

require 'hexapdf/error'
require 'hexapdf/tokenizer'
require 'hexapdf/stream'
require 'hexapdf/xref_section'

module HexaPDF

  # Parses an IO stream according to PDF1.7 to get at the contained objects.
  #
  # This class also contains higher-level methods for getting indirect objects and revisions.
  #
  # See: PDF1.7 s7
  class Parser

    # Creates a new parser for the given IO object.
    #
    # PDF references are resolved using the associated Document object.
    def initialize(io, document)
      @io = io
      @tokenizer = Tokenizer.new(io)
      @document = document
      @object_stream_data = {}
      retrieve_pdf_header_offset_and_version
    end

    # Loads the indirect (potentially compressed) object specified by the given cross-reference
    # entry.
    #
    # For information about the +xref_entry+ argument, have a look at HexaPDF::XRefSection and
    # HexaPDF::XRefSection::Entry.
    def load_object(xref_entry)
      obj, oid, gen, stream =
        case xref_entry.type
        when :in_use
          parse_indirect_object(xref_entry.pos)
        when :free
          [nil, xref_entry.oid, xref_entry.gen, nil]
        when :compressed
          load_compressed_object(xref_entry)
        else
          raise_malformed("Invalid cross-reference type '#{xref_entry.type}' encountered")
        end

      if xref_entry.oid != 0 && (oid != xref_entry.oid || gen != xref_entry.gen)
        raise_malformed("The oid,gen (#{oid},#{gen}) values of the indirect object don't match " \
          "the values (#{xref_entry.oid},#{xref_entry.gen}) from the xref")
      end

      @document.wrap(obj, oid: oid, gen: gen, stream: stream)
    end

    # Parses the indirect object at the specified offset.
    #
    # This method is used by a PDF Document to load objects. It should **not** be used by any
    # other object because invalid object positions lead to errors.
    #
    # Returns an array containing [object, oid, gen, stream].
    #
    # See: PDF1.7 s7.3.10, s7.3.8
    def parse_indirect_object(offset = nil)
      @tokenizer.pos = offset + @header_offset if offset
      oid = @tokenizer.next_token
      gen = @tokenizer.next_token
      tok = @tokenizer.next_token
      unless oid.kind_of?(Integer) && gen.kind_of?(Integer) &&
          tok.kind_of?(Tokenizer::Token) && tok == 'obj'.freeze
        raise_malformed("No valid object found", pos: offset)
      end

      if (tok = @tokenizer.peek_token) && tok.kind_of?(Tokenizer::Token) && tok == 'endobj'.freeze
        maybe_raise("No indirect object value between 'obj' and 'endobj'", pos: @tokenizer.pos)
        object = nil
      else
        object = @tokenizer.next_object
      end

      tok = @tokenizer.next_token

      if tok.kind_of?(Tokenizer::Token) && tok == 'stream'.freeze
        unless object.kind_of?(Hash)
          raise_malformed("A stream needs a dictionary, not a(n) #{object.class}", pos: offset)
        end
        tok1 = @tokenizer.next_byte
        tok2 = @tokenizer.next_byte if tok1 == 13 # 13=CR, 10=LF
        if tok1 != 10 && tok1 != 13
          raise_malformed("Keyword stream must be followed by LF or CR/LF", pos: @tokenizer.pos)
        elsif tok1 == 13 && tok2 != 10
          maybe_raise("Keyword stream must be followed by LF or CR/LF, not CR alone",
                      pos: @tokenizer.pos)
          @tokenizer.pos -= 1
        end

        # Note that getting :Length might move the IO pointer (when resolving references)
        pos = @tokenizer.pos
        length = if object[:Length].kind_of?(Integer)
                   object[:Length]
                 elsif object[:Length].kind_of?(Reference)
                   @document.deref(object[:Length]).value
                 else
                   0
                 end
        @tokenizer.pos = pos + length

        tok = @tokenizer.next_token
        unless tok.kind_of?(Tokenizer::Token) && tok == 'endstream'.freeze
          maybe_raise("Invalid stream length, keyword endstream not found", pos: @tokenizer.pos)
          @tokenizer.pos = pos
          if @tokenizer.scan_until(/(?=\n?endstream)/)
            length = @tokenizer.pos - pos
            tok = @tokenizer.next_token
          else
            raise_malformed("Stream content must be followed by keyword endstream",
                            pos: @tokenizer.pos)
          end
        end
        tok = @tokenizer.next_token

        object[:Length] = length
        stream = StreamData.new(@tokenizer.io, offset: pos, length: length,
                                filter: @document.unwrap(object[:Filter]),
                                decode_parms: @document.unwrap(object[:DecodeParms]))
      end

      unless tok.kind_of?(Tokenizer::Token) && tok == 'endobj'.freeze
        maybe_raise("Indirect object must be followed by keyword endobj", pos: @tokenizer.pos)
      end

      [object, oid, gen, stream]
    end

    # Loads the compressed object identified by the cross-reference entry.
    def load_compressed_object(xref_entry)
      unless @object_stream_data.key?(xref_entry.objstm)
        obj = @document.object(xref_entry.objstm)
        unless obj.respond_to?(:parse_stream)
          raise_malformed("Object with oid=#{xref_entry.objstm} is not an object stream")
        end
        @object_stream_data[xref_entry.objstm] = obj.parse_stream
      end

      [*@object_stream_data[xref_entry.objstm].object_by_index(xref_entry.pos), xref_entry.gen, nil]
    end

    # Loads a single revision whose cross-reference section/stream is located at the given
    # position.
    #
    # Returns an HexaPDF::XRefSection object and the accompanying trailer dictionary.
    def load_revision(pos)
      if xref_section?(pos)
        xref_section, trailer = parse_xref_section_and_trailer(pos)
      else
        obj = load_object(XRefSection.in_use_entry(0, 0, pos))
        unless obj.respond_to?(:xref_section)
          raise_malformed("Object is not a cross-reference stream", pos: pos)
        end
        xref_section = obj.xref_section
        trailer = obj.trailer
        unless xref_section.entry?(obj.oid, obj.gen)
          maybe_raise("Cross-reference stream doesn't contain entry for itself", pos: pos)
          xref_section.add_in_use_entry(obj.oid, obj.gen, pos)
        end
      end
      xref_section.delete(0)
      [xref_section, trailer]
    end

    # Looks at the given offset and returns +true+ if there is a cross-reference section at that
    # position.
    def xref_section?(offset)
      @tokenizer.pos = offset + @header_offset
      token = @tokenizer.peek_token
      token.kind_of?(Tokenizer::Token) && token == 'xref'
    end

    # Parses the cross-reference section at the given position and the following trailer and
    # returns them as an array consisting of an HexaPDF::XRefSection instance and a hash.
    #
    # This method can only parse cross-reference sections, not cross-reference streams!
    #
    # See: PDF1.7 s7.5.4, s7.5.5; ADB1.7 sH.3-3.4.3
    def parse_xref_section_and_trailer(offset)
      @tokenizer.pos = offset + @header_offset
      token = @tokenizer.next_token
      unless token.kind_of?(Tokenizer::Token) && token == 'xref'
        raise_malformed("Xref section doesn't start with keyword xref", pos: @tokenizer.pos)
      end

      xref = XRefSection.new
      start = @tokenizer.next_token
      while start.kind_of?(Integer)
        number_of_entries = @tokenizer.next_token
        unless number_of_entries.kind_of?(Integer)
          raise_malformed("Invalid cross-reference subsection start", pos: @tokenizer.pos)
        end

        @tokenizer.skip_whitespace
        start.upto(start + number_of_entries - 1) do |oid|
          pos, gen, type = @tokenizer.next_xref_entry do |matched_size|
            maybe_raise("Invalid cross-reference subsection entry", pos: @tokenizer.pos,
                        force: matched_size == 20)
          end
          if xref.entry?(oid)
            next
          elsif type == 'n'.freeze
            if pos == 0 || gen > 65535
              maybe_raise("Invalid in use cross-reference entry in cross-reference section",
                          pos: @tokenizer.pos)
              xref.add_free_entry(oid, gen)
            else
              xref.add_in_use_entry(oid, gen, pos)
            end
          else
            xref.add_free_entry(oid, gen)
          end
        end
        start = @tokenizer.next_token
      end

      unless start.kind_of?(Tokenizer::Token) && start == 'trailer'
        raise_malformed("Trailer doesn't start with keyword trailer", pos: @tokenizer.pos)
      end

      trailer = @tokenizer.next_object
      unless trailer.kind_of?(Hash)
        raise_malformed("Trailer is a #{trailer.class} instead of a dictionary ", pos: @tokenizer.pos)
      end

      [xref, trailer]
    end

    # Returns the offset of the main cross-reference section/stream.
    #
    # Implementation note: Normally, the %%EOF marker has to be on the last line, however, Adobe
    # viewers relax this restriction and so do we.
    #
    # If strict parsing is disabled, the whole file is searched for the offset.
    #
    # See: PDF1.7 s7.5.5, ADB1.7 sH.3-3.4.4
    def startxref_offset
      @io.seek(0, IO::SEEK_END)
      step_size = 1024
      pos = @io.pos
      eof_not_found = startxref_missing = false

      while pos != 0
        @io.pos = [pos - step_size, 0].max
        pos = @io.pos
        lines = @io.read(step_size + 40).split(/[\r\n]+/)

        eof_index = lines.rindex {|l| l.strip == '%%EOF' }
        unless eof_index
          eof_not_found = true
          next
        end
        unless eof_index >= 2 && lines[eof_index - 2].strip == "startxref"
          startxref_missing = true
          next
        end

        break # we found the startxref offset
      end

      if eof_not_found
        maybe_raise("PDF file trailer with end-of-file marker not found", pos: pos,
                    force: !eof_index)
      elsif startxref_missing
        maybe_raise("PDF file trailer is missing startxref keyword", pos: pos,
                    force: eof_index < 2 || lines[eof_index - 2].strip != "startxref")
      end

      lines[eof_index - 1].to_i
    end

    # Returns the PDF version number that is stored in the file header.
    #
    # See: PDF1.7 s7.5.2
    def file_header_version
      unless @header_version
        raise_malformed("PDF file header is missing or corrupt", pos: 0)
      end
      @header_version
    end

    private

    # Retrieves the offset of the PDF header and the PDF version number in it.
    #
    # The PDF header should normally appear on the first line. However, Adobe relaxes this
    # restriction so that the header may appear in the first 1024 bytes. We follow the Adobe
    # convention.
    #
    # See: PDF1.7 s7.5.2, ADB1.7 sH.3-3.4.1
    def retrieve_pdf_header_offset_and_version
      @io.seek(0)
      @header_offset = @io.read(1024).index(/%PDF-(\d\.\d)/) || 0
      @header_version = $1
    end

    # Raises a HexaPDF::MalformedPDFError with the given message and source position.
    def raise_malformed(msg, pos: nil)
      raise HexaPDF::MalformedPDFError.new(msg, pos: pos)
    end

    # Calls the block stored in the config option +parser.on_correctable_error+ with the document,
    # the given message and the position. If the returned value is +true+, raises a
    # HexaPDF::MalformedPDFError. Otherwise the error is corrected and parsing continues.
    #
    # If the option +force+ is used, the block is not called and the error is raised immediately.
    def maybe_raise(msg, pos: nil, force: false)
      if force || @document.config['parser.on_correctable_error'].call(@document, msg, pos)
        error = HexaPDF::MalformedPDFError.new(msg, pos: pos)
        error.set_backtrace(caller(1))
        raise error
      end
    end

  end

end
