with Adi.Core; use Adi.Core;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Widget; use Adi.Widget;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Framewise;
with Editor_Context; use Editor_Context;
with Adi.OS;
with Ada.Strings.Fixed;
with Editor_Styles; use Editor_Styles;
with Editor_Widgets; use Editor_Widgets;
with Editor_Controller; use Editor_Controller;

package body Editor_Dialogs is
   use type Labels.Label_Handle;
   use type Inputs.Text_Input_Handle;
   use type Combos.Combo_Box_Handle;
   use type Boxes.Box_Handle;

   function Field (Index : Positive) return String is
     (Ada.Strings.Fixed.Trim (Inputs.Get_Text (Values (Index)), Ada.Strings.Both));

   procedure Set_Field (Index : Positive; Caption, Value : String) is
   begin
      Labels.Set_Text (Captions (Index), Caption);
      Inputs.Set_Text (Values (Index), Value);
      Set_Flag (+Captions (Index), Visible, Caption'Length > 0);
      Set_Flag (+Values (Index), Visible, Caption'Length > 0);
   end Set_Field;

   procedure Prepare_Form (New_Mode : Form_Mode; Title : String) is
   begin
      Mode := New_Mode;
      Dialogs.Set_Title (Form, Title);
      for I in Values'Range loop
         Set_Field (I, "", "");
      end loop;
      Set_Flag (+Kind_Choice, Visible, New_Mode in Import_Media | Add_Track);
      Combos.Set_Selected_Index (Kind_Choice, 1);
   end Prepare_Form;

   procedure Form_Result (Dialog : Widget_Handle; Index : Natural; Caption : String) is
      pragma Unreferenced (Dialog, Caption);
   begin
      if Index /= 1 then
         Dialogs.Hide (Form);
         return;
      end if;
      case Mode is
         when Import_Media =>
            if not Valid_Path (Field (1), "Import Files") then
               return;
            end if;
            Execute_Line ("import " & US.To_String (Form_Target) & " " & Field (1) &
              " " & Field (2) & " " & Combos.Get_Selected_Text (Kind_Choice));
         when Add_Track =>
            if Field (1)'Length not in 1 .. Framewise.Max_Name or else
              (for some C of Field (1) => C not in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_')
            then
               declare
                  Message : constant String := "Track name: use 1-32 letters, numbers, or underscores";
               begin
                  Dialogs.Set_Title (Form, Message);
                  Report_Editor_Error ("Add Track", Message);
               end;
               return;
            end if;
            Execute_Line ("track " & Field (1) & " " & Combos.Get_Selected_Text (Kind_Choice));
         when Place_Clip =>
            Execute_Line ("place " & US.To_String (Form_Target) & " " &
              Combos.Get_Selected_Text (Track_Choice) & " " & Combos.Get_Selected_Text (Source_Choice) &
              " " & Field (1) & " " & Field (2) & " " & Field (3));
         when Move_Clip =>
            Execute_Line ("move " & US.To_String (Form_Target) & " " & Field (1));
         when Project_Settings =>
            Execute_Line ("settings " & Field (1) & " " & Field (2) & " " & Field (3));
      end case;
      if Reply.Ok then
         Dialogs.Hide (Form);
      else
         Dialogs.Set_Title (Form, FS.Image (Reply));
      end if;
   end Form_Result;

   procedure Import_Selected (Files : Adi.OS.String_Array) is
   begin
      if Files'Length = 0 then
         return;
      end if;
      if not Valid_Path (US.To_String (Files (Files'First)), "Import Files") then
         return;
      end if;
      Form_Target := US.To_Unbounded_String (Unique_Name ("media"));
      Prepare_Form (Import_Media, "Import Files - enter media duration in seconds");
      Set_Field (1, "Media file", US.To_String (Files (Files'First)));
      Set_Field (2, "Duration (seconds)", "");
      Dialogs.Show (Form);
   end Import_Selected;

   procedure Build is
   begin
      Form := Dialogs.Create_Handle;
      Form_Content := Boxes.Create_Handle;
      Set_Part_Style (+Form_Content, Main_Part, Style.Base (Panel_Style).Build);
      for I in Values'Range loop
         Captions (I) := Make_Label (+Form_Content, "");
         Values (I) := Inputs.Create_Handle ("");
         Inputs.Set_Min_Visible_Chars (Values (I), 24);
         Set_Part_Style (+Values (I), Text_Part, Style.Base (Text_Style).Build);
         Set_Part_Style (+Values (I), Cursor_Part, Style.Base
           ((Background_Color => Set_Bg (RGB (240, 245, 255)), others => <>)).Build);
         Set_Part_Style (+Values (I), Selected_Part, Style.Base
           ((Background_Color => Set_Bg (RGB (52, 112, 204)), others => <>)).Build);
         Set_Part_Style (+Values (I), Main_Part, Style.Base
           ((Width => Set (Size (Px (Form_Control_Width))),
             Background_Color => Set_Bg (RGB (38, 50, 67)),
             Padding => Set (CSS_Box (Px (6.0))), others => <>)).Build);
         Add_Child (+Form_Content, +Values (I));
      end loop;

      Kind_Choice := Combos.Create_Handle;
      Style_Combo (Kind_Choice);
      Set_Part_Style (+Kind_Choice, Main_Part, Style.Base
        ((Display => Set (Flex), Flex_Direction => Set (Row),
          Width => Set (Size (Px (Form_Control_Width))),
          Height => Set (Size (Px (38.0))), Flex_Shrink => Set (0.0),
          Background_Color => Set_Bg (RGB (38, 50, 67)),
          Padding => Set (CSS_Box (Px (6.0))), others => <>)).Build);
      Combos.Add_Item (Kind_Choice, "video");
      Combos.Add_Item (Kind_Choice, "audio");
      Combos.Add_Item (Kind_Choice, "both");
      Add_Child (+Form_Content, +Kind_Choice);

      Dialogs.Set_Content (Form, +Form_Content);
      Dialogs.Set_Auto_Close (Form, False);
      Dialogs.Add_Button (Form, "Apply");
      Dialogs.Add_Button (Form, "Cancel");
      Dialogs.Connect_Result (Form, Form_Result'Access);

      Confirm := Dialogs.Create_Handle;
      Dialogs.Set_Title (Confirm, "Unsaved project changes");
      Dialogs.Set_Message (Confirm, "Discard changes? Choose Cancel to return and save your project first.");
      Dialogs.Add_Button (Confirm, "Discard Changes");
      Dialogs.Add_Button (Confirm, "Cancel");
      Dialogs.Set_Default_Button (Confirm, 2);
      Dialogs.Connect_Result (Confirm, Confirm_Result'Access);

      declare
         All_Dialogs : constant Dialog_Array := [Form, Confirm];
      begin
         for D of All_Dialogs loop
            Dialogs.Attach_Window (D, W);
            Dialogs.Set_Panel_Style (D,
              (Main_Part => (Style => Style.Base (Panel_Style).Build, Enabled => True), others => <>));
            Dialogs.Set_Button_Row_Style (D,
              (Main_Part => (Style => Style.Base (Row_Style).Build, Enabled => True), others => <>));
            Dialogs.Set_Title_Style (D,
              (Label_Part => (Style => Style.Base (Text_Style).Build, Enabled => True), others => <>));
            Dialogs.Set_Message_Style (D,
              (Label_Part => (Style => Style.Base (Text_Style).Build, Enabled => True), others => <>));
            Style_Button (Dialogs.Get_Button_Handle (D, 1));
            Style_Button (Dialogs.Get_Button_Handle (D, 2));
         end loop;
      end;
   end Build;
end Editor_Dialogs;
