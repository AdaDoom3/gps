-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                     Copyright (C) 2003-2004                       --
--                            ACT-Europe                             --
--                                                                   --
-- GPS is free  software; you can  redistribute it and/or modify  it --
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

with Glide_Kernel;             use Glide_Kernel;
with Glide_Kernel.Contexts;    use Glide_Kernel.Contexts;
with Glide_Kernel.Preferences; use Glide_Kernel.Preferences;
with Glide_Kernel.Project;     use Glide_Kernel.Project;
with Glide_Kernel.Modules;     use Glide_Kernel.Modules;
with Glide_Kernel.Hooks;       use Glide_Kernel.Hooks;
with Glide_Kernel.Standard_Hooks; use Glide_Kernel.Standard_Hooks;
with Glide_Intl;               use Glide_Intl;
with Glib.Object;              use Glib.Object;
with VFS;                      use VFS;
with Docgen.Work_On_File;      use Docgen.Work_On_File;
with Docgen;                   use Docgen;
with Entities;                 use Entities;
with Traces;                   use Traces;
with Ada.Exceptions;           use Ada.Exceptions;
with Gtkada.File_Selector;     use Gtkada.File_Selector;
with Projects;                 use Projects;
with Glib;                     use Glib;
with Glib.Generic_Properties;
with Glib.Properties.Creation; use Glib.Properties.Creation;
with Gtk.Menu_Item;            use Gtk.Menu_Item;
with Gtk.Menu;                 use Gtk.Menu;
with String_Utils;             use String_Utils;
with Docgen;
with GNAT.Directory_Operations; use GNAT.Directory_Operations;
with Projects.Registry;         use Projects.Registry;
with GNAT.OS_Lib;               use GNAT.OS_Lib;
with Docgen_Backend_HTML;       use Docgen_Backend_HTML;

package body Docgen_Module is

   Me : constant Debug_Handle := Create ("Docgen");

   type Docgen_Module_Record is new Module_ID_Record with record
      --  Docgen preferences

      Type_Generated_File   : Param_Spec_Enum;
      --  Type of the generated file (html, texi...)

      Generate_Body_Files   : Param_Spec_Boolean;
      --  Create also the body documentation

      Ignore_Some_Comments  : Param_Spec_Boolean;
      --  Ignore all comments with "--!"

      Comments_Before       : Param_Spec_Boolean;
      --  Find doc comments for entities before the entity itself

      Show_Private_Entities : Param_Spec_Boolean;
      --  Show also private entities

      Show_References       : Param_Spec_Boolean;
      --  True if the program should search for the references
      --  Adding information like "subprogram called by..."

      One_Document_File     : Param_Spec_Boolean;
      --  Used for TexInfo: True, if the project.texi file should be
      --  build and the package files should be included there later.

      Link_All_References   : Param_Spec_Boolean;
      --  Should links be created to entities whose declaration files
      --  aren't being processed

      Process_Tagged_Types  : Param_Spec_Boolean;
      --  True to we want to build a list with all tagged
      --  types declared in the list of files we are processing. For each
      --  tagged types we indicate its parent and children (if they exist)

      Options : All_Options;
      --  Group all the preferences

      HTML_Backend : Docgen.Docgen_Backend.Backend_Handle;
      --  A backend suitable for generating HTML output
   end record;
   type Docgen_Module is access all Docgen_Module_Record'Class;

   package Type_Api_Doc_Properties is new
     Glib.Generic_Properties.Generic_Enumeration_Property
       ("Type_Api_Doc", Type_Api_Doc);

   procedure Set_Options
     (Type_Of_File_P         : Type_Api_Doc := HTML;
      Process_Body_Files_P   : Boolean := False;
      Ignorable_Comments_P   : Boolean := False;
      Comments_Above_P       : Boolean := False;
      Show_Private_P         : Boolean := False;
      References_P           : Boolean := False;
      One_Doc_File_P         : Boolean := False;
      Link_All_P             : Boolean := False;
      Tagged_Types_P         : Boolean := False);
   --  Set new options or reset options
   --
   --  - Type_Of_File_P is the type of the generated file (html, texi...)
   --  - Process_Body_Files_P indicates if we create also documentation
   --    for body files.
   --  - Ignorable_Comments_P indicates if we ignore all comments with "--!"
   --  - Comments_Above_P says if we generate doc comments for entities above
   --    the header.
   --  - Show_Private_P indicates if we show also private entities
   --  - References_P says if we add information like "subprogram called by..."
   --  - One_Doc_File_P says if we create documentation in only one
   --    file (only for texi)
   --  - Link_All_P indicates if links are created for entities whose
   --    declaration files aren't processed
   --  - Tagged_Types indicates if we make a list with all tagged
   --    types declared in the list of files we are processing. For each
   --    tagged types we indicate his parent and his children (if they exist).

   procedure Array2List
     (Kernel     : Kernel_Handle;
      Tab        : VFS.File_Array_Access;
      List       : in out Type_Source_File_Table.HTable;
      Doc_Suffix : String);
   --  Create a list of files with those contained in the array

   procedure On_Preferences_Changed
     (Kernel : access Kernel_Handle_Record'Class);
   --  Called when the preferences have changed

   -----------------------------
   -- For the contextual menu --
   -----------------------------

   procedure Docgen_Contextual
     (Object    : access GObject_Record'Class;
      Context   : access Selection_Context'Class;
      Menu      : access Gtk.Menu.Gtk_Menu_Record'Class);
   --  Add entries to the contextual menu

   procedure Add_Doc_Menu_Project
     (Menu         : in out Gtk_Menu;
      Project      : Project_Type;
      Kernel       : access Kernel_Handle_Record'Class);
   --  Submenu for a project

   procedure On_Generate_Project
     (Kernel : access GObject_Record'Class; Data : File_Project_Record);
   --  Contextual menu : Generate Doc -> Only this project

   procedure On_Generate_Project_Recursive
     (Kernel : access GObject_Record'Class; Data : File_Project_Record);
   --  Contextual menu : Generate Doc -> this project & imported projects

   procedure On_Generate_File
     (Kernel : access GObject_Record'Class; Data : File_Project_Record);
   --  Contextual menu : Generate Doc (for a file)

   ------------------
   -- For the menu --
   ------------------

   procedure Choose_Menu_Current_File
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle);
   --  Generate the doc for the selected file

   procedure Choose_Menu_Project
      (Widget : access GObject_Record'Class; Kernel : Kernel_Handle);
   --  In order to generate the doc of the loaded project
   --  It generates only the direct sources of the project
   --  It calls Generate_Project

   procedure Choose_Menu_Project_Recursive
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle);
   --  In order to generate the doc of the project loaded
   --  It generates the direct sources of the project and the sources
   --     from imported projects
   --  It calls Generate_Project

   procedure Generate_Project
     (Kernel    : Kernel_Handle;
      Recursive : Boolean);
   --  Generate the doc for the project
   --  If Recursive is true, it generates the direct sources of
   --  the project and also the sources from imported projects

   procedure Choose_Menu_File
      (Widget : access GObject_Record'Class; Kernel : Kernel_Handle);
   --  In order to choose a file and generate its documentation
   --  It calls Generate_File

   procedure Generate_File
     (Kernel : Kernel_Handle;
      File   : Virtual_File_Access);
   --  In order to generate the documentation of one file

   ------------------------------------------
   -- main procedure for the documentation --
   ------------------------------------------

   function Get_Backend return Docgen.Docgen_Backend.Backend_Handle;
   --  Return the backend to use given the current options

   procedure Generate
     (Kernel : Kernel_Handle;
      List   : in out Type_Source_File_Table.HTable;
      Backend : access Docgen.Docgen_Backend.Backend'Class);
   --  With the list of source files, it generates the documentation

   -----------------
   -- Get_Options --
   -----------------

   procedure Get_Options (My_Options : in out All_Options) is
   begin
      My_Options :=
        (Type_Of_File       =>
           Docgen_Module (Docgen_Module_ID).Options.Type_Of_File,
         Process_Body_Files =>
           Docgen_Module (Docgen_Module_ID).Options.Process_Body_Files,
         Ignorable_Comments =>
           Docgen_Module (Docgen_Module_ID).Options.Ignorable_Comments,
         Comments_Above     =>
           Docgen_Module (Docgen_Module_ID).Options.Comments_Above,
         Show_Private       =>
           Docgen_Module (Docgen_Module_ID).Options.Show_Private,
         References         =>
           Docgen_Module (Docgen_Module_ID).Options.References,
         One_Doc_File       =>
           Docgen_Module (Docgen_Module_ID).Options.One_Doc_File,
         Link_All           =>
           Docgen_Module (Docgen_Module_ID).Options.Link_All,
         Tagged_Types       =>
           Docgen_Module (Docgen_Module_ID).Options.Tagged_Types);
   end Get_Options;

   -----------------
   -- Set_Options --
   -----------------

   procedure Set_Options
     (Type_Of_File_P       : Type_Api_Doc := HTML;
      Process_Body_Files_P : Boolean := False;
      Ignorable_Comments_P : Boolean := False;
      Comments_Above_P     : Boolean := False;
      Show_Private_P       : Boolean := False;
      References_P         : Boolean := False;
      One_Doc_File_P       : Boolean := False;
      Link_All_P           : Boolean := False;
      Tagged_Types_P       : Boolean := False) is
   begin
      Docgen_Module (Docgen_Module_ID).Options.Type_Of_File := Type_Of_File_P;
      Docgen_Module (Docgen_Module_ID).Options.Process_Body_Files :=
        Process_Body_Files_P;
      Docgen_Module (Docgen_Module_ID).Options.Ignorable_Comments :=
        Ignorable_Comments_P;
      Docgen_Module (Docgen_Module_ID).Options.Comments_Above :=
        Comments_Above_P;
      Docgen_Module (Docgen_Module_ID).Options.Show_Private :=
        Show_Private_P;
      Docgen_Module (Docgen_Module_ID).Options.References :=
        References_P;
      Docgen_Module (Docgen_Module_ID).Options.One_Doc_File :=
        One_Doc_File_P;
      Docgen_Module (Docgen_Module_ID).Options.Link_All :=
        Link_All_P;
      Docgen_Module (Docgen_Module_ID).Options.Tagged_Types :=
        Tagged_Types_P;
   end Set_Options;

   ----------------
   -- Array2List --
   ----------------

   procedure Array2List
     (Kernel     : Kernel_Handle;
      Tab        : VFS.File_Array_Access;
      List       : in out Type_Source_File_Table.HTable;
      Doc_Suffix : String)
   is
      File   : aliased Virtual_File;
      Source : Source_File;
      Is_Spec : Boolean;
   begin
      for J in 1 .. Tab'Length loop
         File := Tab (J);

         Is_Spec := Is_Spec_File (Kernel, File);

         if Docgen_Module (Docgen_Module_ID).Options.Process_Body_Files
           or else Is_Spec
         then
            Source := Get_Or_Create
              (Db           => Get_Database (Kernel),
               File         => File,
               Allow_Create => True);
            Type_Source_File_Table.Set
              (List,
               Source,
               (Package_Name  => new String'(Get_Unit_Name (Source)),
                Doc_File_Name => new String'
                  (Get_Doc_File_Name (File, Doc_Suffix)),
                Is_Spec       => Is_Spec));
         end if;
      end loop;
   end Array2List;

   ----------------------------
   -- On_Preferences_Changed --
   ----------------------------

   procedure On_Preferences_Changed
     (Kernel : access Kernel_Handle_Record'Class) is
   begin
      Set_Options
        (Type_Api_Doc'Val
           (Get_Pref
              (Kernel, Docgen_Module (Docgen_Module_ID).Type_Generated_File)),
         Get_Pref
           (Kernel, Docgen_Module (Docgen_Module_ID).Generate_Body_Files),
         Get_Pref
           (Kernel, Docgen_Module (Docgen_Module_ID).Ignore_Some_Comments),
         Get_Pref
           (Kernel, Docgen_Module (Docgen_Module_ID).Comments_Before),
         Get_Pref
           (Kernel, Docgen_Module (Docgen_Module_ID).Show_Private_Entities),
         Get_Pref (Kernel, Docgen_Module (Docgen_Module_ID).Show_References),
         Get_Pref
           (Kernel, Docgen_Module (Docgen_Module_ID).One_Document_File),
         Get_Pref
           (Kernel, Docgen_Module (Docgen_Module_ID).Link_All_References),
         Get_Pref
           (Kernel, Docgen_Module (Docgen_Module_ID).Process_Tagged_Types));
   end On_Preferences_Changed;

   -----------------------
   -- Docgen_Contextual --
   -----------------------

   procedure Docgen_Contextual
     (Object    : access GObject_Record'Class;
      Context   : access Selection_Context'Class;
      Menu      : access Gtk.Menu.Gtk_Menu_Record'Class)
   is
      pragma Unreferenced (Object);
      Item         : Gtk_Menu_Item;
      File_Context : File_Selection_Context_Access;
      Submenu      : Gtk_Menu;
      File         : Virtual_File;

   begin
      if Context.all in File_Selection_Context'Class then
         File_Context := File_Selection_Context_Access (Context);

         if Has_Project_Information (File_Context)
           and then not Has_Directory_Information (File_Context)
           and then not Has_File_Information (File_Context)
         then
            Add_Doc_Menu_Project
              (Menu         => Submenu,
               Project      => Project_Information (File_Context),
               Kernel       => Get_Kernel (Context));

            if Submenu /= null then
               Gtk_New (Item, -"Documentation");
               Set_Submenu (Item, Submenu);
               Append (Menu, Item);
            end if;

         elsif Has_Directory_Information (File_Context)
           and then not Has_File_Information (File_Context)
         then
            null;

         elsif Has_File_Information (File_Context) then
            File := File_Information (File_Context);
            Gtk_New (Item, -"Generate doc for " & Krunch (Base_Name (File)));
            File_Project_Cb.Object_Connect
               (Item, "activate",
                File_Project_Cb.To_Marshaller (On_Generate_File'Access),
                Slot_Object => Get_Kernel (Context),
                User_Data => File_Project_Record'
                  (Project => No_Project,
                   File    => File));
            Append (Menu, Item);
         end if;
      end if;
   end Docgen_Contextual;

   --------------------------
   -- Add_Doc_Menu_Project --
   --------------------------

   procedure Add_Doc_Menu_Project
     (Menu         : in out Gtk_Menu;
      Project      : Project_Type;
      Kernel       : access Kernel_Handle_Record'Class)
   is
      pragma Unreferenced (Project);
      Mitem     : Gtk_Menu_Item;
      Mitem_Bis : Gtk_Menu_Item;

   begin
      if Menu = null then
         Gtk_New (Menu);
      end if;

      Gtk_New (Mitem, -"Generate project");
      Append (Menu, Mitem);
      Gtk_New (Mitem_Bis, -"Generate project & subprojects");
      Append (Menu, Mitem_Bis);

      File_Project_Cb.Object_Connect
        (Mitem, "activate",
         File_Project_Cb.To_Marshaller (On_Generate_Project'Access),
         Slot_Object => Kernel,
         User_Data => File_Project_Record'
           (Project => Get_Project (Kernel),
            File    => VFS.No_File));
      File_Project_Cb.Object_Connect
        (Mitem_Bis, "activate",
         File_Project_Cb.To_Marshaller (On_Generate_Project_Recursive'Access),
         Slot_Object => Kernel,
         User_Data => File_Project_Record'
           (Project => Get_Project (Kernel),
            File    => VFS.No_File));
   end Add_Doc_Menu_Project;

   -------------------------
   -- On_Generate_Project --
   -------------------------

   procedure On_Generate_Project
     (Kernel : access GObject_Record'Class; Data : File_Project_Record)
   is
      pragma Unreferenced (Data);
   begin
      Generate_Project (Kernel_Handle (Kernel), False);
   end On_Generate_Project;

   -----------------------------------
   -- On_Generate_Project_Recursive --
   -----------------------------------

   procedure On_Generate_Project_Recursive
     (Kernel : access GObject_Record'Class; Data : File_Project_Record)
   is
   pragma Unreferenced (Data);
   begin
      Generate_Project (Kernel_Handle (Kernel), True);
   end On_Generate_Project_Recursive;

   ----------------------
   -- On_Generate_File --
   ----------------------

   procedure On_Generate_File
     (Kernel : access GObject_Record'Class; Data : File_Project_Record) is
   begin
      Generate_File (Kernel_Handle (Kernel), Data.File'Unchecked_Access);
   end On_Generate_File;

   ------------------------------
   -- Choose_Menu_Current_File --
   ------------------------------

   procedure Choose_Menu_Current_File
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle)
   is
      pragma Unreferenced (Widget);
      Context : constant Selection_Context_Access :=
        Get_Current_Context (Kernel);
      File    : aliased Virtual_File;

   begin
      if Context.all in File_Selection_Context'Class
        and then Has_File_Information (File_Selection_Context_Access (Context))
      then
         File := File_Information (File_Selection_Context_Access (Context));

         if File = VFS.No_File then
            return;
         else
            Generate_File (Kernel, File'Unchecked_Access);
         end if;
      end if;
   end Choose_Menu_Current_File;

   -------------------------
   -- Choose_Menu_Project --
   -------------------------

   procedure Choose_Menu_Project
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle)
   is
      pragma Unreferenced (Widget);
   begin
      Generate_Project (Kernel, False);
   end Choose_Menu_Project;

   -----------------------------------
   -- Choose_Menu_Project_Recursive --
   -----------------------------------

   procedure Choose_Menu_Project_Recursive
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle)
   is
      pragma Unreferenced (Widget);
   begin
      Generate_Project (Kernel, True);
   end Choose_Menu_Project_Recursive;

   ----------------------
   -- Generate_Project --
   ----------------------

   procedure Generate_Project
     (Kernel    : Kernel_Handle;
      Recursive : Boolean)
   is
      Sources : VFS.File_Array_Access;
      Project : Project_Type;
      Context : constant Selection_Context_Access :=
        Get_Current_Context (Kernel);
      Source_File_List : Type_Source_File_Table.HTable;
      B       : constant Docgen.Docgen_Backend.Backend_Handle := Get_Backend;

   begin
      if Context = null then
         return;
      end if;

      if Context.all in File_Selection_Context'Class
        and then Has_Project_Information
          (File_Selection_Context_Access (Context))
      then
         Project := Project_Information
           (File_Selection_Context_Access (Context));
      else
         Project := Get_Root_Project (Get_Registry (Kernel).all);
      end if;

      --  To save time, parse everything that we'll need in advance
      --  ??? Doesn't work, since the call graph for instance will require that
      --  more files be parsed (try generating doc for traces.ads)
      Trace (Me, "Parsing files");
      Parse_All_LI_Information (Kernel, Project, Recursive => Recursive);
      Trace (Me, "Generating HTML files");

      Sources := Get_Source_Files (Project, Recursive);
      Array2List (Kernel, Sources, Source_File_List,
                  Docgen.Docgen_Backend.Get_Extension (B));
      Generate (Kernel, Source_File_List, B);
      VFS.Unchecked_Free (Sources);
      Type_Source_File_Table.Reset (Source_File_List);

      Trace (Me, "Done generating for project");

   exception
      when E : others =>
         Trace (Exception_Handle,
                "Unexpected exception " & Exception_Information (E));
   end Generate_Project;

   ----------------------
   -- Choose_Menu_File --
   ---------------------

   procedure Choose_Menu_File
    (Widget : access GObject_Record'Class; Kernel : Kernel_Handle)
   is
      pragma Unreferenced (Widget);
      File  : aliased Virtual_File :=
        Select_File
          (Title             => -"Generate Documentation For",
           Parent            => Get_Current_Window (Kernel),
           Use_Native_Dialog => Get_Pref (Kernel, Use_Native_Dialogs),
           Kind              => Unspecified,
           History           => Get_History (Kernel));

   begin
      if File = VFS.No_File then
         return;
      else
         Generate_File (Kernel, File'Unchecked_Access);
      end if;
   end Choose_Menu_File;

   -------------------
   -- Generate_File --
   -------------------

   procedure Generate_File
     (Kernel     : Kernel_Handle;
      File       : Virtual_File_Access)
   is
      Source_File_List : Type_Source_File_Table.HTable;
      Body_File        : Virtual_File;
      Is_Spec          : constant Boolean := Is_Spec_File (Kernel, File);
      Process_Body     : constant Boolean :=
         Docgen_Module (Docgen_Module_ID).Options.Process_Body_Files;
      Source           : Source_File;
      B         : constant Docgen.Docgen_Backend.Backend_Handle := Get_Backend;
      Doc_Suffix       : constant String :=
         Docgen.Docgen_Backend.Get_Extension (B);

   begin
      if not Is_Spec and then not Process_Body then
         return;
      end if;

      Source := Get_Or_Create
        (Db           => Get_Database (Kernel),
         File         => File.all,
         Allow_Create => True);
      Update_Xref (Source);

      Type_Source_File_Table.Set
        (Source_File_List,
         Source,
         (Package_Name  => new String'(Get_Unit_Name (Source)),
          Doc_File_Name => new String'
            (Get_Doc_File_Name (File.all, Doc_Suffix)),
          Is_Spec       => Is_Spec_File (Kernel, File.all)));

      if Is_Spec and then Process_Body then
         Body_File := Create
           (Other_File_Base_Name
              (Get_Project_From_File
                 (Project_Registry (Get_Registry (Kernel).all),
                  File.all),
               File.all),
            Kernel,
            Use_Object_Path => False);
         Source := Get_Or_Create
           (Db           => Get_Database (Kernel),
            File         => Body_File,
            Allow_Create => True);
         if Body_File /= No_File then
            Type_Source_File_Table.Set
              (Source_File_List,
               Source,
               (Package_Name => new String'(Get_Unit_Name (Source)),
                Doc_File_Name => new String'
                  (Get_Doc_File_Name (Body_File, Doc_Suffix)),
                Is_Spec      => Is_Spec_File (Kernel, Body_File)));
         end if;
      end if;

      Generate (Kernel, Source_File_List, B);

   exception
      when E : others =>
         Trace (Exception_Handle,
                "Unexpected exception " & Exception_Information (E));
   end Generate_File;

   -----------------
   -- Get_Backend --
   -----------------

   function Get_Backend return Docgen.Docgen_Backend.Backend_Handle is
   begin
      case Docgen_Module (Docgen_Module_ID).Options.Type_Of_File is
         when HTML =>
            return Docgen_Module (Docgen_Module_ID).HTML_Backend;

            --  ???
            --       when TEXI =>
            --          return Docgen_Module (Docgen_Module_ID).TEXI_Backend

         when others =>
            return null;
      end case;
   end Get_Backend;

   --------------
   -- Generate --
   --------------

   procedure Generate
     (Kernel : Kernel_Handle;
      List   : in out Type_Source_File_Table.HTable;
      Backend : access Docgen.Docgen_Backend.Backend'Class)
   is
      use Docgen.Docgen_Backend;
   begin
      Push_State (Kernel, Busy);

      --  We override old documentations which has the same format and
      --  which has been already processed.
      --  Documentation for new files is added.

      if not Is_Directory
        (Get_Doc_Directory (Backend, Kernel))
      then
         Make_Dir
           (Get_Doc_Directory (Backend, Kernel));
      end if;

      Process_Files
        (Backend,
         List,
         Kernel,
         Docgen_Module (Docgen_Module_ID).Options);
      Type_Source_File_Table.Reset (List);

      --  ??? <frameset> not supported by internal html viewer.

      Open_Html
        (Kernel,
         Filename => Create
           (Full_Filename =>
              Get_Doc_Directory (Backend, Kernel)
            & "index" & Get_Extension (Backend)));

      Pop_State (Kernel);

   exception
      when E : others =>
         Trace (Exception_Handle,
                "Unexpected exception: " & Exception_Information (E));
         Pop_State (Kernel);
   end Generate;

   ---------------------
   -- Register_Module --
   ---------------------

   procedure Register_Module
     (Kernel : access Glide_Kernel.Kernel_Handle_Record'Class)
   is
      Tools    : constant String := '/' & (-"Tools");
      Generate : constant String := '/' & (-"_Documentation");
   begin
      Docgen_Module_ID := new Docgen_Module_Record;
      Docgen_Module (Docgen_Module_ID).HTML_Backend := new Backend_HTML;

      Register_Module
        (Module                  => Docgen_Module_ID,
         Kernel                  => Kernel,
         Module_Name             => "Docgen",
         Contextual_Menu_Handler => Docgen_Contextual'Access,
         Priority                => Default_Priority);

      Docgen_Module (Docgen_Module_ID).Type_Generated_File
        := Param_Spec_Enum
        (Type_Api_Doc_Properties.Gnew_Enum
           (Name    => "Doc-Output",
            Default => HTML,
            Blurb   => -"Choose the kind of documentation generated",
            Nick    => -"Output"));
      Register_Property
        (Kernel,
         Param_Spec (Docgen_Module (Docgen_Module_ID).Type_Generated_File),
         -"Documentation");

      Docgen_Module (Docgen_Module_ID).Generate_Body_Files
        := Param_Spec_Boolean
        (Gnew_Boolean
          (Name    => "Doc-Process-Body",
           Default => False,
           Blurb   => -"Whether body files should be processed",
           Nick    => -"Process body files"));
      Register_Property
        (Kernel,
         Param_Spec (Docgen_Module (Docgen_Module_ID).Generate_Body_Files),
         -"Documentation");

      Docgen_Module (Docgen_Module_ID).Ignore_Some_Comments
        := Param_Spec_Boolean
        (Gnew_Boolean
          (Name    => "Doc-Ignore-Special-Comments",
           Default => False,
           Blurb   =>
             -("Whether Docgen should ignore all comments with --!"),
           Nick    => -"Ignore comments with --!"));
      Register_Property
        (Kernel,
         Param_Spec (Docgen_Module (Docgen_Module_ID).Ignore_Some_Comments),
         -"Documentation");

      Docgen_Module (Docgen_Module_ID).Comments_Before
        := Param_Spec_Boolean
        (Gnew_Boolean
          (Name    => "Doc-Comments-Before",
           Default => False,
           Blurb   =>
             -("Whether comments are found before corresponding entities"),
           Nick    => -"Comments before entities"));
      Register_Property
        (Kernel,
         Param_Spec (Docgen_Module (Docgen_Module_ID).Comments_Before),
         -"Documentation");

      Docgen_Module (Docgen_Module_ID).Show_Private_Entities
        := Param_Spec_Boolean
        (Gnew_Boolean
          (Name    => "Doc-Show-Private",
           Default => False,
           Blurb   => -"Whether Docgen should show private entities",
           Nick    => -"Show private entities"));
      Register_Property
        (Kernel,
         Param_Spec (Docgen_Module (Docgen_Module_ID).Show_Private_Entities),
         -"Documentation");

      Docgen_Module (Docgen_Module_ID).Show_References := Param_Spec_Boolean
        (Gnew_Boolean
          (Name    => "Doc-References",
           Default => False,
           Blurb   =>
             -("Whether Docgen should compute references (e.g. call graph)"),
           Nick    => -"Compute references"));
      Register_Property
        (Kernel,
         Param_Spec (Docgen_Module (Docgen_Module_ID).Show_References),
         -"Documentation");

      Docgen_Module (Docgen_Module_ID).One_Document_File := Param_Spec_Boolean
        (Gnew_Boolean
          (Name    => "Doc-Texi-Single",
           Default => False,
           Blurb   =>
             -("Whether Docgen should generate doc in one file (TexInfo"),
           Nick    => -"Single file (for TexInfo)"));
      Register_Property
        (Kernel,
         Param_Spec (Docgen_Module (Docgen_Module_ID).One_Document_File),
         -"Documentation");

      Docgen_Module (Docgen_Module_ID).Link_All_References :=
        Param_Spec_Boolean
          (Gnew_Boolean
            (Name    => "Doc-Xref-All",
             Default => False,
             Blurb   =>
               -"Links for entities declared in files which are not processed",
             Nick    => -"Create all links"));
      Register_Property
        (Kernel,
         Param_Spec (Docgen_Module (Docgen_Module_ID).Link_All_References),
         -"Documentation");

      Docgen_Module (Docgen_Module_ID).Process_Tagged_Types :=
        Param_Spec_Boolean
          (Gnew_Boolean
            (Name    => "Doc-Tagged",
             Default => False,
             Blurb   =>
               -"List of tagged types declared in processed files",
             Nick    => -"List tagged types"));
      Register_Property
        (Kernel,
         Param_Spec (Docgen_Module (Docgen_Module_ID).Process_Tagged_Types),
         -"Documentation");

      Add_Hook
        (Kernel, Preferences_Changed_Hook, On_Preferences_Changed'Access);
      On_Preferences_Changed (Kernel);

      Register_Menu
        (Kernel,
         Tools & Generate,
         -"Generate _project",
         Callback => Choose_Menu_Project'Access);

      Register_Menu
        (Kernel,
         Tools & Generate,
         -"Generate project & _subprojects",
         Callback => Choose_Menu_Project_Recursive'Access);

      Register_Menu
        (Kernel,
         Tools & Generate,
         -"Generate _current file",
         Callback => Choose_Menu_Current_File'Access);

      Register_Menu
        (Kernel,
         Tools & Generate,
         -"Generate _for ...",
         Callback => Choose_Menu_File'Access);
   end Register_Module;

end Docgen_Module;
