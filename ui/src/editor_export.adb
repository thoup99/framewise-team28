with Ada.Strings.Fixed;
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

package body Editor_Export is
   use type Boxes.Box_Handle;
   use type Labels.Label_Handle;
   use type Buttons.Button_Handle;
   use type Inputs.Text_Input_Handle;
   use type Adi.Widget.Text_Editor.Text_Editor_Handle;
   use type Timeline_View.Views.Handle;
   Job : FS.Export_Job;
   Dialog : Dialogs.Dialog_Handle;
   Output : Adi.Widget.Text_Editor.Text_Editor_Handle;
   Progress_Track, Progress_Fill : Boxes.Box_Handle;
   Progress_Label : Labels.Label_Handle;
   Displayed : Integer := -1;
   Log_Line : US.Unbounded_String;
   Log_Origin : Editor_Console.Command_Origin;

   function Is_Busy return Boolean is (FS.Export_Running (Job));
   function Is_Open return Boolean is (Dialogs.Is_Shown (Dialog));
   function Details return String is (Adi.Widget.Text_Editor.Get_Text (Output));

   function Progress_Percent return Natural is (Natural'Max (0, Displayed));

   procedure Show_Progress is
      Value : constant Natural := FS.Export_Percent (Job);
   begin
      if Displayed = Value then
         return;
      end if;
      Displayed := Value;
      Labels.Set_Text (Progress_Label, Ada.Strings.Fixed.Trim (Value'Image, Ada.Strings.Both) & "%");
      Set_Part_Style (+Progress_Fill, Main_Part, Style.Base
        ((Width => Set (Size (Pct (Float (Value)))), Height => Set (Size (Px (18.0))),
          Flex_Shrink => Set (0.0), Background_Color => Set_Bg (RGB (52, 112, 204)),
          Border_Radius => Set (Radius (Px (3.0))), others => <>)).Build);
   end Show_Progress;

   procedure Close is
   begin
      if not Is_Busy then
         Dialogs.Hide (Dialog);
         Set_Focus (W, (if Editor_Console.Is_Open then Widget_Handle'(+Console_Input) else +Tracks));
      end if;
   end Close;

   procedure Result (D : Widget_Handle; Index : Natural; Caption : String) is
      pragma Unreferenced (D, Index, Caption);
   begin
      Close;
   end Result;

   procedure Start (Path : String;
      Origin : Editor_Console.Command_Origin := Editor_Console.Editor_Action;
      Command : String := "") is
   begin
      if Is_Busy then
         Editor_Controller.Tell ("An export is already running.");
         return;
      end if;
      Log_Line := US.To_Unbounded_String
        ((if Command'Length > 0 then Command else "export " & FS.Quote_Path (Path)));
      Log_Origin := Origin;
      FS.Start_Export (Editor, Path, Job, Reply);
      Displayed := -1;
      Show_Progress;
      Set_State (+Dialogs.Get_Button_Handle (Dialog, 1), State_Disabled, Is_Busy);
      Dialogs.Set_Title (Dialog, (if Is_Busy then "Exporting..." else "Export failed"));
      Adi.Widget.Text_Editor.Set_Text (Output,
        (if Is_Busy then "Exporting to:" & ASCII.LF & Path & ASCII.LF & ASCII.LF &
          "The progress bar follows the video processed by FFmpeg."
         else FS.Image (Reply)));
      Dialogs.Show (Dialog);
      Set_Focus (W, +Output);
      Editor_Controller.Tell ((if Is_Busy then "Exporting..." else "Export could not start."));
      if not Is_Busy then
         Editor_Console.Record_Command (US.To_String (Log_Line), FS.Image (Reply), Log_Origin);
      end if;
   end Start;

   procedure Poll (Win : Window_Handle) is
      pragma Unreferenced (Win);
      Finished : Boolean;
      R : FS.Response;
   begin
      if not Is_Busy then
         return;
      end if;
      FS.Poll_Export (Job, R, Finished);
      Show_Progress;
      if Finished then
         Reply := R;
         Dialogs.Set_Title (Dialog, (if R.Ok then "Export complete" else "Export failed"));
         Adi.Widget.Text_Editor.Set_Text (Output, FS.Image (R));
         Adi.Widget.Text_Editor.Scroll_To_End (Output);
         Set_State (+Dialogs.Get_Button_Handle (Dialog, 1), State_Disabled, False);
         Editor_Controller.Tell ((if R.Ok then "Video exported." else "Export failed. See FFmpeg details."));
         Editor_Console.Record_Command (US.To_String (Log_Line), FS.Image (R), Log_Origin);
      end if;
   end Poll;

   procedure Build is
      Content : constant Boxes.Box_Handle := Boxes.Create_Handle;
   begin
      Dialog := Dialogs.Create_Handle;
      Dialogs.Attach_Window (Dialog, W);
      Dialogs.Set_Auto_Close (Dialog, False);
      Dialogs.Set_Dismiss_On_Backdrop (Dialog, False);
      Dialogs.Set_Dismiss_On_Escape (Dialog, False);
      Dialogs.Add_Button (Dialog, "Close");
      Dialogs.Connect_Result (Dialog, Result'Access);
      Dialogs.Set_Panel_Style (Dialog,
        (Main_Part => (Style => Style.Base
          ((Floating_Panel_Style with delta Width => Set (Size (Px (680.0))),
            Max_Width => Set (Size (Pct (95.0))))).Build, Enabled => True), others => <>));
      Dialogs.Set_Title_Style (Dialog,
        (Label_Part => (Style => Style.Base (Text_Style).Build, Enabled => True), others => <>));
      Style_Button (Dialogs.Get_Button_Handle (Dialog, 1));
      Set_Part_Style (+Content, Main_Part, Style.Base
        ((Display => Set (Flex), Flex_Direction => Set (Column), Gap => Set (Gap (Px (8.0))),
          others => <>)).Build);
      Progress_Label := Labels.Create_Handle ("0%");
      Set_Part_Style (+Progress_Label, Label_Part, Style.Base (Text_Style).Build);
      Progress_Track := Boxes.Create_Handle;
      Progress_Fill := Boxes.Create_Handle;
      Set_Part_Style (+Progress_Track, Main_Part, Style.Base
        ((Display => Set (Flex), Flex_Direction => Set (Row), Height => Set (Size (Px (18.0))),
          Flex_Shrink => Set (0.0), Background_Color => Set_Bg (RGB (38, 50, 67)),
          Border_Radius => Set (Radius (Px (3.0))), others => <>)).Build);
      Add_Child (+Progress_Track, +Progress_Fill);
      Show_Progress;
      Output := Adi.Widget.Text_Editor.Create_Handle;
      Adi.Widget.Text_Editor.Set_Read_Only (Output);
      Adi.Widget.Text_Editor.Set_Context_Menu_Part_Styles (Output, Popup_Menu_Styles);
      Adi.Widget.Text_Editor.Set_Context_Menu_Item_Part_Styles
        (Output, Menu_Item_Styles (Highlight_Selection => False));
      Set_Part_Style (+Output, Main_Part, Style.Base
        ((Height => Set (Size (Px (240.0))), Overflow_Y => Set (Overflow_Auto),
          Background_Color => Set_Bg (RGB (12, 17, 24)), others => <>)).Build);
      Set_Part_Style (+Output, Text_Part, Style.Base (Text_Style).Build);
      Style_Scrollbar (+Output, Highlight_Interactions => False);
      Add_Child (+Content, +Output);
      Add_Child (+Content, +Progress_Label);
      Add_Child (+Content, +Progress_Track);
      Dialogs.Set_Content (Dialog, +Content);
      Connect_Frame (W, Poll'Access);
   end Build;
end Editor_Export;
