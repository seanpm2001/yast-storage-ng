require "yast"
require "cwm"
require "y2storage"

module Y2Partitioner
  # Partitioner widgets
  module Widgets
    include Yast::Logger

    # The fstab options are mostly checkboxes and combo boxes that share some
    # common methods, so this is a mixin for that shared code.
    module FstabCommon
      def initialize(controller)
        textdomain "storage"

        @controller = controller
      end

      def filesystem
        @controller.filesystem
      end

      def init
        init_regexp if self.class.const_defined?("REGEXP")
      end

      # Not all the fstab options are supported by all the filesystems so each
      # widget is able to check if the current filesystem is supported
      # explicitely or checking if the values it is responsible for are
      # supported by the filesystem.
      def supported_by_filesystem?
        return false if filesystem.nil?

        if self.class.const_defined?("SUPPORTED_FILESYSTEMS")
          self.class::SUPPORTED_FILESYSTEMS
            .include?(filesystem.type.to_sym)
        elsif self.class.const_defined?("VALUES")
          self.class::VALUES.all? do |v|
            filesystem.type.supported_fstab_options.include?(v)
          end
        else
          false
        end
      end

      # @param widget [CWM::AbstractWidget]
      # @return [CWM::WidgetTerm]
      def to_ui_term(widget)
        return Empty() unless widget.supported_by_filesystem?

        Left(widget)
      end

      # @param widget [CWM::AbstractWidget]
      # @return [Array<CWM::WidgetTerm>]
      def ui_term_with_vspace(widget)
        return [Empty()] unless widget.supported_by_filesystem?

        [Left(widget), VSpacing(1)]
      end

      def delete_fstab_option!(option)
        # The options can only be modified using BlkDevice#fstab_options=
        filesystem.fstab_options = filesystem.fstab_options.reject { |o| o =~ option }
      end

      def add_fstab_options(*options)
        # The options can only be modified using BlkDevice#fstab_options=
        filesystem.fstab_options = filesystem.fstab_options + options
      end

      alias_method :add_fstab_option, :add_fstab_options

    private

      # Common regexp checkbox widgets init.
      def init_regexp
        i = filesystem.fstab_options.index { |o| o =~ self.class::REGEXP }

        self.value =
          if i
            filesystem.fstab_options[i].gsub(self.class::REGEXP, "")
          else
            self.class::DEFAULT
          end
      end
    end

    # Push button that launch a dialog to set the fstab options
    class FstabOptionsButton < CWM::PushButton
      include FstabCommon

      def label
        _("Fstab Options...")
      end

      def handle
        log.info("fstab_options before dialog: #{filesystem.fstab_options}")
        Dialogs::FstabOptions.new(@controller).run
        log.info("fstab_options after dialog: #{filesystem.fstab_options}")

        nil
      end
    end

    # FIXME: The help handle does not work without wizard
    # Main widget for set all the available options for a particular filesystem
    class FstabOptions < CWM::CustomWidget
      include FstabCommon

      SUPPORTED_FILESYSTEMS = %i(btrfs ext2 ext3 ext4).freeze

      def initialize(controller)
        @controller = controller

        self.handle_all_events = true
      end

      def init
        disable if !supported_by_filesystem?
      end

      def handle(event)
        case event["ID"]
        when :help
          help = []

          widgets.each do |w|
            help << w.help if w.respond_to? "help"
          end

          Yast::Wizard.ShowHelp(help.join("\n"))
        end

        nil
      end

      def contents
        VBox(
          Left(MountBy.new(@controller)),
          VSpacing(1),
          Left(VolumeLabel.new(@controller)),
          VSpacing(1),
          Left(GeneralOptions.new(@controller)),
          Left(FilesystemsOptions.new(@controller)),
          Left(AclOptions.new(@controller)),
          * ui_term_with_vspace(JournalOptions.new(@controller)),
          Left(ArbitraryOptions.new(@controller))
        )
      end

    private

      def widgets
        Yast::CWM.widgets_in_contents([self])
      end
    end

    # Input field to set the partition Label
    class VolumeLabel < CWM::InputField
      include FstabCommon

      def label
        _("Volume &Label")
      end

      def store
        filesystem.label = value
      end

      def init
        self.value = filesystem.label
      end
    end

    # Group of radio buttons to select the type of identifier to be used for
    # mouth the specific device (UUID, Label, Path...)
    class MountBy < CWM::CustomWidget
      include FstabCommon

      def label
        _("Mount in /etc/fstab by")
      end

      def store
        filesystem.mount_by = selected_mount_by
      end

      def init
        value = filesystem.mount_by ? filesystem.mount_by.to_sym : :uuid
        Yast::UI.ChangeWidget(Id(:mt_group), :Value, value)
      end

      def contents
        RadioButtonGroup(
          Id(:mt_group),
          VBox(
            Left(Label(label)),
            HBox(
              VBox(
                Left(RadioButton(Id(:device), _("&Device Name"))),
                Left(RadioButton(Id(:label), _("Volume &Label"))),
                Left(RadioButton(Id(:uuid), _("&UUID")))
              ),
              Top(
                VBox(
                  Left(RadioButton(Id(:id), _("Device &ID"))),
                  Left(RadioButton(Id(:path), _("Device &Path")))
                )
              )
            )
          )
        )
      end

      def selected_mount_by
        Y2Storage::Filesystems::MountByType.all.detect do |fs|
          fs.to_sym == value
        end
      end

      def value
        Yast::UI.QueryWidget(Id(:mt_group), :Value)
      end
    end

    # A group of options that are general for many filesystem types.
    class GeneralOptions < CWM::CustomWidget
      include FstabCommon

      def contents
        return Empty() unless widgets.any?(&:supported_by_filesystem?)

        VBox(* widgets.map { |w| to_ui_term(w) }, VSpacing(1))
      end

      def widgets
        [
          ReadOnly.new(@controller),
          Noatime.new(@controller),
          MountUser.new(@controller),
          Noauto.new(@controller),
          Quota.new(@controller)
        ]
      end
    end

    # Generic checkbox for fstab options
    # VALUES must be a pair: ["fire", "water"] means "fire" is checked and "water" unchecked
    class FstabCheckBox < CWM::CheckBox
      include FstabCommon

      def init
        self.value = filesystem.fstab_options.include?(checked_value)
      end

      def store
        delete_fstab_option!(Regexp.union(options))
        add_fstab_option(checked_value) if value
      end

    private

      def options
        self.class::VALUES
      end

      def checked_value
        self.class::VALUES[0]
      end
    end

    # CheckBox to disable the automount option when starting up
    class Noauto < FstabCheckBox
      VALUES = ["noauto", "auto"].freeze

      def label
        _("Do Not Mount at System &Start-up")
      end
    end

    # CheckBox to enable the read only option ("ro")
    class ReadOnly < FstabCheckBox
      include FstabCommon
      VALUES = ["ro", "rw"].freeze

      def label
        _("Mount &Read-Only")
      end

      def help
        _("<p><b>Mount Read-Only:</b>\n" \
        "Writing to the file system is not possible. Default is false. During installation\n" \
        "the file system is always mounted read-write.</p>")
      end
    end

    # CheckBox to enable the noatime option
    class Noatime < FstabCheckBox
      VALUES = ["noatime", "atime"].freeze

      def label
        _("No &Access Time")
      end

      def help
        _("<p><b>No Access Time:</b>\nAccess times are not " \
        "updated when a file is read. Default is false.</p>\n")
      end
    end

    # CheckBox to enable the user option which means allow to mount the
    # filesystem by an ordinary user
    class MountUser < FstabCheckBox
      VALUES = ["user", "nouser"].freeze

      def label
        _("Mountable by User")
      end

      def help
        _("<p><b>Mountable by User:</b>\nThe file system may be " \
        "mounted by an ordinary user. Default is false.</p>\n")
      end
    end

    # CheckBox to enable the use of user quotas
    class Quota < CWM::CheckBox
      include FstabCommon
      VALUES = ["grpquota", "usrquota"].freeze

      def label
        _("Enable &Quota Support")
      end

      def help
        _("<p><b>Enable Quota Support:</b>\n" \
        "The file system is mounted with user quotas enabled.\n" \
        "Default is false.</p>\n")
      end

      def init
        self.value = filesystem.fstab_options.any? { |o| VALUES.include?(o) }
      end

      def store
        delete_fstab_option!(Regexp.union(VALUES))
        add_fstab_options("usrquota", "grpquota") if value
      end
    end

    # A group of options related to ACLs (access control lists)
    class AclOptions < CWM::CustomWidget
      include FstabCommon

      def contents
        return Empty() unless widgets.any?(&:supported_by_filesystem?)

        VBox(* widgets.map { |w| to_ui_term(w) }, VSpacing(1))
      end

      def widgets
        [
          Acl.new(@controller),
          UserXattr.new(@controller)
        ]
      end
    end

    # CheckBox to enable access control lists (acl)
    class Acl < FstabCheckBox
      include FstabCommon

      VALUES = ["acl", "noacl"].freeze

      def label
        _("&Access Control Lists (ACL)")
      end

      def help
        _("<p><b>Access Control Lists (acl):</b>\n" \
          "Enable POSIX access control lists and thus more fine-grained " \
          "user permissions on the file system. See also man 5 acl.\n")
      end
    end

    # CheckBox to enable extended user attributes (xattr)
    class UserXattr < FstabCheckBox
      include FstabCommon

      VALUES = ["user_xattr", "nouser_xattr"].freeze

      def label
        _("&Extended User Attributes")
      end

      def help
        _("<p><b>Extended User Attributes (user_xattr):</b>\n" \
          "Enable extended attributes (name:value pairs) on files and directories.\n" \
          "This is an extension to ACLs. See also man 7 xattr.\n")
      end
    end

    # Generic ComboBox for fstab options.
    #
    # This uses some constants that each derived class should define:
    #
    # REGEXP [Regex] The regular expression describing the fstab option.
    # If it ends with "=", the value will be appended to it.
    #
    # ITEMS [Array<String>] The items to choose from.
    # The first one is used as the default (initial) value.
    #
    class FstabComboBox < CWM::ComboBox
      include FstabCommon

      # Set the combo box value to the current value matching REGEXP.
      def init
        i = filesystem.fstab_options.index { |o| o =~ self.class::REGEXP }
        self.value = i ? filesystem.fstab_options[i].gsub(self.class::REGEXP, "") : default_value
      end

      # Convert REGEXP to the option string. This is a very basic
      # implementation that just removes a "^" if the regexp contains it.
      # For anything more sophisticated, reimplement this.
      #
      # @return [String]
      def option_str
        self.class::REGEXP.source.delete("^")
      end

      # Overriding FstabCommon::supported_by_filesystem? to make use of the
      # REGEXP and to avoid having to duplicate it in VALUES
      def supported_by_filesystem?
        return false if filesystem.nil?
        filesystem.type.supported_fstab_options.any? { |opt| opt =~ self.class::REGEXP }
      end

      # The default value for the option.
      #
      # @return [String]
      def default_value
        items.first.first
      end

      # Store the current value in the fstab_options.
      # If the value is nil or empty, it will only remove the old value.
      #
      # If option_str (i.e. normally REGEXP) ends with "=", the value is
      # appended to it, otherwise only the value is used.
      # "codepage=" -> "codepage=value"
      # "foo" -> "value"
      def store
        delete_fstab_option!(self.class::REGEXP)
        return if value.nil? || value.empty?

        opt = option_str
        if opt.end_with?("=")
          opt += value
        else
          opt = value
        end
        add_fstab_option(opt)
      end

      # Convert ITEMS to the format expected by the underlying
      # CWM::ComboBox.
      def items
        self.class::ITEMS.map { |val| [val, val] }
      end

      # Widget options
      def opt
        %i(editable hstretch)
      end
    end

    # ComboBox to specify the journal mode to use by the filesystem
    class JournalOptions < FstabComboBox
      REGEXP = /^data=/

      def label
        _("Data &Journaling Mode")
      end

      def default_value
        "ordered"
      end

      def items
        [
          ["journal", _("journal")],
          ["ordered", _("ordered")],
          ["writeback", _("writeback")]
        ]
      end

      def help
        _("<p><b>Data Journaling Mode:</b>\n" \
        "Specifies the journaling mode for file data.\n" \
        "<tt>journal</tt> -- All data is committed to the journal prior to being\n" \
        "written into the main file system. Highest performance impact.<br>\n" \
        "<tt>ordered</tt> -- All data is forced directly out to the main file system\n" \
        "prior to its metadata being committed to the journal. Medium performance impact.<br>\n" \
        "<tt>writeback</tt> -- Data ordering is not preserved. No performance impact.</p>\n")
      end
    end

    # A input field that allows to set other options that are not handled by
    # specific widgets
    #
    # TODO: FIXME: Pending implementation, currently it is only drawing; all the options
    # that it is responsible for should be defined, removing them if not set or
    # supported by the current filesystem.
    class ArbitraryOptions < CWM::InputField
      def initialize(controller)
        @controller = controller
      end

      def opt
        %i(hstretch disabled)
      end

      def label
        _("Arbitrary Option &Value")
      end
    end

    # Some options that are mainly specific for one filesystem
    class FilesystemsOptions < CWM::CustomWidget
      include FstabCommon

      def contents
        return Empty() unless widgets.any?(&:supported_by_filesystem?)

        VBox(* widgets.map { |w| to_ui_term(w) }, VSpacing(1))
      end

      def widgets
        [
          SwapPriority.new(@controller),
          IOCharset.new(@controller),
          Codepage.new(@controller)
        ]
      end
    end

    # Swap priority
    class SwapPriority < CWM::InputField
      include FstabCommon

      VALUES = ["pri="].freeze
      REGEXP  = /^pri=/
      DEFAULT = "42".freeze

      def label
        _("Swap &Priority")
      end

      def store
        delete_fstab_option!(REGEXP)
        add_fstab_option("pri=#{value}") if value
      end

      def help
        _("<p><b>Swap Priority:</b>\nEnter the swap priority. " \
        "Higher numbers mean higher priority.</p>\n")
      end
    end

    # VFAT IOCharset
    class IOCharset < FstabComboBox
      REGEXP = /^iocharset=/
      ITEMS = [
        "", "iso8859-1", "iso8859-15", "iso8859-2", "iso8859-5", "iso8859-7",
        "iso8859-9", "utf8", "koi8-r", "euc-jp", "sjis", "gb2312", "big5",
        "euc-kr"
      ].freeze

      def store
        delete_fstab_option!(/^utf8=.*/)
        super
      end

      def default_value
        iocharset = filesystem.type.iocharset
        ITEMS.include?(iocharset) ? iocharset : ITEMS.first
      end

      def label
        _("Char&set for file names")
      end

      def help
        _("<p><b>Charset for File Names:</b>\nSet the charset used for display " \
        "of file names in Windows partitions.</p>\n")
      end
    end

    # VFAT Codepage
    class Codepage < FstabComboBox
      REGEXP = /^codepage=/
      ITEMS = ["", "437", "852", "932", "936", "949", "950"].freeze

      def default_value
        cp = filesystem.type.codepage
        ITEMS.include?(cp) ? cp : ITEMS.first
      end

      def label
        _("Code&page for short FAT names")
      end

      def help
        _("<p><b>Codepage for Short FAT Names:</b>\nThis codepage is used for " \
        "converting to shortname characters on FAT file systems.</p>\n")
      end
    end
  end
end
