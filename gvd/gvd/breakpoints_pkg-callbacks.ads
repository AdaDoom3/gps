with Gtk.Widget; use Gtk.Widget;
with Gtk.Arguments; use Gtk.Arguments;

package Breakpoints_Pkg.Callbacks is
   function On_Breakpoints_Delete_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean;

   procedure On_Notebook1_Switch_Page
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args);

   procedure On_Location_Selected_Toggled
     (Object : access Gtk_Widget_Record'Class);

   procedure On_Subprogam_Selected_Toggled
     (Object : access Gtk_Widget_Record'Class);

   procedure On_Address_Selected_Toggled
     (Object : access Gtk_Widget_Record'Class);

   procedure On_Regexp_Selected_Toggled
     (Object : access Gtk_Widget_Record'Class);

   procedure On_Add_Location_Clicked
     (Object : access Gtk_Widget_Record'Class);

   procedure On_Advanced_Location_Clicked
     (Object : access Gtk_Widget_Record'Class);

   procedure On_Add_Watchpoint_Clicked
     (Object : access Gtk_Widget_Record'Class);

   procedure On_Advanced_Watchpoint_Clicked
     (Object : access Gtk_Widget_Record'Class);

   procedure On_Add_Exception_Clicked
     (Object : access Gtk_Widget_Record'Class);

   procedure On_Advanced_Exception_Clicked
     (Object : access Gtk_Widget_Record'Class);

   procedure On_Remove_Clicked
     (Object : access Gtk_Widget_Record'Class);

   procedure On_View_Clicked
     (Object : access Gtk_Widget_Record'Class);

   procedure On_Ok_Bp_Clicked
     (Object : access Gtk_Widget_Record'Class);

   procedure Update_Breakpoint_List
     (Editor : access Breakpoints_Pkg.Breakpoints_Record'Class);
   --  Update the list of breakpoints in the dialog.
   --  The list is taken from the one stored in the current debugger session.

end Breakpoints_Pkg.Callbacks;
