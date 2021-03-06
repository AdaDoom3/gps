------------------------------------------------------------------------------
--                                  G P S                                   --
--                                                                          --
--                     Copyright (C) 2016, AdaCore                          --
--                                                                          --
-- This is free software;  you can redistribute it  and/or modify it  under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  This software is distributed in the hope  that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General  Public  License  distributed  with  this  software;   see  file --
-- COPYING3.  If not, go to http://www.gnu.org/licenses for a complete copy --
-- of the license.                                                          --
------------------------------------------------------------------------------

with Commands;                     use Commands;
with Commands.Interactive;         use Commands.Interactive;
with Debugger;                     use Debugger;
with GNATCOLL.JSON;
with GNATCOLL.Scripts;             use GNATCOLL.Scripts;
with GNATCOLL.Traces;              use GNATCOLL.Traces;
with GPS.Default_Styles;           use GPS.Default_Styles;
with GPS.Editors;                  use GPS.Editors;
with GPS.Editors.Line_Information; use GPS.Editors.Line_Information;
with GPS.Kernel.Actions;           use GPS.Kernel.Actions;
with GPS.Kernel.Contexts;          use GPS.Kernel.Contexts;
with GPS.Kernel.Hooks;             use GPS.Kernel.Hooks;
with GPS.Kernel.Messages;          use GPS.Kernel.Messages;
with GPS.Kernel.Messages.References; use GPS.Kernel.Messages.References;
with GPS.Kernel.Messages.Simple;   use GPS.Kernel.Messages.Simple;
with GPS.Kernel.Modules;           use GPS.Kernel.Modules;
with GPS.Kernel.Modules.UI;        use GPS.Kernel.Modules.UI;
with GPS.Kernel.Preferences;       use GPS.Kernel.Preferences;
with GPS.Kernel.Project;           use GPS.Kernel.Project;
with GPS.Kernel.Properties;        use GPS.Kernel.Properties;
with GPS.Intl;                     use GPS.Intl;
with GPS.Properties;               use GPS.Properties;
with GVD_Module;                   use GVD_Module;
with GVD.Preferences;              use GVD.Preferences;
with GVD.Process;                  use GVD.Process;
with Xref;                         use Xref;
with JSON_Utils;

package body GVD.Breakpoints_List is

   Me : constant Trace_Handle := Create ("Breakpoints");

   type Breakpoints_Module is new Module_ID_Record with record
      Breakpoints : aliased Breakpoint_List;
      --  The list of persistent breakpoints for the current project. This
      --  list can be manipulated even when no debugger is running, and is
      --  loaded/saved to disk as needed
   end record;

   Messages_Category_For_Breakpoints : constant String := "breakpoints";
   Breakpoints_Message_Flags         : constant Message_Flags :=
     (Editor_Side => False,
      Locations   => False,
      Editor_Line => True);

   Module : access Breakpoints_Module;

   type On_Project_Changed is new Simple_Hooks_Function with null record;
   overriding procedure Execute
     (Self   : On_Project_Changed;
      Kernel : not null access Kernel_Handle_Record'Class);
   --  Called when the project changes. This is a good time to load the
   --  persistent breakpoints

   type On_Project_Changing is new File_Hooks_Function with null record;
   overriding procedure Execute
     (Self   : On_Project_Changing;
      Kernel : not null access Kernel_Handle_Record'Class;
      File   : Virtual_File);
   --  Called before the project is changed. This is a good time to save the
   --  persistent breakpoints

   type On_Before_Exit is new Return_Boolean_Hooks_Function with null record;
   overriding function Execute
     (Self   : On_Before_Exit;
      Kernel : not null access Kernel_Handle_Record'Class) return Boolean;
   --  Called before GPS exist. This is a good time to save the persistent
   --  breakpoints.

   type On_Debugger_Terminated is new Debugger_Hooks_Function with null record;
   overriding procedure Execute
     (Self     : On_Debugger_Terminated;
      Kernel   : not null access Kernel_Handle_Record'Class;
      Debugger : access Base_Visual_Debugger'Class);
   --  Called when one debugger terminates. This is a good time to save
   --  persistent breakpoints.

   type On_Debugger_Started is new Debugger_Hooks_Function with null record;
   overriding procedure Execute
     (Self     : On_Debugger_Started;
      Kernel   : not null access Kernel_Handle_Record'Class;
      Debugger : access Base_Visual_Debugger'Class);
   --  Called when one debugger starts. The persistent breakpoints are applied.

   type On_Debugger_Location_Changed is
     new Debugger_Hooks_Function with null record;
   overriding procedure Execute
     (Self     : On_Debugger_Location_Changed;
      Kernel   : not null access Kernel_Handle_Record'Class;
      Debugger : access Base_Visual_Debugger'Class);
   --  Called when the current location has changed in the debugger.
   --  This is a good time to show, on the side of the editor, which lines
   --  have breakpoints.

   procedure Show_Breakpoints_In_All_Editors
     (Kernel : not null access Kernel_Handle_Record'Class);
   --  Update the side column for all editors, and show the breakpoints info

   procedure Add_Information
     (Kernel  : not null access Kernel_Handle_Record'Class;
      B       : Breakpoint_Data);
   --  Create a new message to display information on the side of editors for
   --  that breakpoint.

   --------------
   -- Commands --
   --------------

   type Breakpoint_Command_Mode is (Set, Unset);
   type Set_Breakpoint_Command_At_Line is new Root_Command with record
      File     : GNATCOLL.VFS.Virtual_File;
      Kernel   : not null access Kernel_Handle_Record'Class;
      Line     : Editable_Line_Type;
      Mode     : Breakpoint_Command_Mode;
   end record;
   overriding function Execute
     (Self : access Set_Breakpoint_Command_At_Line) return Command_Return_Type;

   function Create_Set_Breakpoint_Command
     (Kernel : not null access Kernel_Handle_Record'Class;
      Mode   : Breakpoint_Command_Mode;
      File   : GNATCOLL.VFS.Virtual_File;
      Line   : Editable_Line_Type) return Command_Access;
   --  Create a new instance of the command that sets or removes a breakpoint
   --  at a specific location.

   type Set_Breakpoint_Command_Context is new Interactive_Command with record
      On_Line       : Boolean := False;  --  If False, on entity
      Continue_Till : Boolean := False;  --  Continue until given line ?
   end record;
   overriding function Execute
     (Command : access Set_Breakpoint_Command_Context;
      Context : Interactive_Command_Context) return Command_Return_Type;
   --  Set a breakpoint at the line given in the context

   -------------
   -- Filters --
   -------------

   type Subprogram_Variable_Filter is
     new Action_Filter_Record with null record;
   overriding function Filter_Matches_Primitive
     (Filter  : access Subprogram_Variable_Filter;
      Context : Selection_Context) return Boolean;

   type No_Debugger_Or_Stopped_Filter is
     new Action_Filter_Record with null record;
   overriding function Filter_Matches_Primitive
     (Filter  : access No_Debugger_Or_Stopped_Filter;
      Context : Selection_Context) return Boolean;

   ----------------
   -- Properties --
   ----------------

   type Breakpoint_Property_Record is new Property_Record with record
      Kernel      : access Kernel_Handle_Record'Class;
      Breakpoints : Breakpoint_Vectors.Vector;
   end record;
   type Breakpoint_Property is access all Breakpoint_Property_Record'Class;
   overriding procedure Save
     (Property : access Breakpoint_Property_Record;
      Value    : in out GNATCOLL.JSON.JSON_Value);
   overriding procedure Load
     (Property : in out Breakpoint_Property_Record;
      Value    : GNATCOLL.JSON.JSON_Value);

   procedure Save_Persistent_Breakpoints
     (Kernel   : not null access Kernel_Handle_Record'Class);
   --  Save persistent breakpoints to properties.

   ------------------------------
   -- Filter_Matches_Primitive --
   ------------------------------

   overriding function Filter_Matches_Primitive
     (Filter  : access No_Debugger_Or_Stopped_Filter;
      Context : Selection_Context) return Boolean
   is
      pragma Unreferenced (Filter);
      Process : constant Visual_Debugger :=
        Visual_Debugger (Get_Current_Debugger (Get_Kernel (Context)));
   begin
      return Process = null or else not Command_In_Process (Process);
   end Filter_Matches_Primitive;

   ------------------------------
   -- Filter_Matches_Primitive --
   ------------------------------

   overriding function Filter_Matches_Primitive
     (Filter  : access Subprogram_Variable_Filter;
      Context : Selection_Context) return Boolean
   is
      pragma Unreferenced (Filter);
   begin
      if Has_Entity_Name_Information (Context) then
         declare
            Entity : constant Root_Entity'Class := Get_Entity (Context);
         begin
            return Is_Fuzzy (Entity) or else Is_Subprogram (Entity);
         end;
      end if;
      return False;
   end Filter_Matches_Primitive;

   -----------------------------------
   -- Create_Set_Breakpoint_Command --
   -----------------------------------

   function Create_Set_Breakpoint_Command
     (Kernel : not null access Kernel_Handle_Record'Class;
      Mode   : Breakpoint_Command_Mode;
      File   : GNATCOLL.VFS.Virtual_File;
      Line   : Editable_Line_Type) return Command_Access
   is
   begin
      return new Set_Breakpoint_Command_At_Line'
        (Root_Command with
         Kernel => Kernel, Mode => Mode, File => File, Line => Line);
   end Create_Set_Breakpoint_Command;

   ------------------
   -- Break_Source --
   ------------------

   procedure Break_Source
     (Kernel        : not null access Kernel_Handle_Record'Class;
      File          : Virtual_File;
      Line          : Editable_Line_Type;
      Temporary     : Boolean := False)
   is
      Process : constant Visual_Debugger :=
        Visual_Debugger (Get_Current_Debugger (Kernel));

      procedure On_Debugger
        (Self : not null access Base_Visual_Debugger'Class);
      --  Set a breakpoint in a specific instance of the debugger

      procedure On_Debugger
        (Self : not null access Base_Visual_Debugger'Class)
      is
         Num      : Breakpoint_Identifier with Unreferenced;
      begin
         if Self.Command_In_Process then
            Insert
              (Kernel,
               -"The debugger is busy processing a command",
               Mode => Error);
         else
            Num := Visual_Debugger (Self).Debugger.Break_Source
              (File, Line, Temporary => Temporary);
         end if;
      end On_Debugger;

   begin
      if Process = null then
         Module.Breakpoints.List.Append
           (Breakpoint_Data'
              (Location => Kernel.Get_Buffer_Factory.Create_Marker
                   (File   => File,
                    Line   => Line,
                    Column => 1),
               Num         => Module.Breakpoints.Dummy_Id,
               Disposition => (if Temporary then Delete else Keep),
               others      => <>));
         Module.Breakpoints.Dummy_Id :=
           Module.Breakpoints.Dummy_Id + 1;
         Debugger_Breakpoints_Changed_Hook.Run (Kernel, null);
         Show_Breakpoints_In_All_Editors (Kernel);
      else
         For_Each_Debugger (Kernel, On_Debugger'Access);
      end if;
   end Break_Source;

   --------------------
   -- Unbreak_Source --
   --------------------

   procedure Unbreak_Source
     (Kernel        : not null access Kernel_Handle_Record'Class;
      File          : Virtual_File;
      Line          : Editable_Line_Type)
   is
      Process : constant Visual_Debugger :=
        Visual_Debugger (Get_Current_Debugger (Kernel));

      procedure On_Debugger
        (Self : not null access Base_Visual_Debugger'Class);
      --  Remove a breakpoint in a specific instance of the debugger

      procedure On_Debugger
        (Self : not null access Base_Visual_Debugger'Class) is
      begin
         if Self.Command_In_Process then
            Insert
              (Kernel,
               -"The debugger is busy processing a command",
               Mode => Error);
         else
            Visual_Debugger (Self).Debugger.Remove_Breakpoint_At
              (File, Line, Mode => Visible);
         end if;
      end On_Debugger;

   begin
      if Process = null then
         for Idx in Module.Breakpoints.List.First_Index
           .. Module.Breakpoints.List.Last_Index
         loop
            if Get_File (Module.Breakpoints.List (Idx).Location) = File
              and then Get_Line (Module.Breakpoints.List (Idx).Location) = Line
            then
               Module.Breakpoints.List.Delete (Idx);
               exit;
            end if;
         end loop;
         Debugger_Breakpoints_Changed_Hook.Run (Kernel, null);
         Show_Breakpoints_In_All_Editors (Kernel);
      else
         For_Each_Debugger (Kernel, On_Debugger'Access);
      end if;
   end Unbreak_Source;

   -----------------------
   -- Delete_Breakpoint --
   -----------------------

   procedure Delete_Breakpoint
     (Kernel        : not null access Kernel_Handle_Record'Class;
      Num           : Breakpoint_Identifier)
   is
      Process : constant Visual_Debugger :=
        Visual_Debugger (Get_Current_Debugger (Kernel));
   begin
      if Process = null then
         for Idx in Module.Breakpoints.List.First_Index
           .. Module.Breakpoints.List.Last_Index
         loop
            if Module.Breakpoints.List (Idx).Num = Num then
               Module.Breakpoints.List.Delete (Idx);
               exit;
            end if;
         end loop;
         Debugger_Breakpoints_Changed_Hook.Run (Kernel, null);
         Show_Breakpoints_In_All_Editors (Kernel);
      else
         Process.Debugger.Remove_Breakpoint (Num, Mode => GVD.Types.Visible);
      end if;
   end Delete_Breakpoint;

   ---------------------------
   -- Clear_All_Breakpoints --
   ---------------------------

   procedure Clear_All_Breakpoints
     (Kernel        : not null access Kernel_Handle_Record'Class)
   is
      Process : constant Visual_Debugger :=
        Visual_Debugger (Get_Current_Debugger (Kernel));
   begin
      if Process = null then
         Module.Breakpoints.List.Clear;
         Debugger_Breakpoints_Changed_Hook.Run (Kernel, null);
         Show_Breakpoints_In_All_Editors (Kernel);
      else
         --  Only for the current breakpoint, not all
         for Br of Process.Breakpoints.List loop
            Process.Debugger.Remove_Breakpoint
              (Br.Num, Mode => GVD.Types.Visible);
         end loop;

      end if;
   end Clear_All_Breakpoints;

   ----------------------
   -- Break_Subprogram --
   ----------------------

   procedure Break_Subprogram
     (Kernel        : not null access Kernel_Handle_Record'Class;
      Subprogram    : String;
      Temporary     : Boolean := False)
   is
      Process : constant Visual_Debugger :=
        Visual_Debugger (Get_Current_Debugger (Kernel));
      --  Set a breakpoint in a specific instance of the debugger

      procedure On_Debugger
        (Self : not null access Base_Visual_Debugger'Class);

      procedure On_Debugger
        (Self : not null access Base_Visual_Debugger'Class)
      is
         Num      : Breakpoint_Identifier with Unreferenced;
      begin
         if Self.Command_In_Process then
            Insert
              (Kernel,
               -"The debugger is busy processing a command",
               Mode => Error);
         else
            Num := Process.Debugger.Break_Subprogram
              (Subprogram, Temporary => Temporary, Mode => GVD.Types.Visible);
         end if;
      end On_Debugger;

   begin
      if Process = null then
         Module.Breakpoints.List.Append
           (Breakpoint_Data'
              (Subprogram => To_Unbounded_String (Subprogram),
               Num         => Module.Breakpoints.Dummy_Id,
               Disposition => (if Temporary then Delete else Keep),
               others      => <>));
         Module.Breakpoints.Dummy_Id :=
           Module.Breakpoints.Dummy_Id + 1;
         Show_Breakpoints_In_All_Editors (Kernel);
         Show_Breakpoints_In_All_Editors (Kernel);
      else
         For_Each_Debugger (Kernel, On_Debugger'Access);
      end if;
   end Break_Subprogram;

   -------------
   -- Execute --
   -------------

   overriding function Execute
     (Command : access Set_Breakpoint_Command_Context;
      Context : Interactive_Command_Context) return Command_Return_Type
   is
      Kernel  : constant Kernel_Handle := Get_Kernel (Context.Context);
      Process : constant Visual_Debugger :=
        Visual_Debugger (Get_Current_Debugger (Kernel));
      Num      : Breakpoint_Identifier with Unreferenced;

   begin
      if Command.Continue_Till then
         --  Only works if there is a current debugger
         if Process /= null then
            Num := Process.Debugger.Break_Source
              (File_Information (Context.Context),
               Editable_Line_Type
                 (GPS.Kernel.Contexts.Line_Information (Context.Context)),
               Temporary => True);
            Process.Debugger.Continue (Mode => GVD.Types.Visible);
         end if;

      elsif Command.On_Line then
         Break_Source
           (Kernel,
            File  => File_Information (Context.Context),
            Line  => Editable_Line_Type
              (GPS.Kernel.Contexts.Line_Information (Context.Context)));
      else
         Break_Subprogram
           (Kernel,
            Subprogram => Entity_Name_Information (Context.Context));
      end if;
      return Commands.Success;
   end Execute;

   -------------
   -- Execute --
   -------------

   overriding function Execute
     (Self : access Set_Breakpoint_Command_At_Line) return Command_Return_Type
   is
   begin
      case Self.Mode is
         when Set =>
            Break_Source
              (Self.Kernel, File => Self.File, Line => Self.Line);

         when Unset =>
            Unbreak_Source
              (Self.Kernel, File => Self.File, Line => Self.Line);
      end case;
      return Success;
   end Execute;

   ----------
   -- Save --
   ----------

   overriding procedure Save
     (Property : access Breakpoint_Property_Record;
      Value    : in out GNATCOLL.JSON.JSON_Value)
   is
      use GNATCOLL.JSON;

      Values : JSON_Array;

   begin
      GNATCOLL.Traces.Trace (Me, "Saving breakpoints for future sessions");

      for B of Property.Breakpoints loop
         declare
            Value : constant JSON_Value := Create_Object;
         begin
            Value.Set_Field ("type", Breakpoint_Type'Image (B.The_Type));
            Value.Set_Field
              ("disposition",
               Breakpoint_Disposition'Image (B.Disposition));
            Value.Set_Field ("enabled", B.Enabled);
            Value.Set_Field ("expression", To_String (B.Expression));
            if B.Location.Is_Null then
               Value.Set_Field ("file", "");
               Value.Set_Field ("line", "");
            else
               Value.Set_Field
                 ("file", JSON_Utils.Save (Get_File (B.Location)));
               Value.Set_Field
                 ("line", Editable_Line_Type'Image (Get_Line (B.Location)));
            end if;
            Value.Set_Field ("exception", To_String (B.Except));
            Value.Set_Field ("subprogram", To_String (B.Subprogram));
            if B.Address /= Invalid_Address then
               Value.Set_Field ("address", Address_To_String (B.Address));
            else
               Value.Set_Field ("address", "");
            end if;
            Value.Set_Field ("ignore", B.Ignore);
            Value.Set_Field ("condition", To_String (B.Condition));
            Value.Set_Field ("command", To_String (B.Commands));
            Value.Set_Field ("scope", Scope_Type'Image (B.Scope));
            Value.Set_Field ("action", Action_Type'Image (B.Action));
            Append (Values, Value);
         end;
      end loop;
      Value.Set_Field ("breakpoints", Values);
   end Save;

   ----------
   -- Load --
   ----------

   overriding procedure Load
     (Property : in out Breakpoint_Property_Record;
      Value    : GNATCOLL.JSON.JSON_Value)
   is
      use GNATCOLL.JSON;

      Values : JSON_Array;
      B      : Breakpoint_Data;

   begin
      GNATCOLL.Traces.Trace
        (Me, "Restoring breakpoints from previous session");

      Values := Value.Get ("breakpoints");

      for Index in 1 .. Length (Values) loop
         declare
            Item : constant JSON_Value := Get (Values, Index);
            Loc  : Location_Marker     := No_Marker;
         begin
            if String'(Item.Get ("line")) /= ""
              and then JSON_Value'(Item.Get ("file")) /= JSON_Null
            then
               Loc := Property.Kernel.Get_Buffer_Factory.Create_Marker
                 (File   => JSON_Utils.Load (Item.Get ("file")),
                  Line   => Editable_Line_Type'Value (Item.Get ("line")),
                  Column => 1);
            end if;

            B :=
              (Num         => Breakpoint_Identifier'Last,
               Trigger     => Write,
               The_Type    => Breakpoint_Type'Value (Item.Get ("type")),
               Disposition => Breakpoint_Disposition'Value
                 (Item.Get ("disposition")),
               Enabled     => Item.Get ("enabled"),
               Expression  => Item.Get ("expression"),
               Except      => Item.Get ("exception"),
               Subprogram  => Item.Get ("subprogram"),
               Location    => Loc,
               Address     => String_To_Address (Item.Get ("address")),
               Ignore      => Item.Get ("ignore"),
               Condition   => Item.Get ("condition"),
               Commands    => Item.Get ("command"),
               Scope       => Scope_Type'Value (Item.Get ("scope")),
               Action      => Action_Type'Value (Item.Get ("action")));
            Property.Breakpoints.Append (B);
         end;
      end loop;
   end Load;

   -------------
   -- Execute --
   -------------

   overriding procedure Execute
     (Self   : On_Project_Changed;
      Kernel : not null access Kernel_Handle_Record'Class)
   is
      pragma Unreferenced (Self);
      Prop  : Breakpoint_Property_Record;
      Found : Boolean;
   begin
      Module.Breakpoints.List.Clear;

      if not Preserve_State_On_Exit.Get_Pref then
         Trace (Me, "Not loading persistent breakpoints");
         return;
      end if;

      Trace (Me, "Loading persistent breakpoints");
      Prop.Kernel := Kernel;
      Get_Property
        (Prop, Get_Project (Kernel), Name => "breakpoints", Found => Found);
      if Found then
         Module.Breakpoints.List := Prop.Breakpoints;
         Debugger_Breakpoints_Changed_Hook.Run (Kernel, null);
         Show_Breakpoints_In_All_Editors (Kernel);
      end if;
   end Execute;

   -------------
   -- Execute --
   -------------

   overriding procedure Execute
     (Self   : On_Project_Changing;
      Kernel : not null access Kernel_Handle_Record'Class;
      File   : Virtual_File)
   is
      pragma Unreferenced (Self, File);
   begin
      Save_Persistent_Breakpoints (Kernel);
   end Execute;

   -------------
   -- Execute --
   -------------

   overriding function Execute
     (Self   : On_Before_Exit;
      Kernel : not null access Kernel_Handle_Record'Class) return Boolean
   is
      pragma Unreferenced (Self);
   begin
      Save_Persistent_Breakpoints (Kernel);
      return True;  --  allow exit
   end Execute;

   -------------
   -- Execute --
   -------------

   overriding procedure Execute
     (Self     : On_Debugger_Terminated;
      Kernel   : not null access Kernel_Handle_Record'Class;
      Debugger : access Base_Visual_Debugger'Class)
   is
      pragma Unreferenced (Self);
   begin
      --  We always save the debugger-specific breakpoints to the global list,
      --  so that later debuggers are started with the same list. If we don't
      --  do that, and the Preserve_State_On_Exit pref is disabled, we would
      --  end up with complex cases where breakpoints set before the debugger
      --  is started are set when the debugger starts, but not those set while
      --  the debugger is running

      if Visual_Debugger (Debugger).Debugger.Get_Executable = No_File then
         --  If there was no executable, we did not even try to set
         --  breakpoints, so don't save them either
         return;
      end if;

      --  In case the user has set breakpoints manually via the console,
      --  synchronize the global list of breakpoints

      Module.Breakpoints.List.Clear;

      if Break_On_Exception.Get_Pref then
         for B of Visual_Debugger (Debugger).Breakpoints.List loop
            if B.Except = "" or else B.Except /= "all" then
               Module.Breakpoints.List.Append (B);
            end if;
         end loop;
      else
         Module.Breakpoints := Visual_Debugger (Debugger).Breakpoints;
      end if;

      Save_Persistent_Breakpoints (Kernel);
   end Execute;

   ---------------------------------
   -- Save_Persistent_Breakpoints --
   ---------------------------------

   procedure Save_Persistent_Breakpoints
     (Kernel   : not null access Kernel_Handle_Record'Class)
   is
      Prop : Breakpoint_Property;
   begin
      if not Preserve_State_On_Exit.Get_Pref then
         Trace (Me, "Not saving persistent breakpoints");
         return;
      end if;

      if Module.Breakpoints.List.Is_Empty then
         Trace (Me, "No persistent breakpoint to save");
         Remove_Property (Kernel, Get_Project (Kernel), "breakpoints");
         return;
      end if;

      Trace (Me, "Saving persistent breakpoints");
      Prop := new Breakpoint_Property_Record;

      --  Filter breakpoints that are created automatically by GPS as a
      --  result of preferences.

      Prop.Kernel      := Kernel;
      Prop.Breakpoints := Module.Breakpoints.List;
      Set_Property
        (Kernel, Get_Project (Kernel), "breakpoints", Prop,
         Persistent => True);
   end Save_Persistent_Breakpoints;

   -------------
   -- Execute --
   -------------

   overriding procedure Execute
     (Self     : On_Debugger_Started;
      Kernel   : not null access Kernel_Handle_Record'Class;
      Debugger : access Base_Visual_Debugger'Class)
   is
      pragma Unreferenced (Self);
      Process : constant Visual_Debugger := Visual_Debugger (Debugger);
      Id      : Breakpoint_Identifier;
   begin
      if Process.Debugger.Get_Executable = No_File then
         --  Do not try to restore breakpoints, since the debugger has no
         --  source anyway. We do not want to lose the list of persistent
         --  breakpoints.
         return;
      end if;

      Trace (Me, "Restore persistent breakpoints");
      for B of Module.Breakpoints.List loop
         if B.Except /= "" then
            Id := Process.Debugger.Break_Exception
              (To_String (B.Except),
               Temporary => B.Disposition /= Keep, Mode => Internal,
               Unhandled => False);
         elsif B.Location /= No_Marker then
            Id := Process.Debugger.Break_Source
              (Get_File (B.Location),
               Get_Line (B.Location),
               Temporary => B.Disposition /= Keep, Mode => Internal);
         elsif B.Subprogram /= "" then
            Id := Process.Debugger.Break_Subprogram
              (To_String (B.Subprogram),
               Temporary => B.Disposition /= Keep, Mode => Internal);
         elsif B.Address /= Invalid_Address then
            Id := Process.Debugger.Break_Address
              (B.Address,
               Temporary => B.Disposition /= Keep, Mode => Internal);
         else
            Id := GVD.Types.No_Breakpoint;
         end if;

         if Id /= GVD.Types.No_Breakpoint then
            if not B.Enabled then
               Process.Debugger.Enable_Breakpoint (Id, B.Enabled, Internal);
            end if;

            if B.Condition /= "" then
               Process.Debugger.Set_Breakpoint_Condition
                 (Id, To_String (B.Condition), Internal);
            end if;

            if B.Commands /= "" then
               Process.Debugger.Set_Breakpoint_Command
                 (Id, To_String (B.Commands), Internal);
            end if;

            if B.Ignore /= 0 then
               Process.Debugger.Set_Breakpoint_Ignore_Count
                 (Id, B.Ignore, Internal);
            end if;

            if B.Scope /= No_Scope or else B.Action /= No_Action then
               Process.Debugger.Set_Scope_Action
                 (B.Scope, B.Action, Id, Internal);
            end if;
         end if;
      end loop;

      --  Reparse the list to make sure of what the debugger is actually using
      Refresh_Breakpoints_List (Kernel, Process);
   end Execute;

   -----------------------
   -- Toggle_Breakpoint --
   -----------------------

   function Toggle_Breakpoint
     (Kernel         : not null access Kernel_Handle_Record'Class;
      Breakpoint_Num : Breakpoint_Identifier) return Boolean
   is
      Process : constant Visual_Debugger :=
        Visual_Debugger (Get_Current_Debugger (Kernel));
   begin
      for B of Get_Stored_List_Of_Breakpoints (Process).List loop
         if B.Num = Breakpoint_Num then
            B.Enabled := not B.Enabled;
            if Process /= null then
               Process.Debugger.Enable_Breakpoint
                 (B.Num, B.Enabled, Mode => GVD.Types.Visible);
            end if;
            return B.Enabled;
         end if;
      end loop;

      Show_Breakpoints_In_All_Editors (Kernel);
      return False;
   end Toggle_Breakpoint;

   ----------------------------
   -- Get_Breakpoint_From_Id --
   ----------------------------

   function Get_Breakpoint_From_Id
     (Kernel  : not null access Kernel_Handle_Record'Class;
      Id      : Breakpoint_Identifier)
      return Breakpoint_Data
   is
      Process : constant Visual_Debugger :=
        Visual_Debugger (Get_Current_Debugger (Kernel));
   begin
      for B of Get_Stored_List_Of_Breakpoints (Process).List loop
         if B.Num = Id then
            return B;
         end if;
      end loop;
      return Null_Breakpoint;
   end Get_Breakpoint_From_Id;

   ------------------------------
   -- Refresh_Breakpoints_List --
   ------------------------------

   procedure Refresh_Breakpoints_List
     (Kernel   : not null access Kernel_Handle_Record'Class;
      Debugger : access Base_Visual_Debugger'Class)
   is
      Process  : constant Visual_Debugger := Visual_Debugger (Debugger);
   begin
      if Process /= null
        and then Process.Debugger /= null
        and then not Process.Command_In_Process
      then
         Process.Debugger.List_Breakpoints (Kernel, Process.Breakpoints.List);
         Process.Breakpoints.Has_Temporary_Breakpoint := False;

         --  Check whether we have temporary breakpoints

         for B of Process.Breakpoints.List loop
            if B.Disposition /= Keep and then B.Enabled then
               Process.Breakpoints.Has_Temporary_Breakpoint := True;
               exit;
            end if;
         end loop;
      end if;

      Show_Breakpoints_In_All_Editors (Kernel);
      Debugger_Breakpoints_Changed_Hook.Run (Kernel, Process);
   end Refresh_Breakpoints_List;

   -------------
   -- Execute --
   -------------

   overriding procedure Execute
     (Self     : On_Debugger_Location_Changed;
      Kernel   : not null access Kernel_Handle_Record'Class;
      Debugger : access Base_Visual_Debugger'Class)
   is
      pragma Unreferenced (Self, Debugger);
   begin
      Show_Breakpoints_In_All_Editors (Kernel);
   end Execute;

   ---------------------
   -- Add_Information --
   ---------------------

   procedure Add_Information
     (Kernel  : not null access Kernel_Handle_Record'Class;
      B       : Breakpoint_Data)
   is
      Msg  : Simple_Message_Access;
      File : Virtual_File;
      Line : Editable_Line_Type;
   begin
      if B.Location = No_Marker then
         return;
      end if;

      File := Get_File (B.Location);
      Line := Get_Line (B.Location);

      Msg := Create_Simple_Message
        (Get_Messages_Container (Kernel),
         Category                 => Messages_Category_For_Breakpoints,
         File                     => File,
         Line                     => Natural (Line),
         Column                   => 0,
         Text                     =>
           (if not B.Enabled
            then "A disabled breakpoint has been set on this line"
            elsif B.Condition /= ""
            then "A conditional breakpoint has been set on this line"
            else "An active breakpoint has been set on this line"),
         Weight                   => 0,
         Flags                    => Breakpoints_Message_Flags,
         Allow_Auto_Jump_To_First => False);

      Msg.Set_Action
        (new Line_Information_Record'
           (Text               => Null_Unbounded_String,
            Tooltip_Text       => Msg.Get_Text,
            Image              => Null_Unbounded_String,
            Message            => Create (Message_Access (Msg)),
            Associated_Command => Create_Set_Breakpoint_Command
              (Kernel,
               Mode => Unset,
               File => File,
               Line => Line)));

      if not B.Enabled then
         Msg.Set_Highlighting
           (Debugger_Disabled_Breakpoint_Style, Length => 1);
      elsif B.Condition /= "" then
         Msg.Set_Highlighting
           (Debugger_Conditional_Breakpoint_Style, Length => 1);
      else
         Msg.Set_Highlighting (Debugger_Breakpoint_Style, Length => 1);
      end if;
   end Add_Information;

   -------------------------------------
   -- Show_Breakpoints_In_All_Editors --
   -------------------------------------

   procedure Show_Breakpoints_In_All_Editors
     (Kernel : not null access Kernel_Handle_Record'Class)
   is
      Process : constant Visual_Debugger :=
        Visual_Debugger (Get_Current_Debugger (Kernel));
   begin
      Get_Messages_Container (Kernel).Remove_Category
        (Messages_Category_For_Breakpoints,
         Breakpoints_Message_Flags);

      for B of Get_Stored_List_Of_Breakpoints (Process).List loop
         Add_Information (Kernel, B);
      end loop;
   end Show_Breakpoints_In_All_Editors;

   ------------------------------------
   -- Get_Stored_List_Of_Breakpoints --
   ------------------------------------

   function Get_Stored_List_Of_Breakpoints
     (Debugger : access Base_Visual_Debugger'Class := null)
      return access Breakpoint_List is
   begin
      if Debugger = null then
         return Module.Breakpoints'Access;
      else
         return Visual_Debugger (Debugger).Breakpoints'Access;
      end if;
   end Get_Stored_List_Of_Breakpoints;

   ---------------------
   -- Register_Module --
   ---------------------

   procedure Register_Module
     (Kernel : not null access Kernel_Handle_Record'Class)
   is
      No_Debugger_Or_Stopped : Action_Filter;
   begin
      Module := new Breakpoints_Module;
      Register_Module (Module, Kernel, "Persistent_Breakpoints");

      Project_Changed_Hook.Add (new On_Project_Changed);
      Project_Changing_Hook.Add (new On_Project_Changing);
      Before_Exit_Action_Hook.Add (new On_Before_Exit);
      Debugger_Terminated_Hook.Add (new On_Debugger_Terminated);
      Debugger_Started_Hook.Add (new On_Debugger_Started);
      Debugger_Location_Changed_Hook.Add (new On_Debugger_Location_Changed);

      No_Debugger_Or_Stopped := new No_Debugger_Or_Stopped_Filter;

      Register_Action
        (Kernel, "debug set subprogram breakpoint",
         Command     => new Set_Breakpoint_Command_Context,
         Description => "Set a breakpoint on subprogram",
         Filter      => No_Debugger_Or_Stopped and
            new Subprogram_Variable_Filter,
         Category    => -"Debug");
      Register_Contextual_Menu
        (Kernel => Kernel,
         Label  => -"Debug/Set breakpoint on %e",
         Action => "debug set subprogram breakpoint");

      Register_Action
        (Kernel, "debug set line breakpoint",
         Command     => new Set_Breakpoint_Command_Context'
           (Interactive_Command with On_Line => True, Continue_Till => False),
         Description => "Set a breakpoint on line",
         Filter      => No_Debugger_Or_Stopped and
           Kernel.Lookup_Filter ("Source editor"),
         Category    => -"Debug");
      Register_Contextual_Menu
        (Kernel => Kernel,
         Label  => -"Debug/Set breakpoint on line %l",
         Action => "debug set line breakpoint");

      Kernel.Set_Default_Line_Number_Click ("debug set line breakpoint");

      Register_Action
        (Kernel, "debug continue until",
         Command     => new Set_Breakpoint_Command_Context'
           (Interactive_Command with On_Line => True, Continue_Till => True),
         Description => "Continue executing until the given line",
         Filter      => Kernel.Lookup_Filter ("Debugger stopped") and
           Kernel.Lookup_Filter ("Source editor"),
         Category    => -"Debug");
      Register_Contextual_Menu
        (Kernel => Kernel,
         Label  => -"Debug/Continue until line %l",
         Action => "debug continue until");
   end Register_Module;

end GVD.Breakpoints_List;
