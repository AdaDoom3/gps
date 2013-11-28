------------------------------------------------------------------------------
--                                  G P S                                   --
--                                                                          --
--                     Copyright (C) 2007-2013, AdaCore                     --
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

with Ada.Unchecked_Deallocation;

with Ada.Characters.Handling; use Ada.Characters.Handling;
with GNATCOLL.Traces;         use GNATCOLL.Traces;
with GPS.Intl;                use GPS.Intl;
with GPS.Messages_Windows;    use GPS.Messages_Windows;
with GNATdoc.Atree;           use GNATdoc.Atree;
with GNATdoc.Backend;         use GNATdoc.Backend;
with GNATdoc.Frontend;        use GNATdoc.Frontend;
with GNATdoc.Time;            use GNATdoc.Time;
with GNATdoc.Treepr;          use GNATdoc.Treepr;
with GNATdoc.Utils;           use GNATdoc.Utils;
with Language;                use Language;
with Language.Ada;
with Language.C;
with Language.Tree;           use Language.Tree;
with Language.Tree.Database;  use Language.Tree.Database;
with Templates_Parser;        use Templates_Parser;
with Xref.Docgen;             use Xref.Docgen;

with GNAT.IO;  -- to be removed???

package body GNATdoc is
   Me : constant Trace_Handle := Create ("GNATdoc.1");

   -----------------------
   -- Local Subprograms --
   -----------------------

   Serious_Errors : Natural := 0;

   procedure Check_Tree
     (Context   : access constant Docgen_Context;
      Tree      : access Tree_Type;
      All_Files : Files_List.Vector);
   --  Verify that all the nodes of the tree have a minimum decoration

   procedure Process_Files
     (Kernel              : Core_Kernel;
      Options             : Docgen_Options;
      Prj_Files           : in out Project_Files_List.Vector;
      Update_Global_Index : Boolean);
   --  This subprogram factorizes the functionality shared by routines
   --  Process_Single_File and Process_Project_Files. It processes all
   --  the files in Src_Files and generates their documentation.

   ----------------
   -- Check_Tree --
   ----------------

   procedure Check_Tree
     (Context   : access constant Docgen_Context;
      Tree      : access Tree_Type;
      All_Files : Files_List.Vector)
   is
      function Check_Node
        (Entity      : Entity_Id;
         Scope_Level : Natural) return Traverse_Result;
      --  Check a single node

      function Check_Node
        (Entity      : Entity_Id;
         Scope_Level : Natural) return Traverse_Result
      is
         pragma Unreferenced (Scope_Level);

         procedure Check (Entity : Entity_Id);
         procedure Check_List (List : EInfo_List.Vector);

         procedure Check (Entity : Entity_Id) is

            procedure Error_Msg (Msg : String);
            procedure Error_Msg (Msg : String) is
            begin
               Serious_Errors := Serious_Errors + 1;

               GNAT.IO.Put_Line
                 (Image (LL.Get_Location (Entity))
                  & ":"
                  & Get_Short_Name (Entity)
                  & ":"
                  & Msg);
               Atree.pn (Entity);

               if Present (Get_Full_View (Entity)) then
                  Atree.pn (Get_Full_View (Entity));
               end if;
            end Error_Msg;

         begin
            --  We cannot verify entities which are not fully decorated
            --  because they are not part of the project (for example,
            --  entities defined in the runtime of the compiler)

            if not Is_Decorated (Entity) then
               if All_Files.Contains (LL.Get_Location (Entity).File) then
                  Error_Msg ("missing full decoration");
               end if;
            else
               if No (Get_Scope (Entity))
                 and then not Is_Standard_Entity (Entity)
               then
                  Error_Msg ("missing scope decoration (decorated)");

               elsif Present (Get_Alias (Entity))
                 and then No (Get_Scope (Get_Alias (Entity)))
                 and then All_Files.Contains
                            (LL.Get_Location (Get_Alias (Entity)).File)
               then
                  Error_Msg ("missing scope decoration in alias");

               elsif Has_Duplicated_Entities
                       (LL.Get_Parent_Types (Entity).all)
               then
                  Error_Msg ("duplicated entities (Parent_Types)");

               elsif Has_Duplicated_Entities
                       (Get_Progenitors (Entity).all)
               then
                  Error_Msg ("duplicated entities (Progenitors)");

               elsif Has_Duplicated_Entities
                       (Get_Entities (Entity).all)
               then
                  Error_Msg ("duplicated entities (Entities)");

               elsif Has_Duplicated_Entities
                       (Get_Inherited_Methods (Entity).all)
               then
                  Error_Msg ("duplicated entities (Inherited_Methods)");

               elsif Has_Duplicated_Entities
                       (Get_Methods (Entity).all)
               then
                  Error_Msg ("duplicated entities (Methods)");

               elsif Has_Duplicated_Entities
                       (Get_Direct_Derivations (Entity).all)
               then
                  Error_Msg ("duplicated entities (Direct derivations)");

               elsif Has_Duplicated_Entities
                       (LL.Get_Child_Types (Entity).all)
               then
                  Error_Msg ("duplicated entities (Child types)");
               end if;
            end if;
         end Check;

         procedure Check_List (List : EInfo_List.Vector) is
            Cursor : EInfo_List.Cursor;
         begin
            if not EInfo_List.Has_Element (List.First) then
               return;
            end if;

            Cursor := List.First;
            while EInfo_List.Has_Element (Cursor) loop
               Check (EInfo_List.Element (Cursor));
               EInfo_List.Next (Cursor);
            end loop;
         end Check_List;

      begin
         Check (Entity);

         --  Temporarily disabled because it causes regressions!

         Check_List (LL.Get_Parent_Types (Entity).all);
         Check_List (LL.Get_Child_Types (Entity).all);

         return OK;
      end Check_Node;

      Lang         : constant Language_Access :=
                       Get_Language_From_File
                        (Context.Lang_Handler, Tree.File);
      In_Ada_Lang  : constant Boolean :=
                       Lang.all in Language.Ada.Ada_Language'Class;
      In_C_Lang    : constant Boolean := not In_Ada_Lang;
      Root         : Entity_Id renames Tree.Tree_Root;
      Root_E       : Entity_Id;
   begin
      if In_C_Lang then
         Root_E := Root;

         --  At current stage we can check only trees of Ada sources
         return;
      else
         declare
            C : constant EInfo_List.Cursor := Get_Entities (Root).First;
         begin
            if EInfo_List.Has_Element (C) then
               Root_E := EInfo_List.Element (C);
            else
               Root_E := null;
            end if;
         end;
      end if;

      if No (Root_E) then
         return;
      end if;

      Traverse_Tree (Root_E, Check_Node'Access);
   end Check_Tree;

   -------------------
   -- Process_Files --
   -------------------

   procedure Process_Files
     (Kernel              : Core_Kernel;
      Options             : Docgen_Options;
      Prj_Files           : in out Project_Files_List.Vector;
      Update_Global_Index : Boolean)
   is
      Database     : constant General_Xref_Database := Kernel.Databases;
      Lang_Handler : constant Language_Handler := Kernel.Lang_Handler;

      procedure Check_Src_Files;
      --  Check the contents of Src_Files and remove from the list those files
      --  which can not be processed

      procedure Collect_C_Header_Files
        (Direct_Include_Files : access Files_List.Vector;
         All_Include_Files    : access Files_List.Vector);
      --  Collect in Direct_Include_Files all the C/C++ header files referenced
      --  directly by files of Prj_Files, and collect in All_Include_Files all
      --  the C/C++ header files which are transitively referenced by all the
      --  sources of Prj_Files.

      function Have_Files
        (Prj_Files : Project_Files_List.Vector) return Boolean;
      --  Return true if some project in Prj_Files has a file to be processed

      function Number_Of_Files
        (Prj_Files     : Project_Files_List.Vector;
         Include_Files : Files_List.Vector := Files_List.Empty_Vector)
        return Natural;
      --  Return the total number of source files stored in Prj_Files plus
      --  the number of files stored in Include_Files

      procedure Check_Src_Files is

         function Skip_File (File_Index : Files_List.Cursor) return Boolean;
         --  Return True if the file Src_Files (File_Index) cannot be
         --  processed.

         ---------------
         -- Skip_File --
         ---------------

         function Skip_File
           (File_Index : Files_List.Cursor) return Boolean
         is
            File : Virtual_File;
            Lang : Language_Access;
         begin
            if not Files_List.Element (File_Index).Is_Regular_File then
               if Options.Report_Errors = Errors_And_Warnings then
                  Kernel.Messages_Window.Insert
                    ((-"warning: the file ") &
                       Display_Full_Name
                       (Files_List.Element (File_Index)) &
                     (-" cannot be found. It will be skipped."),
                     Mode => GPS.Messages_Windows.Info);
               end if;

               return True;
            end if;

            File := Files_List.Element (File_Index);
            Lang := Get_Language_From_File
              (Lang_Handler, Files_List.Element (File_Index));

            --  We don't support yet other parsers than Ada, C and C++

            if Lang.all not in Language.Ada.Ada_Language'Class
              and then Lang.all not in Language.C.C_Language'Class
            then
               Kernel.Messages_Window.Insert
                 (-("info: Documentation not generated for ") &
                    Display_Base_Name (File) &
                  (-" since this language is not supported."),
                  Mode => GPS.Messages_Windows.Info);

               return True;
            end if;

            --  Verify that we have the LI file for this source file.

            if not Database.Is_Up_To_Date (File) then
               --  (C/C++) Do not report error on header files since the
               --  compiler does not generate their LI file.

               if Lang.all in Language.C.C_Language'Class
                 and then Is_Spec_File (Kernel, File)
               then
                  null;

               elsif Options.Report_Errors = Errors_And_Warnings then
                  Kernel.Messages_Window.Insert
                    (-("warning: cross references for file ") &
                       Display_Base_Name (File) &
                     (-" are not up-to-date. Documentation not generated."),
                     Mode => GPS.Messages_Windows.Error);
               end if;

               return True;
            end if;

            if Lang.all in Language.Ada.Ada_Language'Class
              and then not Is_Spec_File (Kernel, File)
            then
               return True;

            elsif Options.Skip_C_Files
              and then Lang.all in Language.C.C_Language'Class
            then
               return True;
            end if;

            return False;
         end Skip_File;

         --  Local variables

         File_Index : Files_List.Cursor;
         Prj_Index  : Project_Files_List.Cursor;
         Prj_Srcs   : Project_Files;

      --  Start of processing for Check_Files

      begin
         Prj_Index := Prj_Files.First;
         while Project_Files_List.Has_Element (Prj_Index) loop
            Prj_Srcs := Project_Files_List.Element (Prj_Index);

            File_Index := Prj_Srcs.Src_Files.First;
            while Files_List.Has_Element (File_Index) loop
               if Skip_File (File_Index) then
                  Remove_Element (Prj_Srcs.Src_Files.all, File_Index);
               else
                  Files_List.Next (File_Index);
               end if;
            end loop;

            Project_Files_List.Next (Prj_Index);
         end loop;
      end Check_Src_Files;

      ----------------------------
      -- Collect_C_Header_Files --
      ----------------------------

      procedure Collect_C_Header_Files
        (Direct_Include_Files : access Files_List.Vector;
         All_Include_Files    : access Files_List.Vector)
      is
         Prj_Srcs : Project_Files;

         procedure Collect_Include_Files
           (File   : Virtual_File;
            Result : access Files_List.Vector);

         procedure Collect_Include_Files
           (File   : Virtual_File;
            Result : access Files_List.Vector)
         is
            Cursor : Xref.Entities_In_File_Cursor;
            E      : General_Entity;
            Loc    : General_Location;

         begin
            Cursor := Database.Entities_In_File (File);
            while not At_End (Cursor) loop
               E   := Cursor.Get;
               Loc := Get_Location (Database, E);

               if Xref.Get_Display_Kind (Database, E) = "include file"
                 and then not Result.Contains (Loc.File)
               then
                  Result.Append (Loc.File);
               end if;

               Cursor.Next;
            end loop;
         end Collect_Include_Files;

         File_Index : Files_List.Cursor;
         Lang       : Language_Access;
         Prj_Index  : Project_Files_List.Cursor;

      begin
         Prj_Index := Prj_Files.First;
         while Project_Files_List.Has_Element (Prj_Index) loop
            Prj_Srcs := Project_Files_List.Element (Prj_Index);

            File_Index := Prj_Srcs.Src_Files.First;
            while Files_List.Has_Element (File_Index) loop
               Lang :=
                 Get_Language_From_File
                   (Lang_Handler, Files_List.Element (File_Index));

               if Lang.all in Language.C.C_Language'Class then
                  Collect_Include_Files
                    (File   => Files_List.Element (File_Index),
                     Result => Direct_Include_Files);
               end if;

               Files_List.Next (File_Index);
            end loop;

            Project_Files_List.Next (Prj_Index);
         end loop;

         --  At this stage Include_Files contains all the header files which
         --  are directly included by files of the project. Now we continue
         --  collecting all the headers which are transitively included in
         --  these header files.

         declare
            In_Files : aliased Files_List.Vector;
            Result   : aliased Files_List.Vector;

            use type Ada.Containers.Count_Type;
         begin
            Append_Unique_Files
              (Target => In_Files'Access,
               Source => Direct_Include_Files);

            while In_Files.Length > 0 loop
               Result.Clear;

               File_Index := In_Files.First;
               while Files_List.Has_Element (File_Index) loop
                  if not All_Include_Files.Contains
                    (Files_List.Element (File_Index))
                  then
                     All_Include_Files.Append
                       (Files_List.Element (File_Index));

                     Collect_Include_Files
                       (File   => Files_List.Element (File_Index),
                        Result => Result'Access);
                  end if;

                  Files_List.Next (File_Index);
               end loop;

               In_Files.Clear;

               Append_Unique_Files
                 (Target   => In_Files'Access,
                  Source => Result'Access);
            end loop;
         end;
      end Collect_C_Header_Files;

      ----------------
      -- Have_Files --
      ----------------

      function Have_Files
        (Prj_Files : Project_Files_List.Vector) return Boolean
      is
         File_Index : Files_List.Cursor;
         Prj_Index  : Project_Files_List.Cursor;
         Prj_Srcs   : Project_Files;

      begin
         Prj_Index := Prj_Files.First;
         while Project_Files_List.Has_Element (Prj_Index) loop
            Prj_Srcs := Project_Files_List.Element (Prj_Index);

            File_Index := Prj_Srcs.Src_Files.First;

            if Files_List.Has_Element (File_Index) then
               return True;
            end if;

            Project_Files_List.Next (Prj_Index);
         end loop;

         return False;
      end Have_Files;

      ---------------------
      -- Number_Of_Files --
      ---------------------

      function Number_Of_Files
        (Prj_Files     : Project_Files_List.Vector;
         Include_Files : Files_List.Vector := Files_List.Empty_Vector)
         return Natural
      is
         Count      : Natural;
         File_Index : Files_List.Cursor;
         Prj_Index  : Project_Files_List.Cursor;
         Prj_Srcs   : Project_Files;

         All_Files  : Files_List.Vector;
         File       : Virtual_File;

      begin
         Prj_Index := Prj_Files.First;
         while Project_Files_List.Has_Element (Prj_Index) loop
            Prj_Srcs := Project_Files_List.Element (Prj_Index);

            File_Index := Prj_Srcs.Src_Files.First;
            while Files_List.Has_Element (File_Index) loop
               File := Files_List.Element (File_Index);

               if not All_Files.Contains (File) then
                  All_Files.Append (File);
               end if;

               Files_List.Next (File_Index);
            end loop;

            Project_Files_List.Next (Prj_Index);
         end loop;

         File_Index := Include_Files.First;
         while Files_List.Has_Element (File_Index) loop
            File := Files_List.Element (File_Index);

            if not All_Files.Contains (File) then
               All_Files.Append (File);
            end if;

            Files_List.Next (File_Index);
         end loop;

         Count := Natural (All_Files.Length);
         All_Files.Clear;

         return Count;
      end Number_Of_Files;

      ----------
      -- Free --
      ----------

      procedure Free is
        new Ada.Unchecked_Deallocation (Docgen_Context, Docgen_Context_Ptr);

      --  Local variables

      Backend : GNATdoc_Backend'Class :=
                  New_Backend (To_String (Options.Backend_Name));
      Context : aliased Docgen_Context_Ptr :=
                  new Docgen_Context'
                        (Kernel, Database, Lang_Handler, Options, Prj_Files);

      Direct_Include_Files : aliased Files_List.Vector;
      --  C and C++ header files which are directly included by files of the
      --  current project.

      All_Include_Files    : aliased Files_List.Vector;
      --  All the C and C++ header files which transitively included by all
      --  the header files of the project

   --  Start of processing for Process_Files

   begin
      --  Register the database in the tree. Needed by internal routines
      --  which can be called directly from gdb

      Atree.Register_Database (Database);

      --  Remove from the list those files which cannot be processed

      Check_Src_Files;

      if not Have_Files (Prj_Files) then
         Trace (Me, "No files to process");
         return;
      end if;

      if not Context.Options.Skip_C_Files then
         Collect_C_Header_Files
           (Direct_Include_Files'Access, All_Include_Files'Access);
      end if;

      GNATdoc.Time.Reset;

      --  Initialize the Atree. Required to reset the internal counter used to
      --  generate the unique identifiers of the tree nodes (and thus associate
      --  the same id to repeated executions of this module; required when a
      --  breakpoint in set in node with a given id. For details on debugging
      --  see the comments in the body of gnatdoc-atree.adb).

      Atree.Initialize;

      --  Initialize the backend. Required to ensure that we create the
      --  destination directory with support files before processing the
      --  first file.

      Backend.Initialize (Context);

      --  Sort the list of projects and their files. Done to ensure that we
      --  process all the projects in the same order in all the platforms.

      declare
         Prj_Index : Project_Files_List.Cursor;
         Prj_Srcs  : Project_Files;
      begin
         Project_Files_Sort.Sort (Prj_Files);

         Prj_Index := Prj_Files.First;
         while Project_Files_List.Has_Element (Prj_Index) loop
            Prj_Srcs := Project_Files_List.Element (Prj_Index);
            Files_Vector_Sort.Sort (Prj_Srcs.Src_Files.all);

            Project_Files_List.Next (Prj_Index);
         end loop;

         Files_Vector_Sort.Sort (All_Include_Files);
      end;

      --  Process all the files

      declare
         Num_Files  : constant Natural :=
                        Number_Of_Files (Prj_Files, All_Include_Files);
         Count      : Natural := 0;
         All_Files  : Files_List.Vector;
         --  Used to avoid processing a file twice

         All_Trees  : Frontend.Tree_List.Vector;
         Prj_Index  : Project_Files_List.Cursor;
         Prj_Srcs   : Project_Files;

         procedure Process_Src_Files (Src_Files : access Files_List.Vector);
         procedure Process_Src_Files (Src_Files : access Files_List.Vector) is
            File_Index : Files_List.Cursor;

         begin
            File_Index := Src_Files.First;
            while Files_List.Has_Element (File_Index) loop

               declare
                  Current_File  : Virtual_File
                                    renames Files_List.Element (File_Index);
                  Tree          : aliased Tree_Type;

               begin
                  if not All_Files.Contains (Current_File) then
                     if not Options.Quiet_Mode then
                        Count := Count + 1;
                        GNAT.IO.Put_Line
                          (Count'Img & "/" & To_String (Num_Files)
                           & ": "
                           & (+Current_File.Base_Name));
                     end if;

                     Tree :=
                       Frontend.Build_Tree
                         (Context => Context,
                          File    => Current_File);

                     All_Files.Append (Current_File);
                     All_Trees.Append (Tree);
                  end if;
               end;

               Files_List.Next (File_Index);
            end loop;
         end Process_Src_Files;

      begin
         Trace (Me, "Number of files to process: " & Num_Files'Img);

         Process_Src_Files (All_Include_Files'Access);

         Prj_Index := Prj_Files.First;
         while Project_Files_List.Has_Element (Prj_Index) loop
            Prj_Srcs := Project_Files_List.Element (Prj_Index);
            Process_Src_Files (Prj_Srcs.Src_Files);

            Project_Files_List.Next (Prj_Index);
         end loop;

         if Tree_List.Has_Element (All_Trees.First) then
            declare
               Cursor           : Tree_List.Cursor;
               Tree             : aliased Tree_Type;
               Is_C_Header_File : Boolean;
            begin
               --  Verify the trees and generate their output files. This
               --  cannot be done before because as part of decorating a tree
               --  the frontend may complete the decoration of entities defined
               --  in other trees (for example, the decoration of a derived
               --  type completes the decoration of its parent type, which may
               --  be located in another file ---and hence in another tree).

               Cursor := All_Trees.First;
               while Tree_List.Has_Element (Cursor) loop
                  Tree := Tree_List.Element (Cursor);

                  Check_Tree (Context, Tree'Access, All_Files);

                  --  We cannot rely on the service Get_Language_From_File
                  --  because it does not work well with C/C++ header files

                  Is_C_Header_File := All_Include_Files.Contains (Tree.File);

                  --  Target dependant include files generate supurious output
                  --  differences (even processing only the files which are
                  --  directly included from the C body files referenced in
                  --  the project ---available in Direct_Include_Files). For
                  --  this reason we disable their output. More work will be
                  --  needed in this area when we decide to provide full
                  --  support of gnatdoc for C/C++ files.

                  if not Is_C_Header_File then
                     if Options.Tree_Output.Kind /= None then
                        if Options.Tree_Output.Kind = Short then
                           Treepr.Print_Short_Tree
                             (Context     => Context,
                              Tree        => Tree'Access,
                              With_Scopes => True);
                        else
                           Treepr.Print_Full_Tree
                             (Context     => Context,
                              Tree        => Tree'Access,
                              With_Scopes => True);
                        end if;
                     end if;

                     if Options.Output_Comments then
                        Treepr.Print_Comments
                          (Context => Context,
                           Tree    => Tree'Access);
                     end if;
                  end if;

                  Tree_List.Next (Cursor);
               end loop;
            end;

            --  No need to continue if we found serious errors in the tree
            --  since the backend may crash!

            if Serious_Errors > 0 then
               return;
            end if;

            --  Set the inheritance depth level of tagged types. This cannot
            --  be done before because files are not processed following their
            --  order of dependencies (and thus a file containing a child type
            --  may be processed by the frontend before the file containing
            --  its parent type).

            declare
               procedure Set_Idepth (E : Entity_Id);
               procedure Set_Idepth (E : Entity_Id) is
               begin
                  if Is_Tagged (E) then
                     Set_IDepth_Level (E);
                  end if;
               end Set_Idepth;

               procedure Set_Alias (E : Entity_Id);
               procedure Set_Alias (E : Entity_Id) is
                  Alias : Entity_Id;
               begin
                  if Present (LL.Get_Alias (E))
                    and then No (Get_Alias (E))
                  then
                     Alias :=
                       Find_Unique_Entity
                         (Get_Location (Database, LL.Get_Alias (E)));

                     --  Alias should be present. However, using the sources
                     --  of the gnat project there is an entity for which
                     --  LL.Get_Alias() seems to be erroneously decorated.
                     --  May be a bug in Xref/ALI: to be investigated???

                     if Present (Alias) then
                        Set_Alias (E, Alias);
                     end if;

                  end if;
               end Set_Alias;

               Cursor : Tree_List.Cursor;
               Tree   : aliased Tree_Type;

            begin
               Cursor := All_Trees.First;
               while Tree_List.Has_Element (Cursor) loop
                  Tree := Tree_List.Element (Cursor);

                  For_All (Tree.All_Entities, Set_Idepth'Access);
                  For_All (Tree.All_Entities, Set_Alias'Access);

                  begin
                     Backend.Process_File (Tree'Access);
                  exception
                     when E : others =>
                        Trace (Me, E);
                        Kernel.Messages_Window.Insert
                          (-("error: exception occurred when processing ") &
                             Tree.File.Display_Full_Name,
                           Mode => Info);
                  end;

                  Tree_List.Next (Cursor);
               end loop;

               if not Options.Quiet_Mode then
                  Kernel.Messages_Window.Insert
                    (-("info: Documentation generated in ") &
                       Get_Doc_Directory (Kernel).Display_Full_Name,
                     Mode => Info);
               end if;
            end;
         end if;

         All_Files.Clear;
      end;

      Backend.Finalize (Update_Global_Index);

      Templates_Parser.Release_Cache;

      if Options.Display_Time then
         Time.Print_Time (Context);
      end if;

      Free (Context);

   exception
      when E : others =>
         GNAT.IO.Put_Line ("Internal error: program terminated");
         Free (Context);
         Trace (Me, E);
   end Process_Files;

   ---------------------------
   -- Process_Project_Files --
   ---------------------------

   procedure Process_Project_Files
     (Kernel    : not null access GPS.Core_Kernels.Core_Kernel_Record'Class;
      Options   : Docgen_Options;
      Project   : Project_Type;
      Recursive : Boolean := False)
   is
      P         : Project_Type := Project;
      Src_Files : Files_List.Vector;
      Prj_Files : Project_Files_List.Vector;
      Prj_Srcs  : Project_Files;

   begin
      Trace (Me, "Process_Project_Files");

      if P = No_Project then
         P := Kernel.Registry.Tree.Root_Project;
      end if;

      Prj_Srcs.Src_Files := new Files_List.Vector;

      if not Recursive then
         declare
            Source_Files  : File_Array_Access := P.Source_Files;
         begin
            Prj_Srcs.Project := P;

            for J in Source_Files'Range loop
               Prj_Srcs.Src_Files.Append (Source_Files (J));
            end loop;

            Unchecked_Free (Source_Files);
            Prj_Files.Append (Prj_Srcs);
         end;
      else
         declare
            Prj_Iter : Project_Iterator := P.Start_Reversed;

         begin
            while Current (Prj_Iter) /= No_Project loop
               Prj_Srcs.Project := Current (Prj_Iter);

               declare
                  Source_Files : File_Array_Access :=
                                   Prj_Srcs.Project.Source_Files;
               begin
                  for J in Source_Files'Range loop
                     Prj_Srcs.Src_Files.Append (Source_Files (J));
                  end loop;

                  Unchecked_Free (Source_Files);
               end;

               Prj_Files.Append (Prj_Srcs);

               Next (Prj_Iter);
            end loop;
         end;
      end if;

      --  Clear the internal structures of the frontend
      Frontend.Initialize;

      Process_Files
        (Kernel    => Core_Kernel (Kernel),
         Options   => Options,
         Prj_Files => Prj_Files,
         Update_Global_Index => True);

      Src_Files.Clear; -- Free???
   end Process_Project_Files;

   -------------------------
   -- Process_Single_File --
   -------------------------

   procedure Process_Single_File
     (Kernel  : not null access GPS.Core_Kernels.Core_Kernel_Record'Class;
      Options : Docgen_Options;
      File    : GNATCOLL.VFS.Virtual_File)
   is
      Other_File : constant Virtual_File :=
                     Kernel.Registry.Tree.Other_File (File);
      Src_Files  : Files_List.Vector;
      Prj_Files  : Project_Files_List.Vector;
      Prj_Srcs   : Project_Files;

   begin
      Trace (Me, "Process_Single_File");

      Prj_Srcs.Project := No_Project;
      Prj_Srcs.Src_Files := new Files_List.Vector;
      Prj_Srcs.Src_Files.Append (File);

      if Other_File /= File
        and then Is_Regular_File (Other_File)
      then
         Prj_Srcs.Src_Files.Append (Other_File);
      end if;

      Prj_Files.Append (Prj_Srcs);

      Process_Files
        (Kernel    => Core_Kernel (Kernel),
         Options   => Options,
         Prj_Files => Prj_Files,
         Update_Global_Index => False);

      Src_Files.Clear;
   end Process_Single_File;

   -----------
   -- Files --
   -----------

   package body Files is

      -------------------------
      -- Append_Unique_Files --
      -------------------------

      procedure Append_Unique_Files
        (Target : access Files_List.Vector;
         Source : access Files_List.Vector)
      is
         File_Index : Files_List.Cursor;
      begin
         File_Index := Source.First;
         while Files_List.Has_Element (File_Index) loop
            if not Target.Contains (Files_List.Element (File_Index)) then
               Target.Append (Files_List.Element (File_Index));
            end if;

            Files_List.Next (File_Index);
         end loop;
      end Append_Unique_Files;

      -----------------
      -- Print_Files --
      -----------------

      procedure Print_Files
        (Source : Files_List.Vector)
      is
         File_Index : Files_List.Cursor;
      begin
         GNAT.IO.Put_Line ("---------------");
         File_Index := Source.First;
         while Files_List.Has_Element (File_Index) loop
            GNAT.IO.Put_Line
              (String (Files_List.Element (File_Index).Base_Name));

            Files_List.Next (File_Index);
         end loop;
      end Print_Files;

      --------------
      -- Filename --
      --------------

      function Filename (File : Virtual_File) return Filesystem_String is
         Ext  : constant Filesystem_String := File.File_Extension;
         Base : constant Filesystem_String := File.Base_Name;
         Name : constant Filesystem_String :=
           Base (Base'First .. Base'Last - Ext'Length);
      begin
         return Name;
      end Filename;

      ---------------
      -- Less_Than --
      ---------------

      function Less_Than (Left, Right : Virtual_File) return Boolean is
      begin
         return To_Lower (+Base_Name (Left)) < To_Lower (+Base_Name (Right));
      end Less_Than;

      function Less_Than (Left, Right : Project_Files) return Boolean is
      begin
         return To_Lower (Name (Left.Project))
                  < To_Lower (Name (Right.Project));
      end Less_Than;

      --------------------
      -- Remove_Element --
      --------------------

      procedure Remove_Element
        (List   : in out Files_List.Vector;
         Cursor : in out Files_List.Cursor)
      is
         Prev : constant Files_List.Extended_Index :=
           Files_List.To_Index (Cursor);
      begin
         List.Delete (Cursor);
         Cursor := List.To_Cursor (Prev);
      end Remove_Element;

   end Files;

   -------------------
   -- Write_To_File --
   -------------------

   procedure Write_To_File
     (Context   : access constant Docgen_Context;
      Directory : Virtual_File;
      Filename  : Filesystem_String;
      Text      : access Unbounded_String)
   is
      Name   : Virtual_File;
      Output : Writable_File;

   begin
      if not Is_Directory (Directory) then
         Directory.Make_Dir;
      end if;

      Name   := Create_From_Dir (Directory, Filename);
      Output := Name.Write_File;

      if Output = Invalid_File then
         Context.Kernel.Messages_Window.Insert
           ("Could not create " & Name.Display_Full_Name,
            Mode => GPS.Messages_Windows.Error);
         return;
      end if;

      Write (Output, To_String (Text.all));
      Close (Output);
   end Write_To_File;

   -------------------
   -- Write_To_File --
   -------------------

   procedure Write_To_File
     (Context   : access constant Docgen_Context;
      Directory : Virtual_File;
      Filename  : Filesystem_String;
      Text      : String)
   is
      Name   : Virtual_File;
      Output : Writable_File;

   begin
      if not Is_Directory (Directory) then
         Directory.Make_Dir;
      end if;

      Name   := Create_From_Dir (Directory, Filename);
      Output := Name.Write_File;

      if Output = Invalid_File then
         Context.Kernel.Messages_Window.Insert
           ("Could not create " & Name.Display_Full_Name,
            Mode => GPS.Messages_Windows.Error);
         return;
      end if;

      Write (Output, Text);
      Close (Output);
   end Write_To_File;

end GNATdoc;
