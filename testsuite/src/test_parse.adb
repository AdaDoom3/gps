------------------------------------------------------------------------------
--                                  G P S                                   --
--                                                                          --
--                     Copyright (C) 2000-2016, AdaCore                     --
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

with Ada.Calendar;        use Ada.Calendar;
with Ada.Text_IO;         use Ada.Text_IO;

with GNAT.Expect;         use GNAT.Expect;
with GNAT.OS_Lib;         use GNAT.OS_Lib;

with Gtk.Main;            use Gtk.Main;

with Debugger.Gdb.Ada;    use Debugger.Gdb.Ada;
with Debugger.Gdb;        use Debugger.Gdb;
with Debugger;            use Debugger;
with Default_Preferences; use Default_Preferences;
with GVD_Module;          use GVD_Module;
with GVD.Preferences;     use GVD.Preferences;
with GVD.Types;           use GVD.Types;
with Items;               use Items;
with Language.Debugger;   use Language.Debugger;
with Process_Proxies;     use Process_Proxies;
with GNATCOLL.VFS;        use GNATCOLL.VFS;
with Parse_Support;       use Parse_Support;

procedure Test_Parse is

   Gdb_Record : aliased Gdb_Debugger;
   Gdb        : Debugger_Access := Gdb_Record'Unchecked_Access;
   Lang       : access Gdb_Ada_Language := new Gdb_Ada_Language;

   -----------------------
   -- Print_Special_Var --
   -----------------------

   procedure Print_Special_Var (Var : String);
   procedure Print_Special_Var (Var : String) is
      V          : Generic_Type_Access;
      File       : File_Type;
      Type_Str   : String (1 .. 10000);
      Index      : Natural;
      Repeat_Num : Positive;
      Last       : Natural;

   begin
      Put_Line ("------------------------------");
      V := Parse_Type (Gdb, Var);
      if V /= null then
         Open (File, In_File, "tcb.out");
         Get_Line (File, Type_Str, Last);
         Close (File);
         Index := 1;
         Parse_Value (Lang, Type_Str (1 .. Last),
                      Index, V, Repeat_Num);
         Print (V, Lang, Var);
      else
         Put_Line (Var & ": Unknown variable");
      end if;
   end Print_Special_Var;

   ---------------
   -- Print_Var --
   ---------------

   procedure Print_Var (Var : String);
   procedure Print_Var (Var : String) is
      V : Generic_Type_Access;
      Found : Boolean;
   begin
      Put_Line ("------------------------------");
      V := Parse_Type (Gdb, Var);
      if V /= null then
         Parse_Value (Gdb, Var, V, Value_Found => Found);
         Print (V, Lang, Var);
      else
         Put_Line (Var & ": Unknown variable");
      end if;
   end Print_Var;

   ---------------------
   -- Print_Var_Parse --
   ---------------------

   procedure Print_Var_Parse (Var : String);
   procedure Print_Var_Parse (Var : String) is
   begin
      --  Print_Var ("Parse::" & Var);
      Print_Var (Var);
   end Print_Var_Parse;

   -------------------
   -- Print_Var_Bar --
   -------------------

   procedure Print_Var_Bar (Var : String);
   procedure Print_Var_Bar (Var : String) is
   begin
      --  Print_Var ("Bar::" & Var);
      Print_Var (Var);
   end Print_Var_Bar;

   GVD_Prefs : Preferences_Manager;
   List : Argument_List (1 .. 0);
   Num  : Breakpoint_Identifier;
begin
   Init;
   Create_GVD_Module (Kernel => null);
   GVD_Prefs := new Preferences_Manager_Record;
   Register_Default_Preferences (GVD_Prefs);
   Load_Preferences (GVD_Prefs, Create_From_Base ("preferences"));

   Set_Language (Gdb, Lang.all'Unchecked_Access);
   Set_Debugger (Lang, Gdb);

   Spawn (Gdb, null, No_File, List, "", new Process_Proxy);

   Initialize (Gdb);
   Set_Executable (Gdb, Create (Full_Filename => "../parse"));
   Send (Gdb, "begin");
   Num := Break_Exception (Gdb, Unhandled => False);

   Run (Gdb);

   Stack_Up (Gdb);

   Print_Var_Parse ("Non_Existant_Variable");
   --  Check there is no error in that case.

   Print_Var_Parse ("A");
   Print_Var_Parse ("B");
   Print_Var_Parse ("C");
   Print_Var_Parse ("Sh");
   Print_Var_Parse ("Ssh");
   Print_Var_Parse ("S");
   Print_Var_Parse ("S2");
   Print_Var_Parse ("S3");
   Print_Var_Parse ("S4");
   Print_Var_Parse ("Dur");
   Print_Var_Parse ("R");
   Print_Var_Parse ("M");
   Print_Var_Parse ("Act");
   Print_Var_Parse ("My_Enum_Variable");
   Print_Var_Parse ("T");
   Print_Var_Parse ("Ea");
   Print_Var_Parse ("Ea2");
   Print_Var_Parse ("Aoa");
   Print_Var_Parse ("Fiia");
   Print_Var_Parse ("Iaa");
   Print_Var_Parse ("U");
   Print_Var_Parse ("Enum_Array_Variable");
   Print_Var_Parse ("Erm");
   Print_Var_Parse ("Negative_Array_Variable");
   Print_Var_Parse ("Aa");
   Print_Var_Parse ("A3d");
   Print_Var_Parse ("Aos");
   Print_Var_Parse ("Nr");
   Print_Var_Parse ("V");
   Print_Var_Parse ("Mra");
   Print_Var_Parse ("W");
   Print_Var_Parse ("Rr");
   Print_Var_Parse ("Roa");
   Print_Var_Parse ("X");
   Print_Var_Parse ("Ar");
   Print_Var_Parse ("Z");
   Print_Var_Parse ("As");
   Print_Var_Parse ("Y");
   Print_Var_Parse ("Y2");
   Print_Var_Parse ("Tt");
   Print_Var_Parse ("Ctt");
   Print_Var_Parse ("Ctt2");
   Print_Var_Parse ("T_Ptr.all");
   Print_Var_Parse ("T_Ptr2.all");
   Print_Var_Parse ("Ba");
   Print_Var_Parse ("Ba2");
   Print_Var_Parse ("RegExp");

   Print_Var_Parse ("Null_Ptr.all");
   Print_Var_Parse ("Ra");
   Print_Var_Parse ("Nvp");
   Print_Var_Parse ("My_Str");
   Print_Var_Parse ("Final_Result");
   Print_Var_Parse ("Final_Result2");
   Print_Var_Parse ("This");
   Print_Var_Parse ("Scr");
   Print_Var_Parse ("More_Fruits");  --  Test for F223-004

   Stack_Down (Gdb);  --  Test for 9305-014
   Print_Var_Parse ("Args");
   Print_Var_Parse ("Args2");
   Send (Gdb, "cont");

   Print_Var_Parse ("Ut");

   --  Print_Var ("Parse::Tcb");
   --  Print_Special_Var ("Parse::Tcb");

   Print_Var_Bar ("A");
   Print_Var_Bar ("T");
   Print_Var_Bar ("R");
   Print_Var_Parse ("X1");

   Print_Var ("Ustring");
   Print_Var ("Asu_Test");
   Print_Var ("Asu_Test2");
   Print_Var ("My_Exception");

   Print_Var ("NBI_N");
   Print_Var ("NBI_B");
   Print_Var ("NBI_I");
   --  Tests for G328-021

   Print_Var ("AP");
   Print_Var ("AP.all");
   Print_Var ("AF");
   Print_Var ("AF.all");
   Print_Var ("RAF");
   --  Test for G413-004

   Send (Gdb, "b swap");
   Send (Gdb, "cont");
   Print_Var ("Word.all");
   --  Test for JC21-017

   Close (Gdb);

exception
   when others =>
      Close (Gdb);
      raise;

end Test_Parse;
