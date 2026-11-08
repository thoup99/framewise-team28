with Ada.Characters.Latin_1;
with Ada.Strings.Fixed;
with Ada.Strings.Maps;
with Adi.Core; use Adi.Core;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Widget; use Adi.Widget;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Adi.Widget.Text_Editor;
with Adi.Window; use Adi.Window;
with Timeline_View;
with Editor_Context; use Editor_Context;
with Editor_Controller;
with Editor_Styles; use Editor_Styles;
with Editor_Widgets; use Editor_Widgets;

package body Editor_Console is
   package Text_Editors renames Adi.Widget.Text_Editor;
   use type Boxes.Box_Handle;
   use type Inputs.Text_Input_Handle;
   use type Text_Editors.Text_Editor_Handle;
   use type Timeline_View.Views.Handle;
   use type Adi.SDL.Events.SDL_Scancode;

   procedure Submit is
      Whitespace : constant Ada.Strings.Maps.Character_Set :=
        Ada.Strings.Maps.To_Set (" " & Ada.Characters.Latin_1.HT);
      Line : constant String := Ada.Strings.Fixed.Trim
        (Inputs.Get_Text (Console_Input),
         Whitespace, Whitespace);
   begin
      if Line'Length = 0 then
         Inputs.Set_Text (Console_Input, "");
         Set_Focus (W, +Console_Input);
         return;
      end if;

      Editor_Controller.Execute_Console_Line (Line);
      Text_Editors.Append_Text (Console_Output,
        "> " & Line & Ada.Characters.Latin_1.LF &
        FS.Image (Reply) & Ada.Characters.Latin_1.LF);
      Text_Editors.Scroll_To_End (Console_Output);
      Inputs.Set_Text (Console_Input, "");
      Set_Focus (W, +Console_Input);
   end Submit;

   procedure Result (Dialog : Widget_Handle; Index : Natural; Caption : String) is
      pragma Unreferenced (Dialog, Caption);
   begin
      if Index = 1 then
         Submit;
      else
         Dialogs.Hide (Console_Dialog);
         Set_Focus (W, +Tracks);
      end if;
   end Result;

   procedure Show is
   begin
      Dialogs.Show (Console_Dialog);
      Set_Focus (W, +Console_Input);
   end Show;

   procedure Handle_Key
     (Scancode : Adi.SDL.Events.SDL_Scancode;
      Repeat : Boolean; Handled : in out Boolean)
   is
   begin
      if Scancode = Adi.SDL.Events.SDL_SCANCODE_RETURN and then
        Get_Focus_Handle (W) = Widget_Handle'(+Console_Input)
      then
         if not Repeat then
            Submit;
         end if;
         Handled := True;
      end if;
   end Handle_Key;

   procedure Build is
      Content : constant Boxes.Box_Handle := Boxes.Create_Handle;
      Input_Row : constant Boxes.Box_Handle := Boxes.Create_Handle;
      --  Context menus are separate overlays, so they need their own theme.
      Menu_Style : constant Part_Style_Array :=
        (Main_Part => (Style => Style.Base (Panel_Style).Build, Enabled => True), others => <>);
      Menu_Item_Style : constant Part_Style_Array :=
        (Main_Part =>
           (Style => Style.Base
              ((Padding => Set (CSS_Box (Px (6.0), Px (8.0))), others => <>))
              .On_Hover ((Background_Color => Set_Bg (RGB (45, 78, 119)), others => <>))
              .On_Selected ((Background_Color => Set_Bg (RGB (45, 78, 119)), others => <>)).Build,
            Enabled => True),
         Label_Part =>
           (Style => Style.Base (Text_Style)
              .On_Disabled ((Color => Set (RGB (145, 155, 170)), others => <>)).Build,
            Enabled => True),
         others => <>);
   begin
      Console_Dialog := Dialogs.Create_Handle;
      Dialogs.Attach_Window (Console_Dialog, W);
      Dialogs.Set_Title (Console_Dialog, "Framewise Console");
      Dialogs.Set_Auto_Close (Console_Dialog, False);
      Dialogs.Set_Dismiss_On_Backdrop (Console_Dialog, False);
      Dialogs.Add_Button (Console_Dialog, "Run");
      Dialogs.Add_Button (Console_Dialog, "Close");
      Dialogs.Connect_Result (Console_Dialog, Result'Access);
      Dialogs.Set_Panel_Style (Console_Dialog,
        (Main_Part => (Style => Style.Base
           ((Panel_Style with delta Width => Set (Size (Px (760.0))),
             Max_Width => Set (Size (Pct (95.0))), Max_Height => Set (Size (Pct (90.0))))).Build,
         Enabled => True), others => <>));
      Dialogs.Set_Title_Style (Console_Dialog,
        (Label_Part => (Style => Style.Base (Text_Style).Build, Enabled => True), others => <>));
      Dialogs.Set_Button_Row_Style (Console_Dialog,
        (Main_Part => (Style => Style.Base (Row_Style).Build, Enabled => True), others => <>));
      Style_Button (Dialogs.Get_Button_Handle (Console_Dialog, 1));
      Style_Button (Dialogs.Get_Button_Handle (Console_Dialog, 2));

      Set_Part_Style (+Content, Main_Part, Style.Base
        ((Panel_Style with delta Height => Set (Size (Px (340.0))),
          Min_Height => Set (Size (Px (100.0))))).Build);
      Add_Label (+Content, "Enter a Framewise command, then press Enter or Run.");
      Console_Output := Text_Editors.Create_Handle ("Framewise console ready." & Ada.Characters.Latin_1.LF);
      Text_Editors.Set_Read_Only (Console_Output);
      Text_Editors.Set_Context_Menu_Part_Styles (Console_Output, Menu_Style);
      Text_Editors.Set_Context_Menu_Item_Part_Styles (Console_Output, Menu_Item_Style);
      Set_Part_Style (+Console_Output, Main_Part, Style.Base
        ((Flex_Grow => Set (1.0), Height => Set (Size (Px (0.0))),
          Min_Height => Set (Size (Px (40.0))),
          Background_Color => Set_Bg (RGB (12, 17, 24)), others => <>)).Build);
      Set_Part_Style (+Console_Output, Text_Part, Style.Base (Text_Style).Build);
      Add_Child (+Content, +Console_Output);

      Set_Part_Style (+Input_Row, Main_Part, Style.Base (Row_Style).Build);
      Add_Label (+Input_Row, ">");
      Console_Input := Inputs.Create_Handle;
      Inputs.Set_Min_Visible_Chars (Console_Input, 12);
      Inputs.Set_Context_Menu_Part_Styles (Console_Input, Menu_Style);
      Inputs.Set_Context_Menu_Item_Part_Styles (Console_Input, Menu_Item_Style);
      Set_Part_Style (+Console_Input, Main_Part, Style.Base
        ((Flex_Grow => Set (1.0), Width => Set (Size (Px (0.0))),
          Min_Width => Set (Size (Px (60.0))),
          Background_Color => Set_Bg (RGB (38, 50, 67)),
          Padding => Set (CSS_Box (Px (6.0))), others => <>)).Build);
      Set_Part_Style (+Console_Input, Text_Part, Style.Base (Text_Style).Build);
      --  A light caret remains visible against the dark input, including
      --  when the field is empty. Show and Submit both restore input focus.
      Set_Part_Style (+Console_Input, Cursor_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (240, 245, 255)), others => <>)).Build);
      Set_Part_Style (+Console_Input, Selected_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (52, 112, 204)), others => <>)).Build);
      Add_Child (+Input_Row, +Console_Input);
      Add_Child (+Content, +Input_Row);
      Dialogs.Set_Content (Console_Dialog, +Content);
   end Build;
end Editor_Console;
