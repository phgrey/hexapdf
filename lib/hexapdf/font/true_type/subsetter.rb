# -*- encoding: utf-8 -*-
#
#--
# This file is part of HexaPDF.
#
# HexaPDF - A Versatile PDF Creation and Manipulation Library For Ruby
# Copyright (C) 2016 Thomas Leitner
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

module HexaPDF
  module Font
    module TrueType

      # Subsets a TrueType font in the context of PDF.
      #
      # TrueType fonts can be embedded into PDF either as a simple font or as a composite font. This
      # subsetter implements the functionality needed when embedding a TrueType subset for a
      # composite font.
      #
      # This means in particular that the resulting font file cannot be used outside of the PDF.
      class Subsetter

        # Creates a new Subsetter for the given TrueType Font object.
        def initialize(font)
          @font = font
          @glyph_map = {0 => 0}
          @last_id = 0
        end

        # Includes the glyph with the given ID in the subset and returns the new subset glyph ID.
        #
        # Can be called multiple times with the same glyph ID, always returning the correct new
        # subset glyph ID.
        def use_glyph(glyph_id)
          return @glyph_map[glyph_id] if @glyph_map.key?(glyph_id)
          @last_id += 1
          @glyph_map[glyph_id] = @last_id
        end

        # Builds the subset font file and returns it as a binary string.
        def build_font
          glyf, locations = build_glyf_table
          loca = build_loca_table(locations)
          hmtx = build_hmtx_table
          head = build_head_table(modified: Time.now, loca_type: 1)
          hhea = build_hhea_table(@glyph_map.size)
          maxp = build_maxp_table(@glyph_map.size)

          tables = {
            'head' => head,
            'hhea' => hhea,
            'maxp' => maxp,
            'glyf' => glyf,
            'loca' => loca,
            'hmtx' => hmtx,
          }
          tables['cvt '] = @font[:"cvt "].raw_data if @font[:"cvt "]
          tables['fpgm'] = @font[:fpgm].raw_data if @font[:fpgm]
          tables['prep'] = @font[:prep].raw_data if @font[:prep]

          search_range = 2**(tables.length.bit_length - 1) * 16
          entry_selector = tables.length.bit_length - 1
          range_shift = tables.length * 16 - search_range

          font_data = "\x0\x1\x0\x0".b + \
            [tables.length, search_range, entry_selector, range_shift].pack('n4')

          offset = font_data.length + tables.length * 16
          checksum = Table.calculate_checksum(font_data)

          tables.each do |tag, data|
            table_checksum = Table.calculate_checksum(data)
            # tag, offset, data.length are all 32bit uint, table_checksum for header and body
            checksum += tag.unpack('N').first + 2 * table_checksum + offset + data.length
            font_data << [tag, table_checksum, offset, data.length].pack('a4N3')
            offset += data.length
          end

          head[8, 4] = [0xB1B0AFBA - checksum].pack('N')
          tables.each_value {|data| font_data << data}

          font_data
        end

        private

        # Builds the glyf table.
        def build_glyf_table
          add_glyph_components

          orig_glyf = @font[:glyf]
          table = ''.b
          locations = []

          @glyph_map.each_key do |old_gid|
            glyph = orig_glyf[old_gid]
            locations << table.size
            data = glyph.raw_data
            if glyph.compound?
              data = data.dup
              glyph.component_offsets.each_with_index do |offset, index|
                data[offset, 2] = [@glyph_map[glyph.components[index]]].pack('n')
              end
            end
            table << data
          end

          locations << table.size

          [table, locations]
        end

        # Builds the loca table given the locations.
        def build_loca_table(locations)
          locations.pack('N*')
        end

        # Builds the hmtx table.
        def build_hmtx_table
          hmtx = @font[:hmtx]
          data = ''.b
          @glyph_map.each_key do |old_gid|
            metric = hmtx[old_gid]
            data << [metric.advance_width, metric.left_side_bearing].pack('n2'.freeze)
          end
          data
        end

        # Builds the hhea table, adjusting the value of the number of horizontal metrics.
        def build_hhea_table(num_of_long_hor_metrics)
          data = @font[:hhea].raw_data
          data[-2, 2] = [num_of_long_hor_metrics].pack('n')
          data
        end

        # Builds the head table, adjusting the modification time and location table type.
        def build_head_table(modified:, loca_type:)
          data = @font[:head].raw_data
          data[8, 4] = "\0\0\0\0"
          data[28, 8] = [(modified - TrueType::Table::TIME_EPOCH).to_i].pack('q>')
          data[-4, 2] = [loca_type].pack('n')
          data
        end

        # Builds the maxp table, adjusting the number of glyphs.
        def build_maxp_table(nr_of_glyphs)
          data = @font[:maxp].raw_data
          data[4, 2] = [nr_of_glyphs].pack('n')
          data
        end

        # Adds the components of compound glyphs to the subset.
        def add_glyph_components
          glyf = @font[:glyf]
          @glyph_map.keys.each {|gid| glyf[gid].components&.each {|cgid| use_glyph(cgid)}}
        end

      end

    end
  end
end