-----------------------------------------------------------------------
--                 Odd - The Other Display Debugger                  --
--                                                                   --
--                         Copyright (C) 2000                        --
--                 Emmanuel Briot and Arnaud Charlet                 --
--                                                                   --
-- Odd is free  software;  you can redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this library; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with System; use System;
with Glib; use Glib;
with Gtk.Notebook; use Gtk.Notebook;
with Gtk.Widget; use Gtk.Widget;
with Odd.Process; use Odd.Process;
with Debugger; use Debugger;
with Main_Debug_Window_Pkg; use Main_Debug_Window_Pkg;
with Process_Proxies; use Process_Proxies;
with Gtk.Clist;       use Gtk.Clist;
with Gtk.Enums;       use Gtk.Enums;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;

package body Odd.Dialogs.Callbacks is

   use Odd;
   use Gtk.Arguments;

   ----------------------------------
   -- On_Backtrace_List_Select_Row --
   ----------------------------------

   procedure On_Backtrace_List_Select_Row
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args)
   is
      Frame       : constant Gint         := To_Gint (Params, 1) + 1;

      --  Get the process notebook from the main window which is associated
      --  with the task dialog (toplevel (object)).

      Main_Window : constant Gtk_Window   :=
        Backtrace_Dialog_Access (Get_Toplevel (Object)).Main_Window;
      Notebook    : constant Gtk_Notebook :=
        Main_Debug_Window_Access (Main_Window).Process_Notebook;

      --  Get the current page in the process notebook.

      Process     : constant Debugger_Process_Tab :=
        Process_User_Data.Get (Get_Nth_Page
          (Notebook, Get_Current_Page (Notebook)));

   begin
      Stack_Frame (Process.Debugger, Positive (Frame), True);
   end On_Backtrace_List_Select_Row;

   ----------------------------------
   -- On_Backtrace_Process_Stopped --
   ----------------------------------

   procedure On_Backtrace_Process_Stopped
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args)
   is
      Bt       : Backtrace_Array (1 .. Max_Frame);
      Len      : Natural;
      Dialog   : constant Backtrace_Dialog_Access :=
        Debugger_Process_Tab (Object).Window.Backtrace_Dialog;
      Process  : Process_Proxy_Access;
      Internal : Boolean;

   begin
      if Visible_Is_Set (Dialog) then
         Process := Get_Process (Debugger_Process_Tab (Object).Debugger);
         Internal := Is_Internal_Command (Process);
         Push_Internal_Command_Status (Process, True);
         Backtrace (Debugger_Process_Tab (Object).Debugger, Bt, Len);
         Pop_Internal_Command_Status (Process);
         Update (Dialog, Bt (1 .. Len));
         Free  (Bt (1 .. Len));
      end if;
   end On_Backtrace_Process_Stopped;

   -----------------------------
   -- On_Task_List_Select_Row --
   -----------------------------

   procedure On_Task_List_Select_Row
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args)
   is
      --  Since lists start at 0, increment the value.
      Thread        : constant Gint := To_Gint (Params, 1) + 1;

      --  Get the process notebook from the main window which is associated
      --  with the task dialog (toplevel (object)).

      Notebook      : constant Gtk_Notebook :=
        Main_Debug_Window_Access (Task_Dialog_Access
        (Get_Toplevel (Object)).Main_Window).Process_Notebook;

      --  Get the current page in the process notebook.

      Process       : Debugger_Process_Tab :=
        Process_User_Data.Get (Get_Nth_Page
          (Notebook, Get_Current_Page (Notebook)));

   begin
      Thread_Switch (Process.Debugger, Natural (Thread));
   end On_Task_List_Select_Row;

   -----------------------------
   -- On_Task_Process_Stopped --
   -----------------------------

   procedure On_Task_Process_Stopped
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args)
   is
      Dialog   : constant Task_Dialog_Access :=
        Debugger_Process_Tab (Object).Window.Task_Dialog;
      Process  : Process_Proxy_Access;
      Internal : Boolean;

   begin
      if Visible_Is_Set (Dialog) then
         Process := Get_Process (Debugger_Process_Tab (Object).Debugger);
         Internal := Is_Internal_Command (Process);
         Push_Internal_Command_Status (Process, True);

         declare
            Info : Thread_Information_Array :=
              Info_Threads (Debugger_Process_Tab (Object).Debugger);
         begin
            Update (Dialog, Info);
            Free (Info);
         end;

         Pop_Internal_Command_Status (Process);
      end if;
   end On_Task_Process_Stopped;

   -----------------------------
   -- On_Close_Button_Clicked --
   -----------------------------

   procedure On_Close_Button_Clicked
     (Object : access Gtk_Button_Record'Class) is
   begin
      Hide (Get_Toplevel (Object));
   end On_Close_Button_Clicked;

   ----------------------------
   -- On_Question_OK_Clicked --
   ----------------------------

   procedure On_Question_OK_Clicked
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args)
   is
      use type Gint_List.Glist;

      Dialog      : constant Question_Dialog_Access :=
        Question_Dialog_Access (Get_Toplevel (Object));

      Selection : constant Gint_List.Glist := Get_Selection (Dialog.List);
      S         : Unbounded_String;
      Tmp       : Gint_List.Glist := Gint_List.First (Selection);

   begin
      while Tmp /= Gint_List.Null_List loop
         Append (S, Get_Text (Dialog.List, Gint_List.Get_Data (Tmp), 0));
         Tmp := Gint_List.Next (Tmp);
      end loop;

      Send (Dialog.Debugger,
            To_String (S),
            Display => True,
            Empty_Buffer => False,
            Wait_For_Prompt => False);

      --  This dialog is destroyed, not simply hidden, since it has to
      --  be recreated from scratch every time anyway.

      Unregister_Dialog (Convert (Dialog.Main_Window, Dialog.Debugger));
   end On_Question_OK_Clicked;

   -------------------------------
   -- On_Question_Close_Clicked --
   -------------------------------

   procedure On_Question_Close_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
      Dialog      : constant Question_Dialog_Access :=
        Question_Dialog_Access (Get_Toplevel (Object));
   begin
      --  Send the interrupt signal to the debugger, so that it does not keep
      --  waiting for user input.
      Interrupt (Dialog.Debugger);

      --  Destroy the dialog, since we will have to recreate it anyway.
      Unregister_Dialog (Convert (Dialog.Main_Window, Dialog.Debugger));
   end On_Question_Close_Clicked;

end Odd.Dialogs.Callbacks;
