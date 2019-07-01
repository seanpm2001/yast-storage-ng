# Copyright (c) [2019] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "yast"
require "yast/i18n"
require "abstract_method"

Yast.import "HTML"

module Y2Partitioner
  module Widgets
    module DescriptionSection
      # Description section to include in the description of a device
      #
      # A description section is composed by several entries, and each entry might have a
      # help field associated to it.
      #
      # A device description (see {DeviceDescription}) is composed by several description
      # sections.
      class Base
        include Yast::I18n

        # Constructor
        #
        # @param device [Y2Storage::Device]
        def initialize(device)
          @device = device
        end

        # Richtext filled with the data of each section entry
        #
        # @return [String]
        def value
          value = Yast::HTML.Heading(title)
          value << Yast::HTML.List(entries_values)
        end

        # Fields to show in help
        #
        # The device description (see {DeviceDescription#help}) shows the help for the entries
        # of each section.
        #
        # @return [Array<Symbol>]
        def help_fields
          entries
        end

        private

        # @return [Y2Storage::Device]
        attr_reader :device

        # @!method title
        #
        #   Section title
        #
        #   @return [String]
        abstract_method :title

        # @!method entries
        #
        #   Entries that compose the description section
        #
        #   It returns a list with the name of all entries that compose the description section.
        #
        #   To provide a help text for an entry, the entry name needs to be added to the {Help}
        #   module. See also {DeviceDescription#help}.
        #
        #   @return [Array<Symbol>]
        abstract_method :entries

        # Entries data generated by calling the value method of each entry
        #
        # Note: for each entry, an `entry_value` method must be defined.
        #
        # @return [Array<String>]
        def entries_values
          entries.map { |e| send("#{e}_value") }
        end
      end
    end
  end
end
