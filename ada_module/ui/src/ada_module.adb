------------------------------------------------------------------------------
--                                  G P S                                   --
--                                                                          --
--                     Copyright (C) 2002-2016, AdaCore                     --
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

with Default_Preferences;      use Default_Preferences;
with Default_Preferences.Enums;
with GPS.Kernel;               use GPS.Kernel;
with GPS.Kernel.Hooks;         use GPS.Kernel.Hooks;
with GPS.Kernel.Project;       use GPS.Kernel.Project;
with GPS.Intl;                 use GPS.Intl;
with GNATCOLL.Projects;        use GNATCOLL.Projects;
with GPS.Kernel.Preferences;   use GPS.Kernel.Preferences;
with Language.Ada;             use Language.Ada;
with Ada_Semantic_Tree.Lang;   use Ada_Semantic_Tree.Lang;
with Language_Handlers;        use Language_Handlers;
with Language;                 use Language;
with Project_Viewers;          use Project_Viewers;
with Ada_Naming_Editors;       use Ada_Naming_Editors;
with Projects;                 use Projects;
with Case_Handling;            use Case_Handling;

package body Ada_Module is

   package Casing_Policy_Preferences is new
     Default_Preferences.Enums.Generics (Casing_Policy);

   package Casing_Preferences is new
     Default_Preferences.Enums.Generics (Casing_Type);

   package Indent_Preferences is new
     Default_Preferences.Enums.Generics (Indent_Style);

   Ada_Automatic_Indentation : Indentation_Kind_Preferences.Preference;
   Ada_Use_Tabs              : Boolean_Preference;
   Ada_Indentation_Level     : Integer_Preference;
   Ada_Continuation_Level    : Integer_Preference;
   Ada_Declaration_Level     : Integer_Preference;
   Ada_Conditional_Level     : Integer_Preference;
   Ada_Record_Level          : Integer_Preference;
   Ada_Indent_Case_Extra     : Indent_Preferences.Preference;
   Ada_Casing_Policy         : Casing_Policy_Preferences.Preference;
   Ada_Reserved_Casing       : Casing_Preferences.Preference;
   Ada_Ident_Casing          : Casing_Preferences.Preference;
   Ada_Format_Operators      : Boolean_Preference;
   Ada_Align_On_Colons       : Boolean_Preference;
   Ada_Align_On_Arrows       : Boolean_Preference;
   Ada_Align_Decl_On_Colon   : Boolean_Preference;
   Ada_Indent_Comments       : Boolean_Preference;
   Ada_Stick_Comments        : Boolean_Preference;

   type On_Pref_Changed is new Preferences_Hooks_Function with null record;
   overriding procedure Execute
     (Self   : On_Pref_Changed;
      Kernel : not null access Kernel_Handle_Record'Class;
      Pref   : Default_Preferences.Preference);
   --  Called when the preferences have changed

   function Naming_Scheme_Editor
     (Kernel : not null access Kernel_Handle_Record'Class; Lang : String)
      return not null access Project_Editor_Page_Record'Class is
      (new Ada_Naming_Editor_Record);
   --  Create the naming scheme editor page

   -------------
   -- Execute --
   -------------

   overriding procedure Execute
     (Self   : On_Pref_Changed;
      Kernel : not null access Kernel_Handle_Record'Class;
      Pref   : Default_Preferences.Preference)
   is
      pragma Unreferenced (Self, Kernel, Pref);
   begin
      Set_Indentation_Parameters
        (Ada_Lang,
         Indent_Style => Indentation_Kind'(Ada_Automatic_Indentation.Get_Pref),
         Params       =>
           (Indent_Level        => Ada_Indentation_Level.Get_Pref,
            Indent_Continue     => Ada_Continuation_Level.Get_Pref,
            Indent_Decl         => Ada_Declaration_Level.Get_Pref,
            Indent_Conditional  => Ada_Conditional_Level.Get_Pref,
            Indent_Record       => Ada_Record_Level.Get_Pref,
            Indent_Case_Extra   => Ada_Indent_Case_Extra.Get_Pref,
            Casing_Policy       => Ada_Casing_Policy.Get_Pref,
            Reserved_Casing     => Ada_Reserved_Casing.Get_Pref,
            Ident_Casing        => Ada_Ident_Casing.Get_Pref,
            Format_Operators    => Ada_Format_Operators.Get_Pref,
            Use_Tabs            => Ada_Use_Tabs.Get_Pref,
            Align_On_Colons     => Ada_Align_On_Colons.Get_Pref,
            Align_On_Arrows     => Ada_Align_On_Arrows.Get_Pref,
            Align_Decl_On_Colon => Ada_Align_Decl_On_Colon.Get_Pref,
            Indent_Comments     => Ada_Indent_Comments.Get_Pref,
            Stick_Comments      => Ada_Stick_Comments.Get_Pref));
   end Execute;

   ---------------------
   -- Register_Module --
   ---------------------

   procedure Register_Module
     (Kernel : access GPS.Kernel.Kernel_Handle_Record'Class)
   is
      Handler : constant Language_Handler := Get_Language_Handler (Kernel);
   begin
      Register_Language (Handler, Ada_Lang, Ada_Tree_Lang);

      Register_Default_Language_Extension
        (Get_Registry (Kernel).Environment.all,
         Language_Name       => "Ada",
         Default_Spec_Suffix => ".ads",
         Default_Body_Suffix => ".adb",
         Obj_Suffix          => ".o");

      Ada_Automatic_Indentation := Indentation_Kind_Preferences.Create
        (Get_Preferences (Kernel),
         Path    => -"Editor/Ada:Indentation",
         Name    => "Ada-Auto-Indentation",
         Default => Extended,
         Doc     => -"Enable auto-indentation for Ada sources.",
         Label   => -"Auto indentation");

      Ada_Indentation_Level := Create
        (Get_Preferences (Kernel),
         Path    => -"Editor/Ada:Indentation",
         Name    => "Ada-Indent-Level",
         Minimum => 1,
         Maximum => 9,
         Default => 3,
         Doc     => -"Number of spaces for the default Ada indentation.",
         Label   => -"Default indentation");

      Ada_Continuation_Level := Create
        (Get_Preferences (Kernel),
         Path    => -"Editor/Ada:Indentation",
         Name    => "Ada-Continuation-Level",
         Minimum => 0,
         Maximum => 9,
         Default => 2,
         Doc     => -"Number of extra spaces for continuation lines.",
         Label   => -"Continuation lines");

      Ada_Declaration_Level := Create
        (Get_Preferences (Kernel),
         Path  => -"Editor/Ada:Indentation",
         Name    => "Ada-Declaration-Level:Indentation",
         Minimum => 0,
         Maximum => 9,
         Default => 0,
         Doc   => -"Number of extra spaces for multi line declarations.",
         Label => -"Declaration lines");

      Ada_Conditional_Level := Create
        (Get_Preferences (Kernel),
         Path    => -"Editor/Ada:Indentation",
         Name    => "Ada-Conditional-Level",
         Minimum => 0,
         Maximum => 9,
         Default => 1,
         Doc   => -"Number of extra spaces for multiple line conditionals.",
         Label   => -"Conditional continuation lines");

      Ada_Record_Level := Create
        (Get_Preferences (Kernel),
         Path    => -"Editor/Ada:Indentation",
         Name    => "Ada-Record-Level",
         Minimum => 0,
         Maximum => 9,
         Default => 3,
         Doc     => -"Number of extra spaces for multiple line record types.",
         Label   => -"Record indentation");

      Ada_Indent_Case_Extra := Indent_Preferences.Create
        (Get_Preferences (Kernel),
         Path    => -"Editor/Ada:Indentation",
         Name    => "Ada-Indent-Case-Style",
         Default => Automatic,
         Doc     => -"Indent case statement with an extra level.",
         Label   => -"Case indentation");

      Ada_Casing_Policy := Casing_Policy_Preferences.Create
        (Get_Preferences (Kernel),
         Path    => -"Editor/Ada:Casing",
         Name    => "Ada-Casing-Policy",
         Label   => -"Keywords and Identifiers casing",
         Doc     => "",
         Default => Disabled);

      Ada_Reserved_Casing := Casing_Preferences.Create
        (Get_Preferences (Kernel),
         Path    => -"Editor/Ada:Casing",
         Name    => "Ada-Reserved-Casing",
         Default => Lower,
         Doc     => "",
         Label   => -"Reserved word casing");

      Ada_Ident_Casing := Casing_Preferences.Create
        (Get_Preferences (Kernel),
         Path    => -"Editor/Ada:Casing",
         Name    => "Ada-Ident-Casing",
         Default => Smart_Mixed,
         Doc     => "",
         Label   => -"Identifier casing");

      Ada_Use_Tabs := Create
        (Get_Preferences (Kernel),
         Path     => -"Editor/Ada:Indentation",
         Name    => "Ada-Use-Tabs",
         Default => False,
         Doc     =>
         -"Use tabulations when indenting.",
         Label    => -"Use tabulations");

      Ada_Format_Operators := Create
        (Get_Preferences (Kernel),
         Path    => -"Editor/Ada:Indentation",
         Name    => "Ada-Format-Operators",
         Default => False,
         Doc     => -"Add spaces around operators and delimiters.",
         Label   => -"Format operators/delimiters");

      Ada_Align_On_Colons := Create
        (Get_Preferences (Kernel),
         Path    => -"Editor/Ada:Indentation",
         Name    => "Ada-Align-On-Colons",
         Default => False,
         Doc     => -"Align colons in declaration statements.",
         Label   => -"Align colons in declarations");

      Ada_Align_On_Arrows := Create
        (Get_Preferences (Kernel),
         Path    => -"Editor/Ada:Indentation",
         Name    => "Ada-Align-On-Arrows",
         Default => False,
         Doc     => -"Align associations on arrow delimiters.",
         Label   => -"Align associations on arrows");

      Ada_Align_Decl_On_Colon := Create
        (Get_Preferences (Kernel),
         Path    => -"Editor/Ada:Indentation",
         Name    => "Ada-Align-Decl-On_Colon",
         Default => False,
         Doc     =>
         -("Align continuation lines after a declaration " &
           "based on the colon character."),
         Label   => -"Align declarations after colon");

      Ada_Indent_Comments := Create
        (Get_Preferences (Kernel),
         Path    => -"Editor/Ada:Indentation",
         Name    => "Ada-Indent-Comments",
         Default => True,
         Doc     => -"Indent lines with only comments.",
         Label   => -"Indent comments");

      Ada_Stick_Comments := Create
        (Get_Preferences (Kernel),
         Path    => -"Editor/Ada:Indentation",
         Name    => "Ada-Stick-Comments",
         Default => False,
         Doc     =>
         -("Align comment lines following 'record' and " &
           "'is' keywords immediately with no extra space"),
         Label   => -"Align comments on keywords");

      Preferences_Changed_Hook.Add (new On_Pref_Changed);

      Register_Naming_Scheme_Editor
        (Kernel, "Ada", Naming_Scheme_Editor'Access);
   end Register_Module;

end Ada_Module;
