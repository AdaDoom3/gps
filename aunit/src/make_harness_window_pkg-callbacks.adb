-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                      Copyright (C) 2001-2004                      --
--                            ACT-Europe                             --
--                                                                   --
-- GPS is free  software;  you can redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this program; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with Gtk.Main;        use Gtk.Main;
with File_Utils;      use File_Utils;
with Ada.Text_IO;     use Ada.Text_IO;
with Case_Handling;   use Case_Handling;

with Gtkada.Dialogs;  use Gtkada.Dialogs;

with Pixmaps_IDE;     use Pixmaps_IDE;

with Aunit_Filters;   use Aunit_Filters;
with Gtkada.Handlers; use Gtkada.Handlers;

with Gdk.Pixbuf;      use Gdk.Pixbuf;
with GPS.Intl;      use GPS.Intl;
with VFS;             use VFS;

package body Make_Harness_Window_Pkg.Callbacks is
   --  Callbacks for main "AUnit_Make_Harness" window. Template
   --  generated by Glade

   use Gtk.Arguments;

   -----------------------
   -- Local subprograms --
   -----------------------

   procedure On_Ok_Button_Clicked
     (Object : access Gtk_Widget_Record'Class);

   procedure On_Cancel_Button_Clicked
     (Object : access Gtk_Widget_Record'Class);

   ---------------------------------------
   -- On_Make_Harness_Window_Delete_Event --
   ---------------------------------------

   function On_Make_Harness_Window_Delete_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean
   is
      pragma Unreferenced (Params);
   begin
      Hide (Get_Toplevel (Object));
      Main_Quit;
      return True;
   end On_Make_Harness_Window_Delete_Event;

   ---------------------------------
   -- On_Procedure_Entry_Activate --
   ---------------------------------

   procedure On_Procedure_Entry_Activate
     (Object : access Gtk_Entry_Record'Class)
   is
      --  Initialize and set default focus
      Win : constant Make_Harness_Window_Access :=
        Make_Harness_Window_Access (Get_Toplevel (Object));

   begin
      Grab_Focus (Win.Ok);
   end On_Procedure_Entry_Activate;

   ----------------------------
   -- On_Name_Entry_Activate --
   ----------------------------

   procedure On_Name_Entry_Activate
     (Object : access Gtk_Entry_Record'Class)
   is
      Win : constant Make_Harness_Window_Access :=
        Make_Harness_Window_Access (Get_Toplevel (Object));

   begin
      Grab_Focus (Win.Ok);
   end On_Name_Entry_Activate;

   --------------------------
   -- On_Ok_Button_Clicked --
   --------------------------

   procedure On_Ok_Button_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
      Harness_Window : constant Make_Harness_Window_Access :=
        Make_Harness_Window_Access (Get_Toplevel (Object));

      S              : constant Virtual_File :=
        Get_Selection (Harness_Window.Explorer);
      Suite_Name     : String_Access;
      Package_Name   : String_Access;
      Id             : constant Context_Id :=
        Get_Context_Id (Harness_Window.Statusbar, "messages");
      Message        : Message_Id;
      pragma Unreferenced (Message);

   begin
      Hide (Harness_Window.Explorer);

      if S = VFS.No_File then
         return;
      end if;

      Get_Suite_Name (Full_Name (S).all, Package_Name, Suite_Name);

      if Suite_Name /= null
        and then Package_Name /= null
      then
         Harness_Window.Suite_Name := Suite_Name;
         Message := Push
           (Harness_Window.Statusbar, Id,
            -"Found suite: " & Harness_Window.Suite_Name.all);

      else
         Message := Push
           (Harness_Window.Statusbar, Id,
            -"Warning: no suite was found in that file.");
      end if;

      Set_Text (Harness_Window.File_Name_Entry, Full_Name (S).all);
   end On_Ok_Button_Clicked;

   ------------------------------
   -- On_Cancel_Button_Clicked --
   ------------------------------

   procedure On_Cancel_Button_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
      Suite_Window : constant Make_Harness_Window_Access :=
        Make_Harness_Window_Access (Get_Toplevel (Object));
   begin
      Hide (Suite_Window.Explorer);
   end On_Cancel_Button_Clicked;

   -----------------------
   -- On_Browse_Clicked --
   -----------------------

   procedure On_Browse_Clicked
     (Object : access Gtk_Button_Record'Class)
   is
      --  Open explorer window to select suite
      Harness_Window : constant Make_Harness_Window_Access :=
        Make_Harness_Window_Access (Get_Toplevel (Object));

      Filter_A : Filter_Show_All_Access;
      Filter_B : Filter_Show_Ada_Access;
      Filter_C : Filter_Show_Suites_Access;
   begin
      if Harness_Window.Explorer = null then
         Filter_A := new Filter_Show_All;
         Filter_B := new Filter_Show_Ada;
         Filter_C := new Filter_Show_Suites;

         Filter_A.Label := new String'(-"All files");
         Filter_B.Label := new String'(-"Ada files");
         Filter_C.Label := new String'(-"Suite files");

         Filter_C.Pixbuf := Gdk_New_From_Xpm_Data (box_xpm);
         Filter_B.Spec_Pixbuf := Gdk_New_From_Xpm_Data (box_xpm);
         Filter_B.Body_Pixbuf := Gdk_New_From_Xpm_Data (package_xpm);

         Gtk_New
           (Harness_Window.Explorer,
            "/",
            Name_As_Directory (Get_Text (Harness_Window.Directory_Entry)),
            -"Select test harness",
            History => null); --  ??? No history

         Register_Filter (Harness_Window.Explorer, Filter_C);
         Register_Filter (Harness_Window.Explorer, Filter_B);
         Register_Filter (Harness_Window.Explorer, Filter_A);

         Widget_Callback.Object_Connect
           (Get_Ok_Button (Harness_Window.Explorer),
            "clicked", On_Ok_Button_Clicked'Access,
            Gtk_Widget (Harness_Window));
         Widget_Callback.Object_Connect
           (Get_Cancel_Button (Harness_Window.Explorer),
            "clicked",
            On_Cancel_Button_Clicked'Access,
            Gtk_Widget (Harness_Window));
      end if;

      Show_All (Harness_Window.Explorer);
   end On_Browse_Clicked;

   ---------------------------------
   -- On_Browse_Directory_Clicked --
   ---------------------------------

   procedure On_Browse_Directory_Clicked
     (Object : access Gtk_Button_Record'Class)
   is
      --  Open explorer window to select suite
      Harness_Window : constant Make_Harness_Window_Access :=
        Make_Harness_Window_Access (Get_Toplevel (Object));
   begin
      Browse_Location (Harness_Window.Directory_Entry);
   end On_Browse_Directory_Clicked;

   -------------------
   -- On_Ok_Clicked --
   -------------------

   procedure On_Ok_Clicked (Object : access Gtk_Button_Record'Class) is
      --  Generate harness body source file. Close window and main loop if
      --  successful

      Top            : constant Make_Harness_Window_Access :=
        Make_Harness_Window_Access (Get_Toplevel (Object));
      File           : File_Type;
      Directory_Name : constant String := Get_Text (Top.Directory_Entry);
      Procedure_Name : String := Get_Text (Top.Procedure_Entry);
      File_Name      : String := Get_Text (Top.File_Name_Entry);
      Filename       : constant String := Name_As_Directory
        (Directory_Name) & To_File_Name (Procedure_Name);

   begin
      if Directory_Name /= ""
        and then Is_Directory (Directory_Name)
        and then Procedure_Name /= ""
        and then File_Name /= ""
      then
         Mixed_Case (Procedure_Name);
         Mixed_Case (File_Name);

         if Top.Suite_Name = null then
            Top.Suite_Name := new String'("");
         end if;

         if Is_Regular_File (Filename & ".adb") then
            if Message_Dialog
              ("File " & To_File_Name (Procedure_Name)
               & ".adb" & " exists. Overwrite?",
               Warning,
               Button_Yes or Button_No,
               Button_No,
               "",
               "Warning !") = Button_No
            then
               return;
            end if;
         end if;

         Ada.Text_IO.Create
           (File, Out_File, Filename & ".adb");
         Put_Line
           (File,
            "with AUnit.Test_Runner;" & ASCII.LF
            & "with " &
            Top.Suite_Name.all & ";"
            & ASCII.LF
            & ASCII.LF
            & "procedure " & Procedure_Name & " is" & ASCII.LF
            & ASCII.LF
            & "   procedure Run is new AUnit.Test_Runner ("
            & Top.Suite_Name.all
            & ");"
            & ASCII.LF
            & ASCII.LF
            & "begin"  & ASCII.LF
            & "   Run;" & ASCII.LF
            & "end " & Procedure_Name & ";");
         Close (File);
         Top.Procedure_Name := new String'(Filename);
      end if;

      Hide (Top);
      Main_Quit;
   end On_Ok_Clicked;

   -----------------------
   -- On_Cancel_Clicked --
   -----------------------

   procedure On_Cancel_Clicked (Object : access Gtk_Button_Record'Class) is
   begin
      Hide (Get_Toplevel (Object));
      Main_Quit;
   end On_Cancel_Clicked;

end Make_Harness_Window_Pkg.Callbacks;
