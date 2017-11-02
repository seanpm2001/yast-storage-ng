# encoding: utf-8

# Copyright (c) [2017] SUSE LLC
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
require "y2partitioner/device_graphs"
require "y2storage/filesystems/btrfs"
require "abstract_method"

Yast.import "Popup"
Yast.import "HTML"

module Y2Partitioner
  module Actions
    # Base class for the action to delete a device
    class DeleteDevice
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts

      # Constructor
      # @param device [Y2Storage::Device]
      def initialize(device)
        textdomain "storage"

        @device = device
      end

      # Checks whether delete action can be performed and if so,
      # a confirmation popup is shown.
      #
      # @note Delete action and refresh for shadowing of BtrFS subvolumes
      #   are only performed when user confirms.
      #
      # @see Y2Storage::Filesystems::Btrfs.refresh_subvolumes_shadowing
      #
      # @return [Symbol, nil]
      def run
        return :back unless validate && confirm
        delete
        Y2Storage::Filesystems::Btrfs.refresh_subvolumes_shadowing(device_graph)

        :finish
      end

    private

      # @return [Y2Storage::Device] device to delete
      attr_reader :device

      # Current devicegraph
      #
      # @return [Y2Storage::Devicegraph]
      def device_graph
        DeviceGraphs.instance.current
      end

      # Deletes the indicated device
      #
      # @note Derived classes should implement this method.
      abstract_method :delete

      # Validations before performing the delete action
      #
      # @return [Boolean]
      def validate
        true
      end

      # Confirmation message before performing the delete action
      def confirm
        Yast::Popup.YesNo(
          # TRANSLATORS %s is the name of the device to be deleted (e.g., /dev/sda1)
          format(_("Really delete %s?"), device.name)
        )
      end

      # Devices that depends on the device to delete
      #
      # For example, a Vg depends on some partitions used as physical volumes,
      # so the vg should be deleted when one of that partitions is deleted.
      #
      # This method obtains the name of all devices that should be deleted when
      # the current device is deleted. This info is useful for some confirm messages.
      #
      # @see DeleteDisk@confirm
      #
      # @return [Array<String>] name of dependent devices
      def dependent_devices
        device.descendants.map do |dev|
          dev.name if dev.respond_to?(:name)
        end.compact
      end

      # Helpful method to show a descriptive confirm message with all affected devices
      #
      # @see DeleteDisk@confirm
      def confirm_recursive_delete(devices, headline, label_before, label_after)
        button_box = ButtonBox(
          PushButton(Id(:yes), Opt(:okButton), Yast::Label.DeleteButton),
          PushButton(
            Id(:no_button),
            Opt(:default, :cancelButton),
            Yast::Label.CancelButton
          )
        )

        fancy_question(headline,
          label_before,
          Yast::HTML.List(devices.sort),
          label_after,
          button_box)
      end

      # @param rich_text [String]
      # @return [Boolean]
      def fancy_question(headline, label_before, rich_text, label_after, button_term)
        display_info = Yast::UI.GetDisplayInfo || {}
        has_image_support = display_info["HasImageSupport"]

        layout = VBox(
          VSpacing(0.4),
          HBox(
            has_image_support ? Top(Image(Yast::Icon.IconPath("question"))) : Empty(),
            HSpacing(1),
            VBox(
              Left(Heading(headline)),
              VSpacing(0.2),
              Left(Label(label_before)),
              VSpacing(0.2),
              Left(RichText(rich_text)),
              VSpacing(0.2),
              Left(Label(label_after)),
              button_term
            )
          )
        )

        Yast::UI.OpenDialog(layout)
        ret = Yast::UI.UserInput
        Yast::UI.CloseDialog

        ret == :yes
      end
    end
  end
end
