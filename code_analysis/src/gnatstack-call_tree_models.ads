-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                     Copyright (C) 2010, AdaCore                   --
--                                                                   --
-- GPS is Free  software;  you can redistribute it and/or modify  it --
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
private with Ada.Containers.Vectors;

private with Glib.Values;
private with Gtk.Tree_Model;
with Gtkada.Abstract_Tree_Model;

with GNATStack.Data_Model;

package GNATStack.Call_Tree_Models is

   type Call_Tree_Model_Record is
     new Gtkada.Abstract_Tree_Model.Gtk_Abstract_Tree_Model_Record with
       private;

   type Call_Tree_Model is access all Call_Tree_Model_Record'Class;

   procedure Gtk_New
     (Item       : out Call_Tree_Model;
      Subprogram :
        not null GNATStack.Data_Model.Subprogram_Information_Access);

   procedure Initialize
     (Self       : not null access Call_Tree_Model_Record'Class;
      Subprogram :
        not null GNATStack.Data_Model.Subprogram_Information_Access);

private

   type Node_Record;
   type Node_Access is access all Node_Record;

   package Node_Vectors is new Ada.Containers.Vectors (Positive, Node_Access);

   type Node_Record is record
      Subprogram : GNATStack.Data_Model.Subprogram_Information_Access;
      Populated  : Boolean := False;
      Parent     : Node_Access;
      Children   : Node_Vectors.Vector;
   end record;

   type Call_Tree_Model_Record is
     new Gtkada.Abstract_Tree_Model.Gtk_Abstract_Tree_Model_Record with
      record
         Stamp : Glib.Gint := 1;
         Root  : aliased Node_Record := (Populated => True, others => <>);
      end record;

   overriding function Children
     (Self   : access Call_Tree_Model_Record;
      Parent : Gtk.Tree_Model.Gtk_Tree_Iter)
      return Gtk.Tree_Model.Gtk_Tree_Iter;
   --  Override this to return the first child of Parent. If Parent has no
   --  children, return Null_Iter. Parent will remain a valid node after this
   --  function has been called.

   overriding function Get_Column_Type
     (Self  : access Call_Tree_Model_Record;
      Index : Glib.Gint) return Glib.GType;
   --  Override this to return the type of the Index-th column in the model.

   overriding function Get_Iter
     (Self : access Call_Tree_Model_Record;
      Path : Gtk.Tree_Model.Gtk_Tree_Path)
      return Gtk.Tree_Model.Gtk_Tree_Iter;
   --  Override this return an iterator pointing to Path.
   --  Null_Iter is returned if Path was invalid or no iterator could be set.

   overriding function Get_N_Columns
     (Self : access Call_Tree_Model_Record) return Glib.Gint;
   --  Override this to return the number of columns supported by Tree_Model.

   overriding function Get_Path
     (Self : access Call_Tree_Model_Record;
      Iter : Gtk.Tree_Model.Gtk_Tree_Iter)
      return Gtk.Tree_Model.Gtk_Tree_Path;
   --  Override this to return a newly created Gtk_Tree_Path referenced by
   --  Iter. This path will be freed with Path_Free by the caller.

   overriding procedure Get_Value
     (Self   : access Call_Tree_Model_Record;
      Iter   : Gtk.Tree_Model.Gtk_Tree_Iter;
      Column : Glib.Gint;
      Value  : out Glib.Values.GValue);
   --  Override this get a value from the model, at column Column and line
   --  Iter. Value must be freed by the caller.

   overriding function Has_Child
     (Self : access Call_Tree_Model_Record;
      Iter : Gtk.Tree_Model.Gtk_Tree_Iter) return Boolean;
   --  Override this to return True if Iter has children, False otherwise.

   overriding function N_Children
     (Self : access Call_Tree_Model_Record;
      Iter : Gtk.Tree_Model.Gtk_Tree_Iter := Gtk.Tree_Model.Null_Iter)
      return Glib.Gint;
   --  Override this to return the number of children that Iter has.
   --  As a special case, if Iter is Null_Iter, then the number of toplevel
   --  nodes is returned.

   overriding procedure Next
     (Self : access Call_Tree_Model_Record;
      Iter : in out Gtk.Tree_Model.Gtk_Tree_Iter);
   --  Override this to set Iter to point to the node following it at the
   --  current level. If there is none, Iter is set to Null_Iter.

   overriding function Nth_Child
     (Self   : access Call_Tree_Model_Record;
      Parent : Gtk.Tree_Model.Gtk_Tree_Iter;
      N      : Glib.Gint) return Gtk.Tree_Model.Gtk_Tree_Iter;
   --  Override this to return the child of Parent, using the given index.
   --  The First index is 0. If Index is too big, or Parent has no children,
   --  return Null_Iter. If Parent is Null_Iter, then the nth root node is set.

   overriding function Parent
     (Self  : access Call_Tree_Model_Record;
      Child : Gtk.Tree_Model.Gtk_Tree_Iter)
      return Gtk.Tree_Model.Gtk_Tree_Iter;
   --  Override this to return the parent of Child. If Child is at the
   --  toplevel, and doesn't have a parent, then Null_Iter is returned.

end GNATStack.Call_Tree_Models;
