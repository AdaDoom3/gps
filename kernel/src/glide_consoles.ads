-----------------------------------------------------------------------
--                                                                   --
--                     Copyright (C) 2001                            --
--                          ACT-Europe                               --
--                                                                   --
-- This library is free software; you can redistribute it and/or     --
-- modify it under the terms of the GNU General Public               --
-- License as published by the Free Software Foundation; either      --
-- version 2 of the License, or (at your option) any later version.  --
--                                                                   --
-- This library is distributed in the hope that it will be useful,   --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of    --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details.                          --
--                                                                   --
-- You should have received a copy of the GNU General Public         --
-- License along with this library; if not, write to the             --
-- Free Software Foundation, Inc., 59 Temple Place - Suite 330,      --
-- Boston, MA 02111-1307, USA.                                       --
--                                                                   --
-- As a special exception, if other files instantiate generics from  --
-- this unit, or you link this unit with other files to produce an   --
-- executable, this  unit  does not  by itself cause  the resulting  --
-- executable to be covered by the GNU General Public License. This  --
-- exception does not however invalidate any other reasons why the   --
-- executable file  might be covered by the  GNU Public License.     --
-----------------------------------------------------------------------

--  This package provides the implementation for the glide console.
--  It includes all the functions related to manipulating the console.

with Gtk.Scrolled_Window;
with Gtk.Text;
with Glide_Kernel;

package Glide_Consoles is

   type Glide_Console_Record is new
     Gtk.Scrolled_Window.Gtk_Scrolled_Window_Record with private;
   type Glide_Console is access all Glide_Console_Record'Class;


   procedure Gtk_New
     (Console : out Glide_Console;
      Kernel  : access Glide_Kernel.Kernel_Handle_Record'Class);
   --  Create a new console for glide

   procedure Initialize
     (Console : access Glide_Console_Record'Class;
      Kernel  : access Glide_Kernel.Kernel_Handle_Record'Class);
   --  Internal initialization function.

   procedure Insert
     (Console        : access Glide_Console_Record;
      Text           : String;
      Highlight_Sloc : Boolean := True;
      Add_LF         : Boolean := True);
   --  Insert Text in the Glide's console.
   --  Highlight parts of Text that match a source location (the color is set
   --  using the preferences) if Highlight_Sloc is True.
   --  If Add_LF is True, automatically add a line separator.

private

   type Glide_Console_Record is new
     Gtk.Scrolled_Window.Gtk_Scrolled_Window_Record with
      record
         Kernel : Glide_Kernel.Kernel_Handle;
         Text   : Gtk.Text.Gtk_Text;
      end record;

end Glide_Consoles;
