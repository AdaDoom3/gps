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

with Ada.Characters.Handling;  use Ada.Characters.Handling;
with Ada.Text_IO;              use Ada.Text_IO;
with GNAT.OS_Lib;
with System.Img_BIU;           use System.Img_BIU;
with System.WCh_StW;           use System.WCh_StW;

with Glib;             use Glib;

with Gdk.Color;        use Gdk.Color;
with Gdk.Font;         use Gdk.Font;
with Gdk.Window;       use Gdk.Window;

with Gtk;              use Gtk;
with Gtk.Extra.PsFont; use Gtk.Extra.PsFont;
with Gtk.Text;         use Gtk.Text;
with Gtk.GEntry;       use Gtk.GEntry;
with Gtk.Frame;        use Gtk.Frame;
with Gtkada.Canvas;    use Gtkada.Canvas;

with Debugger;              use Debugger;
with Memory_View_Pkg;       use Memory_View_Pkg;

with Odd.Strings; use Odd.Strings;
with Odd.Types;   use Odd.Types;
with Odd.Process; use Odd.Process;

package body Odd.Memory_View is

   ---------------------
   -- Local constants --
   ---------------------

   View_Font      : Gdk_Font;
   View_Color     : Gdk_Color;
   Highlighted    : Gdk_Color;
   Selected       : Gdk_Color;
   White_Color    : Gdk_Color;
   Modified_Color : Gdk_Color;

   -----------------------
   -- Local subprograms --
   -----------------------

   function Is_Highlighted
     (View     : Odd_Memory_View;
      Position : Gint) return Boolean;
   --  Tells whether a given position in the view should be highlighted or not.

   function Conversion
     (S        : in String;
      Size     : Integer;
      Format   : Display_Type;
      Trunc_At : Integer) return String;
   --  Converts a string of hexadecimal digits into a string representing
   --  the same number in Format, with a constant size.

   function To_Standard_Base
     (Address  : in Long_Long_Integer;
      Base     : Integer;
      Trunc_At : Integer := -1) return String;
   --  Conversion from a Long_Long_Integer to a based representation.
   --  Output is truncated to Trunc_At characters if Trunc_At /= -1.

   procedure Clear_View (View : Odd_Memory_View);
   --  Removes everything from the view.

   --------------------
   -- Is_Highlighted --
   --------------------

   function Is_Highlighted
     (View     : Odd_Memory_View;
      Position : Gint) return Boolean
   is
      Row    : Integer;
      Column : Integer;
   begin
      Row := Integer (Position) /
        (View.Number_Of_Columns * (View.Trunc + 1) + 20);
      Column := Integer (Position) -
        Row * (View.Number_Of_Columns * (View.Trunc + 1) + 20) - 18;

      if (Column / (View.Trunc + 1) mod 2) = 1 then
         return True;
      else
         return False;
      end if;
   end Is_Highlighted;

   -----------------------
   -- Position_To_Index --
   -----------------------

   function Position_To_Index
     (View     : in Odd_Memory_View;
      Position : in Gint) return Integer
   is
      Row    : Integer;
      Column : Integer;
      Unit   : Integer;

   begin
      Row := Integer (Position) /
        (View.Number_Of_Columns * (View.Trunc + 1) + 20);
      Column := Integer (Position) -
        Row * (View.Number_Of_Columns * (View.Trunc + 1) + 20) - 18;
      Unit := Column / (View.Trunc + 1) +
        Row * View.Number_Of_Columns;

      return Unit * View.Unit_Size + 1;
   end Position_To_Index;

   ----------------
   -- Conversion --
   ----------------

   function Conversion
     (S        : in String;
      Size     : Integer;
      Format   : Display_Type;
      Trunc_At : Integer) return String
   is
      Long  : Long_Long_Integer;
      Test  : Integer := S'First;
      Dummy : constant String := "------------------------";

   begin
      Skip_To_String (S, Test, "x");

      if Test < S'Last then
         if Trunc_At /= -1 then
            return Dummy (1 .. Trunc_At);
         else
            return "-";
         end if;
      end if;

      Long := Long_Long_Integer'Wide_Value
        (String_To_Wide_String ("16#" & S & "#", 1));

      case Format is
         when Hex =>
            return S;
         when Octal =>
            return To_Standard_Base (Long, 8, Trunc_At);
         when Decimal =>
            return To_Standard_Base (Long, 10, Trunc_At);
         when Text =>
            declare
               Result : String (1 .. S'Length / 2);
               Value  : Integer;
            begin
               for J in 1 .. Result'Last loop
                  Value := Integer'Wide_Value
                    (String_To_Wide_String
                     ("16#" &
                      S (S'First + 2 * J - 2 .. S'First + 2 * J - 1)
                      & "#", 1));
                  if Value > 31 and then Value < 128 then
                     Result (J) := Character'Val (Value);
                  else
                     Result (J) := 'x';
                  end if;
               end loop;

               return Result;
            end;
      end case;
   end Conversion;

   ----------------
   -- Clear_View --
   ----------------

   procedure Clear_View (View : Odd_Memory_View) is
   begin
      Delete_Text (View.View);
   end Clear_View;

   -------------------
   -- Init_Graphics --
   -------------------

   procedure Init_Graphics (Window : Gdk_Window) is
      Success : Boolean;
   begin
      View_Font  := Get_Gdkfont ("Courier", 12);
      View_Color := Parse ("#333399");

      Alloc_Color (Get_System, View_Color, True, True, Success);

      Highlighted := Parse ("#DDDDDD");
      Alloc_Color (Get_System, Highlighted, True, True, Success);

      White_Color := White (Get_System);

      Selected := Parse ("#00009c");
      Alloc_Color (Get_System, Selected, True, True, Success);

      Modified_Color := Parse ("#FF0000");
      Alloc_Color (Get_System, Modified_Color, True, True, Success);
   end Init_Graphics;

   ----------------------
   -- To_Standard_Base --
   ----------------------

   function To_Standard_Base
     (Address  : in Long_Long_Integer;
      Base     : Integer;
      Trunc_At : Integer := -1) return String
   is
      Address_Buffer   : String (1 .. 40);
      Offset_Buffer    : String (1 .. 40);
      Offset_Last      : Natural;
      Address_Last     : Natural;
      Offset_Index     : Natural;
      Address_Index    : Natural;
      Dummy            : Long_Long_Integer := Long_Long_Integer (Base ** 7);

   begin
      Offset_Last := 1;
      Set_Image_Based_Integer
        (Integer (Address mod Dummy + Dummy),
         Base, 20, Offset_Buffer, Offset_Last);
      Offset_Index := 10;
      Skip_Blanks (Offset_Buffer (10 .. Offset_Last), Offset_Index);

      Address_Last := 1;
      Set_Image_Based_Integer
        (Integer (Address / Dummy + Dummy),
         Base, 20, Address_Buffer, Address_Last);
      Address_Index := 10;
      Skip_Blanks (Offset_Buffer (10 .. Address_Last), Address_Index);

      if Trunc_At = -1 then
         return Address_Buffer (Address_Index + 4 .. Address_Last - 1) &
           Offset_Buffer (Offset_Index + 4 .. Offset_Last - 1);

      elsif Trunc_At <= Offset_Last - 5 - Offset_Index then
         return Offset_Buffer (Offset_Last - Trunc_At .. Offset_Last - 1);
      else
         return Address_Buffer
           (Address_Last - (Trunc_At - (Offset_Last - 5 - Offset_Index)) ..
            Address_Last - 1) &
           Offset_Buffer (Offset_Index + 4 .. Offset_Last - 1);
      end if;
   end To_Standard_Base;

   ---------------------
   --  Update_Display --
   ---------------------

   procedure Update_Display (View : Odd_Memory_View) is
      Index      : Integer;
      Width      : Gint;
      Height     : Gint;
      Count      : Integer := 0;
      Background : Gdk_Color := Null_Color;
      Foreground : Gdk_Color := Null_Color;
      Current    : String_Access;

   begin
      if View.Values = null then
         return;
      end if;

      View.Data := Data_Size'Value (Get_Text (View.Size_Entry));

      if Get_Text (View.Data_Entry) = "ASCII" then
         View.Display := Text;
      else
         View.Display := Display_Type'Value (Get_Text (View.Data_Entry));
      end if;

      case View.Data is
         when Byte =>
            View.Unit_Size := 2;
         when Halfword =>
            View.Unit_Size := 4;
         when Word =>
            View.Unit_Size := 8;
      end case;

      case View.Display is
         when Hex =>
            View.Trunc := View.Unit_Size;
         when Text =>
            View.Trunc := View.Unit_Size / 2;
         when Decimal =>
            View.Trunc := Integer (Float (View.Unit_Size) * 1.2 + 0.5);
         when Octal =>
            View.Trunc := View.Unit_Size * 2;
      end case;

      Get_Size (Get_Text_Area (View.View), Width, Height);

      View.Number_Of_Columns :=
        Integer ((Width / Char_Width (View_Font, Character' ('m')) - 30)) /
          (View.Trunc + 1);

      Freeze (View.View);
      Clear_View (View);
      Index := 1;

      Insert
        (View.View,
         Fore  => View_Color,
         Back  => Highlighted,
         Font  => View_Font,
         Chars => "0x" & To_Standard_Base (View.Starting_Address, 16) & ":");
      Insert (View.View, Font  => View_Font, Chars => " ");

      while Index + View.Unit_Size - 1 <= View.Number_Of_Bytes * 2 loop
         if Count mod 2 = 0 then
            Background := Null_Color;
         else
            Background := Highlighted;
         end if;

         if View.Values (Index .. Index + View.Unit_Size - 1) /=
           View.Flags (Index .. Index + View.Unit_Size - 1)
         then
            Foreground := Modified_Color;
            Current := View.Flags;
         else
            Foreground := Null_Color;
            Current := View.Values;
         end if;

         if View.Cursor_Index >= Index
           and then View.Cursor_Index < Index + View.Unit_Size
         then
            View.Cursor_Position := Gint (Get_Length (View.View));
         end if;

         Insert
           (View.View,
            Font  => View_Font,
            Fore  => Foreground,
            Back  => Background,
            Chars =>
              Conversion (Current (Index .. Index + View.Unit_Size - 1),
                          View.Unit_Size,
                          View.Display,
                          View.Trunc));
         Insert
           (View.View,
            Font  => View_Font,
            Fore  => Foreground,
            Back  => Background,
            Chars => " ");
         Count := Count + 1;

         if ((Index + View.Unit_Size) / View.Unit_Size
             mod View.Number_Of_Columns) = 0
           and then Index + View.Unit_Size * 2 - 1 <= View.Number_Of_Bytes * 2
         then
            Count := 0;
            Insert (View.View, Chars => ASCII.CR & ASCII.LF);
            Insert
              (View.View,
               Fore => View_Color,
               Back => Highlighted,
               Font => View_Font,
               Chars =>
                 "0x" & To_Standard_Base
                          (View.Starting_Address
                           + Long_Long_Integer
                           ((Index + View.Unit_Size) / 2), 16) & ":");
            Insert
              (View.View,
               Font  => View_Font,
               Chars => " ");
         end if;

         Index := Index + View.Unit_Size;
      end loop;

      Thaw (View.View);
      Set_Position (View.View, Gint (View.Cursor_Position));
   end Update_Display;

   --------------------
   -- Display_Memory --
   --------------------

   procedure Display_Memory
     (View    : Odd_Memory_View;
      Address : Long_Long_Integer)
   is
      Values : String (1 .. 2 * View.Number_Of_Bytes);
   begin
      Free (View.Values);
      Free (View.Flags);
      View.Starting_Address := Address;

      for J in 1 .. View.Number_Of_Bytes loop
         Values (2 * J - 1 .. 2 * J) :=
           (Get_Memory_Byte
             (Get_Current_Process
              (View.Window).Debugger,
              "0x" & To_Standard_Base (Long_Long_Integer (J - 1)
                                       + View.Starting_Address, 16)));
      end loop;

      View.Values := new String' (Values);
      View.Flags := new String' (Values);
      Update_Display (View);
   end Display_Memory;

   --------------------
   -- Display_Memory --
   --------------------

   procedure Display_Memory (View : Odd_Memory_View; Address : String) is
   begin
      Display_Memory
        (View,
         Long_Long_Integer'Wide_Value
           (String_To_Wide_String
             ("16#" & Address (3 .. Address'Last) & "#", 1)));
   end Display_Memory;

   -------------------
   -- Apply_Changes --
   -------------------

   procedure Apply_Changes (View : Odd_Memory_View) is
   begin
      for J in 1 .. View.Number_Of_Bytes loop
         Put_Memory_Byte
           (Get_Current_Process (View.Window).Debugger,
            "0x" &
              To_Standard_Base
                (View.Starting_Address + Long_Long_Integer (J - 1), 16),
            View.Flags (J * 2 - 1 .. J * 2));
      end loop;

      Free (View.Values);
      View.Values := new String' (View.Flags.all);
      Update_Display (View);
      Refresh_Canvas
        (Interactive_Canvas (Get_Current_Process (View.Window).Data_Canvas));
   end Apply_Changes;

   ------------------------
   -- Create_Memory_View --
   ------------------------

   function Create_Memory_View (Window : Gtk_Widget) return Odd_Memory_View is
      View : Odd_Memory_View;
   begin
      View := new Odd_Memory_View_Record;
      Initialize (View);
      View.Window := Window;
      return View;
   end Create_Memory_View;

   -------------
   -- Page_Up --
   -------------

   procedure Page_Up (View : Odd_Memory_View) is
   begin
      Display_Memory
        (View, View.Starting_Address -
          Long_Long_Integer (View.Number_Of_Bytes));
   end Page_Up;

   ---------------
   -- Page_Down --
   ---------------

   procedure Page_Down (View : Odd_Memory_View) is
   begin
      Display_Memory
        (View, View.Starting_Address +
          Long_Long_Integer (View.Number_Of_Bytes));
   end Page_Down;

   ------------
   -- Update --
   ------------

   procedure Update (View : Odd_Memory_View; Process : Gtk_Widget) is
      Tab : Debugger_Process_Tab := Debugger_Process_Tab (Process);
      use type GNAT.OS_Lib.String_Access;

   begin
      if Tab.Descriptor.Program /= null
        and then Tab.Descriptor.Program.all /= ""
      then
         Set_Label (View.Frame, Tab.Descriptor.Program.all);
      else
         Set_Label (View.Frame, "(no executable)");
      end if;
   end Update;

   -----------------
   -- Move_Cursor --
   -----------------

   procedure Move_Cursor
     (View : Odd_Memory_View; Where : in Dir)
   is
      Move     : Gint := 0;
      Position : Gint := Get_Position (View.View);

   begin
      case Where is
         when Right =>
            if Get_Chars (View.View, Position + 1, Position + 2) = " " then
               Move := 1;
            end if;

         when Left =>
            if Get_Chars (View.View, Position - 1, Position) = " " then
               Move := -1;
            end if;

         when others =>
            null;
      end case;

      Set_Position (View.View, Position + Move);
   end Move_Cursor;


   ------------
   -- Insert --
   ------------

   procedure Insert (View : Odd_Memory_View; Char : String) is
      Prefix      : String (1 .. 3);
      Success     : Boolean;
      Background  : Gdk_Color := Null_Color;
      Value_Index : Integer;

   begin
      if View.View = null then
         return;
      end if;

      Value_Index := Position_To_Index (View, Get_Position (View.View));
      View.Cursor_Position := Get_Position (View.View);
      View.Cursor_Index := Position_To_Index (View, View.Cursor_Position);

      if Get_Chars (View.View,
                    Get_Position (View.View),
                    Get_Position (View.View) + 1) = "-"
      then
         return;
      end if;

      case View.Display is
         when Hex =>
            if Is_Hexadecimal_Digit (Char (Char'First)) then
               Prefix := "16#";
            else
               return;
            end if;
         when Decimal =>
            if Is_Decimal_Digit (Char (Char'First)) then
               Prefix := "10#";
            else
               return;
            end if;
         when Octal =>
            if Char (Char'First) in '0' .. '7' then
               Prefix := "08#";
            else
               return;
            end if;
         when Text =>
            null;
      end case;

      Success := Forward_Delete (View.View, 1);

      if Is_Highlighted (View, Get_Position (View.View)) then
         Background := Highlighted;
      end if;

      declare
         Index      : Integer := 1;
         Next_Index : Integer := 1;
         Current    : String (1 .. 2 * View.Trunc + 2);

      begin
         --  Insert new char.

         Insert (View.View,
                 Font => View_Font,
                 Back => Background,
                 Fore => Modified_Color,
                 Chars => Char);

         --  Grab the new value
         Set_Position (View.View, Get_Position (View.View) - 1);

         Current := Get_Chars (View.View,
                               Get_Position (View.View)
                               - Gint (View.Trunc) - 1,
                               Get_Position (View.View)
                               + Gint (View.Trunc) + 1);
         Skip_To_String (Current, Index, " ");
         Next_Index := Index + 1;
         Skip_To_String (Current, Next_Index, " ");

         --  Modify flags string to match the new value.
         View.Flags (Value_Index .. Value_Index + View.Unit_Size - 1) :=
           (To_Standard_Base
            (Long_Long_Integer'Wide_Value
             (String_To_Wide_String
              (Prefix & Current
               (Index + 1 .. Next_Index - 1) & "#", 1)),
             16,
             View.Unit_Size));
      end;

      Set_Position (View.View, Get_Position (View.View) + 1);

      if Get_Chars
        (View.View,
         Get_Position (View.View),
         Get_Position (View.View) + 1) = " "
      then
         Set_Position (View.View, Get_Position (View.View) + 1);
      end if;
   end Insert;

end Odd.Memory_View;
