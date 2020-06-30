# Copyright (c) [2020] SUSE LLC
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
require "abstract_method"
require "y2partitioner/device_graphs"

module Y2Partitioner
  module Widgets
    module Columns
      # Base class for all widgets representing a column in a table displaying a list of devices
      class Base
        extend Yast::I18n
        include Yast::I18n
        include Yast::UIShortcuts

        # Constructor
        def initialize
          textdomain "storage"
        end

        # @!method title
        #   Title of the column
        #
        #   @return [String, Yast::Term]
        abstract_method :title

        # @!method value_for(device)
        #   The value to display for the given device
        #
        #   @param device [Y2Storage::Device, Y2Storage::SimpleEtcFstabEntry]
        #   @return [String, Yast::Term]
        abstract_method :value_for

        # Convenience method to internally identify the column
        #
        # @note The column id is used to find its help text in the {Y2Partitioner::Widgets::Help}
        #   module. Ideally, each column should have its own #help_text method but those texts still
        #   being shared with the device overview (see {Y2Partitioner:: Widgets::DeviceDescription}.
        #
        # @return [Symbol] usually, the column type
        def symbol
          self.class.name
            .gsub(/^.*::/, "") # demodulize
            .gsub(/(.)([A-Z])/, "\1_\2") # underscore
            .downcase.to_sym
        end

        private

        # Helper method to create a `cell` term
        #
        # @param args [Array] content of the cell
        # @return [Yast::Term]
        def cell(*args)
          Yast::Term.new(:cell, *args.compact)
        end

        # Helper method to create a `sortKey` term
        #
        # @param value [String] a value to be used as a sort key
        # @return [Yast::Term]
        def sort_key(value)
          Yast::Term.new(:sortKey, value)
        end

        # @return [Y2Storage::Devicegraph]
        def system_graph
          DeviceGraphs.instance.system
        end

        # Returns the filesystem for the given device, when possible
        #
        # @return [Y2Storage::Filesystems::Base, nil]
        def filesystem_for(device)
          if device.is?(:filesystem)
            device
          elsif device.respond_to?(:filesystem)
            device.filesystem
          end
        end

        # Whether the device belongs to a multi-device filesystem
        #
        # @param device [Device]
        # @return [Boolean]
        def part_of_multidevice?(device, filesystem)
          return false unless device.is?(:blk_device)

          filesystem.multidevice?
        end

        # Determines if given device is actually an fstab entry
        #
        # @return [Boolean]
        def fstab_entry?(device)
          device.is_a?(Y2Storage::SimpleEtcFstabEntry)
        end
      end
    end
  end
end
